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

enum BuildFlavor: String, CaseIterable {
    case debug = "Debug"
    case release = "Release"
}

struct BuildIdentity {
    let flavor: BuildFlavor
    let wrapperBundleIdentifier: String
    let xpcBundleIdentifier: String
    let groupName: String
    let groupUUID: String
    let displayNameKeySuffix: String
    let pluginUUIDs: [String: String]

    static func identity(for flavor: BuildFlavor) -> BuildIdentity {
        switch flavor {
        case .debug:
            return BuildIdentity(
                flavor: flavor,
                wrapperBundleIdentifier: "AnyUpright-Debug",
                xpcBundleIdentifier: "AnyUpright-XPC-Service-Debug",
                groupName: "AnyUpright Debug",
                groupUUID: "00C61B27-8CBC-409D-BACB-CD0E52F6C3C8",
                displayNameKeySuffix: ".Debug",
                pluginUUIDs: [
                    "AnyUprightHorizonPlugIn": "7AC8C310-D0CD-4A33-BCC5-5604D246FEDB",
                    "AnyUprightInnerStretchPlugIn": "2AA478E2-3B35-4EBB-AA1E-3D4633107194",
                    "AnyUprightOuterStretchPlugIn": "4B01F78F-E8A9-4BCA-B488-6DEAA1898F34",
                    "AnyUprightInnerStretchOSCPlugIn": "B8CBF4B9-DCD9-43BA-8CBD-CCD0ED1400DD",
                    "AnyUprightOuterStretchOSCPlugIn": "F5F88B1B-1044-489C-BC1B-05DBEC786FC4",
                    "AnyUprightUprightPlugIn": "DD3A2A86-DE92-45DD-9F04-DDC6A42734E9",
                    "AnyUprightUprightOSCPlugIn": "473FD080-C794-445C-B5F3-B67ABFC36335",
                ]
            )
        case .release:
            return BuildIdentity(
                flavor: flavor,
                wrapperBundleIdentifier: "AnyUpright",
                xpcBundleIdentifier: "AnyUpright-XPC-Service",
                groupName: "AnyUpright",
                groupUUID: "DA62260F-B8B9-498A-A220-E33F20DE872C",
                displayNameKeySuffix: "",
                pluginUUIDs: [
                    "AnyUprightHorizonPlugIn": "2E32E3C2-91C7-44D4-A0AC-0E87832A86A1",
                    "AnyUprightInnerStretchPlugIn": "9BB4C7D9-9384-4C8F-927D-4F716DA78B14",
                    "AnyUprightOuterStretchPlugIn": "81C621CF-4119-46E9-BC04-47A1539A8B54",
                    "AnyUprightInnerStretchOSCPlugIn": "1E97E435-F4A5-4252-8B14-86F44BAD0BF7",
                    "AnyUprightOuterStretchOSCPlugIn": "4CA1AA25-31BD-4AB8-BF52-A379917B80E3",
                    "AnyUprightUprightPlugIn": "A8F7169F-B5C7-44EB-B0AD-5F9178DCE9AB",
                    "AnyUprightUprightOSCPlugIn": "FEF0BD6C-BB81-4E37-B5BD-8C163FBB7782",
                ]
            )
        }
    }

    var buildSettingReplacements: [String: String] {
        [
            "$(AU_PLUGIN_GROUP_NAME)": groupName,
            "$(AU_PLUGIN_GROUP_UUID)": groupUUID,
            "$(AU_PLUGIN_NAME_KEY_SUFFIX)": displayNameKeySuffix,
            "$(AU_HORIZON_PLUGIN_UUID)": uuid(for: "AnyUprightHorizonPlugIn"),
            "$(AU_INNER_STRETCH_PLUGIN_UUID)": uuid(for: "AnyUprightInnerStretchPlugIn"),
            "$(AU_OUTER_STRETCH_PLUGIN_UUID)": uuid(for: "AnyUprightOuterStretchPlugIn"),
            "$(AU_INNER_STRETCH_OSC_UUID)": uuid(for: "AnyUprightInnerStretchOSCPlugIn"),
            "$(AU_OUTER_STRETCH_OSC_UUID)": uuid(for: "AnyUprightOuterStretchOSCPlugIn"),
            "$(AU_UPRIGHT_PLUGIN_UUID)": uuid(for: "AnyUprightUprightPlugIn"),
            "$(AU_UPRIGHT_OSC_UUID)": uuid(for: "AnyUprightUprightOSCPlugIn"),
        ]
    }

    func uuid(for className: String) -> String {
        pluginUUIDs[className] ?? ""
    }
}

struct ExpectedPlugin {
    let className: String
    let displayNameKey: String
    let descriptionKey: String
    let protocols: Set<String>
    let localizedDisplayName: String
    let localizedDescriptions: [String: String]
    let supportedPluginClasses: Set<String>
}

struct ValidateFxPlugManifest {
    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath)
        let sourceInfoPlist = root.appendingPathComponent("AnyUpright/Plugin/Info.plist")
        let localizedTables = try loadLocalizedTables(root: root)

        if arguments.count == 1 || arguments.isEmpty {
            let sourcePlist = try dictionaryPlist(at: sourceInfoPlist)
            for flavor in BuildFlavor.allCases {
                let identity = BuildIdentity.identity(for: flavor)
                guard let expanded = replaceBuildSettings(
                    in: sourcePlist,
                    replacements: identity.buildSettingReplacements
                ) as? [String: Any] else {
                    throw ManifestValidationFailure.failed("Expected expanded manifest to remain a dictionary")
                }
                try validate(plist: expanded, identity: identity, localizedTables: localizedTables)
            }
            let serialized = String(data: try Data(contentsOf: sourceInfoPlist), encoding: .utf8) ?? ""
            try assertTrue(!serialized.localizedCaseInsensitiveContains("brightness"), "Info.plist should not contain template brightness entries")
            print("AnyUpright FxPlug Debug and Release manifest template validation passed")
            return
        }

        guard arguments.count == 4,
              let flavor = BuildFlavor(rawValue: arguments[1]) else {
            throw ManifestValidationFailure.failed(
                "Usage: validate-fxplug-manifest ROOT [Debug|Release XPC_INFO_PLIST WRAPPER_INFO_PLIST]"
            )
        }

        let identity = BuildIdentity.identity(for: flavor)
        let xpcPlist = try dictionaryPlist(at: URL(fileURLWithPath: arguments[2]))
        let wrapperPlist = try dictionaryPlist(at: URL(fileURLWithPath: arguments[3]))
        try validate(plist: xpcPlist, identity: identity, localizedTables: localizedTables)
        try assertEqual(xpcPlist["CFBundleIdentifier"] as? String, identity.xpcBundleIdentifier, "\(flavor.rawValue) XPC bundle identifier")
        try assertEqual(wrapperPlist["CFBundleIdentifier"] as? String, identity.wrapperBundleIdentifier, "\(flavor.rawValue) wrapper bundle identifier")
        print("AnyUpright FxPlug \(flavor.rawValue) build identity validation passed")
    }

    private static func validate(
        plist: [String: Any],
        identity: BuildIdentity,
        localizedTables: [String: (displayNames: [String: Any], descriptions: [String: Any])]
    ) throws {
        let expected = expectedPlugins(identity: identity)
        let groupList = try requireArray(plist["ProPlugPlugInGroupList"], "ProPlugPlugInGroupList")
        try assertTrue(
            groupList.contains {
                guard let group = $0 as? [String: Any] else { return false }
                return group["uuid"] as? String == identity.groupUUID
                    && group["groupName"] as? String == identity.groupName
            },
            "Expected \(identity.flavor.rawValue) plugin group \(identity.groupUUID)"
        )

        let pluginList = try requireArray(plist["ProPlugPlugInList"], "ProPlugPlugInList")
        try assertEqual(pluginList.count, expected.count, "\(identity.flavor.rawValue) registered plugin count")
        let pluginDictionaries = try pluginList.map { item -> [String: Any] in
            guard let dictionary = item as? [String: Any] else {
                throw ManifestValidationFailure.failed("Expected plugin list item to be a dictionary")
            }
            return dictionary
        }
        let pluginsByClass = Dictionary(uniqueKeysWithValues: pluginDictionaries.compactMap { dictionary -> (String, [String: Any])? in
            guard let className = dictionary["className"] as? String else { return nil }
            return (className, dictionary)
        })

        try assertEqual(pluginsByClass.count, expected.count, "\(identity.flavor.rawValue) unique plugin class count")
        try assertEqual(Set(pluginDictionaries.compactMap { $0["uuid"] as? String }).count, expected.count, "\(identity.flavor.rawValue) unique plugin UUID count")

        for item in expected {
            guard let plugin = pluginsByClass[item.className] else {
                throw ManifestValidationFailure.failed("Missing plugin class \(item.className)")
            }
            try assertEqual(plugin["uuid"] as? String, identity.uuid(for: item.className), "\(item.className) UUID")
            try assertEqual(plugin["group"] as? String, identity.groupUUID, "\(item.className) group")
            try assertEqual(plugin["displayName"] as? String, item.displayNameKey, "\(item.className) display key")
            try assertEqual(plugin["infoString"] as? String, item.descriptionKey, "\(item.className) description key")
            try assertEqual(Set(try requireStringArray(plugin["protocolNames"], "\(item.className) protocolNames")), item.protocols, "\(item.className) protocols")
            let expectedSupported = Set(item.supportedPluginClasses.map { identity.uuid(for: $0) })
            try assertEqual(Set(plugin["supportedPlugins"] as? [String] ?? []), expectedSupported, "\(item.className) supported plugins")

            for locale in ["en", "zh-Hans"] {
                guard let tables = localizedTables[locale],
                      let expectedDescription = item.localizedDescriptions[locale] else {
                    throw ManifestValidationFailure.failed("Missing expected localization data for \(locale)")
                }
                try assertEqual(tables.displayNames[item.displayNameKey] as? String, item.localizedDisplayName, "\(item.className) \(locale) localized display name")
                try assertEqual(tables.descriptions[item.descriptionKey] as? String, expectedDescription, "\(item.className) \(locale) localized description")
            }
        }

        let englishDisplayKeys = Set(localizedTables["en"]?.displayNames.keys.map { $0 } ?? [])
        let chineseDisplayKeys = Set(localizedTables["zh-Hans"]?.displayNames.keys.map { $0 } ?? [])
        try assertEqual(chineseDisplayKeys, englishDisplayKeys, "localized display-name key set")
    }

    private static func expectedPlugins(identity: BuildIdentity) -> [ExpectedPlugin] {
        let suffix = identity.displayNameKeySuffix
        let debugNameSuffix = identity.flavor == .debug ? " (Debug)" : ""
        return [
            ExpectedPlugin(className: "AnyUprightHorizonPlugIn", displayNameKey: "AnyUpright::Horizon Name\(suffix)", descriptionKey: "AnyUpright::Horizon Description", protocols: ["FxFilter", "FxAnalyzer"], localizedDisplayName: "AnyUpright Horizon\(debugNameSuffix)", localizedDescriptions: ["en": "Automatic or manual leveling, with automatic canvas fill after rotation.", "zh-Hans": "自动或手动水平，旋转后自动填充画布。"], supportedPluginClasses: []),
            ExpectedPlugin(className: "AnyUprightInnerStretchPlugIn", displayNameKey: "AnyUpright::Inner Stretch Name\(suffix)", descriptionKey: "AnyUpright::Inner Stretch Description", protocols: ["FxFilter"], localizedDisplayName: "AnyUpright Inner Stretch\(debugNameSuffix)", localizedDescriptions: ["en": "Select an area of the input image and stretch it to fill the frame, similar to a document scanning app.", "zh-Hans": "选择输入画面中的区域，并将其拉伸到完整画面。（类似文档扫描app）"], supportedPluginClasses: []),
            ExpectedPlugin(className: "AnyUprightOuterStretchPlugIn", displayNameKey: "AnyUpright::Outer Stretch Name\(suffix)", descriptionKey: "AnyUpright::Outer Stretch Description", protocols: ["FxFilter"], localizedDisplayName: "AnyUpright Outer Stretch\(debugNameSuffix)", localizedDescriptions: ["en": "Drag the four corners of the output image to stretch it, similar to Final Cut Pro's built-in Transform effect.", "zh-Hans": "拖动输出画面的四角以拉伸。（类似Final Cut Pro自带的“变换”）"], supportedPluginClasses: []),
            ExpectedPlugin(className: "AnyUprightInnerStretchOSCPlugIn", displayNameKey: "AnyUpright::Inner Stretch OSC Name\(suffix)", descriptionKey: "AnyUpright::Inner Stretch OSC Description", protocols: ["FxOnScreenControl"], localizedDisplayName: "AnyUpright Inner Stretch Controls\(debugNameSuffix)", localizedDescriptions: ["en": "Onscreen input selection controls for AnyUpright Inner Stretch.", "zh-Hans": "AnyUpright Inner Stretch 的屏幕选区控制。"], supportedPluginClasses: ["AnyUprightInnerStretchPlugIn"]),
            ExpectedPlugin(className: "AnyUprightOuterStretchOSCPlugIn", displayNameKey: "AnyUpright::Outer Stretch OSC Name\(suffix)", descriptionKey: "AnyUpright::Outer Stretch OSC Description", protocols: ["FxOnScreenControl"], localizedDisplayName: "AnyUpright Outer Stretch Controls\(debugNameSuffix)", localizedDescriptions: ["en": "Onscreen outer corner controls for AnyUpright Outer Stretch.", "zh-Hans": "AnyUpright Outer Stretch 的屏幕外角控制。"], supportedPluginClasses: ["AnyUprightOuterStretchPlugIn"]),
            ExpectedPlugin(className: "AnyUprightUprightPlugIn", displayNameKey: "AnyUpright::Upright Name\(suffix)", descriptionKey: "AnyUpright::Upright Description", protocols: ["FxFilter", "FxAnalyzer"], localizedDisplayName: "AnyUpright Upright\(debugNameSuffix)", localizedDescriptions: ["en": "Lightroom-style Upright perspective correction with vertical-only, horizontal-only, and full correction, plus manual, auto-detect with manual selection, and fully automatic modes.", "zh-Hans": "类似 Lightroom 的Upright透视校正。可选择仅纵向、仅横向和全向；手动、自动识别+手动选择、全自动模式。"], supportedPluginClasses: []),
            ExpectedPlugin(className: "AnyUprightUprightOSCPlugIn", displayNameKey: "AnyUpright::Upright OSC Name\(suffix)", descriptionKey: "AnyUpright::Upright OSC Description", protocols: ["FxOnScreenControl"], localizedDisplayName: "AnyUpright Upright Controls\(debugNameSuffix)", localizedDescriptions: ["en": "Onscreen guide and candidate line controls for AnyUpright Upright.", "zh-Hans": "AnyUpright Upright 的屏幕辅助线和候选线控制。"], supportedPluginClasses: ["AnyUprightUprightPlugIn", "AnyUprightHorizonPlugIn"]),
        ]
    }

    private static func loadLocalizedTables(root: URL) throws -> [String: (displayNames: [String: Any], descriptions: [String: Any])] {
        try Dictionary(uniqueKeysWithValues: ["en", "zh-Hans"].map { locale in
            let directory = root.appendingPathComponent("AnyUpright/Plugin/\(locale).lproj")
            return (locale, (
                displayNames: try dictionaryPlist(at: directory.appendingPathComponent("InfoPlist.strings")),
                descriptions: try dictionaryPlist(at: directory.appendingPathComponent("Localizable.strings"))
            ))
        })
    }

    private static func replaceBuildSettings(in value: Any, replacements: [String: String]) -> Any {
        if let string = value as? String {
            return replacements.reduce(string) { partial, replacement in
                partial.replacingOccurrences(of: replacement.key, with: replacement.value)
            }
        }
        if let array = value as? [Any] {
            return array.map { replaceBuildSettings(in: $0, replacements: replacements) }
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues { replaceBuildSettings(in: $0, replacements: replacements) }
        }
        return value
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
        guard value else { throw ManifestValidationFailure.failed(label) }
    }
}

do {
    try ValidateFxPlugManifest.run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
