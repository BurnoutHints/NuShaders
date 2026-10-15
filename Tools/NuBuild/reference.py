"""First-time setup: getting the stock shader bundles into Reference/.

A fresh clone does not have everything the build needs. The Remastered corpus is
committed, but none of the Xbox 360 ones are — the repo carries only empty
`place_*_shader_bundle_here` marker files where they belong. Without them,
`build x360`, `manifest regen --platform x360` and `verify x360` have nothing to
read, because the resource-id map is derived from the bundle's own .debug.xml.

Rather than telling people to run YAP by hand and land the output in exactly the
right directory, `reference import` takes a .bndl/.BUNDLE, unpacks it, works out
which platform it is from its .meta.yaml, and puts it where the build looks.

    nushaders.py reference status
    nushaders.py reference import "D:/dumps/SHADERS.bndl" --version Breaker
    nushaders.py reference extract

Supplying the bundles is still the user's job: they come from a game install or
a devkit, and are not ours to distribute.

`reference extract` turns the imported BPR corpus into evidence you can read:
every ShaderProgramBuffer's exact DXBC, its fxc disassembly, an optional
decompile, and Reference/BPR/Extracted/manifest.json tying each one to its
resource id, .debug.xml name, primary/secondary pair, and the source technique
that rebuilds it. Validation lives in `nushaders extract-bpr` (C#), which owns
the format; this side only names, writes and runs tools.
"""

import hashlib
import json
import os
import re
import shutil
from collections import Counter, defaultdict, namedtuple

from . import context, proc, toolchain

# platform: as used by targets/config. version: X360 game build, None for BPR.
Corpus = namedtuple("Corpus", "platform version path label needed_by")

# Marker files the repo ships so the directories exist and are self-describing.
MARKERS = {
    "bpr": "place_BPR_shader_bundle_here",
    "Breaker": "place_360_breaker_shader_bundle_here",
    "1.6": "place_360_1.6_shader_bundle_here",
    "1.8": "place_360_1.8_shader_bundle_here",
}


def corpora():
    out = [Corpus("bpr", None, context.BPR_REF,
                  "BPR (Remastered PC)",
                  "build bpr, verify bpr, manifest regen --platform bpr")]
    for version in context.X360_VERSIONS:
        out.append(Corpus("x360", version, context.x360_ref(version),
                          "X360 %s" % version,
                          "verify x360" if version != "Breaker"
                          else "build x360, verify x360, manifest regen --platform x360"))
    return tuple(out)


def _state(corpus):
    """(present, detail) for one corpus."""
    if not os.path.isdir(corpus.path):
        return False, "directory missing"
    spb = os.path.join(corpus.path, "ShaderProgramBuffer")
    if not os.path.isdir(spb):
        return False, "no ShaderProgramBuffer/"
    pairs = len([n for n in os.listdir(spb) if n.endswith("_primary.dat")])
    has_debug = os.path.isfile(os.path.join(corpus.path, ".debug.xml"))
    if pairs == 0:
        return False, "no resources unpacked"
    detail = "%d shader resources" % pairs
    if not has_debug:
        # The build can still verify, but not derive ids.
        detail += ", NO .debug.xml (manifest regen will not work)"
    return True, detail


def status():
    proc.step("reference status")
    missing = []
    for corpus in corpora():
        present, detail = _state(corpus)
        proc.info("%-4s %-16s %s" % ("ok" if present else "MISS", corpus.label, detail))
        if not present:
            missing.append(corpus)

    if not missing:
        proc.info("")
        proc.info("every reference corpus is in place")
        return context.EXIT_OK

    proc.info("")
    for corpus in missing:
        proc.info("%s is needed by: %s" % (corpus.label, corpus.needed_by))
    proc.fix('unpack one with: nushaders.py reference import <bundle>%s'
             % (" --version <ver>" if any(c.platform == "x360" for c in missing) else ""))
    # Missing corpora are an environment gap, not a failure of this command.
    return context.EXIT_SKIP


def _destination(platform, version):
    if platform == "bpr":
        return context.BPR_REF
    return context.x360_ref(version)


def _normalise_newlines(directory):
    """Convert YAP's CRLF text output to LF. Returns how many files changed.

    YAP writes .debug.xml and the *_imports.yaml sidecars with CRLF, but the
    committed corpus is LF and ImportsYAML.ToYAML() emits LF. Without this,
    importing a bundle silently reintroduces the exact mismatch .gitattributes
    exists to prevent: 86 round-trip tests fail and `git status` shows hundreds
    of line-ending-only modifications, with nothing pointing at the import as
    the cause.

    Binary resources are left alone — a .dat containing 0x0D0A is data, not a
    line ending, and rewriting it would corrupt the corpus.
    """
    changed = 0
    for root, _dirs, files in os.walk(directory):
        for name in files:
            path = os.path.join(root, name)
            try:
                data = open(path, "rb").read()
            except OSError:
                continue
            if b"\x00" in data[:8192] or b"\r\n" not in data:
                continue
            with open(path, "wb") as handle:
                handle.write(data.replace(b"\r\n", b"\n"))
            changed += 1
    return changed


def _describe(directory):
    """Resource-type dirs and counts, for the post-import report."""
    rows = []
    for name in sorted(os.listdir(directory)):
        sub = os.path.join(directory, name)
        if os.path.isdir(sub):
            rows.append((name, len(os.listdir(sub))))
    return rows


def import_bundle(bundle_path, version=None, force=False):
    from . import bundle as bundle_mod

    yap = toolchain.require(toolchain.yap())
    bundle_path = os.path.abspath(os.path.expanduser(bundle_path))
    if not os.path.isfile(bundle_path):
        raise proc.StepError("no such bundle: %s" % bundle_path,
                             fix="point this at a SHADERS.bndl / SHADERS.BUNDLE")

    proc.step("reference import %s" % os.path.basename(bundle_path))

    # Unpack somewhere disposable first. We cannot know which corpus this is
    # until we have read its .meta.yaml, and unpacking straight into a guessed
    # destination would corrupt whatever was already there if the guess is wrong.
    scratch = os.path.join(context.CACHE_DIR, "reference-import")
    proc.remove_tree(scratch)
    proc.ensure_dir(scratch)
    proc.run([yap, "e", bundle_path, scratch])

    meta = bundle_mod.meta_platform(scratch)
    platform = {1: "bpr", 2: "x360"}.get(meta)
    if platform is None:
        raise proc.StepError(
            "could not read a platform from the bundle's .meta.yaml (got %r)" % meta,
            fix="expected platform 1 (BPR) or 2 (X360); is this a SHADERS bundle?",
        )
    proc.info("bundle reports platform %d (%s)" % (meta, platform))

    if platform == "x360":
        if not version:
            raise proc.StepError(
                "this is an Xbox 360 bundle, so which game build is it?",
                fix="pass --version %s  (they cannot be told apart from content)"
                    % "|".join(context.X360_VERSIONS),
            )
    elif version:
        proc.warn("--version is meaningless for a BPR bundle; ignoring it")
        version = None

    destination = _destination(platform, version)
    present, detail = _state(Corpus(platform, version, destination, "", ""))
    if present and not force:
        raise proc.StepError(
            "%s already holds %s" % (context.rel(destination), detail),
            fix="pass --force to replace it",
        )

    if not proc.DRY_RUN:
        # Keep the marker file: it is what documents the directory in a clone
        # that has not imported anything yet.
        marker = MARKERS.get(version or platform)
        parent = os.path.dirname(destination)
        if os.path.isdir(destination):
            shutil.rmtree(destination)
        proc.ensure_dir(parent)
        shutil.move(scratch, destination)
        if marker and not os.path.exists(os.path.join(parent, marker)):
            open(os.path.join(parent, marker), "a").close()

    proc.info("unpacked -> %s" % context.rel(destination))
    if not proc.DRY_RUN:
        normalised = _normalise_newlines(destination)
        if normalised:
            proc.info("normalised %d text file(s) to LF" % normalised)
        for name, count in _describe(destination):
            proc.info("  %-24s %d" % (name, count))
        if not os.path.isfile(os.path.join(destination, ".debug.xml")):
            proc.warn("this bundle has no .debug.xml, so `manifest regen` cannot "
                      "derive resource ids from it")
        else:
            proc.info("")
            proc.fix("next: nushaders.py manifest regen --platform %s" % platform)
    return context.EXIT_OK


# --- extract: the BPR shader programs as readable evidence -------------------


# gamedb://burnout5/<dir>/<Fx>.fx.Shader?ID=<n>_<Technique>_<Stage>, or a bare shared "<Name>_<Stage>".
# Wider than manifest.py's pattern on purpose: the bundle also ships Playground/ shaders.
_PROGRAM_NAME_RE = re.compile(
    r"^(?:gamedb://burnout5/(?P<path>[^?]+?)\.fx\.Shader\?ID=\d+_)?(?P<tech>[^/?]+?)_(?P<stage>VertexShader|PixelShader)$")


def _family(name, res_id):
    """(readable file stem, family fields) from a .debug.xml name. The id keeps stems unique."""
    m = _PROGRAM_NAME_RE.match(name or "")
    if not m:
        stem, fields = name or "unresolved", {}
    else:
        stage = {"VertexShader": "vs", "PixelShader": "ps"}[m.group("stage")]
        if m.group("path"):
            fx_name = m.group("path").rsplit("/", 1)[-1]
            fields = {"fx": fx_name, "fx_path": m.group("path") + ".fx", "technique": m.group("tech"), "stage": stage}
            stem = "%s.%s.%s" % (fx_name, m.group("tech"), stage)
        else:
            fields = {"shared_name": m.group("tech"), "stage": stage}
            stem = "%s.%s" % (m.group("tech"), stage)
    return "%s.%s" % (re.sub(r"[^\w.-]", "_", stem), res_id.upper()), fields


def _source_map():
    """resource id -> the technique in Source/ that rebuilds it, from the committed bpr manifest."""
    from . import manifest

    try:
        data = manifest.load("bpr")
    except proc.StepError:
        return {}

    def where(fx_name):
        return context.rel(os.path.join(context.SHADERS_DIR, fx_name + ".fx"))

    out = {}
    for t in data["targets"]:
        for stage in ("vs", "ps"):
            if t.get(stage):
                out[t[stage]] = {"source": where(t["fx"]), "technique": t["technique"],
                                 "entry": t.get(stage + "_entry"), "mapping": "manifest"}
    for s in data["shared"]:
        for stage in ("vs", "ps"):
            if s.get(stage):
                out[s[stage]] = {
                    "source": where(s["canonical"]), "technique": s["technique"],
                    "entry": s.get(stage + "_entry"), "shared_name": s["shared_name"],
                    "mapping": "manifest, canonical of %d copies%s"
                               % (len(s["sources"]), " that disagree" if s.get("conflicts") else ""),
                }
    return out


def _disassemble(fxc, dxbc_path, asm_path):
    if not fxc:
        return {"status": "not-run", "reason": fxc.what}
    done = proc.run([fxc, "/nologo", "/dumpbin", "/Fc", asm_path, dxbc_path], check=False)
    if done.returncode != 0 or not os.path.isfile(asm_path):
        return {"status": "failed", "reason": ((done.stderr or "") + (done.stdout or "")).strip()[:300]}
    return {"status": "ok", "path": context.rel(asm_path)}


def _decompile(template, dxbc_path, hlsl_path):
    """Run the user's NUSHADERS_DECOMPILER template; keep its log whether it worked or not."""
    import shlex

    if not template:
        return {"status": "not-run", "reason": "no decompiler configured"}
    argv = [tok.strip('"').replace("{in}", dxbc_path).replace("{out}", hlsl_path)
            for tok in shlex.split(template, posix=False)]
    log_path = os.path.splitext(hlsl_path)[0] + ".decompile.log"
    try:
        done = proc.run(argv, check=False, timeout=300)
        log, code = (done.stdout or "") + (done.stderr or ""), done.returncode
    except proc.StepError as err:
        log, code = err.message, -1
    with open(log_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(log)
    ok = code == 0 and os.path.isfile(hlsl_path)
    result = {"status": "ok" if ok else "failed", "log": context.rel(log_path)}
    if ok:
        result["path"] = context.rel(hlsl_path)
    return result


def _file(fact):
    if not fact:
        return None
    return {"path": context.rel(fact["path"]), "length": fact["length"], "sha256": fact["sha256"]}


def extract(jobs=None):
    from concurrent.futures import ThreadPoolExecutor

    from . import graph, manifest

    nushaders = toolchain.require(toolchain.nushaders())
    if not os.path.isdir(context.BPR_SPB_REF):
        raise proc.StepError(
            "no BPR corpus at %s" % context.rel(context.BPR_SPB_REF),
            code=context.EXIT_SKIP,
            fix='unpack the stock bundle first: nushaders.py reference import "<install>/SHADERS.BNDL"',
        )
    fxc = toolchain.pc_fxc()
    decompiler = toolchain.decompiler()
    out = context.BPR_EXTRACTED

    proc.step("reference extract bpr")
    done = proc.run([nushaders, "extract-bpr", "--spb-dir", context.BPR_SPB_REF], read_only=True)
    report = json.loads(done.stdout)
    records = report["resources"]
    if proc.DRY_RUN:
        proc.info("DRY-RUN: would write %d resources to %s" % (len(records), context.rel(out)))
        return context.EXIT_OK

    # Regenerated whole every run, so a resource that left the corpus cannot linger here.
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)

    sources = _source_map()
    entries = []
    by_payload = defaultdict(list)
    for rec in records:
        res_id = rec["id"].lower()
        stem, family = _family(rec.get("debug_name"), rec["id"])
        name = rec.get("debug_name")
        entry = {
            "id": res_id,
            "identity": dict(family, name=name, type=rec.get("debug_type"), aliases=[],
                             name_status="unresolved" if not name
                             else "resolved" if rec.get("name_matches_id") else "id-mismatch"),
            "pair": {"primary": _file(rec.get("primary")), "secondary": _file(rec.get("secondary"))},
            "evidence": {"dxbc": None, "profile": None, "reflection": rec.get("reflection"),
                         "disassembly": {"status": "not-run"}, "decompiled": {"status": "not-run"}},
            "reconstruction": sources.get(res_id),
            "validation": {"structural": "fail" if rec["errors"] else "pass",
                           "errors": rec["errors"],
                           "stock_round_trip": rec["stock_round_trip"],
                           "primary_describes_dxbc": rec["primary_describes_dxbc"],
                           "notes": rec["notes"]},
        }
        entries.append(entry)
        if rec["errors"] or not rec.get("dxbc_sha256"):
            continue  # never hand a payload that failed validation to fxc or a decompiler

        with open(rec["secondary"]["path"], "rb") as handle:
            dxbc = handle.read(rec["dxbc_length"])
        if hashlib.sha256(dxbc).hexdigest() != rec["dxbc_sha256"]:
            raise proc.StepError("%s changed while extracting" % rec["secondary"]["path"],
                                 fix="re-run once nothing is writing to the corpus")
        path = os.path.join(out, stem + ".dxbc")
        with open(path, "wb") as handle:
            handle.write(dxbc)
        entry["evidence"]["dxbc"] = {"path": context.rel(path), "length": len(dxbc),
                                     "sha256": rec["dxbc_sha256"]}
        entry["evidence"]["profile"] = rec["reflection"]["profile"]
        by_payload[rec["dxbc_sha256"]].append((stem, entry))

    # Identical payloads are disassembled/decompiled once, then copied under every alias's name so the
    # folder reads by shader; every alias keeps its own entry and pair.
    def per_payload(group):
        base = os.path.join(out, group[0][0])
        asm = _disassemble(fxc, base + ".dxbc", base + ".asm")
        hlsl = _decompile(decompiler, base + ".dxbc", base + ".hlsl")
        ids = [e["id"] for _stem, e in group]
        for stem, e in group:
            e["evidence"]["disassembly"] = dict(asm)
            e["evidence"]["decompiled"] = dict(hlsl)
            e["identity"]["aliases"] = [i for i in ids if i != e["id"]]
            for kind, ext in (("disassembly", ".asm"), ("decompiled", ".hlsl")):
                if stem != group[0][0] and e["evidence"][kind].get("path"):
                    shutil.copyfile(base + ext, os.path.join(out, stem + ext))
                    e["evidence"][kind]["path"] = context.rel(os.path.join(out, stem + ext))

    with ThreadPoolExecutor(max_workers=jobs or graph.default_jobs()) as pool:
        list(pool.map(per_payload, by_payload.values()))

    failed = [e for e in entries if e["validation"]["structural"] == "fail"]
    named = Counter(e["identity"]["name_status"] for e in entries)
    unmapped = [e for e in entries if not e["reconstruction"]]
    asm_status = Counter(e["evidence"]["disassembly"]["status"] for e in entries)
    hlsl_status = Counter(e["evidence"]["decompiled"]["status"] for e in entries)
    summary = {
        "resources": len(entries),
        "unique_dxbc": len(by_payload),
        "structural_failures": len(failed),
        "stock_round_trip": dict(Counter(e["validation"]["stock_round_trip"] for e in entries)),
        "primary_describes_dxbc": dict(Counter(e["validation"]["primary_describes_dxbc"] for e in entries)),
        "names": dict(named),
        "unmapped_to_source": len(unmapped),
        "disassembly": dict(asm_status),
        "decompiled": dict(hlsl_status),
    }
    doc = {
        "schema": 1,
        "platform": "bpr",
        "generated_from": {"spb_dir": context.rel(report["spb_dir"]),
                           "debug_xml": context.rel(report["debug_xml"]) if report.get("debug_xml") else None,
                           "source_map": context.rel(manifest.manifest_path("bpr"))},
        "hash_algorithm": "sha256 over the exact, unpadded DXBC",
        "decompiler": decompiler or None,
        "summary": summary,
        "resources": entries,
    }
    manifest_file = os.path.join(out, "manifest.json")
    with open(manifest_file, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(manifest.dumps(doc))

    proc.info("%d resources, %d unique DXBC payloads -> %s"
              % (len(entries), len(by_payload), context.rel(out)))
    proc.info("validation: %d pass, %d fail   stock round-trip %s   primary describes DXBC %s"
              % (len(entries) - len(failed), len(failed),
                 summary["stock_round_trip"], summary["primary_describes_dxbc"]))
    proc.info("names: %s" % dict(named))
    proc.info("source: %d mapped to a technique, %d with no source in the tree"
              % (len(entries) - len(unmapped), len(unmapped)))
    proc.info("disassembly: %s   decompile: %s" % (dict(asm_status), dict(hlsl_status)))
    if not fxc:
        proc.warn("no fxc, so no disassembly")
        proc.fix(fxc.fix)
    if not decompiler:
        proc.warn("decompile not run: no decompiler configured")
        proc.fix(decompiler.fix)
    proc.info("wrote %s" % context.rel(manifest_file))

    if failed:
        for e in failed[:10]:
            proc.info("  FAIL %s: %s" % (e["id"], "; ".join(e["validation"]["errors"])))
        raise proc.StepError(
            "%d of %d resources failed validation" % (len(failed), len(entries)),
            fix="see validation.errors in %s; the outputs for the rest are usable"
                % context.rel(manifest_file),
        )
    return context.EXIT_OK
