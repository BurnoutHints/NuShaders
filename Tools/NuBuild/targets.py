"""Platform and variant definitions — the one declarative table.

The PowerShell era hardcoded a different variant matrix in each script:
compile_xbox360.ps1 had seven variants, build_xbox360_resources.ps1 had a single
fixed define set, and compile_pc_bpr.ps1 had another. Nothing reconciled them, so
"the X360 build" meant different things depending on which script you ran.

Two build modes, because the old scripts really were doing two different jobs:

  resource  compile each technique's VS and PS separately (/T vs_3_0, /E VS_Main)
            and pack the result into ShaderProgramBuffer .dat pairs under the
            game's own resource ids. This is what ships.

  effect    compile the whole .fx as an effect (/T fx_2_0) into a .fxo. Nothing
            consumes the .fxo — it is a compile check across the variant matrix,
            which is why it can afford to build seven define sets.

Output paths are deliberately unchanged from the PowerShell layout so existing
extracted-bundle scratch dirs and deploy configs keep working.
"""

import os
from collections import namedtuple

from . import context

Variant = namedtuple("Variant", "name defines")

Platform = namedtuple(
    "Platform",
    "name mode compiler vs_target ps_target effect_target base_defines extra_args "
    "variants out_root spb_dir unmatched_dir packer",
)


def _out(*parts):
    return os.path.join(context.OUTPUT_DIR, *parts)


X360 = Platform(
    name="x360",
    mode="resource",
    compiler="xdk",
    vs_target="vs_3_0",
    ps_target="ps_3_0",
    effect_target="fx_2_0",
    base_defines=("D_PLATFORM_X360",),
    # /Zpr: the Xenos path relies on row-major packing. BPR does not get this —
    # its matrices are declared row_major explicitly in the cbuffer.
    extra_args=("/Zpr",),
    variants=(
        # First entry is the default. These are the defines the shipped
        # Xbox 360 resource build used (build_xbox360_resources.ps1).
        Variant("mrt_aniso", ("D_MRT", "D_OREN_NAYAR", "D_SHADOWMAP_ANISOTROPIC")),
        Variant("base", ()),
        Variant("mrt", ("D_MRT",)),
        Variant("mrt_msaa", ("D_MRT", "D_MSAA_ENABLED")),
        Variant("mrt_msaa_aniso", ("D_MRT", "D_MSAA_ENABLED", "D_SHADOWMAP_ANISOTROPIC")),
        # No D_SOFT_SHADOWS here: soft shadows were never an option on Xbox 360.
        # compile_xbox360.ps1 carried mrt_soft and mrt_msaa_soft anyway, and they
        # failed with X3551 microcode validation on the heaviest pixel shaders
        # every time anyone ran them. A variant that can never go green only
        # teaches people to ignore red output. The define lives on PC_TUB, which
        # is the only target where it compiles.
    ),
    out_root=_out("Xbox360_Resources"),
    spb_dir=_out("Xbox360_Resources", "ShaderProgramBuffer"),
    unmatched_dir=_out("Xbox360_Resources", "Unmatched"),
    packer="pack-x360",
)

BPR = Platform(
    name="bpr",
    mode="resource",
    compiler="pc",
    vs_target="vs_5_0",
    ps_target="ps_5_0",
    effect_target=None,  # SM5 has no effect profile; fx_2_0 is DX9-only
    base_defines=("D_PLATFORM_BPR",),
    # The flags every shipped BPR shader was built with (RDEF flags 0x1108, fxc 10.1):
    # /Gec backwards compatibility (POSITION -> SV_POSITION, loose globals -> $Globals),
    # /Zpr row-major matrices, /Op no preshader. Matching them is what lets the
    # TUB-era source reproduce the shipped interface instead of approximating it.
    extra_args=("/Gec", "/Zpr", "/Op"),
    variants=(Variant("default", ()),),
    out_root=_out("PC_BPR"),
    spb_dir=_out("PC_BPR", "ShaderProgramBuffer"),
    unmatched_dir=_out("PC_BPR", "Unmatched"),
    packer="pack-bpr",
)

PC_TUB = Platform(
    name="pc-tub",
    mode="effect",
    compiler="pc",
    vs_target="vs_3_0",
    ps_target="ps_3_0",
    effect_target="fx_2_0",
    # Neither D_PLATFORM_* define: Platform.fxh falls through to the DX9 SM3 path.
    base_defines=(),
    extra_args=(),
    # D_SOFT_SHADOWS belongs here and nowhere else: Shadow.fxh's BPR branch says
    # explicitly not to define it, and the Xenos compiler rejects it.
    variants=(Variant("base", ()), Variant("soft", ("D_SOFT_SHADOWS",))),
    out_root=_out("PC_TUB"),
    spb_dir=None,
    unmatched_dir=None,
    packer=None,
)

PS3 = Platform(
    name="ps3",
    mode="unimplemented",
    compiler=None,
    vs_target="sce_vp_rsx",
    ps_target="sce_fp_rsx",
    effect_target=None,
    base_defines=("D_PLATFORM_PS3",),
    extra_args=(),
    variants=(),
    out_root=_out("PS3"),
    spb_dir=None,
    unmatched_dir=None,
    packer=None,
)

ALL = (X360, BPR, PC_TUB, PS3)
BY_NAME = {p.name: p for p in ALL}
BUILDABLE = tuple(p.name for p in ALL if p.mode != "unimplemented")
NAMES = tuple(p.name for p in ALL)


def get(name):
    from . import proc

    platform = BY_NAME.get(name)
    if platform is None:
        raise proc.StepError("unknown platform %r" % name,
                             fix="one of: %s" % ", ".join(NAMES))
    if platform.mode == "unimplemented":
        raise proc.StepError(
            "%s is not implemented" % name,
            code=context.EXIT_SKIP,
            fix="the PS3 target needs an NVIDIA Cg toolchain (sce_vp_rsx / sce_fp_rsx); "
                "compile_ps3.ps1 was a stub and this is too",
        )
    return platform


def variant(platform, name=None):
    from . import proc

    if not name:
        return platform.variants[0]
    for v in platform.variants:
        if v.name == name:
            return v
    raise proc.StepError(
        "%s has no variant %r" % (platform.name, name),
        fix="one of: %s" % ", ".join(v.name for v in platform.variants),
    )


def defines_for(platform, variant_obj, extra=()):
    """Base + variant + user defines, deduped, order preserved."""
    out = []
    for d in tuple(platform.base_defines) + tuple(variant_obj.defines) + tuple(extra or ()):
        if d and d not in out:
            out.append(d)
    return out
