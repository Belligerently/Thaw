//
//  ActiveMenuBarDisplayWatcher.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Reports when the active menu bar moves to another display, so settings
/// that depend on the display, such as "Always show hidden items", follow it.
///
/// macOS sends no notification for the move itself. App activation, a Space
/// change and a display change catch most moves; a click into another window
/// of the same app on another display is caught by a one-second check.
@MainActor
final class ActiveMenuBarDisplayWatcher {
    var onChange: (() -> Void)?
    /// Whether anything depends on the active display right now; the
    /// one-second check skips its read while nothing does.
    var isNeeded: () -> Bool = { true }

    private let readDisplayID: () -> CGDirectDisplayID?
    private var lastDisplayID: CGDirectDisplayID?
    /// Set by start(), in the +Live file.
    var observers: [any NSObjectProtocol] = []
    var timer: Timer?

    init(readDisplayID: @escaping () -> CGDirectDisplayID? = { Bridging.getActiveMenuBarDisplayID() }) {
        self.readDisplayID = readDisplayID
    }

    /// Reads the active display and reports a change from the last known one.
    func check() {
        guard let displayID = readDisplayID() else { return }
        defer { lastDisplayID = displayID }
        if let lastDisplayID, lastDisplayID != displayID {
            onChange?()
        }
    }
}
