#include "../Include/Platform.fxh"
#include "../Include/Transform.fxh"
#include "../Include/Shadow.fxh"
#include "../Include/Fog.fxh"
#include "../Include/Irradiance.fxh"
#include "../Include/DepthEncode.fxh"
#ifdef D_OREN_NAYAR
#include "../Include/OrenNayar.fxh"
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
float4   Time    : time
<
 string scope = "global";
>;
float3      SkyReflectionColour
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
    float UIMax = 200.0;
    float UIStep = 1.0;
    string UIName = "specular power";
> = 100.0;
float Specularity
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 1.0;
    float UIMax = 10.0;
    float UIStep = 0.1;
    string UIName = "Specularity";
> = 1.5;
texture2D WaveNormalMap : diffuse
<
 string scope = "material";
 string purpose = "none";
>;
texture2D RiverFloorTexture
<
 string scope = "material";
 string purpose = "none";
>;
textureCUBE ReflectionTexture
<
 string scope = "material";
 string purpose = "none";
 string textureType = "CUBE";
>;
SAMPLER_2D(WaveNormalMapSampler, 0, 
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <WaveNormalMap>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
SAMPLER_2D(RiverFloorTextureSampler, 1, 
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <RiverFloorTexture>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
SAMPLER_CUBE(ReflectionTextureSampler, 2, 
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
};
struct vertexOutput {
    float4 hPosition    : POSITION;
    float2 texCoordDiffuse   : TEXCOORD0;
    float4 texCoordWater   : TEXCOORD1;
    float4 EyeToVertexAndFog  : TEXCOORD2;
    SHADOWMAP_INTERPOLATORS2( 3,4 ) 
    float4 IndirectColourAndKey  : TEXCOORD5;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD6;
#endif
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    float3 WorldNormal              : TEXCOORD7;
#endif
};
struct vertexOutputLod1 {
    float4 hPosition    : POSITION;
    float2 texCoordDiffuse   : TEXCOORD0;
    float4 texCoordWater   : TEXCOORD1;
    float4 EyeToVertexAndFog  : TEXCOORD2;
 float4 LightSpacePosFar         : TEXCOORD3;
    float4 IndirectColourAndKey  : TEXCOORD4;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD5;
#endif
};
vertexOutput VS_Main(vertexInput IN) 
{
    vertexOutput OUT;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    float3 WorldSpaceNormal = float3(0.0f,1.0f,0.0f);
    float2 BaseTexCoord = WorldSpacePosition.xz * (1.0 / 50.0f);
    OUT.texCoordDiffuse = BaseTexCoord;
 OUT.texCoordWater.xy = BaseTexCoord + (Time.x / 50.0);
 OUT.texCoordWater.zw = BaseTexCoord - (Time.x / 39.0) + float2(0.432, 0.123);
    float  lrDirectionalLightIntensity = dot( WorldSpaceNormal, -KeyLightDirection );
    float3 lIrradiance = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.xyz = lIrradiance;
    OUT.IndirectColourAndKey.w   = lrDirectionalLightIntensity; 
    float3 lEyeToVertex = ViewPosition.xyz - WorldSpacePosition;
    OUT.EyeToVertexAndFog.xyz = lEyeToVertex;
    OUT.EyeToVertexAndFog.w = CalculateScattering( length( lEyeToVertex ) );
    CALC_SHADOWMAP_INTERPOLATORS3( WorldSpacePosition, OUT.hPosition.w );    
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    OUT.WorldNormal = WorldSpaceNormal;
#endif
    return OUT;
}
#ifdef D_MRT
void PS_Main( in  vertexOutput IN,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 PS_Main( vertexOutput IN ) : COLOR
#endif
{
 float3 riverfloorTexture = tex2D(RiverFloorTextureSampler, IN.texCoordDiffuse);
 float2 normalTexture2dA;
 float2 normalTexture2dB;
 normalTexture2dA = tex2D( WaveNormalMapSampler, IN.texCoordWater.xy).ga;
 normalTexture2dB = tex2D( WaveNormalMapSampler, IN.texCoordWater.zw).ga;
 float2 normalMap2d = lerp( normalTexture2dA, normalTexture2dB, 0.5f );
 normalMap2d = ((normalMap2d * 2.0f) - 1.0f);
 float3 normalMap3d;
 normalMap3d.xz = normalMap2d;
 normalMap3d.y  = 1.0 - dot(normalMap2d, normalMap2d);
 normalMap3d = normalize(normalMap3d);
 float3 lLightDirection    = (float3)-KeyLightDirection;
 float3 lNormalisedEyeToVertex = normalize( (float3)IN.EyeToVertexAndFog.xyz );
 float  lrSpecularPower    = (float)SpecularPower;
 float3 WorldSpaceNormal = normalMap3d;
 float3 lReflection = ( WorldSpaceNormal * ( 2.0f * dot( lNormalisedEyeToVertex, WorldSpaceNormal ) ) ) - lNormalisedEyeToVertex;
 float  lrRdotL = saturate( dot( lReflection, lLightDirection ) );
 float3 lSpecularColour = float3(KeyLightSpecularColour) * ( Specularity * pow( lrRdotL, lrSpecularPower ) );
 float3 reflectionTexture = texCUBE(ReflectionTextureSampler, lReflection);
 float fresnelValue = saturate( dot( lNormalisedEyeToVertex, WorldSpaceNormal ) );
 float3 diffuseTexture = lerp(reflectionTexture, riverfloorTexture, fresnelValue);
    float lShadowModulation = CALC_SHADOW_FACTOR_3( (float)IN.IndirectColourAndKey.w );
#ifdef D_OREN_NAYAR
    float  lDirectLightFactor   = ComputeOrenNayarDiffuse( normalize(IN.WorldNormal), (float3)-KeyLightDirection, lNormalisedEyeToVertex, 0.1 ) * lShadowModulation;
#else
    float  lDirectLightFactor   = saturate( (float)IN.IndirectColourAndKey.w ) * lShadowModulation;
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor ) * float3(materialDiffuse.xyz);
    float3 lFinalColour         = (diffuseTexture * lLightColour) + (lSpecularColour * lShadowModulation);
    lFinalColour = lerp( lFinalColour.rgb, float3(FogColourPlusWhiteLevel.rgb), float(IN.EyeToVertexAndFog.w) );
    float lDistToHorizon = (10000.0f*10000.0f) - dot( IN.EyeToVertexAndFog.xyz, IN.EyeToVertexAndFog.xyz );
    float  lhHorizonFog   = saturate( lDistToHorizon * ( 1.0f / (10000.0f*10000.0f) ) );
    lFinalColour = lerp( float3(SkyReflectionColour.rgb), lFinalColour.rgb, lhHorizonFog );
#ifdef D_MRT
    oColour0 = float4(lFinalColour, 1);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth );
#else
    return float4(lFinalColour, 1);
#endif
}
technique Default
{
    pass p0
    {  
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
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    return lfDepth.xxxx;
#else
    return float4(1,1,1,1);
#endif
}
technique ZOnlyNull
<
     string sharedName="ZOnlyNull";
>
{
    pass p0
    {  
        ZWriteEnable = False;
#ifndef D_MSAA_ENABLED
        ColorWriteEnable = 0;
#endif
  VertexShader = compile vs_3_0 VS_Main_ZOnly();
  PixelShader  = compile ps_3_0 PS_Main_ZOnly();
    }
}



