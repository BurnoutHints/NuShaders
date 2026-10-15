#include "../Include/Platform.fxh"
#include "../Include/Transform.fxh"
#define SHADOW_APPLY_Z_BIAS
#define SHADOW_Z_BIAS_VALUE 0.0001
#include "../Include/Shadow.fxh"
#include "../Include/Fog.fxh"
#include "../Include/Irradiance.fxh"
#include "../Include/DepthEncode.fxh"
#include "../Include/Constants.fxh"
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
#include "../Include/VehicleDeformation.fxh"
float4      g_glassFractureStrength
<
    string scope = "object";
>;
float4      g_glassFractureUVOffsets
<
    string scope = "object";
>;
float4      g_glassFractureFresnelRanges
<
    string scope = "object";
> = float4( 0.0, 1.0, 0.0, 0.0 );
float4      g_PerVehicleFog
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
texture GlassFractureTexture
<
    string scope = "persistent";
    string purpose = "glassFractureTexturePersistent";
>;
SAMPLER_2D_UNTYPED(GlassFractureSampler, 14,
<
    string scope = "persistent";
    string purpose = "glassFractureTexturePersistent";
> = sampler_state
{
    Texture = <GlassFractureTexture>;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
});
struct DamagedAttributes
{
    float3  position                : POSITION;
    float3  normal                  : NORMAL;
    float2  texCoordDiffuse         : TEXCOORD0;
    float2  texCoordGlassFracture   : TEXCOORD1;
    BONE_INDICES4  boneIndices             : BLENDINDICES;
    float3  boneWeights             : BLENDWEIGHT;
};
struct DamagedInterpolators
{
    float4 hPosition                   : POSITION;
    float3 vertToEyeVector             : TEXCOORD0;
    float4 worldNormalAndInvWhiteLevel : TEXCOORD1;
    float2 texCoords                   : TEXCOORD2;
    SHADOWMAP_INTERPOLATORS2( 3,4 )
    float3 indirectColour              : TEXCOORD5;
    float4 texCoordsDamaged            : TEXCOORD6;
#ifdef D_MRT
    float2 hPositionDepthCopy          : TEXCOORD7;
#endif
};
DamagedInterpolators
DamagedVS( DamagedAttributes IN )
{
    DamagedInterpolators OUT;
    float3 verletOffset = VerletOffset( (int2)IN.boneIndices.xy, IN.boneWeights.xy );
    IN.position += verletOffset;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.worldNormalAndInvWhiteLevel.xyz = normalize( mul( IN.normal, (float3x3)world ) );
    OUT.worldNormalAndInvWhiteLevel.w = 1.0f / FogColourPlusWhiteLevel.w;
    OUT.texCoords.xy = IN.texCoordDiffuse;
    OUT.texCoordsDamaged.xy = (IN.texCoordGlassFracture * g_glassFractureFresnelRanges.xy) + g_glassFractureUVOffsets.xy;
    OUT.texCoordsDamaged.zw = (IN.texCoordGlassFracture * g_glassFractureFresnelRanges.zw) + g_glassFractureUVOffsets.zw;
    OUT.indirectColour.xyz = ComputeIrradianceFast( OUT.worldNormalAndInvWhiteLevel.xyz );
 float3 objectCentreWorldSpace = world[3];
    float objectCentreViewSpaceDepth = GetViewSpaceDepthFromWorldPosition( objectCentreWorldSpace );
    CALC_SHADOWMAP_INTERPOLATORS2_SELECT_VS( WorldSpacePosition, OUT.hPosition.w, objectCentreViewSpaceDepth );
    float3 vertToEye = (ViewPosition - WorldSpacePosition);
    OUT.vertToEyeVector = normalize( vertToEye );
    return OUT;
}
#ifdef D_MRT
void DamagedPS( in  DamagedInterpolators IN,
              in  float lfFace : VFACE,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 DamagedPS( DamagedInterpolators IN, float lfFace : VFACE ) : COLOR
#endif
{
    float4   diffuseTex = tex2D( DiffuseTextureSampler, IN.texCoords.xy );
    float3   normal = normalize( float3( IN.worldNormalAndInvWhiteLevel.xyz ) );
    float3   keyLightDirection = float3( -KeyLightDirection );
    float    lightDotNormal = saturate( dot( normal, keyLightDirection ) );
    float4 fresnelRanges = g_fresnelRanges;
    float    fresnelCurve = g_reflectConstants.y;
    float shadowModulation = CALC_SHADOW_FACTOR_2_SELECT_VEHICLE( lightDotNormal );
    float3 view = normalize( float3( IN.vertToEyeVector ) );
    float illumination = lightDotNormal * shadowModulation;
    float4 fractureTex1 = tex2D( GlassFractureSampler, IN.texCoordsDamaged.xy );
    float4 fractureTex2 = tex2D( GlassFractureSampler, IN.texCoordsDamaged.zw );
    float4 fractureSample = max(fractureTex1, fractureTex2);
    float lfOneMinusNonNegativeFractureStrengthMultNormalisingRange  = float(g_glassFractureStrength.x);
    float lfNormalisingRange                                         = float(g_glassFractureStrength.y);
    float lfCrackAmount = saturate(fractureSample.r * lfNormalisingRange - lfOneMinusNonNegativeFractureStrengthMultNormalisingRange);
    float lfCrackAmountStepped = step(-lfCrackAmount, float(-0.05));
    float lfReflectionWarpAmount = saturate(fractureSample.g * lfNormalisingRange - lfOneMinusNonNegativeFractureStrengthMultNormalisingRange);
    float3 lPerturbedNormal = normalize(float3(normal.x, normal.y - lfReflectionWarpAmount, normal.z));
 float normalDotViewSaturated = saturate( dot( lPerturbedNormal, view ) );
    float3 reflectedView = float(2.0) * normalDotViewSaturated * lPerturbedNormal - view;
    float fresnelValue = lerp(fresnelRanges.w, fresnelRanges.z, normalDotViewSaturated);
    float3 reflectTex = texCUBE( ReflectionTextureSampler, reflectedView ).rgb;
    float lfContrast = float(g_reflectConstants.w);
    float lfHalfWhiteLevel = float(FogColourPlusWhiteLevel.w) * float(0.5);
    reflectTex = reflectTex*lfContrast - lfHalfWhiteLevel*lfContrast + lfHalfWhiteLevel;
    float lfSaturation = float(g_reflectConstants.z);
    float luminance = dot( reflectTex, (float3)k_luminanceMapping );
    reflectTex = lerp( luminance.xxx, reflectTex, lfSaturation );
    float    reflectDotLight = saturate( dot( reflectedView, keyLightDirection ) );
    float    specularIntensity = pow( reflectDotLight, (float)g_reflectConstants.x );
    float3 lfCrackColour = lerp(float3(0.2, 0.3, 0.3), float3(0.53, 0.95, 0.93), lfCrackAmount) * (float)FogColourPlusWhiteLevel.w;
    float3 baseColour = lerp(float3(materialDiffuse.rgb) * diffuseTex.rgb, lfCrackColour, lfCrackAmountStepped);
    float alpha = (lfCrackAmountStepped * diffuseTex.a) + diffuseTex.a;
    fresnelValue = (-fresnelValue * lfCrackAmountStepped) + fresnelValue;
    specularIntensity = (lfCrackAmountStepped * fractureSample.a) + specularIntensity;
    float3   reflectColour = reflectTex * fresnelValue;
    float3   specularLightColour = float3(KeyLightSpecularColour.rgb);
    float3   specularColour = ( specularLightColour * specularIntensity );
    float3   lightColour = ( float3(IN.indirectColour) + float3(KeyLightClampedColour.rgb) * illumination ) * alpha;
    float    lightIntensity = saturate( dot( lightColour, float3(k_luminanceMapping) ) * float(IN.worldNormalAndInvWhiteLevel.w) );
    float3   diffuseColour = baseColour * lightColour;
    diffuseColour *= ( float(1.0) - fresnelValue * float(0.5) );
    float3 finalColour = diffuseColour + ( reflectColour + specularColour * shadowModulation ) * lightIntensity;
    finalColour = ( finalColour * float( g_PerVehicleFog.a ) ) + float3(g_PerVehicleFog.rgb);
#ifdef D_MRT
    oColour0 = (lfFace < 0) ? float4(finalColour, alpha) : float4(0.0, 0.0, 0.0, 0.3);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth ) + 2.0f;
#else
    return (lfFace < 0) ? float4(finalColour, alpha) : float4(0.0, 0.0, 0.0, 0.3);
#endif
}
technique Damaged
{
    pass p0
    {
        CULLMODE = NONE;
        AlphaFunc = GREATER;
        AlphaBlendEnable = True;
        AlphaTestEnable = False;
        SrcBlend = SrcAlpha;
        DestBlend = InvSrcAlpha;
        VertexShader = compile vs_3_0 DamagedVS();
        PixelShader  = compile ps_3_0 DamagedPS();
    }
}
struct DefaultAttributes
{
    float3  position                : POSITION;
    float3  normal                  : NORMAL;
    float2  texCoordDiffuse         : TEXCOORD0;
};
struct DefaultInterpolators
{
    float4 hPosition                   : POSITION;
    float3 vertToEyeVector             : TEXCOORD0;
    float4 worldNormalAndInvWhiteLevel : TEXCOORD1;
    float2 texCoords                   : TEXCOORD2;
    SHADOWMAP_INTERPOLATORS2( 3,4 )
    float3 indirectColour              : TEXCOORD5;
#ifdef D_MRT
    float2 hPositionDepthCopy          : TEXCOORD7;
#endif
};
DefaultInterpolators
DefaultVS( DefaultAttributes IN )
{
    DefaultInterpolators OUT;
    float3 verletOffset = 0.0;
    IN.position += verletOffset;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.worldNormalAndInvWhiteLevel.xyz = normalize( mul( IN.normal, (float3x3)world ) );
    OUT.worldNormalAndInvWhiteLevel.w = 1.0f / FogColourPlusWhiteLevel.w;
    OUT.texCoords.xy = IN.texCoordDiffuse;
    OUT.indirectColour.xyz = ComputeIrradianceFast( OUT.worldNormalAndInvWhiteLevel.xyz );
 float3 objectCentreWorldSpace = world[3];
    float objectCentreViewSpaceDepth = GetViewSpaceDepthFromWorldPosition( objectCentreWorldSpace );
    CALC_SHADOWMAP_INTERPOLATORS2_SELECT_VS( WorldSpacePosition, OUT.hPosition.w, objectCentreViewSpaceDepth );
    float3 vertToEye = (ViewPosition - WorldSpacePosition);
    OUT.vertToEyeVector = normalize( vertToEye );
    return OUT;
}
#ifdef D_MRT
void DefaultPS( in  DefaultInterpolators IN,
              in  float lfFace : VFACE,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 DefaultPS( DefaultInterpolators IN, float lfFace : VFACE ) : COLOR
#endif
{
    float4   diffuseTex = tex2D( DiffuseTextureSampler, IN.texCoords.xy );
    float3   normal = normalize( float3( IN.worldNormalAndInvWhiteLevel.xyz ) );
    float3   keyLightDirection = float3( -KeyLightDirection );
    float    lightDotNormal = saturate( dot( normal, keyLightDirection ) );
    float4 fresnelRanges = g_fresnelRanges;
    float    fresnelCurve = g_reflectConstants.y;
    float shadowModulation = CALC_SHADOW_FACTOR_2_SELECT_VEHICLE( lightDotNormal );
    float3 view = normalize( float3( IN.vertToEyeVector ) );
    float illumination = lightDotNormal * shadowModulation;
    float3 lPerturbedNormal = normal;
 float normalDotViewSaturated = saturate( dot( lPerturbedNormal, view ) );
    float3 reflectedView = float(2.0) * normalDotViewSaturated * lPerturbedNormal - view;
    float fresnelValue = lerp(fresnelRanges.w, fresnelRanges.z, normalDotViewSaturated);
    float3 reflectTex = texCUBE( ReflectionTextureSampler, reflectedView ).rgb;
    float lfContrast = float(g_reflectConstants.w);
    float lfHalfWhiteLevel = float(FogColourPlusWhiteLevel.w) * float(0.5);
    reflectTex = reflectTex*lfContrast - lfHalfWhiteLevel*lfContrast + lfHalfWhiteLevel;
    float lfSaturation = float(g_reflectConstants.z);
    float luminance = dot( reflectTex, (float3)k_luminanceMapping );
    reflectTex = lerp( luminance.xxx, reflectTex, lfSaturation );
    float    reflectDotLight = saturate( dot( reflectedView, keyLightDirection ) );
    float    specularIntensity = pow( reflectDotLight, (float)g_reflectConstants.x );
    float3   baseColour = float3(materialDiffuse.rgb) * diffuseTex.rgb;
    float alpha = diffuseTex.a;
    float3   reflectColour = reflectTex * fresnelValue;
    float3   specularLightColour = float3(KeyLightSpecularColour.rgb);
    float3   specularColour = ( specularLightColour * specularIntensity );
    float3   lightColour = ( float3(IN.indirectColour) + float3(KeyLightClampedColour.rgb) * illumination ) * alpha;
    float    lightIntensity = saturate( dot( lightColour, float3(k_luminanceMapping) ) * float(IN.worldNormalAndInvWhiteLevel.w) );
    float3   diffuseColour = baseColour * lightColour;
    diffuseColour *= ( float(1.0) - fresnelValue * float(0.5) );
    float3 finalColour = diffuseColour + ( reflectColour + specularColour * shadowModulation ) * lightIntensity;
    finalColour = ( finalColour * float( g_PerVehicleFog.a ) ) + float3(g_PerVehicleFog.rgb);
#ifdef D_MRT
    oColour0 = (lfFace < 0) ? float4(finalColour, alpha) : float4(0.0, 0.0, 0.0, 0.3);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth ) + 2.0f;
#else
    return (lfFace < 0) ? float4(finalColour, alpha) : float4(0.0, 0.0, 0.0, 0.3);
#endif
}
technique Default
{
    pass p0
    {
        CULLMODE = NONE;
        AlphaFunc = GREATER;
        AlphaBlendEnable = True;
        AlphaTestEnable = False;
        SrcBlend = SrcAlpha;
        DestBlend = InvSrcAlpha;
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
#ifdef D_MSAA_ENABLED
#undef D_ADD_STENCIL
#endif
