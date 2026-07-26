#include <metal_stdlib>
using namespace metal;

struct AUImageTensorPackConfig {
    uint width;
    uint height;
    uint channelCount;
};

kernel void auPackResampledTextureToNCHW(
    texture2d<float, access::read> source [[texture(0)]],
    device float *output [[buffer(0)]],
    constant AUImageTensorPackConfig &config [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    uint planeSize = config.width * config.height;
    uint outputCount = planeSize * config.channelCount;
    if (id >= outputCount) {
        return;
    }

    uint pixelIndex = id % planeSize;
    uint channel = id / planeSize;
    uint2 position = uint2(pixelIndex % config.width, pixelIndex / config.width);
    float4 color = source.read(position);

    if (config.channelCount == 1) {
        output[id] = clamp(
            dot(color.rgb, float3(0.299f, 0.587f, 0.114f)),
            0.0f,
            1.0f
        );
        return;
    }

    output[id] = color[channel];
}
