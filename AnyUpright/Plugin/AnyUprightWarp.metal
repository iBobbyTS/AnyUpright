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
    float2 pixelSpacePosition;
    float4 color;
    float2 primitiveOrigin;
    float2 primitiveAxis;
    float2 primitiveSize;
    float primitiveKind;
} OverlayRasterizerData;

static float2 clampedImageCoordinate(float2 outputCoordinate, constant AnyUprightWarpState *warpState)
{
    return clamp(outputCoordinate, warpState->imageCoordinateMin, warpState->imageCoordinateMax);
}

static float2 inputTextureUV(float2 texturePixel, constant AnyUprightWarpState *warpState)
{
    return texturePixel / warpState->inputTextureSize;
}

static float sourceImageCoverage(float2 texturePixel, constant AnyUprightWarpState *warpState)
{
    float2 sourceSize = max(warpState->inputSize, float2(1.0));
    float2 sourcePixel = float2(
        texturePixel.x - warpState->inputImageOriginInTexture.x,
        sourceSize.y - (texturePixel.y - warpState->inputImageOriginInTexture.y)
    );
    float outsideDistance = max(
        max(-sourcePixel.x, sourcePixel.x - sourceSize.x),
        max(-sourcePixel.y, sourcePixel.y - sourceSize.y)
    );
    float antialiasWidth = max(fwidth(outsideDistance), 0.0001);
    return 1.0 - smoothstep(-antialiasWidth, antialiasWidth, outsideDistance);
}

static float cross2D(float2 lhs, float2 rhs)
{
    return lhs.x * rhs.y - lhs.y * rhs.x;
}

static float signedDistanceOutsideOrientedEdge(float2 point, float2 start, float2 end, float orientation)
{
    float2 edge = end - start;
    float edgeLength = max(length(edge), 0.0001);
    return -orientation * cross2D(edge, point - start) / edgeLength;
}

static float outerStretchCoverage(float2 outputCoordinate, constant AnyUprightWarpState *warpState)
{
    float2 topLeft = warpState->stretchTopLeft;
    float2 topRight = warpState->stretchTopRight;
    float2 bottomRight = warpState->stretchBottomRight;
    float2 bottomLeft = warpState->stretchBottomLeft;
    float signedArea = cross2D(topRight - topLeft, bottomRight - topLeft)
        + cross2D(bottomRight - topLeft, bottomLeft - topLeft);
    if (fabs(signedArea) < 0.0001) {
        return 0.0;
    }

    float orientation = signedArea > 0.0 ? 1.0 : -1.0;
    float outsideDistance = signedDistanceOutsideOrientedEdge(outputCoordinate, topLeft, topRight, orientation);
    outsideDistance = max(outsideDistance, signedDistanceOutsideOrientedEdge(outputCoordinate, topRight, bottomRight, orientation));
    outsideDistance = max(outsideDistance, signedDistanceOutsideOrientedEdge(outputCoordinate, bottomRight, bottomLeft, orientation));
    outsideDistance = max(outsideDistance, signedDistanceOutsideOrientedEdge(outputCoordinate, bottomLeft, topLeft, orientation));
    float antialiasWidth = max(fwidth(outsideDistance), 0.75);
    return 1.0 - smoothstep(-antialiasWidth, antialiasWidth, outsideDistance);
}

static float4 sampleInputImage(texture2d<half> colorTexture,
                               sampler textureSampler,
                               float2 texturePixel,
                               constant AnyUprightWarpState *warpState)
{
    float coverage = sourceImageCoverage(texturePixel, warpState);
    float2 sourceUV = clamp(inputTextureUV(texturePixel, warpState), float2(0.0), float2(1.0));
    float4 color = float4(colorTexture.sample(textureSampler, sourceUV));
    color.rgb *= coverage;
    return color;
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
    constexpr sampler linearTextureSampler(mag_filter::linear,
                                            min_filter::linear,
                                            address::clamp_to_edge);
    constexpr sampler nearestTextureSampler(mag_filter::nearest,
                                             min_filter::nearest,
                                             address::clamp_to_edge);

    if (warpState->renderMode == AURM_InnerStretchAdjusterPreview) {
        float2 outputCoordinate = clampedImageCoordinate(in.outputCoordinate, warpState);
        float3 sourceHomogeneous = warpState->outputToSource * float3(outputCoordinate, 1.0);
        if (fabs(sourceHomogeneous.z) < 0.000001) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        float2 texturePixel = sourceHomogeneous.xy / sourceHomogeneous.z;
        float4 color = warpState->usesNearestSampling != 0
            ? sampleInputImage(colorTexture, nearestTextureSampler, texturePixel, warpState)
            : sampleInputImage(colorTexture, linearTextureSampler, texturePixel, warpState);
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
    float outputCoverage = 1.0;
    if (warpState->renderMode == AURM_OuterStretch) {
        outputCoverage = outerStretchCoverage(outputCoordinate, warpState);
        if (outputCoverage <= 0.0) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }
    }

    float3 sourceHomogeneous = warpState->outputToSource * float3(outputCoordinate, 1.0);
    if (fabs(sourceHomogeneous.z) < 0.000001) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 texturePixel = sourceHomogeneous.xy / sourceHomogeneous.z;
    float4 color = warpState->usesNearestSampling != 0
        ? sampleInputImage(colorTexture, nearestTextureSampler, texturePixel, warpState)
        : sampleInputImage(colorTexture, linearTextureSampler, texturePixel, warpState);
    color.rgb *= outputCoverage;
    return color;
}

vertex OverlayRasterizerData anyUprightOverlayVertex(uint vertexID [[vertex_id]],
                                                     constant AnyUprightOverlayVertex2D *vertexArray [[buffer(AUVII_Vertices)]],
                                                     constant vector_uint2 *viewportSizePointer [[buffer(AUVII_ViewportSize)]])
{
    OverlayRasterizerData out;
    AnyUprightOverlayVertex2D overlayVertex = vertexArray[vertexID];
    float2 pixelSpacePosition = overlayVertex.position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize / 2.0);
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1.0;
    out.pixelSpacePosition = pixelSpacePosition;
    out.color = overlayVertex.color;
    out.primitiveOrigin = overlayVertex.primitiveOrigin;
    out.primitiveAxis = overlayVertex.primitiveAxis;
    out.primitiveSize = overlayVertex.primitiveSize;
    out.primitiveKind = overlayVertex.primitiveKind;

    return out;
}

static float antialiasedCoverage(float signedDistance)
{
    float antialiasWidth = max(fwidth(signedDistance), 0.75);
    return 1.0 - smoothstep(-antialiasWidth, antialiasWidth, signedDistance);
}

static float signedDistanceToOrientedRect(float2 point, float2 center, float2 axis, float2 halfSize)
{
    float2 unitAxis = normalize(axis);
    float2 normal = float2(-unitAxis.y, unitAxis.x);
    float2 offset = point - center;
    float2 localPoint = float2(dot(offset, unitAxis), dot(offset, normal));
    float2 q = abs(localPoint) - halfSize;
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0);
}

fragment float4 anyUprightOverlayFragment(OverlayRasterizerData in [[stage_in]])
{
    if (in.primitiveKind < 0.5) {
        return in.color;
    }

    float signedDistance = 0.0;
    if (in.primitiveKind < 1.5) {
        signedDistance = signedDistanceToOrientedRect(
            in.pixelSpacePosition,
            in.primitiveOrigin,
            in.primitiveAxis,
            in.primitiveSize
        );
    } else {
        signedDistance = length(in.pixelSpacePosition - in.primitiveOrigin) - in.primitiveSize.x;
    }

    float4 color = in.color;
    color.a *= antialiasedCoverage(signedDistance);
    return color;
}
