//
//  export-scalelsd-upright-lines.swift
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
        case inputPath = "input_f32_path"
    }
}

private struct ExportPayload: Encodable {
    var detector: String
    var model: String
    var results: [ExportResult]
}

private struct ExportResult: Encodable {
    var stem: String
    var width: Int
    var height: Int
    var candidates: [ExportLine]
}

private struct ExportLine: Encodable {
    var start: ExportPoint
    var end: ExportPoint
    var score: Double
}

private struct ExportPoint: Encodable {
    var x: Double
    var y: Double
}

private struct Options {
    var manifest: URL?
    var model: URL?
    var output: URL?
    var computeUnits = MLComputeUnits.all
}

private enum CLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)
    case missingRequiredArgument(String)
    case invalidComputeUnits(String)
    case invalidInput(path: String, expectedBytes: Int, actualBytes: Int)

    var description: String {
        switch self {
        case .missingValue(let flag):
            return "\(flag) requires a value"
        case .unknownArgument(let value):
            return "unknown argument: \(value)"
        case .missingRequiredArgument(let flag):
            return "missing required argument: \(flag)"
        case .invalidComputeUnits(let value):
            return "invalid compute units: \(value)"
        case .invalidInput(let path, let expectedBytes, let actualBytes):
            return "invalid input tensor at \(path): expected \(expectedBytes) bytes, got \(actualBytes)"
        }
    }
}

@main
private enum ExportScaleLSDUprightLines {
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
            case "--manifest":
                options.manifest = URL(fileURLWithPath: try value())
            case "--model":
                options.model = URL(fileURLWithPath: try value())
            case "--output":
                options.output = URL(fileURLWithPath: try value())
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

    private static func parseComputeUnits(_ value: String) throws -> MLComputeUnits {
        switch value {
        case "all": return .all
        case "cpu": return .cpuOnly
        case "cpuAndGPU": return .cpuAndGPU
        case "cpuAndNeuralEngine": return .cpuAndNeuralEngine
        default: throw CLIError.invalidComputeUnits(value)
        }
    }

    private static func run(options: Options) throws -> ExportPayload {
        guard let manifestURL = options.manifest else {
            throw CLIError.missingRequiredArgument("--manifest")
        }
        guard let modelURL = options.model else {
            throw CLIError.missingRequiredArgument("--model")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        let session = try AUScaleLSDCoreMLSession(modelURL: modelURL, computeUnits: options.computeUnits)
        let results = try manifest.samples.map { sample in
            try detect(sample: sample, session: session)
        }
        return ExportPayload(detector: "scalelsd-coreml", model: modelURL.path, results: results)
    }

    private static func detect(sample: ManifestSample, session: AUScaleLSDCoreMLSession) throws -> ExportResult {
        let inputURL = URL(fileURLWithPath: sample.inputPath)
        let data = try Data(contentsOf: inputURL)
        let expectedCount = 512 * 512
        let expectedBytes = expectedCount * MemoryLayout<Float>.stride
        guard data.count == expectedBytes else {
            throw CLIError.invalidInput(path: inputURL.path, expectedBytes: expectedBytes, actualBytes: data.count)
        }
        var input = [Float](repeating: 0, count: expectedCount)
        _ = input.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        let dense = try session.run(inputNCHW: input)
        let lines = try AnyUprightScaleLSDPostprocessor.decode(
            denseLogits: dense.values,
            shape: dense.shape,
            imageWidth: sample.width,
            imageHeight: sample.height
        )
        return ExportResult(
            stem: sample.stem,
            width: sample.width,
            height: sample.height,
            candidates: lines.map {
                ExportLine(
                    start: ExportPoint(x: $0.start.x, y: $0.start.y),
                    end: ExportPoint(x: $0.end.x, y: $0.end.y),
                    score: $0.score
                )
            }
        )
    }

    private static func printUsage() {
        print("usage: export-scalelsd-upright-lines --manifest manifest.json --model scalelsd.mlmodelc [--output output.json]")
    }
}
