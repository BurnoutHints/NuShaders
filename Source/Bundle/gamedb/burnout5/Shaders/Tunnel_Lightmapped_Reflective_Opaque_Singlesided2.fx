#include "../Include/Platform.fxh"
#include "../Include/Transform.fxh"
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
    float UIMax = 2.0;
    float UIStep = 0.01;
> = 1.0;
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
textureCUBE ReflectionTexture
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
    float2 texCoordDiffuseAndFog : TEXCOORD0;
    float2 lightmapUV    : TEXCOORD1;
 float4 ReflectionVectorAndFog : TEXCOORD2;
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
    float2 texCoordDiffuseAndFog : TEXCOORD0;
    float2 lightmapUV    : TEXCOORD1;
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
    OUT.texCoordDiffuseAndFog.xy = IN.map1;
    OUT.lightmapUV.xy = IN.atlas;
    CALC_SHADOWMAP_INTERPOLATORS3( WorldSpacePosition, OUT.hPosition.w );    
    OUT.IndirectColourAndKey.xyz = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.w   = dot( WorldSpaceNormal, -KeyLightDirection ); 
    float3 lEyeToVertex = ViewPosition.xyz - WorldSpacePosition;
    float3 lReflection  = ( WorldSpaceNormal * ( 2.0f * dot( lEyeToVertex, WorldSpaceNormal ) ) ) - lEyeToVertex;
    OUT.ReflectionVectorAndFog.xyz = lReflection;
    OUT.ReflectionVectorAndFog.w = CalculateScattering( length( lEyeToVertex ) );
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
 float4 diffuseTexture  = tex2D( DiffuseTextureSampler, IN.texCoordDiffuseAndFog );
 float4 specularTexture = tex2D( SpecularTextureSampler, IN.texCoordDiffuseAndFog );
 float3 lightmapTexture = tex2D( LightmapTextureSampler, IN.lightmapUV.xy ).rgb;
float lf2xWhiteLevel = (float)FogColourPlusWhiteLevel.w + (float)FogColourPlusWhiteLevel.w;
 lightmapTexture *= lf2xWhiteLevel;
    float3 lLightDirection = (float3)-KeyLightDirection;
    float3 lReflectionVector = (float3)IN.ReflectionVectorAndFog.xyz;
    float  lrSpecularPower = (float)SpecularPower;
    float3 lReflection = normalize( lReflectionVector );
    float  lrRdotL = max( dot( lReflection, lLightDirection ), 0.0f );
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    // Slots are full, so derive the view direction from the reflection vector and
    // normal instead of a dedicated interpolator:  E = 2(N·R)N - R,  V = normalize(E).
    float3 lReconN       = normalize( IN.WorldNormal );
    float3 lReconViewDir = normalize( 2.0 * dot( lReconN, lReflectionVector ) * lReconN - lReflectionVector );
#endif
#ifdef D_GGX_SPECULAR
    float  lGGXRoughness = sqrt( 2.0 / ( SpecularPower + 2.0 ) );
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( Specularity * ComputeGGXSpecular( lReconN, (float3)-KeyLightDirection, lReconViewDir, lGGXRoughness, 0.04 ) );
#else
    float4 lSpecularColour = float4(KeyLightSpecularColour * ( Specularity * pow( lrRdotL, lrSpecularPower ) ), 0.0);
#endif
    lSpecularColour *= specularTexture.y;
 float4 reflectionTexture = texCUBE(ReflectionTextureSampler, lReflection);
 reflectionTexture = float4(reflectionTexture.xyz * reflectStrength, reflectionTexture.w);
 diffuseTexture = lerp(diffuseTexture, reflectionTexture, specularTexture.x);
    float lShadowModulation = CALC_SHADOW_FACTOR_3( (float)IN.IndirectColourAndKey.w );
#ifdef D_OREN_NAYAR
    float  lDirectLightFactor   = ComputeOrenNayarDiffuseFromSpecMap( lReconN, (float3)-KeyLightDirection, lReconViewDir, specularTexture ) * lShadowModulation;
#else
    float  lDirectLightFactor   = saturate( (float)IN.IndirectColourAndKey.w ) * lShadowModulation;
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor ) * float3(materialDiffuse.xyz);
    float3 lLightOrLightmap     = max( lLightColour, lightmapTexture );
    float3 lFinalColour         = (diffuseTexture * lLightOrLightmap) + (lSpecularColour);
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





