//
//  PermissionsOnboardingView.swift
//  Monitome
//

import SwiftUI

struct PermissionsOnboardingView: View {
    let onContinue: () -> Void

    @State private var screenRecordingGranted = PermissionsManager.isScreenRecordingGranted
    @State private var accessibilityGranted = PermissionsManager.isAccessibilityGranted
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Set Up Monitome")
                    .font(.system(size: 24, weight: .semibold))

                Text("Monitome needs permissions to capture screenshots and detect tab changes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                PermissionSetupRow(
                    title: "Screen Recording",
                    description: "Required to capture periodic screenshots",
                    granted: screenRecordingGranted,
                    buttonTitle: "Open Settings",
                    note: "You may need to quit/reopen Monitome after granting"
                ) {
                    _ = PermissionsManager.requestScreenRecording()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        PermissionsManager.openScreenRecordingSettings()
                    }
                }

                PermissionSetupRow(
                    title: "Accessibility",
                    description: "Optional, but enables browser tab-change detection",
                    granted: accessibilityGranted,
                    buttonTitle: "Open Settings"
                ) {
                    PermissionsManager.requestAccessibility()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        PermissionsManager.openAccessibilitySettings()
                    }
                }
            }

            Button("Continue") {
                UserDefaults.standard.set(true, forKey: "didCompletePermissionsOnboarding")
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!screenRecordingGranted)

            if !screenRecordingGranted {
                Text("Enable Screen Recording to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 540)
        .onAppear {
            refreshPermissions()
            startPolling()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshPermissions() {
        screenRecordingGranted = PermissionsManager.isScreenRecordingGranted
        accessibilityGranted = PermissionsManager.isAccessibilityGranted
    }
}

private struct PermissionSetupRow: View {
    let title: String
    let description: String
    let granted: Bool
    let buttonTitle: String
    var note: String? = nil
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !granted {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(granted ? Color.green.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(granted ? Color.green.opacity(0.45) : Color(NSColor.separatorColor), lineWidth: 1)
                )
        )
    }
}

#Preview {
    PermissionsOnboardingView(onContinue: {})
}
