import Foundation

private enum LocalizationTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

private final class EmptyLocalizationBundleToken {}

@main
struct AnyUprightLocalizationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let plugin = root.appendingPathComponent("AnyUpright/Plugin")
        let english = try stringsDictionary(at: plugin.appendingPathComponent("en.lproj/Localizable.strings"))
        let chinese = try stringsDictionary(at: plugin.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))

        try testResourceCompleteness(english: english, chinese: chinese)
        try testFormatPlaceholders(english: english, chinese: chinese)
        try testLanguageSeparation(english: english, chinese: chinese)
        try testBrandNames(plugin: plugin)
        try testEnglishFallback()
        try testStablePopupOrders()
        print("AnyUprightLocalizationTests passed")
    }

    private static func testResourceCompleteness(english: [String: String], chinese: [String: String]) throws {
        try require(Set(english.keys) == Set(chinese.keys), "English and zh-Hans key sets must match")
        try require(Set(english.keys) == Set(AUStringKey.allCases.map(\.rawValue)), "resource keys must exactly match AUStringKey")
        try require(english.values.allSatisfy { !$0.isEmpty }, "English values must be nonempty")
        try require(chinese.values.allSatisfy { !$0.isEmpty }, "zh-Hans values must be nonempty")
        for key in AUStringKey.allCases {
            try require(english[key.rawValue] == key.englishFallback, "English resource must match fallback for \(key.rawValue)")
        }
    }

    private static func testFormatPlaceholders(english: [String: String], chinese: [String: String]) throws {
        for key in AUStringKey.allCases {
            let englishValue = try requireValue(english, key)
            let chineseValue = try requireValue(chinese, key)
            try require(
                placeholders(in: englishValue) == placeholders(in: chineseValue),
                "placeholder mismatch for \(key.rawValue)"
            )
        }
    }

    private static func testLanguageSeparation(english: [String: String], chinese: [String: String]) throws {
        for key in AUStringKey.allCases {
            let englishValue = try requireValue(english, key)
            let chineseValue = try requireValue(chinese, key)
            try require(!containsCJK(englishValue), "English value contains CJK text for \(key.rawValue)")
            try require(englishValue != chineseValue, "zh-Hans value reuses the complete English value for \(key.rawValue)")
        }
    }

    private static func testBrandNames(plugin: URL) throws {
        let english = try stringsDictionary(at: plugin.appendingPathComponent("en.lproj/InfoPlist.strings"))
        let chinese = try stringsDictionary(at: plugin.appendingPathComponent("zh-Hans.lproj/InfoPlist.strings"))
        try require(Set(english.keys) == Set(chinese.keys), "InfoPlist localization key sets must match")
        try require(english == chinese, "AnyUpright product and OSC names must remain English in zh-Hans")
    }

    private static func testEnglishFallback() throws {
        let localizer = AULocalizer(bundle: Bundle(for: EmptyLocalizationBundleToken.self))
        try require(localizer.text(.modelLoading) == "Loading model", "missing resource must use English fallback")
        try require(localizer.format(.guideNumber, 3) == "Guide 3", "formatted fallback must preserve arguments")
    }

    private static func testStablePopupOrders() throws {
        try require([AUStringKey.none, .fit, .fill].map(\.englishFallback) == ["None", "Fit", "Fill"], "Ratio popup order")
        try require([AUStringKey.vertical, .horizontal, .full].map(\.englishFallback) == ["Vertical", "Horizontal", "Full"], "Direction popup order")
        try require([AUStringKey.manual, .semiAuto, .automatic].map(\.englishFallback) == ["Manual", "Auto Detect + Manual Select", "Auto"], "Mode popup order")
    }

    private static func stringsDictionary(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
            throw LocalizationTestFailure.failed("Unable to parse strings table at \(url.path)")
        }
        return dictionary
    }

    private static func placeholders(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:@|d|i|u|f)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            return String(value[swiftRange])
        }
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    private static func requireValue(_ table: [String: String], _ key: AUStringKey) throws -> String {
        guard let value = table[key.rawValue] else {
            throw LocalizationTestFailure.failed("Missing \(key.rawValue)")
        }
        return value
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw LocalizationTestFailure.failed(message) }
    }
}
