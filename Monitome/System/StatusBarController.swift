//
//  StatusBarController.swift
//  Monitome
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var recordingSub: AnyCancellable?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            updateIcon(isRecording: AppState.shared.isRecording)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: StatusMenuView())

        // Observe recording state
        recordingSub = AppState.shared.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.updateIcon(isRecording: isRecording)
            }
    }

    private func updateIcon(isRecording: Bool) {
        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = !isRecording  // Template for inactive, colored for active
            button.image = image

            if isRecording {
                button.contentTintColor = .systemRed
            } else {
                button.contentTintColor = nil
            }
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Activate app to ensure popover gets focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
