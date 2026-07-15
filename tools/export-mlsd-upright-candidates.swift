//
//  export-mlsd-upright-candidates.swift
//  AnyUpright
//
//  Offline helper for the HoliCity validation harness. Python owns archive and
//  image decoding; this tool owns the Swift/Core ML M-LSD detector invocation.
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
    var rgbaPath: String

    private enum CodingKeys: String, CodingKey {
        case stem
        case width
        case height
        case rgbaPath = "rgba_path"
    }
}

private struct ExportPayload: Encodable {
    var detector: String
    var model: String
    var mode: String
    var results: [ExportResult]
}

private struct ExportResult: Encodable {
    var stem: String
    var width: Int
    var height: Int
    var candidates: [ExportCandidate]
}

private struct ExportCandidate: Encodable {
    var orientation: String
    var start: ExportPoint
    var end: ExportPoint
    var score: Double
}

private struct ExportPoint: Encodable {
    var x: Double
    var y: Double
}

private struct CLIOptions {
    var manifest: URL?
    var model: URL?
    var output: URL?
    var mode = UprightCorrectionMode.full
    var computeUnits = MLComputeUnits.all
}

private enum CLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)
    case missingRequiredArgument(String)
    case invalidMode(String)
    case invalidComputeUnits(String)
    case invalidRGBA(path: String, expected: Int, actual: Int)

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "\(flag) requires a value"
        case .unknownArgument(let value):
            return "unknown argument: \(value)"
        case .missingRequiredArgument(let flag):
            return "missing required argument: \(flag)"
        case .invalidMode(let value):
            return "invalid mode: \(value)"
        case .invalidComputeUnits(let value):
            return "invalid compute units: \(value)"
        case .invalidRGBA(let path, let expected, let actual):
            return "invalid RGBA payload at \(path): expected \(expected) bytes, got \(actual)"
        }
    }
}

@main
private enum ExportMLSDUprightCandidates {
    static func main() {
        do {
            let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
            let payload = try run(options: options)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            if let output = options.output {
                try data.write(to: output)
            } else {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([0x0A]))
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func parseOptions(_ arguments: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            func value() throws -> String {
                let nextIndex = index + 1
                guard nextIndex < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                index = nextIndex
                return arguments[nextIndex]
            }

            switch argument {
            case "--manifest":
                options.manifest = URL(fileURLWithPath: try value())
            case "--model":
                options.model = URL(fileURLWithPath: try value())
            case "--output":
                options.output = URL(fileURLWithPath: try value())
            case "--mode":
                options.mode = try parseMode(try value())
            case "--compute-units":
                options.computeUnits = try parseComputeUnits(try value())
            case "--help", "-h":
                printUsage()
                Foundation.exit(0)
            default:
                throw CLIError.unknownArgument(argument)
            }
            index += 1
        }
        return options
    }

    private static func parseMode(_ value: String) throws -> UprightCorrectionMode {
        switch value {
        case "vertical":
            return .vertical
        case "horizontal":
            return .horizontal
        case "full":
            return .full
        default:
            throw CLIError.invalidMode(value)
        }
    }

    private static func parseComputeUnits(_ value: String) throws -> MLComputeUnits {
        switch value {
        case "all":
            return .all
        case "cpu":
            return .cpuOnly
        case "cpuAndGPU":
            return .cpuAndGPU
        case "cpuAndNeuralEngine":
            return .cpuAndNeuralEngine
        default:
            throw CLIError.invalidComputeUnits(value)
        }
    }

    private static func run(options: CLIOptions) throws -> ExportPayload {
        guard let manifestURL = options.manifest else {
            throw CLIError.missingRequiredArgument("--manifest")
        }
        guard let modelURL = options.model else {
            throw CLIError.missingRequiredArgument("--model")
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        let results = try manifest.samples.map { sample in
            try detect(sample: sample, modelURL: modelURL, mode: options.mode, computeUnits: options.computeUnits)
        }
        return ExportPayload(
            detector: "mlsd-coreml",
            model: modelURL.path,
            mode: modeName(options.mode),
            results: results
        )
    }

    private static func detect(
        sample: ManifestSample,
        modelURL: URL,
        mode: UprightCorrectionMode,
        computeUnits: MLComputeUnits
    ) throws -> ExportResult {
        let rgbaURL = URL(fileURLWithPath: sample.rgbaPath)
        let rgba = try Data(contentsOf: rgbaURL)
        let expectedCount = sample.width * sample.height * 4
        guard rgba.count == expectedCount else {
            throw CLIError.invalidRGBA(path: rgbaURL.path, expected: expectedCount, actual: rgba.count)
        }

        let candidates = try AnyUprightMLSDCoreMLDetector.detectImageCandidates(
            width: sample.width,
            height: sample.height,
            rgbaPixels: [UInt8](rgba),
            correctionMode: mode,
            modelURL: modelURL,
            computeUnits: computeUnits
        )
        return ExportResult(
            stem: sample.stem,
            width: sample.width,
            height: sample.height,
            candidates: candidates.map(exportCandidate)
        )
    }

    private static func exportCandidate(_ candidate: UprightDetectedCandidate) -> ExportCandidate {
        ExportCandidate(
            orientation: orientationName(candidate.orientation),
            start: ExportPoint(x: candidate.start.x, y: candidate.start.y),
            end: ExportPoint(x: candidate.end.x, y: candidate.end.y),
            score: candidate.score
        )
    }

    private static func orientationName(_ orientation: UprightGuideOrientation) -> String {
        switch orientation {
        case .vertical:
            return "vertical"
        case .horizontal:
            return "horizontal"
        }
    }

    private static func modeName(_ mode: UprightCorrectionMode) -> String {
        switch mode {
        case .vertical:
            return "vertical"
        case .horizontal:
            return "horizontal"
        case .full:
            return "full"
        }
    }

    private static func printUsage() {
        print(
            """
            usage: export-mlsd-upright-candidates --manifest manifest.json --model mlsd.mlmodelc [--mode vertical|horizontal|full] [--output output.json]

            Manifest schema:
              {"samples":[{"stem":"id","width":1920,"height":1080,"rgba_path":"/tmp/id.rgba"}]}
            """
        )
    }
}
