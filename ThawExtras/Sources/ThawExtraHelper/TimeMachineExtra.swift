//
//  TimeMachineExtra.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import OSLog

/// The Time Machine stand-in: it asks `tmutil status` whether a backup is
/// running, spins its icon while one is, and can stay out of the menu bar
/// the rest of the time.
@MainActor
final class TimeMachineExtra: NSObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThawExtraHelper", category: "timemachine")
    private let button: NSStatusBarButton
    private let symbolName: String
    private let label: String
    /// Called when the item should appear or go, so the helper can combine it
    /// with Thaw's own choice.
    private let visibilityDidChange: () -> Void

    private(set) var status = TimeMachineStatus.idle
    private var pollTask: Task<Void, Never>?
    private var spinTimer: Timer?
    private var spinFrame = 0
    private lazy var spinFrames: [NSImage] = Self.spinFrames(symbolName: symbolName, label: label)

    /// Saved in the helper's own defaults: only this stand-in reads it.
    static let onlyWhileBackingUpKey = "ShowOnlyWhileBackingUp"

    var onlyWhileBackingUp: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onlyWhileBackingUpKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.onlyWhileBackingUpKey)
            visibilityDidChange()
        }
    }

    /// How often tmutil is asked. Often enough to catch a backup a few seconds
    /// after it starts, and more often while one runs, for the percentage.
    private static let idleInterval = Duration.seconds(10)
    private static let runningInterval = Duration.seconds(3)
    private static let spinInterval: TimeInterval = 1.0 / 12

    init(button: NSStatusBarButton, symbolName: String, label: String, visibilityDidChange: @escaping () -> Void) {
        self.button = button
        self.symbolName = symbolName
        self.label = label
        self.visibilityDidChange = visibilityDidChange
    }

    func start() {
        showStill()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let output = await Self.readStatus()
                guard let self else { return }
                self.update(TimeMachineStatus.parse(output))
                try? await Task.sleep(for: self.status.isRunning ? Self.runningInterval : Self.idleInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        spinTimer?.invalidate()
    }

    private func update(_ new: TimeMachineStatus) {
        let startedOrStopped = new.isRunning != status.isRunning
        status = new
        guard startedOrStopped else {
            updateToolTip()
            return
        }
        logger.info("Time Machine backup \(new.isRunning ? "started" : "finished", privacy: .public)")
        if new.isRunning {
            startSpinning()
        } else {
            spinTimer?.invalidate()
            spinTimer = nil
            showStill()
        }
        updateToolTip()
        visibilityDidChange()
    }

    // MARK: Menu

    func populate(_ menu: NSMenu, target: AnyObject, backUpNow: Selector, browse: Selector, settings: Selector) {
        if status.isRunning {
            let title = status.fraction.map {
                String(localized: "Backing Up… \($0.formatted(.percent.precision(.fractionLength(0))))")
            } ?? String(localized: "Backing Up…")
            let progress = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            progress.isEnabled = false
            menu.addItem(progress)
            menu.addItem(.separator())
        } else {
            menu.addItem(item(String(localized: "Back Up Now"), backUpNow, target: target))
        }
        menu.addItem(item(String(localized: "Browse Time Machine Backups"), browse, target: target))
        menu.addItem(.separator())
        let only = NSMenuItem(title: String(localized: "Show Only While Backing Up"), action: #selector(toggleOnlyWhileBackingUp), keyEquivalent: "")
        only.target = self
        only.state = onlyWhileBackingUp ? .on : .off
        menu.addItem(only)
        menu.addItem(item(String(localized: "Open Time Machine Settings…"), settings, target: target))
    }

    private func item(_ title: String, _ action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }

    @objc private func toggleOnlyWhileBackingUp() {
        onlyWhileBackingUp.toggle()
    }

    // MARK: Icon

    private func showStill() {
        button.image = spinFrames.first
    }

    private func startSpinning() {
        spinTimer?.invalidate()
        spinFrame = 0
        let timer = Timer(timeInterval: Self.spinInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.spinFrame = (self.spinFrame + 1) % self.spinFrames.count
                self.button.image = self.spinFrames[self.spinFrame]
            }
        }
        // Common modes, so the icon keeps turning while its menu is open.
        RunLoop.main.add(timer, forMode: .common)
        spinTimer = timer
    }

    private func updateToolTip() {
        if status.isRunning, let fraction = status.fraction {
            button.toolTip = String(localized: "Backing up, \(fraction.formatted(.percent.precision(.fractionLength(0)))) done")
        } else if status.isRunning {
            button.toolTip = String(localized: "Backing up")
        } else {
            button.toolTip = label
        }
    }

    /// The symbol turned counterclockwise in twelve steps, like the arrow on
    /// Apple's own icon. Frame 0 is the still icon.
    static func spinFrames(symbolName: String, label: String) -> [NSImage] {
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: label)
            ?? NSImage()
        let size = base.size
        return (0 ..< 12).map { step in
            let image = NSImage(size: size, flipped: false) { rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.translateBy(x: rect.midX, y: rect.midY)
                context.rotate(by: CGFloat(step) * .pi / 6)
                context.translateBy(x: -rect.midX, y: -rect.midY)
                base.draw(in: rect)
                return true
            }
            image.isTemplate = true
            image.accessibilityDescription = label
            return image
        }
    }

    // MARK: tmutil

    /// Runs `tmutil status` off the main thread. A failure reads as idle.
    private static nonisolated func readStatus() async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/tmutil")
                process.arguments = ["status"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: String(bytes: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
