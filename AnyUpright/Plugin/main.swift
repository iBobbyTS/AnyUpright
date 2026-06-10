//
//  main.swift
//  AnyUpright
//
//  Created by iBobby on 2026-06-05.
//

import Foundation

enum AnyUprightHostContext {
    private static let lock = NSLock()
    private static var currentBundleIdentifier: String?
    private static var currentVersion: String?

    static var hostBundleIdentifier: String? {
        lock.lock()
        defer { lock.unlock() }
        return currentBundleIdentifier
    }

    static var hostVersion: String? {
        lock.lock()
        defer { lock.unlock() }
        return currentVersion
    }

    static func update(bundleIdentifier: String, version: String) {
        lock.lock()
        currentBundleIdentifier = bundleIdentifier
        currentVersion = version
        lock.unlock()
    }
}

final class AnyUprightHostConnectionDelegate: NSObject, FxPrincipalDelegate {
    func didEstablishConnection(withHost hostBundleIdentifier: String, version hostVersionString: String) {
        AnyUprightHostContext.update(bundleIdentifier: hostBundleIdentifier, version: hostVersionString)
    }
}

private let hostConnectionDelegate = AnyUprightHostConnectionDelegate()
FxPrincipal.startServicePrincipal(with: hostConnectionDelegate)
