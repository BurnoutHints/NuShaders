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
float4 AnimPrivate
<
 string scope = "material";
 string purpose = "none";
> = {0.0f, 0.0f, 0.0f, 0.0f};
float AnimDuration 
<
 string scope = "material";
 string purpose = "none"; 
 string cpu = "true";
 string UIWidget = "slider";
    float UIMin = -100.0;
    float UIMax = 100.0;
    float UIStep = 1.0;
    string UIName = "animation duration";
> = 0;
float AnimNumberOfFramesU
<
 string scope = "material";
 string purpose = "none"; 
 string cpu = "true";
 string UIWidget = "slider";
    float UIMin = 0.0;
    float UIMax = 100.0;
    float UIStep = 1.0;
    string UIName = "animation number of frames";
> = 0;
float AnimNumberOfFramesV
<
 string scope = "material";
 string purpose = "none"; 
 string cpu = "true";
 string UIWidget = "slider";
    float UIMin = 0.0;
    float UIMax = 100.0;
    float UIStep = 1.0;
    string UIName = "animation number of frames in V";
> = 0;
float2 AnimateUV(float2 input)
{
 return input + AnimPrivate.xy;
}
#include "../Include/DepthEncode.fxh"
#ifdef D_OREN_NAYAR
#include "../Include/OrenNayar.fxh"
#endif
float3   KeyLightDirection
<
 string scope = "global";
>;
float3   ViewPosition    : cameraposition
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
 string purpose = "none";
    string UIWidget = "rgba";
> = {1.0f, 1.0f, 1.0f, 1.0f};
texture2D DiffuseTexture : diffuse
<
 string scope = "material";
>;
texture2D IllumTexture
<
 string scope = "material";
>;
texture2D AnimTexture
<
 string scope = "material";
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
SAMPLER_2D(IllumTextureSampler, 1,
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <IllumTexture>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
SAMPLER_2D(AnimTextureSampler, 2,
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <AnimTexture>;
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
    float3 texCoordDiffuseAndFog : TEXCOORD0;
    SHADOWMAP_INTERPOLATORS2( 1,2 ) 
    float4 IndirectColourAndKey  : TEXCOORD3;
    float2 texCoordAnim    : TEXCOORD4;
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
    float3 texCoordDiffuseAndFog : TEXCOORD0;
 float4 LightSpacePosFar   : TEXCOORD1;
    float4 IndirectColourAndKey  : TEXCOORD2;
};
vertexOutput VS_Main(vertexInput IN
                     ) 
{
    vertexOutput OUT;
        float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;           
    float3 WorldSpaceNormal  = normalize( mul( IN.normal, (float3x3)world ) );             
    OUT.hPosition    = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.texCoordDiffuseAndFog.xy = IN.texCoordDiffuse;
    OUT.texCoordAnim.xy = AnimateUV(float2(0,0));
    OUT.IndirectColourAndKey.xyz = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.w = dot( WorldSpaceNormal, -KeyLightDirection ); 
    float3 lEyeToVertex    = ViewPosition.xyz - WorldSpacePosition;
    OUT.texCoordDiffuseAndFog.z = CalculateScattering( length( lEyeToVertex ) );
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
 float4 diffuseTexture = tex2D( DiffuseTextureSampler, IN.texCoordDiffuseAndFog.xy );
 ALPHA_TEST( diffuseTexture.a );
 float illumTexture = tex2D( IllumTextureSampler, IN.texCoordDiffuseAndFog.xy ).g;
 float lf2xWhiteLevel = (float)FogColourPlusWhiteLevel.w + (float)FogColourPlusWhiteLevel.w;
 illumTexture *= lf2xWhiteLevel;
 float animTexture = tex2D( AnimTextureSampler, IN.texCoordAnim.xy ).g;
 illumTexture = lerp(0.0f, illumTexture, animTexture);
 float  lNormalDotLight  = (lfFace<0) ? (float)IN.IndirectColourAndKey.w : (float)-IN.IndirectColourAndKey.w;
    float lShadowModulation = CALC_SHADOW_FACTOR_3( lNormalDotLight  );
#ifdef D_OREN_NAYAR
    float  lDirectLightFactor   = ComputeOrenNayarDiffuse( normalize(IN.WorldNormal), (float3)-KeyLightDirection, normalize(IN.ViewDirection), 0.1 ) * lShadowModulation;
#else
    float  lDirectLightFactor   = saturate( lNormalDotLight * lShadowModulation );
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = max( illumTexture, ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor ) ) * float3(materialDiffuse.xyz);
    float3 lFinalColour         = (diffuseTexture.rgb * lLightColour);
    lFinalColour = lerp( lFinalColour, float3(FogColourPlusWhiteLevel.rgb), float(IN.texCoordDiffuseAndFog.z) );
#ifdef D_MRT
    oColour0 = float4(lFinalColour, diffuseTexture.a);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth );
#else
    return float4(lFinalColour, diffuseTexture.a);
#endif
}
technique Default
<
>
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



