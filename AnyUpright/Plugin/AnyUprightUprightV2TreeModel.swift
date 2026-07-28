//
//  AnyUprightUprightV2TreeModel.swift
//  AnyUpright
//

import Foundation

enum AUUprightV2TreeModelError: Error, CustomStringConvertible {
    case unreadableModel(URL)
    case invalidHeader(String)
    case invalidTree(Int, String)
    case featureCount(expected: Int, actual: Int)
    case missingBundledModel(String)

    var description: String {
        switch self {
        case .unreadableModel(let url):
            return "Could not read Upright V2 tree model at \(url.path)"
        case .invalidHeader(let reason):
            return "Invalid Upright V2 tree model header: \(reason)"
        case .invalidTree(let index, let reason):
            return "Invalid Upright V2 tree \(index): \(reason)"
        case .featureCount(let expected, let actual):
            return "Upright V2 model expects \(expected) features, received \(actual)"
        case .missingBundledModel(let filename):
            return "Missing bundled Upright V2 model \(filename)"
        }
    }
}

private struct AUUprightV2DecisionTree {
    var splitFeatures: [Int]
    var thresholds: [Double]
    var leftChildren: [Int]
    var rightChildren: [Int]
    var leafValues: [Double]

    func prediction(features: [Double]) -> Double {
        var node = 0
        while node >= 0 {
            let feature = splitFeatures[node]
            node = features[feature] <= thresholds[node]
                ? leftChildren[node]
                : rightChildren[node]
        }
        return leafValues[-node - 1]
    }
}

final class AUUprightV2TreeModel {
    enum OutputTransform {
        case identity
        case logistic
    }

    let featureNames: [String]
    private let trees: [AUUprightV2DecisionTree]
    private let outputTransform: OutputTransform

    init(contentsOf url: URL) throws {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw AUUprightV2TreeModelError.unreadableModel(url)
        }
        let sections = text.components(separatedBy: "\nTree=")
        guard let header = sections.first else {
            throw AUUprightV2TreeModelError.invalidHeader("missing header")
        }
        let headerValues = Self.values(in: header)
        guard headerValues["version"] == "v4" else {
            throw AUUprightV2TreeModelError.invalidHeader("unsupported version")
        }
        guard headerValues["num_class"] == "1",
              headerValues["num_tree_per_iteration"] == "1" else {
            throw AUUprightV2TreeModelError.invalidHeader("only scalar models are supported")
        }
        guard let featureNames = headerValues["feature_names"]?.split(separator: " ").map(String.init),
              !featureNames.isEmpty else {
            throw AUUprightV2TreeModelError.invalidHeader("missing feature names")
        }
        self.featureNames = featureNames
        outputTransform = headerValues["objective"]?.hasPrefix("binary") == true ? .logistic : .identity

        var parsedTrees: [AUUprightV2DecisionTree] = []
        parsedTrees.reserveCapacity(max(0, sections.count - 1))
        for (treeIndex, rawSection) in sections.dropFirst().enumerated() {
            let values = Self.values(in: rawSection)
            guard let leafCount = values["num_leaves"].flatMap(Int.init), leafCount > 0 else {
                throw AUUprightV2TreeModelError.invalidTree(treeIndex, "missing leaf count")
            }
            let splitCount = leafCount - 1
            let splitFeatures = try Self.integerArray(
                values["split_feature"],
                count: splitCount,
                treeIndex: treeIndex,
                field: "split_feature"
            )
            let thresholds = try Self.doubleArray(
                values["threshold"],
                count: splitCount,
                treeIndex: treeIndex,
                field: "threshold"
            )
            let leftChildren = try Self.integerArray(
                values["left_child"],
                count: splitCount,
                treeIndex: treeIndex,
                field: "left_child"
            )
            let rightChildren = try Self.integerArray(
                values["right_child"],
                count: splitCount,
                treeIndex: treeIndex,
                field: "right_child"
            )
            let leafValues = try Self.doubleArray(
                values["leaf_value"],
                count: leafCount,
                treeIndex: treeIndex,
                field: "leaf_value"
            )
            guard splitFeatures.allSatisfy({ featureNames.indices.contains($0) }),
                  leftChildren.allSatisfy({ $0 < splitCount && ($0 >= 0 || -$0 - 1 < leafCount) }),
                  rightChildren.allSatisfy({ $0 < splitCount && ($0 >= 0 || -$0 - 1 < leafCount) }) else {
                throw AUUprightV2TreeModelError.invalidTree(treeIndex, "node index out of range")
            }
            parsedTrees.append(
                AUUprightV2DecisionTree(
                    splitFeatures: splitFeatures,
                    thresholds: thresholds,
                    leftChildren: leftChildren,
                    rightChildren: rightChildren,
                    leafValues: leafValues
                )
            )
        }
        guard !parsedTrees.isEmpty else {
            throw AUUprightV2TreeModelError.invalidHeader("missing trees")
        }
        trees = parsedTrees
    }

    func prediction(features: [Double]) throws -> Double {
        guard features.count == featureNames.count else {
            throw AUUprightV2TreeModelError.featureCount(
                expected: featureNames.count,
                actual: features.count
            )
        }
        guard features.allSatisfy(\.isFinite) else {
            throw AUUprightV2TreeModelError.invalidHeader("features must be finite")
        }
        let raw = trees.reduce(0.0) { $0 + $1.prediction(features: features) }
        switch outputTransform {
        case .identity:
            return raw
        case .logistic:
            if raw >= 0.0 {
                return 1.0 / (1.0 + exp(-raw))
            }
            let exponential = exp(raw)
            return exponential / (1.0 + exponential)
        }
    }

    private static func values(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<separator])
            result[key] = String(line[line.index(after: separator)...])
        }
        return result
    }

    private static func integerArray(
        _ value: String?,
        count: Int,
        treeIndex: Int,
        field: String
    ) throws -> [Int] {
        let result = value?.split(separator: " ").compactMap { Int($0) } ?? []
        guard result.count == count else {
            throw AUUprightV2TreeModelError.invalidTree(
                treeIndex,
                "\(field) expected \(count) values, found \(result.count)"
            )
        }
        return result
    }

    private static func doubleArray(
        _ value: String?,
        count: Int,
        treeIndex: Int,
        field: String
    ) throws -> [Double] {
        let result = value?.split(separator: " ").compactMap { Double($0) } ?? []
        guard result.count == count, result.allSatisfy(\.isFinite) else {
            throw AUUprightV2TreeModelError.invalidTree(
                treeIndex,
                "\(field) expected \(count) finite values, found \(result.count)"
            )
        }
        return result
    }
}

private final class AUUprightV2ResourceAnchor: NSObject {}

enum AUUprightV2Models {
    static let expectedFeatureNames = [
        "term_alignment", "term_consensus", "term_coverage", "term_orthogonality",
        "term_third_axis", "term_camera_prior", "term_crop", "term_jacobian",
        "term_fov", "term_identity", "vertical_strength", "horizontal_strength",
        "crop_scale", "frozen_energy", "best_energy_gap", "frozen_rank_percentile",
        "prepared_line_count", "vp_cluster_count", "vertical_count",
        "vertical_total_length", "vertical_mean_length", "vertical_mean_score",
        "vertical_x_mean", "vertical_y_mean", "vertical_x_std", "vertical_y_std",
        "vertical_cell_coverage", "vertical_bbox_width", "vertical_bbox_height",
        "vertical_axis_alignment", "horizontal_count", "horizontal_total_length",
        "horizontal_mean_length", "horizontal_mean_score", "horizontal_x_mean",
        "horizontal_y_mean", "horizontal_x_std", "horizontal_y_std",
        "horizontal_cell_coverage", "horizontal_bbox_width", "horizontal_bbox_height",
        "horizontal_axis_alignment", "supporter_count_ratio", "supporter_length_ratio",
        "supporter_overlap", "supporter_center_distance", "intersection_finite_ratio",
        "intersection_inside_ratio", "intersection_x_std", "intersection_y_std",
        "intersection_center_distance",
    ]

    static let riskThreshold = 0.2588290335371039

    private static let loaded: Result<(pair: AUUprightV2TreeModel, risk: AUUprightV2TreeModel), Error> = Result {
        let pair = try AUUprightV2TreeModel(contentsOf: try modelURL(filename: "pair-ranker.txt"))
        let risk = try AUUprightV2TreeModel(contentsOf: try modelURL(filename: "risk-model.txt"))
        guard pair.featureNames == expectedFeatureNames, risk.featureNames == expectedFeatureNames else {
            throw AUUprightV2TreeModelError.invalidHeader("feature contract mismatch")
        }
        return (pair, risk)
    }

    static func predictions(features: [Double]) throws -> (rank: Double, risk: Double) {
        let models = try loaded.get()
        return (
            rank: try models.pair.prediction(features: features),
            risk: try models.risk.prediction(features: features)
        )
    }

    private static func modelURL(filename: String) throws -> URL {
        let roots = [
            Bundle(for: AUUprightV2ResourceAnchor.self).resourceURL,
            Bundle.main.resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        ].compactMap { $0 }
        let candidates = roots.flatMap { root in
            [
                root.appendingPathComponent(filename),
                root.appendingPathComponent("UprightV2/\(filename)"),
                root.appendingPathComponent("Plugin/UprightV2/\(filename)"),
                root.appendingPathComponent("AnyUpright/Plugin/UprightV2/\(filename)"),
            ]
        }
        guard let result = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw AUUprightV2TreeModelError.missingBundledModel(filename)
        }
        return result
    }
}
