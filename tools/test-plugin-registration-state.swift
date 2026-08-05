import Foundation

@main
enum TestPluginRegistrationState {
    static func main() {
        let appPath = "/Applications/AnyUpright.app/Contents/PlugIns/AnyUpright XPC Service.pluginkit"
        let otherPath = "/private/tmp/AnyUpright.app/Contents/PlugIns/AnyUpright XPC Service.pluginkit"

        assertEqual(
            PluginRegistrationService.parseState(
                output: "     AnyUpright-XPC-Service(1.1) UUID DATE \(appPath)",
                expectedPaths: [appPath]
            ),
            .registered,
            "active registration"
        )
        assertEqual(
            PluginRegistrationService.parseState(
                output: "-    AnyUpright-XPC-Service(1.1) UUID DATE \(appPath)",
                expectedPaths: [appPath]
            ),
            .notRegistered,
            "ignored registration"
        )
        assertEqual(
            PluginRegistrationService.parseState(
                output: "     AnyUpright-XPC-Service(1.1) UUID DATE \(otherPath)",
                expectedPaths: [appPath]
            ),
            .notRegistered,
            "different bundle path"
        )

        print("AnyUpright plugin registration state tests passed")
    }

    private static func assertEqual(
        _ actual: PluginRegistrationState,
        _ expected: PluginRegistrationState,
        _ label: String
    ) {
        guard actual == expected else {
            fatalError("\(label): expected \(expected), got \(actual)")
        }
    }
}
