#include <metal_stdlib>
using namespace metal;

// Compute Kernel Function
kernel void solve_vertex(texture2d<float, access::read> depthTexture [[ texture(0) ]],
                         constant float3x3& cameraIntrinsics [[ buffer(0) ]],
                         device float3* worldCoords [[ buffer(1) ]],
                         device float2* xyCoords [[ buffer(2) ]],
                         uint vid [[ thread_position_in_grid ]])
{
    uint2 pos;
    pos.y = vid / depthTexture.get_width();
    pos.x = vid % depthTexture.get_width();

    float depth = depthTexture.read(pos).x * 1000.0f;

    float xrw = (pos.x - cameraIntrinsics[2][0]) * depth / cameraIntrinsics[0][0];
    float yrw = (pos.y - cameraIntrinsics[2][1]) * depth / cameraIntrinsics[1][1];

    worldCoords[vid] = float3(xrw, yrw, depth);
}

typedef struct
{
    float4 clipSpacePosition [[position]];
    float2 coor;
    float pSize [[point_size]];
    float depth;
    float4 color;
    float3 worldPosition;
} RasterizerDataColor;

// Vertex Function
vertex RasterizerDataColor
vertexShaderPoints(uint vertexID [[ vertex_id ]],
                   constant float4x4& viewMatrix [[ buffer(0) ]],
                   constant float3* worldCoords [[ buffer(1) ]])
{
    RasterizerDataColor out;

    float3 worldPos = worldCoords[vertexID];

    float4 xyzw = float4(worldPos, 1.0);

    out.clipSpacePosition = viewMatrix * xyzw;
    out.coor = { vertexID % 640 / 639.0, vertexID / 640 / 479.0 }; // Assuming 640x480 resolution
    out.depth = worldPos.z;
    out.pSize = 5.0f;
    out.worldPosition = worldPos;

    return out;
}

fragment float4 fragmentShaderPoints(RasterizerDataColor in [[stage_in]],
                                     texture2d<float> colorTexture [[ texture(0) ]])
{
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    const float4 colorSample = colorTexture.sample(textureSampler, in.coor);
    return colorSample;
}
