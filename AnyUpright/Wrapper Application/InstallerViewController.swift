import AppKit

final class InstallerViewController: NSViewController {
    private let registrationService: PluginRegistrationService
    private let registrationStatus = NSTextField(labelWithString: "")
    private let registrationInstallButton = NSButton()
    private let registrationUninstallButton = NSButton()

    init(registrationService: PluginRegistrationService) {
        self.registrationService = registrationService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        configureView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshRegistrationState()
    }

    private func configureView() {
        let heading = NSTextField(labelWithString: WrapperL10n.text("installer.title"))
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        heading.alignment = .center

        let pluginColumn = makeColumn(
            title: WrapperL10n.text("installer.pluginRegistration"),
            statusView: registrationStatus,
            installAction: #selector(installPlugin),
            uninstallAction: #selector(uninstallPlugin),
            installButton: registrationInstallButton,
            uninstallButton: registrationUninstallButton
        )

        let effectsStatus = NSTextField(labelWithString: WrapperL10n.text("status.notInstalled"))
        effectsStatus.alignment = .center
        let effectsColumn = makeColumn(
            title: WrapperL10n.text("installer.motionEffects"),
            statusView: effectsStatus,
            installAction: #selector(showNotImplemented),
            uninstallAction: #selector(showNotImplemented)
        )

        let divider = NSBox()
        divider.boxType = .separator

        let columns = NSStackView(views: [pluginColumn, divider, effectsColumn])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 24
        columns.distribution = .fill

        let content = NSStackView(views: [heading, columns])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 28
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -28),
            columns.widthAnchor.constraint(equalTo: content.widthAnchor),
            pluginColumn.widthAnchor.constraint(equalTo: effectsColumn.widthAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalTo: columns.heightAnchor)
        ])
    }

    private func makeColumn(
        title: String,
        statusView: NSTextField,
        installAction: Selector,
        uninstallAction: Selector,
        installButton: NSButton = NSButton(),
        uninstallButton: NSButton = NSButton()
    ) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.alignment = .center

        statusView.alignment = .center
        statusView.lineBreakMode = .byTruncatingTail

        configureButton(
            installButton,
            title: WrapperL10n.text("action.install"),
            action: installAction
        )
        configureButton(
            uninstallButton,
            title: WrapperL10n.text("action.uninstall"),
            action: uninstallAction
        )

        let column = NSStackView(views: [titleLabel, statusView, installButton, uninstallButton])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 14
        installButton.widthAnchor.constraint(equalToConstant: 180).isActive = true
        uninstallButton.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return column
    }

    private func configureButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    @objc private func installPlugin() {
        performRegistrationAction { try self.registrationService.install() }
    }

    @objc private func uninstallPlugin() {
        performRegistrationAction { try self.registrationService.uninstall() }
    }

    @objc private func showNotImplemented() {
        let alert = NSAlert()
        alert.messageText = WrapperL10n.text("notImplemented.title")
        alert.informativeText = WrapperL10n.text("notImplemented.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: WrapperL10n.text("action.ok"))
        alert.beginSheetModal(for: view.window!)
    }

    private func performRegistrationAction(_ action: @escaping () throws -> Void) {
        setRegistrationButtonsEnabled(false)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try action()
                DispatchQueue.main.async {
                    self?.refreshRegistrationState()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.present(error: error)
                    self?.refreshRegistrationState()
                }
            }
        }
    }

    private func refreshRegistrationState() {
        setRegistrationButtonsEnabled(false)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let state = registrationService.state()
            DispatchQueue.main.async {
                self.apply(state)
            }
        }
    }

    private func apply(_ state: PluginRegistrationState) {
        switch state {
        case .registered:
            registrationStatus.stringValue = WrapperL10n.text("status.installed")
            registrationStatus.textColor = .systemGreen
            registrationInstallButton.isEnabled = false
            registrationUninstallButton.isEnabled = true
        case .notRegistered:
            registrationStatus.stringValue = WrapperL10n.text("status.notInstalled")
            registrationStatus.textColor = .secondaryLabelColor
            registrationInstallButton.isEnabled = true
            registrationUninstallButton.isEnabled = false
        case .unavailable(let message):
            registrationStatus.stringValue = WrapperL10n.format("status.unavailable", message)
            registrationStatus.textColor = .systemRed
            setRegistrationButtonsEnabled(false)
        }
    }

    private func setRegistrationButtonsEnabled(_ enabled: Bool) {
        registrationInstallButton.isEnabled = enabled
        registrationUninstallButton.isEnabled = enabled
    }

    private func present(error: Error) {
        guard let window = view.window else { return }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }
}
