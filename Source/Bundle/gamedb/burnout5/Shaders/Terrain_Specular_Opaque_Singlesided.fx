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
 string UIWidget = "Slider";
 float UIMin = 1.0;
 float UIMax = 128.0;
 float UIStep = 1.0;
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
float SpecMapContrast
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.0;
    float UIMax = 2.0;
    float UIStep = 0.01;
> = 0.5;
float slantedFacelimit 
<
 string scope = "material";
    string UIWidget = "slider";
 float UIMin = 0.0;
 float UIMax = 1.0;
 float UIStep = 0.01;
> = 0.5;
float verticalFacelimit 
<
 string scope = "material";
    string UIWidget = "slider";
 float UIMin = 0.0;
 float UIMax = 1.0;
 float UIStep = 0.01;
> = 0.0;
float horizontalFacelimit 
<
 string scope = "material";
    string UIWidget = "slider";
 float UIMin = 0.0;
 float UIMax = 1.0;
 float UIStep = 0.01;
> = 0.8;
float slantedFaceTile 
<
 string scope = "material";
    string UIWidget = "slider";
 float UIMin = 1.0;
 float UIMax = 32.0;
 float UIStep = 1.0;
> = 1.0;
float horizontalFaceTile 
<
 string scope = "material";
    string UIWidget = "slider";
 float UIMin = 1.0;
 float UIMax = 32.0;
 float UIStep = 1.0;
> = 1.0;
float verticalFaceTile 
<
 string scope = "material";
    string UIWidget = "slider";
 float UIMin = 1.0;
 float UIMax = 32.0;
 float UIStep = 0.01;
> = 1.0;
texture2D VerticalFaceTexture : diffuse
<
 string scope = "material";
 string purpose = "none";
>;
texture2D SlantedFaceTexture
<
 string scope = "material";
 string purpose = "none";
>;
texture2D HorizontalFaceTexture
<
 string scope = "material";
 string purpose = "none";
>;
SAMPLER_2D(VerticalFaceTextureSampler, 0, 
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <VerticalFaceTexture>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
SAMPLER_2D(SlantedFaceTextureSampler, 1, 
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <SlantedFaceTexture>;
 MinFilter = Linear;
 MagFilter = Linear;
 MipFilter = Linear;
});
SAMPLER_2D(HorizontalFaceTextureSampler, 2, 
<
 string scope = "material";
 string purpose = "none";
> = sampler_state
{
 Texture = <HorizontalFaceTexture>;
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
 float3 WorldSpaceNormal   : TEXCOORD2;
    SHADOWMAP_INTERPOLATORS2( 3,4 ) 
    float4 IndirectColourAndKey  : TEXCOORD5;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD6;
#endif
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    float3 ViewDirection            : TEXCOORD7;
#endif
};
struct vertexOutputLod1 {
    float4 hPosition    : POSITION;
    float2 texCoordDiffuse   : TEXCOORD0;
 float4 ReflectionVectorAndFog : TEXCOORD1;
 float3 WorldSpaceNormal   : TEXCOORD2;
 float4 LightSpacePosFar         : TEXCOORD3;
    float4 IndirectColourAndKey  : TEXCOORD4;
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
    CALC_SHADOWMAP_INTERPOLATORS3( WorldSpacePosition, OUT.hPosition.w );    
    OUT.IndirectColourAndKey.xyz = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.w   = dot( WorldSpaceNormal, -KeyLightDirection ); 
    float3 lEyeToVertex = ViewPosition.xyz - WorldSpacePosition;
    float3 lReflection  = ( WorldSpaceNormal * ( 2.0f * dot( lEyeToVertex, WorldSpaceNormal ) ) ) - lEyeToVertex;
    OUT.ReflectionVectorAndFog.xyz = lReflection;
    OUT.WorldSpaceNormal = WorldSpaceNormal;
    OUT.ReflectionVectorAndFog.w = CalculateScattering( length( lEyeToVertex ) );
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    OUT.ViewDirection = normalize( ViewPosition.xyz - WorldSpacePosition );
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
 float3 baseTex = tex2D( VerticalFaceTextureSampler, IN.texCoordDiffuse * verticalFaceTile ).rgb;
 float3 slantedFaceTexture = tex2D( SlantedFaceTextureSampler, IN.texCoordDiffuse * slantedFaceTile ).rgb;
 float3 horizontalFaceTexture = tex2D( HorizontalFaceTextureSampler, IN.texCoordDiffuse * horizontalFaceTile ).rgb;
    float lerpValue;
    float3 verticalFaceTexture;
 lerpValue = smoothstep(verticalFacelimit, slantedFacelimit, float(IN.WorldSpaceNormal.y));
 verticalFaceTexture = lerp(baseTex, slantedFaceTexture, lerpValue);
 lerpValue = smoothstep(horizontalFacelimit, 1.0, float(IN.WorldSpaceNormal.y));
 verticalFaceTexture = lerp(verticalFaceTexture, horizontalFaceTexture, lerpValue);
    float3 lLightDirection = (float3)-KeyLightDirection;
    float3 lReflectionVector = (float3)IN.ReflectionVectorAndFog.xyz;
    float  lrSpecularPower = (float)SpecularPower;
    float3 lReflection = normalize( lReflectionVector );
    float  lrRdotL = saturate( dot( lReflection, lLightDirection ) );
    float3 lSpecularColour = float3(KeyLightSpecularColour) * ( Specularity * pow( lrRdotL, lrSpecularPower ) );
    lSpecularColour *= ( ( ( max(verticalFaceTexture.x, verticalFaceTexture.y) - 0.5 ) * SpecMapContrast ) + 0.5 );
    float lShadowModulation = CALC_SHADOW_FACTOR_3( (float)IN.IndirectColourAndKey.w );
#ifdef D_OREN_NAYAR
    float  lDirectLightFactor   = ComputeOrenNayarDiffuse( normalize(IN.WorldSpaceNormal), (float3)-KeyLightDirection, normalize(IN.ViewDirection), 0.1 ) * lShadowModulation;
#else
    float  lDirectLightFactor   = saturate( (float)IN.IndirectColourAndKey.w ) * lShadowModulation;
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor ) * float3(materialDiffuse.xyz);
    float3 lFinalColour         = (verticalFaceTexture * lLightColour) + (lSpecularColour * lShadowModulation);
    lFinalColour = lerp( lFinalColour, FogColourPlusWhiteLevel.rgb, IN.ReflectionVectorAndFog.w );
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



