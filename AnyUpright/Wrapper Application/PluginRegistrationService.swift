import Foundation

enum PluginRegistrationState: Equatable {
    case registered
    case notRegistered
    case unavailable(String)
}

struct PluginRegistrationService {
    private let executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")

    func state() -> PluginRegistrationState {
        do {
            let plugin = try embeddedPlugin()
            let output = try run(["-m", "-ADv", "-i", plugin.identifier])
            let expectedPath = plugin.url.resolvingSymlinksInPath().standardizedFileURL.path
            return Self.parseState(
                output: output,
                expectedPaths: [expectedPath, plugin.url.standardizedFileURL.path]
            )
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    static func parseState(output: String, expectedPaths: [String]) -> PluginRegistrationState {
        let matchingLine = output.components(separatedBy: .newlines).first { line in
            expectedPaths.contains { line.contains($0) }
        }
        guard let matchingLine else {
            return .notRegistered
        }

        return matchingLine.trimmingCharacters(in: .whitespaces).hasPrefix("-")
            ? .notRegistered
            : .registered
    }

    func install() throws {
        let plugin = try embeddedPlugin()
        _ = try run(["-a", plugin.url.path])
        _ = try run(["-e", "use", "-i", plugin.identifier])
    }

    func uninstall() throws {
        let plugin = try embeddedPlugin()
        _ = try run(["-e", "ignore", "-i", plugin.identifier])
        _ = try run(["-r", plugin.url.path])
    }

    private func embeddedPlugin() throws -> (url: URL, identifier: String) {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else {
            throw RegistrationError.missingPlugInsDirectory
        }

        let candidates = try FileManager.default.contentsOfDirectory(
            at: pluginsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard let pluginURL = candidates.first(where: { $0.pathExtension == "pluginkit" }),
              let pluginBundle = Bundle(url: pluginURL),
              let identifier = pluginBundle.bundleIdentifier else {
            throw RegistrationError.missingEmbeddedPlugin
        }
        return (pluginURL, identifier)
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RegistrationError.commandFailed(message?.isEmpty == false ? message! : "pluginkit exited with status \(process.terminationStatus)")
        }
        return String(data: output, encoding: .utf8) ?? ""
    }
}

private enum RegistrationError: LocalizedError {
    case missingPlugInsDirectory
    case missingEmbeddedPlugin
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPlugInsDirectory:
            return WrapperL10n.text("registration.error.missingDirectory")
        case .missingEmbeddedPlugin:
            return WrapperL10n.text("registration.error.missingPlugin")
        case .commandFailed(let message):
            return WrapperL10n.format("registration.error.commandFailed", message)
        }
    }
}
