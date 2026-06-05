//
//  AnyUprightWarpShaderTypes.h
//  AnyUpright
//

#ifndef AnyUprightWarpShaderTypes_h
#define AnyUprightWarpShaderTypes_h

#import <simd/simd.h>

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
} AnyUprightOverlayVertex2D;

typedef struct AnyUprightWarpState {
    matrix_float3x3 outputToSource;
    vector_float2 outputSize;
    vector_float2 inputSize;
} AnyUprightWarpState;

#endif /* AnyUprightWarpShaderTypes_h */
