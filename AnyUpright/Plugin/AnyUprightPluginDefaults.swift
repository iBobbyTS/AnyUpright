//
//  AnyUprightPluginDefaults.swift
//  AnyUpright
//

import Foundation

protocol AUPluginDefaultSettings: Codable, Equatable {
    static var currentSchemaVersion: Int { get }
    static var fileName: String { get }
    static var factoryDefaults: Self { get }

    var schemaVersion: Int { get }
}

struct AUPluginDefaultsEditingState<Settings: Equatable> {
    let factoryDefaults: Settings
    private(set) var saved: Settings
    private(set) var current: Settings

    init(factoryDefaults: Settings, saved: Settings) {
        self.factoryDefaults = factoryDefaults
        self.saved = saved
        current = saved
    }

    var canRestoreFactoryDefaults: Bool {
        current != factoryDefaults
    }

    var canSave: Bool {
        current != saved
    }

    mutating func updateCurrent(_ settings: Settings) {
        current = settings
    }

    mutating func restoreFactoryDefaults() {
        current = factoryDefaults
    }

    mutating func markCurrentAsSaved() {
        saved = current
    }
}

struct AUHorizonDefaultSettings: AUPluginDefaultSettings {
    static let currentSchemaVersion = 1
    static let fileName = "Horizon.plist"
    static let factoryDefaults = AUHorizonDefaultSettings(fillFrame: false)

    let schemaVersion: Int
    var fillFrame: Bool

    init(fillFrame: Bool) {
        schemaVersion = Self.currentSchemaVersion
        self.fillFrame = fillFrame
    }
}

struct AUInnerStretchDefaultSettings: AUPluginDefaultSettings {
    static let currentSchemaVersion = 1
    static let fileName = "InnerStretch.plist"
    static let factoryDefaults = AUInnerStretchDefaultSettings(ratio: .none)

    let schemaVersion: Int
    var ratio: AUStretchRatioMode

    init(ratio: AUStretchRatioMode) {
        schemaVersion = Self.currentSchemaVersion
        self.ratio = ratio
    }
}

struct AUUprightDefaultSettings: AUPluginDefaultSettings {
    static let currentSchemaVersion = 1
    static let fileName = "Upright.plist"
    static let factoryDefaults = AUUprightDefaultSettings(
        direction: .vertical,
        mode: .automatic,
        autoCrop: true
    )

    let schemaVersion: Int
    var direction: UprightCorrectionMode
    var mode: UprightControlMode
    var autoCrop: Bool

    init(direction: UprightCorrectionMode, mode: UprightControlMode, autoCrop: Bool) {
        schemaVersion = Self.currentSchemaVersion
        self.direction = direction
        self.mode = mode
        self.autoCrop = autoCrop
    }
}

final class AUPluginDefaultsStore<Settings: AUPluginDefaultSettings> {
    let fileURL: URL

    private let fileManager: FileManager
    private let lock = NSLock()

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func load() -> Settings {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    func save(_ settings: Settings) throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    func reset() throws {
        try save(Settings.factoryDefaults)
    }

    private func loadUnlocked() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? PropertyListDecoder().decode(Settings.self, from: data),
              settings.schemaVersion == Settings.currentSchemaVersion else {
            return Settings.factoryDefaults
        }
        return settings
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("AnyUpright", isDirectory: true)
            .appendingPathComponent("Defaults", isDirectory: true)
            .appendingPathComponent(Settings.fileName, isDirectory: false)
    }
}

enum AUPluginDefaults {
    static let horizon = AUPluginDefaultsStore<AUHorizonDefaultSettings>()
    static let innerStretch = AUPluginDefaultsStore<AUInnerStretchDefaultSettings>()
    static let upright = AUPluginDefaultsStore<AUUprightDefaultSettings>()
}
