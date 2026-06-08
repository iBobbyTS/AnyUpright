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

static float coverageInside(float signedOutsideDistance)
{
    float aa = max(fwidth(signedOutsideDistance), 0.75);
    return 1.0 - smoothstep(-aa, aa, signedOutsideDistance);
}

static float coverageWithinRadius(float distance, float radius)
{
    float aa = max(fwidth(distance), 0.75);
    return 1.0 - smoothstep(radius - aa, radius + aa, distance);
}

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

    if (warpState->renderMode == AURM_SourceQuadAdjusterPreview) {
        float3 sourceHomogeneous = warpState->fallbackOutputToSource * float3(in.outputCoordinate, 1.0);
        if (fabs(sourceHomogeneous.z) < 0.000001) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        float2 sourcePixel = sourceHomogeneous.xy / sourceHomogeneous.z;
        float2 sourceUV = sourcePixel / warpState->inputSize;
        if (sourceUV.x < 0.0 || sourceUV.x > 1.0 || sourceUV.y < 0.0 || sourceUV.y > 1.0) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        float4 color = float4(colorTexture.sample(textureSampler, sourceUV));
        float3 selectionHomogeneous = warpState->selectionOutputToRect * float3(in.outputCoordinate, 1.0);
        if (fabs(selectionHomogeneous.z) < 0.000001) {
            color.rgb *= 0.70;
            return color;
        }

        float2 rectPoint = selectionHomogeneous.xy / selectionHomogeneous.z;
        float2 outputSize = warpState->outputSize;
        float borderDistance = min(
            min(abs(rectPoint.x), abs(outputSize.x - rectPoint.x)),
            min(abs(rectPoint.y), abs(outputSize.y - rectPoint.y))
        );
        float outsideDistance = max(
            max(-rectPoint.x, rectPoint.x - outputSize.x),
            max(-rectPoint.y, rectPoint.y - outputSize.y)
        );
        float insideSelection = coverageInside(outsideDistance);

        color.rgb *= mix(0.70, 1.0, insideSelection);

        float2 handleCenters[4] = {
            warpState->sourceQuadTopLeft,
            warpState->sourceQuadTopRight,
            warpState->sourceQuadBottomRight,
            warpState->sourceQuadBottomLeft
        };

        float handleDistance = 1000000.0;
        for (int i = 0; i < 4; ++i) {
            handleDistance = min(handleDistance, length(in.outputCoordinate - handleCenters[i]));
        }

        float edgeCoverage = coverageWithinRadius(max(outsideDistance, 0.0), 4.0);
        float edgeShadow = edgeCoverage * coverageWithinRadius(borderDistance, 5.0);
        float edgeLine = edgeCoverage * coverageWithinRadius(borderDistance, 3.0);
        float handleShadow = coverageWithinRadius(handleDistance, 22.0);
        float handleFill = coverageWithinRadius(handleDistance, 16.0);

        color.rgb = mix(color.rgb, float3(0.0, 0.0, 0.0), edgeShadow * 0.70);
        color.rgb = mix(color.rgb, float3(1.0, 1.0, 1.0), edgeLine);
        color.rgb = mix(color.rgb, float3(0.0, 0.0, 0.0), handleShadow * 0.70);
        color.rgb = mix(color.rgb, float3(0.0, 0.55, 1.0), handleFill);

        return color;
    }

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
