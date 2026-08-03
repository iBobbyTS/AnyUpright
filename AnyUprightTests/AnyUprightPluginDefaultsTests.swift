import Foundation

private enum PluginDefaultsTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct AnyUprightPluginDefaultsTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnyUprightPluginDefaultsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try testFactoryDefaults(root: root)
        try testIndependentRoundTrips(root: root)
        try testInvalidFilesFailClosed(root: root)
        try testEditingStateTransitions()
        print("AnyUprightPluginDefaultsTests passed")
    }

    private static func testFactoryDefaults(root: URL) throws {
        let horizon = horizonStore(root)
        let innerStretch = innerStretchStore(root)
        let upright = uprightStore(root)

        try require(horizon.load() == .factoryDefaults, "Horizon missing-file default")
        try require(innerStretch.load() == .factoryDefaults, "Inner Stretch missing-file default")
        try require(upright.load() == .factoryDefaults, "Upright missing-file default")
    }

    private static func testIndependentRoundTrips(root: URL) throws {
        let horizon = horizonStore(root)
        let innerStretch = innerStretchStore(root)
        let upright = uprightStore(root)

        try horizon.save(AUHorizonDefaultSettings(fillFrame: true))
        try innerStretch.save(AUInnerStretchDefaultSettings(ratio: .fill))
        try upright.save(AUUprightDefaultSettings(
            direction: .full,
            mode: .semiAutomatic,
            autoCrop: false
        ))

        try require(horizon.load().fillFrame, "Horizon persisted Fill Frame")
        try require(innerStretch.load().ratio == .fill, "Inner Stretch persisted Ratio")
        let uprightValue = upright.load()
        try require(uprightValue.direction == .full, "Upright persisted Direction")
        try require(uprightValue.mode == .semiAutomatic, "Upright persisted Mode")
        try require(!uprightValue.autoCrop, "Upright persisted Auto Crop")

        try horizon.reset()
        try require(horizon.load() == .factoryDefaults, "Horizon reset")
        try require(innerStretch.load().ratio == .fill, "Horizon reset leaves Inner Stretch unchanged")
        try require(upright.load().direction == .full, "Horizon reset leaves Upright unchanged")
    }

    private static func testInvalidFilesFailClosed(root: URL) throws {
        let corruptURL = root.appendingPathComponent("Corrupt.plist")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: corruptURL)
        let corruptStore = AUPluginDefaultsStore<AUHorizonDefaultSettings>(fileURL: corruptURL)
        try require(corruptStore.load() == .factoryDefaults, "corrupt plist fallback")

        let staleURL = root.appendingPathComponent("Stale.plist")
        let stale: [String: Any] = ["schemaVersion": 999, "fillFrame": true]
        let staleData = try PropertyListSerialization.data(fromPropertyList: stale, format: .xml, options: 0)
        try staleData.write(to: staleURL)
        let staleStore = AUPluginDefaultsStore<AUHorizonDefaultSettings>(fileURL: staleURL)
        try require(staleStore.load() == .factoryDefaults, "unknown schema fallback")
    }

    private static func testEditingStateTransitions() throws {
        let factory = AUHorizonDefaultSettings.factoryDefaults
        let custom = AUHorizonDefaultSettings(fillFrame: true)
        var state = AUPluginDefaultsEditingState(factoryDefaults: factory, saved: custom)

        try require(state.current == custom, "editing state starts from saved settings")
        try require(state.canRestoreFactoryDefaults, "custom saved value can restore")
        try require(!state.canSave, "unchanged saved value cannot save")

        state.restoreFactoryDefaults()
        try require(state.current == factory, "restore changes only current settings")
        try require(!state.canRestoreFactoryDefaults, "factory current value cannot restore")
        try require(state.canSave, "restored current value remains unsaved")
        try require(state.saved == custom, "restore does not overwrite saved snapshot")

        state.markCurrentAsSaved()
        try require(!state.canSave, "saved current value cannot save again")
        try require(state.saved == factory, "save advances saved snapshot")

        state.updateCurrent(custom)
        try require(state.canRestoreFactoryDefaults, "edited custom value can restore")
        try require(state.canSave, "edited custom value can save")

        state.updateCurrent(factory)
        try require(!state.canRestoreFactoryDefaults, "returning to factory disables restore")
        try require(!state.canSave, "returning to saved value disables save")
    }

    private static func horizonStore(_ root: URL) -> AUPluginDefaultsStore<AUHorizonDefaultSettings> {
        AUPluginDefaultsStore(fileURL: root.appendingPathComponent(AUHorizonDefaultSettings.fileName))
    }

    private static func innerStretchStore(_ root: URL) -> AUPluginDefaultsStore<AUInnerStretchDefaultSettings> {
        AUPluginDefaultsStore(fileURL: root.appendingPathComponent(AUInnerStretchDefaultSettings.fileName))
    }

    private static func uprightStore(_ root: URL) -> AUPluginDefaultsStore<AUUprightDefaultSettings> {
        AUPluginDefaultsStore(fileURL: root.appendingPathComponent(AUUprightDefaultSettings.fileName))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PluginDefaultsTestFailure.failed(message) }
    }
}
