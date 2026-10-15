"""Verb tree, global flags, and the one place StepError is caught.

Handlers are imported lazily inside their branch so a contributor running
`doctor bpr` never imports the deploy or Xbox 360 code paths — an import error
in a module they will never touch must not break their verb.
"""

import argparse
import sys
import time

from . import context, proc

_EPILOG = """\
common flows:
  nushaders.py reference status            fresh clone: which stock bundles you still need
  nushaders.py doctor all                  what is installed, what is missing, how to fix it
  nushaders.py tools build-cli             build nushaders.exe (NuShaders.CLI)
  nushaders.py tools test-cli              run the C# format round-trip tests
  nushaders.py verify bpr                  prove the packer reproduces shipped bytes
  nushaders.py config new                  set this machine up for deploying
  nushaders.py deploy bpr                  build -> bundle -> copy into the install -> launch

exit codes:
  0 ok    1 failure    2 environmental skip (a tool or reference corpus is missing)
"""


def _add_global_flags(parser):
    """Re-registered on every subparser.

    SUPPRESS matters: without it a subparser's default would overwrite a value
    the user already gave at the top level, so `nushaders.py --dry-run deploy bpr`
    would silently run for real.
    """
    parser.add_argument("--dry-run", action="store_true", default=argparse.SUPPRESS,
                        help="print what would run without changing anything")
    parser.add_argument("-v", "--verbose", action="store_true", default=argparse.SUPPRESS,
                        help="show full command lines")


def _sub(parent, name, help_text):
    p = parent.add_parser(name, help=help_text)
    _add_global_flags(p)
    return p


def build_parser():
    parser = argparse.ArgumentParser(
        prog="nushaders.py",
        description="Burnout Paradise shader build system.",
        epilog=_EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    _add_global_flags(parser)
    verbs = parser.add_subparsers(dest="verb", metavar="VERB")

    # --- doctor --------------------------------------------------------------
    from . import toolchain

    d = _sub(verbs, "doctor", "check the toolchain and reference corpora")
    d.add_argument("role", nargs="?", default="all",
                   choices=("all",) + toolchain.ROLES,
                   help="which role to check (default: all)")
    d.set_defaults(_handler=_handle_doctor)

    # --- build / clean -------------------------------------------------------
    from . import targets

    b = _sub(verbs, "build", "compile (and pack) shaders for a platform")
    b.add_argument("platform", choices=targets.NAMES)
    b.add_argument("--filter", metavar="GLOB", help='e.g. "Vehicle_*.fx"')
    b.add_argument("--technique", metavar="NAME", help="build only this technique")
    b.add_argument("--variant", metavar="NAME", help="define set (default: the platform's first)")
    b.add_argument("-D", dest="defines", action="append", default=[], metavar="DEFINE",
                   help="extra preprocessor define; repeatable")
    b.add_argument("--force", action="store_true", help="ignore the cache")
    b.add_argument("-j", dest="jobs", type=int, metavar="N",
                   help="parallel jobs (default: cpu count)")
    b.add_argument("--no-pack", action="store_true", help="stop after compiling")
    b.add_argument("--effects", action="store_true",
                   help="compile whole .fx as effects (fx_2_0) instead of per-stage resources")
    b.add_argument("--all-variants", action="store_true",
                   help="build every variant in the platform's matrix, not just one")
    b.add_argument("--stock-primary-dir", metavar="DIR",
                   help="BPR: where the shipped pairs are (default: Reference/BPR/SHADERS); "
                        "a stock primary is reused only once verified against the rebuilt shader")
    b.add_argument("--generate", action="store_true",
                   help="BPR: build every primary from reflection instead of reusing verified stock ones")
    b.set_defaults(_handler=_handle_build)

    vf = _sub(verbs, "verify", "byte-compare our packer against the shipped resources")
    vf.add_argument("platform", choices=("x360", "bpr"))
    vf.add_argument("--against", metavar="DIR", help="a specific ShaderProgramBuffer dir")
    vf.add_argument("--version", default="Breaker", choices=context.X360_VERSIONS)
    vf.add_argument("-j", dest="jobs", type=int, metavar="N")
    vf.add_argument("--limit", type=int, metavar="N", help="check only the first N pairs")
    vf.add_argument("--generate", action="store_true",
                    help="bpr: build the primary from reflection alone (reports divergence)")
    vf.set_defaults(_handler=_handle_verify)

    c = _sub(verbs, "clean", "remove build outputs and the cache")
    c.add_argument("platform", nargs="?", choices=targets.NAMES)
    c.set_defaults(_handler=_handle_clean)

    # --- reference (first-time setup) ----------------------------------------
    rf = _sub(verbs, "reference", "get the stock shader bundles into Reference/")
    rf_sub = rf.add_subparsers(dest="reference_action", metavar="ACTION")
    rs = rf_sub.add_parser("status", help="which reference corpora are present")
    _add_global_flags(rs)
    ri = rf_sub.add_parser("import", help="unpack a SHADERS bundle into the right place")
    _add_global_flags(ri)
    ri.add_argument("bundle", help="path to a SHADERS.bndl / SHADERS.BUNDLE")
    ri.add_argument("--version", choices=context.X360_VERSIONS,
                    help="which X360 game build this is (required for X360)")
    ri.add_argument("--force", action="store_true", help="replace an existing corpus")
    rx = rf_sub.add_parser("extract", help="BPR: exact DXBC, disassembly and a manifest for every shader program")
    _add_global_flags(rx)
    rx.add_argument("-j", dest="jobs", type=int, metavar="N")
    rf.set_defaults(_handler=_handle_reference)

    # --- bundle / deploy / autotest / config ---------------------------------
    bn = _sub(verbs, "bundle", "extract the stock bundle, inject our resources, repack")
    bn.add_argument("--config", dest="config_name", metavar="NAME")
    bn.add_argument("--out", metavar="PATH", help="write the repacked bundle here")
    bn.set_defaults(_handler=_handle_bundle)

    dp = _sub(verbs, "deploy", "build, bundle, and send to the console or install")
    dp.add_argument("platform", nargs="?", choices=("x360", "bpr"))
    dp.add_argument("--config", dest="config_name", metavar="NAME")
    dp.add_argument("--no-build", action="store_true", help="deploy what is already packed")
    dp.add_argument("--no-bundle", action="store_true", help="reuse the existing new_bundle")
    dp.add_argument("--no-launch", action="store_true", help="do not reboot or start the game")
    dp.add_argument("--restore", action="store_true", help="BPR: put the stock bundle back")
    dp.add_argument("-j", dest="jobs", type=int, metavar="N")
    dp.set_defaults(_handler=_handle_deploy)

    at = _sub(verbs, "autotest", "push Build/autotest to the devkit and reboot the title")
    at.add_argument("--config", dest="config_name", metavar="NAME")
    at.add_argument("--script", metavar="NAME", help="entry script (default: autotest.txt as tracked)")
    at.add_argument("--no-reboot", action="store_true")
    at.set_defaults(_handler=_handle_autotest)

    cf = _sub(verbs, "config", "per-machine deploy configuration")
    cf_sub = cf.add_subparsers(dest="config_action", metavar="ACTION")
    for name, help_text in (
        ("list", "every config in Build/config"),
        ("show", "print this host's config"),
        ("new", "copy example.toml to <hostname>.toml"),
        ("set", "change one value in place"),
        ("discover-ip", "scan the subnet for an XDK debug port"),
        ("validate", "report anything unusable"),
        ("migrate", "convert a legacy repack_and_send.<host>.psd1"),
    ):
        a = cf_sub.add_parser(name, help=help_text)
        _add_global_flags(a)
        a.add_argument("--config", dest="config_name", metavar="NAME")
        if name == "set":
            a.add_argument("key")
            a.add_argument("value")
        if name == "new":
            a.add_argument("--force", action="store_true")
        if name == "migrate":
            a.add_argument("psd1")
            a.add_argument("--force", action="store_true")
        if name == "discover-ip":
            a.add_argument("--subnet", metavar="A.B.C", help="e.g. 192.168.1")
            a.add_argument("--write", action="store_true", help="record a single hit")
    cf.set_defaults(_handler=_handle_config)

    # --- manifest ------------------------------------------------------------
    m = _sub(verbs, "manifest", "generate / inspect / verify the shader<->resource-id map")
    m_sub = m.add_subparsers(dest="manifest_action", metavar="ACTION")
    for name, help_text in (
        ("regen", "re-derive from .debug.xml (+ ResourceDB.json) and write it"),
        ("show", "summarize the committed manifest"),
        ("check", "re-derive and diff against what is committed"),
    ):
        a = m_sub.add_parser(name, help=help_text)
        _add_global_flags(a)
        a.add_argument("--platform", choices=("x360", "bpr"),
                       help="default: both (show requires one)")
        a.add_argument("--version", default="Breaker", choices=context.X360_VERSIONS,
                       help="which X360 corpus to read (default: Breaker)")
        if name == "regen":
            a.add_argument("--reset", action="store_true",
                           help="discard hand-set `canonical` overrides too")
    m.set_defaults(_handler=_handle_manifest)

    # --- tools ---------------------------------------------------------------
    t = _sub(verbs, "tools", "invoke the out-of-scope C#/C++ projects and fetch helpers")
    t_sub = t.add_subparsers(dest="tools_action", metavar="ACTION")
    for name, help_text in (
        ("build-cli", "dotnet build NuShaders.CLI -> nushaders.exe"),
        ("test-cli", "dotnet test the NuShaders solution"),
        ("build-ssrhook", "cmake build the SSRHook proxy DLL"),
        ("fetch-yap", "download + extract YAP into Build/tools/yap"),
    ):
        a = t_sub.add_parser(name, help=help_text)
        _add_global_flags(a)
        if name in ("build-cli", "build-ssrhook"):
            a.add_argument("--config", default="Release", choices=("Release", "Debug"))
    t.set_defaults(_handler=_handle_tools)

    return parser


# --- handlers ----------------------------------------------------------------


def _handle_doctor(args):
    from . import doctor

    return doctor.run(args.role)


def _handle_build(args):
    from . import compile as compile_mod

    return compile_mod.build(
        args.platform,
        name_filter=args.filter,
        technique=args.technique,
        variant=args.variant,
        extra_defines=args.defines,
        force=args.force,
        jobs=args.jobs,
        no_pack=args.no_pack,
        stock_primary_dir=args.stock_primary_dir,
        effects=args.effects,
        all_variants=args.all_variants,
        generate=args.generate,
    )


def _handle_verify(args):
    from . import verify

    return verify.verify(args.platform, against=args.against, version=args.version,
                         jobs=args.jobs, limit=args.limit, generate=args.generate)


def _handle_clean(args):
    from . import compile as compile_mod

    return compile_mod.clean(args.platform)


def _handle_reference(args):
    from . import reference

    action = getattr(args, "reference_action", None)
    if not action:
        raise proc.StepError("reference needs an action",
                             fix="try: nushaders.py reference status")
    if action == "status":
        return reference.status()
    if action == "extract":
        return reference.extract(args.jobs)
    return reference.import_bundle(args.bundle, args.version, args.force)


def _handle_bundle(args):
    from . import bundle, config

    cfg = config.load(args.config_name).require_valid()
    bundle.make(cfg, args.out)
    return context.EXIT_OK


def _handle_deploy(args):
    from . import config, deploy

    if args.restore:
        return deploy.restore_bpr(config.load(args.config_name).require_valid())
    return deploy.deploy(args.platform, name=args.config_name, no_build=args.no_build,
                         no_bundle=args.no_bundle, launch=not args.no_launch,
                         jobs=args.jobs)


def _handle_autotest(args):
    from . import deploy

    return deploy.autotest(name=args.config_name, script=args.script,
                           reboot=not args.no_reboot)


def _handle_config(args):
    from . import config

    action = getattr(args, "config_action", None)
    if not action:
        raise proc.StepError("config needs an action", fix="try: nushaders.py config show")
    name = args.config_name
    if action == "list":
        return config.verb_list()
    if action == "show":
        return config.verb_show(name)
    if action == "new":
        return config.verb_new(name, force=args.force)
    if action == "set":
        return config.verb_set(args.key, args.value, name)
    if action == "discover-ip":
        return config.verb_discover(args.subnet, name, write=args.write)
    if action == "validate":
        return config.verb_validate(name)
    return config.verb_migrate(args.psd1, name, force=args.force)


def _handle_manifest(args):
    from . import manifest

    action = getattr(args, "manifest_action", None)
    if not action:
        raise proc.StepError("manifest needs an action",
                             fix="try: nushaders.py manifest regen")
    if action == "regen":
        return manifest.regen(args.platform, args.version, reset=args.reset)
    if action == "check":
        return manifest.check(args.platform, args.version)
    if not args.platform:
        raise proc.StepError("manifest show needs --platform",
                             fix="try: nushaders.py manifest show --platform bpr")
    return manifest.show(args.platform)


def _handle_tools(args):
    from . import tools

    action = getattr(args, "tools_action", None)
    if not action:
        raise proc.StepError("tools needs an action",
                             fix="try: nushaders.py tools build-cli")
    config = getattr(args, "config", "Release")
    return {
        "build-cli": lambda: tools.build_cli(config),
        "test-cli": tools.test_cli,
        "build-ssrhook": lambda: tools.build_ssrhook(config),
        "fetch-yap": tools.fetch_yap,
    }[action]()


# --- entry -------------------------------------------------------------------


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv)

    if not getattr(args, "verb", None):
        parser.print_help()
        return context.EXIT_OK

    proc.configure(
        dry_run=getattr(args, "dry_run", False),
        verbose=getattr(args, "verbose", False),
    )

    label = args.verb
    for extra in ("role", "platform", "reference_action", "config_action",
              "manifest_action", "tools_action"):
        value = getattr(args, extra, None)
        if value:
            label = "%s %s" % (args.verb, value)
            break

    started = time.time()
    try:
        code = args._handler(args)
    except proc.StepError as err:
        proc.error(err.message)
        if err.fix:
            proc.fix(err.fix)
        code = err.code
    except KeyboardInterrupt:
        proc.error("interrupted")
        code = context.EXIT_FAIL

    code = context.EXIT_OK if code is None else code
    proc.result(label, code, time.time() - started)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
