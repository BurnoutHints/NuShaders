#ifndef PLATFORM_FXH
#define PLATFORM_FXH

// ===========================================================================
//  Cross-platform shader compatibility layer.
//
//  One set of .fx source compiles to three targets via these macros:
//    D_PLATFORM_BPR  -> SM5 / DX11  (Burnout Paradise Remastered)
//    D_PLATFORM_X360 -> Xenos SM3   (Xbox 360)
//    (neither)       -> DX9 SM3     (PC TUB)
//
//  SM5 differences handled here: single global cbuffer at b0 (packoffset),
//  Texture2D+SamplerState pairs, .Sample/.SampleBias/.SampleCmp, and SV_*
//  system-value semantics. The only real *logic* difference (shadow compare)
//  lives in Shadow.fxh.
//
//  Most shaders reach BPR the way the remaster itself did: the TUB-era source,
//  loose globals and DX9 sampling intact, compiled /Gec /Zpr /Op (the flags in
//  every shipped RDEF). $Globals then lays out in declaration order, which is
//  why this header must be included first (sampleCoverage leads every shipped
//  layout). Sampler declarations go through SAMPLER_2D / SAMPLER_CUBE, and only
//  the remaster's own changes carry a D_PLATFORM_BPR branch; everything else
//  expands identically on SM3.
//
//  Global-constant macros take the constant's register on BOTH platforms as
//  full tokens (e.g. c0 / c5) to avoid preprocessor token-pasting pitfalls.
//  Texture macros take a numeric slot (paste-friendly: t##slot / s##slot).
// ===========================================================================

#ifdef D_PLATFORM_BPR
// ----------------------------- SM5 / DX11 ----------------------------------

#define GLOBALS_BEGIN  cbuffer _Globals : register(b0) {
#define GLOBALS_END    }

// Shared globals. _R = had a forced X360 register; plain = auto on SM3.
#define GLOBAL_F4(name, bprreg)               float4 name : packoffset(bprreg);
#define GLOBAL_F3(name, bprreg)               float3 name : packoffset(bprreg);
#define GLOBAL_F4X4(name, bprreg)             row_major float4x4 name : packoffset(bprreg);
#define GLOBAL_F4_R(name, x360reg, bprreg)    float4 name : packoffset(bprreg);
#define GLOBAL_F3_R(name, x360reg, bprreg)    float3 name : packoffset(bprreg);
#define GLOBAL_F4X4_R(name, x360reg, bprreg)  row_major float4x4 name : packoffset(bprreg);
#define GLOBAL_F4X4_ARRAY_R(name, cnt, x360reg, bprreg) row_major float4x4 name[cnt] : packoffset(bprreg);

// Per-shader material constants (inside the same _Globals cbuffer).
#define MATERIAL_F4(name, bprreg, x,y,z,w)    float4 name : packoffset(bprreg);
#define MATERIAL_F(name, bprreg, dflt)        float  name : packoffset(bprreg);

// Textures / samplers (BPR pairs a SamplerState "name" with Texture2D "nameTexture").
#define DECL_TEX2D(name, slot)    Texture2D   name##Texture : register(t##slot); SamplerState name : register(s##slot)
#define DECL_TEXCUBE(name, slot)  TextureCube name##Texture : register(t##slot); SamplerState name : register(s##slot)
// One sampler declaration for every platform: name and slot once, then the SM3
// annotations + sampler_state verbatim. BPR drops that block: on DX11 the engine
// binds the sampler state itself (from TextureState), so only the pair remains.
#define SAMPLER_2D(name, slot, sm3state)    DECL_TEX2D(name, slot)
#define SAMPLER_CUBE(name, slot, sm3state)  DECL_TEXCUBE(name, slot)
#define SAMPLER_2D_UNTYPED(name, slot, sm3state)  DECL_TEX2D(name, slot)
#define SAMPLE2D(name, uv)         name##Texture.Sample(name, uv)
#define SAMPLE2D_BIAS(name, uv, b) name##Texture.SampleBias(name, uv, b)
#define SAMPLE2D_LOD(name, uv, lod) name##Texture.SampleLevel(name, uv, lod)
#define SAMPLECUBE(name, dir)      name##Texture.Sample(name, dir)
#define SAMPLECUBE_LOD(name, dir, lod) name##Texture.SampleLevel(name, dir, lod)
// Pass a 2D texture+sampler pair to a function (and the matching call-site argument).
#define TEX2D_PARAM(name)          Texture2D name##Texture, SamplerState name
#define TEX2D_ARG(name)            name##Texture, name
#define TEXCUBE_PARAM(name)        TextureCube name##Texture, SamplerState name
#define TEXCUBE_ARG(name)          name##Texture, name

// TUB-era shaders keep their DX9 sampling calls; only their sampler declarations
// have a BPR alternative (DECL_TEX2D / DECL_TEXCUBE). Every shipped BPR shader
// pairs sampler X at sN with texture XTexture at tN, which is what these resolve to.
#define tex2D(s, uv)               s##Texture.Sample(s, uv)
#define tex2Dbias(s, uvb)          s##Texture.SampleBias(s, (uvb).xy, (uvb).w)
#define texCUBE(s, dir)            s##Texture.Sample(s, dir)

#ifndef USE_SHARED_GLOBALS
// The remaster prepends this to every shader, so it is the first member of every
// shipped $Globals (offset 0). The 1-bit alpha shaders read it. Platform.fxh must
// therefore be the first include of a shader that declares loose globals.
float4 sampleCoverage;
#endif

// DX11 has no fixed-function alpha test. The remaster replaced it (and the 0.499999
// threshold of the ZOnly passes) with this, in all 17 shipped 1-bit pixel shaders:
// alpha > ~0 while the engine runs alpha-to-coverage (sampleCoverage.x != 0), else > 0.5.
#define ALPHA_TEST_THRESHOLD       ( sampleCoverage.x != 0 ? 0.000001 : 0.499999 )
#define ALPHA_TEST(alpha)          clip( (alpha) - ALPHA_TEST_THRESHOLD )

// Remastered fix in 7 shipped vertex shaders: a zero vertex normal would normalize to NaN.
#define SAFE_NORMAL(n)             ( all( (n) == 0 ) ? float3( 0, 1, 0 ) : (n) )

// Semantics
#define VPOS_OUT       SV_Position
#define COLOR_OUT(n)   SV_Target##n
// Conservative depth output: POM only pushes depth farther, so SV_DepthGreaterEqual keeps early-Z.
#define DEPTH_OUT      SV_DepthGreaterEqual
#define VFACE_TYPE     bool
#define VFACE_SEM      SV_IsFrontFace
// The BPR vehicle vertex format feeds BLENDINDICES as SINT; D3D11 needs the VS input to match.
#define BONE_INDICES4  int4
// FACE_IS_FRONT mirrors the SM3 `(lfFace < 0)` test (which is the FRONT case in
// Burnout's X360 VFACE polarity). On DX11 the front face is SV_IsFrontFace == true,
// i.e. the bool itself.
#define FACE_IS_FRONT(f) (f)

#else
// --------------------------- SM3 (X360 + TUB) ------------------------------

#define GLOBALS_BEGIN
#define GLOBALS_END

#define GLOBAL_F4(name, bprreg)               float4 name;
#define GLOBAL_F3(name, bprreg)               float3 name;
#define GLOBAL_F4X4(name, bprreg)             float4x4 name;

#ifdef D_PLATFORM_X360
#define GLOBAL_F4_R(name, x360reg, bprreg)    float4 name : register(x360reg);
#define GLOBAL_F3_R(name, x360reg, bprreg)    float3 name : register(x360reg);
#define GLOBAL_F4X4_R(name, x360reg, bprreg)  float4x4 name : register(x360reg);
#define GLOBAL_F4X4_ARRAY_R(name, cnt, x360reg, bprreg) float4x4 name[cnt] : register(x360reg);
#else
#define GLOBAL_F4_R(name, x360reg, bprreg)    float4 name;
#define GLOBAL_F3_R(name, x360reg, bprreg)    float3 name;
#define GLOBAL_F4X4_R(name, x360reg, bprreg)  float4x4 name;
#define GLOBAL_F4X4_ARRAY_R(name, cnt, x360reg, bprreg) float4x4 name[cnt];
#endif

#define MATERIAL_F4(name, bprreg, x,y,z,w)    float4 name = { x, y, z, w };
#define MATERIAL_F(name, bprreg, dflt)        float  name = dflt;

#define DECL_TEX2D(name, slot)    sampler2D   name : register(s##slot)
#define DECL_TEXCUBE(name, slot)  samplerCUBE name : register(s##slot)
// sm3state is the declaration's annotations + sampler_state, passed through untouched:
// TUB's D3DX effects apply exactly the states listed and read the scope annotations.
#define SAMPLER_2D(name, slot, sm3state)    sampler2D   name : register(s##slot) sm3state
#define SAMPLER_CUBE(name, slot, sm3state)  samplerCUBE name : register(s##slot) sm3state
// Some TUB samplers are declared as plain `sampler`; the effect records that type, so keep it.
#define SAMPLER_2D_UNTYPED(name, slot, sm3state)  sampler name : register(s##slot) sm3state
#define SAMPLE2D(name, uv)         tex2D(name, uv)
#define SAMPLE2D_BIAS(name, uv, b) tex2Dbias(name, float4((uv), 0, (b)))
#define SAMPLE2D_LOD(name, uv, lod) tex2Dlod(name, float4((uv), 0, (lod)))
#define SAMPLECUBE(name, dir)      texCUBE(name, dir)
#define SAMPLECUBE_LOD(name, dir, lod) texCUBElod(name, float4((dir), (lod)))
// Pass a 2D sampler to a function (and the matching call-site argument).
#define TEX2D_PARAM(name)          sampler2D name
#define TEX2D_ARG(name)            name
#define TEXCUBE_PARAM(name)        samplerCUBE name
#define TEXCUBE_ARG(name)          name

// Semantics
#define VPOS_OUT       POSITION
#define COLOR_OUT(n)   COLOR##n
#define DEPTH_OUT      DEPTH
#define VFACE_TYPE     float
#define VFACE_SEM      VFACE
#define BONE_INDICES4  float4

// SM3 keeps the technique's AlphaTestEnable, so ALPHA_TEST adds nothing here.
#define ALPHA_TEST_THRESHOLD       0.499999f
#define ALPHA_TEST(alpha)
#define SAFE_NORMAL(n)             n
#define FACE_IS_FRONT(f) ((f) < 0.0)

#endif

#endif // PLATFORM_FXH
