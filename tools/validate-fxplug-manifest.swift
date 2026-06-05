//
//  validate-fxplug-manifest.swift
//  AnyUpright
//

import Foundation

enum ManifestValidationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

struct ExpectedPlugin {
    var className: String
    var displayNameKey: String
    var descriptionKey: String
    var uuid: String
    var protocols: Set<String>
    var localizedDisplayName: String
    var localizedDescription: String
}

struct ValidateFxPlugManifest {
    static func run() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let infoPlist = root.appendingPathComponent("AnyUpright/Plugin/Info.plist")
        let infoStrings = root.appendingPathComponent("AnyUpright/Plugin/en.lproj/InfoPlist.strings")
        let localizableStrings = root.appendingPathComponent("AnyUpright/Plugin/en.lproj/Localizable.strings")

        let plist = try dictionaryPlist(at: infoPlist)
        let displayNames = try dictionaryPlist(at: infoStrings)
        let descriptions = try dictionaryPlist(at: localizableStrings)

        let expectedGroup = "DA62260F-B8B9-498A-A220-E33F20DE872C"
        let expected = [
            ExpectedPlugin(
                className: "AnyUprightHorizonManualPlugIn",
                displayNameKey: "AnyUpright::Horizon Manual Name",
                descriptionKey: "AnyUpright::Horizon Manual Description",
                uuid: "2E32E3C2-91C7-44D4-A0AC-0E87832A86A1",
                protocols: ["FxFilter", "FxAnalyzer"],
                localizedDisplayName: "AnyUpright Horizon Manual",
                localizedDescription: "Automatic horizon correction with manual rotation and optional fill."
            ),
            ExpectedPlugin(
                className: "AnyUprightQuadManualPlugIn",
                displayNameKey: "AnyUpright::Quad Manual Name",
                descriptionKey: "AnyUpright::Quad Manual Description",
                uuid: "9BB4C7D9-9384-4C8F-927D-4F716DA78B14",
                protocols: ["FxFilter", "FxOnScreenControl"],
                localizedDisplayName: "AnyUpright Quad Manual",
                localizedDescription: "Manual four-corner source and output perspective correction."
            ),
            ExpectedPlugin(
                className: "AnyUprightUprightManualPlugIn",
                displayNameKey: "AnyUpright::Upright Manual Name",
                descriptionKey: "AnyUpright::Upright Manual Description",
                uuid: "A8F7169F-B5C7-44EB-B0AD-5F9178DCE9AB",
                protocols: ["FxFilter", "FxAnalyzer", "FxOnScreenControl"],
                localizedDisplayName: "AnyUpright Upright Manual",
                localizedDescription: "Lightroom-style manual, guided, automatic, and semi-automatic upright correction."
            )
        ]

        let groupList = try requireArray(plist["ProPlugPlugInGroupList"], "ProPlugPlugInGroupList")
        try assertTrue(
            groupList.contains { ($0 as? [String: Any])?["uuid"] as? String == expectedGroup },
            "Expected AnyUpright plugin group \(expectedGroup)"
        )

        let pluginList = try requireArray(plist["ProPlugPlugInList"], "ProPlugPlugInList")
        try assertEqual(pluginList.count, expected.count, "registered plugin count")

        let pluginDictionaries = try pluginList.map { item -> [String: Any] in
            guard let dictionary = item as? [String: Any] else {
                throw ManifestValidationFailure.failed("Expected plugin list item to be a dictionary")
            }
            return dictionary
        }
        let pluginsByClass = Dictionary(uniqueKeysWithValues: pluginDictionaries.compactMap { dictionary -> (String, [String: Any])? in
            guard let className = dictionary["className"] as? String else {
                return nil
            }
            return (className, dictionary)
        })

        try assertEqual(pluginsByClass.count, expected.count, "unique plugin class count")
        try assertEqual(Set(pluginDictionaries.compactMap { $0["uuid"] as? String }).count, expected.count, "unique plugin UUID count")

        for item in expected {
            guard let plugin = pluginsByClass[item.className] else {
                throw ManifestValidationFailure.failed("Missing plugin class \(item.className)")
            }
            try assertEqual(plugin["uuid"] as? String, item.uuid, "\(item.className) UUID")
            try assertEqual(plugin["group"] as? String, expectedGroup, "\(item.className) group")
            try assertEqual(plugin["displayName"] as? String, item.displayNameKey, "\(item.className) display key")
            try assertEqual(plugin["infoString"] as? String, item.descriptionKey, "\(item.className) description key")
            try assertEqual(Set(try requireStringArray(plugin["protocolNames"], "\(item.className) protocolNames")), item.protocols, "\(item.className) protocols")
            try assertEqual(displayNames[item.displayNameKey] as? String, item.localizedDisplayName, "\(item.className) localized display name")
            try assertEqual(descriptions[item.descriptionKey] as? String, item.localizedDescription, "\(item.className) localized description")
        }

        let serialized = String(data: try Data(contentsOf: infoPlist), encoding: .utf8) ?? ""
        try assertTrue(!serialized.localizedCaseInsensitiveContains("brightness"), "Info.plist should not contain template brightness entries")

        print("AnyUpright FxPlug manifest validation passed")
    }

    private static func dictionaryPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw ManifestValidationFailure.failed("Expected dictionary plist at \(url.path)")
        }
        return dictionary
    }

    private static func requireArray(_ value: Any?, _ label: String) throws -> [Any] {
        guard let array = value as? [Any] else {
            throw ManifestValidationFailure.failed("Expected array for \(label)")
        }
        return array
    }

    private static func requireStringArray(_ value: Any?, _ label: String) throws -> [String] {
        guard let array = value as? [String] else {
            throw ManifestValidationFailure.failed("Expected string array for \(label)")
        }
        return array
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else {
            throw ManifestValidationFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func assertTrue(_ value: Bool, _ label: String) throws {
        guard value else {
            throw ManifestValidationFailure.failed(label)
        }
    }
}

do {
    try ValidateFxPlugManifest.run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
