#ifndef SHADOW_FXH
#define SHADOW_FXH

#include "../Include/Transform.fxh"

#ifndef USE_SHARED_GLOBALS
#ifdef D_PLATFORM_X360
float4x4 ShadowMap_WorldToLight[3] : register(c4)
#else
float4x4 ShadowMap_WorldToLight[3]
#endif
<
    string scope = "global";
>;

float4 ShadowMap_Constants
<
 string scope = "global";
>;

float4 ShadowMap_Constants2
<
 string scope = "global";
>;

#ifdef D_PLATFORM_BPR
// Remastered addition (.x = PCF kernel step, see CalcShadowFactor3CSM). Declared here
// because every shipped BPR $Globals has it between Constants2 and ObjectCsmSelect.
float4 ShadowMap_Constants3
<
 string scope = "global";
>;
#endif

float4 ShadowMap_ObjectCsmSelect
<
    string scope = "object";
>;
#endif // USE_SHARED_GLOBALS

#ifdef D_PLATFORM_BPR
// SM5/DX11: hardware comparison sampler (matches the Remastered binding: t15 + s15 comparison)
Texture2D              shadowMapSamplerHighDetailTexture : register(t15);
SamplerComparisonState shadowMapSamplerHighDetail        : register(s15);
#else
texture2D shadowMap0
<
 string scope   = "persistent";
 string purpose = "shadowMap";
>;

sampler2D shadowMapSamplerHighDetail : register(s15)
<
 string scope   = "persistent";
 string purpose = "shadowMap";
> = sampler_state
{
 Texture = <shadowMap0>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = none;
};
#endif

#ifdef D_NO_SHADOWS
    #define SHADOWMAP_INTERPOLATORS1( semantic0 )
    #define SHADOWMAP_INTERPOLATORS2( semantic0, semantic1 )
    #define CALC_SHADOWMAP_INTERPOLATORS1( wsp, eyeZ )          1.0f
    #define CALC_SHADOWMAP_INTERPOLATORS2( wsp, eyeZ )          1.0f
    #define CALC_SHADOWMAP_INTERPOLATORS3( wsp, eyeZ )          1.0f
    #define CALC_SHADOWMAP_INTERPOLATORS3_4( wsp, eyeZ )        1.0f
    #define CALC_SHADOWMAP_INTERPOLATORS2_SELECT( wsp, eyeZ )   1.0f
    #define CALC_SHADOWMAP_INTERPOLATORS2_SELECT_VS( wsp, eyeZ, objDist )  1.0f
    #define CALC_SHADOWMAP_INTERPOLATORS_DUMMY
    #define CALC_SHADOW_FACTOR_1( NDotL )   1.0f
    #define CALC_SHADOW_FACTOR_2( NDotL )   1.0f
    #define CALC_SHADOW_FACTOR_2_SELECT( NDotL )    1.0f
    #define CALC_SHADOW_FACTOR_2_SELECT_VEHICLE( NDotL )    1.0f
    #define CALC_SHADOW_FACTOR_2_SELECT_VEHICLE_DAMAGED( NDotL, damage )    1.0f
    #define CALC_SHADOW_FACTOR_3( NDotL )   1.0f
#else
    #define SHADOWMAP_INTERPOLATORS1( semantic0 ) \
        float4 LightSpacePos0 : TEXCOORD## semantic0 ;
    #define SHADOWMAP_INTERPOLATORS2( semantic0, semantic1 ) \
        float4 LightSpacePos0 : TEXCOORD## semantic0 ; \
        float4 LightSpacePos1 : TEXCOORD## semantic1 ;
    #define CALC_SHADOWMAP_INTERPOLATORS1( wsp, eyeZ )          GetShadowMapPositions1CSM( wsp, eyeZ, OUT.LightSpacePos0 )
    #define CALC_SHADOWMAP_INTERPOLATORS2( wsp, eyeZ )          GetShadowMapPositions2CSM( wsp, eyeZ, OUT.LightSpacePos0, OUT.LightSpacePos1 )
    #define CALC_SHADOWMAP_INTERPOLATORS3( wsp, eyeZ )          GetShadowMapPositions3CSM( wsp, eyeZ, OUT.LightSpacePos0, OUT.LightSpacePos1 )
    #define CALC_SHADOWMAP_INTERPOLATORS3_4( wsp, eyeZ )        GetShadowMapPositions3CSM_4( wsp, eyeZ, OUT.LightSpacePos0, OUT.LightSpacePos1 )
    #define CALC_SHADOWMAP_INTERPOLATORS2_SELECT( wsp, eyeZ )   GetShadowMapPositions2CSMSelect( wsp, eyeZ, OUT.LightSpacePos0, OUT.LightSpacePos1 )
    #define CALC_SHADOWMAP_INTERPOLATORS2_SELECT_VS( wsp, eyeZ, objDist )   GetShadowMapPositions2CSMSelectVS( wsp, eyeZ, objDist, OUT.LightSpacePos0, OUT.LightSpacePos1 )
    #define CALC_SHADOWMAP_INTERPOLATORS_DUMMY                  OUT.LightSpacePos0 = float4( 0.0, 0.0, 0.0, 0.0 ); \
                                                                OUT.LightSpacePos1 = float4( 0.0, 0.0, 0.0, 0.0 );
    #define CALC_SHADOW_FACTOR_1( NDotL )                                 CalcShadowFactor1CSM( IN.LightSpacePos0, NDotL )
    #define CALC_SHADOW_FACTOR_2( NDotL )                                 CalcShadowFactor2CSM( IN.LightSpacePos0, IN.LightSpacePos1, NDotL )
    #define CALC_SHADOW_FACTOR_2_SELECT( NDotL )                          CalcShadowFactor2CSMSelect( IN.LightSpacePos0, IN.LightSpacePos1, NDotL )
    #define CALC_SHADOW_FACTOR_2_SELECT_VEHICLE( NDotL )                  CalcShadowFactorCSM_Vehicle_Damaged_2CSM_Select( IN.LightSpacePos0, IN.LightSpacePos1, NDotL, 0.0 )
    #define CALC_SHADOW_FACTOR_2_SELECT_VEHICLE_DAMAGED( NDotL, damage )  CalcShadowFactorCSM_Vehicle_Damaged_2CSM_Select( IN.LightSpacePos0, IN.LightSpacePos1, NDotL, damage )
#ifdef D_PLATFORM_X360
    #define CALC_SHADOW_FACTOR_3_FORCE_ANISO( NDotL )                     CalcShadowFactor3CSM_X360_Aniso( IN.LightSpacePos0, IN.LightSpacePos1, NDotL )
    #define CALC_SHADOW_FACTOR_3_FORCE_NO_ANISO( NDotL )                  CalcShadowFactor3CSM( IN.LightSpacePos0, IN.LightSpacePos1, NDotL )
#ifdef D_SHADOWMAP_ANISOTROPIC
    #define CALC_SHADOW_FACTOR_3( NDotL )                                 CalcShadowFactor3CSM_X360_Aniso( IN.LightSpacePos0, IN.LightSpacePos1, NDotL )
#else
    #define CALC_SHADOW_FACTOR_3( NDotL )                                 CalcShadowFactor3CSM( IN.LightSpacePos0, IN.LightSpacePos1, NDotL )
#endif
#else
    #define CALC_SHADOW_FACTOR_3( NDotL )                                 CalcShadowFactor3CSM( IN.LightSpacePos0, IN.LightSpacePos1, NDotL )
#endif
#if defined(D_HACK_FORCE_3CSM)
    #define SHADOWMAP_INTERPOLATORS( semantic0, semantic1, semantic2 ) \
        float4 LightSpacePos0 : TEXCOORD## semantic0 ; \
        float4 LightSpacePos1 : TEXCOORD## semantic1 ;
    #define GetShadowMapPositions( wsp, l0, l1 )        GetShadowMapPositions3CSM( wsp, OUT.hPosition.w, OUT.LightSpacePos0, OUT.LightSpacePos1 )
    #define CalcShadowFactorCSM_New( l0, l1, NDotL )    CalcShadowFactor3CSM( IN.LightSpacePos0, IN.LightSpacePos1, NDotL )
#endif
#endif

#ifdef D_SOFT_SHADOWS
#define M_PI 3.14159265358979323846
#define fmodp(x,n) ((n)*frac((x)/(n)))
float2 rand(float2 ij)
{
  const float4 a=float4(M_PI * M_PI * M_PI * M_PI, exp(4.0), pow(13.0, M_PI / 2.0), sqrt(1997.0));
  float4 result =float4(ij,ij);
  for(int i = 0; i < 3; i++)
  {
      result.x = frac(dot(result, a));
      result.y = frac(dot(result, a));
      result.z = frac(dot(result, a));
      result.w = frac(dot(result, a));
  }
  return (result.xy) - 0.5;
}
#endif

#ifdef D_PLATFORM_BPR
// SM5: same call shape as the SM3 non-soft path (callers pass the sampler), but
// a hardware comparison sampler. (Do not define D_SOFT_SHADOWS for BPR.)
#ifndef D_BPR_SHADOW_BIAS
#define D_BPR_SHADOW_BIAS 0.01   // depth bias to kill self-shadow acne (diagnostic value; tune down once confirmed)
#endif
float CalcOrthoShadowFactorBySampler( SamplerComparisonState shadowMapSampler, in float3 lLightSpacePos )
{
    // Hardware PCF: .xy = shadow-map UV, .z = depth to compare (biased toward the light).
    return shadowMapSamplerHighDetailTexture.SampleCmpLevelZero( shadowMapSampler, lLightSpacePos.xy, lLightSpacePos.z - D_BPR_SHADOW_BIAS );
}
#else
float CalcOrthoShadowFactorBySampler(
        sampler2D   shadowMapSampler,
 in float3   lLightSpacePos
#ifdef D_SOFT_SHADOWS
       ,in float    eyeZ
#endif
                                   )
{
#ifdef D_SOFT_SHADOWS
 if (eyeZ > 140.0f)
 {
  return 0.0f;
 }
 else
 {
    float4 shadowedSum = 0;
    float4 shadowedSum2 = 0;
 float4 jitterOffset = 0.0;
 float4 jitterTex2dOffset = 0.0;
 float jitterKernelSize = 8.0f;
 int kernelSize = 2;
 int intpart;
 #define jitterScale 12
    #define GB_KERNEL_SIZE 2.0
    #define GB_KERNEL_SPARSE_SIZE 4.0
    float blurRadius = 5.0 * ( 1.0 - ( min( eyeZ, 140.0f ) / 140.0f ) );
    float falloff = blurRadius*blurRadius*2.0;
 float weightTotal = 0.0f;
    for ( float v = -GB_KERNEL_SIZE*GB_KERNEL_SIZE; v <= GB_KERNEL_SIZE*GB_KERNEL_SIZE; v+=GB_KERNEL_SPARSE_SIZE )
    {
        for ( float u = -GB_KERNEL_SIZE*GB_KERNEL_SIZE; u <= GB_KERNEL_SIZE*GB_KERNEL_SIZE; u+=GB_KERNEL_SPARSE_SIZE )
        {
            float weight = exp(-(u*u + v*v) / (falloff));
            float4 t = tex2Dproj( shadowMapSampler, float4( lLightSpacePos, 1.0 ) + float4(u/4096.0, v/3072.0, 0, 0) ).r;
            shadowedSum += weight * t;
   weightTotal += weight;
        }
    }
    shadowedSum *= 1.0 / (weightTotal);
    return saturate(shadowedSum.x);
    }
#else
    return tex2Dproj( shadowMapSampler, float4( lLightSpacePos, 1.0 ) ).r;
#endif
}
#endif // D_PLATFORM_BPR  (CalcOrthoShadowFactorBySampler)

#ifdef D_PLATFORM_BPR
// The remaster's soft shadow, shared by every BPR shadow factor below (reconstructed
// from the shipped bytecode): nine SampleCmp taps spread by stepU/stepV around centre,
// Gaussian-weighted, with the blur shrinking to nothing at 140 units.
float ShadowPCF_BPR( float3 centre, float3 stepU, float3 stepV, float eyeZ )
{
    float blurRadius  = 5.0 * ( 1.0 - ( min( eyeZ, 140.0 ) / 140.0 ) );
    float falloff     = blurRadius * blurRadius * 2.0;
    float shadowedSum = 0.0;
    float weightTotal = 0.0;
    for ( float v = -1.0; v <= 1.0; v += 1.0 )
    {
        for ( float u = -1.0; u <= 1.0; u += 1.0 )
        {
            float  weight = exp( -( u*u + v*v ) / falloff );
            float3 tap    = centre + v * stepV + u * stepU;
            shadowedSum  += weight * shadowMapSamplerHighDetailTexture.SampleCmpLevelZero( shadowMapSamplerHighDetail, tap.xy, tap.z );
            weightTotal  += weight;
        }
    }
    return saturate( shadowedSum * ( 1.0 / weightTotal ) );
}

// The cascade eyeZ picks, pos mapped through it, and the PCF steps: ShadowMap_Constants3.x
// along world x and y. A step only depends on the matrix's linear part, which is why the
// vehicle PS can pass a light-space position here and still get the shipped result.
void ShadowSteps_BPR( float3 pos, float eyeZ, out float3 origin, out float3 stepU, out float3 stepV )
{
    bool beforeFar  = eyeZ < ShadowMap_Constants.y;
    bool beforeNear = eyeZ < ShadowMap_Constants.x;
    float4x4 w2l = beforeNear ? ShadowMap_WorldToLight[0]
                 : beforeFar  ? ShadowMap_WorldToLight[1]
                              : ShadowMap_WorldToLight[2];
    float3 posU = pos + float3( ShadowMap_Constants3.x, 0, 0 );
    float3 posV = pos + float3( 0, ShadowMap_Constants3.x, 0 );
    origin = mul( float4( pos, 1.0 ), w2l ).xyz;
    stepU  = mul( float4( posU, 1.0 ), w2l ).xyz - origin;
    stepV  = mul( float4( posV, 1.0 ), w2l ).xyz - origin;
}
#endif

void
GetShadowMapPositions2CSMSelect(
    in float3 positionWorld,
    in float eyeZ,
    out float4 texCoord0,
    out float4 texCoord1 )
{
    float3 position0 = mul( float4( positionWorld,1 ), ShadowMap_WorldToLight[ShadowMap_ObjectCsmSelect.x] ).xyz;
    float3 position1 = mul( float4( positionWorld,1 ), ShadowMap_WorldToLight[ShadowMap_ObjectCsmSelect.y] ).xyz;
    texCoord0 = float4( position0, eyeZ );
    texCoord1 = float4( position1, ShadowMap_ObjectCsmSelect.z );
}

void
GetShadowMapPositions2CSMSelectVS(
    in float3 positionWorld,
    in float eyeZ,
    in float objectDistance,
    out float4 texCoord0,
    out float4 texCoord1 )
{
    int     firstCsmIndex  = ( objectDistance < ShadowMap_Constants2.x ) ? 0 : 1;
    float   distanceThresh = ( objectDistance < ShadowMap_Constants2.x ) ? ShadowMap_Constants.x : ShadowMap_Constants.y;
    float3 position0 = mul( float4( positionWorld,1 ), ShadowMap_WorldToLight[firstCsmIndex] ).xyz;
    float3 position1 = mul( float4( positionWorld,1 ), ShadowMap_WorldToLight[firstCsmIndex+1] ).xyz;
#if defined(D_PLATFORM_BPR) && defined(SHADOW_APPLY_Z_BIAS)
    // Remastered: the shader's own SHADOW_Z_BIAS_VALUE, engine-scaled, on both cascades.
    position0.z -= ShadowMap_Constants2.z * SHADOW_Z_BIAS_VALUE;
    position1.z -= ShadowMap_Constants2.z * SHADOW_Z_BIAS_VALUE;
#endif
    texCoord0 = float4( position0, eyeZ );
    texCoord1 = float4( position1, distanceThresh );
}

void
GetShadowMapPositions3CSM(
    in float3 positionWorld,
    in float eyeZ,
    out float4 texCoord0,
    out float4 texCoord1 )
{
#ifdef D_PLATFORM_BPR
    // Remastered: the PS picks the cascade itself from the world position in
    // texCoord1. texCoord0.xyz (cascade 0) is unused by the PS but shipped.
    float3 position0 = mul( float4( positionWorld,1 ), ShadowMap_WorldToLight[0] ).xyz;
#ifdef SHADOW_APPLY_Z_BIAS
    position0.z -= ShadowMap_Constants2.z * SHADOW_Z_BIAS_VALUE;
#endif
    texCoord0 = float4( position0, eyeZ );
    texCoord1 = float4( positionWorld, 1.0 );
#else
    float3 position0 = mul( float4( positionWorld,1 ), ShadowMap_WorldToLight[0] ).xyz;
    float3 position1 = mul( float4( positionWorld,1 ), ShadowMap_WorldToLight[1] ).xyz;
    float3 position2 = mul( float4( positionWorld,1 ), ShadowMap_WorldToLight[2] ).xyz;
    texCoord0 = float4( position0, eyeZ );
    texCoord1 = float4( position1.xy, position2.xy );
    texCoord1.x += ShadowMap_Constants2.x * 1e-30;
#endif
}

void
GetShadowMapPositions3CSM_4(
    in float4 positionWorld,
    in float  eyeZ,
    out float4 texCoord0,
    out float4 texCoord1 )
{
    GetShadowMapPositions3CSM( positionWorld.xyz, eyeZ, texCoord0, texCoord1 );
}

void
GetShadowMapPositions2CSM(
    in float3 positionWorld,
    in float eyeZ,
    out float4 texCoord0,
    out float4 texCoord1 )
{
    float3 position0 = mul( float4( positionWorld,1), ShadowMap_WorldToLight[0] ).xyz;
    float3 position1 = mul( float4( positionWorld,1), ShadowMap_WorldToLight[1] ).xyz;
    texCoord0 = float4( position0, eyeZ );
    texCoord1 = float4( position1, 1.0 );
}

void
GetShadowMapPositions1CSM(
    in float3 positionWorld,
    in float eyeZ,
    out float4 texCoord0 )
{
    float3 position0 = mul( float4( positionWorld,1 ), ShadowMap_WorldToLight[0] ).xyz;
    texCoord0 = float4( position0, eyeZ );
}

float ApplyFade( float factor, float fadeValue )
{
    return factor * fadeValue + (float)1 - fadeValue;
}

float
CalcShadowFactor3CSM(
 in float4   lLightSpacePosPacked0,
    in float4   lLightSpacePosPacked1,
    in float     NDotL )
{
#ifdef D_PLATFORM_BPR
    // Remastered: the PS picks the cascade itself from the world position in
    // lLightSpacePosPacked1 (see GetShadowMapPositions3CSM).
    float  eyeZ = lLightSpacePosPacked0.w;
    float  factor;
    if ( eyeZ > 140.0 )
    {
        factor = 0.0;
    }
    else
    {
        float3 centre, stepU, stepV;
        ShadowSteps_BPR( lLightSpacePosPacked1.xyz, eyeZ, centre, stepU, stepV );
#ifdef SHADOW_APPLY_Z_BIAS
        centre.z -= ShadowMap_Constants2.z * SHADOW_Z_BIAS_VALUE;
#endif
        factor = ShadowPCF_BPR( centre, stepU, stepV, eyeZ );
    }
    float cutoffFactor = saturate( ( NDotL - 0.25 ) * 20.0 );
    float fadeValue    = saturate( (float)ShadowMap_Constants.w - eyeZ * (float)ShadowMap_Constants2.w );
    return ApplyFade( factor * cutoffFactor, fadeValue );
#else
    float3 lLightSpacePos0 = lLightSpacePosPacked0.xyz;
    float3 lLightSpacePos1 = float3( lLightSpacePosPacked1.xy, lLightSpacePosPacked0.z );
    float3 lLightSpacePos2 = float3( lLightSpacePosPacked1.zw, lLightSpacePosPacked0.z );
    float3 lLightSpacePos1or2   = ( lLightSpacePosPacked0.w < ShadowMap_Constants.y ? lLightSpacePos1 : lLightSpacePos2 );
    float3 tc3                  = ( lLightSpacePosPacked0.w < ShadowMap_Constants.x ? lLightSpacePos0 : lLightSpacePos1or2 );
    float3 metaMapTexCoord      = tc3;
#ifdef D_SOFT_SHADOWS
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, metaMapTexCoord, lLightSpacePosPacked0.w );
#else
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, metaMapTexCoord );
#endif
    float cutoffFactor = saturate( ( NDotL - 0.25 ) * 20.0 );
    float fadeValue    = saturate( (float)ShadowMap_Constants.w - (float)lLightSpacePosPacked0.w * (float)ShadowMap_Constants2.w );
    return ApplyFade( factor * cutoffFactor, fadeValue );
#endif
}

#ifdef D_PLATFORM_X360
// X360 anisotropic variant, which got culled when the source was preprocessed for TUB PC
// Currently we just call the standard 3CSM until we decompile the 360 version of the function
float
CalcShadowFactor3CSM_X360_Aniso(
 in float4   lLightSpacePosPacked0,
    in float4   lLightSpacePosPacked1,
    in float     NDotL )
{
    return CalcShadowFactor3CSM( lLightSpacePosPacked0, lLightSpacePosPacked1, NDotL );
}
#endif

float
CalcShadowFactor2CSM(
 in float4   lLightSpacePosPacked0,
    in float4   lLightSpacePosPacked1,
    in float     NDotL )
{
    float3 lLightSpacePos0 = lLightSpacePosPacked0.xyz;
    float3 lLightSpacePos1 = lLightSpacePosPacked1.xyz;
    float3 lLightSpacePos0or1   = ( lLightSpacePosPacked0.w < ShadowMap_Constants.x ? lLightSpacePos0 : lLightSpacePos1 );
    float3 metaMapTexCoord      = lLightSpacePos0or1;
#ifdef D_SOFT_SHADOWS
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, metaMapTexCoord, lLightSpacePosPacked0.w );
#else
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, metaMapTexCoord );
#endif
    float cutoffFactor = saturate( ( NDotL - 0.25 ) * 20.0 );
    factor *= cutoffFactor;
    return ( lLightSpacePosPacked0.w<(float)ShadowMap_Constants.y ) ? factor : 0.75;
}

float
CalcShadowFactor2CSMSelect(
 in float4   lLightSpacePosPacked0,
    in float4   lLightSpacePosPacked1,
    in float     NDotL )
{
    float3 lLightSpacePos0 = lLightSpacePosPacked0.xyz;
    float3 lLightSpacePos1 = lLightSpacePosPacked1.xyz;
    float3 lLightSpacePos0or1   = ( lLightSpacePosPacked0.w < lLightSpacePosPacked1.w ? lLightSpacePos0 : lLightSpacePos1 );
    float3 metaMapTexCoord      = lLightSpacePos0or1;
#ifdef D_PLATFORM_BPR
    // Remastered (Foliage_1Bit_Doublesided, the only user): the shared PCF with no tap
    // spread, and no NdotL cutoff.
    float factor;
    if ( lLightSpacePosPacked0.w > 140.0 )
    {
        factor = 0.0;
    }
    else
    {
        factor = ShadowPCF_BPR( metaMapTexCoord, (float3)0, (float3)0, lLightSpacePosPacked0.w );
    }
    float fadeValue    = saturate( (float)ShadowMap_Constants.w - (float)lLightSpacePosPacked0.w * (float)ShadowMap_Constants2.w );
    return ApplyFade( factor, fadeValue );
#else
#ifdef D_SOFT_SHADOWS
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, metaMapTexCoord, lLightSpacePosPacked0.w );
#else
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, metaMapTexCoord );
#endif
    float cutoffFactor = saturate( ( NDotL - 0.25 ) * 20.0 );
    float fadeValue    = saturate( (float)ShadowMap_Constants.w - (float)lLightSpacePosPacked0.w * (float)ShadowMap_Constants2.w );
    return ApplyFade( factor * cutoffFactor, fadeValue );
#endif
}

float
CalcShadowFactor1CSM(
 in float4   lLightSpacePosPacked0,
    in float     NDotL )
{
    float3 lLightSpacePos0 = lLightSpacePosPacked0.xyz;
#ifdef D_SOFT_SHADOWS
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, lLightSpacePos0, 0.0 );
#else
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, lLightSpacePos0 );
#endif
    float cutoffFactor = saturate( ( NDotL - 0.25 ) * 20.0 );
    float fadeValue    = saturate( (float)ShadowMap_Constants.w - ( (float)lLightSpacePosPacked0.w/(float)ShadowMap_Constants.x ) * (float)ShadowMap_Constants.w );
    return ApplyFade( factor * cutoffFactor, fadeValue );
}

float
CalcShadowFactorCSM_Vehicle_Damaged_2CSM_Select
(
    in float4   lLightSpacePosPacked0,
    in float4   lLightSpacePosPacked1,
    in float     NDotL,
    in float     damage )
{
    float3 lLightSpacePos0 = lLightSpacePosPacked0.xyz;
    float3 lLightSpacePos1 = lLightSpacePosPacked1.xyz;
    float3 lLightSpacePos0or1 = ( lLightSpacePosPacked0.w < lLightSpacePosPacked1.w ? lLightSpacePos0 : lLightSpacePos1 );
    float3 metaMapTexCoord    = lLightSpacePos0or1;
#ifdef D_PLATFORM_BPR
    // Remastered: the shared PCF, centred on the biased cascade position the VS picked.
    float  eyeZ = lLightSpacePosPacked0.w;
    float  factor;
    if ( eyeZ > 140.0 )
    {
        factor = 0.0;
    }
    else
    {
        float damageBiasModifier = saturate( damage - 0.05 ) * 0.002;
        float biasFactor = 1.0 - NDotL * NDotL;
        float nearBias   = min( -0.00019 * biasFactor, -0.000051 ) - damageBiasModifier;
        metaMapTexCoord.z+=nearBias * ShadowMap_Constants2.z;
        float3 origin, stepU, stepV;
        ShadowSteps_BPR( lLightSpacePosPacked1.xyz, eyeZ, origin, stepU, stepV );
        factor = ShadowPCF_BPR( metaMapTexCoord, stepU, stepV, eyeZ );
    }
#else
    float damageBiasModifier = saturate( damage - 0.05 ) * 0.002;
    float biasFactor = 1.0 - NDotL * NDotL;
    float nearBias   = min( -0.00019 * biasFactor, -0.000051 ) - damageBiasModifier;
    metaMapTexCoord.z+=nearBias * ShadowMap_Constants2.z;
#endif
#if defined(D_PLATFORM_BPR)
#elif defined(D_SOFT_SHADOWS)
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, metaMapTexCoord, lLightSpacePosPacked0.w );
#else
    float factor = CalcOrthoShadowFactorBySampler( shadowMapSamplerHighDetail, metaMapTexCoord );
#endif
    float cutoffFactor = saturate( ( NDotL - 0.25 ) * 20.0 );
    return factor * cutoffFactor;
}

#endif
