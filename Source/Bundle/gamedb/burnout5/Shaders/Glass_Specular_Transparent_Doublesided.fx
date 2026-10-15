#include "../Include/Platform.fxh"
#define USE_HDR_CONSTANTS
#include "../Include/Constants.fxh"
#include "../Include/NormalMapping.fxh"
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
float3   ViewPosition : cameraposition
<
 string scope = "global";
>;
float3   KeyLightDirection
<
 string scope = "global";
>;
float3   KeyLightSpecularColour
<
 string scope = "global";
>;
float3   KeyLightColour
<
 string scope = "global";
>;
float4x4  worldViewProj : WorldViewProjection
<
 string scope = "object";
>;
float4x4  world : World
<
 string scope = "object";
>;
float4 materialDiffuse
<
 string scope = "material";
    string UIWidget = "rgba";
> = {1.0f, 1.0f, 1.0f, 1.0f};
float reflectStrength
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.0;
    float UIMax = 1.0;
    float UIStep = 0.01;
> = 0.6;
float reflectStrengthCameraFacing
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.0;
    float UIMax = 1.0;
    float UIStep = 0.01;
    string UIName = "Reflect strength (camera facing)";
> = 0.25;
float SpecularPower
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 1.0;
    float UIMax = 4000.0;
    float UIStep = 1.0;
    string UIName = "specular power";
> = 12.0;
float Specularity
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.0;
    float UIMax = 5.0;
    float UIStep = 0.1;
    string UIName = "Specularity";
> = 1.5;
textureCUBE ReflectionTexture : diffuse
<
 string scope = "material";
 string purpose = "none";
 string textureType = "CUBE";
>;
SAMPLER_CUBE(ReflectionTextureSampler, 0,
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <ReflectionTexture>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
 AddressU = clamp;
 AddressV = clamp;
});
struct vertexInput {
    float3 position    : POSITION;
    float3 normal    : NORMAL;
    float2 texCoordDiffuse  : TEXCOORD0;
};
struct vertexOutput {
    float4 hPosition    : POSITION;
 float4 EyeToVertexAndFog  : TEXCOORD0;
 float4 WorldSpaceNormalAlpha : TEXCOORD1;
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
    float4 hPosition    : POSITION;
 float4 EyeToVertexAndFog  : TEXCOORD0;
 float4 WorldSpaceNormalAlpha : TEXCOORD1;
 float4 LightSpacePosFar   : TEXCOORD2;
    float4 IndirectColourAndKey  : TEXCOORD3;
};
vertexOutput VS_Main( vertexInput IN
      ) 
{
    vertexOutput OUT;
     float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;           
    float3 WorldSpaceNormal  = normalize( mul( IN.normal, (float3x3)world ) );             
    OUT.hPosition    = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.IndirectColourAndKey.xyz = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.w   = dot( WorldSpaceNormal, -KeyLightDirection );
    float3 lEyeToVertex = ViewPosition.xyz - WorldSpacePosition;
    OUT.EyeToVertexAndFog.xyz = lEyeToVertex;
    OUT.WorldSpaceNormalAlpha.xyz = WorldSpaceNormal;
    OUT.EyeToVertexAndFog.w = CalculateScattering( length( lEyeToVertex ) );
    CALC_SHADOWMAP_INTERPOLATORS3( WorldSpacePosition, OUT.hPosition.w );    
    OUT.WorldSpaceNormalAlpha.w = dot( normalize(lEyeToVertex), WorldSpaceNormal );
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    OUT.WorldNormal = WorldSpaceNormal;
    OUT.ViewDirection = normalize( ViewPosition.xyz - WorldSpacePosition );
#endif
    return OUT;
}
#ifdef D_MRT
void PS_Main( in  vertexOutput IN,
              in  float lfFace : VFACE,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 PS_Main( vertexOutput IN, float lfFace : VFACE ) : COLOR
#endif
{ 
    float3 lLightDirection = (float3)-KeyLightDirection;
    float  lhSpecularPower = (float)SpecularPower;
    float3  lInputWorldSpaceNormal = (lfFace<0) ? (float3)IN.WorldSpaceNormalAlpha.xyz : (float3)-IN.WorldSpaceNormalAlpha.xyz;
    float3 lWorldSpaceNormal      = (float3)normalize( lInputWorldSpaceNormal );
    float3 lReflectionVector      = ( lWorldSpaceNormal * ( 2.0f * dot( IN.EyeToVertexAndFog.xyz, lWorldSpaceNormal ) ) ) - IN.EyeToVertexAndFog.xyz;
    float3  lReflection = normalize( (float3)lReflectionVector );
    float   lrRdotL = saturate( dot( lReflection, lLightDirection ) );
    float3  lSpecularColour = float3(KeyLightSpecularColour) * ( (float)Specularity * pow( lrRdotL, lhSpecularPower ) );
 float3 reflectionTexture  = texCUBE( ReflectionTextureSampler, lReflectionVector ).rgb;
 float  lNormalDotLight  = (lfFace<0) ? (float)IN.IndirectColourAndKey.w : (float)-IN.IndirectColourAndKey.w;
    float lShadowModulation = CALC_SHADOW_FACTOR_3( lNormalDotLight  );
#ifdef D_OREN_NAYAR
    float  lDirectLightFactor   = ComputeOrenNayarDiffuse( normalize(IN.WorldNormal), (float3)-KeyLightDirection, normalize(IN.ViewDirection), 0.1 ) * lShadowModulation;
#else
    float  lDirectLightFactor   = saturate( lNormalDotLight * lShadowModulation );
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor ) * float3(materialDiffuse.xyz);
    float3 lFinalColour         = (reflectionTexture * lLightColour) + (lSpecularColour * lShadowModulation);
    lFinalColour = lerp( lFinalColour, FogColourPlusWhiteLevel.rgb, float(IN.EyeToVertexAndFog.w) );      
    float lEyeDotNormal = (lfFace<0) ? (float3)IN.WorldSpaceNormalAlpha.w : (float3)-IN.WorldSpaceNormalAlpha.w;
 float lAlpha = lerp( reflectStrength, reflectStrengthCameraFacing, lEyeDotNormal );
#ifdef D_MRT
    oColour0 = float4(lFinalColour, lAlpha);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth );
#else
    return float4(lFinalColour, lAlpha);
#endif
}
technique Default
{
    pass p0
    { 
  CULLMODE = none;
  AlphaRef = 0;
  AlphaFunc = GREATER;
  AlphaTestEnable = True;
  AlphaBlendEnable = True;
     SrcBlend = SrcAlpha; 
      DestBlend = InvSrcAlpha; 
  VertexShader = compile vs_3_0 VS_Main();
  PixelShader  = compile ps_3_0 PS_Main();
    }
}
struct vertexInputZOnly {
    float3 position    : POSITION;
};
struct vertexOutputZOnly {
    float4 hPosition   : POSITION;
#ifdef D_MSAA_ENABLED
    float2 hPositionDepthCopy   : TEXCOORD0;
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
    return OUT;
}
float4 PS_Main_ZOnly( vertexOutputZOnly IN ): COLOR
{
#ifdef D_MSAA_ENABLED
#ifdef D_ADD_STENCIL
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y ) + 2.0f;
#else
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
#endif
    return lfDepth.xxxx;
#else
    return float4(1,1,1,1);
#endif
}
technique ZOnlyOpaqueSingleSided
<
  string sharedName="ZOnlyOpaqueSingleSided";
>
{
    pass p0
    {  
        CullMode = cw;
#ifndef D_MSAA_ENABLED
        ColorWriteEnable = 0;
#endif
  VertexShader = compile vs_3_0 VS_Main_ZOnly();
  PixelShader  = compile ps_3_0 PS_Main_ZOnly();
    }
}



