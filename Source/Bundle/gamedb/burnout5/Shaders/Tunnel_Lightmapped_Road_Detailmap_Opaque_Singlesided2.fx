#include "../Include/Platform.fxh"
#include "../Include/Transform.fxh"
#include "../Include/Shadow.fxh"
#include "../Include/Fog.fxh"
#include "../Include/Irradiance.fxh"
#include "../Include/DepthEncode.fxh"
#include "../Include/Constants.fxh"
float3   ViewPosition : cameraposition
<
 string scope = "global";
>;
#ifdef D_VERSION_16
bool gbDisableAniso : register(b0);
#endif
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
float paintVariation
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.0;
    float UIMax = 1.0;
    float UIStep = 0.05;
    string UIName = "paint Variation";
> = 0.0;
float paintAlpha
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.0;
    float UIMax = 10.0;
    float UIStep = 0.1;
    string UIName = "paint Alpha";
> = 1.3;
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
    float UIMin = 0.0;
    float UIMax = 5.0;
    float UIStep = 0.1;
    string UIName = "Specularity";
> = 1.5;
float detailMultiplier
<
    string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.1;
    float UIMax = 32.0;
    float UIStep = 0.1;
    string UIName = "detail multiplier";
> = 4.5;
float lineUMultiplier
<
    string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.1;
    float UIMax = 32.0;
    float UIStep = 0.1;
    string UIName = "line U multiplier";
> = 4.0f;
float lineVMultiplier
<
    string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.1;
    float UIMax = 32.0;
    float UIStep = 0.1;
    string UIName = "line V multiplier";
> = 1.0f;
float lineDetailControl
<
    string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.0;
    float UIMax = 1.0;
    float UIStep = 0.1;
    string UIName = "line detail amount";
> = 0.5f;
texture2D lineMap : diffuse
<
 string scope   = "material";
 string purpose = "none";
>;
texture2D detailMap
<
 string scope   = "material";
 string purpose = "none";
>;
texture2D baseMap
<
 string scope   = "material";
 string purpose = "none";
>;
SAMPLER_2D(lineMapSampler, 0, 
<
 string scope   = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <lineMap>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
SAMPLER_2D(detailMapSampler, 1,
<
 string scope   = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <detailMap>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
SAMPLER_2D(baseMapSampler, 2,
<
 string scope   = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <baseMap>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
texture2D LightmapTexture
<
 string scope = "material";
>;
SAMPLER_2D(LightmapTextureSampler, 3,
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <LightmapTexture>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
struct vertexInput {
    float3 position    : POSITION;
    float3 normal    : NORMAL;
    float2 map1     : TEXCOORD0;
    float2 atlas    : TEXCOORD1;
};
struct vertexOutput {
    float4 hPosition    : POSITION;
    float4 texCoordDiffuseAndLM     : TEXCOORD0;
    float4 texCoordDetailAndLine    : TEXCOORD1;
 float4 ReflectionVectorAndFog : TEXCOORD2;
    SHADOWMAP_INTERPOLATORS2( 3,4 ) 
    float4 IndirectColourAndKey  : TEXCOORD5;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD6;
#endif
};
struct vertexOutputLod1 {
    float4 hPosition    : POSITION;
    float4 texCoordDiffuseAndLM     : TEXCOORD0;
    float4 texCoordDetailAndLine    : TEXCOORD1;
 float4 ReflectionVectorAndFog : TEXCOORD2;
 float4 LightSpacePosFar         : TEXCOORD3;
    float4 IndirectColourAndKey  : TEXCOORD4;
};
vertexOutput VS_Main( vertexInput IN ) 
{
    vertexOutput OUT;
     float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;           
    float3 WorldSpaceNormal  = normalize( mul( IN.normal, (float3x3)world ) );             
    OUT.hPosition    = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.texCoordDiffuseAndLM.xy = IN.map1;
    OUT.texCoordDiffuseAndLM.zw = IN.atlas;
    OUT.texCoordDetailAndLine.xy = IN.position.xz * (1.0f / 4.5f) * detailMultiplier;
    OUT.texCoordDetailAndLine.z  = IN.map1.x * lineUMultiplier;
    OUT.texCoordDetailAndLine.w  = IN.map1.y * lineVMultiplier;
    OUT.IndirectColourAndKey.xyz = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.w = dot( WorldSpaceNormal, -KeyLightDirection );
    float3 lEyeToVertex = ViewPosition.xyz - WorldSpacePosition;
    float3 lReflection  = ( WorldSpaceNormal * ( 2.0f * dot( lEyeToVertex, WorldSpaceNormal ) ) ) - lEyeToVertex;
    OUT.ReflectionVectorAndFog.xyz = lReflection;
    OUT.ReflectionVectorAndFog.w = CalculateScattering( length( lEyeToVertex ) );
    CALC_SHADOWMAP_INTERPOLATORS3( WorldSpacePosition, OUT.hPosition.w );    
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
     float4 lBaseAndLMUV     = IN.texCoordDiffuseAndLM;
    float4 lDetailAndLineUV = IN.texCoordDetailAndLine;
#ifdef D_VERSION_16
 float  detailsT;
 if (gbDisableAniso) { detailsT = tex2Dbias(detailMapSampler, float4(lDetailAndLineUV.xy, 0, 0)).r * 2.0; }
 else { detailsT = tex2D(detailMapSampler, lDetailAndLineUV.xy).r * 2.0; }
#else
 float  detailsT = tex2D(detailMapSampler, lDetailAndLineUV.xy).r * 2.0;
#endif
 float3 baseT    = tex2D(baseMapSampler, lBaseAndLMUV.xy) * (float3)materialDiffuse;
 float3 lines    = tex2D(lineMapSampler, lDetailAndLineUV.zw).rgb;
 float3 lightmapTexture = tex2D( LightmapTextureSampler, lBaseAndLMUV.zw ).rgb;
    float lf2xWhiteLevel = (float)FogColourPlusWhiteLevel.w + (float)FogColourPlusWhiteLevel.w;
 lightmapTexture *= lf2xWhiteLevel;
 float  lineDetail = lerp( float(1.0), detailsT, (float)lineDetailControl );
 lines *= lineDetail;
 float3 asphalt = baseT * detailsT;
 float lineMask = lines.g;
 lineMask -= paintVariation;
 lineMask *= paintAlpha;
 lineMask = saturate( lineMask );
 float3 diffuseTexture = lerp(asphalt, lines, lineMask);
    float3 lLightDirection = (float3)-KeyLightDirection;
    float3 lReflectionVector = (float3)IN.ReflectionVectorAndFog.xyz;
    float  lrSpecularPower = (float)SpecularPower;
    float3 lReflection = normalize( lReflectionVector );
    float  lrRdotL = saturate( dot( lReflection, lLightDirection ) );
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( (float)Specularity * pow( lrRdotL, lrSpecularPower ) );
    float lTextureLuminance = dot(diffuseTexture, k_luminanceMapping);
    lSpecularColour  *= lTextureLuminance;
    float lShadowModulation = CALC_SHADOW_FACTOR_3( (float)IN.IndirectColourAndKey.w );
    float  lDirectLightFactor   = saturate( (float)IN.IndirectColourAndKey.w ) * lShadowModulation;
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor );
    float3 lLightOrLightmap     = max( lLightColour, lightmapTexture );
    float3 lFinalColour         = (diffuseTexture * lLightOrLightmap) + (lSpecularColour * lShadowModulation);
    lFinalColour = lerp( lFinalColour, float3(FogColourPlusWhiteLevel.rgb), float(IN.ReflectionVectorAndFog.w) );
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

