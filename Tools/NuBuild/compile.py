"""Building the action list: compile each stage, and pack it into a resource.

One action per (shader, technique, stage). Each action is a whole chain —
fxc, then (X360) xsd, then the nushaders packer — so a slow shader's pack
overlaps a fast shader's compile instead of waiting on a phase barrier.

Shared techniques are built ONCE, from the manifest's canonical source. The
PowerShell bulk build compiled every copy and wrote the same resource id for
each, so the output depended on directory iteration order; see manifest.py.

Intermediates land in Build/Output/<platform>/obj/<variant>/ rather than a temp
directory that is deleted on exit. They are small, `clean` removes them, and
having the actual .dxbc to hand is most of the debugging when a pack goes wrong.

BPR packing policy. A stage that replaces a shipped resource is compared with
that shipped shader by `pack-bpr --stock-primary-dir` (Reference/BPR/SHADERS):
an identical interface reuses the stock primary; moved $Globals offsets get a
generated one; a new or moved slot, changed stage I/O, or a variable the shipped
shader never read fails the stage, because no primary makes the engine supply
it. Either way <stage>.pack.log records the differences, which double as the
porting to-do. `--generate` skips the comparison; unmatched stages (no resource
id) always generate.
"""

import os

from . import cache, context, fx, graph, manifest, proc, targets, toolchain


def _resolve_compiler(platform):
    if platform.compiler == "xdk":
        return toolchain.require(toolchain.xdk_fxc(), "Xbox 360 XDK fxc.exe")
    return toolchain.require(toolchain.pc_fxc(), "Windows SDK fxc.exe")


def _tool_map(platform, packing):
    tools = {"fxc": _resolve_compiler(platform)}
    if packing and platform.mode == "resource":
        tools["nushaders"] = toolchain.require(toolchain.nushaders())
        if platform.name == "x360":
            tools["xsd"] = toolchain.require(toolchain.xdk_xsd(), "Xbox 360 XDK xsd.exe")
    return tools


def _fxc_argv(fxc, platform, target, entry, defines, out_path, source):
    argv = [fxc, "/T", target]
    if entry:
        argv += ["/E", entry]
    argv += ["/I", context.INCLUDE_DIR, "/nologo"]
    argv += list(platform.extra_args)
    for d in defines:
        argv += ["/D", d]
    argv += ["/Fo", out_path, source]
    return argv


def _compile(argv, label):
    done = proc.run(argv, check=False)
    if done.returncode != 0:
        text = ((done.stderr or "") + (done.stdout or "")).strip()
        lines = [ln for ln in text.splitlines() if "error" in ln.lower()][:3]
        raise proc.StepError(
            "fxc failed for %s\n%s" % (label, "\n".join(lines) or text[:400])
        )


def _run_xsd(xsd, blob_path):
    """Disassemble Xenos constants to text; pack-x360 --mode generate needs it.

    xsd writes to stdout, so we capture and persist it exactly as
    build_shader_360.ps1 did.
    """
    out_path = blob_path + ".xsd.txt"
    done = proc.run([xsd, blob_path], check=False)
    if done.returncode != 0 and not (done.stdout or "").strip():
        raise proc.StepError("xsd failed for %s: %s"
                             % (context.rel(blob_path), (done.stderr or "").strip()[:300]))
    if not proc.DRY_RUN:
        with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(done.stdout or "")
    return out_path


def _pack_argv(platform, tools, blob, xsd_txt, out_dir, name, stock_primary_dir):
    if platform.name == "x360":
        return [tools["nushaders"], "pack-x360", "--mode", "generate",
                "--input", blob, "--xsd", xsd_txt,
                "--out-dir", out_dir, "--name", name, "--force"]
    argv = [tools["nushaders"], "pack-bpr", "--input", blob,
            "--out-dir", out_dir, "--name", name, "--force"]
    if stock_primary_dir:
        argv += ["--stock-primary-dir", stock_primary_dir]
    return argv


class _Job(object):
    """One stage of one technique: what to compile, and where it lands."""

    def __init__(self, fx_path, fx_name, technique, stage, entry, resource_id, shared_name=None):
        self.fx_path = fx_path
        self.fx_name = fx_name
        self.technique = technique
        self.stage = stage
        self.entry = entry
        self.resource_id = resource_id
        self.shared_name = shared_name

    @property
    def slug(self):
        who = self.shared_name or "%s.%s" % (self.fx_name, self.technique)
        return "%s.%s" % (who, self.stage)

    @property
    def label(self):
        target = self.resource_id or "unmatched"
        return "%-58s %s" % (self.slug, target)


def _jobs_from_manifest(data, shaders_dir, name_filter, technique_filter):
    """Every stage the manifest says exists, filtered, shared ones collapsed."""
    import fnmatch

    jobs = []

    def want(fx_name, technique):
        if name_filter and not fnmatch.fnmatch(fx_name + ".fx", name_filter):
            return False
        if technique_filter and technique != technique_filter:
            return False
        return True

    for entry in data["targets"]:
        if not want(entry["fx"], entry["technique"]):
            continue
        path = os.path.join(shaders_dir, entry["fx"] + ".fx")
        if not os.path.isfile(path):
            continue
        for stage in ("vs", "ps"):
            point = entry.get(stage + "_entry")
            if not point:
                continue
            jobs.append(_Job(path, entry["fx"], entry["technique"], stage,
                             point, entry.get(stage)))

    for entry in data["shared"]:
        canonical = entry["canonical"]
        if not want(canonical, entry["technique"]):
            continue
        path = os.path.join(shaders_dir, canonical + ".fx")
        if not os.path.isfile(path):
            continue
        for stage in ("vs", "ps"):
            point = entry.get(stage + "_entry")
            if not point:
                continue
            jobs.append(_Job(path, canonical, entry["technique"], stage,
                             point, entry.get(stage), shared_name=entry["shared_name"]))

    return jobs


def _reference_listing(res_id):
    """Extracted disassembly of the shipped shader this stage replaces, if `reference extract` has run."""
    import glob

    hits = glob.glob(os.path.join(context.BPR_EXTRACTED, "*.%s.asm" % res_id.upper()))
    return context.rel(hits[0]) if hits else None


def _make_resource_action(job, platform, variant_obj, defines, tools, obj_dir, packing,
                          stock_primary_dir):
    target = platform.vs_target if job.stage == "vs" else platform.ps_target
    # Only a stage that replaces a shipped resource has a stock primary to prove reuse against.
    if not job.resource_id:
        stock_primary_dir = None
    suffix = ".bin" if platform.name == "x360" else ".dxbc"
    blob = os.path.join(obj_dir, job.slug + suffix)

    if job.resource_id:
        # Uppercase to match the bundle's own convention (00433B5E_primary.dat).
        # .debug.xml stores ids lowercase and the manifest keeps them that way;
        # only the filename is uppercased, exactly as the PowerShell packers did.
        out_dir, out_name = platform.spb_dir, job.resource_id.upper()
    else:
        out_dir, out_name = platform.unmatched_dir, job.slug.replace(".", "_")

    if packing:
        outputs = [os.path.join(out_dir, out_name + "_primary.dat"),
                   os.path.join(out_dir, out_name + "_secondary.dat")]
    else:
        outputs = [blob]

    key = cache.compute_key(
        source=job.fx_path,
        includes=fx.scan_includes(job.fx_path, [context.INCLUDE_DIR]),
        defines=defines,
        target=target,
        entry=job.entry,
        tools=tools,
        extra=(platform.name, variant_obj.name, out_name,
               "pack" if packing else "nopack",
               "stock:%s" % (stock_primary_dir or ""))
              + tuple(cache.file_digest(os.path.join(stock_primary_dir, out_name + half))
                      for half in ("_primary.dat", "_secondary.dat") if stock_primary_dir and packing),
    )

    def run(_scratch):
        proc.ensure_dir(obj_dir)
        _compile(
            _fxc_argv(tools["fxc"], platform, target, job.entry, defines, blob, job.fx_path),
            job.slug,
        )
        if not packing:
            return
        proc.ensure_dir(out_dir)
        xsd_txt = _run_xsd(tools["xsd"], blob) if platform.name == "x360" else None
        argv = _pack_argv(platform, tools, blob, xsd_txt, out_dir, out_name, stock_primary_dir)
        done = proc.run(argv, check=False)
        # Kept on success too: for BPR it records which packing policy was chosen and why.
        text = ((done.stderr or "") + (done.stdout or "")).strip("\r\n")
        log = blob + ".pack.log"
        if not proc.DRY_RUN:
            with open(log, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(text + "\n")
        if done.returncode != 0:
            fix = "full report: %s" % context.rel(log)
            if stock_primary_dir and platform.name == "bpr":
                ref = _reference_listing(job.resource_id)
                fix += "; shipped shader: %s" % (ref or "run `nushaders.py reference extract` for its disassembly")
            raise proc.StepError("pack failed for %s: %s" % (job.slug, text), fix=fix)

    return graph.Action(id=job.slug + "|" + variant_obj.name, label=job.label,
                        key=key, outputs=outputs, run=run)


def _make_effect_action(path, platform, variant_obj, defines, tools, out_dir):
    name = fx.base_name(path)
    out_path = os.path.join(out_dir, name + ".fxo")
    key = cache.compute_key(
        source=path,
        includes=fx.scan_includes(path, [context.INCLUDE_DIR]),
        defines=defines,
        target=platform.effect_target,
        entry=None,
        tools=tools,
        extra=(platform.name, variant_obj.name, "effect"),
    )

    def run(_scratch):
        proc.ensure_dir(out_dir)
        _compile(
            _fxc_argv(tools["fxc"], platform, platform.effect_target, None,
                      defines, out_path, path),
            name,
        )

    return graph.Action(id="effect|%s|%s" % (name, variant_obj.name),
                        label="%-58s %s" % (name, variant_obj.name),
                        key=key, outputs=[out_path], run=run)


def build(platform_name, name_filter=None, technique=None, variant=None, extra_defines=(),
          force=False, jobs=None, no_pack=False, stock_primary_dir=None, version="Breaker",
          effects=False, all_variants=False, generate=False):
    platform = targets.get(platform_name)
    effect_mode = effects or platform.mode == "effect"

    if effect_mode and not platform.effect_target:
        raise proc.StepError(
            "%s has no effect profile" % platform.name,
            fix="SM5 has no fx_ target; effect compilation is DX9-only (x360, pc-tub)",
        )

    if all_variants:
        variant_list = list(platform.variants)
    else:
        variant_list = [targets.variant(platform, variant)]

    packing = not no_pack and not effect_mode and platform.mode == "resource"
    if packing and platform.name == "bpr":
        stock_primary_dir = _bpr_stock_dir(stock_primary_dir, generate)
    tools = _tool_map(platform, packing)
    store = cache.Cache(platform.name)

    actions = []
    for variant_obj in variant_list:
        defines = targets.defines_for(platform, variant_obj, extra_defines)
        obj_dir = os.path.join(platform.out_root, "obj", variant_obj.name)

        if effect_mode:
            # Whole-.fx compile check across the variant matrix. Nothing consumes
            # the .fxo; this is what compile_xbox360.ps1 and compile_pc_tub.ps1 did.
            paths = fx.shader_files(context.SHADERS_DIR, name_filter or "*.fx")
            out_dir = os.path.join(platform.out_root, variant_obj.name)
            actions += [_make_effect_action(p, platform, variant_obj, defines, tools, out_dir)
                        for p in paths]
        else:
            data = manifest.load(platform.name)
            job_list = _jobs_from_manifest(data, context.SHADERS_DIR, name_filter, technique)
            actions += [
                _make_resource_action(j, platform, variant_obj, defines, tools, obj_dir,
                                      packing, stock_primary_dir)
                for j in job_list
            ]

    if not actions:
        proc.warn("nothing to build (filter matched no shaders)")
        return context.EXIT_OK

    kind = "effects" if effect_mode else "stages"
    names = ", ".join(v.name for v in variant_list)
    proc.step("build %s [%s]: %d %s" % (platform.name, names, len(actions), kind))
    if len(variant_list) == 1:
        proc.info("defines: %s"
                  % (", ".join(targets.defines_for(platform, variant_list[0], extra_defines))
                     or "(none)"))
    if not packing and not effect_mode:
        proc.info("--no-pack: stopping after compile")
    elif packing and platform.name == "bpr":
        proc.info("primaries: %s" % ("checked against %s (identical: stock reused; layout moved: "
                                     "generated; contract broken: refused)"
                                     % context.rel(stock_primary_dir) if stock_primary_dir
                                     else "generated from reflection, not checked against stock (--generate)"))

    stats = graph.run_actions(actions, store, jobs=jobs, force=force)
    store.save()
    return graph.report(stats, len(actions))


def _bpr_stock_dir(explicit, generate):
    """Where BPR's shipped pairs are, or None when the user asked for generated primaries."""
    if generate:
        if explicit:
            raise proc.StepError("--generate and --stock-primary-dir contradict each other",
                                 fix="pick one packing policy")
        return None
    path = explicit or context.BPR_SPB_REF
    if not os.path.isdir(path):
        raise proc.StepError(
            "no stock ShaderProgramBuffer pairs at %s to verify reuse against" % context.rel(path),
            code=context.EXIT_SKIP,
            fix='nushaders.py reference import "<install>/SHADERS.BNDL", or pass --generate to '
                "build every primary from reflection instead",
        )
    return path


def clean(platform_name=None):
    names = [platform_name] if platform_name else list(targets.BUILDABLE)
    for name in names:
        platform = targets.BY_NAME[name]
        if platform.mode == "unimplemented":
            continue
        proc.step("clean %s" % name)
        store = cache.Cache(name)
        removed = 0
        for path in store.outputs():
            if os.path.exists(path) and not proc.DRY_RUN:
                try:
                    os.remove(path)
                    removed += 1
                except OSError:
                    pass
        proc.remove_tree(platform.out_root)
        store.clear()
        store.save()
        cache_path = os.path.join(context.CACHE_DIR, name + ".json")
        if os.path.exists(cache_path) and not proc.DRY_RUN:
            os.remove(cache_path)
        proc.info("removed %d recorded outputs and %s"
                  % (removed, context.rel(platform.out_root)))
    return context.EXIT_OK
