#define USE_SHARED_GLOBALS
#define USE_HDR_CONSTANTS
#include "../Include/Platform.fxh"
#include "../Include/Constants.fxh"
#include "../Include/NormalMapping.fxh"

// All shared global constants in one place (cbuffer _Globals @ b0 on BPR;
// loose uniforms with X360 register-forcing on SM3).
GLOBALS_BEGIN
#include "../Include/SharedGlobals.fxh"
MATERIAL_F4(materialDiffuse, c47,   1.0, 1.0, 1.0, 1.0)
MATERIAL_F (SpecularPower,   c48,   12.0)
MATERIAL_F (Specularity,     c48.y, 1.5)
GLOBALS_END

#include "../Include/Transform.fxh"
#define SHADOW_APPLY_Z_BIAS
#define SHADOW_Z_BIAS_VALUE 0.0005
#include "../Include/Shadow.fxh"
#include "../Include/Fog.fxh"
#include "../Include/Irradiance.fxh"
#include "../Include/DepthEncode.fxh"
#ifdef D_OREN_NAYAR
#include "../Include/OrenNayar.fxh"
#endif
#ifdef D_GGX_SPECULAR
#include "../Include/GGX.fxh"
#endif

DECL_TEX2D(DiffuseTextureSampler, 0);
DECL_TEX2D(SpecularTextureSampler, 1);

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
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    float3 WorldNormal              : TEXCOORD6;
    float3 ViewDirection            : TEXCOORD7;
#endif
};
struct vertexOutputLod1 {
    float4 hPosition    : VPOS_OUT;
    float2 texCoordDiffuse   : TEXCOORD0;
 float4 ReflectionVectorAndFog : TEXCOORD1;
 float4 LightSpacePosFar   : TEXCOORD2;
    float4 IndirectColourAndKey  : TEXCOORD3;
};
vertexOutput VS_Main(vertexInput IN
      )
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
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    OUT.WorldNormal = WorldSpaceNormal;
    OUT.ViewDirection = normalize( ViewPosition.xyz - WorldSpacePosition );
#endif
    return OUT;
}
#ifdef D_MRT
void PS_Main( in  vertexOutput IN,
              in  VFACE_TYPE lfFace : VFACE_SEM,
              out float4 oColour0 : COLOR_OUT(0),
              out float4 oColour1 : COLOR_OUT(1) )
#else
float4 PS_Main( vertexOutput IN, VFACE_TYPE lfFace : VFACE_SEM ) : COLOR_OUT(0)
#endif
{
 float4 diffuseTexture = SAMPLE2D( DiffuseTextureSampler, IN.texCoordDiffuse );
#ifdef D_PLATFORM_BPR
 // DX11 has no fixed-function alpha test; the SM3 Default technique relied on
 // AlphaTestEnable to cut out the 1-bit alpha. Do it explicitly here.
 clip( diffuseTexture.a - 0.5 );
#endif
 float  specularTexture = SAMPLE2D( SpecularTextureSampler, IN.texCoordDiffuse ).g;
    float3 lLightDirection = (float3)-KeyLightDirection;
    float3 lReflectionVector = (float3)IN.ReflectionVectorAndFog.xyz;
    float  lrSpecularPower = (float)SpecularPower;
    float3 lReflection = normalize( lReflectionVector );
    float  lrRdotL = saturate( dot( lReflection, lLightDirection ) );
#ifdef D_GGX_SPECULAR
    float  lGGXRoughness = max( 1.0 - specularTexture, 0.04 );   // roughness from the inverted specular map (clamped to avoid a singular highlight)
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( Specularity * ComputeGGXSpecular( normalize(IN.WorldNormal) * (FACE_IS_FRONT(lfFace) ? 1.0 : -1.0), (float3)-KeyLightDirection, normalize(IN.ViewDirection), lGGXRoughness, 0.04 ) );
#else
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( (float)Specularity * pow( lrRdotL, lrSpecularPower ) );
#endif
    lSpecularColour *= specularTexture.r;
 float  lNormalDotLight  = FACE_IS_FRONT(lfFace) ? (float)IN.IndirectColourAndKey.w : (float)-IN.IndirectColourAndKey.w;
    float lShadowModulation = CALC_SHADOW_FACTOR_3( lNormalDotLight  );
#ifdef D_OREN_NAYAR
    float  lDirectLightFactor   = ComputeOrenNayarDiffuseFromSpecMap( normalize(IN.WorldNormal) * (FACE_IS_FRONT(lfFace) ? 1.0 : -1.0), (float3)-KeyLightDirection, normalize(IN.ViewDirection), specularTexture ) * lShadowModulation;
#else
    float  lDirectLightFactor   = saturate( lNormalDotLight * lShadowModulation );
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor ) * float3(materialDiffuse.xyz);
    float3 lFinalColour         = (diffuseTexture * lLightColour) + (lSpecularColour * lShadowModulation);
    lFinalColour = lerp( lFinalColour.rgb, float3(FogColourPlusWhiteLevel.rgb), float(IN.ReflectionVectorAndFog.w) );
#ifdef D_GGX_DEBUG
    float3 lDbgN   = normalize(IN.WorldNormal) * (FACE_IS_FRONT(lfFace) ? 1.0 : -1.0);
    float  lDbgNdL = saturate( dot( lDbgN, (float3)-KeyLightDirection ) );
    float  lDbgGGX = saturate( ComputeGGXSpecular( lDbgN, (float3)-KeyLightDirection, normalize(IN.ViewDirection), 0.3, 0.04 ) );
    lFinalColour = float3( lDbgNdL, lDbgGGX, 0.0 );
#endif
#ifdef D_MRT
    oColour0 = float4(lFinalColour, diffuseTexture.a);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth );
#else
    return float4(lFinalColour, diffuseTexture.a);
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
    float2 texCoordDiffuse  : TEXCOORD0;
};
struct vertexOutputZOnly {
    float4 hPosition   : VPOS_OUT;
    float2 texCoordDiffuse  : TEXCOORD0;
#ifdef D_MSAA_ENABLED
    float2 hPositionDepthCopy   : TEXCOORD1;
#endif
};
vertexOutputZOnly VS_Main_ZOnly( vertexInputZOnly IN
        )
{
    vertexOutputZOnly OUT;
     float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition    = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MSAA_ENABLED
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.texCoordDiffuse = IN.texCoordDiffuse;
    return OUT;
}
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
