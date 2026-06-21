//
//  evaluate-swift-geocalib-rotation.swift
//  AnyUpright
//
//  Standalone LaMAR2k validator for the project-owned Swift/Metal GeoCalib
//  Horizon path.
//

import CoreGraphics
import CoreImage
import CoreML
import Dispatch
import Foundation

private struct SwiftGeoCalibEvaluationOptions {
    var dataset = URL(fileURLWithPath: "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/data/lamar2k")
    var output = URL(fileURLWithPath: "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/swift_geocalib_lamar2k_full")
    var runtimeBundle = URL(fileURLWithPath: "AnyUpright/Plugin/GeoCalibRuntime")
    var metalSource = URL(fileURLWithPath: "AnyUpright/Plugin/AnyUprightGeoCalib.metal")
    var metalLibrary: URL?
    var coreMLModel: URL?
    var coreMLComputeUnits = "all"
    var maxImages: Int?
    var offset = 0
    var maxAnalysisDimension = 1920
    var verifierMaxDimension = 640
    var progressEvery = 10
    var resume = false
    var filenames: [String] = []
    var imageList: URL?
}

private struct DatasetRecord {
    var filename: String
    var gtRollDegrees: Double
}

private struct AnalysisImage {
    var width: Int
    var height: Int
    var rgbNCHW: [Float]
    var grayscale: AUGrayscaleImage
}

private struct PredictionRecord {
    var filename: String
    var gtRollDegrees: Double
    var predRollDegrees: Double
    var correctionDegrees: Double
    var rollUncertaintyDegrees: Double
    var accepted: Bool
    var rejectionReasons: [String]
    var absErrorDegrees: Double
    var axisHoughRollDegrees: Double?
    var axisHoughDiffDegrees: Double?
    var axisHoughConfidence: Double
    var gradientAxisRollDegrees: Double?
    var gradientAxisDiffDegrees: Double?
    var gradientAxisConfidence: Double
    var totalTimeMilliseconds: Double
    var loadTimeMilliseconds: Double
    var preprocessTimeMilliseconds: Double
    var verifierTimeMilliseconds: Double
    var detectTimeMilliseconds: Double
    var geocalibTimeMilliseconds: Double
}

private let selectedPolicyName = "unc<=3 && no_2_verifier_diff>10 && abs_correction<=45"

private enum EvaluationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct SwiftGeoCalibRotationEvaluator {
    static func main() throws {
        let options = try parseOptions()
        try FileManager.default.createDirectory(
            at: options.output,
            withIntermediateDirectories: true
        )

        var records = try readDataset(options.dataset.appendingPathComponent("images.csv"))
        let requested = try requestedFilenames(options)
        if !requested.isEmpty {
            let byName = Dictionary(uniqueKeysWithValues: records.map { ($0.filename, $0) })
            let missing = requested.filter { byName[$0] == nil }
            if !missing.isEmpty {
                throw EvaluationFailure.failed("requested image(s) not found in dataset: \(missing.prefix(10).joined(separator: ", "))")
            }
            records = requested.compactMap { byName[$0] }
        }
        if options.offset > 0 {
            records = Array(records.dropFirst(options.offset))
        }
        if let maxImages = options.maxImages {
            records = Array(records.prefix(maxImages))
        }
        let predictionsURL = options.output.appendingPathComponent("predictions.csv")
        let existingPredictions = options.resume ? try readPredictionsCSV(predictionsURL) : []
        let completedFilenames = Set(existingPredictions.map(\.filename))
        if options.resume, !completedFilenames.isEmpty {
            records = records.filter { !completedFilenames.contains($0.filename) }
            print("Resume enabled: keeping \(existingPredictions.count) completed row(s), \(records.count) row(s) remaining.")
        }
        guard !records.isEmpty || !existingPredictions.isEmpty else {
            throw EvaluationFailure.failed("no dataset records to evaluate")
        }

        let neuralSession: EvaluationNeuralSession
        if let coreMLModel = options.coreMLModel {
            neuralSession = .coreML(
                try AUGeoCalibCoreMLNeuralInferenceSession(
                    modelURL: coreMLModel,
                    computeUnits: try coreMLComputeUnits(named: options.coreMLComputeUnits)
                )
            )
        } else {
            let runtimeBundle = try AUGeoCalibRuntimeBundle(rootURL: options.runtimeBundle)
            let session: AUGeoCalibNeuralInferenceSession
            if let metalLibrary = options.metalLibrary {
                session = try AUGeoCalibNeuralInferenceSession(
                    runtimeBundle: runtimeBundle,
                    metalLibraryURL: metalLibrary
                )
            } else {
                session = try AUGeoCalibNeuralInferenceSession(
                    runtimeBundle: runtimeBundle,
                    metalSource: options.metalSource
                )
            }
            neuralSession = .metal(session)
        }

        let context = CIContext(options: nil)
        let predictionsFile = try openPredictionsFile(predictionsURL, appending: options.resume && !existingPredictions.isEmpty)
        defer {
            try? predictionsFile.close()
        }

        if !options.resume || existingPredictions.isEmpty {
            try writeCSVLine(csvHeader, to: predictionsFile)
        }

        var predictions = existingPredictions
        predictions.reserveCapacity(existingPredictions.count + records.count)
        let fullRunStart = nowNanos()
        let totalTargetCount = existingPredictions.count + records.count

        for (index, record) in records.enumerated() {
            let prediction = try autoreleasepool {
                try evaluateRecord(
                    record,
                    options: options,
                    neuralSession: neuralSession,
                    context: context
                )
            }
            predictions.append(prediction)
            try writeCSVLine(csvRow(prediction), to: predictionsFile)
            try predictionsFile.synchronize()
            context.clearCaches()

            if options.progressEvery > 0,
               ((index + 1) % options.progressEvery == 0 || index + 1 == records.count) {
                let accepted = prediction.accepted ? "accepted" : "rejected"
                let completed = existingPredictions.count + index + 1
                print(
                    "[\(completed)/\(totalTargetCount)] \(record.filename) \(accepted) " +
                    "err=\(format(prediction.absErrorDegrees))deg " +
                    "total=\(format(prediction.totalTimeMilliseconds))ms " +
                    "detect=\(format(prediction.detectTimeMilliseconds))ms"
                )
                fflush(stdout)
            }
        }

        let wallTimeMilliseconds = elapsedMilliseconds(since: fullRunStart)
        let summary = summaryJSON(
            predictions: predictions,
            dataset: options.dataset,
            wallTimeMilliseconds: wallTimeMilliseconds
        )
        let summaryURL = options.output.appendingPathComponent("summary.json")
        try JSONSerialization.data(
            withJSONObject: summary,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: summaryURL)
        try markdownSummary(
            predictions: predictions,
            dataset: options.dataset,
            wallTimeMilliseconds: wallTimeMilliseconds
        ).write(
            to: options.output.appendingPathComponent("summary.md"),
            atomically: true,
            encoding: .utf8
        )
        print(String(data: try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }

    private static func parseOptions() throws -> SwiftGeoCalibEvaluationOptions {
        var options = SwiftGeoCalibEvaluationOptions()
        var index = 1
        let args = CommandLine.arguments
        while index < args.count {
            let arg = args[index]
            func requireValue() throws -> String {
                guard index + 1 < args.count else {
                    throw EvaluationFailure.failed("missing value for \(arg)")
                }
                index += 1
                return args[index]
            }
            switch arg {
            case "--dataset":
                options.dataset = resolvedURL(try requireValue())
            case "--out":
                options.output = resolvedURL(try requireValue())
            case "--runtime-bundle":
                options.runtimeBundle = resolvedURL(try requireValue())
            case "--metal-source":
                options.metalSource = resolvedURL(try requireValue())
            case "--metal-library":
                options.metalLibrary = resolvedURL(try requireValue())
            case "--coreml-model":
                options.coreMLModel = resolvedURL(try requireValue())
            case "--coreml-compute-units":
                options.coreMLComputeUnits = try requireValue()
            case "--max-images":
                options.maxImages = try parsePositiveInt(try requireValue(), label: arg)
            case "--offset":
                options.offset = try parseNonNegativeInt(try requireValue(), label: arg)
            case "--max-analysis-dimension":
                options.maxAnalysisDimension = try parsePositiveInt(try requireValue(), label: arg)
            case "--verifier-max-dimension":
                options.verifierMaxDimension = try parsePositiveInt(try requireValue(), label: arg)
            case "--progress-every":
                options.progressEvery = try parseNonNegativeInt(try requireValue(), label: arg)
            case "--filenames":
                options.filenames = parseFilenameList(try requireValue())
            case "--image-list":
                options.imageList = resolvedURL(try requireValue())
            case "--resume":
                options.resume = true
            case "--help", "-h":
                printUsageAndExit()
            default:
                throw EvaluationFailure.failed("unknown argument \(arg)")
            }
            index += 1
        }
        return options
    }
}

private enum EvaluationNeuralSession {
    case metal(AUGeoCalibNeuralInferenceSession)
    case coreML(AUGeoCalibCoreMLNeuralInferenceSession)

    func detect(
        preprocessedImage: AUGeoCalibPreprocessedImage,
        verifierEstimates: [AUGeoCalibHorizonVerifierEstimate]
    ) throws -> AUGeoCalibHorizonDetectionResult {
        switch self {
        case .metal(let session):
            return try AUGeoCalibHorizonDetector.detect(
                preprocessedImage: preprocessedImage,
                neuralSession: session,
                verifierEstimates: verifierEstimates
            )
        case .coreML(let session):
            let neuralOutput = try session.run(
                inputRGB: preprocessedImage.inputRGBNCHW,
                inputShape: preprocessedImage.inputShape
            )
            return try AUGeoCalibHorizonDetector.detect(
                preprocessedImage: preprocessedImage,
                neuralOutput: neuralOutput,
                verifierEstimates: verifierEstimates
            )
        }
    }
}

private func evaluateRecord(
    _ record: DatasetRecord,
    options: SwiftGeoCalibEvaluationOptions,
    neuralSession: EvaluationNeuralSession,
    context: CIContext
) throws -> PredictionRecord {
    let imageURL = options.dataset.appendingPathComponent("images").appendingPathComponent(record.filename)
    let totalStart = nowNanos()

    let loadStart = nowNanos()
    let analysisImage = try loadAnalysisImage(
        imageURL,
        maxDimension: options.maxAnalysisDimension,
        context: context
    )
    let loadTime = elapsedMilliseconds(since: loadStart)

    let preprocessStart = nowNanos()
    let preprocessed = try AUGeoCalibImagePreprocessor.preprocessRGB(
        analysisImage.rgbNCHW,
        width: analysisImage.width,
        height: analysisImage.height
    )
    let preprocessTime = elapsedMilliseconds(since: preprocessStart)

    let verifierStart = nowNanos()
    let verifierImage = boundedGrayscaleImage(
        analysisImage.grayscale,
        maximumDimension: options.verifierMaxDimension
    )
    let verifiers = [
        AUGeoCalibHorizonVerifiers.axisHough(in: verifierImage),
        AUGeoCalibHorizonVerifiers.gradientAxis(in: verifierImage),
    ]
    let verifierTime = elapsedMilliseconds(since: verifierStart)

    let detectStart = nowNanos()
    let result = try neuralSession.detect(
        preprocessedImage: preprocessed,
        verifierEstimates: verifiers
    )
    let detectTime = elapsedMilliseconds(since: detectStart)

    let predRollDegrees = radiansToDegrees(result.rollRadians)
    let absError = abs(wrapAngleDegrees(predRollDegrees - record.gtRollDegrees))
    let totalTime = elapsedMilliseconds(since: totalStart)
    let axisHough = verifier(named: "axis_hough", in: verifiers)
    let gradientAxis = verifier(named: "gradient_axis", in: verifiers)
    let axisHoughDiff = diff(named: "axis_hough", in: result.verifierDiffs)
    let gradientAxisDiff = diff(named: "gradient_axis", in: result.verifierDiffs)

    return PredictionRecord(
        filename: record.filename,
        gtRollDegrees: record.gtRollDegrees,
        predRollDegrees: predRollDegrees,
        correctionDegrees: radiansToDegrees(result.correctionRadians),
        rollUncertaintyDegrees: radiansToDegrees(result.rollUncertaintyRadians),
        accepted: result.accepted,
        rejectionReasons: result.rejectionReasons,
        absErrorDegrees: absError,
        axisHoughRollDegrees: axisHough.rollRadians.map(radiansToDegrees),
        axisHoughDiffDegrees: axisHoughDiff,
        axisHoughConfidence: axisHough.confidence,
        gradientAxisRollDegrees: gradientAxis.rollRadians.map(radiansToDegrees),
        gradientAxisDiffDegrees: gradientAxisDiff,
        gradientAxisConfidence: gradientAxis.confidence,
        totalTimeMilliseconds: totalTime,
        loadTimeMilliseconds: loadTime,
        preprocessTimeMilliseconds: preprocessTime,
        verifierTimeMilliseconds: verifierTime,
        detectTimeMilliseconds: detectTime,
        geocalibTimeMilliseconds: preprocessTime + detectTime
    )
}

private let csvHeader = [
    "fname",
    "gt_roll_deg",
    "pred_roll_deg",
    "correction_deg",
    "roll_uncertainty_deg",
    "accepted",
    "rejection_reasons",
    "abs_error_deg",
    "axis_hough_roll_deg",
    "axis_hough_diff_deg",
    "axis_hough_confidence",
    "gradient_axis_roll_deg",
    "gradient_axis_diff_deg",
    "gradient_axis_confidence",
    "total_time_ms",
    "load_time_ms",
    "preprocess_time_ms",
    "verifier_time_ms",
    "detect_time_ms",
    "geocalib_time_ms",
]

private func csvRow(_ record: PredictionRecord) -> [String] {
    [
        record.filename,
        string(record.gtRollDegrees),
        string(record.predRollDegrees),
        string(record.correctionDegrees),
        string(record.rollUncertaintyDegrees),
        record.accepted ? "true" : "false",
        record.rejectionReasons.joined(separator: "|"),
        string(record.absErrorDegrees),
        string(record.axisHoughRollDegrees),
        string(record.axisHoughDiffDegrees),
        string(record.axisHoughConfidence),
        string(record.gradientAxisRollDegrees),
        string(record.gradientAxisDiffDegrees),
        string(record.gradientAxisConfidence),
        string(record.totalTimeMilliseconds),
        string(record.loadTimeMilliseconds),
        string(record.preprocessTimeMilliseconds),
        string(record.verifierTimeMilliseconds),
        string(record.detectTimeMilliseconds),
        string(record.geocalibTimeMilliseconds),
    ]
}

private func openPredictionsFile(_ url: URL, appending: Bool) throws -> FileHandle {
    if appending, FileManager.default.fileExists(atPath: url.path) {
        let file = try FileHandle(forWritingTo: url)
        try file.seekToEnd()
        return file
    }

    if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
    }
    FileManager.default.createFile(atPath: url.path, contents: nil)
    return try FileHandle(forWritingTo: url)
}

private func readPredictionsCSV(_ url: URL) throws -> [PredictionRecord] {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return []
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    guard let headerLine = lines.first else {
        return []
    }
    let header = splitCSVLine(headerLine)
    let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })

    func field(_ fields: [String], _ name: String) -> String? {
        guard let index = indexes[name], fields.indices.contains(index) else {
            return nil
        }
        return fields[index]
    }
    func requiredDouble(_ fields: [String], _ name: String) -> Double? {
        field(fields, name).flatMap(Double.init)
    }
    func optionalDouble(_ fields: [String], _ name: String) -> Double? {
        guard let value = field(fields, name), !value.isEmpty else {
            return nil
        }
        return Double(value)
    }

    var records: [PredictionRecord] = []
    for line in lines.dropFirst() {
        let fields = splitCSVLine(line)
        guard fields.count >= csvHeader.count,
              let filename = field(fields, "fname"),
              let gtRoll = requiredDouble(fields, "gt_roll_deg"),
              let predRoll = requiredDouble(fields, "pred_roll_deg"),
              let correction = requiredDouble(fields, "correction_deg"),
              let uncertainty = requiredDouble(fields, "roll_uncertainty_deg"),
              let acceptedText = field(fields, "accepted"),
              let absError = requiredDouble(fields, "abs_error_deg"),
              let axisHoughConfidence = requiredDouble(fields, "axis_hough_confidence"),
              let gradientAxisConfidence = requiredDouble(fields, "gradient_axis_confidence"),
              let totalTime = requiredDouble(fields, "total_time_ms"),
              let loadTime = requiredDouble(fields, "load_time_ms"),
              let preprocessTime = requiredDouble(fields, "preprocess_time_ms"),
              let verifierTime = requiredDouble(fields, "verifier_time_ms"),
              let detectTime = requiredDouble(fields, "detect_time_ms"),
              let geocalibTime = requiredDouble(fields, "geocalib_time_ms") else {
            continue
        }
        records.append(
            PredictionRecord(
                filename: filename,
                gtRollDegrees: gtRoll,
                predRollDegrees: predRoll,
                correctionDegrees: correction,
                rollUncertaintyDegrees: uncertainty,
                accepted: acceptedText == "true",
                rejectionReasons: field(fields, "rejection_reasons")?.split(separator: "|").map(String.init) ?? [],
                absErrorDegrees: absError,
                axisHoughRollDegrees: optionalDouble(fields, "axis_hough_roll_deg"),
                axisHoughDiffDegrees: optionalDouble(fields, "axis_hough_diff_deg"),
                axisHoughConfidence: axisHoughConfidence,
                gradientAxisRollDegrees: optionalDouble(fields, "gradient_axis_roll_deg"),
                gradientAxisDiffDegrees: optionalDouble(fields, "gradient_axis_diff_deg"),
                gradientAxisConfidence: gradientAxisConfidence,
                totalTimeMilliseconds: totalTime,
                loadTimeMilliseconds: loadTime,
                preprocessTimeMilliseconds: preprocessTime,
                verifierTimeMilliseconds: verifierTime,
                detectTimeMilliseconds: detectTime,
                geocalibTimeMilliseconds: geocalibTime
            )
        )
    }
    return records
}

private func loadAnalysisImage(_ url: URL, maxDimension: Int, context: CIContext) throws -> AnalysisImage {
    guard let sourceImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        throw EvaluationFailure.failed("could not load image \(url.path)")
    }
    let sourceWidth = max(1, Int(sourceImage.extent.width.rounded()))
    let sourceHeight = max(1, Int(sourceImage.extent.height.rounded()))
    let scale = min(1.0, Double(maxDimension) / Double(max(sourceWidth, sourceHeight)))
    let width = max(1, Int(round(Double(sourceWidth) * scale)))
    let height = max(1, Int(round(Double(sourceHeight) * scale)))
    let image = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    var rgba = Array(repeating: UInt8(0), count: width * height * 4)

    context.render(
        image,
        toBitmap: &rgba,
        rowBytes: width * 4,
        bounds: CGRect(x: 0, y: 0, width: width, height: height),
        format: .RGBA8,
        colorSpace: CGColorSpaceCreateDeviceRGB()
    )

    let spatial = width * height
    var rgb = Array(repeating: Float(0), count: 3 * spatial)
    var gray = Array(repeating: UInt8(0), count: spatial)
    for index in 0..<spatial {
        let base = index * 4
        let red = Double(rgba[base])
        let green = Double(rgba[base + 1])
        let blue = Double(rgba[base + 2])
        rgb[index] = Float(red / 255.0)
        rgb[spatial + index] = Float(green / 255.0)
        rgb[2 * spatial + index] = Float(blue / 255.0)
        gray[index] = UInt8(min(255.0, max(0.0, round(red * 0.299 + green * 0.587 + blue * 0.114))))
    }
    return AnalysisImage(
        width: width,
        height: height,
        rgbNCHW: rgb,
        grayscale: AUGrayscaleImage(width: width, height: height, pixels: gray)
    )
}

private func boundedGrayscaleImage(_ image: AUGrayscaleImage, maximumDimension: Int) -> AUGrayscaleImage {
    guard image.width > 0,
          image.height > 0,
          image.pixels.count == image.width * image.height,
          max(image.width, image.height) > maximumDimension else {
        return image
    }
    let scale = Double(maximumDimension) / Double(max(image.width, image.height))
    let width = max(1, Int(round(Double(image.width) * scale)))
    let height = max(1, Int(round(Double(image.height) * scale)))
    var output = Array(repeating: UInt8(0), count: width * height)
    for y in 0..<height {
        let sourceY = min(image.height - 1, Int((Double(y) + 0.5) / scale))
        for x in 0..<width {
            let sourceX = min(image.width - 1, Int((Double(x) + 0.5) / scale))
            output[y * width + x] = image.pixels[sourceY * image.width + sourceX]
        }
    }
    return AUGrayscaleImage(width: width, height: height, pixels: output)
}

private func readDataset(_ csvURL: URL) throws -> [DatasetRecord] {
    let text = try String(contentsOf: csvURL, encoding: .utf8)
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    guard let headerLine = lines.first else {
        throw EvaluationFailure.failed("empty dataset csv \(csvURL.path)")
    }
    let header = splitCSVLine(headerLine)
    let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
    guard let fnameIndex = indexes["fname"],
          let rollIndex = indexes["roll"] else {
        throw EvaluationFailure.failed("dataset csv must contain fname and roll columns")
    }

    return try lines.dropFirst().map { line in
        let fields = splitCSVLine(line)
        guard fields.count > max(fnameIndex, rollIndex),
              let rollRadians = Double(fields[rollIndex]) else {
            throw EvaluationFailure.failed("invalid dataset row: \(line)")
        }
        return DatasetRecord(
            filename: fields[fnameIndex],
            gtRollDegrees: radiansToDegrees(rollRadians)
        )
    }
}

private func requestedFilenames(_ options: SwiftGeoCalibEvaluationOptions) throws -> [String] {
    var names = options.filenames
    if let imageList = options.imageList {
        let text = try String(contentsOf: imageList, encoding: .utf8)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if imageList.pathExtension.lowercased() == "csv",
           let headerLine = lines.first {
            let header = splitCSVLine(headerLine)
            let fnameIndex = header.firstIndex(of: "fname") ?? 0
            for line in lines.dropFirst() {
                let fields = splitCSVLine(line)
                if fields.indices.contains(fnameIndex) {
                    let name = fields[fnameIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        names.append(name)
                    }
                }
            }
        } else {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    continue
                }
                let name = trimmed.split(separator: ",", maxSplits: 1).first.map(String.init) ?? trimmed
                if !name.isEmpty {
                    names.append(name)
                }
            }
        }
    }

    var seen = Set<String>()
    var unique: [String] = []
    for name in names where !seen.contains(name) {
        seen.insert(name)
        unique.append(name)
    }
    return unique
}

private func parseFilenameList(_ value: String) -> [String] {
    value
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func summaryJSON(
    predictions: [PredictionRecord],
    dataset: URL,
    wallTimeMilliseconds: Double
) -> [String: Any] {
    let accepted = predictions.filter(\.accepted)
    return [
        "dataset": dataset.path,
        "image_count": predictions.count,
        "selected_policy": selectedPolicyName,
        "accepted_count": accepted.count,
        "acceptance": Double(accepted.count) / Double(max(1, predictions.count)),
        "rejected_count": predictions.count - accepted.count,
        "wall_time_ms": wallTimeMilliseconds,
        "all_results": metrics(for: predictions),
        "accepted_results": metrics(for: accepted),
    ]
}

private func markdownSummary(
    predictions: [PredictionRecord],
    dataset: URL,
    wallTimeMilliseconds: Double
) -> String {
    let accepted = predictions.filter(\.accepted)
    let allMetrics = metrics(for: predictions)
    let acceptedMetrics = metrics(for: accepted)
    var lines: [String] = [
        "# Swift/Metal GeoCalib Rotation Experiment",
        "",
        "Dataset: `\(dataset.path)`",
        "Images evaluated: `\(predictions.count)`",
        "Selected policy: `\(selectedPolicyName)`",
        "Wall time: `\(format(wallTimeMilliseconds / 1000.0)) s`",
        "",
        "| Scope | Count | MAE | Median AE | RMSE | P90 AE | <=1 deg | <=2 deg | <=5 deg | Mean GeoCalib | Median GeoCalib | P90 GeoCalib | Mean total | Median total | P90 total | Mean detect | Median detect | P90 detect |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    lines.append(markdownMetricsRow("All GeoCalib results", allMetrics))
    lines.append(markdownMetricsRow("Accepted writebacks", acceptedMetrics))
    lines.append("")
    lines.append("Accepted: `\(accepted.count) / \(predictions.count) (\(format(Double(accepted.count) / Double(max(1, predictions.count)) * 100.0))%)`")
    return lines.joined(separator: "\n") + "\n"
}

private func metrics(for predictions: [PredictionRecord]) -> [String: Any] {
    if predictions.isEmpty {
        return [
            "count": 0,
            "mae_deg": NSNull(),
            "median_abs_error_deg": NSNull(),
            "rmse_deg": NSNull(),
            "p90_abs_error_deg": NSNull(),
            "within_1deg": NSNull(),
            "within_2deg": NSNull(),
            "within_5deg": NSNull(),
            "mean_total_time_ms": NSNull(),
            "median_total_time_ms": NSNull(),
            "p90_total_time_ms": NSNull(),
            "mean_geocalib_time_ms": NSNull(),
            "median_geocalib_time_ms": NSNull(),
            "p90_geocalib_time_ms": NSNull(),
            "mean_detect_time_ms": NSNull(),
            "median_detect_time_ms": NSNull(),
            "p90_detect_time_ms": NSNull(),
        ]
    }
    let errors = predictions.map(\.absErrorDegrees)
    let totalTimes = predictions.map(\.totalTimeMilliseconds)
    let detectTimes = predictions.map(\.detectTimeMilliseconds)
    let geocalibTimes = predictions.map(\.geocalibTimeMilliseconds)
    return [
        "count": predictions.count,
        "mae_deg": mean(errors),
        "median_abs_error_deg": percentile(errors, 50),
        "rmse_deg": rmse(errors),
        "p90_abs_error_deg": percentile(errors, 90),
        "within_1deg": fraction(errors) { $0 <= 1.0 },
        "within_2deg": fraction(errors) { $0 <= 2.0 },
        "within_5deg": fraction(errors) { $0 <= 5.0 },
        "mean_total_time_ms": mean(totalTimes),
        "median_total_time_ms": percentile(totalTimes, 50),
        "p90_total_time_ms": percentile(totalTimes, 90),
        "mean_geocalib_time_ms": mean(geocalibTimes),
        "median_geocalib_time_ms": percentile(geocalibTimes, 50),
        "p90_geocalib_time_ms": percentile(geocalibTimes, 90),
        "mean_detect_time_ms": mean(detectTimes),
        "median_detect_time_ms": percentile(detectTimes, 50),
        "p90_detect_time_ms": percentile(detectTimes, 90),
    ]
}

private func markdownMetricsRow(_ label: String, _ metrics: [String: Any]) -> String {
    func double(_ key: String) -> Double {
        metrics[key] as? Double ?? .nan
    }
    let count = metrics["count"] as? Int ?? 0
    return "| \(label) | \(count) | \(format(double("mae_deg"))) deg | \(format(double("median_abs_error_deg"))) deg | \(format(double("rmse_deg"))) deg | \(format(double("p90_abs_error_deg"))) deg | \(format(double("within_1deg") * 100.0))% | \(format(double("within_2deg") * 100.0))% | \(format(double("within_5deg") * 100.0))% | \(format(double("mean_geocalib_time_ms"))) ms | \(format(double("median_geocalib_time_ms"))) ms | \(format(double("p90_geocalib_time_ms"))) ms | \(format(double("mean_total_time_ms"))) ms | \(format(double("median_total_time_ms"))) ms | \(format(double("p90_total_time_ms"))) ms | \(format(double("mean_detect_time_ms"))) ms | \(format(double("median_detect_time_ms"))) ms | \(format(double("p90_detect_time_ms"))) ms |"
}

private func splitCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var inQuotes = false
    var iterator = line.makeIterator()
    while let character = iterator.next() {
        if character == "\"" {
            inQuotes.toggle()
        } else if character == "," && !inQuotes {
            fields.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }
    fields.append(current)
    return fields
}

private func writeCSVLine(_ fields: [String], to file: FileHandle) throws {
    let line = fields.map(escapeCSVField).joined(separator: ",") + "\n"
    try file.write(contentsOf: Data(line.utf8))
}

private func escapeCSVField(_ field: String) -> String {
    guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
        return field
    }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

private func verifier(named name: String, in verifiers: [AUGeoCalibHorizonVerifierEstimate]) -> AUGeoCalibHorizonVerifierEstimate {
    verifiers.first { $0.name == name } ??
        AUGeoCalibHorizonVerifierEstimate(name: name, rollRadians: nil, confidence: 0, sampleCount: 0)
}

private func diff(named name: String, in diffs: [AUGeoCalibHorizonVerifierDiff]) -> Double? {
    diffs.first { $0.name == name }?.differenceRadians.map(radiansToDegrees)
}

private func nowNanos() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

private func elapsedMilliseconds(since start: UInt64) -> Double {
    Double(nowNanos() - start) / 1_000_000.0
}

private func radiansToDegrees(_ radians: Double) -> Double {
    radians * 180.0 / .pi
}

private func wrapAngleDegrees(_ angle: Double) -> Double {
    var wrapped = (angle + 180.0).truncatingRemainder(dividingBy: 360.0)
    if wrapped < 0 {
        wrapped += 360.0
    }
    return wrapped - 180.0
}

private func mean(_ values: [Double]) -> Double {
    guard !values.isEmpty else {
        return .nan
    }
    return values.reduce(0.0, +) / Double(values.count)
}

private func rmse(_ values: [Double]) -> Double {
    guard !values.isEmpty else {
        return .nan
    }
    return sqrt(values.reduce(0.0) { $0 + $1 * $1 } / Double(values.count))
}

private func percentile(_ values: [Double], _ percentile: Double) -> Double {
    guard !values.isEmpty else {
        return .nan
    }
    let sorted = values.sorted()
    guard sorted.count > 1 else {
        return sorted[0]
    }
    let position = (Double(sorted.count - 1) * percentile) / 100.0
    let lower = Int(floor(position))
    let upper = Int(ceil(position))
    if lower == upper {
        return sorted[lower]
    }
    let fraction = position - Double(lower)
    return sorted[lower] * (1.0 - fraction) + sorted[upper] * fraction
}

private func fraction(_ values: [Double], predicate: (Double) -> Bool) -> Double {
    guard !values.isEmpty else {
        return .nan
    }
    return Double(values.filter(predicate).count) / Double(values.count)
}

private func string(_ value: Double?) -> String {
    guard let value, value.isFinite else {
        return ""
    }
    return String(format: "%.12g", value)
}

private func format(_ value: Double) -> String {
    guard value.isFinite else {
        return "nan"
    }
    return String(format: "%.3f", value)
}

private func resolvedURL(_ path: String) -> URL {
    let url = URL(fileURLWithPath: path)
    if url.path.hasPrefix("/") {
        return url
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
}

private func parsePositiveInt(_ value: String, label: String) throws -> Int {
    guard let intValue = Int(value), intValue > 0 else {
        throw EvaluationFailure.failed("\(label) must be a positive integer")
    }
    return intValue
}

private func parseNonNegativeInt(_ value: String, label: String) throws -> Int {
    guard let intValue = Int(value), intValue >= 0 else {
        throw EvaluationFailure.failed("\(label) must be a non-negative integer")
    }
    return intValue
}

private func coreMLComputeUnits(named name: String) throws -> MLComputeUnits {
    switch name {
    case "all":
        return .all
    case "cpuOnly":
        return .cpuOnly
    case "cpuAndGPU":
        return .cpuAndGPU
    case "cpuAndNeuralEngine":
        return .cpuAndNeuralEngine
    default:
        throw EvaluationFailure.failed(
            "--coreml-compute-units must be one of all, cpuOnly, cpuAndGPU, cpuAndNeuralEngine"
        )
    }
}

private func printUsageAndExit() -> Never {
    print(
        """
        Usage:
          evaluate-swift-geocalib-rotation [options]

        Options:
          --dataset PATH                 LaMAR2k dataset directory containing images.csv and images/
          --out PATH                     Output directory for predictions.csv, summary.json, summary.md
          --runtime-bundle PATH          AnyUpright GeoCalibRuntime directory
          --metal-source PATH            Metal source file, used when --metal-library is omitted
          --metal-library PATH           Prebuilt default.metallib
          --coreml-model PATH            Core ML neural-forward .mlpackage/.mlmodel/.mlmodelc
          --coreml-compute-units NAME    all, cpuOnly, cpuAndGPU, cpuAndNeuralEngine
          --max-images N                 Evaluate only the first N rows after --offset
          --offset N                     Skip first N rows
          --max-analysis-dimension N     Long-edge cap before GeoCalib preprocessing
          --verifier-max-dimension N     Long-edge cap for lightweight verifiers
          --progress-every N             Print progress every N images; 0 disables progress
          --filenames A,B                Comma-separated image filenames to evaluate
          --image-list PATH              Text or CSV file containing image filenames to evaluate
          --resume                       Append to an existing predictions.csv and skip completed filenames
        """
    )
    Foundation.exit(0)
}
