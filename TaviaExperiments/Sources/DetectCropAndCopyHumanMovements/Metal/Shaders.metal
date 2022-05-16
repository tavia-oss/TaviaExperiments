#include <metal_stdlib>
using namespace metal;

float4 ycbcrToRGBTransform(float4 y, float4 CbCr)
{
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f));
    float4 ycbcr = float4(y.r, CbCr.rg, 1.0);
    return ycbcrToRGBTransform * ycbcr;
}

typedef struct {
    float2 position;
    float2 texCoord;
} Vertex;

typedef struct {
    float4 position [[position]];
    float2 texCoordCamera;
    float2 texCoordScene;
} RasterizerData;

vertex RasterizerData vertexShader(
    const device Vertex* cameraVertices [[buffer(0)]],
    const device Vertex* sceneVertices [[buffer(1)]],
    unsigned int vid [[vertex_id]])
{
    RasterizerData out;
    const device Vertex& cv = cameraVertices[vid];
    const device Vertex& sv = sceneVertices[vid];
    out.position = float4(cv.position, 0.0, 1.0);
    out.texCoordCamera = cv.texCoord;
    out.texCoordScene = sv.texCoord;
    return out;
}

fragment half4 fragmentShader(
    RasterizerData in [[stage_in]],
    texture2d<float, access::sample> capturedImageTextureY [[texture(0)]],
    texture2d<float, access::sample> capturedImageTextureCbCr [[texture(1)]],
    texture2d<float, access::sample> sceneColorTexture [[texture(2)]],
    texture2d<float, access::sample> alphaTexture [[texture(3)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 cameraTexCoord = in.texCoordCamera;
    float2 sceneTexCoord = in.texCoordScene;
    float4 rgb = ycbcrToRGBTransform(
        capturedImageTextureY.sample(s, cameraTexCoord),
        capturedImageTextureCbCr.sample(s, cameraTexCoord));
    half4 sceneColor = half4(sceneColorTexture.sample(s, sceneTexCoord));
    half4 cameraColor = half4(rgb);
    half alpha = half(alphaTexture.sample(s, cameraTexCoord).r);
    half4 res = mix(sceneColor, cameraColor, alpha);
    return res;
}
