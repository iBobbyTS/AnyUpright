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

static float2 clampedImageCoordinate(float2 outputCoordinate, constant AnyUprightWarpState *warpState)
{
    return clamp(outputCoordinate, warpState->imageCoordinateMin, warpState->imageCoordinateMax);
}

static float2 inputTextureUV(float2 sourcePixel, constant AnyUprightWarpState *warpState)
{
    float2 texturePixel = sourcePixel + warpState->inputImageOriginInTexture;
    return texturePixel / warpState->inputTextureSize;
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
                                     address::clamp_to_edge);

    if (warpState->renderMode == AURM_SourceQuadAdjusterPreview) {
        float2 outputCoordinate = clampedImageCoordinate(in.outputCoordinate, warpState);
        float3 sourceHomogeneous = warpState->outputToSource * float3(outputCoordinate, 1.0);
        if (fabs(sourceHomogeneous.z) < 0.000001) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        float2 sourcePixel = sourceHomogeneous.xy / sourceHomogeneous.z;
        float2 sourceUV = inputTextureUV(sourcePixel, warpState);
        if (sourceUV.x < 0.0 || sourceUV.x > 1.0 || sourceUV.y < 0.0 || sourceUV.y > 1.0) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        float4 color = float4(colorTexture.sample(textureSampler, sourceUV));
        float3 selectionHomogeneous = warpState->selectionOutputToRect * float3(outputCoordinate, 1.0);
        if (fabs(selectionHomogeneous.z) < 0.000001) {
            color.rgb *= 0.70;
            return color;
        }

        float2 rectPoint = selectionHomogeneous.xy / selectionHomogeneous.z;
        float2 outputSize = warpState->outputSize;
        float outsideDistance = max(
            max(-rectPoint.x, rectPoint.x - outputSize.x),
            max(-rectPoint.y, rectPoint.y - outputSize.y)
        );
        float insideSelection = outsideDistance <= 0.0 ? 1.0 : 0.0;
        float dimAmount = 1.0 - insideSelection;

        color.rgb *= mix(1.0, 0.70, dimAmount);

        return color;
    }

    float2 outputCoordinate = clampedImageCoordinate(in.outputCoordinate, warpState);
    float3 sourceHomogeneous = warpState->outputToSource * float3(outputCoordinate, 1.0);
    if (fabs(sourceHomogeneous.z) < 0.000001) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 sourcePixel = sourceHomogeneous.xy / sourceHomogeneous.z;
    float2 sourceUV = inputTextureUV(sourcePixel, warpState);

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
