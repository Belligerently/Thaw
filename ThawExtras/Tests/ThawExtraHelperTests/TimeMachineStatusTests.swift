//
//  TimeMachineStatusTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawExtraHelper

@Suite("Time Machine status")
struct TimeMachineStatusTests {
    @Test("Idle output reads as not running, with no percentage")
    func idle() {
        let output = """
        Backup session status:
        {
            ClientID = "com.apple.backupd";
            Percent = "-1";
            Running = 0;
        }
        """
        #expect(TimeMachineStatus.parse(output) == .idle)
    }

    @Test("A backup in progress reads as running with its fraction done")
    func running() {
        let output = """
        Backup session status:
        {
            BackupPhase = Copying;
            ClientID = "com.apple.backupd";
            Percent = "0.42";
            Progress =     {
                Percent = "0.42";
                TimeRemaining = 120;
            };
            Running = 1;
            Stopping = 0;
        }
        """
        #expect(TimeMachineStatus.parse(output) == TimeMachineStatus(isRunning: true, fraction: 0.42))
    }

    @Test("A backup that hasn't started copying has no fraction yet")
    func preparing() {
        let output = "{\n    BackupPhase = Starting;\n    Percent = \"-1\";\n    Running = 1;\n}"
        #expect(TimeMachineStatus.parse(output) == TimeMachineStatus(isRunning: true, fraction: nil))
    }

    @Test("Empty output, from tmutil failing, reads as idle")
    func failure() {
        #expect(TimeMachineStatus.parse("") == .idle)
    }

    @Test("The stand-in shows unless Thaw hides it, and only during a backup when asked", arguments: [
        (false, false, false, true),
        (false, true, false, false),
        (false, true, true, true),
        (true, false, true, false),
        (true, true, true, false),
    ])
    func visibility(hiddenByThaw: Bool, onlyWhileBackingUp: Bool, isRunning: Bool, shows: Bool) {
        #expect(TimeMachineStatus.showsItem(hiddenByThaw: hiddenByThaw, onlyWhileBackingUp: onlyWhileBackingUp, isRunning: isRunning) == shows)
    }
}

@MainActor
@Suite("Time Machine icon")
struct TimeMachineIconTests {
    @Test("The spinning icon has twelve template frames of the same size")
    func frames() {
        let frames = TimeMachineExtra.spinFrames(symbolName: "clock.arrow.trianglehead.counterclockwise.rotate.90", label: "Time Machine")
        #expect(frames.count == 12)
        let allTemplates = frames.allSatisfy(\.isTemplate)
        let sizes = Set(frames.map { "\($0.size)" })
        #expect(allTemplates)
        #expect(sizes.count == 1)
    }
}
