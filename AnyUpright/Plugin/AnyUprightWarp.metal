//
//  AnyUprightWarp.metal
//  AnyUpright
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#include "AnyUprightWarpShaderTypes.h"

typedef struct
{
    float4 clipSpacePosition [[position]];
    float2 outputCoordinate;
} RasterizerData;

typedef struct
{
    float4 clipSpacePosition [[position]];
    float4 color;
} OverlayRasterizerData;

vertex RasterizerData anyUprightWarpVertex(uint vertexID [[vertex_id]],
                                           constant AnyUprightVertex2D *vertexArray [[buffer(AUVII_Vertices)]],
                                           constant vector_uint2 *viewportSizePointer [[buffer(AUVII_ViewportSize)]])
{
    RasterizerData out;
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize / 2.0);
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1.0;
    out.outputCoordinate = vertexArray[vertexID].outputCoordinate;

    return out;
}

fragment float4 anyUprightWarpFragment(RasterizerData in [[stage_in]],
                                       texture2d<half> colorTexture [[texture(AUTI_InputImage)]],
                                       constant AnyUprightWarpState *warpState [[buffer(AUFII_WarpState)]])
{
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::clamp_to_zero);

    if (warpState->renderMode == AURM_WarpSelectionOverOriginal) {
        float3 selectionHomogeneous = warpState->selectionOutputToRect * float3(in.outputCoordinate, 1.0);
        if (fabs(selectionHomogeneous.z) >= 0.000001) {
            float2 selectionRect = selectionHomogeneous.xy / selectionHomogeneous.z;
            if (selectionRect.x >= 0.0 && selectionRect.x <= warpState->outputSize.x &&
                selectionRect.y >= 0.0 && selectionRect.y <= warpState->outputSize.y) {
                float3 mirroredSourceHomogeneous = warpState->outputToSource * float3(in.outputCoordinate, 1.0);
                if (fabs(mirroredSourceHomogeneous.z) >= 0.000001) {
                    float2 mirroredSourcePixel = mirroredSourceHomogeneous.xy / mirroredSourceHomogeneous.z;
                    float2 mirroredSourceUV = mirroredSourcePixel / warpState->inputSize;
                    if (mirroredSourceUV.x >= 0.0 && mirroredSourceUV.x <= 1.0 &&
                        mirroredSourceUV.y >= 0.0 && mirroredSourceUV.y <= 1.0) {
                        return float4(colorTexture.sample(textureSampler, mirroredSourceUV));
                    }
                }
            }
        }
    }

    float3 sourceHomogeneous = (warpState->renderMode == AURM_WarpSelectionOverOriginal
                                ? warpState->fallbackOutputToSource
                                : warpState->outputToSource) * float3(in.outputCoordinate, 1.0);
    if (fabs(sourceHomogeneous.z) < 0.000001) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 sourcePixel = sourceHomogeneous.xy / sourceHomogeneous.z;
    float2 sourceUV = sourcePixel / warpState->inputSize;

    if (sourceUV.x < 0.0 || sourceUV.x > 1.0 || sourceUV.y < 0.0 || sourceUV.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    return float4(colorTexture.sample(textureSampler, sourceUV));
}

vertex OverlayRasterizerData anyUprightOverlayVertex(uint vertexID [[vertex_id]],
                                                     constant AnyUprightOverlayVertex2D *vertexArray [[buffer(AUVII_Vertices)]],
                                                     constant vector_uint2 *viewportSizePointer [[buffer(AUVII_ViewportSize)]])
{
    OverlayRasterizerData out;
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize / 2.0);
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1.0;
    out.color = vertexArray[vertexID].color;

    return out;
}

fragment float4 anyUprightOverlayFragment(OverlayRasterizerData in [[stage_in]])
{
    return in.color;
}
