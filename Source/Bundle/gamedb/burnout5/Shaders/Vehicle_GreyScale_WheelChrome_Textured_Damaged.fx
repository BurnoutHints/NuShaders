#include "../Include/Platform.fxh"
#include "../Include/Transform.fxh"
#define SHADOW_APPLY_Z_BIAS
#define SHADOW_Z_BIAS_VALUE 0.0001
#include "../Include/Shadow.fxh"
#include "../Include/Fog.fxh"
#include "../Include/Irradiance.fxh"
#include "../Include/DepthEncode.fxh"
#include "../Include/Constants.fxh"
float4x4    worldViewProj : WorldViewProjection
<
    string scope = "object";
>;
float4x4    world : World
<
    string scope = "object";
>;
float3      KeyLightDirection  : Direction
<
    string scope = "global";
>;
float3      ViewPosition : Direction
<
    string scope = "global";
>;
float3      KeyLightSpecularColour : Diffuse
<
    string scope = "global";
>;
float3      KeyLightClampedColour : Diffuse
<
    string scope = "global";
>;
float4  g_wheelConstants
<
    string scope = "object";
> = float4( 0.0, 0.0, 0.0, 0.0 );
float4  g_fresnelRanges 
<
    string scope = "material";
    string UIName = "Fresnel Ranges";
> = float4( 1.0, 2.0, 0.5, 1.0 );
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
texture2D DiffuseTexture
<
    string scope = "material";
>;
SAMPLER_2D_UNTYPED(DiffuseTextureSampler, 0,
<
    string scope = "material";
> = sampler_state
{
    Texture = <DiffuseTexture>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
});
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
texture2D BlurDiffuseTexture
<
    string scope = "material";
>;
SAMPLER_2D_UNTYPED(BlurDiffuseTextureSampler, 3,
<
    string scope = "material";
> = sampler_state
{
    Texture = <BlurDiffuseTexture>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
});
texture BlurNormalTexture
<
    string scope = "material";
>;
SAMPLER_2D_UNTYPED(BlurNormalTextureSampler, 4,
<
    string scope = "material";
> = sampler_state
{
    Texture = <BlurNormalTexture>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
});
#define NORMAL_MAP_SWAP_TB
#include "../Include/NormalMapping.fxh"
#include "../Include/Fresnel.fxh"
#define CONTRAST_USE_FIXED_MID
#include "../Include/Utility.fxh"
struct Attributes
{
    float3  position                : POSITION;
        float3  normal                  : NORMAL;
        float3  tangent                 : TANGENT;
    float2  texCoordDiffuse         : TEXCOORD0;
};
struct Interpolators
{
    float4 hPosition                : POSITION;
    float3 worldPosition            : TEXCOORD0;
    float3 worldNormal              : TEXCOORD1;
    float3 texCoordsAndBlur         : TEXCOORD2;
    SHADOWMAP_INTERPOLATORS2( 3,4 ) 
    float3 worldTangent             : TEXCOORD5;
    float4 indirectColour           : TEXCOORD6;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD7;
#endif
};
Interpolators
WheelVS( Attributes IN
    )
{
    Interpolators OUT;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.worldPosition = WorldSpacePosition;
    OUT.worldNormal     = normalize( mul( IN.normal, (float3x3)world ) );
    OUT.worldTangent = normalize( mul( IN.tangent, (float3x3)world ) );
 OUT.texCoordsAndBlur.z = g_wheelConstants.x;
 float3 objectCentreWorldSpace = world[3].xyz;
    float objectCentreViewSpaceDepth = GetViewSpaceDepthFromWorldPosition( objectCentreWorldSpace );
    OUT.texCoordsAndBlur.xy = IN.texCoordDiffuse;
    OUT.indirectColour.xyz = ComputeIrradianceFast( normalize( OUT.worldNormal ) );
    OUT.indirectColour.w   = CalculateScattering( length( ViewPosition - OUT.worldPosition.xyz ) );
    CALC_SHADOWMAP_INTERPOLATORS2_SELECT_VS( OUT.worldPosition.xyz, OUT.hPosition.w, objectCentreViewSpaceDepth );
    return OUT;
}
#ifdef D_MRT
void StationaryPS( in  Interpolators IN,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 StationaryPS( Interpolators IN ) : COLOR
#endif
{
    float4   diffuseTex = tex2D( DiffuseTextureSampler, IN.texCoordsAndBlur.xy );
    float4   blurDiffuseTex = tex2D( BlurDiffuseTextureSampler, IN.texCoordsAndBlur.xy );
    diffuseTex = lerp( diffuseTex, blurDiffuseTex, IN.texCoordsAndBlur.z );
    float4   normalTex = tex2D( NormalTextureSampler, IN.texCoordsAndBlur.xy );
    float4   blurNormalTex = tex2D( BlurNormalTextureSampler, IN.texCoordsAndBlur.xy );
    normalTex = lerp( normalTex, blurNormalTex, IN.texCoordsAndBlur.z );
    const float selfIllumination = 0.0;
    float3 baseColour = materialDiffuse.rgb * diffuseTex.rgb;
    float3   binormal = cross( IN.worldTangent, IN.worldNormal );
    float3   normal = DecodeNormalMap( normalTex.ga, IN.worldNormal, IN.worldTangent, binormal, 2.0 );
    float3   view = normalize( ViewPosition.xyz - IN.worldPosition.xyz );
    float3   reflectedView;
    float2   fresnelValues;
    CalculateFresnel( normal, view, g_fresnelRanges, g_reflectConstants.y, reflectedView, fresnelValues );
    float4   reflectTex = texCUBE( ReflectionTextureSampler, reflectedView );
    reflectTex.rgb = AdjustContrast( reflectTex.rgb, g_reflectConstants.w );
    reflectTex.rgb = AdjustSaturation( reflectTex.rgb, g_reflectConstants.z );
    fresnelValues.xy = fresnelValues.xy * normalTex.r;
    float3   reflectColour = reflectTex.rgb * fresnelValues.y;
    float specularMask = fresnelValues.x;
    float3   keyLightDirection = float3( -KeyLightDirection );
    float    reflectDotLight = saturate( dot( reflectedView, keyLightDirection ) );
    float    specularIntensity = pow( reflectDotLight, g_reflectConstants.x );
    float    lightToReflectMagnitude = length( reflectedView - keyLightDirection );
    float    hotSpotIntensity = LinearStep1Fast( g_specularConstants.x, 3.0, 1.0 - lightToReflectMagnitude ) * g_specularConstants.y * FogColourPlusWhiteLevel.w;
    float3   specularLightColour = lerp( KeyLightSpecularColour.rgb, baseColour * 2.0, g_specularConstants.z );
    float3   specularColour = ( specularLightColour * specularIntensity + hotSpotIntensity ) * specularMask;
    float    lightDotNormal = saturate( dot( normal, keyLightDirection ) );
    float shadowModulation = CALC_SHADOW_FACTOR_2_SELECT_VEHICLE( lightDotNormal );
    float3   lightColour = ( IN.indirectColour.rgb + KeyLightClampedColour.rgb * lightDotNormal * shadowModulation );
    float    lightIntensity = saturate( dot( lightColour, k_luminanceMapping ) );
    float3   diffuseColour = baseColour * lightColour;
    float4   finalColour;
    diffuseColour *= ( 1.0 - fresnelValues.y * 0.5 );
    finalColour.rgb = diffuseColour + ( reflectColour + specularColour * shadowModulation ) * lightIntensity;
    finalColour.a = diffuseTex.a;
    finalColour.rgb = lerp( finalColour.rgb, FogColourPlusWhiteLevel.rgb, float( IN.indirectColour.a ) );
#ifdef D_MRT
    oColour0 = finalColour;
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth ) + 2.0f;
#else
    return finalColour;
#endif
}
#ifdef D_MRT
void BlurredPS( in  Interpolators IN,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 BlurredPS( Interpolators IN ) : COLOR
#endif
{
#ifdef D_PLATFORM_BPR
    // Remastered: cross-fade from the sharp maps to the blurred ones by the blur factor.
    float4   diffuseTex = lerp( tex2D( DiffuseTextureSampler, IN.texCoordsAndBlur.xy ), tex2D( BlurDiffuseTextureSampler, IN.texCoordsAndBlur.xy ), IN.texCoordsAndBlur.z );
    float4   normalTex = lerp( tex2D( NormalTextureSampler, IN.texCoordsAndBlur.xy ), tex2D( BlurNormalTextureSampler, IN.texCoordsAndBlur.xy ), IN.texCoordsAndBlur.z );
#else
    float4   diffuseTex = tex2D( BlurDiffuseTextureSampler, IN.texCoordsAndBlur.xy );
    float4   normalTex = tex2D( BlurNormalTextureSampler, IN.texCoordsAndBlur.xy );
#endif
    const float selfIllumination = 0.0;
    float3 baseColour = materialDiffuse.rgb * diffuseTex.rgb;
    float3   binormal = cross( IN.worldTangent, IN.worldNormal );
    float3   normal = DecodeNormalMap( normalTex.ga, IN.worldNormal, IN.worldTangent, binormal, 2.0 );
    float3   view = normalize( ViewPosition.xyz - IN.worldPosition.xyz );
    float3   reflectedView;
    float2   fresnelValues;
    CalculateFresnel( normal, view, g_fresnelRanges, g_reflectConstants.y, reflectedView, fresnelValues );
    float4   reflectTex = texCUBE( ReflectionTextureSampler, reflectedView );
    reflectTex.rgb = AdjustContrast( reflectTex.rgb, g_reflectConstants.w );
    reflectTex.rgb = AdjustSaturation( reflectTex.rgb, g_reflectConstants.z );
    fresnelValues.xy = fresnelValues.xy * normalTex.r;
    float3   reflectColour = reflectTex.rgb * fresnelValues.y;
    float specularMask = fresnelValues.x;
    float3   keyLightDirection = float3( -KeyLightDirection );
    float    reflectDotLight = saturate( dot( reflectedView, keyLightDirection ) );
    float    specularIntensity = pow( reflectDotLight, g_reflectConstants.x );
    float    lightToReflectMagnitude = length( reflectedView - keyLightDirection );
    float    hotSpotIntensity = LinearStep1Fast( g_specularConstants.x, 3.0, 1.0 - lightToReflectMagnitude ) * g_specularConstants.y * FogColourPlusWhiteLevel.w;
    float3   specularLightColour = lerp( KeyLightSpecularColour.rgb, baseColour * 2.0, g_specularConstants.z );
    float3   specularColour = ( specularLightColour * specularIntensity + hotSpotIntensity ) * specularMask;
    float    lightDotNormal = saturate( dot( normal, keyLightDirection ) );
    float shadowModulation = CALC_SHADOW_FACTOR_2_SELECT_VEHICLE( lightDotNormal );
    float3   lightColour = ( IN.indirectColour.rgb + KeyLightClampedColour.rgb * lightDotNormal * shadowModulation );
    float    lightIntensity = saturate( dot( lightColour, k_luminanceMapping ) );
    float3   diffuseColour = baseColour * lightColour;
    float4   finalColour;
    diffuseColour *= ( 1.0 - fresnelValues.y * 0.5 );
    finalColour.rgb = diffuseColour + ( reflectColour + specularColour * shadowModulation ) * lightIntensity;
    finalColour.a = diffuseTex.a;
    finalColour.rgb = lerp( finalColour.rgb, FogColourPlusWhiteLevel.rgb, float( IN.indirectColour.a ) );
#ifdef D_MRT
    oColour0 = finalColour;
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth ) + 2.0f;
#else
    return finalColour;
#endif
}
technique Blurred
<
>
{
    pass p0
    {
        AlphaFunc = GREATER;
        AlphaRef = 32;
        AlphaBlendEnable = True;
        AlphaTestEnable = True;
        SrcBlend = SrcAlpha;
        DestBlend = InvSrcAlpha;
        VertexShader = compile vs_3_0 WheelVS();
        PixelShader  = compile ps_3_0 BlurredPS();
    }
}
technique Default
<
>
{
    pass p0
    {
        AlphaFunc = GREATER;
        AlphaRef = 64;
        AlphaBlendEnable = True;
        AlphaTestEnable = True;
        SrcBlend = SrcAlpha;
        DestBlend = InvSrcAlpha;
        VertexShader = compile vs_3_0 WheelVS();
        PixelShader  = compile ps_3_0 StationaryPS();
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
#ifdef D_MSAA_ENABLED
#undef D_ADD_STENCIL
#endif
