#include <metal_stdlib>
using namespace metal;

struct AUGeoCalibDirectPreprocessConfig {
    uint inputWidth;
    uint inputHeight;
    uint outputWidth;
    uint outputHeight;
    uint resizedWidth;
    uint resizedHeight;
    uint cropLeft;
    uint cropTop;
    uint kernelWidth;
    uint kernelHeight;
    uint usesAntialias;
};

static uint auReflect101(int value, uint length)
{
    if (length <= 1) {
        return 0;
    }
    int maxIndex = int(length) - 1;
    while (value < 0 || value > maxIndex) {
        if (value < 0) {
            value = -value;
        } else {
            value = 2 * maxIndex - value;
        }
    }
    return uint(value);
}

static float auSourceSample(
    texture2d<float, access::read> source,
    uint channel,
    uint x,
    uint y
) {
    float4 color = source.read(uint2(x, y));
    if (channel == 0) {
        return color.r;
    }
    if (channel == 1) {
        return color.g;
    }
    return color.b;
}

static float auBlurredSample(
    texture2d<float, access::read> source,
    device const float *kernelX,
    device const float *kernelY,
    constant AUGeoCalibDirectPreprocessConfig &config,
    uint channel,
    int centerX,
    int centerY
) {
    if (config.usesAntialias == 0) {
        return auSourceSample(source, channel, uint(centerX), uint(centerY));
    }

    int radiusX = int(config.kernelWidth / 2);
    int radiusY = int(config.kernelHeight / 2);
    float sum = 0.0f;
    for (uint ky = 0; ky < config.kernelHeight; ky++) {
        uint sy = auReflect101(centerY + int(ky) - radiusY, config.inputHeight);
        float wy = kernelY[ky];
        for (uint kx = 0; kx < config.kernelWidth; kx++) {
            uint sx = auReflect101(centerX + int(kx) - radiusX, config.inputWidth);
            sum += auSourceSample(source, channel, sx, sy) * kernelX[kx] * wy;
        }
    }
    return sum;
}

kernel void auGeoCalibDirectPreprocessTextureKernel(
    texture2d<float, access::read> source [[texture(0)]],
    device float *output [[buffer(0)]],
    constant AUGeoCalibDirectPreprocessConfig &config [[buffer(1)]],
    device const float *kernelX [[buffer(2)]],
    device const float *kernelY [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = 3 * config.outputHeight * config.outputWidth;
    if (id >= count) {
        return;
    }

    uint x = id % config.outputWidth;
    uint t = id / config.outputWidth;
    uint y = t % config.outputHeight;
    uint channel = t / config.outputHeight;

    float resizedX = float(config.cropLeft + x);
    float resizedY = float(config.cropTop + y);
    float sourceX = (resizedX + 0.5f) * float(config.inputWidth) / float(config.resizedWidth) - 0.5f;
    float sourceY = (resizedY + 0.5f) * float(config.inputHeight) / float(config.resizedHeight) - 0.5f;
    int floorX = int(floor(sourceX));
    int floorY = int(floor(sourceY));
    uint x0 = min(uint(max(floorX, 0)), config.inputWidth - 1);
    uint y0 = min(uint(max(floorY, 0)), config.inputHeight - 1);
    uint x1 = min(uint(max(floorX + 1, 0)), config.inputWidth - 1);
    uint y1 = min(uint(max(floorY + 1, 0)), config.inputHeight - 1);
    float wx = sourceX - float(floorX);
    float wy = sourceY - float(floorY);

    float v00 = auBlurredSample(source, kernelX, kernelY, config, channel, int(x0), int(y0));
    float v01 = auBlurredSample(source, kernelX, kernelY, config, channel, int(x1), int(y0));
    float v10 = auBlurredSample(source, kernelX, kernelY, config, channel, int(x0), int(y1));
    float v11 = auBlurredSample(source, kernelX, kernelY, config, channel, int(x1), int(y1));

    float top = mix(v00, v01, wx);
    float bottom = mix(v10, v11, wx);
    output[id] = mix(top, bottom, wy);
}
