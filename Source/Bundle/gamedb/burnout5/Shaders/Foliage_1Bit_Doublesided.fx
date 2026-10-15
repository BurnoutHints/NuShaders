#include "../Include/Platform.fxh"
#include "../Include/Transform.fxh"
#define SHADOW_APPLY_Z_BIAS
#define SHADOW_Z_BIAS_VALUE 0.0030
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
float4   Time : time
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
float4x4  world      : World
<
 string scope = "object";
>;
float4 materialDiffuse
<
 string scope = "material";
 string purpose = "none";
    string UIWidget = "rgba";
> = {1.0f, 1.0f, 1.0f, 1.0f};
float amplitude
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.01f;
    float UIMax = 1.0f;
    float UIStep = 0.01f;
> = 0.2f;
float wavelength
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.01f;
    float UIMax = 10.0f;
    float UIStep = 0.01f;
> = 3.0f;
float speed
<
 string scope = "material";
    string UIWidget = "slider";
    float UIMin = 0.01f;
    float UIMax = 1.0f;
    float UIStep = 0.01f;
> = 0.2f;
texture2D DiffuseTexture : diffuse
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
struct vertexInput {
    float3 position    : POSITION;
    float3 normal    : NORMAL;
    float2 texCoordDiffuse  : TEXCOORD0;
};
struct vertexOutput {
    float4 hPosition    : POSITION;
    float3 texCoordDiffuseAndFog : TEXCOORD0;
    float4 IndirectColourAndKey  : TEXCOORD1;
    SHADOWMAP_INTERPOLATORS2(2,3)
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD5;
#endif
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    float3 WorldNormal              : TEXCOORD6;
    float3 ViewDirection            : TEXCOORD7;
#endif
};
vertexOutput VS_Main(vertexInput IN) 
{
    vertexOutput OUT;
 float angle = Time.x * speed ;
    IN.position.y += (sin((IN.position.x * wavelength) + angle * 1.5)) * amplitude;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    OUT.texCoordDiffuseAndFog.xy = IN.texCoordDiffuse;
    float3 WorldSpaceNormal = mul( IN.position, (float3x3)world );
    WorldSpaceNormal = normalize( WorldSpaceNormal );
    OUT.IndirectColourAndKey.xyz = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.w   = dot( WorldSpaceNormal, -KeyLightDirection ); 
    float3 lEyeToVertex   = ViewPosition.xyz - WorldSpacePosition;
    OUT.texCoordDiffuseAndFog.z = CalculateScattering( length( lEyeToVertex ) );
 float3 ObjectCentreWorldSpace = world[3];
    CALC_SHADOWMAP_INTERPOLATORS2_SELECT_VS( WorldSpacePosition, OUT.hPosition.w, GetViewSpaceDepthFromWorldPosition( ObjectCentreWorldSpace ) );
#if defined(D_OREN_NAYAR) || defined(D_GGX_SPECULAR)
    OUT.WorldNormal = WorldSpaceNormal;
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
 float4 diffuseTexture = tex2D( DiffuseTextureSampler, IN.texCoordDiffuseAndFog.xy );
 ALPHA_TEST( diffuseTexture.a );
 float lShadowModulation = CALC_SHADOW_FACTOR_2_SELECT( (float)IN.IndirectColourAndKey.w );
#ifdef D_OREN_NAYAR
    float  lDirectLightFactor   = ComputeOrenNayarDiffuse( normalize(IN.WorldNormal), (float3)-KeyLightDirection, normalize(IN.ViewDirection), 0.1 ) * lShadowModulation;
#else
    float  lDirectLightFactor   = saturate( (float)IN.IndirectColourAndKey.w ) * lShadowModulation;
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor ) * float3(materialDiffuse.xyz);
    float3 lFinalColour         = (diffuseTexture.rgb * lLightColour);
    lFinalColour = lerp( lFinalColour, FogColourPlusWhiteLevel.rgb, float(IN.texCoordDiffuseAndFog.z) );
#ifdef D_MRT
    oColour0 = float4(lFinalColour, diffuseTexture.a);
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth );
#else
    return float4(lFinalColour, diffuseTexture.a);
#endif
}
technique Default
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
vertexOutputZOnly VS_Main_ZOnly( vertexInputZOnly IN ) 
{ 
    vertexOutputZOnly OUT;
 float angle = Time.x * speed ;
    IN.position.y += (sin((IN.position.x * wavelength) + angle * 1.5)) * amplitude;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
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
technique ZOnlyFoliage1Bit
<
    string sharedName="ZOnlyFoliage1Bit";
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



