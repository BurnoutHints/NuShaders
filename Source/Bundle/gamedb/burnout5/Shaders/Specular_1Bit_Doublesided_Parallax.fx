#define USE_SHARED_GLOBALS
#define USE_HDR_CONSTANTS
#include "../Include/Platform.fxh"
#include "../Include/Constants.fxh"
#include "../Include/NormalMapping.fxh"

// Specular_1Bit_Doublesided + parallax occlusion mapping (height/displacement map)
// with soft self-shadowing. POM is per-pixel (works on the stock low-poly geometry);
// the tangent frame is rebuilt from derivatives so no extra vertex data/interpolators
// are needed. One source -> X360 (SM3), TUB (DX9 SM3), BPR (SM5).

GLOBALS_BEGIN
#include "../Include/SharedGlobals.fxh"
MATERIAL_F4(materialDiffuse, c47,   1.0, 1.0, 1.0, 1.0)
MATERIAL_F (SpecularPower,   c48,   12.0)
MATERIAL_F (Specularity,     c48.y, 1.5)
#ifndef D_POM_STOCKBIND
MATERIAL_F (ParallaxScale,   c48.z, 0.04)
MATERIAL_F (ParallaxBumpScale, c48.w, 2.0)
MATERIAL_F (ParallaxDepthScale, c49,  0.05)   // world-space relief depth, for D_POM_DEPTH
#endif
GLOBALS_END
#ifdef D_POM_STOCKBIND
// Stock-binding mode: the cloned stock 0x32 has no Parallax constants, so they're compile-time
// literals, and height comes from the spec map's alpha (no dedicated displacement sampler).
static const float ParallaxScale      = 0.04;
static const float ParallaxBumpScale  = 2.0;
static const float ParallaxDepthScale = 0.05;
#endif

#include "../Include/Transform.fxh"
#define SHADOW_APPLY_Z_BIAS
#define SHADOW_Z_BIAS_VALUE 0.0005
#include "../Include/Shadow.fxh"
#include "../Include/Fog.fxh"
#include "../Include/Irradiance.fxh"
#include "../Include/DepthEncode.fxh"
#ifdef D_POM_STOCKBIND
#define D_POM_HEIGHT_CHANNEL a   // height packed in the spec map's alpha
#endif
#include "../Include/Parallax.fxh"
#ifdef D_OREN_NAYAR
#include "../Include/OrenNayar.fxh"
#endif
#if defined(D_GGX_SPECULAR) || defined(D_PBR_SPECMAP)
#include "../Include/GGX.fxh"
#endif
#ifdef D_PBR_SPECMAP
#include "../Include/Pbr.fxh"   // reusable metallic-roughness model + knobs (D_PBR_* defines live here)
#endif
#ifdef D_SSR
#include "../Include/Ssr.fxh"
#endif

DECL_TEX2D(DiffuseTextureSampler, 0);
DECL_TEX2D(SpecularTextureSampler, 1);
#ifdef D_POM_STOCKBIND
#define HEIGHT_SAMPLER SpecularTextureSampler        // height from spec.alpha (stock bindings, clone-compatible)
#else
DECL_TEX2D(DisplacementTextureSampler, 2);
#define HEIGHT_SAMPLER DisplacementTextureSampler
#endif
#ifdef D_PBR_REFLECTION
DECL_TEXCUBE(ReflectionTextureSampler, 2);           // static material cubemap (the material binds a cube to s2)
#endif
#if defined(D_DBG_VIEW_SCENE) || defined(D_SSR)
DECL_TEX2D(g_depthSampler, 8);   // scene depth  (bound by the SSR hook DLL; debug probe reads it raw)
DECL_TEX2D(samplersource, 7);    // scene colour (bound by the SSR hook DLL)
#endif

struct vertexInput {
    float3 position    : POSITION;
    float3 normal    : NORMAL;
    float2 texCoordDiffuse  : TEXCOORD0;
};
struct vertexOutput {
    float4 hPosition    : VPOS_OUT;
    float2 texCoordDiffuse   : TEXCOORD0;
    float4 ReflectionVectorAndFog : TEXCOORD1;
    SHADOWMAP_INTERPOLATORS2( 2,3 )
    float4 IndirectColourAndKey  : TEXCOORD4;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD5;
#endif
    float3 WorldNormal              : TEXCOORD6;
    float3 EyeToVertex              : TEXCOORD7;   // un-normalized (ViewPosition - WorldPos): view dir + cotangent frame
};

vertexOutput VS_Main(vertexInput IN)
{
    vertexOutput OUT;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    float3 WorldSpaceNormal  = normalize( mul( IN.normal, (float3x3)world ) );
    OUT.hPosition    = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.texCoordDiffuse = IN.texCoordDiffuse;
    OUT.IndirectColourAndKey.xyz = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.w   = dot( WorldSpaceNormal, -KeyLightDirection );
    float3 lEyeToVertex = ViewPosition.xyz - WorldSpacePosition;
    float3 lReflection  = ( WorldSpaceNormal * ( 2.0f * dot( lEyeToVertex, WorldSpaceNormal ) ) ) - lEyeToVertex;
    OUT.ReflectionVectorAndFog.xyz = lReflection;
    OUT.ReflectionVectorAndFog.w = CalculateScattering( length( lEyeToVertex ) );
    CALC_SHADOWMAP_INTERPOLATORS3( WorldSpacePosition, OUT.hPosition.w );
    OUT.WorldNormal = WorldSpaceNormal;
    OUT.EyeToVertex = lEyeToVertex;
    return OUT;
}

void PS_Main( in vertexOutput IN, in VFACE_TYPE lfFace : VFACE_SEM,
              out float4 oColour0 : COLOR_OUT(0)
#ifdef D_MRT
            , out float4 oColour1 : COLOR_OUT(1)
#endif
#ifdef D_POM_DEPTH
            , out float oDepth : DEPTH_OUT
#endif
            )
{
    // --- Parallax occlusion: build a per-pixel tangent frame and offset the UV. ---
    float3 lWorldNormal = normalize( IN.WorldNormal ) * (FACE_IS_FRONT(lfFace) ? 1.0 : -1.0);
    float3 lWorldPos    = (float3)ViewPosition.xyz - IN.EyeToVertex;
    float3 lEyeDir      = normalize( IN.EyeToVertex );                 // toward the eye
    float3x3 lTBN       = CotangentFrame( lWorldNormal, lWorldPos, IN.texCoordDiffuse );
    float3 lTsView      = mul( lTBN, lEyeDir );
    float  lHitDepth    = 0.0;
    float2 lUV          = ParallaxOcclusion( TEX2D_ARG(HEIGHT_SAMPLER), IN.texCoordDiffuse, lTsView, (float)ParallaxScale, lHitDepth );

    float4 diffuseTexture = SAMPLE2D( DiffuseTextureSampler, lUV );
#ifdef D_PLATFORM_BPR
    clip( diffuseTexture.a - 0.5 );
#endif
#ifndef D_PBR_SPECMAP
    float  specularTexture = SAMPLE2D( SpecularTextureSampler, lUV ).g;
#endif

    // Height-derived shading normal so the relief catches the key light (already on the
    // correct face side: lTBN's N row is the face-flipped geometric normal).
    float3 lShadingNormal = normalize( mul( ParallaxNormal( TEX2D_ARG(HEIGHT_SAMPLER), lUV, (float)ParallaxBumpScale ), lTBN ) );

    // Soft self-shadow from the relief toward the key light.
    float3 lTsLight   = mul( lTBN, normalize( (float3)-KeyLightDirection ) );
    float  lPomShadow = ParallaxSelfShadowFactor( TEX2D_ARG(HEIGHT_SAMPLER), lUV, lTsLight, (float)ParallaxScale );

    float3 lLightDirection = (float3)-KeyLightDirection;
#ifdef D_PBR_SPECMAP
    // --- Metallic-roughness PBR (model in Pbr.fxh): spec .g=roughness, .b=metallic, .a=height(POM). ---
    float2 lSpecGB    = SAMPLE2D( SpecularTextureSampler, lUV ).gb;
    float  lRoughness = max( lSpecGB.x, 0.04 );
    float  lMetallic  = lSpecGB.y;
    float3 lAlbedo    = float3(diffuseTexture.rgb) * float3(materialDiffuse.xyz);
    float3 lF0        = PbrF0( lAlbedo, lMetallic );
    float3 lIndirect  = float3( IN.IndirectColourAndKey.xyz );
    float  lShadowModulation = CALC_SHADOW_FACTOR_3( dot( lShadingNormal, lLightDirection ) ) * lPomShadow;
#ifdef D_PBR_AO
    float  lAO = SAMPLE2D( SpecularTextureSampler, lUV ).r;   // R = ambient occlusion (ORM packing); scales ambient only, not direct light
#else
    float  lAO = 1.0;
#endif

    float3 lFinalColour = PbrDirect( lShadingNormal, lLightDirection, lEyeDir, lAlbedo, lRoughness, lMetallic, lF0,
                                     float3(KeyLightColour), float3(KeyLightSpecularColour), lIndirect * lAO, lShadowModulation );
#ifdef D_PBR_REFLECTION
    float3 lReflVec = reflect( -lEyeDir, lShadingNormal );
    float  lNdotVr  = saturate( dot( lShadingNormal, lEyeDir ) );
    float3 lEnv     = PbrSampleEnv( TEXCUBE_ARG(ReflectionTextureSampler), lReflVec, lRoughness );
#ifdef D_SSR
    // Screen-space reflection (parked): the hook DLL binds scene depth@t8 + colour@t7; blend over the cube.
    float4 lSsr = ScreenSpaceReflection( TEX2D_ARG(g_depthSampler), TEX2D_ARG(samplersource), lWorldPos, lReflVec );
    lEnv        = lerp( lEnv, lSsr.rgb, lSsr.a * saturate( 1.0 - lRoughness * 2.0 ) );
#endif
    lFinalColour += PbrReflection( lEnv, lNdotVr, lRoughness, lF0, lMetallic, float3(FogColourPlusWhiteLevel.rgb), lShadowModulation, (float)FogColourPlusWhiteLevel.w ) * lAO;
#else
    lFinalColour   += lIndirect * lAO * lF0;   // cheap ambient-spec fallback (no cube)
#endif
    lFinalColour = lerp( lFinalColour.rgb, float3(FogColourPlusWhiteLevel.rgb), float(IN.ReflectionVectorAndFog.w) );
#else
#ifdef D_GGX_SPECULAR
    float  lGGXRoughness = max( 1.0 - specularTexture, 0.04 );
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( Specularity * ComputeGGXSpecular( lShadingNormal, lLightDirection, lEyeDir, lGGXRoughness, 0.04 ) );
#else
    float3 lReflection = normalize( ( lShadingNormal * ( 2.0 * dot( lEyeDir, lShadingNormal ) ) ) - lEyeDir );
    float  lrRdotL     = saturate( dot( lReflection, lLightDirection ) );
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( (float)Specularity * pow( lrRdotL, (float)SpecularPower ) );
#endif
    lSpecularColour *= specularTexture;

    float lNormalDotLight   = dot( lShadingNormal, lLightDirection );   // per-pixel, from the relief
    float lShadowModulation = CALC_SHADOW_FACTOR_3( lNormalDotLight ) * lPomShadow;   // CSM shadow * POM self-shadow
#ifdef D_OREN_NAYAR
    float lDirectLightFactor = ComputeOrenNayarDiffuseFromSpecMap( lShadingNormal, lLightDirection, lEyeDir, specularTexture ) * lShadowModulation;
#else
    float lDirectLightFactor = saturate( lNormalDotLight * lShadowModulation );
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor ) * float3(materialDiffuse.xyz);
    float3 lFinalColour         = (diffuseTexture * lLightColour) + (lSpecularColour * lShadowModulation);
    lFinalColour = lerp( lFinalColour.rgb, float3(FogColourPlusWhiteLevel.rgb), float(IN.ReflectionVectorAndFog.w) );
#endif

#ifdef D_SSR
    // Transparent-pass build: force opaque alpha so the alpha-blend state renders solid
    // (src*1 + dst*0). The clip(diffuseTexture.a-0.5) above still carves the 1-bit cutout shape.
    oColour0 = float4(lFinalColour, 1.0);
#else
    oColour0 = float4(lFinalColour, diffuseTexture.a);
#endif
#ifdef D_MRT
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth );
#endif
#ifdef D_POM_DEPTH
    // Push the fragment depth back to where the view ray meets the relief, so it
    // intersects/occludes scene geometry correctly. lWorldNormal is the flat (face) normal.
    float  lNdotV    = max( dot( lEyeDir, lWorldNormal ), 0.1 );
    float3 lHitWorld = lWorldPos - lEyeDir * ( lHitDepth * (float)ParallaxDepthScale / lNdotV );
    oDepth = DepthFromWorldPosition( lHitWorld );
#endif
#ifdef D_DBG_VIEW_SCENE
    // Transparent-pass DEPTH probe (size-agnostic): read g_depthSampler at its OWN dimensions.
    // MAGENTA = reads exactly 0 (no usable depth). Otherwise depth: R=banded, G=raw, B=sqrt(d).
    {
        int2 dbgPx = int2( IN.hPosition.xy );
        float2 scDim; samplersourceTexture.GetDimensions( scDim.x, scDim.y );      // half-res scene colour
        float2 screenSz = max( scDim * 2.0, float2(1.0,1.0) );
        float2 uv = float2( dbgPx ) / screenSz;
        float2 dDim; g_depthSamplerTexture.GetDimensions( dDim.x, dDim.y );
        float  d = g_depthSamplerTexture.Load( int3( int2( uv * dDim ), 0 ) ).r;
        if ( d == 0.0 )
            oColour0 = float4( 1.0, 0.0, 1.0, 1.0 );                                // magenta = exactly 0
        else
            oColour0 = float4( frac( d * 16.0 ), d, sqrt( saturate( d ) ), 1.0 );   // real depth (banded)
    }
#endif
}

#ifndef D_PLATFORM_BPR
technique Default
<
>
{
    pass p0
    {
        CULLMODE = none;
        AlphaRef = 0;
        AlphaFunc = GREATER;
        AlphaTestEnable = True;
        AlphaBlendEnable = False;
        VertexShader = compile vs_3_0 VS_Main();
        PixelShader  = compile ps_3_0 PS_Main();
    }
}
#endif

struct vertexInputZOnly {
    float3 position    : POSITION;
#ifdef D_POM_DEPTH
    float3 normal      : NORMAL;
#endif
    float2 texCoordDiffuse  : TEXCOORD0;
};
struct vertexOutputZOnly {
    float4 hPosition   : VPOS_OUT;
    float2 texCoordDiffuse  : TEXCOORD0;
#ifdef D_MSAA_ENABLED
    float2 hPositionDepthCopy   : TEXCOORD1;
#endif
#ifdef D_POM_DEPTH
    float3 WorldNormal  : TEXCOORD2;
    float3 EyeToVertex  : TEXCOORD3;
#endif
};
vertexOutputZOnly VS_Main_ZOnly( vertexInputZOnly IN )
{
    vertexOutputZOnly OUT;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition    = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MSAA_ENABLED
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.texCoordDiffuse = IN.texCoordDiffuse;
#ifdef D_POM_DEPTH
    OUT.WorldNormal = normalize( mul( IN.normal, (float3x3)world ) );
    OUT.EyeToVertex = ViewPosition.xyz - WorldSpacePosition;
#endif
    return OUT;
}
#ifdef D_POM_DEPTH
// Prepass must produce the SAME parallax-offset cutout AND corrected depth as the main pass.
void PS_Main_ZOnly( in vertexOutputZOnly IN, in VFACE_TYPE lfFace : VFACE_SEM,
                    out float4 oColour0 : COLOR_OUT(0),
                    out float oDepth : DEPTH_OUT )
{
    float3 lWorldNormal = normalize( IN.WorldNormal ) * (FACE_IS_FRONT(lfFace) ? 1.0 : -1.0);
    float3 lWorldPos    = (float3)ViewPosition.xyz - IN.EyeToVertex;
    float3 lEyeDir      = normalize( IN.EyeToVertex );
    float3x3 lTBN       = CotangentFrame( lWorldNormal, lWorldPos, IN.texCoordDiffuse );
    float  lHitDepth    = 0.0;
    float2 lUV          = ParallaxOcclusion( TEX2D_ARG(HEIGHT_SAMPLER), IN.texCoordDiffuse, mul( lTBN, lEyeDir ), (float)ParallaxScale, lHitDepth );

    float4 lDiffuse = SAMPLE2D( DiffuseTextureSampler, lUV );
    clip( lDiffuse.a - ALPHA_TEST_THRESHOLD );

    float  lNdotV    = max( dot( lEyeDir, lWorldNormal ), 0.1 );
    float3 lHitWorld = lWorldPos - lEyeDir * ( lHitDepth * (float)ParallaxDepthScale / lNdotV );
    oDepth = DepthFromWorldPosition( lHitWorld );
#ifdef D_MSAA_ENABLED
    float4 lfDepth = oDepth;
    lfDepth.w = lDiffuse.a;
    oColour0 = lfDepth;
#else
    oColour0 = lDiffuse;
#endif
}
#else
float4 PS_Main_ZOnly( vertexOutputZOnly IN ): COLOR_OUT(0)
{
    float4 lDiffuse = SAMPLE2D( DiffuseTextureSampler, IN.texCoordDiffuse);
    clip( lDiffuse.a - ALPHA_TEST_THRESHOLD );
#ifdef D_MSAA_ENABLED
    float4 lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    lfDepth.w = lDiffuse.a;
    return lfDepth;
#else
    return lDiffuse;
#endif
}
#endif
#ifndef D_PLATFORM_BPR
technique ZOnly1BitDoubleSided
<
  string sharedName="ZOnly1BitDoubleSided";
>
{
    pass p0
    {
        CULLMODE = none;
        AlphaRef = 128;
        AlphaFunc = GREATER;
        AlphaTestEnable = True;
        AlphaBlendEnable = False;
        SrcBlend = SrcAlpha;
        DestBlend = InvSrcAlpha;
#ifndef D_MSAA_ENABLED
        ColorWriteEnable = 0;
#endif
        VertexShader = compile vs_3_0 VS_Main_ZOnly();
        PixelShader  = compile ps_3_0 PS_Main_ZOnly();
    }
}
#endif
