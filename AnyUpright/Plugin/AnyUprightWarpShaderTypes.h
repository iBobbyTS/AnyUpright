//
//  AnyUprightWarpShaderTypes.h
//  AnyUpright
//

#ifndef AnyUprightWarpShaderTypes_h
#define AnyUprightWarpShaderTypes_h

#import <simd/simd.h>

#define AURM_WarpFullFrame 0
#define AURM_InnerStretchAdjusterPreview 2

typedef enum AnyUprightVertexInputIndex {
    AUVII_Vertices        = 0,
    AUVII_ViewportSize    = 1,
    AUVII_WarpState       = 2
} AnyUprightVertexInputIndex;

typedef enum AnyUprightTextureIndex {
    AUTI_InputImage = 0
} AnyUprightTextureIndex;

typedef enum AnyUprightFragmentInputIndex {
    AUFII_WarpState = 0
} AnyUprightFragmentInputIndex;

typedef struct AnyUprightVertex2D {
    vector_float2 position;
    vector_float2 outputCoordinate;
} AnyUprightVertex2D;

typedef struct AnyUprightOverlayVertex2D {
    vector_float2 position;
    vector_float4 color;
    vector_float2 primitiveOrigin;
    vector_float2 primitiveAxis;
    vector_float2 primitiveSize;
    float primitiveKind;
    float reserved0;
} AnyUprightOverlayVertex2D;

typedef struct AnyUprightWarpState {
    matrix_float3x3 outputToSource;
    matrix_float3x3 selectionOutputToRect;
    vector_float2 outputSize;
    vector_float2 inputSize;
    vector_float2 imageCoordinateMin;
    vector_float2 imageCoordinateMax;
    vector_float2 inputImageOriginInTexture;
    vector_float2 inputTextureSize;
    vector_float2 innerStretchTopLeft;
    vector_float2 innerStretchTopRight;
    vector_float2 innerStretchBottomRight;
    vector_float2 innerStretchBottomLeft;
    int renderMode;
    int reserved0;
    int reserved1;
    int reserved2;
} AnyUprightWarpState;

#endif /* AnyUprightWarpShaderTypes_h */
