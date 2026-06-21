//
//  AnyUprightGeoCalibRuntimeBundle.swift
//  AnyUpright
//

import Foundation

enum AUGeoCalibRuntimeBundleError: Error, CustomStringConvertible {
    case missingManifest(URL)
    case invalidManifest(String)
    case missingTensor(URL)
    case unreadableTensor(URL)

    var description: String {
        switch self {
        case .missingManifest(let url):
            return "Missing GeoCalib runtime manifest at \(url.path)"
        case .invalidManifest(let message):
            return "Invalid GeoCalib runtime manifest: \(message)"
        case .missingTensor(let url):
            return "Missing GeoCalib runtime tensor at \(url.path)"
        case .unreadableTensor(let url):
            return "Unreadable GeoCalib runtime tensor at \(url.path)"
        }
    }
}

struct AUGeoCalibRuntimeManifest: Decodable {
    var description: String
    var runtimeFileCount: Int
    var neuralForward: NeuralForwardSpec

    enum CodingKeys: String, CodingKey {
        case description
        case runtimeFileCount = "runtime_file_count"
        case neuralForward = "neural_forward"
    }
}

struct AUGeoCalibRuntimeBundle {
    let rootURL: URL
    let manifest: AUGeoCalibRuntimeManifest
    let runtimeTensorPaths: [String]

    init(rootURL: URL) throws {
        self.rootURL = rootURL
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw AUGeoCalibRuntimeBundleError.missingManifest(manifestURL)
        }

        let data = try Data(contentsOf: manifestURL)
        manifest = try JSONDecoder().decode(AUGeoCalibRuntimeManifest.self, from: data)
        runtimeTensorPaths = try Self.tensorPaths(inManifestData: data)

        guard runtimeTensorPaths.count == manifest.runtimeFileCount else {
            throw AUGeoCalibRuntimeBundleError.invalidManifest(
                "manifest declares \(manifest.runtimeFileCount) tensors but references \(runtimeTensorPaths.count)"
            )
        }
    }

    func validateRuntimeTensors(readContents: Bool = false) throws -> Int {
        var totalBytes = 0
        for relativePath in runtimeTensorPaths {
            let url = rootURL.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AUGeoCalibRuntimeBundleError.missingTensor(url)
            }
            if readContents {
                do {
                    let data = try Data(contentsOf: url)
                    totalBytes += data.count
                } catch {
                    throw AUGeoCalibRuntimeBundleError.unreadableTensor(url)
                }
            }
        }
        return totalBytes
    }

    private static func tensorPaths(inManifestData data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let neuralForward = root["neural_forward"] else {
            throw AUGeoCalibRuntimeBundleError.invalidManifest("missing neural_forward")
        }
        return Array(referencedTensorPaths(in: neuralForward)).sorted()
    }

    private static func referencedTensorPaths(in value: Any) -> Set<String> {
        if let string = value as? String, string.hasSuffix(".f32") {
            return [string]
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { result, child in
                result.formUnion(referencedTensorPaths(in: child))
            }
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.reduce(into: Set<String>()) { result, child in
                result.formUnion(referencedTensorPaths(in: child))
            }
        }
        return []
    }
}

struct AUGeoCalibNeuralOutput {
    var upField: [Float]
    var upConfidence: [Float]
    var latitudeField: [Float]
    var latitudeConfidence: [Float]
    var fieldShape: [Int]
    var confidenceShape: [Int]
}

enum AUGeoCalibNeuralInference {
    static func run(
        inputRGB: [Float],
        inputShape: [Int],
        runtimeBundle: AUGeoCalibRuntimeBundle,
        metalSource: URL
    ) throws -> AUGeoCalibNeuralOutput {
        let session = try AUGeoCalibNeuralInferenceSession(runtimeBundle: runtimeBundle, metalSource: metalSource)
        return try session.run(inputRGB: inputRGB, inputShape: inputShape)
    }

    static func run(
        inputRGB: [Float],
        inputShape: [Int],
        runtimeBundle: AUGeoCalibRuntimeBundle,
        metalLibraryURL: URL
    ) throws -> AUGeoCalibNeuralOutput {
        let session = try AUGeoCalibNeuralInferenceSession(runtimeBundle: runtimeBundle, metalLibraryURL: metalLibraryURL)
        return try session.run(inputRGB: inputRGB, inputShape: inputShape)
    }
}

struct AUGeoCalibNeuralInferenceSession {
    private let runner: MetalConv2DRunner
    private let stem: LoadedStem
    private let stage1: LoadedStage
    private let stage2: LoadedStage
    private let stage3: LoadedStage
    private let stage4: LoadedStage
    private let lowLevelEncoder: LoadedLowLevelEncoder
    private let upHead: LoadedFullHead
    private let latitudeHead: LoadedFullHead

    init(runtimeBundle: AUGeoCalibRuntimeBundle, metalSource: URL) throws {
        try self.init(
            runtimeBundle: runtimeBundle,
            runner: try MetalConv2DRunner(metalSource: metalSource)
        )
    }

    init(runtimeBundle: AUGeoCalibRuntimeBundle, metalLibraryURL: URL) throws {
        try self.init(
            runtimeBundle: runtimeBundle,
            runner: try MetalConv2DRunner(metalLibraryURL: metalLibraryURL)
        )
    }

    private init(runtimeBundle: AUGeoCalibRuntimeBundle, runner: MetalConv2DRunner) throws {
        self.runner = runner
        let spec = runtimeBundle.manifest.neuralForward
        let fixtures = runtimeBundle.rootURL

        stem = try loadStem(spec.stem, fixtures: fixtures)
        stage1 = try loadStage(
            patchEmbed: nil,
            blocks: spec.stage1.blocks,
            norm: spec.stage1.norm,
            fixtures: fixtures
        )
        stage2 = try loadStage(
            patchEmbed: spec.stage2.patchEmbed,
            blocks: spec.stage2.blocks,
            norm: spec.stage2.norm,
            fixtures: fixtures
        )
        stage3 = try loadStage(
            patchEmbed: spec.stage3.patchEmbed,
            blocks: spec.stage3.blocks,
            norm: spec.stage3.norm,
            fixtures: fixtures
        )
        stage4 = try loadStage(
            patchEmbed: spec.stage4.patchEmbed,
            blocks: spec.stage4.blocks,
            norm: spec.stage4.norm,
            fixtures: fixtures
        )
        lowLevelEncoder = try loadLowLevelEncoder(spec.lowLevelEncoder, fixtures: fixtures)
        upHead = try loadFullHead(spec.upHead, fixtures: fixtures)
        latitudeHead = try loadFullHead(spec.latitudeHead, fixtures: fixtures)
    }

    func run(
        inputRGB: [Float],
        inputShape: [Int]
    ) throws -> AUGeoCalibNeuralOutput {
        let inputBGR255 = try rgbToBGR255(inputRGB, shape: inputShape)
        let stemOutput = try runStem(
            runner: runner,
            inputBGR255: inputBGR255,
            inputShape: inputShape,
            stem: stem
        )
        let stage1Output = try runStageForward(
            runner: runner,
            input: stemOutput.output,
            inputShape: stemOutput.shape,
            stage: stage1
        )
        let stage2Output = try runStageForward(
            runner: runner,
            input: stage1Output.output,
            inputShape: stage1Output.shape,
            stage: stage2
        )
        let stage3Output = try runStageForward(
            runner: runner,
            input: stage2Output.output,
            inputShape: stage2Output.shape,
            stage: stage3
        )
        let stage4Output = try runStageForward(
            runner: runner,
            input: stage3Output.output,
            inputShape: stage3Output.shape,
            stage: stage4
        )
        let lowLevel = try runLowLevelEncoder(
            runner: runner,
            input: inputRGB,
            inputShape: inputShape,
            encoder: lowLevelEncoder
        )
        let levels = [
            (values: stage1Output.output, shape: stage1Output.shape),
            (values: stage2Output.output, shape: stage2Output.shape),
            (values: stage3Output.output, shape: stage3Output.shape),
            (values: stage4Output.output, shape: stage4Output.shape),
        ]
        let lowLevelTensor = (values: lowLevel.output, shape: lowLevel.shape)
        let up = try runFullHead(runner: runner, levels: levels, lowLevel: lowLevelTensor, head: upHead)
        let latitude = try runFullHead(runner: runner, levels: levels, lowLevel: lowLevelTensor, head: latitudeHead)

        guard up.fieldShape.count == 4,
              latitude.fieldShape.count == 4,
              up.fieldShape[0] == latitude.fieldShape[0],
              up.fieldShape[2] == latitude.fieldShape[2],
              up.fieldShape[3] == latitude.fieldShape[3],
              up.confidenceShape == latitude.confidenceShape else {
            throw AUGeoCalibRuntimeBundleError.invalidManifest("up and latitude output shapes do not match")
        }

        return AUGeoCalibNeuralOutput(
            upField: up.field,
            upConfidence: up.confidence,
            latitudeField: latitude.field,
            latitudeConfidence: latitude.confidence,
            fieldShape: up.fieldShape,
            confidenceShape: up.confidenceShape
        )
    }
}
