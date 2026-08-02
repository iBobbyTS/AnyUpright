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

    func reloadFromStore()
    func save() throws
    func restoreFactoryDefaults() throws
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

final class AUPluginDefaultsWindowPresenter {
    private static let rootIdentifier = NSUserInterfaceItemIdentifier("AnyUpright.PluginDefaults.Root")
    private static let contentSize = CGSize(width: 480.0, height: 260.0)

    private let stateLock = NSLock()
    private var requestPending = false
    private var nextRequestID: UInt64 = 0
    private weak var activeParentView: NSView?
    private var viewController: AUPluginDefaultsViewController?

    func present(remoteWindowAPI: FxRemoteWindowAPI, editor: AUPluginDefaultsEditor) {
        precondition(Thread.isMainThread, "Plugin defaults UI must be presented on the main thread")

        if let activeParentView,
           let activeWindow = activeParentView.window,
           activeWindow.isVisible {
            AUPluginDefaultsDiagnostics.log(
                "present reused presenter=\(ObjectIdentifier(self)) editor=\(editor.title)"
            )
            activeWindow.makeKeyAndOrderFront(nil)
            return
        }
        activeParentView = nil

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
        editor.reloadFromStore()
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

                AUPluginDefaultsDiagnostics.log(
                    "present attach begin request=\(requestID) parentFrame=\(NSStringFromRect(parentView.frame)) parentBounds=\(NSStringFromRect(parentView.bounds)) existingSubviews=\(parentView.subviews.count)"
                )
                let controller = AUPluginDefaultsViewController(editor: editor)
                self.viewController = controller
                let rootView = controller.view
                rootView.identifier = Self.rootIdentifier
                rootView.frame = NSRect(origin: .zero, size: parentView.bounds.size)
                rootView.autoresizingMask = [.width, .height]

                parentView.subviews
                    .filter { $0.identifier == Self.rootIdentifier }
                    .forEach { $0.removeFromSuperview() }
                parentView.addSubview(rootView)
                self.activeParentView = parentView
                AUPluginDefaultsDiagnostics.log(
                    "present attach end request=\(requestID) rootFrame=\(NSStringFromRect(rootView.frame)) parentSubviews=\(parentView.subviews.count)"
                )
            }
        }
        AUPluginDefaultsDiagnostics.log("present submitted request=\(requestID)")
    }
}

private final class AUPluginDefaultsViewController: NSViewController {
    private let editor: AUPluginDefaultsEditor
    private let statusLabel = NSTextField(labelWithString: "")

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
            fallback: "These defaults apply only to new filter instances."
        ))
        scopeLabel.textColor = .secondaryLabelColor

        let contentStack = NSStackView(views: [titleLabel, scopeLabel, editor.contentView])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14.0
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let resetButton = NSButton(
            title: defaultsLocalized(
                "AnyUpright::Defaults Restore Factory",
                fallback: "Restore Factory Defaults"
            ),
            target: self,
            action: #selector(restoreFactoryDefaults)
        )
        let saveButton = NSButton(
            title: defaultsLocalized("AnyUpright::Defaults Save", fallback: "Save"),
            target: self,
            action: #selector(save)
        )
        saveButton.keyEquivalent = "\r"

        let actionStack = NSStackView(views: [statusLabel, resetButton, saveButton])
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 10.0
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        rootView.addSubview(contentStack)
        rootView.addSubview(actionStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20.0),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -20.0),
            contentStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20.0),
            editor.contentView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),

            actionStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20.0),
            actionStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20.0),
            actionStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -20.0),
            actionStack.topAnchor.constraint(greaterThanOrEqualTo: contentStack.bottomAnchor, constant: 20.0),
        ])
    }

    @objc private func save() {
        do {
            try editor.save()
            statusLabel.stringValue = defaultsLocalized(
                "AnyUpright::Defaults Saved",
                fallback: "Saved for new instances."
            )
        } catch {
            statusLabel.stringValue = defaultsLocalized(
                "AnyUpright::Defaults Save Failed",
                fallback: "Unable to save defaults."
            )
            NSLog("AnyUpright defaults save error: %@", String(describing: error))
        }
    }

    @objc private func restoreFactoryDefaults() {
        do {
            try editor.restoreFactoryDefaults()
            statusLabel.stringValue = defaultsLocalized(
                "AnyUpright::Defaults Restored",
                fallback: "Factory defaults restored."
            )
        } catch {
            statusLabel.stringValue = defaultsLocalized(
                "AnyUpright::Defaults Save Failed",
                fallback: "Unable to save defaults."
            )
            NSLog("AnyUpright defaults restore error: %@", String(describing: error))
        }
    }
}

final class AUHorizonDefaultsEditor: AUPluginDefaultsEditor {
    let title = defaultsLocalized("AnyUpright::Horizon Defaults Title", fallback: "Horizon Defaults")

    private let store: AUPluginDefaultsStore<AUHorizonDefaultSettings>
    private let fillFrameButton = NSButton(
        checkboxWithTitle: defaultsLocalized("AnyUpright::Defaults Fill Frame", fallback: "Fill Frame"),
        target: nil,
        action: nil
    )

    lazy var contentView: NSView = {
        let stack = NSStackView(views: [fillFrameButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        return stack
    }()

    init(store: AUPluginDefaultsStore<AUHorizonDefaultSettings> = AUPluginDefaults.horizon) {
        self.store = store
    }

    func reloadFromStore() {
        fillFrameButton.state = store.load().fillFrame ? .on : .off
    }

    func save() throws {
        try store.save(AUHorizonDefaultSettings(fillFrame: fillFrameButton.state == .on))
    }

    func restoreFactoryDefaults() throws {
        try store.reset()
        reloadFromStore()
    }
}

final class AUInnerStretchDefaultsEditor: AUPluginDefaultsEditor {
    let title = defaultsLocalized("AnyUpright::Inner Stretch Defaults Title", fallback: "Inner Stretch Defaults")

    private let store: AUPluginDefaultsStore<AUInnerStretchDefaultSettings>
    private let ratioPopup = AUPluginDefaultsForm.popup(entries: [
        (defaultsLocalized("AnyUpright::Defaults Ratio None", fallback: "None"), Int(AUStretchRatioMode.none.rawValue)),
        (defaultsLocalized("AnyUpright::Defaults Ratio Fit", fallback: "Fit"), Int(AUStretchRatioMode.fit.rawValue)),
        (defaultsLocalized("AnyUpright::Defaults Ratio Fill", fallback: "Fill"), Int(AUStretchRatioMode.fill.rawValue)),
    ])

    lazy var contentView: NSView = {
        AUPluginDefaultsForm.labeledRow(
            label: defaultsLocalized("AnyUpright::Defaults Ratio", fallback: "Ratio"),
            control: ratioPopup
        )
    }()

    init(store: AUPluginDefaultsStore<AUInnerStretchDefaultSettings> = AUPluginDefaults.innerStretch) {
        self.store = store
    }

    func reloadFromStore() {
        AUPluginDefaultsForm.select(tag: Int(store.load().ratio.rawValue), in: ratioPopup)
    }

    func save() throws {
        let ratio = AUStretchRatioMode(rawValue: Int32(ratioPopup.selectedTag())) ?? .none
        try store.save(AUInnerStretchDefaultSettings(ratio: ratio))
    }

    func restoreFactoryDefaults() throws {
        try store.reset()
        reloadFromStore()
    }
}

final class AUUprightDefaultsEditor: AUPluginDefaultsEditor {
    let title = defaultsLocalized("AnyUpright::Upright Defaults Title", fallback: "Upright Defaults")

    private let store: AUPluginDefaultsStore<AUUprightDefaultSettings>
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
        self.store = store
    }

    func reloadFromStore() {
        let settings = store.load()
        AUPluginDefaultsForm.select(tag: Int(settings.direction.rawValue), in: directionPopup)
        AUPluginDefaultsForm.select(tag: Int(settings.mode.rawValue), in: modePopup)
        autoCropButton.state = settings.autoCrop ? .on : .off
    }

    func save() throws {
        let direction = UprightCorrectionMode(rawValue: Int32(directionPopup.selectedTag())) ?? .vertical
        let mode = UprightControlMode(rawValue: Int32(modePopup.selectedTag())) ?? .automatic
        try store.save(AUUprightDefaultSettings(
            direction: direction,
            mode: mode,
            autoCrop: autoCropButton.state == .on
        ))
    }

    func restoreFactoryDefaults() throws {
        try store.reset()
        reloadFromStore()
    }
}
