//
//  rank-scalelsd-upright-proposals.swift
//  AnyUpright
//

import Foundation
import simd

private struct InputPayload: Decodable {
    var results: [InputResult]
}

private struct InputResult: Decodable {
    var stem: String
    var width: Int
    var height: Int
    var candidates: [InputLine]
    var cameraPrior: InputCameraPrior?

    enum CodingKeys: String, CodingKey {
        case stem
        case width
        case height
        case candidates
        case cameraPrior = "camera_prior"
    }
}

private struct InputCameraPrior: Decodable {
    var gravity: [Double]
    var verticalFOVRadians: Double
    var gravityUncertainty: Double
    var verticalFOVUncertaintyRadians: Double

    enum CodingKeys: String, CodingKey {
        case gravity
        case verticalFOVRadians = "vertical_fov_radians"
        case gravityUncertainty = "gravity_uncertainty"
        case verticalFOVUncertaintyRadians = "vertical_fov_uncertainty_radians"
    }
}

private struct InputLine: Codable {
    var start: InputPoint
    var end: InputPoint
    var score: Double
}

private struct InputPoint: Codable {
    var x: Double
    var y: Double
}

private struct OutputPayload: Encodable {
    var mode: String
    var results: [OutputResult]
}

private struct OutputResult: Encodable {
    var stem: String
    var width: Int
    var height: Int
    var accepted: Bool
    var rejectionReason: String?
    var verticalPair: OutputPair?
    var horizontalPair: OutputPair?
    var verticalResidualDegrees: Double?
    var horizontalResidualDegrees: Double?
    var autoCropScale: Double?
    var outputToSourceMatrix: [Float]?

    enum CodingKeys: String, CodingKey {
        case stem
        case width
        case height
        case accepted
        case rejectionReason = "rejection_reason"
        case verticalPair = "vertical_pair"
        case horizontalPair = "horizontal_pair"
        case verticalResidualDegrees = "vertical_residual_degrees"
        case horizontalResidualDegrees = "horizontal_residual_degrees"
        case autoCropScale = "auto_crop_scale"
        case outputToSourceMatrix = "output_to_source_matrix"
    }
}

private struct OutputPair: Encodable {
    var firstIndex: Int
    var secondIndex: Int
    var firstLine: InputLine
    var secondLine: InputLine
    var vanishingPoint: InputPoint?
    var supportCount: Int
    var meanSupportResidualRatio: Double
    var score: Double

    enum CodingKeys: String, CodingKey {
        case firstIndex = "first_index"
        case secondIndex = "second_index"
        case firstLine = "first_line"
        case secondLine = "second_line"
        case vanishingPoint = "vanishing_point"
        case supportCount = "support_count"
        case meanSupportResidualRatio = "mean_support_residual_ratio"
        case score
    }
}

private struct Options {
    var input: URL?
    var output: URL?
    var mode: UprightCorrectionMode = .full
}

private enum CLIError: Error, CustomStringConvertible {
    case missingValue(String)
    case missingRequiredArgument(String)
    case unknownArgument(String)
    case invalidMode(String)

    var description: String {
        switch self {
        case .missingValue(let flag): return "\(flag) requires a value"
        case .missingRequiredArgument(let flag): return "missing required argument: \(flag)"
        case .unknownArgument(let value): return "unknown argument: \(value)"
        case .invalidMode(let value): return "invalid mode: \(value)"
        }
    }
}

@main
private enum RankScaleLSDUprightProposals {
    static func main() {
        do {
            let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
            guard let inputURL = options.input else {
                throw CLIError.missingRequiredArgument("--input")
            }
            let input = try JSONDecoder().decode(InputPayload.self, from: Data(contentsOf: inputURL))
            let results = input.results.map { rank($0, mode: options.mode) }
            let payload = OutputPayload(mode: modeName(options.mode), results: results)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
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

    private static func rank(_ input: InputResult, mode: UprightCorrectionMode) -> OutputResult {
        let proposalInputs = input.candidates.map {
            AUUprightProposalInputLine(
                line: AULineSegment(
                    start: AUPoint(x: $0.start.x, y: $0.start.y),
                    end: AUPoint(x: $0.end.x, y: $0.end.y)
                ),
                score: $0.score
            )
        }
        let proposal = AnyUprightUprightProposalRanker.makeProposal(
            lines: proposalInputs,
            correctionMode: mode,
            imageSize: AUSize(width: Double(input.width), height: Double(input.height)),
            cameraPrior: cameraPrior(input.cameraPrior)
        )
        return OutputResult(
            stem: input.stem,
            width: input.width,
            height: input.height,
            accepted: proposal.accepted,
            rejectionReason: proposal.rejectionReason?.rawValue,
            verticalPair: outputPair(proposal.verticalPair, candidates: input.candidates),
            horizontalPair: outputPair(proposal.horizontalPair, candidates: input.candidates),
            verticalResidualDegrees: proposal.verticalResidualDegrees,
            horizontalResidualDegrees: proposal.horizontalResidualDegrees,
            autoCropScale: proposal.autoCropScale,
            outputToSourceMatrix: matrixValues(proposal.outputToSourceMatrix)
        )
    }

    private static func cameraPrior(_ input: InputCameraPrior?) -> AUUprightCameraPrior? {
        guard let input, input.gravity.count == 3 else {
            return nil
        }
        return AUUprightCameraPrior(
            gravity: SIMD3<Double>(input.gravity[0], input.gravity[1], input.gravity[2]),
            verticalFOVRadians: input.verticalFOVRadians,
            gravityUncertainty: input.gravityUncertainty,
            verticalFOVUncertaintyRadians: input.verticalFOVUncertaintyRadians
        )
    }

    private static func outputPair(_ pair: AUUprightProposalPair?, candidates: [InputLine]) -> OutputPair? {
        guard let pair,
              candidates.indices.contains(pair.firstIndex),
              candidates.indices.contains(pair.secondIndex) else {
            return nil
        }
        return OutputPair(
            firstIndex: pair.firstIndex,
            secondIndex: pair.secondIndex,
            firstLine: candidates[pair.firstIndex],
            secondLine: candidates[pair.secondIndex],
            vanishingPoint: pair.vanishingPoint.map { InputPoint(x: $0.x, y: $0.y) },
            supportCount: pair.supportCount,
            meanSupportResidualRatio: pair.meanSupportResidualRatio,
            score: pair.score
        )
    }

    private static func matrixValues(_ matrix: simd_float3x3?) -> [Float]? {
        guard let matrix else {
            return nil
        }
        return [
            matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x,
            matrix.columns.0.y, matrix.columns.1.y, matrix.columns.2.y,
            matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z,
        ]
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
            case "--input": options.input = URL(fileURLWithPath: try value())
            case "--output": options.output = URL(fileURLWithPath: try value())
            case "--mode": options.mode = try parseMode(try value())
            case "--help", "-h":
                print("usage: rank-scalelsd-upright-proposals --input scalelsd-lines.json [--output proposals.json] [--mode vertical|horizontal|full]")
                Foundation.exit(0)
            default: throw CLIError.unknownArgument(argument)
            }
            index += 1
        }
        return options
    }

    private static func parseMode(_ value: String) throws -> UprightCorrectionMode {
        switch value {
        case "vertical": return .vertical
        case "horizontal": return .horizontal
        case "full": return .full
        default: throw CLIError.invalidMode(value)
        }
    }

    private static func modeName(_ mode: UprightCorrectionMode) -> String {
        switch mode {
        case .vertical: return "vertical"
        case .horizontal: return "horizontal"
        case .full: return "full"
        }
    }
}
