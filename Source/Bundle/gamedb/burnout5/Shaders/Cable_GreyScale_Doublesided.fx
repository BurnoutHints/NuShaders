#include "../Include/Platform.fxh"
#include "../Include/Fog.fxh"
#include "../Include/Transform.fxh"
#include "../Include/DepthEncode.fxh"
float3   ViewPosition : cameraposition
<
 string scope = "global";
>;
float3   KeyLightDirection
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
float4x4  world : World
<
 string scope = "object";
>;
float4 materialDiffuse
<
 string scope = "material";
    string UIWidget = "rgba";
> = {0.0f, 0.0f, 0.0f, 1.0f}; 
float nearFadeDistance
<
 string scope = "material";
 string UIWidget = "slider";
    float UIMin = 0.0f;
    float UIMax = 2000.0f;
    float UIStep = 1.0f;
> = 10.0f;
float farFadeDistance
<
 string scope = "material";
 string UIWidget = "slider";
    float UIMin = 0.0f;
    float UIMax = 2000.0f; 
    float UIStep = 1.0f;
> = 200.0f;
struct vertexInput {
    float3 position    : POSITION;
};
struct vertexOutput {
    float4 hPosition   : POSITION;
 float2 FogAndAlpha     : TEXCOORD0;
#ifdef D_MRT
    float2 hPositionDepthCopy   : TEXCOORD1;
#endif
};
vertexOutput VS_Main(vertexInput IN) 
{
    vertexOutput OUT;
    float3 WorldSpacePosition = mul( float4( IN.position, 1.0f ), world ).xyz;
    OUT.hPosition = TransformWorldToProjection( WorldSpacePosition );
#ifdef D_MRT
    OUT.hPositionDepthCopy = OUT.hPosition.zw;
#endif
    float3 lEyeToVertex = ViewPosition.xyz - WorldSpacePosition;
    float  lfDistance = length( lEyeToVertex );
#ifdef D_PLATFORM_BPR
    // Remastered: a fixed 10..500 fade, not the material's near/farFadeDistance (TUB defaults 10..200).
    float  lfAlpha  = saturate( (lfDistance - 10.0f ) / ( 500.0f - 10.0f ) );
#else
    float  lfAlpha  = saturate( (lfDistance - nearFadeDistance ) / ( farFadeDistance - nearFadeDistance ) ); 
#endif
    OUT.FogAndAlpha.x = CalculateScattering( lfDistance );     
    OUT.FogAndAlpha.y = 1.0f - lfAlpha;
    return OUT;
}
#ifdef D_MRT
void PS_Main( in  vertexOutput IN,
              out float4 oColour0 : COLOR0,
              out float4 oColour1 : COLOR1 )
#else
float4 PS_Main( vertexOutput IN ): COLOR
#endif
{
    float  lfWhiteLevel = FogColourPlusWhiteLevel.w;
    float4 lFinalColour = materialDiffuse * lfWhiteLevel;
    lFinalColour.rgb = lerp( lFinalColour.rgb, FogColourPlusWhiteLevel.rgb, float(IN.FogAndAlpha.x) );
    lFinalColour.a = IN.FogAndAlpha.y;
#ifdef D_MRT
    oColour0 = lFinalColour;
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    oColour1 = ConvertDepthToARGB( lfDepth );
#else
    return lFinalColour;
#endif
}
technique Default
{
    pass p0
    { 
  AlphaTestEnable = True;
  AlphaBlendEnable = True;
        AlphaRef = 0;
  AlphaFunc = Greater;
        CullMode = None;
     SrcBlend = SrcAlpha; 
     DestBlend = InvSrcAlpha; 
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
    float lfDepth = ( IN.hPositionDepthCopy.x / IN.hPositionDepthCopy.y );
    return lfDepth.xxxx;
#else
    return float4(1,1,1,1);
#endif
}
technique ZOnlyOpaqueDoubleSided
<
  string sharedName="ZOnlyOpaqueDoubleSided";
>
{
    pass p0
    {  
  CULLMODE = none;
#ifndef D_MSAA_ENABLED
        ColorWriteEnable = 0;
#endif
  VertexShader = compile vs_3_0 VS_Main_ZOnly();
  PixelShader  = compile ps_3_0 PS_Main_ZOnly();
    }
}
