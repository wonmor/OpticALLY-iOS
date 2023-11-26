#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 coor;
    float pSize [[point_size]];
    float depth;
    float4 color;
} RasterizerDataColor;

// Vertex Function
vertex RasterizerDataColor vertexShaderPoints(uint vertexID [[ vertex_id ]],
                                              texture2d<float, access::read> depthTexture [[ texture(0) ]],
                                              constant float4x4& viewMatrix [[ buffer(0) ]],
                                              constant float3x3& cameraIntrinsics [[ buffer(1) ]]) {
    RasterizerDataColor out;

    // Downsampling factor: Adjust this value to reduce the number of points
    const uint downsamplingFactor = 4;

    // Calculate position with downsampling
    uint2 pos;
    pos.y = (vertexID / depthTexture.get_width()) * downsamplingFactor;
    pos.x = (vertexID % depthTexture.get_width()) * downsamplingFactor;

    // Ensure pos does not exceed texture bounds
    pos.x = min(pos.x, depthTexture.get_width() - 1);
    pos.y = min(pos.y, depthTexture.get_height() - 1);

    // Read depth
    float depth = depthTexture.read(pos).x * 1000.0f;
    
    float xrw = (pos.x - cameraIntrinsics[2][0]) * depth / cameraIntrinsics[0][0];
    float yrw = (pos.y - cameraIntrinsics[2][1]) * depth / cameraIntrinsics[1][1];
    
    float4 xyzw = { xrw, yrw, depth, 1.f };
    
    out.clipSpacePosition = viewMatrix * xyzw;
    out.coor = { pos.x / (float)(depthTexture.get_width() - 1),
                 pos.y / (float)(depthTexture.get_height() - 1) };
    out.depth = depth;
    out.pSize = 5.0f; // Point size can be adjusted as needed

    return out;
}

fragment float4 fragmentShaderPoints(RasterizerDataColor in [[stage_in]],
                                     texture2d<float> colorTexture [[ texture(0) ]]) {
    const float faceMinDepth = 1.0; // Adjust to the minimum depth for face
    const float faceMaxDepth = 1000.0; // Adjust to the maximum depth for face

    // Discard fragment if outside the depth range for the face
    if (in.depth < faceMinDepth || in.depth > faceMaxDepth) {
        discard_fragment();
        return float4(0, 0, 0, 0); // transparent color
    }

    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);
    const float4 colorSample = colorTexture.sample(textureSampler, in.coor);
    return colorSample;
}
