//
//  AppDelegate.swift
//  AnyUpright
//
//  Created by iBobby on 2026-06-05.
//

import AppKit

@NSApplicationMain
@objc(AppDelegate) class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewController = InstallerViewController(
            registrationService: PluginRegistrationService()
        )
        window.contentViewController = viewController
        window.title = "AnyUpright"
        window.setContentSize(NSSize(width: 680, height: 300))
        window.minSize = NSSize(width: 620, height: 280)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
