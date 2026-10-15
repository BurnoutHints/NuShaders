#include "../Include/Platform.fxh"
#include "../Include/Transform.fxh"
#define SHADOW_APPLY_Z_BIAS
#define SHADOW_Z_BIAS_VALUE 0.0001
#include "../Include/Shadow.fxh"
#include "../Include/Fog.fxh"
#include "../Include/Irradiance.fxh"
#include "../Include/DepthEncode.fxh"
#include "../Include/Constants.fxh"
float3   KeyLightColour
<
 string scope = "global";
>;
float3      KeyLightDirection 
<
    string scope = "global";
>;
float3      ViewPosition : Direction
<
    string scope = "global";
>;
float3      KeyLightSpecularColour
<
    string scope = "global";
>;
float3      KeyLightClampedColour
<
    string scope = "global";
>;
float4x4    worldViewProj : WorldViewProjection
<
    string scope = "object";
>;
float4x4    world : World
<
    string scope = "object";
>;
float4      g_verletOffsets[ 128 ]
<
    string scope = "object";
>;
#define NORMAL_MAP_SWAP_TB
#include "../Include/NormalMapping.fxh"
#include "../Include/Fresnel.fxh"
#include "../Include/Utility.fxh"
#define VEHICLE_USE_SCRATCHES
#include "../Include/VehicleDeformation.fxh"
float4      g_damageConstants   
<
    string scope = "object";
> = float4( 0.0, 0.0, 0.0, 0.0 );
float3 g_paintColour : Diffuse
<
    string scope = "object";
> = float3( 1.0, 1.0, 1.0 );
float4      g_PerVehicleFog
<
    string scope = "object";
> = float4( 0.0, 0.0, 0.0, 0.0 );
float4  g_fresnelRanges 
<
    string scope = "material";
    string UIName = "Fresnel Ranges";
> = float4( 1.0, 2.0, 0.5, 1.0 );
float4  g_scratchFresnelRanges
<
    string scope = "material";
    string UIName = "Scratch Fresnel Ranges";
> = float4( 0.0, 1.0, 0.0, 0.5 );
float4  g_reflectConstants
<
    string scope = "material";
    string UIName = "Reflection Constants";
> = float4( 32.0, 1.0, 1.0, 1.0 );
float4  g_specularConstants
<
    string scope = "material";
    string UIName = "Specular Constants";
> = float4( 0.996, 2.0, 0.5, 1.0 );
float4  materialDiffuse
<
    string scope = "material";
    string UIWidget = "rgba";
> = float4( 1.0 , 1.0 , 1.0 , 1.0 );
textureCUBE ReflectionTexture : Environment
<
    string scope = "persistent";
  string textureType = "Cube";
    string purpose = "environmentMap";
>;
SAMPLER_CUBE(ReflectionTextureSampler, 13,
<
    string scope = "persistent";
    string purpose = "environmentMap";
> = sampler_state
{
    Texture = <ReflectionTexture>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
});
texture NormalTexture
<
    string scope = "material";
>;
SAMPLER_2D_UNTYPED(NormalTextureSampler, 2,
<
    string scope = "material";
> = sampler_state
{
    Texture = <NormalTexture>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
});
struct DamagedInput
{
    float3  position                : POSITION;
        float3  normal                  : NORMAL;
        float3  tangent                 : TANGENT;
    float2  texCoordDiffuse         : TEXCOORD0;
    BONE_INDICES4  boneIndices             : BLENDINDICES;
    float3  boneWeights             : BLENDWEIGHT;
};
struct DamagedOutput
{
    float4 hPosition                : POSITION;
    float3 vertToEyeVector          : TEXCOORD0;
    float3 worldNormal              : TEXCOORD1;
    float4 texCoords                : TEXCOORD2;
    SHADOWMAP_INTERPOLATORS2( 3,4 )
    float3 indirectColour           : TEXCOORD5;
    float3 worldTangent             : TEXCOORD6;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD7;
#endif
};
DamagedOutput
DamagedVS( DamagedInput IN )
{
    DamagedOutput OUT;
    float3 verletOffset = VerletOffset( (int2)IN.boneIndices.xy, IN.boneWeights.xy);
    float deformation = saturate( length( verletOffset.xyz ) * 3.0 );
    OUT.texCoords.zw = 0.0;
    IN.position += verletOffset.xyz;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.worldNormal = normalize( mul( IN.normal, (float3x3)world ) );
    OUT.worldTangent = normalize( mul( IN.tangent, (float3x3)world ) );
    OUT.texCoords.xy = IN.texCoordDiffuse;
    OUT.indirectColour.xyz = ComputeIrradianceFast( OUT.worldNormal );
    OUT.vertToEyeVector.xyz = (ViewPosition - WorldSpacePosition);
 float3 objectCentreWorldSpace = world[3].xyz;
    float objectCentreViewSpaceDepth = GetViewSpaceDepthFromWorldPosition( objectCentreWorldSpace );
    CALC_SHADOWMAP_INTERPOLATORS2_SELECT_VS( WorldSpacePosition, OUT.hPosition.w, objectCentreViewSpaceDepth );
    return OUT;
}
#ifdef D_MRT
void DamagedPS( in  DamagedOutput IN,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 DamagedPS( DamagedOutput IN ) : COLOR
#endif
{
    float3   keyLightDirection = float3( -KeyLightDirection );
    float4   normalTex = tex2D( NormalTextureSampler, IN.texCoords.xy );
    float3   binormal = cross( IN.worldTangent, IN.worldNormal );
    float3   normal = DecodeNormalMap( normalTex.ga, (float3)IN.worldNormal, (float3)IN.worldTangent, binormal, (float)2.0 );
    float    lightDotNormal       = saturate( dot( normal, keyLightDirection ) );
 float3   view = normalize( float3( IN.vertToEyeVector.xyz ) );
  float3 materialColour = (float3)g_paintColour;
    float3   baseColour = materialColour;
    float4   fresnelRanges = (float4)g_fresnelRanges;
    float alpha = 1.0;
    float3   reflectedView;
    float2   fresnelValues;
    CalculateFresnel( normal, view, fresnelRanges, (float)g_reflectConstants.y, reflectedView, fresnelValues );
    float3   reflectTex = (float3)texCUBE( ReflectionTextureSampler, reflectedView ).rgb;
        reflectTex = reflectTex * saturate( float(FogColourPlusWhiteLevel.w) * float(1000.0) );
    float    reflectDotLight = saturate( dot( reflectedView, keyLightDirection ) );
    float    specularIntensity = pow( reflectDotLight, (float)g_reflectConstants.x );
    float    hotSpotIntensity = 0.0;
    float3   specularLightColour = (float3)KeyLightSpecularColour.rgb;
    float3   specularColour = ( specularLightColour * specularIntensity + hotSpotIntensity ) * fresnelValues.x;
    float    ambientOcclusion = normalTex.r;
    float shadowModulation = CALC_SHADOW_FACTOR_2_SELECT_VEHICLE( lightDotNormal );
    float illumination = lightDotNormal * shadowModulation;
    float3   lightColour  = ( (float3)IN.indirectColour.rgb + (float3)KeyLightClampedColour.rgb * illumination ) * ambientOcclusion;
    float    lightIntensity = saturate( dot( lightColour, k_luminanceMapping ) / (float)FogColourPlusWhiteLevel.w );
    float3   diffuseColour = baseColour * lightColour;
    float3   finalColour;
    float    reflectIntensity = (fresnelValues.y * ambientOcclusion);
    float    lReflectionShadowModulation = saturate(shadowModulation + float(0.9));
    reflectIntensity *= lReflectionShadowModulation;
    float3   lBlendedDiffuseAndReflection = lerp(diffuseColour, reflectTex, reflectIntensity);
    finalColour = lBlendedDiffuseAndReflection + ( specularColour * shadowModulation );
    finalColour = ( finalColour * float( g_PerVehicleFog.a ) ) + float3(g_PerVehicleFog.rgb);
#ifdef D_MRT
    oColour0 = float4(finalColour, alpha);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth ) + 2.0f;
#else
    return float4(finalColour, alpha);
#endif
}
technique Damaged
{
    pass p0
    {
        AlphaBlendEnable = False;
        AlphaFunc = ALWAYS;
        AlphaTestEnable = False;
        SrcBlend = One;
        DestBlend = Zero;
        VertexShader = compile vs_3_0 DamagedVS();
        PixelShader  = compile ps_3_0 DamagedPS();
    }
}
struct DefaultInput
{
    float3  position                : POSITION;
        float3  normal                  : NORMAL;
        float3  tangent                 : TANGENT;
    float2  texCoordDiffuse         : TEXCOORD0;
};
struct DefaultOutput
{
    float4 hPosition                : POSITION;
    float3 vertToEyeVector          : TEXCOORD0;
    float3 worldNormal              : TEXCOORD1;
    float4 texCoords                : TEXCOORD2;
    SHADOWMAP_INTERPOLATORS2( 3,4 )
    float3 indirectColour           : TEXCOORD5;
    float3 worldTangent             : TEXCOORD6;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD7;
#endif
};
DefaultOutput
DefaultVS( DefaultInput IN )
{
    DefaultOutput OUT;
    float3 verletOffset = 0.0;
    float deformation = 0.0;
    OUT.texCoords.zw = 0.0;
    IN.position += verletOffset.xyz;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.worldNormal = normalize( mul( IN.normal, (float3x3)world ) );
    OUT.worldTangent = normalize( mul( IN.tangent, (float3x3)world ) );
    OUT.texCoords.xy = IN.texCoordDiffuse;
    OUT.indirectColour.xyz = ComputeIrradianceFast( OUT.worldNormal );
    OUT.vertToEyeVector.xyz = (ViewPosition - WorldSpacePosition);
 float3 objectCentreWorldSpace = world[3].xyz;
    float objectCentreViewSpaceDepth = GetViewSpaceDepthFromWorldPosition( objectCentreWorldSpace );
    CALC_SHADOWMAP_INTERPOLATORS2_SELECT_VS( WorldSpacePosition, OUT.hPosition.w, objectCentreViewSpaceDepth );
    return OUT;
}
#ifdef D_MRT
void DefaultPS( in  DefaultOutput IN,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 DefaultPS( DefaultOutput IN ) : COLOR
#endif
{
    float3   keyLightDirection = float3( -KeyLightDirection );
    float4   normalTex = tex2D( NormalTextureSampler, IN.texCoords.xy );
    float3   binormal = cross( IN.worldTangent, IN.worldNormal );
    float3   normal = DecodeNormalMap( normalTex.ga, (float3)IN.worldNormal, (float3)IN.worldTangent, binormal, (float)2.0 );
    float    lightDotNormal       = saturate( dot( normal, keyLightDirection ) );
 float3   view = normalize( float3( IN.vertToEyeVector.xyz ) );
  float3 materialColour = (float3)g_paintColour;
    float3   baseColour = materialColour;
    float4   fresnelRanges = (float4)g_fresnelRanges;
    float alpha = 1.0;
    float3   reflectedView;
    float2   fresnelValues;
    CalculateFresnel( normal, view, fresnelRanges, (float)g_reflectConstants.y, reflectedView, fresnelValues );
    float3   reflectTex = (float3)texCUBE( ReflectionTextureSampler, reflectedView ).rgb;
        reflectTex = reflectTex * saturate( float(FogColourPlusWhiteLevel.w) * float(1000.0) );
    float    reflectDotLight = saturate( dot( reflectedView, keyLightDirection ) );
    float    specularIntensity = pow( reflectDotLight, (float)g_reflectConstants.x );
    float    hotSpotIntensity = 0.0;
    float3   specularLightColour = (float3)KeyLightSpecularColour.rgb;
    float3   specularColour = ( specularLightColour * specularIntensity + hotSpotIntensity ) * fresnelValues.x;
    float    ambientOcclusion = normalTex.r;
    float shadowModulation = CALC_SHADOW_FACTOR_2_SELECT_VEHICLE( lightDotNormal );
    float illumination = lightDotNormal * shadowModulation;
    float3   lightColour  = ( (float3)IN.indirectColour.rgb + (float3)KeyLightClampedColour.rgb * illumination ) * ambientOcclusion;
    float    lightIntensity = saturate( dot( lightColour, k_luminanceMapping ) / (float)FogColourPlusWhiteLevel.w );
    float3   diffuseColour = baseColour * lightColour;
    float3   finalColour;
    float    reflectIntensity = (fresnelValues.y * ambientOcclusion);
    float    lReflectionShadowModulation = saturate(shadowModulation + float(0.9));
    reflectIntensity *= lReflectionShadowModulation;
    float3   lBlendedDiffuseAndReflection = lerp(diffuseColour, reflectTex, reflectIntensity);
    finalColour = lBlendedDiffuseAndReflection + ( specularColour * shadowModulation );
    finalColour = ( finalColour * float( g_PerVehicleFog.a ) ) + float3(g_PerVehicleFog.rgb);
#ifdef D_MRT
    oColour0 = float4(finalColour, alpha);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth ) + 2.0f;
#else
    return float4(finalColour, alpha);
#endif
}
technique Default
{
    pass p0
    {
        AlphaBlendEnable = False;
        AlphaFunc = ALWAYS;
        AlphaTestEnable = False;
        SrcBlend = One;
        DestBlend = Zero;
        VertexShader = compile vs_3_0 DefaultVS();
        PixelShader  = compile ps_3_0 DefaultPS();
    }
}
#ifdef D_MSAA_ENABLED
#define D_ADD_STENCIL
#endif
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
struct vertexInputZOnlySkinned {
    float3 position        : POSITION;
    BONE_INDICES4 boneIndices    : BLENDINDICES;
    float3 boneWeights    : BLENDWEIGHT;
};
struct vertexOutputZOnlySkinned {
    float4 hPosition       : POSITION;
#ifdef D_MSAA_ENABLED
    float2 hPositionDepthCopy       : TEXCOORD0;
#endif
};
vertexOutputZOnlySkinned VS_Main_ZOnlySkinned( vertexInputZOnlySkinned IN
         ) 
{ 
    vertexOutputZOnlySkinned OUT;
    float3 verletOffset = VerletOffset( (int4)IN.boneIndices, IN.boneWeights );
    IN.position += verletOffset;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MSAA_ENABLED
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    return OUT;
}
float4 PS_Main_ZOnlySkinned( vertexOutputZOnlySkinned IN ): COLOR
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
technique ZOnlyVehicleSkinnedOpaqueSingleSided
<
  string sharedName="ZOnlyVehicleSkinnedOpaqueSingleSided";
>
{
    pass p0
    {  
        CullMode = cw;
#ifndef D_MSAA_ENABLED
        ColorWriteEnable = 0;
#endif
  VertexShader = compile vs_3_0 VS_Main_ZOnlySkinned();
  PixelShader  = compile ps_3_0 PS_Main_ZOnlySkinned();
    }
}
#ifdef D_MSAA_ENABLED
#undef D_ADD_STENCIL
#endif
