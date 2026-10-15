#include "../Include/Platform.fxh"
#include "../Include/Transform.fxh"
#define SHADOW_APPLY_FADE_ROAD
#include "../Include/Shadow.fxh"
#include "../Include/Fog.fxh"
#include "../Include/Irradiance.fxh"
#include "../Include/DepthEncode.fxh"
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
texture2D baseMap : diffuse
<
 string scope   = "material";
 string purpose = "none";
>;
texture2D detailMap
<
 string scope   = "material";
 string purpose = "none";
>;
SAMPLER_2D(baseMapSampler, 0,
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
struct vertexInput {
    float3 position    : POSITION;
    float3 normal    : NORMAL;
    float2 texCoordDiffuse  : TEXCOORD0;
};
struct vertexOutput {
    float4 hPosition    : POSITION;
    float4 texCoordDiffuse   : TEXCOORD0;
 float4 ReflectionVectorAndFog : TEXCOORD1;
    SHADOWMAP_INTERPOLATORS2( 2,3 ) 
    float4 IndirectColourAndKey  : TEXCOORD4;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD5;
#endif
};
struct vertexOutputLod1 {
    float4 hPosition    : POSITION;
    float4 texCoordDiffuse   : TEXCOORD0;
 float4 ReflectionVectorAndFog : TEXCOORD1;
 float4 LightSpacePosFar   : TEXCOORD2;
    float4 IndirectColourAndKey  : TEXCOORD3;
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
    OUT.texCoordDiffuse.xy = IN.texCoordDiffuse;
    OUT.texCoordDiffuse.zw = IN.position.xz;
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
 float4 lUV = IN.texCoordDiffuse;
#ifdef D_VERSION_16
 float  detailsT;
 if (gbDisableAniso) { detailsT = tex2Dbias(detailMapSampler, float4(lUV.zw, 0, 0)).r; }
 else { detailsT = tex2D(detailMapSampler, lUV.zw).r; }
#else
 float  detailsT = tex2D(detailMapSampler, lUV.zw).r;
#endif
 float3 baseT    = tex2D(baseMapSampler, lUV.xy).rgb * (float3)materialDiffuse;
 detailsT *= (float)2.0;
 float3 diffuseTexture = baseT * detailsT;
    float3 lLightDirection = (float3)-KeyLightDirection;
    float3 lReflectionVector = (float3)IN.ReflectionVectorAndFog.xyz;
    float  lrSpecularPower = (float)SpecularPower;
    float3 lReflection = normalize( lReflectionVector );
    float  lrRdotL = saturate( dot( lReflection, lLightDirection ) );
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( Specularity * pow( lrRdotL, lrSpecularPower ) );
    lSpecularColour *= max(diffuseTexture.r, diffuseTexture.g);
    float lShadowModulation = CALC_SHADOW_FACTOR_3( 1.0f );
    float  lDirectLightFactor   = saturate( (float)IN.IndirectColourAndKey.w ) * lShadowModulation;
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor );
    float3 lFinalColour         = (diffuseTexture * lLightColour) + (lSpecularColour * lShadowModulation);
    lFinalColour = lerp( lFinalColour, (float3)FogColourPlusWhiteLevel.rgb, float(IN.ReflectionVectorAndFog.w) );
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

