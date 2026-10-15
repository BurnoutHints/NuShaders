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
#ifdef D_GGX_SPECULAR
#include "../Include/GGX.fxh"
#endif
float3   ViewPosition    : cameraposition
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
float4x4  worldViewProj    : WorldViewProjection
<
 string scope = "object";
>;
float4x4  world     : World
<
 string scope = "object";
>;
float4 materialDiffuse
<
 string scope = "material";
    string UIWidget = "rgba";
> = {1.0f, 1.0f, 1.0f, 1.0f};
float SpecularPower
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 1.0;
    float UIMax = 100.0;
    float UIStep = 1.0;
    string UIName = "specular power";
> = 12.0;
float Specularity
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 1.0;
    float UIMax = 5.0;
    float UIStep = 0.1;
    string UIName = "Specularity";
> = 1.5;
texture2D DiffuseTexture : diffuse
<
 string scope = "material";
 string purpose = "none";
>;
texture2D SpecularTexture
<
 string scope = "material";
 string purpose = "none";
>;
texture2D BlendTexture
<
 string scope = "material";
 string purpose = "none";
>;
SAMPLER_2D(DiffuseTextureSampler, 0, 
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <DiffuseTexture>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
SAMPLER_2D(SpecularTextureSampler, 1, 
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <SpecularTexture>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
SAMPLER_2D(BlendTextureSampler, 2, 
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <BlendTexture>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
struct vertexInput {
    float3 position    : POSITION;
    float3 normal    : NORMAL;
    float2 texCoordDiffuse  : TEXCOORD0;
};
struct vertexOutput {
    float4 hPosition    : POSITION;
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
    float4 hPosition    : POSITION;
    float2 texCoordDiffuse   : TEXCOORD0;
 float4 ReflectionVectorAndFog : TEXCOORD1;
 float4 LightSpacePosFar         : TEXCOORD2;
    float4 IndirectColourAndKey  : TEXCOORD3;
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
    float3 lIrradiance = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.xyz = lIrradiance;
    float  lrDirectionalLightIntensity = dot( WorldSpaceNormal, -KeyLightDirection );
    OUT.IndirectColourAndKey.w = lrDirectionalLightIntensity;
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
              in  float lfFace : VFACE,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 PS_Main( vertexOutput IN, float lfFace : VFACE ) : COLOR
#endif
{
 float4 diffuseTexture = tex2D( DiffuseTextureSampler, IN.texCoordDiffuse );
 ALPHA_TEST( diffuseTexture.a );
 float  specularTexture = tex2D( SpecularTextureSampler, IN.texCoordDiffuse ).g;
 float  blendTexture = tex2D( BlendTextureSampler, IN.texCoordDiffuse ).g;
 diffuseTexture.xyz = lerp(diffuseTexture.xyz, diffuseTexture.xyz * float3(materialDiffuse.xyz), blendTexture);
    float3 lLightDirection = (float3)-KeyLightDirection;
    float3 lReflectionVector = (float3)IN.ReflectionVectorAndFog.xyz;
    float  lrSpecularPower = (float)SpecularPower;
    float3 lReflection = normalize( lReflectionVector );
    float  lrRdotL = saturate( dot( lReflection, lLightDirection ) );
#ifdef D_GGX_SPECULAR
    float  lGGXRoughness = sqrt( 2.0 / ( SpecularPower + 2.0 ) );
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( Specularity * ComputeGGXSpecular( normalize(IN.WorldNormal) * (lfFace < 0.0 ? 1.0 : -1.0), (float3)-KeyLightDirection, normalize(IN.ViewDirection), lGGXRoughness, 0.04 ) );
#else
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( Specularity * pow( lrRdotL, lrSpecularPower ) );
#endif
    lSpecularColour *= specularTexture;
 float  lNormalDotLight  = (lfFace<0) ? (float)IN.IndirectColourAndKey.w : (float)-IN.IndirectColourAndKey.w;
    float lShadowModulation = CALC_SHADOW_FACTOR_3( lNormalDotLight  );
#ifdef D_OREN_NAYAR
    float  lDirectLightFactor   = ComputeOrenNayarDiffuseFromSpecMap( normalize(IN.WorldNormal) * (lfFace < 0.0 ? 1.0 : -1.0), (float3)-KeyLightDirection, normalize(IN.ViewDirection), specularTexture ) * lShadowModulation;
#else
    float  lDirectLightFactor   = saturate( lNormalDotLight * lShadowModulation );
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor );
    float3 lFinalColour         = (diffuseTexture * lLightColour) + (lSpecularColour * lShadowModulation);
    lFinalColour = lerp( lFinalColour.rgb, float3(FogColourPlusWhiteLevel.rgb), float(IN.ReflectionVectorAndFog.w) );
#ifdef D_MRT
    oColour0 = float4(lFinalColour, diffuseTexture.a);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth );
#else
    return float4(lFinalColour, diffuseTexture.a);
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
  AlphaBlendEnable = False;
  VertexShader = compile vs_3_0 VS_Main();
  PixelShader  = compile ps_3_0 PS_Main();
    }
}
struct vertexInputZOnly {
    float3 position    : POSITION;
    float2 texCoordDiffuse  : TEXCOORD0;
};
struct vertexOutputZOnly {
    float4 hPosition   : POSITION;
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
float4 PS_Main_ZOnly( vertexOutputZOnly IN ): COLOR
{
 float4 lDiffuse = tex2D( DiffuseTextureSampler, IN.texCoordDiffuse);
 clip( lDiffuse.a - ALPHA_TEST_THRESHOLD );
#ifdef D_MSAA_ENABLED
    float4 lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    lfDepth.w = lDiffuse.a;
    return lfDepth;
#else
 return lDiffuse; 
#endif
}
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






