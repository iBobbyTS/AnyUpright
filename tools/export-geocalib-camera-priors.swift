//
//  export-geocalib-camera-priors.swift
//  AnyUpright
//

import CoreML
import Foundation

private struct Manifest: Decodable {
    var samples: [ManifestSample]
}

private struct ManifestSample: Decodable {
    var stem: String
    var width: Int
    var height: Int
    var inputPath: String

    enum CodingKeys: String, CodingKey {
        case stem
        case width
        case height
        case inputPath = "rgb_nchw_f32_path"
    }
}

private struct OutputPayload: Encodable {
    var results: [OutputResult]
}

private struct OutputResult: Encodable {
    var stem: String
    var width: Int
    var height: Int
    var gravity: [Float]
    var rollRadians: Double
    var pitchRadians: Double
    var verticalFOVRadians: Double
    var rollUncertaintyRadians: Double
    var pitchUncertaintyRadians: Double
    var gravityUncertainty: Double
    var verticalFOVUncertaintyRadians: Double

    enum CodingKeys: String, CodingKey {
        case stem
        case width
        case height
        case gravity
        case rollRadians = "roll_radians"
        case pitchRadians = "pitch_radians"
        case verticalFOVRadians = "vertical_fov_radians"
        case rollUncertaintyRadians = "roll_uncertainty_radians"
        case pitchUncertaintyRadians = "pitch_uncertainty_radians"
        case gravityUncertainty = "gravity_uncertainty"
        case verticalFOVUncertaintyRadians = "vertical_fov_uncertainty_radians"
    }
}

private struct Options {
    var manifest: URL?
    var output: URL?
    var models: [URL] = []
    var computeUnits = MLComputeUnits.all
}

private enum CLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case missingRequiredArgument(String)
    case unknownArgument(String)
    case invalidComputeUnits(String)
    case invalidInput(path: String, expectedBytes: Int, actualBytes: Int)

    var description: String {
        switch self {
        case .missingValue(let flag): return "\(flag) requires a value"
        case .missingRequiredArgument(let flag): return "missing required argument: \(flag)"
        case .unknownArgument(let value): return "unknown argument: \(value)"
        case .invalidComputeUnits(let value): return "invalid compute units: \(value)"
        case let .invalidInput(path, expectedBytes, actualBytes):
            return "\(path): expected \(expectedBytes) bytes, got \(actualBytes)"
        }
    }
}

@main
private enum ExportGeoCalibCameraPriors {
    static func main() {
        do {
            let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
            guard let manifestURL = options.manifest else {
                throw CLIError.missingRequiredArgument("--manifest")
            }
            guard !options.models.isEmpty else {
                throw CLIError.missingRequiredArgument("--model")
            }
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            let router = try AUGeoCalibCoreMLNeuralInferenceRouter(
                modelURLs: options.models,
                computeUnits: options.computeUnits
            )
            let shapeSpecs = router.supportedInputShapes.map {
                AUGeoCalibInputShapeSpec(label: "\($0[3]):\($0[2])", inputShape: $0)
            }
            let results = try manifest.samples.map { sample in
                let input = try readInput(sample)
                let shape = try AUGeoCalibInputShapeSpec.closest(
                    toWidth: sample.width,
                    height: sample.height,
                    in: shapeSpecs
                ).inputShape
                let preprocessed = try AUGeoCalibImagePreprocessor.preprocessRGB(
                    input,
                    width: sample.width,
                    height: sample.height,
                    targetInputShape: shape
                )
                let neuralOutput = try router.run(
                    inputRGB: preprocessed.inputRGBNCHW,
                    inputShape: preprocessed.inputShape
                )
                let detection = try AUGeoCalibHorizonDetector.detect(
                    preprocessedImage: preprocessed,
                    neuralOutput: neuralOutput
                )
                let optimizer = detection.optimizerResult
                return OutputResult(
                    stem: sample.stem,
                    width: sample.width,
                    height: sample.height,
                    gravity: optimizer.gravityData,
                    rollRadians: optimizer.rollRadians,
                    pitchRadians: optimizer.pitchRadians,
                    verticalFOVRadians: optimizer.verticalFOVRadians,
                    rollUncertaintyRadians: optimizer.rollUncertaintyRadians,
                    pitchUncertaintyRadians: optimizer.pitchUncertaintyRadians,
                    gravityUncertainty: optimizer.gravityUncertainty,
                    verticalFOVUncertaintyRadians: optimizer.verticalFOVUncertaintyRadians
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(OutputPayload(results: results))
            if let outputURL = options.output {
                try data.write(to: outputURL)
            } else {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([0x0A]))
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func readInput(_ sample: ManifestSample) throws -> [Float] {
        let url = URL(fileURLWithPath: sample.inputPath)
        let data = try Data(contentsOf: url)
        let count = 3 * sample.width * sample.height
        let expectedBytes = count * MemoryLayout<Float>.stride
        guard data.count == expectedBytes else {
            throw CLIError.invalidInput(path: url.path, expectedBytes: expectedBytes, actualBytes: data.count)
        }
        var values = [Float](repeating: 0, count: count)
        _ = values.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        return values
    }

    private static func parseOptions(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            func value() throws -> String {
                let next = index + 1
                guard next < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                index = next
                return arguments[next]
            }
            switch argument {
            case "--manifest": options.manifest = URL(fileURLWithPath: try value())
            case "--output": options.output = URL(fileURLWithPath: try value())
            case "--model": options.models.append(URL(fileURLWithPath: try value()))
            case "--compute-units": options.computeUnits = try parseComputeUnits(try value())
            case "--help", "-h":
                print("usage: export-geocalib-camera-priors --manifest manifest.json --model model.mlmodelc [--model ...] [--output priors.json]")
                Foundation.exit(0)
            default: throw CLIError.unknownArgument(argument)
            }
            index += 1
        }
        return options
    }

    private static func parseComputeUnits(_ value: String) throws -> MLComputeUnits {
        switch value {
        case "all": return .all
        case "cpu": return .cpuOnly
        case "cpuAndGPU": return .cpuAndGPU
        case "cpuAndNeuralEngine": return .cpuAndNeuralEngine
        default: throw CLIError.invalidComputeUnits(value)
        }
    }
}
