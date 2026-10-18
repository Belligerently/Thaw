//
//  WideDisplayRuleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("Wide display rule", .serialized)
@MainActor
struct WideDisplayRuleTests {
    private func withStore(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "WideDisplayRuleTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        let previousStore = Defaults.store
        Defaults.store = store
        defer {
            Defaults.store = previousStore
            ScratchDefaults.remove(suite)
        }
        try body(store)
    }

    @Test("A display at least as wide as the minimum shows every item")
    func wideDisplayShowsEverything() {
        #expect(WideDisplayRule.applies(isEnabled: true, screenWidth: 2560, minimumWidth: 2560))
        #expect(WideDisplayRule.applies(isEnabled: true, screenWidth: 3008, minimumWidth: 2560))
    }

    @Test("A narrower display, an unknown display or a switched-off rule shows nothing extra")
    func otherCasesShowNothing() {
        #expect(!WideDisplayRule.applies(isEnabled: true, screenWidth: 1512, minimumWidth: 2560))
        #expect(!WideDisplayRule.applies(isEnabled: true, screenWidth: nil, minimumWidth: 2560))
        #expect(!WideDisplayRule.applies(isEnabled: false, screenWidth: 3008, minimumWidth: 2560))
    }

    @Test("The rule starts off at 2,560 points")
    func defaults() throws {
        try withStore { _ in
            let rule = WideDisplayRule()
            #expect(!rule.isEnabled)
            #expect(rule.minimumWidth == 2560)
        }
    }

    @Test("Changes are saved and read back")
    func persists() throws {
        try withStore { _ in
            let rule = WideDisplayRule()
            rule.isEnabled = true
            rule.minimumWidth = 3200
            let reloaded = WideDisplayRule()
            #expect(reloaded.isEnabled)
            #expect(reloaded.minimumWidth == 3200)
        }
    }

    @Test("The rule asks for the width of the display it is given")
    func readsTheDisplayWidth() throws {
        try withStore { _ in
            let rule = WideDisplayRule(screenWidth: { $0 == 2 ? 3008 : 1512 })
            rule.isEnabled = true
            #expect(rule.showsEveryItem(on: 2))
            #expect(!rule.showsEveryItem(on: 1))
        }
    }
}

@Suite("Active menu bar display watcher")
@MainActor
struct ActiveMenuBarDisplayWatcherTests {
    @MainActor
    final class Probe {
        var displayID: CGDirectDisplayID? = 1
        var changes = 0
    }

    @Test("A move of the active menu bar to another display is reported once")
    func reportsAMove() {
        let probe = Probe()
        let watcher = ActiveMenuBarDisplayWatcher(readDisplayID: { probe.displayID })
        watcher.onChange = { probe.changes += 1 }
        watcher.check()
        #expect(probe.changes == 0)

        probe.displayID = 2
        watcher.check()
        watcher.check()
        #expect(probe.changes == 1)
    }

    @Test("Losing track of the active display is not a move")
    func ignoresUnknown() {
        let probe = Probe()
        let watcher = ActiveMenuBarDisplayWatcher(readDisplayID: { probe.displayID })
        watcher.onChange = { probe.changes += 1 }
        watcher.check()
        probe.displayID = nil
        watcher.check()
        probe.displayID = 1
        watcher.check()
        #expect(probe.changes == 0)
    }
}
