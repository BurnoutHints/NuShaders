# NuShaders

Custom shaders for Burnout Paradise.

## Quick start

```bash
python nushaders.py doctor all        # what is installed, what is missing, how to fix it
python nushaders.py tools build-cli   # build nushaders.exe (the C# format tool)
python nushaders.py build bpr         # compile + pack for Remastered PC
python nushaders.py verify bpr        # verify if the packer still reproduces correct bytes
```

## First-time setup

Before doing anything, run this command:

```
python nushaders.py reference status     # what is present, what is missing, what needs it
```

Supply these versions of `SHADERS.BNDL` yourself:
### To compile for Remastered
- Just the `SHADERS.BNDL` found in your game install folder
### To compile for Xbox 360
- Burnout_tcartwright 'Breaker Island' build
- 1.6 'Free Feburary' Content Update
- 1.8 'Cops n Robbers' Content Update

Then, import the reference bundles:
```bash
python nushaders.py reference import "D:/dumps/SHADERS.BNDL" --version Breaker
# or alternatively, let the tool auto-detect the Remastered version
python nushaders.py reference import "D:/dumps/SHADERS.BNDL"
# then regenerate the manifest for your desired platform
python nushaders.py manifest regen --platform x360
```

`reference import` uses YAP to unpack the bundles into their respective directories.

For Remastered, also extract the stock shader programs (see [below](#remastered-bpr-shader-programs)):
```bash
python nushaders.py reference extract
```

Note: For Xbox 360, only `Breaker` has a resource string table. 
`manifest regen` will only work when that version of SHADERS.BNDL is provided.

Then check the toolchain:

```bash
python nushaders.py doctor all
```

## Layout

| Path | What |
|---|---|
| `Source/Bundle/gamedb/burnout5/Shaders` | the shader source |
| `Source/Bundle/gamedb/burnout5/Include` | shared shader headers |
| `Reference/` | where to place the extracted stock bundles, + format docs |
| `Build/manifest/` | generated shader ↔ resource-id map |
| `Build/config/` | per-machine deploy configs |
| `Build/Output/` | build artifacts |
| `Tools/NuBuild/` | the build system |
| `Tools/ShaderApp/` | the C# NuShaders app (`nushaders.exe`, GUI, format tests) |
| `Tools/Mod/SSRHook/` | (broken) SSR proxy DLL mod |

## Platforms

`D_PLATFORM_*` defines platform specific behavior. `Include/Platform.fxh` switches on:

| Target | Profile | Notes |
|---|---|---|
| `x360` | Xenos SM3 (`vs_3_0`/`ps_3_0`) | needs XDK 6534 |
| `bpr` | SM5 (`vs_5_0`/`ps_5_0`) | uses standard Windows SDK fxc |
| `pc-tub` | DX9 `fx_2_0` | the actual game uses the source direcly |
| `ps3` | — | not implemented yet |

`build` compiles each technique's VS and PS separately and packs them into
ShaderProgramBuffer resources. `build <platform> --effects --all-variants`
compiles all variants to ensure they properly compile, but don't work ingame.

## Examples

```bash
# compile one shader
python nushaders.py build bpr --filter "Specular_1Bit_Doublesided.fx"

# compile all X360 shaders, then look at what changed
python nushaders.py build x360
python nushaders.py manifest show --platform x360

# set this machine up to deploy to BPR, then deploy
python nushaders.py config new
python nushaders.py config set bpr.game_exe "C:/.../BurnoutPR.exe"
python nushaders.py deploy bpr

# set up to deploy to xbox 360, then deploy
python nushaders.py config discover-ip --write
python nushaders.py deploy x360
python nushaders.py autotest --script shadertest.lua

# put a Remastered install back the way it was
python nushaders.py deploy --restore
```

`--dry-run` works on everything and prints what runs without
touching anything.

## The manifest

`Build/manifest/{x360,bpr}.json` maps each shader technique to the resource id
the game expects, derived from the stock bundle's `.debug.xml` plus
`Reference/ResourceDB.json`.

```bash
python nushaders.py manifest regen     # re-derive and write
python nushaders.py manifest check     # re-derive and diff; non-zero on drift
```

A technique whose annotation carries `string sharedName="..."` maps to **one**
engine resource however many `.fx` declare it — `ZOnlyOpaqueSingleSided` appears
in 55 shaders and has a single id. The manifest collapses those to one build
action. Where the copies disagree it records every distinct implementation under
`conflicts` and marks one `canonical`; `regen` never overwrites a `canonical`
someone set by hand.

## Remastered (BPR) shader programs

`reference extract` validates every ShaderProgramBuffer pair in `Reference/BPR/SHADERS`
and writes `Reference/BPR/Extracted/` (gitignored, regenerated whole each run):

| File | What |
|---|---|
| `<Fx>.<Technique>.<vs\|ps>.<ID>.dxbc` | the exact shipped DXBC, padding stripped (shared techniques: `<Name>.<vs\|ps>.<ID>`) |
| `….asm` | fxc disassembly: `$Globals` offsets, resource slots, stage I/O, code |
| `….hlsl` | a decompile, only if `NUSHADERS_DECOMPILER="<command> {in} {out}"` is set |
| `manifest.json` | each id's name, primary/secondary pair, hashes, reflection, aliases, the source technique that rebuilds it, and validation results |

`build bpr` then checks every stage that replaces a shipped resource against that
shipped shader before choosing its primary:

| Rebuilt vs shipped | Primary |
|---|---|
| identical interface | stock primary reused, only `dxbcSize` patched |
| `$Globals` offsets moved; same slots and stage I/O; reads nothing new | generated from reflection |
| a slot added or moved, stage I/O changed, or a variable read that the shipped shader never read | **refused**: nothing proves the engine supplies it |

A refusal names every difference in `Build/Output/PC_BPR/obj/default/<stage>.pack.log`
and points at the shipped `.asm`. That list is the porting to-do for the shader.
`--generate` skips the comparison and generates every primary.

## Known issues

- **The full BPR build has not been run in game yet.** `build bpr` compiles all 232
  stages; 204 of the 208 that replace a shipped shader reproduce its interface
  exactly (stock primary reused) and 107 its bytecode. A deploy now replaces every
  shader, so check in game first. To ship a subset: `clean bpr`, then
  `build bpr --filter "<file>.fx"`, then `deploy bpr --no-build`.
- **Four BPR stages still get a generated primary.** `ZOnlyNull` and
  `ZOnlyOpaqueSingleSided` VS were built by the remaster from a file not in this
  tree; the hand-ported `Specular_1Bit_Doublesided` VS/PS keep their fixed
  `SharedGlobals.fxh` layout.
- **`ZOnly1BitDoubleSided` has three different implementations** across the files 
  its present in, and those variants all share one resource ID.