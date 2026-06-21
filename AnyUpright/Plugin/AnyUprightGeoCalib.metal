#include <metal_stdlib>
using namespace metal;

struct Conv2DConfig {
    uint batch;
    uint inChannels;
    uint outChannels;
    uint groups;
    uint inputHeight;
    uint inputWidth;
    uint outputHeight;
    uint outputWidth;
    uint kernelHeight;
    uint kernelWidth;
    uint strideY;
    uint strideX;
    uint paddingY;
    uint paddingX;
};

struct Concat4Config {
    uint batch;
    uint channels0;
    uint channels1;
    uint channels2;
    uint channels3;
    uint height;
    uint width;
};

struct NMFConfig {
    uint d;
    uint n;
    uint r;
    float epsilon;
    float invT;
};

kernel void conv2dNCHWKernel(
    device const float *input [[buffer(0)]],
    device const float *weight [[buffer(1)]],
    device const float *bias [[buffer(2)]],
    device float *output [[buffer(3)]],
    constant Conv2DConfig &config [[buffer(4)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.batch * config.outChannels * config.outputHeight * config.outputWidth;
    if (id >= count) {
        return;
    }

    uint ow = id % config.outputWidth;
    uint t0 = id / config.outputWidth;
    uint oh = t0 % config.outputHeight;
    uint t1 = t0 / config.outputHeight;
    uint oc = t1 % config.outChannels;
    uint b = t1 / config.outChannels;

    uint outChannelsPerGroup = config.outChannels / config.groups;
    uint inChannelsPerGroup = config.inChannels / config.groups;
    uint groupIndex = oc / outChannelsPerGroup;
    uint inputChannelBase = groupIndex * inChannelsPerGroup;

    float sum = bias[oc];
    for (uint localIC = 0; localIC < inChannelsPerGroup; localIC++) {
        uint ic = inputChannelBase + localIC;
        for (uint ky = 0; ky < config.kernelHeight; ky++) {
            int iy = int(oh * config.strideY + ky) - int(config.paddingY);
            if (iy < 0 || iy >= int(config.inputHeight)) {
                continue;
            }
            for (uint kx = 0; kx < config.kernelWidth; kx++) {
                int ix = int(ow * config.strideX + kx) - int(config.paddingX);
                if (ix < 0 || ix >= int(config.inputWidth)) {
                    continue;
                }
                uint inputIndex = ((b * config.inChannels + ic) * config.inputHeight + uint(iy)) * config.inputWidth + uint(ix);
                uint weightIndex = ((oc * inChannelsPerGroup + localIC) * config.kernelHeight + ky) * config.kernelWidth + kx;
                sum += input[inputIndex] * weight[weightIndex];
            }
        }
    }

    output[id] = sum;
}

kernel void affineNCHWKernel(
    device const float *input [[buffer(0)]],
    device const float *scale [[buffer(1)]],
    device const float *offset [[buffer(2)]],
    device float *output [[buffer(3)]],
    constant Conv2DConfig &config [[buffer(4)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.batch * config.outChannels * config.outputHeight * config.outputWidth;
    if (id >= count) {
        return;
    }

    uint spatial = config.outputHeight * config.outputWidth;
    uint oc = (id / spatial) % config.outChannels;
    output[id] = input[id] * scale[oc] + offset[oc];
}

static float erfApprox(float x) {
    float signValue = x < 0.0f ? -1.0f : 1.0f;
    x = fabs(x);
    float t = 1.0f / (1.0f + 0.3275911f * x);
    float y = 1.0f - (((((1.061405429f * t - 1.453152027f) * t) + 1.421413741f) * t - 0.284496736f) * t + 0.254829592f) * t * exp(-x * x);
    return signValue * y;
}

kernel void geluExactKernel(
    device const float *input [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant uint &count [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) {
        return;
    }

    float x = input[id];
    output[id] = 0.5f * x * (1.0f + erfApprox(x * 0.7071067811865476f));
}

kernel void reluKernel(
    device const float *input [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant uint &count [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) {
        return;
    }
    output[id] = max(input[id], 0.0f);
}

kernel void addTensorsKernel(
    device const float *a [[buffer(0)]],
    device const float *b [[buffer(1)]],
    device float *output [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) {
        return;
    }
    output[id] = a[id] + b[id];
}

kernel void multiplyTensorsKernel(
    device const float *a [[buffer(0)]],
    device const float *b [[buffer(1)]],
    device float *output [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) {
        return;
    }
    output[id] = a[id] * b[id];
}

kernel void addScaledChannelsNCHWKernel(
    device const float *residual [[buffer(0)]],
    device const float *branch [[buffer(1)]],
    device const float *scale [[buffer(2)]],
    device float *output [[buffer(3)]],
    constant Conv2DConfig &config [[buffer(4)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.batch * config.outChannels * config.outputHeight * config.outputWidth;
    if (id >= count) {
        return;
    }

    uint spatial = config.outputHeight * config.outputWidth;
    uint channel = (id / spatial) % config.outChannels;
    output[id] = residual[id] + branch[id] * scale[channel];
}

kernel void layerNormChannelsNCHWKernel(
    device const float *input [[buffer(0)]],
    device const float *weight [[buffer(1)]],
    device const float *bias [[buffer(2)]],
    device float *output [[buffer(3)]],
    constant Conv2DConfig &config [[buffer(4)]],
    constant float &epsilon [[buffer(5)]],
    uint id [[thread_position_in_grid]]
) {
    uint spatial = config.outputHeight * config.outputWidth;
    uint count = config.batch * spatial;
    if (id >= count) {
        return;
    }

    uint b = id / spatial;
    uint s = id % spatial;
    uint y = s / config.outputWidth;
    uint x = s % config.outputWidth;

    float mean = 0.0f;
    for (uint c = 0; c < config.outChannels; c++) {
        uint index = ((b * config.outChannels + c) * config.outputHeight + y) * config.outputWidth + x;
        mean += input[index];
    }
    mean /= float(config.outChannels);

    float variance = 0.0f;
    for (uint c = 0; c < config.outChannels; c++) {
        uint index = ((b * config.outChannels + c) * config.outputHeight + y) * config.outputWidth + x;
        float centered = input[index] - mean;
        variance += centered * centered;
    }
    variance /= float(config.outChannels);
    float invStd = rsqrt(variance + epsilon);

    for (uint c = 0; c < config.outChannels; c++) {
        uint index = ((b * config.outChannels + c) * config.outputHeight + y) * config.outputWidth + x;
        output[index] = (input[index] - mean) * invStd * weight[c] + bias[c];
    }
}

kernel void bilinearResizeNCHWKernel(
    device const float *input [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant Conv2DConfig &config [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.batch * config.inChannels * config.outputHeight * config.outputWidth;
    if (id >= count) {
        return;
    }

    uint ow = id % config.outputWidth;
    uint t0 = id / config.outputWidth;
    uint oh = t0 % config.outputHeight;
    uint t1 = t0 / config.outputHeight;
    uint c = t1 % config.inChannels;
    uint b = t1 / config.inChannels;

    float sourceY = (float(oh) + 0.5f) * float(config.inputHeight) / float(config.outputHeight) - 0.5f;
    float sourceX = (float(ow) + 0.5f) * float(config.inputWidth) / float(config.outputWidth) - 0.5f;
    sourceY = clamp(sourceY, 0.0f, float(config.inputHeight - 1));
    sourceX = clamp(sourceX, 0.0f, float(config.inputWidth - 1));

    uint y0 = uint(floor(sourceY));
    uint x0 = uint(floor(sourceX));
    uint y1 = min(y0 + 1, config.inputHeight - 1);
    uint x1 = min(x0 + 1, config.inputWidth - 1);
    float wy = sourceY - float(y0);
    float wx = sourceX - float(x0);

    uint base = (b * config.inChannels + c) * config.inputHeight;
    float v00 = input[(base + y0) * config.inputWidth + x0];
    float v01 = input[(base + y0) * config.inputWidth + x1];
    float v10 = input[(base + y1) * config.inputWidth + x0];
    float v11 = input[(base + y1) * config.inputWidth + x1];

    float top = mix(v00, v01, wx);
    float bottom = mix(v10, v11, wx);
    output[id] = mix(top, bottom, wy);
}

kernel void concat4NCHWKernel(
    device const float *input0 [[buffer(0)]],
    device const float *input1 [[buffer(1)]],
    device const float *input2 [[buffer(2)]],
    device const float *input3 [[buffer(3)]],
    device float *output [[buffer(4)]],
    constant Concat4Config &config [[buffer(5)]],
    uint id [[thread_position_in_grid]]
) {
    uint totalChannels = config.channels0 + config.channels1 + config.channels2 + config.channels3;
    uint count = config.batch * totalChannels * config.height * config.width;
    if (id >= count) {
        return;
    }

    uint x = id % config.width;
    uint t0 = id / config.width;
    uint y = t0 % config.height;
    uint t1 = t0 / config.height;
    uint c = t1 % totalChannels;
    uint b = t1 / totalChannels;

    device const float *source = input0;
    uint sourceChannel = c;
    uint sourceChannels = config.channels0;
    if (c >= config.channels0 + config.channels1 + config.channels2) {
        source = input3;
        sourceChannel = c - config.channels0 - config.channels1 - config.channels2;
        sourceChannels = config.channels3;
    } else if (c >= config.channels0 + config.channels1) {
        source = input2;
        sourceChannel = c - config.channels0 - config.channels1;
        sourceChannels = config.channels2;
    } else if (c >= config.channels0) {
        source = input1;
        sourceChannel = c - config.channels0;
        sourceChannels = config.channels1;
    }

    uint sourceIndex = ((b * sourceChannels + sourceChannel) * config.height + y) * config.width + x;
    output[id] = source[sourceIndex];
}

kernel void nmfXTBasesKernel(
    device const float *input [[buffer(0)]],
    device const float *bases [[buffer(1)]],
    device float *output [[buffer(2)]],
    constant NMFConfig &config [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.n * config.r;
    if (id >= count) {
        return;
    }

    uint rIndex = id % config.r;
    uint nIndex = id / config.r;
    float sum = 0.0f;
    for (uint dIndex = 0; dIndex < config.d; dIndex++) {
        sum += input[dIndex * config.n + nIndex] * bases[dIndex * config.r + rIndex];
    }
    output[id] = sum;
}

kernel void nmfSoftmaxRowsKernel(
    device float *values [[buffer(0)]],
    constant NMFConfig &config [[buffer(1)]],
    uint row [[thread_position_in_grid]]
) {
    if (row >= config.n) {
        return;
    }

    uint base = row * config.r;
    float maxValue = values[base] * config.invT;
    for (uint index = 1; index < config.r; index++) {
        maxValue = max(maxValue, values[base + index] * config.invT);
    }

    float sum = 0.0f;
    for (uint index = 0; index < config.r; index++) {
        float value = exp(values[base + index] * config.invT - maxValue);
        values[base + index] = value;
        sum += value;
    }

    float invSum = 1.0f / sum;
    for (uint index = 0; index < config.r; index++) {
        values[base + index] *= invSum;
    }
}

kernel void nmfBasesGramKernel(
    device const float *bases [[buffer(0)]],
    device float *gram [[buffer(1)]],
    constant NMFConfig &config [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.r * config.r;
    if (id >= count) {
        return;
    }

    uint col = id % config.r;
    uint row = id / config.r;
    float sum = 0.0f;
    for (uint dIndex = 0; dIndex < config.d; dIndex++) {
        sum += bases[dIndex * config.r + row] * bases[dIndex * config.r + col];
    }
    gram[id] = sum;
}

kernel void nmfCoefTimesGramKernel(
    device const float *coef [[buffer(0)]],
    device const float *gram [[buffer(1)]],
    device float *output [[buffer(2)]],
    constant NMFConfig &config [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.n * config.r;
    if (id >= count) {
        return;
    }

    uint col = id % config.r;
    uint row = id / config.r;
    float sum = 0.0f;
    for (uint k = 0; k < config.r; k++) {
        sum += coef[row * config.r + k] * gram[k * config.r + col];
    }
    output[id] = sum;
}

kernel void nmfUpdateInPlaceKernel(
    device float *values [[buffer(0)]],
    device const float *numerator [[buffer(1)]],
    device const float *denominator [[buffer(2)]],
    constant float &epsilon [[buffer(3)]],
    constant uint &count [[buffer(4)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) {
        return;
    }

    values[id] = values[id] * numerator[id] / (denominator[id] + epsilon);
}

kernel void nmfXCoefKernel(
    device const float *input [[buffer(0)]],
    device const float *coef [[buffer(1)]],
    device float *output [[buffer(2)]],
    constant NMFConfig &config [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.d * config.r;
    if (id >= count) {
        return;
    }

    uint rIndex = id % config.r;
    uint dIndex = id / config.r;
    float sum = 0.0f;
    for (uint nIndex = 0; nIndex < config.n; nIndex++) {
        sum += input[dIndex * config.n + nIndex] * coef[nIndex * config.r + rIndex];
    }
    output[id] = sum;
}

kernel void nmfCoefGramKernel(
    device const float *coef [[buffer(0)]],
    device float *gram [[buffer(1)]],
    constant NMFConfig &config [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.r * config.r;
    if (id >= count) {
        return;
    }

    uint col = id % config.r;
    uint row = id / config.r;
    float sum = 0.0f;
    for (uint nIndex = 0; nIndex < config.n; nIndex++) {
        sum += coef[nIndex * config.r + row] * coef[nIndex * config.r + col];
    }
    gram[id] = sum;
}

kernel void nmfBasesTimesGramKernel(
    device const float *bases [[buffer(0)]],
    device const float *gram [[buffer(1)]],
    device float *output [[buffer(2)]],
    constant NMFConfig &config [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.d * config.r;
    if (id >= count) {
        return;
    }

    uint col = id % config.r;
    uint row = id / config.r;
    float sum = 0.0f;
    for (uint k = 0; k < config.r; k++) {
        sum += bases[row * config.r + k] * gram[k * config.r + col];
    }
    output[id] = sum;
}

kernel void nmfBasesCoefTKernel(
    device const float *bases [[buffer(0)]],
    device const float *coef [[buffer(1)]],
    device float *output [[buffer(2)]],
    constant NMFConfig &config [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    uint count = config.d * config.n;
    if (id >= count) {
        return;
    }

    uint nIndex = id % config.n;
    uint dIndex = id / config.n;
    float sum = 0.0f;
    for (uint rIndex = 0; rIndex < config.r; rIndex++) {
        sum += bases[dIndex * config.r + rIndex] * coef[nIndex * config.r + rIndex];
    }
    output[id] = sum;
}

kernel void normalize2ChannelNCHWKernel(
    device const float *input [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant Conv2DConfig &config [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    uint spatial = config.outputHeight * config.outputWidth;
    uint count = config.batch * spatial;
    if (id >= count) {
        return;
    }

    uint b = id / spatial;
    uint s = id % spatial;
    uint y = s / config.outputWidth;
    uint x = s % config.outputWidth;
    uint index0 = ((b * 2) * config.outputHeight + y) * config.outputWidth + x;
    uint index1 = ((b * 2 + 1) * config.outputHeight + y) * config.outputWidth + x;
    float v0 = input[index0];
    float v1 = input[index1];
    float norm = max(sqrt(v0 * v0 + v1 * v1), 1.0e-12f);
    output[index0] = v0 / norm;
    output[index1] = v1 / norm;
}

kernel void sigmoidKernel(
    device const float *input [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant uint &count [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) {
        return;
    }
    output[id] = 1.0f / (1.0f + exp(-input[id]));
}

kernel void latitudeFieldKernel(
    device const float *input [[buffer(0)]],
    device float *output [[buffer(1)]],
    constant uint &count [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= count) {
        return;
    }
    float value = tanh(input[id]);
    value = clamp(value, -0.99999f, 0.99999f);
    output[id] = asin(value);
}
