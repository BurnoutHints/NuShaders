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
float4 materialDiffuseSlantedFace
<
 string scope = "material";
    string UIWidget = "rgba";
> = {1.0f, 1.0f, 1.0f, 1.0f};
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
#ifdef D_PLATFORM_BPR
// Remastered: the vertical/slanted blend, sampling the slanted map only when it shows.
float3 SteepFaces_BPR( float3 baseTex, float2 uv, float slantLerp )
{
    float3 faces;
    if ( slantLerp >= 1.0 )
        faces = tex2D( SlantedFaceTextureSampler, uv * slantedFaceTile ).rgb;
    else if ( slantLerp > 0.0 )
        faces = lerp( baseTex, tex2D( SlantedFaceTextureSampler, uv * slantedFaceTile ).rgb, slantLerp );
    else
        faces = baseTex;
    return faces;
}
#endif
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
    float3 WorldSpaceNormal   : TEXCOORD4;
#ifdef D_MRT
    float2 hPositionDepthCopy       : TEXCOORD5;
#elif defined(D_PLATFORM_BPR)
    float3 ReflectionVector         : TEXCOORD5;    // Remastered: terrain specular
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
    float3 WorldSpaceNormal   : TEXCOORD3;
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
 OUT.WorldSpaceNormal = WorldSpaceNormal;
    OUT.texCoordDiffuseAndFog.xy = IN.texCoordDiffuse;
    OUT.IndirectColourAndKey.xyz = ComputeIrradianceFast( WorldSpaceNormal );
    OUT.IndirectColourAndKey.w = dot( WorldSpaceNormal, -KeyLightDirection ); 
    float3 lEyeToVertex    = ViewPosition.xyz - WorldSpacePosition;
    OUT.texCoordDiffuseAndFog.z = CalculateScattering( length( lEyeToVertex ) );
#ifdef D_PLATFORM_BPR
    OUT.ReflectionVector = ( WorldSpaceNormal * ( 2.0f * dot( lEyeToVertex, WorldSpaceNormal ) ) ) - lEyeToVertex;
#endif
    CALC_SHADOWMAP_INTERPOLATORS3( WorldSpacePosition, OUT.hPosition.w );
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
#ifdef D_PLATFORM_BPR
    // Remastered: sample only the faces that contribute, and add a key-light specular on
    // horizontal faces, masked by a levels curve (in 222, gamma 0.43) of the base texture.
    float2 uv = IN.texCoordDiffuseAndFog.xy;
    float3 baseTex = tex2D( VerticalFaceTextureSampler, uv * verticalFaceTile ).rgb;
    float  flatLerp = smoothstep(horizontalFacelimit, 1.0, float(IN.WorldSpaceNormal.y));
    float3 verticalFaceTexture;
    if ( flatLerp >= 1.0 )
    {
        verticalFaceTexture = tex2D( HorizontalFaceTextureSampler, uv * horizontalFaceTile ).rgb * materialDiffuse.rgb;
    }
    else
    {
        float slantLerp = smoothstep(verticalFacelimit, slantedFacelimit, float(IN.WorldSpaceNormal.y));
        if ( flatLerp > 0.0 )
            verticalFaceTexture = lerp( SteepFaces_BPR( baseTex, uv, slantLerp ), tex2D( HorizontalFaceTextureSampler, uv * horizontalFaceTile ).rgb * materialDiffuse.rgb, flatLerp );
        else
            verticalFaceTexture = SteepFaces_BPR( baseTex, uv, slantLerp );
    }
    float  wetMask  = flatLerp * ( pow( min( max( dot( baseTex, float3( 1, 1, 1 ) ) / 3.0, 0.0 ) * ( 255.0 / 222.0 ), 1.0 ), 1.0 / 0.43 ) * 1.0882354 );
    float3 specular = KeyLightColour * ( pow( saturate( dot( normalize( IN.ReflectionVector ), -KeyLightDirection ) ), 12.0 ) * wetMask );
    specular *= ( max( verticalFaceTexture.r, verticalFaceTexture.g ) - 0.5 ) * 0.5 + 0.5;
#else
    float3 baseTex = tex2D( VerticalFaceTextureSampler, IN.texCoordDiffuseAndFog.xy * verticalFaceTile ).rgb;
 float3 slantedFaceTexture = tex2D( SlantedFaceTextureSampler, IN.texCoordDiffuseAndFog.xy * slantedFaceTile ).rgb;
 float3 horizontalFaceTexture = tex2D( HorizontalFaceTextureSampler, IN.texCoordDiffuseAndFog.xy * horizontalFaceTile ).rgb * materialDiffuse.rgb;
    float lerpValue;
    float3 verticalFaceTexture;
 lerpValue = smoothstep(verticalFacelimit, slantedFacelimit, float(IN.WorldSpaceNormal.y));
 verticalFaceTexture = lerp(baseTex, slantedFaceTexture, lerpValue);
 lerpValue = smoothstep(horizontalFacelimit, 1.0, float(IN.WorldSpaceNormal.y));
 verticalFaceTexture = lerp(verticalFaceTexture, horizontalFaceTexture, lerpValue);
#endif
 float lShadowModulation = CALC_SHADOW_FACTOR_3( (float)IN.IndirectColourAndKey.w );
#ifdef D_OREN_NAYAR
    float  lDirectLightFactor   = ComputeOrenNayarDiffuse( normalize(IN.WorldNormal), (float3)-KeyLightDirection, normalize(IN.ViewDirection), 0.1 ) * lShadowModulation;
#else
    float  lDirectLightFactor   = saturate( (float)IN.IndirectColourAndKey.w ) * lShadowModulation;
#endif
    float3 lDirectLightColour   = float3( KeyLightColour );
    float3 lIndirectLightColour = float3( IN.IndirectColourAndKey.xyz );
    float3 lLightColour         = ( lIndirectLightColour + lDirectLightColour * lDirectLightFactor );
#ifdef D_PLATFORM_BPR
    float3 lFinalColour         = (verticalFaceTexture * lLightColour) + specular;
#else
    float3 lFinalColour         = (verticalFaceTexture * lLightColour);
#endif
    lFinalColour = lerp( lFinalColour.rgb, float3(FogColourPlusWhiteLevel.rgb), float(IN.texCoordDiffuseAndFog.z) );
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



