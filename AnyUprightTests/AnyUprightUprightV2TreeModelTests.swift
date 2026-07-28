import Foundation

private enum AUUprightV2TreeTestFailure: Error {
    case failed(String)
}

private struct AUUprightV2TreeFixture: Decodable {
    struct Case: Decodable {
        var features: [Double]
        var pairScore: Double
        var riskProbability: Double

        enum CodingKeys: String, CodingKey {
            case features
            case pairScore = "pair_score"
            case riskProbability = "risk_probability"
        }
    }

    var featureNames: [String]
    var cases: [Case]

    enum CodingKeys: String, CodingKey {
        case featureNames = "feature_names"
        case cases
    }
}

@main
private enum AnyUprightUprightV2TreeModelTests {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw AUUprightV2TreeTestFailure.failed(
                "usage: test pair-ranker.txt risk-model.txt parity.json"
            )
        }
        let pair = try AUUprightV2TreeModel(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let risk = try AUUprightV2TreeModel(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        let fixture = try JSONDecoder().decode(
            AUUprightV2TreeFixture.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        )
        try require(pair.featureNames == fixture.featureNames, "pair feature contract")
        try require(risk.featureNames == fixture.featureNames, "risk feature contract")
        try require(fixture.cases.count >= 10, "fixture coverage")

        for (index, item) in fixture.cases.enumerated() {
            let pairPrediction = try pair.prediction(features: item.features)
            let riskPrediction = try risk.prediction(features: item.features)
            try require(
                abs(pairPrediction - item.pairScore) <= 1e-12,
                "pair prediction \(index): \(pairPrediction) != \(item.pairScore)"
            )
            try require(
                abs(riskPrediction - item.riskProbability) <= 1e-12,
                "risk prediction \(index): \(riskPrediction) != \(item.riskProbability)"
            )
        }

        do {
            _ = try pair.prediction(features: [0.0])
            throw AUUprightV2TreeTestFailure.failed("feature count should be validated")
        } catch is AUUprightV2TreeModelError {
        }
        print("AnyUprightUprightV2TreeModelTests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw AUUprightV2TreeTestFailure.failed(message)
        }
    }
}
