//
//  AnyUprightPluginDefaultsUI.swift
//  AnyUpright
//

import AppKit
import Foundation

private final class AUPluginDefaultsLocalizationToken {}

enum AUPluginDefaultsDiagnostics {
    static let logPath = "/tmp/AnyUprightPluginDefaults.log"

    private static let lock = NSLock()

    static func log(_ message: String) {
        NSLog("AnyUpright Defaults: %@", message)
        let timestamp = String(format: "%.6f", Date().timeIntervalSince1970)
        let thread = Thread.isMainThread ? "main" : "background"
        let line = "[\(timestamp)] build=defaults-diagnostics-v2 pid=\(ProcessInfo.processInfo.processIdentifier) thread=\(thread) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        let url = URL(fileURLWithPath: logPath)
        if FileManager.default.fileExists(atPath: logPath),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private func defaultsLocalized(_ key: String, fallback: String) -> String {
    Bundle(for: AUPluginDefaultsLocalizationToken.self).localizedString(
        forKey: key,
        value: fallback,
        table: nil
    )
}

protocol AUPluginDefaultsEditor: AnyObject {
    var title: String { get }
    var contentView: NSView { get }
    var canRestoreFactoryDefaults: Bool { get }
    var canSave: Bool { get }
    var onChange: (() -> Void)? { get set }

    func beginEditingSession()
    func save() throws
    func restoreFactoryDefaults()
}

private final class AUPluginDefaultsEditorSession<Settings: AUPluginDefaultSettings> {
    private let store: AUPluginDefaultsStore<Settings>
    private var state: AUPluginDefaultsEditingState<Settings>

    var onChange: (() -> Void)?
    var canRestoreFactoryDefaults: Bool { state.canRestoreFactoryDefaults }
    var canSave: Bool { state.canSave }

    init(store: AUPluginDefaultsStore<Settings>) {
        self.store = store
        state = AUPluginDefaultsEditingState(
            factoryDefaults: Settings.factoryDefaults,
            saved: Settings.factoryDefaults
        )
    }

    func beginEditingSession() -> Settings {
        let saved = store.load()
        state = AUPluginDefaultsEditingState(
            factoryDefaults: Settings.factoryDefaults,
            saved: saved
        )
        return state.current
    }

    func updateCurrent(_ settings: Settings) {
        state.updateCurrent(settings)
        onChange?()
    }

    func save(_ settings: Settings) throws {
        state.updateCurrent(settings)
        try store.save(state.current)
        state.markCurrentAsSaved()
        onChange?()
    }

    func restoreFactoryDefaults() -> Settings {
        state.restoreFactoryDefaults()
        onChange?()
        return state.current
    }
}

enum AUPluginDefaultsForm {
    static func labeledRow(label: String, control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.setContentHuggingPriority(.required, for: .horizontal)
        labelView.widthAnchor.constraint(equalToConstant: 112.0).isActive = true

        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12.0
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    static func popup(entries: [(String, Int)]) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for entry in entries {
            let item = NSMenuItem(title: entry.0, action: nil, keyEquivalent: "")
            item.tag = entry.1
            popup.menu?.addItem(item)
        }
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 180.0).isActive = true
        return popup
    }

    static func select(tag: Int, in popup: NSPopUpButton) {
        guard let item = popup.itemArray.first(where: { $0.tag == tag }) else {
            return
        }
        popup.select(item)
    }
}

private enum AUPluginDefaultsRemoteWindowMount {
    static func attach(
        rootView: NSView,
        to callbackParentView: NSView,
        identifier: NSUserInterfaceItemIdentifier
    ) -> NSView {
        precondition(Thread.isMainThread, "Plugin defaults UI must be attached on the main thread")

        let hostView = callbackParentView.superview ?? callbackParentView
        hostView.subviews
            .filter { $0.identifier == identifier }
            .forEach { $0.removeFromSuperview() }

        rootView.identifier = identifier
        rootView.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(rootView)
        NSLayoutConstraint.activate([
            rootView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            rootView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            rootView.topAnchor.constraint(equalTo: hostView.topAnchor),
            rootView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])
        hostView.layoutSubtreeIfNeeded()
        return hostView
    }
}

final class AUPluginDefaultsWindowPresenter {
    private static let rootIdentifier = NSUserInterfaceItemIdentifier("AnyUpright.PluginDefaults.Root")
    private static let contentSize = CGSize(width: 480.0, height: 260.0)

    private let stateLock = NSLock()
    private var requestPending = false
    private var nextRequestID: UInt64 = 0
    private weak var activeHostView: NSView?
    private var viewController: AUPluginDefaultsViewController?

    func present(remoteWindowAPI: FxRemoteWindowAPI, editor: AUPluginDefaultsEditor) {
        precondition(Thread.isMainThread, "Plugin defaults UI must be presented on the main thread")

        if let activeHostView,
           let activeWindow = activeHostView.window,
           activeWindow.isVisible {
            AUPluginDefaultsDiagnostics.log(
                "present reused presenter=\(ObjectIdentifier(self)) editor=\(editor.title)"
            )
            activeWindow.makeKeyAndOrderFront(nil)
            return
        }
        activeHostView = nil

        stateLock.lock()
        guard !requestPending else {
            stateLock.unlock()
            AUPluginDefaultsDiagnostics.log(
                "present ignored reason=request-pending presenter=\(ObjectIdentifier(self)) editor=\(editor.title)"
            )
            return
        }
        requestPending = true
        nextRequestID &+= 1
        let requestID = nextRequestID
        stateLock.unlock()

        AUPluginDefaultsDiagnostics.log(
            "present begin request=\(requestID) presenter=\(ObjectIdentifier(self)) editor=\(editor.title) api=\(String(describing: type(of: remoteWindowAPI)))"
        )
        editor.beginEditingSession()
        AUPluginDefaultsDiagnostics.log("present reloaded request=\(requestID) editor=\(editor.title)")
        remoteWindowAPI.remoteWindow(of: Self.contentSize) { [weak self] parentView, error in
            AUPluginDefaultsDiagnostics.log(
                "present callback received request=\(requestID) presenterAlive=\(self != nil) parentProvided=\(parentView != nil) error=\(String(describing: error))"
            )

            guard let self else {
                return
            }

            DispatchQueue.main.async {
                self.stateLock.lock()
                self.requestPending = false
                self.stateLock.unlock()

                guard let parentView else {
                    AUPluginDefaultsDiagnostics.log(
                        "present callback failed request=\(requestID) error=\(String(describing: error))"
                    )
                    if let error {
                        NSLog("AnyUpright defaults window error: %@", error.localizedDescription)
                    }
                    return
                }

                let hostView = parentView.superview ?? parentView
                AUPluginDefaultsDiagnostics.log(
                    "present attach begin request=\(requestID) parentFrame=\(NSStringFromRect(parentView.frame)) parentBounds=\(NSStringFromRect(parentView.bounds)) parentSubviews=\(parentView.subviews.count) hostIsSuperview=\(hostView !== parentView) hostFrame=\(NSStringFromRect(hostView.frame)) hostBounds=\(NSStringFromRect(hostView.bounds)) hostSubviews=\(hostView.subviews.count)"
                )
                let controller = AUPluginDefaultsViewController(editor: editor)
                self.viewController = controller
                let rootView = controller.view
                let mountedHostView = AUPluginDefaultsRemoteWindowMount.attach(
                    rootView: rootView,
                    to: parentView,
                    identifier: Self.rootIdentifier
                )
                self.activeHostView = mountedHostView
                AUPluginDefaultsDiagnostics.log(
                    "present attach end request=\(requestID) rootFrame=\(NSStringFromRect(rootView.frame)) hostBounds=\(NSStringFromRect(mountedHostView.bounds)) hostSubviews=\(mountedHostView.subviews.count)"
                )
            }
        }
        AUPluginDefaultsDiagnostics.log("present submitted request=\(requestID)")
    }
}

private final class AUPluginDefaultsViewController: NSViewController {
    private static let contentInset = 20.0
    private static let contentToFooterSpacing = 20.0
    private static let actionSpacing = 10.0

    private let editor: AUPluginDefaultsEditor
    private let statusLabel = NSTextField(labelWithString: "")
    private lazy var resetButton = NSButton(
        title: defaultsLocalized(
            "AnyUpright::Defaults Restore Factory",
            fallback: "Restore Factory Defaults"
        ),
        target: self,
        action: #selector(restoreFactoryDefaults)
    )
    private lazy var saveButton = NSButton(
        title: defaultsLocalized("AnyUpright::Defaults Save", fallback: "Save"),
        target: self,
        action: #selector(save)
    )

    init(editor: AUPluginDefaultsEditor) {
        self.editor = editor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0.0, y: 0.0, width: 480.0, height: 260.0))
        self.view = rootView

        let titleLabel = NSTextField(labelWithString: editor.title)
        titleLabel.font = NSFont.systemFont(ofSize: 17.0, weight: .semibold)

        let scopeLabel = NSTextField(wrappingLabelWithString: defaultsLocalized(
            "AnyUpright::Defaults New Instances Only",
            fallback: "Default parameter values apply only to new filter instances."
        ))
        scopeLabel.textColor = .secondaryLabelColor

        let contentStack = NSStackView(views: [titleLabel, scopeLabel, editor.contentView])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14.0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.setContentHuggingPriority(.required, for: .vertical)
        contentStack.setContentCompressionResistancePriority(.required, for: .vertical)
        editor.contentView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        saveButton.keyEquivalent = "\r"
        resetButton.setContentHuggingPriority(.required, for: .horizontal)
        resetButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        saveButton.setContentHuggingPriority(.required, for: .horizontal)
        saveButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let footerStack = NSStackView(views: [statusLabel, resetButton, saveButton])
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = Self.actionSpacing
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        footerStack.setContentHuggingPriority(.required, for: .vertical)
        footerStack.setContentCompressionResistancePriority(.required, for: .vertical)

        let flexibleSpacer = NSView()
        flexibleSpacer.translatesAutoresizingMaskIntoConstraints = false
        flexibleSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        flexibleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let layoutStack = NSStackView(views: [contentStack, flexibleSpacer, footerStack])
        layoutStack.orientation = .vertical
        layoutStack.alignment = .leading
        layoutStack.distribution = .fill
        layoutStack.spacing = 0.0
        layoutStack.setCustomSpacing(Self.contentToFooterSpacing, after: contentStack)
        layoutStack.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(layoutStack)
        NSLayoutConstraint.activate([
            layoutStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Self.contentInset),
            layoutStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Self.contentInset),
            layoutStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Self.contentInset),
            layoutStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -Self.contentInset),

            contentStack.widthAnchor.constraint(equalTo: layoutStack.widthAnchor),
            flexibleSpacer.widthAnchor.constraint(equalTo: layoutStack.widthAnchor),
            footerStack.widthAnchor.constraint(equalTo: layoutStack.widthAnchor),
            editor.contentView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])

        editor.onChange = { [weak self] in
            self?.editorDidChange()
        }
        updateActionState()
    }

    private func editorDidChange() {
        statusLabel.stringValue = ""
        updateActionState()
    }

    private func updateActionState() {
        resetButton.isEnabled = editor.canRestoreFactoryDefaults
        saveButton.isEnabled = editor.canSave
    }

    @objc private func save() {
        do {
            try editor.save()
            statusLabel.stringValue = ""
            updateActionState()
        } catch {
            statusLabel.stringValue = defaultsLocalized(
                "AnyUpright::Defaults Save Failed",
                fallback: "Unable to save defaults."
            )
            NSLog("AnyUpright defaults save error: %@", String(describing: error))
        }
    }

    @objc private func restoreFactoryDefaults() {
        editor.restoreFactoryDefaults()
        statusLabel.stringValue = ""
        updateActionState()
    }
}

final class AUHorizonDefaultsEditor: NSObject, AUPluginDefaultsEditor {
    let title = defaultsLocalized("AnyUpright::Horizon Defaults Title", fallback: "Horizon Defaults")

    private let session: AUPluginDefaultsEditorSession<AUHorizonDefaultSettings>
    private let fillFrameButton = NSButton(
        checkboxWithTitle: defaultsLocalized("AnyUpright::Defaults Fill Frame", fallback: "Fill Frame"),
        target: nil,
        action: nil
    )
    var onChange: (() -> Void)? {
        get { session.onChange }
        set { session.onChange = newValue }
    }

    var canRestoreFactoryDefaults: Bool { session.canRestoreFactoryDefaults }
    var canSave: Bool { session.canSave }

    lazy var contentView: NSView = {
        let stack = NSStackView(views: [fillFrameButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        return stack
    }()

    init(store: AUPluginDefaultsStore<AUHorizonDefaultSettings> = AUPluginDefaults.horizon) {
        session = AUPluginDefaultsEditorSession(store: store)
        super.init()
        fillFrameButton.target = self
        fillFrameButton.action = #selector(controlDidChange)
    }

    func beginEditingSession() {
        apply(session.beginEditingSession())
    }

    func save() throws {
        try session.save(settingsFromControls())
    }

    func restoreFactoryDefaults() {
        apply(session.restoreFactoryDefaults())
    }

    @objc private func controlDidChange() {
        session.updateCurrent(settingsFromControls())
    }

    private func settingsFromControls() -> AUHorizonDefaultSettings {
        AUHorizonDefaultSettings(fillFrame: fillFrameButton.state == .on)
    }

    private func apply(_ settings: AUHorizonDefaultSettings) {
        fillFrameButton.state = settings.fillFrame ? .on : .off
    }
}

final class AUInnerStretchDefaultsEditor: NSObject, AUPluginDefaultsEditor {
    let title = defaultsLocalized("AnyUpright::Inner Stretch Defaults Title", fallback: "Inner Stretch Defaults")

    private let session: AUPluginDefaultsEditorSession<AUInnerStretchDefaultSettings>
    private let ratioPopup = AUPluginDefaultsForm.popup(entries: [
        (defaultsLocalized("AnyUpright::Defaults Ratio None", fallback: "None"), Int(AUStretchRatioMode.none.rawValue)),
        (defaultsLocalized("AnyUpright::Defaults Ratio Fit", fallback: "Fit"), Int(AUStretchRatioMode.fit.rawValue)),
        (defaultsLocalized("AnyUpright::Defaults Ratio Fill", fallback: "Fill"), Int(AUStretchRatioMode.fill.rawValue)),
    ])
    private let suppressKeyframeNotificationsButton = NSButton(
        checkboxWithTitle: defaultsLocalized(
            "AnyUpright::Defaults Suppress Keyframe Notifications",
            fallback: "Don't show keyframe notifications"
        ),
        target: nil,
        action: nil
    )
    var onChange: (() -> Void)? {
        get { session.onChange }
        set { session.onChange = newValue }
    }

    var canRestoreFactoryDefaults: Bool { session.canRestoreFactoryDefaults }
    var canSave: Bool { session.canSave }

    lazy var contentView: NSView = {
        let stack = NSStackView(views: [
            AUPluginDefaultsForm.labeledRow(
                label: defaultsLocalized("AnyUpright::Defaults Ratio", fallback: "Ratio"),
                control: ratioPopup
            ),
            AUPluginDefaultsForm.labeledRow(label: "", control: suppressKeyframeNotificationsButton),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10.0
        return stack
    }()

    init(store: AUPluginDefaultsStore<AUInnerStretchDefaultSettings> = AUPluginDefaults.innerStretch) {
        session = AUPluginDefaultsEditorSession(store: store)
        super.init()
        ratioPopup.target = self
        ratioPopup.action = #selector(controlDidChange)
        suppressKeyframeNotificationsButton.target = self
        suppressKeyframeNotificationsButton.action = #selector(controlDidChange)
    }

    func beginEditingSession() {
        apply(session.beginEditingSession())
    }

    func save() throws {
        try session.save(settingsFromControls())
    }

    func restoreFactoryDefaults() {
        apply(session.restoreFactoryDefaults())
    }

    @objc private func controlDidChange() {
        session.updateCurrent(settingsFromControls())
    }

    private func settingsFromControls() -> AUInnerStretchDefaultSettings {
        let ratio = AUStretchRatioMode(rawValue: Int32(ratioPopup.selectedTag())) ?? .none
        return AUInnerStretchDefaultSettings(
            ratio: ratio,
            suppressKeyframeNotifications: suppressKeyframeNotificationsButton.state == .on
        )
    }

    private func apply(_ settings: AUInnerStretchDefaultSettings) {
        AUPluginDefaultsForm.select(tag: Int(settings.ratio.rawValue), in: ratioPopup)
        suppressKeyframeNotificationsButton.state = settings.suppressKeyframeNotifications ? .on : .off
    }
}

final class AUOuterStretchDefaultsEditor: NSObject, AUPluginDefaultsEditor {
    let title = defaultsLocalized("AnyUpright::Outer Stretch Defaults Title", fallback: "Outer Stretch Defaults")

    private let session: AUPluginDefaultsEditorSession<AUOuterStretchDefaultSettings>
    private let suppressKeyframeNotificationsButton = NSButton(
        checkboxWithTitle: defaultsLocalized(
            "AnyUpright::Defaults Suppress Keyframe Notifications",
            fallback: "Don't show keyframe notifications"
        ),
        target: nil,
        action: nil
    )
    var onChange: (() -> Void)? {
        get { session.onChange }
        set { session.onChange = newValue }
    }

    var canRestoreFactoryDefaults: Bool { session.canRestoreFactoryDefaults }
    var canSave: Bool { session.canSave }

    lazy var contentView: NSView = {
        let stack = NSStackView(views: [suppressKeyframeNotificationsButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        return stack
    }()

    init(store: AUPluginDefaultsStore<AUOuterStretchDefaultSettings> = AUPluginDefaults.outerStretch) {
        session = AUPluginDefaultsEditorSession(store: store)
        super.init()
        suppressKeyframeNotificationsButton.target = self
        suppressKeyframeNotificationsButton.action = #selector(controlDidChange)
    }

    func beginEditingSession() {
        apply(session.beginEditingSession())
    }

    func save() throws {
        try session.save(settingsFromControls())
    }

    func restoreFactoryDefaults() {
        apply(session.restoreFactoryDefaults())
    }

    @objc private func controlDidChange() {
        session.updateCurrent(settingsFromControls())
    }

    private func settingsFromControls() -> AUOuterStretchDefaultSettings {
        AUOuterStretchDefaultSettings(
            suppressKeyframeNotifications: suppressKeyframeNotificationsButton.state == .on
        )
    }

    private func apply(_ settings: AUOuterStretchDefaultSettings) {
        suppressKeyframeNotificationsButton.state = settings.suppressKeyframeNotifications ? .on : .off
    }
}

final class AUUprightDefaultsEditor: NSObject, AUPluginDefaultsEditor {
    let title = defaultsLocalized("AnyUpright::Upright Defaults Title", fallback: "Upright Defaults")

    private let session: AUPluginDefaultsEditorSession<AUUprightDefaultSettings>
    private let directionPopup = AUPluginDefaultsForm.popup(entries: [
        (defaultsLocalized("AnyUpright::Defaults Direction Vertical", fallback: "Vertical"), Int(UprightCorrectionMode.vertical.rawValue)),
        (defaultsLocalized("AnyUpright::Defaults Direction Horizontal", fallback: "Horizontal"), Int(UprightCorrectionMode.horizontal.rawValue)),
        (defaultsLocalized("AnyUpright::Defaults Direction Full", fallback: "Full"), Int(UprightCorrectionMode.full.rawValue)),
    ])
    private let modePopup = AUPluginDefaultsForm.popup(entries: [
        (defaultsLocalized("AnyUpright::Defaults Mode Manual", fallback: "Manual"), Int(UprightControlMode.manual.rawValue)),
        (defaultsLocalized("AnyUpright::Defaults Mode Semi Auto", fallback: "Semi Auto"), Int(UprightControlMode.semiAutomatic.rawValue)),
        (defaultsLocalized("AnyUpright::Defaults Mode Auto", fallback: "Auto"), Int(UprightControlMode.automatic.rawValue)),
    ])
    private let autoCropButton = NSButton(
        checkboxWithTitle: defaultsLocalized("AnyUpright::Defaults Auto Crop", fallback: "Auto Crop"),
        target: nil,
        action: nil
    )
    var onChange: (() -> Void)? {
        get { session.onChange }
        set { session.onChange = newValue }
    }

    var canRestoreFactoryDefaults: Bool { session.canRestoreFactoryDefaults }
    var canSave: Bool { session.canSave }

    lazy var contentView: NSView = {
        let stack = NSStackView(views: [
            AUPluginDefaultsForm.labeledRow(
                label: defaultsLocalized("AnyUpright::Defaults Direction", fallback: "Direction"),
                control: directionPopup
            ),
            AUPluginDefaultsForm.labeledRow(
                label: defaultsLocalized("AnyUpright::Defaults Mode", fallback: "Mode"),
                control: modePopup
            ),
            AUPluginDefaultsForm.labeledRow(label: "", control: autoCropButton),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10.0
        return stack
    }()

    init(store: AUPluginDefaultsStore<AUUprightDefaultSettings> = AUPluginDefaults.upright) {
        session = AUPluginDefaultsEditorSession(store: store)
        super.init()
        directionPopup.target = self
        directionPopup.action = #selector(controlDidChange)
        modePopup.target = self
        modePopup.action = #selector(controlDidChange)
        autoCropButton.target = self
        autoCropButton.action = #selector(controlDidChange)
    }

    func beginEditingSession() {
        apply(session.beginEditingSession())
    }

    func save() throws {
        try session.save(settingsFromControls())
    }

    func restoreFactoryDefaults() {
        apply(session.restoreFactoryDefaults())
    }

    @objc private func controlDidChange() {
        session.updateCurrent(settingsFromControls())
    }

    private func settingsFromControls() -> AUUprightDefaultSettings {
        let direction = UprightCorrectionMode(rawValue: Int32(directionPopup.selectedTag())) ?? .vertical
        let mode = UprightControlMode(rawValue: Int32(modePopup.selectedTag())) ?? .automatic
        return AUUprightDefaultSettings(
            direction: direction,
            mode: mode,
            autoCrop: autoCropButton.state == .on
        )
    }

    private func apply(_ settings: AUUprightDefaultSettings) {
        AUPluginDefaultsForm.select(tag: Int(settings.direction.rawValue), in: directionPopup)
        AUPluginDefaultsForm.select(tag: Int(settings.mode.rawValue), in: modePopup)
        autoCropButton.state = settings.autoCrop ? .on : .off
    }
}
