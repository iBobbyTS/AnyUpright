import Foundation
import Metal

struct Manifest: Decodable {
    let imageCount: Int
    let weights: Weights?
    let stem: StemSpec?
    let block1: Block1Spec?
    let stage1: Stage1Spec?
    let stage2: StageSpec?
    let stage3: StageSpec?
    let stage4: StageSpec?
    let decoderPreNMF: DecoderPreNMFSpec?
    let hamburger: HamburgerSpec?
    let decoderOutput: DecoderOutputSpec?
    let lowLevelEncoder: LowLevelEncoderSpec?
    let neuralForward: NeuralForwardSpec?
    let conv: ConvSpec?
    let entries: [Entry]

    enum CodingKeys: String, CodingKey {
        case imageCount = "image_count"
        case weights
        case stem
        case block1
        case stage1
        case stage2
        case stage3
        case stage4
        case decoderPreNMF = "decoder_pre_nmf"
        case hamburger
        case decoderOutput = "decoder_output"
        case lowLevelEncoder = "low_level_encoder"
        case neuralForward = "neural_forward"
        case conv
        case entries
    }
}

struct Weights: Decodable {
    let weight: String
    let bias: String
    let weightShape: [Int]
    let biasShape: [Int]

    enum CodingKeys: String, CodingKey {
        case weight
        case bias
        case weightShape = "weight_shape"
        case biasShape = "bias_shape"
    }
}

struct ConvSpec: Decodable {
    let padding: [Int]
    let stride: [Int]
    let dilation: [Int]
    let groups: Int
}

struct StemSpec: Decodable {
    let conv0: ConvLayerSpec
    let bn1: AffineLayerSpec
    let gelu: GeluSpec
    let conv3: ConvLayerSpec
    let bn4: AffineLayerSpec
}

struct ConvLayerSpec: Decodable {
    let weight: String
    let bias: String
    let weightShape: [Int]
    let biasShape: [Int]
    let padding: [Int]
    let stride: [Int]
    let dilation: [Int]?
    let groups: Int?

    enum CodingKeys: String, CodingKey {
        case weight
        case bias
        case weightShape = "weight_shape"
        case biasShape = "bias_shape"
        case padding
        case stride
        case dilation
        case groups
    }
}

struct AffineLayerSpec: Decodable {
    let scale: String
    let offset: String
    let shape: [Int]
}

struct GeluSpec: Decodable {
    let approximate: String
}

struct ParameterSpec: Decodable {
    let path: String
    let shape: [Int]
}

struct Block1Spec: Decodable {
    let norm1: AffineLayerSpec
    let norm2: AffineLayerSpec
    let layerScale1: ParameterSpec
    let layerScale2: ParameterSpec
    let attn: AttentionSpec
    let mlp: MLPSpec

    enum CodingKeys: String, CodingKey {
        case norm1
        case norm2
        case layerScale1 = "layer_scale_1"
        case layerScale2 = "layer_scale_2"
        case attn
        case mlp
    }
}

struct AttentionSpec: Decodable {
    let proj1: ConvLayerSpec
    let sgu: SpatialGatingSpec
    let proj2: ConvLayerSpec

    enum CodingKeys: String, CodingKey {
        case proj1 = "proj_1"
        case sgu
        case proj2 = "proj_2"
    }
}

struct SpatialGatingSpec: Decodable {
    let conv0: ConvLayerSpec
    let conv0_1: ConvLayerSpec
    let conv0_2: ConvLayerSpec
    let conv1_1: ConvLayerSpec
    let conv1_2: ConvLayerSpec
    let conv2_1: ConvLayerSpec
    let conv2_2: ConvLayerSpec
    let conv3: ConvLayerSpec
}

struct MLPSpec: Decodable {
    let fc1: ConvLayerSpec
    let dwconv: ConvLayerSpec
    let fc2: ConvLayerSpec
}

struct LayerNormSpec: Decodable {
    let weight: String
    let bias: String
    let shape: [Int]
    let eps: Float
}

struct Stage1Spec: Decodable {
    let blocks: [Block1Spec]
    let norm: LayerNormSpec
}

struct PatchEmbedSpec: Decodable {
    let proj: ConvLayerSpec
    let norm: AffineLayerSpec
}

struct StageSpec: Decodable {
    let patchEmbed: PatchEmbedSpec?
    let blocks: [Block1Spec]
    let norm: LayerNormSpec

    enum CodingKeys: String, CodingKey {
        case patchEmbed = "patch_embed"
        case blocks
        case norm
    }
}

struct DecoderPreNMFSpec: Decodable {
    let head: String
    let squeeze: ConvLayerSpec
    let alignCorners: Bool

    enum CodingKeys: String, CodingKey {
        case head
        case squeeze
        case alignCorners = "align_corners"
    }
}

struct HamburgerSpec: Decodable {
    let head: String
    let squeeze: ConvLayerSpec
    let hamIn: ConvLayerSpec
    let hamOut: ConvLayerSpec
    let nmf: NMFSpec
    let alignCorners: Bool

    enum CodingKeys: String, CodingKey {
        case head
        case squeeze
        case hamIn = "ham_in"
        case hamOut = "ham_out"
        case nmf
        case alignCorners = "align_corners"
    }
}

struct NMFSpec: Decodable {
    let bases: String
    let basisShape: [Int]
    let steps: Int
    let epsilon: Float
    let invT: Float

    enum CodingKeys: String, CodingKey {
        case bases
        case basisShape = "basis_shape"
        case steps
        case epsilon
        case invT = "inv_t"
    }
}

struct DecoderOutputSpec: Decodable {
    let head: String
    let align: ConvLayerSpec
    let outConv: ConvLayerSpec
    let fusion: FusionSpec
    let uncertainty: UncertaintySpec
    let linearPredUp: ConvLayerSpec?
    let linearPredLatitude: ConvLayerSpec?

    enum CodingKeys: String, CodingKey {
        case head
        case align
        case outConv = "out_conv"
        case fusion
        case uncertainty
        case linearPredUp = "linear_pred_up"
        case linearPredLatitude = "linear_pred_latitude"
    }
}

struct FusionSpec: Decodable {
    let resConfUnit1: ResidualConvUnitSpec
    let resConfUnit2: ResidualConvUnitSpec

    enum CodingKeys: String, CodingKey {
        case resConfUnit1 = "res_conf_unit1"
        case resConfUnit2 = "res_conf_unit2"
    }
}

struct ResidualConvUnitSpec: Decodable {
    let conv1: ConvLayerSpec
    let conv2: ConvLayerSpec
}

struct UncertaintySpec: Decodable {
    let hidden: ConvLayerSpec
    let linear: ConvLayerSpec
}

struct LowLevelEncoderSpec: Decodable {
    let conv1: ConvLayerSpec
    let conv2: ConvLayerSpec
}

struct NeuralForwardSpec: Decodable {
    let stem: StemSpec
    let stage1: Stage1Spec
    let stage2: StageSpec
    let stage3: StageSpec
    let stage4: StageSpec
    let lowLevelEncoder: LowLevelEncoderSpec
    let upHead: FullHeadSpec
    let latitudeHead: FullHeadSpec

    enum CodingKeys: String, CodingKey {
        case stem
        case stage1
        case stage2
        case stage3
        case stage4
        case lowLevelEncoder = "low_level_encoder"
        case upHead = "up_head"
        case latitudeHead = "latitude_head"
    }
}

struct FullHeadSpec: Decodable {
    let head: String
    let squeeze: ConvLayerSpec
    let hamIn: ConvLayerSpec
    let hamOut: ConvLayerSpec
    let nmf: NMFSpec
    let align: ConvLayerSpec
    let outConv: ConvLayerSpec
    let fusion: FusionSpec
    let uncertainty: UncertaintySpec
    let linearPredUp: ConvLayerSpec?
    let linearPredLatitude: ConvLayerSpec?

    enum CodingKeys: String, CodingKey {
        case head
        case squeeze
        case hamIn = "ham_in"
        case hamOut = "ham_out"
        case nmf
        case align
        case outConv = "out_conv"
        case fusion
        case uncertainty
        case linearPredUp = "linear_pred_up"
        case linearPredLatitude = "linear_pred_latitude"
    }
}

struct Entry: Decodable {
    let filename: String
    let input: String?
    let expected: String?
    let bn1Expected: String?
    let geluExpected: String?
    let conv3Expected: String?
    let bn4Expected: String?
    let inputShape: [Int]?
    let expectedShape: [Int]?
    let bn1Shape: [Int]?
    let geluShape: [Int]?
    let conv3Shape: [Int]?
    let bn4Shape: [Int]?
    let height: Int?
    let width: Int?
    let maxDirectDelta: Double?
    let tensors: [String: String]?
    let shapes: [String: [Int]]?

    enum CodingKeys: String, CodingKey {
        case filename = "fname"
        case input
        case expected
        case bn1Expected = "bn1_expected"
        case geluExpected = "gelu_expected"
        case conv3Expected = "conv3_expected"
        case bn4Expected = "bn4_expected"
        case inputShape = "input_shape"
        case expectedShape = "expected_shape"
        case bn1Shape = "bn1_shape"
        case geluShape = "gelu_shape"
        case conv3Shape = "conv3_shape"
        case bn4Shape = "bn4_shape"
        case height
        case width
        case maxDirectDelta = "max_direct_delta"
        case tensors
        case shapes
    }
}

struct Conv2DConfig {
    var batch: UInt32
    var inChannels: UInt32
    var outChannels: UInt32
    var groups: UInt32
    var inputHeight: UInt32
    var inputWidth: UInt32
    var outputHeight: UInt32
    var outputWidth: UInt32
    var kernelHeight: UInt32
    var kernelWidth: UInt32
    var strideY: UInt32
    var strideX: UInt32
    var paddingY: UInt32
    var paddingX: UInt32
}

struct Concat4Config {
    var batch: UInt32
    var channels0: UInt32
    var channels1: UInt32
    var channels2: UInt32
    var channels3: UInt32
    var height: UInt32
    var width: UInt32
}

struct NMFConfig {
    var d: UInt32
    var n: UInt32
    var r: UInt32
    var epsilon: Float
    var invT: Float
}

struct VerificationSummary: Encodable {
    let fixtureCount: Int
    let passedCount: Int
    let failedCount: Int
    let maxAbsDifference: Float
    let maxRelativeDifference: Float
    let maxRMSE: Float
    let stages: [String: StageSummary]
    let failures: [String]

    enum CodingKeys: String, CodingKey {
        case fixtureCount = "fixture_count"
        case passedCount = "passed_count"
        case failedCount = "failed_count"
        case maxAbsDifference = "max_abs_difference"
        case maxRelativeDifference = "max_relative_difference"
        case maxRMSE = "max_rmse"
        case stages
        case failures
    }
}

struct StageSummary: Encodable {
    let count: Int
    let failedCount: Int
    let maxAbsDifference: Float
    let maxRelativeDifference: Float
    let maxRMSE: Float

    enum CodingKeys: String, CodingKey {
        case count
        case failedCount = "failed_count"
        case maxAbsDifference = "max_abs_difference"
        case maxRelativeDifference = "max_relative_difference"
        case maxRMSE = "max_rmse"
    }
}

struct MutableStageSummary {
    var count = 0
    var failedCount = 0
    var maxAbsDifference: Float = 0
    var maxRelativeDifference: Float = 0
    var maxRMSE: Float = 0

    func frozen() -> StageSummary {
        StageSummary(
            count: count,
            failedCount: failedCount,
            maxAbsDifference: maxAbsDifference,
            maxRelativeDifference: maxRelativeDifference,
            maxRMSE: maxRMSE
        )
    }
}

enum StemPrototypeError: Error, CustomStringConvertible {
    case missingArgument(String)
    case invalidFixture(String)
    case metalUnavailable
    case metalFailure(String)
    case verificationFailed(Int)

    var description: String {
        switch self {
        case .missingArgument(let argument):
            return "Missing argument: \(argument)"
        case .invalidFixture(let message):
            return "Invalid fixture: \(message)"
        case .metalUnavailable:
            return "Metal is unavailable"
        case .metalFailure(let message):
            return "Metal failure: \(message)"
        case .verificationFailed(let count):
            return "GeoCalib stem verification failed for \(count) fixture(s)"
        }
    }
}

struct Options {
    var fixtures = URL(fileURLWithPath: "../fixtures/geocalib_stem_20")
    var metalSource = URL(fileURLWithPath: "Sources/GeoCalibStemPrototype/GeoCalibStem.metal")
    var outputJSON = URL(fileURLWithPath: "../outputs/swift_geocalib_stem_20/summary.json")
    var absTolerance: Float = 2e-4
    var relativeTolerance: Float = 2e-5
    var rmseTolerance: Float = 5e-5
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 1
    while index < arguments.count {
        let key = arguments[index]
        func value() throws -> String {
            guard index + 1 < arguments.count else { throw StemPrototypeError.missingArgument(key) }
            index += 1
            return arguments[index]
        }
        switch key {
        case "--fixtures":
            options.fixtures = URL(fileURLWithPath: try value())
        case "--metal-source":
            options.metalSource = URL(fileURLWithPath: try value())
        case "--out":
            options.outputJSON = URL(fileURLWithPath: try value())
        case "--abs-tolerance":
            guard let parsed = Float(try value()) else { throw StemPrototypeError.missingArgument(key) }
            options.absTolerance = parsed
        case "--relative-tolerance":
            guard let parsed = Float(try value()) else { throw StemPrototypeError.missingArgument(key) }
            options.relativeTolerance = parsed
        case "--rmse-tolerance":
            guard let parsed = Float(try value()) else { throw StemPrototypeError.missingArgument(key) }
            options.rmseTolerance = parsed
        default:
            throw StemPrototypeError.missingArgument("unknown option \(key)")
        }
        index += 1
    }
    return options
}

func product(_ shape: [Int]) -> Int {
    shape.reduce(1, *)
}

func readFloat32Array(_ url: URL, expectedCount: Int) throws -> [Float] {
    let data = try Data(contentsOf: url)
    let expectedBytes = expectedCount * MemoryLayout<Float>.stride
    guard data.count == expectedBytes else {
        throw StemPrototypeError.invalidFixture("\(url.lastPathComponent) has \(data.count) bytes, expected \(expectedBytes)")
    }
    var values = [Float](repeating: 0, count: expectedCount)
    _ = values.withUnsafeMutableBytes { destination in
        data.copyBytes(to: destination)
    }
    return values
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url)
}

final class MetalConv2DRunner {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let convPipeline: MTLComputePipelineState
    private let affinePipeline: MTLComputePipelineState
    private let geluPipeline: MTLComputePipelineState
    private let reluPipeline: MTLComputePipelineState
    private let addPipeline: MTLComputePipelineState
    private let multiplyPipeline: MTLComputePipelineState
    private let addScaledChannelsPipeline: MTLComputePipelineState
    private let layerNormPipeline: MTLComputePipelineState
    private let bilinearResizePipeline: MTLComputePipelineState
    private let concat4Pipeline: MTLComputePipelineState
    private let nmfXTBasesPipeline: MTLComputePipelineState
    private let nmfSoftmaxRowsPipeline: MTLComputePipelineState
    private let nmfBasesGramPipeline: MTLComputePipelineState
    private let nmfCoefTimesGramPipeline: MTLComputePipelineState
    private let nmfUpdateInPlacePipeline: MTLComputePipelineState
    private let nmfXCoefPipeline: MTLComputePipelineState
    private let nmfCoefGramPipeline: MTLComputePipelineState
    private let nmfBasesTimesGramPipeline: MTLComputePipelineState
    private let nmfBasesCoefTPipeline: MTLComputePipelineState
    private let normalize2ChannelPipeline: MTLComputePipelineState
    private let sigmoidPipeline: MTLComputePipelineState
    private let latitudeFieldPipeline: MTLComputePipelineState

    convenience init(metalSource: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw StemPrototypeError.metalUnavailable
        }
        guard let queue = device.makeCommandQueue() else {
            throw StemPrototypeError.metalFailure("could not create command queue")
        }
        let source = try String(contentsOf: metalSource, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        try self.init(device: device, queue: queue, library: library)
    }

    convenience init(metalLibraryURL: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw StemPrototypeError.metalUnavailable
        }
        guard let queue = device.makeCommandQueue() else {
            throw StemPrototypeError.metalFailure("could not create command queue")
        }
        let library = try device.makeLibrary(URL: metalLibraryURL)
        try self.init(device: device, queue: queue, library: library)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) throws {
        guard let convFunction = library.makeFunction(name: "conv2dNCHWKernel") else {
            throw StemPrototypeError.metalFailure("missing conv2dNCHWKernel")
        }
        guard let affineFunction = library.makeFunction(name: "affineNCHWKernel") else {
            throw StemPrototypeError.metalFailure("missing affineNCHWKernel")
        }
        guard let geluFunction = library.makeFunction(name: "geluExactKernel") else {
            throw StemPrototypeError.metalFailure("missing geluExactKernel")
        }
        guard let reluFunction = library.makeFunction(name: "reluKernel") else {
            throw StemPrototypeError.metalFailure("missing reluKernel")
        }
        guard let addFunction = library.makeFunction(name: "addTensorsKernel") else {
            throw StemPrototypeError.metalFailure("missing addTensorsKernel")
        }
        guard let multiplyFunction = library.makeFunction(name: "multiplyTensorsKernel") else {
            throw StemPrototypeError.metalFailure("missing multiplyTensorsKernel")
        }
        guard let addScaledChannelsFunction = library.makeFunction(name: "addScaledChannelsNCHWKernel") else {
            throw StemPrototypeError.metalFailure("missing addScaledChannelsNCHWKernel")
        }
        guard let layerNormFunction = library.makeFunction(name: "layerNormChannelsNCHWKernel") else {
            throw StemPrototypeError.metalFailure("missing layerNormChannelsNCHWKernel")
        }
        guard let bilinearResizeFunction = library.makeFunction(name: "bilinearResizeNCHWKernel") else {
            throw StemPrototypeError.metalFailure("missing bilinearResizeNCHWKernel")
        }
        guard let concat4Function = library.makeFunction(name: "concat4NCHWKernel") else {
            throw StemPrototypeError.metalFailure("missing concat4NCHWKernel")
        }
        guard let nmfXTBasesFunction = library.makeFunction(name: "nmfXTBasesKernel") else {
            throw StemPrototypeError.metalFailure("missing nmfXTBasesKernel")
        }
        guard let nmfSoftmaxRowsFunction = library.makeFunction(name: "nmfSoftmaxRowsKernel") else {
            throw StemPrototypeError.metalFailure("missing nmfSoftmaxRowsKernel")
        }
        guard let nmfBasesGramFunction = library.makeFunction(name: "nmfBasesGramKernel") else {
            throw StemPrototypeError.metalFailure("missing nmfBasesGramKernel")
        }
        guard let nmfCoefTimesGramFunction = library.makeFunction(name: "nmfCoefTimesGramKernel") else {
            throw StemPrototypeError.metalFailure("missing nmfCoefTimesGramKernel")
        }
        guard let nmfUpdateInPlaceFunction = library.makeFunction(name: "nmfUpdateInPlaceKernel") else {
            throw StemPrototypeError.metalFailure("missing nmfUpdateInPlaceKernel")
        }
        guard let nmfXCoefFunction = library.makeFunction(name: "nmfXCoefKernel") else {
            throw StemPrototypeError.metalFailure("missing nmfXCoefKernel")
        }
        guard let nmfCoefGramFunction = library.makeFunction(name: "nmfCoefGramKernel") else {
            throw StemPrototypeError.metalFailure("missing nmfCoefGramKernel")
        }
        guard let nmfBasesTimesGramFunction = library.makeFunction(name: "nmfBasesTimesGramKernel") else {
            throw StemPrototypeError.metalFailure("missing nmfBasesTimesGramKernel")
        }
        guard let nmfBasesCoefTFunction = library.makeFunction(name: "nmfBasesCoefTKernel") else {
            throw StemPrototypeError.metalFailure("missing nmfBasesCoefTKernel")
        }
        guard let normalize2ChannelFunction = library.makeFunction(name: "normalize2ChannelNCHWKernel") else {
            throw StemPrototypeError.metalFailure("missing normalize2ChannelNCHWKernel")
        }
        guard let sigmoidFunction = library.makeFunction(name: "sigmoidKernel") else {
            throw StemPrototypeError.metalFailure("missing sigmoidKernel")
        }
        guard let latitudeFieldFunction = library.makeFunction(name: "latitudeFieldKernel") else {
            throw StemPrototypeError.metalFailure("missing latitudeFieldKernel")
        }
        self.device = device
        self.queue = queue
        self.convPipeline = try device.makeComputePipelineState(function: convFunction)
        self.affinePipeline = try device.makeComputePipelineState(function: affineFunction)
        self.geluPipeline = try device.makeComputePipelineState(function: geluFunction)
        self.reluPipeline = try device.makeComputePipelineState(function: reluFunction)
        self.addPipeline = try device.makeComputePipelineState(function: addFunction)
        self.multiplyPipeline = try device.makeComputePipelineState(function: multiplyFunction)
        self.addScaledChannelsPipeline = try device.makeComputePipelineState(function: addScaledChannelsFunction)
        self.layerNormPipeline = try device.makeComputePipelineState(function: layerNormFunction)
        self.bilinearResizePipeline = try device.makeComputePipelineState(function: bilinearResizeFunction)
        self.concat4Pipeline = try device.makeComputePipelineState(function: concat4Function)
        self.nmfXTBasesPipeline = try device.makeComputePipelineState(function: nmfXTBasesFunction)
        self.nmfSoftmaxRowsPipeline = try device.makeComputePipelineState(function: nmfSoftmaxRowsFunction)
        self.nmfBasesGramPipeline = try device.makeComputePipelineState(function: nmfBasesGramFunction)
        self.nmfCoefTimesGramPipeline = try device.makeComputePipelineState(function: nmfCoefTimesGramFunction)
        self.nmfUpdateInPlacePipeline = try device.makeComputePipelineState(function: nmfUpdateInPlaceFunction)
        self.nmfXCoefPipeline = try device.makeComputePipelineState(function: nmfXCoefFunction)
        self.nmfCoefGramPipeline = try device.makeComputePipelineState(function: nmfCoefGramFunction)
        self.nmfBasesTimesGramPipeline = try device.makeComputePipelineState(function: nmfBasesTimesGramFunction)
        self.nmfBasesCoefTPipeline = try device.makeComputePipelineState(function: nmfBasesCoefTFunction)
        self.normalize2ChannelPipeline = try device.makeComputePipelineState(function: normalize2ChannelFunction)
        self.sigmoidPipeline = try device.makeComputePipelineState(function: sigmoidFunction)
        self.latitudeFieldPipeline = try device.makeComputePipelineState(function: latitudeFieldFunction)
    }

    private func makeFloatBuffer(_ values: [Float]) throws -> MTLBuffer {
        let byteCount = values.count * MemoryLayout<Float>.stride
        guard let buffer = device.makeBuffer(bytes: values, length: byteCount) else {
            throw StemPrototypeError.metalFailure("could not create float buffer")
        }
        return buffer
    }

    private func finishOutput(_ outputBuffer: MTLBuffer, count: Int) -> [Float] {
        let pointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    func runConv2D(input: [Float], weight: [Float], bias: [Float], config: Conv2DConfig) throws -> [Float] {
        let inputBytes = input.count * MemoryLayout<Float>.stride
        let weightBytes = weight.count * MemoryLayout<Float>.stride
        let biasBytes = bias.count * MemoryLayout<Float>.stride
        let outputCount = Int(config.batch * config.outChannels * config.outputHeight * config.outputWidth)
        guard let inputBuffer = device.makeBuffer(bytes: input, length: inputBytes),
              let weightBuffer = device.makeBuffer(bytes: weight, length: weightBytes),
              let biasBuffer = device.makeBuffer(bytes: bias, length: biasBytes),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create buffers")
        }
        var mutableConfig = config
        guard let configBuffer = device.makeBuffer(bytes: &mutableConfig, length: MemoryLayout<Conv2DConfig>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create command encoder")
        }
        encoder.setComputePipelineState(convPipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(weightBuffer, offset: 0, index: 1)
        encoder.setBuffer(biasBuffer, offset: 0, index: 2)
        encoder.setBuffer(outputBuffer, offset: 0, index: 3)
        encoder.setBuffer(configBuffer, offset: 0, index: 4)
        let threads = MTLSize(width: outputCount, height: 1, depth: 1)
        let group = MTLSize(width: convPipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    func runAffine(input: [Float], scale: [Float], offset: [Float], config: Conv2DConfig) throws -> [Float] {
        let outputCount = input.count
        guard let inputBuffer = device.makeBuffer(bytes: input, length: outputCount * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create affine buffers")
        }
        let scaleBuffer = try makeFloatBuffer(scale)
        let offsetBuffer = try makeFloatBuffer(offset)
        var mutableConfig = config
        guard let configBuffer = device.makeBuffer(bytes: &mutableConfig, length: MemoryLayout<Conv2DConfig>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create affine command encoder")
        }
        encoder.setComputePipelineState(affinePipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(scaleBuffer, offset: 0, index: 1)
        encoder.setBuffer(offsetBuffer, offset: 0, index: 2)
        encoder.setBuffer(outputBuffer, offset: 0, index: 3)
        encoder.setBuffer(configBuffer, offset: 0, index: 4)
        let threads = MTLSize(width: outputCount, height: 1, depth: 1)
        let group = MTLSize(width: affinePipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    func runGELU(input: [Float]) throws -> [Float] {
        let outputCount = input.count
        guard let inputBuffer = device.makeBuffer(bytes: input, length: outputCount * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create GELU buffers")
        }
        var count = UInt32(outputCount)
        guard let countBuffer = device.makeBuffer(bytes: &count, length: MemoryLayout<UInt32>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create GELU command encoder")
        }
        encoder.setComputePipelineState(geluPipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(countBuffer, offset: 0, index: 2)
        let threads = MTLSize(width: outputCount, height: 1, depth: 1)
        let group = MTLSize(width: geluPipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    func runReLU(input: [Float]) throws -> [Float] {
        let outputCount = input.count
        guard let inputBuffer = device.makeBuffer(bytes: input, length: outputCount * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create ReLU buffers")
        }
        var count = UInt32(outputCount)
        guard let countBuffer = device.makeBuffer(bytes: &count, length: MemoryLayout<UInt32>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create ReLU command encoder")
        }
        encoder.setComputePipelineState(reluPipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(countBuffer, offset: 0, index: 2)
        let threads = MTLSize(width: outputCount, height: 1, depth: 1)
        let group = MTLSize(width: reluPipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    private func runBinary(inputA: [Float], inputB: [Float], pipeline: MTLComputePipelineState) throws -> [Float] {
        guard inputA.count == inputB.count else {
            throw StemPrototypeError.invalidFixture("binary op shape mismatch: \(inputA.count) vs \(inputB.count)")
        }
        let outputCount = inputA.count
        guard let inputABuffer = device.makeBuffer(bytes: inputA, length: outputCount * MemoryLayout<Float>.stride),
              let inputBBuffer = device.makeBuffer(bytes: inputB, length: outputCount * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create binary op buffers")
        }
        var count = UInt32(outputCount)
        guard let countBuffer = device.makeBuffer(bytes: &count, length: MemoryLayout<UInt32>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create binary op command encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputABuffer, offset: 0, index: 0)
        encoder.setBuffer(inputBBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBuffer(countBuffer, offset: 0, index: 3)
        let threads = MTLSize(width: outputCount, height: 1, depth: 1)
        let group = MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    func runAdd(inputA: [Float], inputB: [Float]) throws -> [Float] {
        try runBinary(inputA: inputA, inputB: inputB, pipeline: addPipeline)
    }

    func runMultiply(inputA: [Float], inputB: [Float]) throws -> [Float] {
        try runBinary(inputA: inputA, inputB: inputB, pipeline: multiplyPipeline)
    }

    func runAddScaledChannels(residual: [Float], branch: [Float], scale: [Float], config: Conv2DConfig) throws -> [Float] {
        guard residual.count == branch.count else {
            throw StemPrototypeError.invalidFixture("add-scaled shape mismatch: \(residual.count) vs \(branch.count)")
        }
        let outputCount = residual.count
        guard let residualBuffer = device.makeBuffer(bytes: residual, length: outputCount * MemoryLayout<Float>.stride),
              let branchBuffer = device.makeBuffer(bytes: branch, length: outputCount * MemoryLayout<Float>.stride),
              let scaleBuffer = device.makeBuffer(bytes: scale, length: scale.count * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create add-scaled buffers")
        }
        var mutableConfig = config
        guard let configBuffer = device.makeBuffer(bytes: &mutableConfig, length: MemoryLayout<Conv2DConfig>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create add-scaled command encoder")
        }
        encoder.setComputePipelineState(addScaledChannelsPipeline)
        encoder.setBuffer(residualBuffer, offset: 0, index: 0)
        encoder.setBuffer(branchBuffer, offset: 0, index: 1)
        encoder.setBuffer(scaleBuffer, offset: 0, index: 2)
        encoder.setBuffer(outputBuffer, offset: 0, index: 3)
        encoder.setBuffer(configBuffer, offset: 0, index: 4)
        let threads = MTLSize(width: outputCount, height: 1, depth: 1)
        let group = MTLSize(width: addScaledChannelsPipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    func runLayerNormNCHW(input: [Float], shape: [Int], weight: [Float], bias: [Float], epsilon: Float) throws -> [Float] {
        guard shape.count == 4 else {
            throw StemPrototypeError.invalidFixture("LayerNorm expects 4D NCHW shape")
        }
        let outputCount = input.count
        guard weight.count == shape[1], bias.count == shape[1] else {
            throw StemPrototypeError.invalidFixture("LayerNorm parameter shape mismatch")
        }
        guard let inputBuffer = device.makeBuffer(bytes: input, length: outputCount * MemoryLayout<Float>.stride),
              let weightBuffer = device.makeBuffer(bytes: weight, length: weight.count * MemoryLayout<Float>.stride),
              let biasBuffer = device.makeBuffer(bytes: bias, length: bias.count * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create LayerNorm buffers")
        }
        var config = try tensorConfig(shape: shape)
        var eps = epsilon
        guard let configBuffer = device.makeBuffer(bytes: &config, length: MemoryLayout<Conv2DConfig>.stride),
              let epsBuffer = device.makeBuffer(bytes: &eps, length: MemoryLayout<Float>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create LayerNorm command encoder")
        }
        encoder.setComputePipelineState(layerNormPipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(weightBuffer, offset: 0, index: 1)
        encoder.setBuffer(biasBuffer, offset: 0, index: 2)
        encoder.setBuffer(outputBuffer, offset: 0, index: 3)
        encoder.setBuffer(configBuffer, offset: 0, index: 4)
        encoder.setBuffer(epsBuffer, offset: 0, index: 5)
        let threads = MTLSize(width: shape[0] * shape[2] * shape[3], height: 1, depth: 1)
        let group = MTLSize(width: layerNormPipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    func runBilinearResizeNCHW(input: [Float], inputShape: [Int], outputShape: [Int]) throws -> [Float] {
        guard inputShape.count == 4, outputShape.count == 4 else {
            throw StemPrototypeError.invalidFixture("bilinear resize expects 4D NCHW shapes")
        }
        guard inputShape[0] == outputShape[0], inputShape[1] == outputShape[1] else {
            throw StemPrototypeError.invalidFixture("bilinear resize batch/channel mismatch: \(inputShape) -> \(outputShape)")
        }
        let outputCount = product(outputShape)
        guard let inputBuffer = device.makeBuffer(bytes: input, length: input.count * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create bilinear resize buffers")
        }
        var config = Conv2DConfig(
            batch: UInt32(inputShape[0]),
            inChannels: UInt32(inputShape[1]),
            outChannels: UInt32(outputShape[1]),
            groups: 1,
            inputHeight: UInt32(inputShape[2]),
            inputWidth: UInt32(inputShape[3]),
            outputHeight: UInt32(outputShape[2]),
            outputWidth: UInt32(outputShape[3]),
            kernelHeight: 1,
            kernelWidth: 1,
            strideY: 1,
            strideX: 1,
            paddingY: 0,
            paddingX: 0
        )
        guard let configBuffer = device.makeBuffer(bytes: &config, length: MemoryLayout<Conv2DConfig>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create bilinear resize command encoder")
        }
        encoder.setComputePipelineState(bilinearResizePipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(configBuffer, offset: 0, index: 2)
        let threads = MTLSize(width: outputCount, height: 1, depth: 1)
        let group = MTLSize(width: bilinearResizePipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    func runConcat4NCHW(inputs: [(values: [Float], shape: [Int])], outputShape: [Int]) throws -> [Float] {
        guard inputs.count == 4, outputShape.count == 4 else {
            throw StemPrototypeError.invalidFixture("concat4 expects four 4D NCHW inputs")
        }
        let batch = outputShape[0]
        let height = outputShape[2]
        let width = outputShape[3]
        var channels: [Int] = []
        for input in inputs {
            guard input.shape.count == 4,
                  input.shape[0] == batch,
                  input.shape[2] == height,
                  input.shape[3] == width
            else {
                throw StemPrototypeError.invalidFixture("concat4 shape mismatch: \(inputs.map { $0.shape }) -> \(outputShape)")
            }
            channels.append(input.shape[1])
        }
        guard channels.reduce(0, +) == outputShape[1] else {
            throw StemPrototypeError.invalidFixture("concat4 channel mismatch: \(channels) -> \(outputShape)")
        }
        let outputCount = product(outputShape)
        guard let input0 = device.makeBuffer(bytes: inputs[0].values, length: inputs[0].values.count * MemoryLayout<Float>.stride),
              let input1 = device.makeBuffer(bytes: inputs[1].values, length: inputs[1].values.count * MemoryLayout<Float>.stride),
              let input2 = device.makeBuffer(bytes: inputs[2].values, length: inputs[2].values.count * MemoryLayout<Float>.stride),
              let input3 = device.makeBuffer(bytes: inputs[3].values, length: inputs[3].values.count * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create concat4 buffers")
        }
        var config = Concat4Config(
            batch: UInt32(batch),
            channels0: UInt32(channels[0]),
            channels1: UInt32(channels[1]),
            channels2: UInt32(channels[2]),
            channels3: UInt32(channels[3]),
            height: UInt32(height),
            width: UInt32(width)
        )
        guard let configBuffer = device.makeBuffer(bytes: &config, length: MemoryLayout<Concat4Config>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create concat4 command encoder")
        }
        encoder.setComputePipelineState(concat4Pipeline)
        encoder.setBuffer(input0, offset: 0, index: 0)
        encoder.setBuffer(input1, offset: 0, index: 1)
        encoder.setBuffer(input2, offset: 0, index: 2)
        encoder.setBuffer(input3, offset: 0, index: 3)
        encoder.setBuffer(outputBuffer, offset: 0, index: 4)
        encoder.setBuffer(configBuffer, offset: 0, index: 5)
        let threads = MTLSize(width: outputCount, height: 1, depth: 1)
        let group = MTLSize(width: concat4Pipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    func runFixedNMF(
        input: [Float],
        shape: [Int],
        bases: [Float],
        basisShape: [Int],
        steps: Int,
        epsilon: Float,
        invT: Float
    ) throws -> (output: [Float], finalBases: [Float], finalCoef: [Float]) {
        guard shape.count == 4, basisShape.count == 3 else {
            throw StemPrototypeError.invalidFixture("NMF expects input NCHW and basis SDR shapes")
        }
        guard shape[0] == 1, basisShape[0] == 1 else {
            throw StemPrototypeError.invalidFixture("NMF prototype currently supports batch=1 and S=1")
        }
        let d = shape[1]
        let n = shape[2] * shape[3]
        let r = basisShape[2]
        guard basisShape[1] == d else {
            throw StemPrototypeError.invalidFixture("NMF basis D mismatch: \(basisShape) vs \(shape)")
        }
        guard input.count == d * n, bases.count == d * r else {
            throw StemPrototypeError.invalidFixture("NMF input/basis count mismatch")
        }

        let coefCount = n * r
        let basesCount = d * r
        let outputCount = d * n
        let gramCount = r * r
        guard let inputBuffer = device.makeBuffer(bytes: input, length: input.count * MemoryLayout<Float>.stride),
              let basesBuffer = device.makeBuffer(bytes: bases, length: bases.count * MemoryLayout<Float>.stride),
              let coefBuffer = device.makeBuffer(length: coefCount * MemoryLayout<Float>.stride),
              let coefNumeratorBuffer = device.makeBuffer(length: coefCount * MemoryLayout<Float>.stride),
              let coefDenominatorBuffer = device.makeBuffer(length: coefCount * MemoryLayout<Float>.stride),
              let basesNumeratorBuffer = device.makeBuffer(length: basesCount * MemoryLayout<Float>.stride),
              let basesDenominatorBuffer = device.makeBuffer(length: basesCount * MemoryLayout<Float>.stride),
              let basesGramBuffer = device.makeBuffer(length: gramCount * MemoryLayout<Float>.stride),
              let coefGramBuffer = device.makeBuffer(length: gramCount * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create NMF buffers")
        }

        var config = NMFConfig(
            d: UInt32(d),
            n: UInt32(n),
            r: UInt32(r),
            epsilon: epsilon,
            invT: invT
        )
        var epsilonValue = epsilon
        var coefCountValue = UInt32(coefCount)
        var basesCountValue = UInt32(basesCount)
        guard let configBuffer = device.makeBuffer(bytes: &config, length: MemoryLayout<NMFConfig>.stride),
              let epsilonBuffer = device.makeBuffer(bytes: &epsilonValue, length: MemoryLayout<Float>.stride),
              let coefCountBuffer = device.makeBuffer(bytes: &coefCountValue, length: MemoryLayout<UInt32>.stride),
              let basesCountBuffer = device.makeBuffer(bytes: &basesCountValue, length: MemoryLayout<UInt32>.stride),
              let commandBuffer = queue.makeCommandBuffer()
        else {
            throw StemPrototypeError.metalFailure("could not create NMF command buffer")
        }

        func encode(
            _ pipeline: MTLComputePipelineState,
            threadCount: Int,
            _ configure: (MTLComputeCommandEncoder) -> Void
        ) throws {
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
                throw StemPrototypeError.metalFailure("could not create NMF command encoder")
            }
            encoder.setComputePipelineState(pipeline)
            configure(encoder)
            let threads = MTLSize(width: threadCount, height: 1, depth: 1)
            let group = MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1)
            encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
            encoder.endEncoding()
        }

        try encode(nmfXTBasesPipeline, threadCount: coefCount) { encoder in
            encoder.setBuffer(inputBuffer, offset: 0, index: 0)
            encoder.setBuffer(basesBuffer, offset: 0, index: 1)
            encoder.setBuffer(coefBuffer, offset: 0, index: 2)
            encoder.setBuffer(configBuffer, offset: 0, index: 3)
        }
        try encode(nmfSoftmaxRowsPipeline, threadCount: n) { encoder in
            encoder.setBuffer(coefBuffer, offset: 0, index: 0)
            encoder.setBuffer(configBuffer, offset: 0, index: 1)
        }

        for _ in 0..<steps {
            try encode(nmfXTBasesPipeline, threadCount: coefCount) { encoder in
                encoder.setBuffer(inputBuffer, offset: 0, index: 0)
                encoder.setBuffer(basesBuffer, offset: 0, index: 1)
                encoder.setBuffer(coefNumeratorBuffer, offset: 0, index: 2)
                encoder.setBuffer(configBuffer, offset: 0, index: 3)
            }
            try encode(nmfBasesGramPipeline, threadCount: gramCount) { encoder in
                encoder.setBuffer(basesBuffer, offset: 0, index: 0)
                encoder.setBuffer(basesGramBuffer, offset: 0, index: 1)
                encoder.setBuffer(configBuffer, offset: 0, index: 2)
            }
            try encode(nmfCoefTimesGramPipeline, threadCount: coefCount) { encoder in
                encoder.setBuffer(coefBuffer, offset: 0, index: 0)
                encoder.setBuffer(basesGramBuffer, offset: 0, index: 1)
                encoder.setBuffer(coefDenominatorBuffer, offset: 0, index: 2)
                encoder.setBuffer(configBuffer, offset: 0, index: 3)
            }
            try encode(nmfUpdateInPlacePipeline, threadCount: coefCount) { encoder in
                encoder.setBuffer(coefBuffer, offset: 0, index: 0)
                encoder.setBuffer(coefNumeratorBuffer, offset: 0, index: 1)
                encoder.setBuffer(coefDenominatorBuffer, offset: 0, index: 2)
                encoder.setBuffer(epsilonBuffer, offset: 0, index: 3)
                encoder.setBuffer(coefCountBuffer, offset: 0, index: 4)
            }
            try encode(nmfXCoefPipeline, threadCount: basesCount) { encoder in
                encoder.setBuffer(inputBuffer, offset: 0, index: 0)
                encoder.setBuffer(coefBuffer, offset: 0, index: 1)
                encoder.setBuffer(basesNumeratorBuffer, offset: 0, index: 2)
                encoder.setBuffer(configBuffer, offset: 0, index: 3)
            }
            try encode(nmfCoefGramPipeline, threadCount: gramCount) { encoder in
                encoder.setBuffer(coefBuffer, offset: 0, index: 0)
                encoder.setBuffer(coefGramBuffer, offset: 0, index: 1)
                encoder.setBuffer(configBuffer, offset: 0, index: 2)
            }
            try encode(nmfBasesTimesGramPipeline, threadCount: basesCount) { encoder in
                encoder.setBuffer(basesBuffer, offset: 0, index: 0)
                encoder.setBuffer(coefGramBuffer, offset: 0, index: 1)
                encoder.setBuffer(basesDenominatorBuffer, offset: 0, index: 2)
                encoder.setBuffer(configBuffer, offset: 0, index: 3)
            }
            try encode(nmfUpdateInPlacePipeline, threadCount: basesCount) { encoder in
                encoder.setBuffer(basesBuffer, offset: 0, index: 0)
                encoder.setBuffer(basesNumeratorBuffer, offset: 0, index: 1)
                encoder.setBuffer(basesDenominatorBuffer, offset: 0, index: 2)
                encoder.setBuffer(epsilonBuffer, offset: 0, index: 3)
                encoder.setBuffer(basesCountBuffer, offset: 0, index: 4)
            }
        }

        try encode(nmfXTBasesPipeline, threadCount: coefCount) { encoder in
            encoder.setBuffer(inputBuffer, offset: 0, index: 0)
            encoder.setBuffer(basesBuffer, offset: 0, index: 1)
            encoder.setBuffer(coefNumeratorBuffer, offset: 0, index: 2)
            encoder.setBuffer(configBuffer, offset: 0, index: 3)
        }
        try encode(nmfBasesGramPipeline, threadCount: gramCount) { encoder in
            encoder.setBuffer(basesBuffer, offset: 0, index: 0)
            encoder.setBuffer(basesGramBuffer, offset: 0, index: 1)
            encoder.setBuffer(configBuffer, offset: 0, index: 2)
        }
        try encode(nmfCoefTimesGramPipeline, threadCount: coefCount) { encoder in
            encoder.setBuffer(coefBuffer, offset: 0, index: 0)
            encoder.setBuffer(basesGramBuffer, offset: 0, index: 1)
            encoder.setBuffer(coefDenominatorBuffer, offset: 0, index: 2)
            encoder.setBuffer(configBuffer, offset: 0, index: 3)
        }
        try encode(nmfUpdateInPlacePipeline, threadCount: coefCount) { encoder in
            encoder.setBuffer(coefBuffer, offset: 0, index: 0)
            encoder.setBuffer(coefNumeratorBuffer, offset: 0, index: 1)
            encoder.setBuffer(coefDenominatorBuffer, offset: 0, index: 2)
            encoder.setBuffer(epsilonBuffer, offset: 0, index: 3)
            encoder.setBuffer(coefCountBuffer, offset: 0, index: 4)
        }
        try encode(nmfBasesCoefTPipeline, threadCount: outputCount) { encoder in
            encoder.setBuffer(basesBuffer, offset: 0, index: 0)
            encoder.setBuffer(coefBuffer, offset: 0, index: 1)
            encoder.setBuffer(outputBuffer, offset: 0, index: 2)
            encoder.setBuffer(configBuffer, offset: 0, index: 3)
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }

        return (
            output: finishOutput(outputBuffer, count: outputCount),
            finalBases: finishOutput(basesBuffer, count: basesCount),
            finalCoef: finishOutput(coefBuffer, count: coefCount)
        )
    }

    func runNormalize2ChannelsNCHW(input: [Float], shape: [Int]) throws -> [Float] {
        guard shape.count == 4, shape[1] == 2 else {
            throw StemPrototypeError.invalidFixture("2-channel normalize expects NCHW shape with C=2")
        }
        let outputCount = product(shape)
        guard let inputBuffer = device.makeBuffer(bytes: input, length: outputCount * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create normalize buffers")
        }
        var config = try tensorConfig(shape: shape)
        guard let configBuffer = device.makeBuffer(bytes: &config, length: MemoryLayout<Conv2DConfig>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create normalize command encoder")
        }
        encoder.setComputePipelineState(normalize2ChannelPipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(configBuffer, offset: 0, index: 2)
        let threads = MTLSize(width: shape[0] * shape[2] * shape[3], height: 1, depth: 1)
        let group = MTLSize(width: normalize2ChannelPipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    private func runUnary(input: [Float], pipeline: MTLComputePipelineState, label: String) throws -> [Float] {
        let outputCount = input.count
        guard let inputBuffer = device.makeBuffer(bytes: input, length: outputCount * MemoryLayout<Float>.stride),
              let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride)
        else {
            throw StemPrototypeError.metalFailure("could not create \(label) buffers")
        }
        var count = UInt32(outputCount)
        guard let countBuffer = device.makeBuffer(bytes: &count, length: MemoryLayout<UInt32>.stride),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw StemPrototypeError.metalFailure("could not create \(label) command encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(countBuffer, offset: 0, index: 2)
        let threads = MTLSize(width: outputCount, height: 1, depth: 1)
        let group = MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw StemPrototypeError.metalFailure(error.localizedDescription)
        }
        return finishOutput(outputBuffer, count: outputCount)
    }

    func runSigmoid(input: [Float]) throws -> [Float] {
        try runUnary(input: input, pipeline: sigmoidPipeline, label: "sigmoid")
    }

    func runLatitudeField(input: [Float]) throws -> [Float] {
        try runUnary(input: input, pipeline: latitudeFieldPipeline, label: "latitude field")
    }
}

func compare(actual: [Float], expected: [Float]) -> (maxAbs: Float, maxRelative: Float, rmse: Float) {
    var maxAbs: Float = 0
    var maxRelative: Float = 0
    var squared: Double = 0
    for index in actual.indices {
        let diff = abs(actual[index] - expected[index])
        maxAbs = max(maxAbs, diff)
        maxRelative = max(maxRelative, diff / max(1, abs(expected[index])))
        squared += Double(diff * diff)
    }
    return (maxAbs, maxRelative, Float((squared / Double(actual.count)).squareRoot()))
}

func convConfig(inputShape: [Int], outputShape: [Int], weightShape: [Int], stride: [Int], padding: [Int], groups: Int) throws -> Conv2DConfig {
    guard inputShape.count == 4, outputShape.count == 4, weightShape.count == 4 else {
        throw StemPrototypeError.invalidFixture("conv config expects 4D NCHW/OIHW shapes")
    }
    guard inputShape[1] % groups == 0, outputShape[1] % groups == 0 else {
        throw StemPrototypeError.invalidFixture("invalid grouped conv shape: input=\(inputShape), output=\(outputShape), groups=\(groups)")
    }
    guard weightShape[1] == inputShape[1] / groups else {
        throw StemPrototypeError.invalidFixture("invalid weight shape \(weightShape) for input=\(inputShape), groups=\(groups)")
    }
    return Conv2DConfig(
        batch: UInt32(inputShape[0]),
        inChannels: UInt32(inputShape[1]),
        outChannels: UInt32(outputShape[1]),
        groups: UInt32(groups),
        inputHeight: UInt32(inputShape[2]),
        inputWidth: UInt32(inputShape[3]),
        outputHeight: UInt32(outputShape[2]),
        outputWidth: UInt32(outputShape[3]),
        kernelHeight: UInt32(weightShape[2]),
        kernelWidth: UInt32(weightShape[3]),
        strideY: UInt32(stride[0]),
        strideX: UInt32(stride[1]),
        paddingY: UInt32(padding[0]),
        paddingX: UInt32(padding[1])
    )
}

func tensorConfig(shape: [Int]) throws -> Conv2DConfig {
    guard shape.count == 4 else {
        throw StemPrototypeError.invalidFixture("tensor config expects a 4D NCHW shape")
    }
    return Conv2DConfig(
        batch: UInt32(shape[0]),
        inChannels: UInt32(shape[1]),
        outChannels: UInt32(shape[1]),
        groups: 1,
        inputHeight: UInt32(shape[2]),
        inputWidth: UInt32(shape[3]),
        outputHeight: UInt32(shape[2]),
        outputWidth: UInt32(shape[3]),
        kernelHeight: 1,
        kernelWidth: 1,
        strideY: 1,
        strideX: 1,
        paddingY: 0,
        paddingX: 0
    )
}

func convOutputShape(inputShape: [Int], spec: ConvLayerSpec) throws -> [Int] {
    guard inputShape.count == 4, spec.weightShape.count == 4 else {
        throw StemPrototypeError.invalidFixture("conv output shape expects 4D shapes")
    }
    let dilation = spec.dilation ?? [1, 1]
    let outHeight = ((inputShape[2] + 2 * spec.padding[0] - dilation[0] * (spec.weightShape[2] - 1) - 1) / spec.stride[0]) + 1
    let outWidth = ((inputShape[3] + 2 * spec.padding[1] - dilation[1] * (spec.weightShape[3] - 1) - 1) / spec.stride[1]) + 1
    return [inputShape[0], spec.weightShape[0], outHeight, outWidth]
}

func loadConvWeights(_ spec: ConvLayerSpec, fixtures: URL) throws -> (weight: [Float], bias: [Float]) {
    let dilation = spec.dilation ?? [1, 1]
    guard dilation == [1, 1] else {
        throw StemPrototypeError.invalidFixture("dilated conv is not supported by this prototype")
    }
    return (
        weight: try readFloat32Array(
            fixtures.appendingPathComponent(spec.weight),
            expectedCount: product(spec.weightShape)
        ),
        bias: try readFloat32Array(
            fixtures.appendingPathComponent(spec.bias),
            expectedCount: product(spec.biasShape)
        )
    )
}

func runConvLayer(
    runner: MetalConv2DRunner,
    input: [Float],
    inputShape: [Int],
    spec: ConvLayerSpec,
    weights: (weight: [Float], bias: [Float])
) throws -> (output: [Float], shape: [Int]) {
    let outputShape = try convOutputShape(inputShape: inputShape, spec: spec)
    let config = try convConfig(
        inputShape: inputShape,
        outputShape: outputShape,
        weightShape: spec.weightShape,
        stride: spec.stride,
        padding: spec.padding,
        groups: spec.groups ?? 1
    )
    return (
        output: try runner.runConv2D(
            input: input,
            weight: weights.weight,
            bias: weights.bias,
            config: config
        ),
        shape: outputShape
    )
}

func runConvModule(
    runner: MetalConv2DRunner,
    input: [Float],
    inputShape: [Int],
    spec: ConvLayerSpec,
    weights: (weight: [Float], bias: [Float])
) throws -> (output: [Float], shape: [Int]) {
    let conv = try runConvLayer(
        runner: runner,
        input: input,
        inputShape: inputShape,
        spec: spec,
        weights: weights
    )
    return (output: try runner.runReLU(input: conv.output), shape: conv.shape)
}

func readEntryTensor(_ entry: Entry, key: String, fixtures: URL) throws -> (values: [Float], shape: [Int]) {
    guard let name = entry.tensors?[key],
          let shape = entry.shapes?[key]
    else {
        throw StemPrototypeError.invalidFixture("missing block tensor \(key) for \(entry.filename)")
    }
    return (
        values: try readFloat32Array(
            fixtures.appendingPathComponent(name),
            expectedCount: product(shape)
        ),
        shape: shape
    )
}

struct LoadedResidualConvUnit {
    let spec: ResidualConvUnitSpec
    let conv1: (weight: [Float], bias: [Float])
    let conv2: (weight: [Float], bias: [Float])
}

func loadResidualConvUnit(_ spec: ResidualConvUnitSpec, fixtures: URL) throws -> LoadedResidualConvUnit {
    LoadedResidualConvUnit(
        spec: spec,
        conv1: try loadConvWeights(spec.conv1, fixtures: fixtures),
        conv2: try loadConvWeights(spec.conv2, fixtures: fixtures)
    )
}

func runResidualConvUnit(
    runner: MetalConv2DRunner,
    input: [Float],
    inputShape: [Int],
    unit: LoadedResidualConvUnit
) throws -> (conv1: [Float], conv2: [Float], output: [Float], shape: [Int]) {
    let relu1 = try runner.runReLU(input: input)
    let conv1 = try runConvLayer(
        runner: runner,
        input: relu1,
        inputShape: inputShape,
        spec: unit.spec.conv1,
        weights: unit.conv1
    )
    let relu2 = try runner.runReLU(input: conv1.output)
    let conv2 = try runConvLayer(
        runner: runner,
        input: relu2,
        inputShape: conv1.shape,
        spec: unit.spec.conv2,
        weights: unit.conv2
    )
    return (
        conv1: conv1.output,
        conv2: conv2.output,
        output: try runner.runAdd(inputA: conv2.output, inputB: relu1),
        shape: conv2.shape
    )
}

struct LoadedBlock {
    let spec: Block1Spec
    let norm1Scale: [Float]
    let norm1Offset: [Float]
    let norm2Scale: [Float]
    let norm2Offset: [Float]
    let layerScale1: [Float]
    let layerScale2: [Float]
    let attnProj1: (weight: [Float], bias: [Float])
    let attnConv0: (weight: [Float], bias: [Float])
    let attnConv0_1: (weight: [Float], bias: [Float])
    let attnConv0_2: (weight: [Float], bias: [Float])
    let attnConv1_1: (weight: [Float], bias: [Float])
    let attnConv1_2: (weight: [Float], bias: [Float])
    let attnConv2_1: (weight: [Float], bias: [Float])
    let attnConv2_2: (weight: [Float], bias: [Float])
    let attnConv3: (weight: [Float], bias: [Float])
    let attnProj2: (weight: [Float], bias: [Float])
    let mlpFC1: (weight: [Float], bias: [Float])
    let mlpDWConv: (weight: [Float], bias: [Float])
    let mlpFC2: (weight: [Float], bias: [Float])
}

func loadBlock(_ block: Block1Spec, fixtures: URL) throws -> LoadedBlock {
    LoadedBlock(
        spec: block,
        norm1Scale: try readFloat32Array(fixtures.appendingPathComponent(block.norm1.scale), expectedCount: product(block.norm1.shape)),
        norm1Offset: try readFloat32Array(fixtures.appendingPathComponent(block.norm1.offset), expectedCount: product(block.norm1.shape)),
        norm2Scale: try readFloat32Array(fixtures.appendingPathComponent(block.norm2.scale), expectedCount: product(block.norm2.shape)),
        norm2Offset: try readFloat32Array(fixtures.appendingPathComponent(block.norm2.offset), expectedCount: product(block.norm2.shape)),
        layerScale1: try readFloat32Array(fixtures.appendingPathComponent(block.layerScale1.path), expectedCount: product(block.layerScale1.shape)),
        layerScale2: try readFloat32Array(fixtures.appendingPathComponent(block.layerScale2.path), expectedCount: product(block.layerScale2.shape)),
        attnProj1: try loadConvWeights(block.attn.proj1, fixtures: fixtures),
        attnConv0: try loadConvWeights(block.attn.sgu.conv0, fixtures: fixtures),
        attnConv0_1: try loadConvWeights(block.attn.sgu.conv0_1, fixtures: fixtures),
        attnConv0_2: try loadConvWeights(block.attn.sgu.conv0_2, fixtures: fixtures),
        attnConv1_1: try loadConvWeights(block.attn.sgu.conv1_1, fixtures: fixtures),
        attnConv1_2: try loadConvWeights(block.attn.sgu.conv1_2, fixtures: fixtures),
        attnConv2_1: try loadConvWeights(block.attn.sgu.conv2_1, fixtures: fixtures),
        attnConv2_2: try loadConvWeights(block.attn.sgu.conv2_2, fixtures: fixtures),
        attnConv3: try loadConvWeights(block.attn.sgu.conv3, fixtures: fixtures),
        attnProj2: try loadConvWeights(block.attn.proj2, fixtures: fixtures),
        mlpFC1: try loadConvWeights(block.mlp.fc1, fixtures: fixtures),
        mlpDWConv: try loadConvWeights(block.mlp.dwconv, fixtures: fixtures),
        mlpFC2: try loadConvWeights(block.mlp.fc2, fixtures: fixtures)
    )
}

struct LoadedStem {
    let spec: StemSpec
    let conv0: (weight: [Float], bias: [Float])
    let conv3: (weight: [Float], bias: [Float])
    let bn1Scale: [Float]
    let bn1Offset: [Float]
    let bn4Scale: [Float]
    let bn4Offset: [Float]
}

func loadStem(_ spec: StemSpec, fixtures: URL) throws -> LoadedStem {
    LoadedStem(
        spec: spec,
        conv0: try loadConvWeights(spec.conv0, fixtures: fixtures),
        conv3: try loadConvWeights(spec.conv3, fixtures: fixtures),
        bn1Scale: try readFloat32Array(fixtures.appendingPathComponent(spec.bn1.scale), expectedCount: product(spec.bn1.shape)),
        bn1Offset: try readFloat32Array(fixtures.appendingPathComponent(spec.bn1.offset), expectedCount: product(spec.bn1.shape)),
        bn4Scale: try readFloat32Array(fixtures.appendingPathComponent(spec.bn4.scale), expectedCount: product(spec.bn4.shape)),
        bn4Offset: try readFloat32Array(fixtures.appendingPathComponent(spec.bn4.offset), expectedCount: product(spec.bn4.shape))
    )
}

func rgbToBGR255(_ input: [Float], shape: [Int]) throws -> [Float] {
    guard shape.count == 4, shape[1] == 3 else {
        throw StemPrototypeError.invalidFixture("RGB input expects NCHW shape with C=3")
    }
    let batch = shape[0]
    let height = shape[2]
    let width = shape[3]
    let spatial = height * width
    var output = [Float](repeating: 0, count: input.count)
    for b in 0..<batch {
        let base = b * 3 * spatial
        for index in 0..<spatial {
            output[base + index] = input[base + 2 * spatial + index] * 255
            output[base + spatial + index] = input[base + spatial + index] * 255
            output[base + 2 * spatial + index] = input[base + index] * 255
        }
    }
    return output
}

func runStem(
    runner: MetalConv2DRunner,
    inputBGR255: [Float],
    inputShape: [Int],
    stem: LoadedStem
) throws -> (output: [Float], shape: [Int]) {
    let conv0 = try runConvLayer(
        runner: runner,
        input: inputBGR255,
        inputShape: inputShape,
        spec: stem.spec.conv0,
        weights: stem.conv0
    )
    let bn1 = try runner.runAffine(
        input: conv0.output,
        scale: stem.bn1Scale,
        offset: stem.bn1Offset,
        config: try tensorConfig(shape: conv0.shape)
    )
    let gelu = try runner.runGELU(input: bn1)
    let conv3 = try runConvLayer(
        runner: runner,
        input: gelu,
        inputShape: conv0.shape,
        spec: stem.spec.conv3,
        weights: stem.conv3
    )
    let bn4 = try runner.runAffine(
        input: conv3.output,
        scale: stem.bn4Scale,
        offset: stem.bn4Offset,
        config: try tensorConfig(shape: conv3.shape)
    )
    return (output: bn4, shape: conv3.shape)
}

func runLoadedBlock(
    runner: MetalConv2DRunner,
    input: [Float],
    inputShape: [Int],
    block: LoadedBlock
) throws -> (output: [Float], shape: [Int], attnOutput: [Float], afterAttn: [Float], norm2: [Float], mlpOutput: [Float]) {
    let spec = block.spec
    let norm1 = try runner.runAffine(
        input: input,
        scale: block.norm1Scale,
        offset: block.norm1Offset,
        config: try tensorConfig(shape: inputShape)
    )

    let proj1 = try runConvLayer(runner: runner, input: norm1, inputShape: inputShape, spec: spec.attn.proj1, weights: block.attnProj1)
    let proj1GELU = try runner.runGELU(input: proj1.output)
    let sguConv0 = try runConvLayer(runner: runner, input: proj1GELU, inputShape: proj1.shape, spec: spec.attn.sgu.conv0, weights: block.attnConv0)
    let sguConv0_1 = try runConvLayer(runner: runner, input: sguConv0.output, inputShape: sguConv0.shape, spec: spec.attn.sgu.conv0_1, weights: block.attnConv0_1)
    let sguConv0_2 = try runConvLayer(runner: runner, input: sguConv0_1.output, inputShape: sguConv0_1.shape, spec: spec.attn.sgu.conv0_2, weights: block.attnConv0_2)
    let sguConv1_1 = try runConvLayer(runner: runner, input: sguConv0.output, inputShape: sguConv0.shape, spec: spec.attn.sgu.conv1_1, weights: block.attnConv1_1)
    let sguConv1_2 = try runConvLayer(runner: runner, input: sguConv1_1.output, inputShape: sguConv1_1.shape, spec: spec.attn.sgu.conv1_2, weights: block.attnConv1_2)
    let sguConv2_1 = try runConvLayer(runner: runner, input: sguConv0.output, inputShape: sguConv0.shape, spec: spec.attn.sgu.conv2_1, weights: block.attnConv2_1)
    let sguConv2_2 = try runConvLayer(runner: runner, input: sguConv2_1.output, inputShape: sguConv2_1.shape, spec: spec.attn.sgu.conv2_2, weights: block.attnConv2_2)

    let sguSum01 = try runner.runAdd(inputA: sguConv0.output, inputB: sguConv0_2.output)
    let sguSum012 = try runner.runAdd(inputA: sguSum01, inputB: sguConv1_2.output)
    let sguSum = try runner.runAdd(inputA: sguSum012, inputB: sguConv2_2.output)
    let sguConv3 = try runConvLayer(runner: runner, input: sguSum, inputShape: sguConv0.shape, spec: spec.attn.sgu.conv3, weights: block.attnConv3)
    let sguOutput = try runner.runMultiply(inputA: sguConv3.output, inputB: proj1GELU)
    let proj2 = try runConvLayer(runner: runner, input: sguOutput, inputShape: sguConv3.shape, spec: spec.attn.proj2, weights: block.attnProj2)
    let attnOutput = try runner.runAdd(inputA: proj2.output, inputB: norm1)

    let afterAttn = try runner.runAddScaledChannels(
        residual: input,
        branch: attnOutput,
        scale: block.layerScale1,
        config: try tensorConfig(shape: inputShape)
    )
    let norm2 = try runner.runAffine(
        input: afterAttn,
        scale: block.norm2Scale,
        offset: block.norm2Offset,
        config: try tensorConfig(shape: inputShape)
    )
    let mlpFC1Output = try runConvLayer(runner: runner, input: norm2, inputShape: inputShape, spec: spec.mlp.fc1, weights: block.mlpFC1)
    let mlpDWOutput = try runConvLayer(runner: runner, input: mlpFC1Output.output, inputShape: mlpFC1Output.shape, spec: spec.mlp.dwconv, weights: block.mlpDWConv)
    let mlpGELU = try runner.runGELU(input: mlpDWOutput.output)
    let mlpOutput = try runConvLayer(runner: runner, input: mlpGELU, inputShape: mlpDWOutput.shape, spec: spec.mlp.fc2, weights: block.mlpFC2)

    let final = try runner.runAddScaledChannels(
        residual: afterAttn,
        branch: mlpOutput.output,
        scale: block.layerScale2,
        config: try tensorConfig(shape: inputShape)
    )
    return (final, inputShape, attnOutput, afterAttn, norm2, mlpOutput.output)
}

struct LoadedStage {
    let patchEmbed: PatchEmbedSpec?
    let patchWeights: (weight: [Float], bias: [Float])?
    let patchNormScale: [Float]?
    let patchNormOffset: [Float]?
    let blocks: [LoadedBlock]
    let norm: LayerNormSpec
    let normWeight: [Float]
    let normBias: [Float]
}

func loadStage(
    patchEmbed: PatchEmbedSpec?,
    blocks: [Block1Spec],
    norm: LayerNormSpec,
    fixtures: URL
) throws -> LoadedStage {
    LoadedStage(
        patchEmbed: patchEmbed,
        patchWeights: try patchEmbed.map { try loadConvWeights($0.proj, fixtures: fixtures) },
        patchNormScale: try patchEmbed.map {
            try readFloat32Array(fixtures.appendingPathComponent($0.norm.scale), expectedCount: product($0.norm.shape))
        },
        patchNormOffset: try patchEmbed.map {
            try readFloat32Array(fixtures.appendingPathComponent($0.norm.offset), expectedCount: product($0.norm.shape))
        },
        blocks: try blocks.map { try loadBlock($0, fixtures: fixtures) },
        norm: norm,
        normWeight: try readFloat32Array(fixtures.appendingPathComponent(norm.weight), expectedCount: product(norm.shape)),
        normBias: try readFloat32Array(fixtures.appendingPathComponent(norm.bias), expectedCount: product(norm.shape))
    )
}

func runStageForward(
    runner: MetalConv2DRunner,
    input: [Float],
    inputShape: [Int],
    stage: LoadedStage
) throws -> (output: [Float], shape: [Int]) {
    var current = (values: input, shape: inputShape)
    if let patchEmbed = stage.patchEmbed,
       let patchWeights = stage.patchWeights,
       let patchNormScale = stage.patchNormScale,
       let patchNormOffset = stage.patchNormOffset {
        let patchConv = try runConvLayer(
            runner: runner,
            input: current.values,
            inputShape: current.shape,
            spec: patchEmbed.proj,
            weights: patchWeights
        )
        let patchOutput = try runner.runAffine(
            input: patchConv.output,
            scale: patchNormScale,
            offset: patchNormOffset,
            config: try tensorConfig(shape: patchConv.shape)
        )
        current = (values: patchOutput, shape: patchConv.shape)
    }

    for block in stage.blocks {
        let result = try runLoadedBlock(
            runner: runner,
            input: current.values,
            inputShape: current.shape,
            block: block
        )
        current = (values: result.output, shape: result.shape)
    }

    let final = try runner.runLayerNormNCHW(
        input: current.values,
        shape: current.shape,
        weight: stage.normWeight,
        bias: stage.normBias,
        epsilon: stage.norm.eps
    )
    return (output: final, shape: current.shape)
}

struct LoadedLowLevelEncoder {
    let spec: LowLevelEncoderSpec
    let conv1: (weight: [Float], bias: [Float])
    let conv2: (weight: [Float], bias: [Float])
}

func loadLowLevelEncoder(_ spec: LowLevelEncoderSpec, fixtures: URL) throws -> LoadedLowLevelEncoder {
    LoadedLowLevelEncoder(
        spec: spec,
        conv1: try loadConvWeights(spec.conv1, fixtures: fixtures),
        conv2: try loadConvWeights(spec.conv2, fixtures: fixtures)
    )
}

func runLowLevelEncoder(
    runner: MetalConv2DRunner,
    input: [Float],
    inputShape: [Int],
    encoder: LoadedLowLevelEncoder
) throws -> (output: [Float], shape: [Int]) {
    let conv1 = try runConvModule(
        runner: runner,
        input: input,
        inputShape: inputShape,
        spec: encoder.spec.conv1,
        weights: encoder.conv1
    )
    return try runConvModule(
        runner: runner,
        input: conv1.output,
        inputShape: conv1.shape,
        spec: encoder.spec.conv2,
        weights: encoder.conv2
    )
}

struct LoadedFullHead {
    let spec: FullHeadSpec
    let squeeze: (weight: [Float], bias: [Float])
    let hamIn: (weight: [Float], bias: [Float])
    let hamOut: (weight: [Float], bias: [Float])
    let bases: [Float]
    let align: (weight: [Float], bias: [Float])
    let outConv: (weight: [Float], bias: [Float])
    let fusionUnit1: LoadedResidualConvUnit
    let fusionUnit2: LoadedResidualConvUnit
    let uncertaintyHidden: (weight: [Float], bias: [Float])
    let uncertaintyLinear: (weight: [Float], bias: [Float])
    let linearPredUp: (weight: [Float], bias: [Float])?
    let linearPredLatitude: (weight: [Float], bias: [Float])?
}

func loadFullHead(_ spec: FullHeadSpec, fixtures: URL) throws -> LoadedFullHead {
    LoadedFullHead(
        spec: spec,
        squeeze: try loadConvWeights(spec.squeeze, fixtures: fixtures),
        hamIn: try loadConvWeights(spec.hamIn, fixtures: fixtures),
        hamOut: try loadConvWeights(spec.hamOut, fixtures: fixtures),
        bases: try readFloat32Array(fixtures.appendingPathComponent(spec.nmf.bases), expectedCount: product(spec.nmf.basisShape)),
        align: try loadConvWeights(spec.align, fixtures: fixtures),
        outConv: try loadConvWeights(spec.outConv, fixtures: fixtures),
        fusionUnit1: try loadResidualConvUnit(spec.fusion.resConfUnit1, fixtures: fixtures),
        fusionUnit2: try loadResidualConvUnit(spec.fusion.resConfUnit2, fixtures: fixtures),
        uncertaintyHidden: try loadConvWeights(spec.uncertainty.hidden, fixtures: fixtures),
        uncertaintyLinear: try loadConvWeights(spec.uncertainty.linear, fixtures: fixtures),
        linearPredUp: try spec.linearPredUp.map { try loadConvWeights($0, fixtures: fixtures) },
        linearPredLatitude: try spec.linearPredLatitude.map { try loadConvWeights($0, fixtures: fixtures) }
    )
}

func runFullHead(
    runner: MetalConv2DRunner,
    levels: [(values: [Float], shape: [Int])],
    lowLevel: (values: [Float], shape: [Int]),
    head: LoadedFullHead
) throws -> (field: [Float], fieldShape: [Int], confidence: [Float], confidenceShape: [Int]) {
    guard levels.count == 4 else {
        throw StemPrototypeError.invalidFixture("full head expects four high-level feature tensors")
    }
    let targetHeight = levels[0].shape[2]
    let targetWidth = levels[0].shape[3]
    let resized = try levels.map { level in
        let outputShape = [level.shape[0], level.shape[1], targetHeight, targetWidth]
        return (
            values: try runner.runBilinearResizeNCHW(
                input: level.values,
                inputShape: level.shape,
                outputShape: outputShape
            ),
            shape: outputShape
        )
    }
    let concatShape = [
        resized[0].shape[0],
        resized.reduce(0) { $0 + $1.shape[1] },
        targetHeight,
        targetWidth,
    ]
    let concat = try runner.runConcat4NCHW(inputs: resized, outputShape: concatShape)
    let squeeze = try runConvModule(
        runner: runner,
        input: concat,
        inputShape: concatShape,
        spec: head.spec.squeeze,
        weights: head.squeeze
    )
    let hamIn = try runConvModule(
        runner: runner,
        input: squeeze.output,
        inputShape: squeeze.shape,
        spec: head.spec.hamIn,
        weights: head.hamIn
    )
    let nmf = try runner.runFixedNMF(
        input: hamIn.output,
        shape: hamIn.shape,
        bases: head.bases,
        basisShape: head.spec.nmf.basisShape,
        steps: head.spec.nmf.steps,
        epsilon: head.spec.nmf.epsilon,
        invT: head.spec.nmf.invT
    )
    let hamOut = try runConvModule(
        runner: runner,
        input: nmf.output,
        inputShape: hamIn.shape,
        spec: head.spec.hamOut,
        weights: head.hamOut
    )
    let hamResidual = try runner.runAdd(inputA: squeeze.output, inputB: hamOut.output)
    let hamburger = try runner.runReLU(input: hamResidual)
    let align = try runConvModule(
        runner: runner,
        input: hamburger,
        inputShape: squeeze.shape,
        spec: head.spec.align,
        weights: head.align
    )
    let alignUpShape = [align.shape[0], align.shape[1], align.shape[2] * 2, align.shape[3] * 2]
    let alignUp = try runner.runBilinearResizeNCHW(input: align.output, inputShape: align.shape, outputShape: alignUpShape)
    let outConv = try runConvModule(
        runner: runner,
        input: alignUp,
        inputShape: alignUpShape,
        spec: head.spec.outConv,
        weights: head.outConv
    )
    let outUpShape = [outConv.shape[0], outConv.shape[1], outConv.shape[2] * 2, outConv.shape[3] * 2]
    let outUp = try runner.runBilinearResizeNCHW(input: outConv.output, inputShape: outConv.shape, outputShape: outUpShape)
    let llResidual = try runResidualConvUnit(runner: runner, input: lowLevel.values, inputShape: lowLevel.shape, unit: head.fusionUnit1)
    let fusionSum = try runner.runAdd(inputA: outUp, inputB: llResidual.output)
    let fusion = try runResidualConvUnit(runner: runner, input: fusionSum, inputShape: outUpShape, unit: head.fusionUnit2)
    let uncertaintyHidden = try runConvModule(
        runner: runner,
        input: fusion.output,
        inputShape: fusion.shape,
        spec: head.spec.uncertainty.hidden,
        weights: head.uncertaintyHidden
    )
    let logUncertainty = try runConvLayer(
        runner: runner,
        input: uncertaintyHidden.output,
        inputShape: uncertaintyHidden.shape,
        spec: head.spec.uncertainty.linear,
        weights: head.uncertaintyLinear
    )
    let confidence = try runner.runSigmoid(input: logUncertainty.output)

    switch head.spec.head {
    case "up":
        guard let linearPredUp = head.spec.linearPredUp,
              let linearPredUpWeights = head.linearPredUp
        else {
            throw StemPrototypeError.invalidFixture("full up head missing linear_pred_up")
        }
        let logits = try runConvLayer(
            runner: runner,
            input: fusion.output,
            inputShape: fusion.shape,
            spec: linearPredUp,
            weights: linearPredUpWeights
        )
        return (
            field: try runner.runNormalize2ChannelsNCHW(input: logits.output, shape: logits.shape),
            fieldShape: logits.shape,
            confidence: confidence,
            confidenceShape: logUncertainty.shape
        )
    case "latitude":
        guard let linearPredLatitude = head.spec.linearPredLatitude,
              let linearPredLatitudeWeights = head.linearPredLatitude
        else {
            throw StemPrototypeError.invalidFixture("full latitude head missing linear_pred_latitude")
        }
        let logits = try runConvLayer(
            runner: runner,
            input: fusion.output,
            inputShape: fusion.shape,
            spec: linearPredLatitude,
            weights: linearPredLatitudeWeights
        )
        return (
            field: try runner.runLatitudeField(input: logits.output),
            fieldShape: logits.shape,
            confidence: confidence,
            confidenceShape: logUncertainty.shape
        )
    default:
        throw StemPrototypeError.invalidFixture("unsupported full head \(head.spec.head)")
    }
}

func recordStage(
    name: String,
    filename: String,
    actual: [Float],
    expected: [Float],
    options: Options,
    stages: inout [String: MutableStageSummary],
    failures: inout [String],
    globalMaxAbs: inout Float,
    globalMaxRelative: inout Float,
    globalMaxRMSE: inout Float
) {
    let metrics = compare(actual: actual, expected: expected)
    var stage = stages[name] ?? MutableStageSummary()
    stage.count += 1
    stage.maxAbsDifference = max(stage.maxAbsDifference, metrics.maxAbs)
    stage.maxRelativeDifference = max(stage.maxRelativeDifference, metrics.maxRelative)
    stage.maxRMSE = max(stage.maxRMSE, metrics.rmse)
    let failed = metrics.maxAbs > options.absTolerance ||
        metrics.maxRelative > options.relativeTolerance ||
        metrics.rmse > options.rmseTolerance
    if failed {
        stage.failedCount += 1
        failures.append(
            "\(filename) \(name): maxAbs=\(metrics.maxAbs), maxRelative=\(metrics.maxRelative), rmse=\(metrics.rmse)"
        )
    }
    stages[name] = stage
    globalMaxAbs = max(globalMaxAbs, metrics.maxAbs)
    globalMaxRelative = max(globalMaxRelative, metrics.maxRelative)
    globalMaxRMSE = max(globalMaxRMSE, metrics.rmse)
}

func verifyStage(
    options: Options,
    manifest: Manifest,
    stageName: String,
    patchEmbed: PatchEmbedSpec?,
    blocks: [Block1Spec],
    norm: LayerNormSpec
) throws -> VerificationSummary {
    let runner = try MetalConv2DRunner(metalSource: options.metalSource)
    let loadedBlocks = try blocks.map { try loadBlock($0, fixtures: options.fixtures) }
    let normWeight = try readFloat32Array(
        options.fixtures.appendingPathComponent(norm.weight),
        expectedCount: product(norm.shape)
    )
    let normBias = try readFloat32Array(
        options.fixtures.appendingPathComponent(norm.bias),
        expectedCount: product(norm.shape)
    )
    let patchWeights = try patchEmbed.map { try loadConvWeights($0.proj, fixtures: options.fixtures) }
    let patchNormScale = try patchEmbed.map {
        try readFloat32Array(
            options.fixtures.appendingPathComponent($0.norm.scale),
            expectedCount: product($0.norm.shape)
        )
    }
    let patchNormOffset = try patchEmbed.map {
        try readFloat32Array(
            options.fixtures.appendingPathComponent($0.norm.offset),
            expectedCount: product($0.norm.shape)
        )
    }

    var failures: [String] = []
    var stages: [String: MutableStageSummary] = [:]
    var globalMaxAbs: Float = 0
    var globalMaxRelative: Float = 0
    var globalMaxRMSE: Float = 0

    for entry in manifest.entries {
        var current = try readEntryTensor(entry, key: "input_nchw", fixtures: options.fixtures)
        if let patchEmbed,
           let patchWeights,
           let patchNormScale,
           let patchNormOffset {
            let patchConv = try runConvLayer(
                runner: runner,
                input: current.values,
                inputShape: current.shape,
                spec: patchEmbed.proj,
                weights: patchWeights
            )
            let patchOutput = try runner.runAffine(
                input: patchConv.output,
                scale: patchNormScale,
                offset: patchNormOffset,
                config: try tensorConfig(shape: patchConv.shape)
            )
            current = (values: patchOutput, shape: patchConv.shape)
            let expectedPatch = try readEntryTensor(entry, key: "patch_embed_nchw", fixtures: options.fixtures)
            recordStage(
                name: "\(stageName).patch_embed_nchw",
                filename: entry.filename,
                actual: current.values,
                expected: expectedPatch.values,
                options: options,
                stages: &stages,
                failures: &failures,
                globalMaxAbs: &globalMaxAbs,
                globalMaxRelative: &globalMaxRelative,
                globalMaxRMSE: &globalMaxRMSE
            )
        }

        for (index, block) in loadedBlocks.enumerated() {
            let result = try runLoadedBlock(
                runner: runner,
                input: current.values,
                inputShape: current.shape,
                block: block
            )
            current = (values: result.output, shape: result.shape)
            let expected = try readEntryTensor(
                entry,
                key: "block\(index)_final_nchw",
                fixtures: options.fixtures
            )
            recordStage(
                name: "\(stageName).block\(index)_final_nchw",
                filename: entry.filename,
                actual: current.values,
                expected: expected.values,
                options: options,
                stages: &stages,
                failures: &failures,
                globalMaxAbs: &globalMaxAbs,
                globalMaxRelative: &globalMaxRelative,
                globalMaxRMSE: &globalMaxRMSE
            )
        }

        let final = try runner.runLayerNormNCHW(
            input: current.values,
            shape: current.shape,
            weight: normWeight,
            bias: normBias,
            epsilon: norm.eps
        )
        let expectedFinal = try readEntryTensor(entry, key: "final_nchw", fixtures: options.fixtures)
        recordStage(
            name: "\(stageName).final_nchw",
            filename: entry.filename,
            actual: final,
            expected: expectedFinal.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )
    }

    let frozenStages = Dictionary(uniqueKeysWithValues: stages.map { ($0.key, $0.value.frozen()) })
    let failedFixtures = Set(failures.compactMap { $0.split(separator: " ").first.map(String.init) }).count
    let summary = VerificationSummary(
        fixtureCount: manifest.entries.count,
        passedCount: manifest.entries.count - failedFixtures,
        failedCount: failedFixtures,
        maxAbsDifference: globalMaxAbs,
        maxRelativeDifference: globalMaxRelative,
        maxRMSE: globalMaxRMSE,
        stages: frozenStages,
        failures: Array(failures.prefix(25))
    )
    try writeJSON(summary, to: options.outputJSON)
    return summary
}

func verifyStage1(options: Options, manifest: Manifest, stage: Stage1Spec) throws -> VerificationSummary {
    try verifyStage(
        options: options,
        manifest: manifest,
        stageName: "stage1",
        patchEmbed: nil,
        blocks: stage.blocks,
        norm: stage.norm
    )
}

func verifyBlock1(options: Options, manifest: Manifest, block: Block1Spec) throws -> VerificationSummary {
    let runner = try MetalConv2DRunner(metalSource: options.metalSource)
    var failures: [String] = []
    var stages: [String: MutableStageSummary] = [:]
    var globalMaxAbs: Float = 0
    var globalMaxRelative: Float = 0
    var globalMaxRMSE: Float = 0

    let norm1Scale = try readFloat32Array(options.fixtures.appendingPathComponent(block.norm1.scale), expectedCount: product(block.norm1.shape))
    let norm1Offset = try readFloat32Array(options.fixtures.appendingPathComponent(block.norm1.offset), expectedCount: product(block.norm1.shape))
    let norm2Scale = try readFloat32Array(options.fixtures.appendingPathComponent(block.norm2.scale), expectedCount: product(block.norm2.shape))
    let norm2Offset = try readFloat32Array(options.fixtures.appendingPathComponent(block.norm2.offset), expectedCount: product(block.norm2.shape))
    let layerScale1 = try readFloat32Array(options.fixtures.appendingPathComponent(block.layerScale1.path), expectedCount: product(block.layerScale1.shape))
    let layerScale2 = try readFloat32Array(options.fixtures.appendingPathComponent(block.layerScale2.path), expectedCount: product(block.layerScale2.shape))

    let attnProj1 = try loadConvWeights(block.attn.proj1, fixtures: options.fixtures)
    let attnConv0 = try loadConvWeights(block.attn.sgu.conv0, fixtures: options.fixtures)
    let attnConv0_1 = try loadConvWeights(block.attn.sgu.conv0_1, fixtures: options.fixtures)
    let attnConv0_2 = try loadConvWeights(block.attn.sgu.conv0_2, fixtures: options.fixtures)
    let attnConv1_1 = try loadConvWeights(block.attn.sgu.conv1_1, fixtures: options.fixtures)
    let attnConv1_2 = try loadConvWeights(block.attn.sgu.conv1_2, fixtures: options.fixtures)
    let attnConv2_1 = try loadConvWeights(block.attn.sgu.conv2_1, fixtures: options.fixtures)
    let attnConv2_2 = try loadConvWeights(block.attn.sgu.conv2_2, fixtures: options.fixtures)
    let attnConv3 = try loadConvWeights(block.attn.sgu.conv3, fixtures: options.fixtures)
    let attnProj2 = try loadConvWeights(block.attn.proj2, fixtures: options.fixtures)

    let mlpFC1 = try loadConvWeights(block.mlp.fc1, fixtures: options.fixtures)
    let mlpDWConv = try loadConvWeights(block.mlp.dwconv, fixtures: options.fixtures)
    let mlpFC2 = try loadConvWeights(block.mlp.fc2, fixtures: options.fixtures)

    for entry in manifest.entries {
        let inputTensor = try readEntryTensor(entry, key: "input_nchw", fixtures: options.fixtures)
        let norm1Expected = try readEntryTensor(entry, key: "norm1", fixtures: options.fixtures)
        let attnExpected = try readEntryTensor(entry, key: "attn_output", fixtures: options.fixtures)
        let afterAttnExpected = try readEntryTensor(entry, key: "after_attn", fixtures: options.fixtures)
        let norm2Expected = try readEntryTensor(entry, key: "norm2", fixtures: options.fixtures)
        let mlpExpected = try readEntryTensor(entry, key: "mlp_output", fixtures: options.fixtures)
        let finalExpected = try readEntryTensor(entry, key: "final_nchw", fixtures: options.fixtures)

        let norm1 = try runner.runAffine(
            input: inputTensor.values,
            scale: norm1Scale,
            offset: norm1Offset,
            config: try tensorConfig(shape: inputTensor.shape)
        )
        recordStage(name: "block1.norm1", filename: entry.filename, actual: norm1, expected: norm1Expected.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let proj1 = try runConvLayer(runner: runner, input: norm1, inputShape: inputTensor.shape, spec: block.attn.proj1, weights: attnProj1)
        let proj1GELU = try runner.runGELU(input: proj1.output)
        let sguConv0 = try runConvLayer(runner: runner, input: proj1GELU, inputShape: proj1.shape, spec: block.attn.sgu.conv0, weights: attnConv0)
        let sguConv0_1 = try runConvLayer(runner: runner, input: sguConv0.output, inputShape: sguConv0.shape, spec: block.attn.sgu.conv0_1, weights: attnConv0_1)
        let sguConv0_2 = try runConvLayer(runner: runner, input: sguConv0_1.output, inputShape: sguConv0_1.shape, spec: block.attn.sgu.conv0_2, weights: attnConv0_2)
        let sguConv1_1 = try runConvLayer(runner: runner, input: sguConv0.output, inputShape: sguConv0.shape, spec: block.attn.sgu.conv1_1, weights: attnConv1_1)
        let sguConv1_2 = try runConvLayer(runner: runner, input: sguConv1_1.output, inputShape: sguConv1_1.shape, spec: block.attn.sgu.conv1_2, weights: attnConv1_2)
        let sguConv2_1 = try runConvLayer(runner: runner, input: sguConv0.output, inputShape: sguConv0.shape, spec: block.attn.sgu.conv2_1, weights: attnConv2_1)
        let sguConv2_2 = try runConvLayer(runner: runner, input: sguConv2_1.output, inputShape: sguConv2_1.shape, spec: block.attn.sgu.conv2_2, weights: attnConv2_2)

        let sguSum01 = try runner.runAdd(inputA: sguConv0.output, inputB: sguConv0_2.output)
        let sguSum012 = try runner.runAdd(inputA: sguSum01, inputB: sguConv1_2.output)
        let sguSum = try runner.runAdd(inputA: sguSum012, inputB: sguConv2_2.output)
        let sguConv3 = try runConvLayer(runner: runner, input: sguSum, inputShape: sguConv0.shape, spec: block.attn.sgu.conv3, weights: attnConv3)
        let sguOutput = try runner.runMultiply(inputA: sguConv3.output, inputB: proj1GELU)
        let proj2 = try runConvLayer(runner: runner, input: sguOutput, inputShape: sguConv3.shape, spec: block.attn.proj2, weights: attnProj2)
        let attnOutput = try runner.runAdd(inputA: proj2.output, inputB: norm1)
        recordStage(name: "block1.attn_output", filename: entry.filename, actual: attnOutput, expected: attnExpected.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let afterAttn = try runner.runAddScaledChannels(
            residual: inputTensor.values,
            branch: attnOutput,
            scale: layerScale1,
            config: try tensorConfig(shape: inputTensor.shape)
        )
        recordStage(name: "block1.after_attn", filename: entry.filename, actual: afterAttn, expected: afterAttnExpected.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let norm2 = try runner.runAffine(
            input: afterAttn,
            scale: norm2Scale,
            offset: norm2Offset,
            config: try tensorConfig(shape: afterAttnExpected.shape)
        )
        recordStage(name: "block1.norm2", filename: entry.filename, actual: norm2, expected: norm2Expected.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let mlpFC1Output = try runConvLayer(runner: runner, input: norm2, inputShape: norm2Expected.shape, spec: block.mlp.fc1, weights: mlpFC1)
        let mlpDWOutput = try runConvLayer(runner: runner, input: mlpFC1Output.output, inputShape: mlpFC1Output.shape, spec: block.mlp.dwconv, weights: mlpDWConv)
        let mlpGELU = try runner.runGELU(input: mlpDWOutput.output)
        let mlpOutput = try runConvLayer(runner: runner, input: mlpGELU, inputShape: mlpDWOutput.shape, spec: block.mlp.fc2, weights: mlpFC2)
        recordStage(name: "block1.mlp_output", filename: entry.filename, actual: mlpOutput.output, expected: mlpExpected.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let final = try runner.runAddScaledChannels(
            residual: afterAttn,
            branch: mlpOutput.output,
            scale: layerScale2,
            config: try tensorConfig(shape: finalExpected.shape)
        )
        recordStage(name: "block1.final_nchw", filename: entry.filename, actual: final, expected: finalExpected.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
    }

    let frozenStages = Dictionary(uniqueKeysWithValues: stages.map { ($0.key, $0.value.frozen()) })
    let failedFixtures = Set(failures.compactMap { $0.split(separator: " ").first.map(String.init) }).count
    let summary = VerificationSummary(
        fixtureCount: manifest.entries.count,
        passedCount: manifest.entries.count - failedFixtures,
        failedCount: failedFixtures,
        maxAbsDifference: globalMaxAbs,
        maxRelativeDifference: globalMaxRelative,
        maxRMSE: globalMaxRMSE,
        stages: frozenStages,
        failures: Array(failures.prefix(25))
    )
    try writeJSON(summary, to: options.outputJSON)
    return summary
}

func verifyDecoderPreNMF(options: Options, manifest: Manifest, spec: DecoderPreNMFSpec) throws -> VerificationSummary {
    guard spec.alignCorners == false else {
        throw StemPrototypeError.invalidFixture("decoder pre-NMF verifier currently supports align_corners=false only")
    }

    let runner = try MetalConv2DRunner(metalSource: options.metalSource)
    let squeezeWeights = try loadConvWeights(spec.squeeze, fixtures: options.fixtures)

    var failures: [String] = []
    var stages: [String: MutableStageSummary] = [:]
    var globalMaxAbs: Float = 0
    var globalMaxRelative: Float = 0
    var globalMaxRMSE: Float = 0

    for entry in manifest.entries {
        var resizedInputs: [(values: [Float], shape: [Int])] = []

        for index in 0..<4 {
            let level = try readEntryTensor(entry, key: "level\(index)", fixtures: options.fixtures)
            let expectedResized = try readEntryTensor(entry, key: "resized\(index)", fixtures: options.fixtures)
            let resized = try runner.runBilinearResizeNCHW(
                input: level.values,
                inputShape: level.shape,
                outputShape: expectedResized.shape
            )
            recordStage(
                name: "decoder_pre_nmf.resized\(index)",
                filename: entry.filename,
                actual: resized,
                expected: expectedResized.values,
                options: options,
                stages: &stages,
                failures: &failures,
                globalMaxAbs: &globalMaxAbs,
                globalMaxRelative: &globalMaxRelative,
                globalMaxRMSE: &globalMaxRMSE
            )
            resizedInputs.append((values: resized, shape: expectedResized.shape))
        }

        let expectedConcat = try readEntryTensor(entry, key: "concat", fixtures: options.fixtures)
        let concat = try runner.runConcat4NCHW(inputs: resizedInputs, outputShape: expectedConcat.shape)
        recordStage(
            name: "decoder_pre_nmf.concat",
            filename: entry.filename,
            actual: concat,
            expected: expectedConcat.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )

        let squeezeConv = try runConvLayer(
            runner: runner,
            input: concat,
            inputShape: expectedConcat.shape,
            spec: spec.squeeze,
            weights: squeezeWeights
        )
        let squeeze = try runner.runReLU(input: squeezeConv.output)
        let expectedSqueeze = try readEntryTensor(entry, key: "squeeze", fixtures: options.fixtures)
        guard squeezeConv.shape == expectedSqueeze.shape else {
            throw StemPrototypeError.invalidFixture("decoder squeeze shape mismatch: \(squeezeConv.shape) vs \(expectedSqueeze.shape)")
        }
        recordStage(
            name: "decoder_pre_nmf.squeeze",
            filename: entry.filename,
            actual: squeeze,
            expected: expectedSqueeze.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )
    }

    let frozenStages = Dictionary(uniqueKeysWithValues: stages.map { ($0.key, $0.value.frozen()) })
    let failedFixtures = Set(failures.compactMap { $0.split(separator: " ").first.map(String.init) }).count
    let summary = VerificationSummary(
        fixtureCount: manifest.entries.count,
        passedCount: manifest.entries.count - failedFixtures,
        failedCount: failedFixtures,
        maxAbsDifference: globalMaxAbs,
        maxRelativeDifference: globalMaxRelative,
        maxRMSE: globalMaxRMSE,
        stages: frozenStages,
        failures: Array(failures.prefix(25))
    )
    try writeJSON(summary, to: options.outputJSON)
    return summary
}

func verifyHamburger(options: Options, manifest: Manifest, spec: HamburgerSpec) throws -> VerificationSummary {
    let runner = try MetalConv2DRunner(metalSource: options.metalSource)
    let hamInWeights = try loadConvWeights(spec.hamIn, fixtures: options.fixtures)
    let hamOutWeights = try loadConvWeights(spec.hamOut, fixtures: options.fixtures)
    let fixedBases = try readFloat32Array(
        options.fixtures.appendingPathComponent(spec.nmf.bases),
        expectedCount: product(spec.nmf.basisShape)
    )

    var failures: [String] = []
    var stages: [String: MutableStageSummary] = [:]
    var globalMaxAbs: Float = 0
    var globalMaxRelative: Float = 0
    var globalMaxRMSE: Float = 0

    for entry in manifest.entries {
        let input = try readEntryTensor(entry, key: "input", fixtures: options.fixtures)

        let hamInConv = try runConvLayer(
            runner: runner,
            input: input.values,
            inputShape: input.shape,
            spec: spec.hamIn,
            weights: hamInWeights
        )
        let hamIn = try runner.runReLU(input: hamInConv.output)
        let expectedHamIn = try readEntryTensor(entry, key: "ham_in", fixtures: options.fixtures)
        recordStage(
            name: "hamburger.ham_in",
            filename: entry.filename,
            actual: hamIn,
            expected: expectedHamIn.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )

        let nmf = try runner.runFixedNMF(
            input: hamIn,
            shape: expectedHamIn.shape,
            bases: fixedBases,
            basisShape: spec.nmf.basisShape,
            steps: spec.nmf.steps,
            epsilon: spec.nmf.epsilon,
            invT: spec.nmf.invT
        )

        let expectedNMFOutput = try readEntryTensor(entry, key: "nmf_output", fixtures: options.fixtures)
        recordStage(
            name: "hamburger.nmf_output",
            filename: entry.filename,
            actual: nmf.output,
            expected: expectedNMFOutput.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )

        let expectedNMFBases = try readEntryTensor(entry, key: "nmf_final_bases", fixtures: options.fixtures)
        recordStage(
            name: "hamburger.nmf_final_bases",
            filename: entry.filename,
            actual: nmf.finalBases,
            expected: expectedNMFBases.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )

        let expectedNMFCoef = try readEntryTensor(entry, key: "nmf_final_coef", fixtures: options.fixtures)
        recordStage(
            name: "hamburger.nmf_final_coef",
            filename: entry.filename,
            actual: nmf.finalCoef,
            expected: expectedNMFCoef.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )

        let hamOutConv = try runConvLayer(
            runner: runner,
            input: nmf.output,
            inputShape: expectedNMFOutput.shape,
            spec: spec.hamOut,
            weights: hamOutWeights
        )
        let hamOut = try runner.runReLU(input: hamOutConv.output)
        let expectedHamOut = try readEntryTensor(entry, key: "ham_out", fixtures: options.fixtures)
        recordStage(
            name: "hamburger.ham_out",
            filename: entry.filename,
            actual: hamOut,
            expected: expectedHamOut.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )

        let residual = try runner.runAdd(inputA: input.values, inputB: hamOut)
        let hamburger = try runner.runReLU(input: residual)
        let expectedHamburger = try readEntryTensor(entry, key: "hamburger", fixtures: options.fixtures)
        recordStage(
            name: "hamburger.final",
            filename: entry.filename,
            actual: hamburger,
            expected: expectedHamburger.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )
    }

    let frozenStages = Dictionary(uniqueKeysWithValues: stages.map { ($0.key, $0.value.frozen()) })
    let failedFixtures = Set(failures.compactMap { $0.split(separator: " ").first.map(String.init) }).count
    let summary = VerificationSummary(
        fixtureCount: manifest.entries.count,
        passedCount: manifest.entries.count - failedFixtures,
        failedCount: failedFixtures,
        maxAbsDifference: globalMaxAbs,
        maxRelativeDifference: globalMaxRelative,
        maxRMSE: globalMaxRMSE,
        stages: frozenStages,
        failures: Array(failures.prefix(25))
    )
    try writeJSON(summary, to: options.outputJSON)
    return summary
}

func verifyDecoderOutput(options: Options, manifest: Manifest, spec: DecoderOutputSpec) throws -> VerificationSummary {
    let runner = try MetalConv2DRunner(metalSource: options.metalSource)
    let alignWeights = try loadConvWeights(spec.align, fixtures: options.fixtures)
    let outConvWeights = try loadConvWeights(spec.outConv, fixtures: options.fixtures)
    let fusionUnit1 = try loadResidualConvUnit(spec.fusion.resConfUnit1, fixtures: options.fixtures)
    let fusionUnit2 = try loadResidualConvUnit(spec.fusion.resConfUnit2, fixtures: options.fixtures)
    let uncertaintyHiddenWeights = try loadConvWeights(spec.uncertainty.hidden, fixtures: options.fixtures)
    let uncertaintyLinearWeights = try loadConvWeights(spec.uncertainty.linear, fixtures: options.fixtures)
    let linearPredUpWeights = try spec.linearPredUp.map { try loadConvWeights($0, fixtures: options.fixtures) }
    let linearPredLatitudeWeights = try spec.linearPredLatitude.map { try loadConvWeights($0, fixtures: options.fixtures) }

    var failures: [String] = []
    var stages: [String: MutableStageSummary] = [:]
    var globalMaxAbs: Float = 0
    var globalMaxRelative: Float = 0
    var globalMaxRMSE: Float = 0

    for entry in manifest.entries {
        let input = try readEntryTensor(entry, key: "input", fixtures: options.fixtures)
        let ll = try readEntryTensor(entry, key: "ll", fixtures: options.fixtures)

        let align = try runConvModule(
            runner: runner,
            input: input.values,
            inputShape: input.shape,
            spec: spec.align,
            weights: alignWeights
        )
        let expectedAlign = try readEntryTensor(entry, key: "align", fixtures: options.fixtures)
        recordStage(name: "decoder_output.align", filename: entry.filename, actual: align.output, expected: expectedAlign.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let expectedAlignUp = try readEntryTensor(entry, key: "align_up", fixtures: options.fixtures)
        let alignUp = try runner.runBilinearResizeNCHW(
            input: align.output,
            inputShape: align.shape,
            outputShape: expectedAlignUp.shape
        )
        recordStage(name: "decoder_output.align_up", filename: entry.filename, actual: alignUp, expected: expectedAlignUp.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let outConv = try runConvModule(
            runner: runner,
            input: alignUp,
            inputShape: expectedAlignUp.shape,
            spec: spec.outConv,
            weights: outConvWeights
        )
        let expectedOutConv = try readEntryTensor(entry, key: "out_conv", fixtures: options.fixtures)
        recordStage(name: "decoder_output.out_conv", filename: entry.filename, actual: outConv.output, expected: expectedOutConv.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let expectedOutUp = try readEntryTensor(entry, key: "out_up", fixtures: options.fixtures)
        let outUp = try runner.runBilinearResizeNCHW(
            input: outConv.output,
            inputShape: outConv.shape,
            outputShape: expectedOutUp.shape
        )
        recordStage(name: "decoder_output.out_up", filename: entry.filename, actual: outUp, expected: expectedOutUp.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let llResidual = try runResidualConvUnit(
            runner: runner,
            input: ll.values,
            inputShape: ll.shape,
            unit: fusionUnit1
        )
        let expectedLLRes1Conv1 = try readEntryTensor(entry, key: "ll_res1_conv1", fixtures: options.fixtures)
        recordStage(name: "decoder_output.ll_res1_conv1", filename: entry.filename, actual: llResidual.conv1, expected: expectedLLRes1Conv1.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
        let expectedLLResidualConv2 = try readEntryTensor(entry, key: "ll_residual_conv2", fixtures: options.fixtures)
        recordStage(name: "decoder_output.ll_residual_conv2", filename: entry.filename, actual: llResidual.conv2, expected: expectedLLResidualConv2.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
        let expectedLLResidual = try readEntryTensor(entry, key: "ll_residual", fixtures: options.fixtures)
        recordStage(name: "decoder_output.ll_residual", filename: entry.filename, actual: llResidual.output, expected: expectedLLResidual.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let fusionSum = try runner.runAdd(inputA: outUp, inputB: llResidual.output)
        let expectedFusionSum = try readEntryTensor(entry, key: "fusion_sum", fixtures: options.fixtures)
        recordStage(name: "decoder_output.fusion_sum", filename: entry.filename, actual: fusionSum, expected: expectedFusionSum.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let fusion = try runResidualConvUnit(
            runner: runner,
            input: fusionSum,
            inputShape: expectedFusionSum.shape,
            unit: fusionUnit2
        )
        let expectedFusionConv1 = try readEntryTensor(entry, key: "fusion_conv1", fixtures: options.fixtures)
        recordStage(name: "decoder_output.fusion_conv1", filename: entry.filename, actual: fusion.conv1, expected: expectedFusionConv1.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
        let expectedFusionConv2 = try readEntryTensor(entry, key: "fusion_conv2", fixtures: options.fixtures)
        recordStage(name: "decoder_output.fusion_conv2", filename: entry.filename, actual: fusion.conv2, expected: expectedFusionConv2.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
        let expectedFusion = try readEntryTensor(entry, key: "fusion", fixtures: options.fixtures)
        recordStage(name: "decoder_output.fusion", filename: entry.filename, actual: fusion.output, expected: expectedFusion.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let uncertaintyHidden = try runConvModule(
            runner: runner,
            input: fusion.output,
            inputShape: fusion.shape,
            spec: spec.uncertainty.hidden,
            weights: uncertaintyHiddenWeights
        )
        let expectedUncertaintyHidden = try readEntryTensor(entry, key: "uncertainty_hidden", fixtures: options.fixtures)
        recordStage(name: "decoder_output.uncertainty_hidden", filename: entry.filename, actual: uncertaintyHidden.output, expected: expectedUncertaintyHidden.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let logUncertainty = try runConvLayer(
            runner: runner,
            input: uncertaintyHidden.output,
            inputShape: uncertaintyHidden.shape,
            spec: spec.uncertainty.linear,
            weights: uncertaintyLinearWeights
        )
        let expectedLogUncertainty = try readEntryTensor(entry, key: "log_uncertainty", fixtures: options.fixtures)
        recordStage(name: "decoder_output.log_uncertainty", filename: entry.filename, actual: logUncertainty.output, expected: expectedLogUncertainty.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let confidence = try runner.runSigmoid(input: logUncertainty.output)
        let expectedConfidence = try readEntryTensor(entry, key: "confidence", fixtures: options.fixtures)
        recordStage(name: "decoder_output.confidence", filename: entry.filename, actual: confidence, expected: expectedConfidence.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        switch spec.head {
        case "up":
            guard let linearPredUp = spec.linearPredUp,
                  let linearPredUpWeights
            else {
                throw StemPrototypeError.invalidFixture("up decoder output manifest missing linear_pred_up")
            }
            let upLogits = try runConvLayer(
                runner: runner,
                input: fusion.output,
                inputShape: fusion.shape,
                spec: linearPredUp,
                weights: linearPredUpWeights
            )
            let expectedUpLogits = try readEntryTensor(entry, key: "up_logits", fixtures: options.fixtures)
            recordStage(name: "decoder_output.up_logits", filename: entry.filename, actual: upLogits.output, expected: expectedUpLogits.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

            let upField = try runner.runNormalize2ChannelsNCHW(input: upLogits.output, shape: upLogits.shape)
            let expectedUpField = try readEntryTensor(entry, key: "up_field", fixtures: options.fixtures)
            recordStage(name: "decoder_output.up_field", filename: entry.filename, actual: upField, expected: expectedUpField.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
        case "latitude":
            guard let linearPredLatitude = spec.linearPredLatitude,
                  let linearPredLatitudeWeights
            else {
                throw StemPrototypeError.invalidFixture("latitude decoder output manifest missing linear_pred_latitude")
            }
            let latitudeLogits = try runConvLayer(
                runner: runner,
                input: fusion.output,
                inputShape: fusion.shape,
                spec: linearPredLatitude,
                weights: linearPredLatitudeWeights
            )
            let expectedLatitudeLogits = try readEntryTensor(entry, key: "latitude_logits", fixtures: options.fixtures)
            recordStage(name: "decoder_output.latitude_logits", filename: entry.filename, actual: latitudeLogits.output, expected: expectedLatitudeLogits.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

            let latitudeField = try runner.runLatitudeField(input: latitudeLogits.output)
            let expectedLatitudeField = try readEntryTensor(entry, key: "latitude_field", fixtures: options.fixtures)
            recordStage(name: "decoder_output.latitude_field", filename: entry.filename, actual: latitudeField, expected: expectedLatitudeField.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
        default:
            throw StemPrototypeError.invalidFixture("unsupported decoder output head \(spec.head)")
        }
    }

    let frozenStages = Dictionary(uniqueKeysWithValues: stages.map { ($0.key, $0.value.frozen()) })
    let failedFixtures = Set(failures.compactMap { $0.split(separator: " ").first.map(String.init) }).count
    let summary = VerificationSummary(
        fixtureCount: manifest.entries.count,
        passedCount: manifest.entries.count - failedFixtures,
        failedCount: failedFixtures,
        maxAbsDifference: globalMaxAbs,
        maxRelativeDifference: globalMaxRelative,
        maxRMSE: globalMaxRMSE,
        stages: frozenStages,
        failures: Array(failures.prefix(25))
    )
    try writeJSON(summary, to: options.outputJSON)
    return summary
}

func verifyLowLevelEncoder(options: Options, manifest: Manifest, spec: LowLevelEncoderSpec) throws -> VerificationSummary {
    let runner = try MetalConv2DRunner(metalSource: options.metalSource)
    let conv1Weights = try loadConvWeights(spec.conv1, fixtures: options.fixtures)
    let conv2Weights = try loadConvWeights(spec.conv2, fixtures: options.fixtures)

    var failures: [String] = []
    var stages: [String: MutableStageSummary] = [:]
    var globalMaxAbs: Float = 0
    var globalMaxRelative: Float = 0
    var globalMaxRMSE: Float = 0

    for entry in manifest.entries {
        let input = try readEntryTensor(entry, key: "input", fixtures: options.fixtures)
        let conv1 = try runConvModule(
            runner: runner,
            input: input.values,
            inputShape: input.shape,
            spec: spec.conv1,
            weights: conv1Weights
        )
        let expectedConv1 = try readEntryTensor(entry, key: "conv1", fixtures: options.fixtures)
        recordStage(
            name: "low_level.conv1",
            filename: entry.filename,
            actual: conv1.output,
            expected: expectedConv1.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )

        let features = try runConvModule(
            runner: runner,
            input: conv1.output,
            inputShape: conv1.shape,
            spec: spec.conv2,
            weights: conv2Weights
        )
        let expectedFeatures = try readEntryTensor(entry, key: "features", fixtures: options.fixtures)
        recordStage(
            name: "low_level.features",
            filename: entry.filename,
            actual: features.output,
            expected: expectedFeatures.values,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )
    }

    let frozenStages = Dictionary(uniqueKeysWithValues: stages.map { ($0.key, $0.value.frozen()) })
    let failedFixtures = Set(failures.compactMap { $0.split(separator: " ").first.map(String.init) }).count
    let summary = VerificationSummary(
        fixtureCount: manifest.entries.count,
        passedCount: manifest.entries.count - failedFixtures,
        failedCount: failedFixtures,
        maxAbsDifference: globalMaxAbs,
        maxRelativeDifference: globalMaxRelative,
        maxRMSE: globalMaxRMSE,
        stages: frozenStages,
        failures: Array(failures.prefix(25))
    )
    try writeJSON(summary, to: options.outputJSON)
    return summary
}

func verifyNeuralForward(options: Options, manifest: Manifest, spec: NeuralForwardSpec) throws -> VerificationSummary {
    let runner = try MetalConv2DRunner(metalSource: options.metalSource)
    let stem = try loadStem(spec.stem, fixtures: options.fixtures)
    let stage1 = try loadStage(
        patchEmbed: nil,
        blocks: spec.stage1.blocks,
        norm: spec.stage1.norm,
        fixtures: options.fixtures
    )
    let stage2 = try loadStage(
        patchEmbed: spec.stage2.patchEmbed,
        blocks: spec.stage2.blocks,
        norm: spec.stage2.norm,
        fixtures: options.fixtures
    )
    let stage3 = try loadStage(
        patchEmbed: spec.stage3.patchEmbed,
        blocks: spec.stage3.blocks,
        norm: spec.stage3.norm,
        fixtures: options.fixtures
    )
    let stage4 = try loadStage(
        patchEmbed: spec.stage4.patchEmbed,
        blocks: spec.stage4.blocks,
        norm: spec.stage4.norm,
        fixtures: options.fixtures
    )
    let lowLevelEncoder = try loadLowLevelEncoder(spec.lowLevelEncoder, fixtures: options.fixtures)
    let upHead = try loadFullHead(spec.upHead, fixtures: options.fixtures)
    let latitudeHead = try loadFullHead(spec.latitudeHead, fixtures: options.fixtures)

    var failures: [String] = []
    var stages: [String: MutableStageSummary] = [:]
    var globalMaxAbs: Float = 0
    var globalMaxRelative: Float = 0
    var globalMaxRMSE: Float = 0

    for entry in manifest.entries {
        let inputRGB = try readEntryTensor(entry, key: "input_rgb", fixtures: options.fixtures)
        let inputBGR255 = try rgbToBGR255(inputRGB.values, shape: inputRGB.shape)

        let stemOutput = try runStem(
            runner: runner,
            inputBGR255: inputBGR255,
            inputShape: inputRGB.shape,
            stem: stem
        )
        let stage1Output = try runStageForward(
            runner: runner,
            input: stemOutput.output,
            inputShape: stemOutput.shape,
            stage: stage1
        )
        let expectedStage1 = try readEntryTensor(entry, key: "stage1", fixtures: options.fixtures)
        recordStage(name: "neural.stage1", filename: entry.filename, actual: stage1Output.output, expected: expectedStage1.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let stage2Output = try runStageForward(
            runner: runner,
            input: stage1Output.output,
            inputShape: stage1Output.shape,
            stage: stage2
        )
        let expectedStage2 = try readEntryTensor(entry, key: "stage2", fixtures: options.fixtures)
        recordStage(name: "neural.stage2", filename: entry.filename, actual: stage2Output.output, expected: expectedStage2.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let stage3Output = try runStageForward(
            runner: runner,
            input: stage2Output.output,
            inputShape: stage2Output.shape,
            stage: stage3
        )
        let expectedStage3 = try readEntryTensor(entry, key: "stage3", fixtures: options.fixtures)
        recordStage(name: "neural.stage3", filename: entry.filename, actual: stage3Output.output, expected: expectedStage3.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let stage4Output = try runStageForward(
            runner: runner,
            input: stage3Output.output,
            inputShape: stage3Output.shape,
            stage: stage4
        )
        let expectedStage4 = try readEntryTensor(entry, key: "stage4", fixtures: options.fixtures)
        recordStage(name: "neural.stage4", filename: entry.filename, actual: stage4Output.output, expected: expectedStage4.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let lowLevel = try runLowLevelEncoder(
            runner: runner,
            input: inputRGB.values,
            inputShape: inputRGB.shape,
            encoder: lowLevelEncoder
        )
        let expectedLowLevel = try readEntryTensor(entry, key: "low_level", fixtures: options.fixtures)
        recordStage(name: "neural.low_level", filename: entry.filename, actual: lowLevel.output, expected: expectedLowLevel.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let levels = [
            (values: stage1Output.output, shape: stage1Output.shape),
            (values: stage2Output.output, shape: stage2Output.shape),
            (values: stage3Output.output, shape: stage3Output.shape),
            (values: stage4Output.output, shape: stage4Output.shape),
        ]
        let lowLevelTensor = (values: lowLevel.output, shape: lowLevel.shape)

        let up = try runFullHead(runner: runner, levels: levels, lowLevel: lowLevelTensor, head: upHead)
        let expectedUpField = try readEntryTensor(entry, key: "up_field", fixtures: options.fixtures)
        recordStage(name: "neural.up_field", filename: entry.filename, actual: up.field, expected: expectedUpField.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
        let expectedUpConfidence = try readEntryTensor(entry, key: "up_confidence", fixtures: options.fixtures)
        recordStage(name: "neural.up_confidence", filename: entry.filename, actual: up.confidence, expected: expectedUpConfidence.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)

        let latitude = try runFullHead(runner: runner, levels: levels, lowLevel: lowLevelTensor, head: latitudeHead)
        let expectedLatitudeField = try readEntryTensor(entry, key: "latitude_field", fixtures: options.fixtures)
        recordStage(name: "neural.latitude_field", filename: entry.filename, actual: latitude.field, expected: expectedLatitudeField.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
        let expectedLatitudeConfidence = try readEntryTensor(entry, key: "latitude_confidence", fixtures: options.fixtures)
        recordStage(name: "neural.latitude_confidence", filename: entry.filename, actual: latitude.confidence, expected: expectedLatitudeConfidence.values, options: options, stages: &stages, failures: &failures, globalMaxAbs: &globalMaxAbs, globalMaxRelative: &globalMaxRelative, globalMaxRMSE: &globalMaxRMSE)
    }

    let frozenStages = Dictionary(uniqueKeysWithValues: stages.map { ($0.key, $0.value.frozen()) })
    let failedFixtures = Set(failures.compactMap { $0.split(separator: " ").first.map(String.init) }).count
    let summary = VerificationSummary(
        fixtureCount: manifest.entries.count,
        passedCount: manifest.entries.count - failedFixtures,
        failedCount: failedFixtures,
        maxAbsDifference: globalMaxAbs,
        maxRelativeDifference: globalMaxRelative,
        maxRMSE: globalMaxRMSE,
        stages: frozenStages,
        failures: Array(failures.prefix(25))
    )
    try writeJSON(summary, to: options.outputJSON)
    return summary
}

func verify(options: Options) throws -> VerificationSummary {
    let manifestURL = options.fixtures.appendingPathComponent("manifest.json")
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    if let neuralForward = manifest.neuralForward {
        return try verifyNeuralForward(options: options, manifest: manifest, spec: neuralForward)
    }
    if let lowLevelEncoder = manifest.lowLevelEncoder {
        return try verifyLowLevelEncoder(options: options, manifest: manifest, spec: lowLevelEncoder)
    }
    if let decoderOutput = manifest.decoderOutput {
        return try verifyDecoderOutput(options: options, manifest: manifest, spec: decoderOutput)
    }
    if let hamburger = manifest.hamburger {
        return try verifyHamburger(options: options, manifest: manifest, spec: hamburger)
    }
    if let decoderPreNMF = manifest.decoderPreNMF {
        return try verifyDecoderPreNMF(options: options, manifest: manifest, spec: decoderPreNMF)
    }
    if let stage = manifest.stage1 {
        return try verifyStage1(options: options, manifest: manifest, stage: stage)
    }
    if let stage = manifest.stage2 {
        return try verifyStage(
            options: options,
            manifest: manifest,
            stageName: "stage2",
            patchEmbed: stage.patchEmbed,
            blocks: stage.blocks,
            norm: stage.norm
        )
    }
    if let stage = manifest.stage3 {
        return try verifyStage(
            options: options,
            manifest: manifest,
            stageName: "stage3",
            patchEmbed: stage.patchEmbed,
            blocks: stage.blocks,
            norm: stage.norm
        )
    }
    if let stage = manifest.stage4 {
        return try verifyStage(
            options: options,
            manifest: manifest,
            stageName: "stage4",
            patchEmbed: stage.patchEmbed,
            blocks: stage.blocks,
            norm: stage.norm
        )
    }
    if let block = manifest.block1 {
        return try verifyBlock1(options: options, manifest: manifest, block: block)
    }
    guard let topConv = manifest.conv,
          let topWeights = manifest.weights
    else {
        throw StemPrototypeError.invalidFixture("expected either block1 or top-level conv/weights manifest")
    }
    guard topConv.dilation == [1, 1] else {
        throw StemPrototypeError.invalidFixture("dilated conv is not supported by this prototype")
    }

    let runner = try MetalConv2DRunner(metalSource: options.metalSource)
    var failures: [String] = []
    var stages: [String: MutableStageSummary] = [:]
    var globalMaxAbs: Float = 0
    var globalMaxRelative: Float = 0
    var globalMaxRMSE: Float = 0

    let conv0Spec = manifest.stem?.conv0 ?? ConvLayerSpec(
        weight: topWeights.weight,
        bias: topWeights.bias,
        weightShape: topWeights.weightShape,
        biasShape: topWeights.biasShape,
        padding: topConv.padding,
        stride: topConv.stride,
        dilation: topConv.dilation,
        groups: topConv.groups
    )
    let conv0Weight = try readFloat32Array(
        options.fixtures.appendingPathComponent(conv0Spec.weight),
        expectedCount: product(conv0Spec.weightShape)
    )
    let conv0Bias = try readFloat32Array(
        options.fixtures.appendingPathComponent(conv0Spec.bias),
        expectedCount: product(conv0Spec.biasShape)
    )

    let conv3Weight: [Float]?
    let conv3Bias: [Float]?
    let bn1Scale: [Float]?
    let bn1Offset: [Float]?
    let bn4Scale: [Float]?
    let bn4Offset: [Float]?
    if let stem = manifest.stem {
        conv3Weight = try readFloat32Array(
            options.fixtures.appendingPathComponent(stem.conv3.weight),
            expectedCount: product(stem.conv3.weightShape)
        )
        conv3Bias = try readFloat32Array(
            options.fixtures.appendingPathComponent(stem.conv3.bias),
            expectedCount: product(stem.conv3.biasShape)
        )
        bn1Scale = try readFloat32Array(
            options.fixtures.appendingPathComponent(stem.bn1.scale),
            expectedCount: product(stem.bn1.shape)
        )
        bn1Offset = try readFloat32Array(
            options.fixtures.appendingPathComponent(stem.bn1.offset),
            expectedCount: product(stem.bn1.shape)
        )
        bn4Scale = try readFloat32Array(
            options.fixtures.appendingPathComponent(stem.bn4.scale),
            expectedCount: product(stem.bn4.shape)
        )
        bn4Offset = try readFloat32Array(
            options.fixtures.appendingPathComponent(stem.bn4.offset),
            expectedCount: product(stem.bn4.shape)
        )
    } else {
        conv3Weight = nil
        conv3Bias = nil
        bn1Scale = nil
        bn1Offset = nil
        bn4Scale = nil
        bn4Offset = nil
    }

    for entry in manifest.entries {
        guard let entryInputShape = entry.inputShape,
              let entryExpectedShape = entry.expectedShape,
              let entryInput = entry.input,
              let entryExpected = entry.expected,
              entryInputShape.count == 4,
              entryExpectedShape.count == 4
        else {
            throw StemPrototypeError.invalidFixture("expected 4D NCHW shapes for \(entry.filename)")
        }
        let input = try readFloat32Array(
            options.fixtures.appendingPathComponent(entryInput),
            expectedCount: product(entryInputShape)
        )
        let expected = try readFloat32Array(
            options.fixtures.appendingPathComponent(entryExpected),
            expectedCount: product(entryExpectedShape)
        )
        let conv0Config = try convConfig(
            inputShape: entryInputShape,
            outputShape: entryExpectedShape,
            weightShape: conv0Spec.weightShape,
            stride: conv0Spec.stride,
            padding: conv0Spec.padding,
            groups: conv0Spec.groups ?? (manifest.stem == nil ? topConv.groups : 1)
        )

        let conv0 = try runner.runConv2D(input: input, weight: conv0Weight, bias: conv0Bias, config: conv0Config)
        recordStage(
            name: "conv0",
            filename: entry.filename,
            actual: conv0,
            expected: expected,
            options: options,
            stages: &stages,
            failures: &failures,
            globalMaxAbs: &globalMaxAbs,
            globalMaxRelative: &globalMaxRelative,
            globalMaxRMSE: &globalMaxRMSE
        )

        if let stem = manifest.stem,
           let bn1ExpectedName = entry.bn1Expected,
           let bn1Shape = entry.bn1Shape,
           let geluExpectedName = entry.geluExpected,
           let geluShape = entry.geluShape,
           let conv3ExpectedName = entry.conv3Expected,
           let conv3Shape = entry.conv3Shape,
           let bn4ExpectedName = entry.bn4Expected,
           let bn4Shape = entry.bn4Shape,
           let bn1Scale,
           let bn1Offset,
           let conv3Weight,
           let conv3Bias,
           let bn4Scale,
           let bn4Offset {
            let bn1Expected = try readFloat32Array(
                options.fixtures.appendingPathComponent(bn1ExpectedName),
                expectedCount: product(bn1Shape)
            )
            let bn1 = try runner.runAffine(
                input: conv0,
                scale: bn1Scale,
                offset: bn1Offset,
                config: try tensorConfig(shape: bn1Shape)
            )
            recordStage(
                name: "bn1",
                filename: entry.filename,
                actual: bn1,
                expected: bn1Expected,
                options: options,
                stages: &stages,
                failures: &failures,
                globalMaxAbs: &globalMaxAbs,
                globalMaxRelative: &globalMaxRelative,
                globalMaxRMSE: &globalMaxRMSE
            )

            let geluExpected = try readFloat32Array(
                options.fixtures.appendingPathComponent(geluExpectedName),
                expectedCount: product(geluShape)
            )
            let gelu = try runner.runGELU(input: bn1)
            recordStage(
                name: "gelu",
                filename: entry.filename,
                actual: gelu,
                expected: geluExpected,
                options: options,
                stages: &stages,
                failures: &failures,
                globalMaxAbs: &globalMaxAbs,
                globalMaxRelative: &globalMaxRelative,
                globalMaxRMSE: &globalMaxRMSE
            )

            let conv3Expected = try readFloat32Array(
                options.fixtures.appendingPathComponent(conv3ExpectedName),
                expectedCount: product(conv3Shape)
            )
            let conv3 = try runner.runConv2D(
                input: gelu,
                weight: conv3Weight,
                bias: conv3Bias,
                config: try convConfig(
                    inputShape: geluShape,
                    outputShape: conv3Shape,
                    weightShape: stem.conv3.weightShape,
                    stride: stem.conv3.stride,
                    padding: stem.conv3.padding,
                    groups: 1
                )
            )
            recordStage(
                name: "conv3",
                filename: entry.filename,
                actual: conv3,
                expected: conv3Expected,
                options: options,
                stages: &stages,
                failures: &failures,
                globalMaxAbs: &globalMaxAbs,
                globalMaxRelative: &globalMaxRelative,
                globalMaxRMSE: &globalMaxRMSE
            )

            let bn4Expected = try readFloat32Array(
                options.fixtures.appendingPathComponent(bn4ExpectedName),
                expectedCount: product(bn4Shape)
            )
            let bn4 = try runner.runAffine(
                input: conv3,
                scale: bn4Scale,
                offset: bn4Offset,
                config: try tensorConfig(shape: bn4Shape)
            )
            recordStage(
                name: "bn4",
                filename: entry.filename,
                actual: bn4,
                expected: bn4Expected,
                options: options,
                stages: &stages,
                failures: &failures,
                globalMaxAbs: &globalMaxAbs,
                globalMaxRelative: &globalMaxRelative,
                globalMaxRMSE: &globalMaxRMSE
            )
        }
    }

    let frozenStages = Dictionary(uniqueKeysWithValues: stages.map { ($0.key, $0.value.frozen()) })
    let failedFixtures = Set(failures.compactMap { $0.split(separator: " ").first.map(String.init) }).count

    let summary = VerificationSummary(
        fixtureCount: manifest.entries.count,
        passedCount: manifest.entries.count - failedFixtures,
        failedCount: failedFixtures,
        maxAbsDifference: globalMaxAbs,
        maxRelativeDifference: globalMaxRelative,
        maxRMSE: globalMaxRMSE,
        stages: frozenStages,
        failures: Array(failures.prefix(25))
    )
    try writeJSON(summary, to: options.outputJSON)
    return summary
}
