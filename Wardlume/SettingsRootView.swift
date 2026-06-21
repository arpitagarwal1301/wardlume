//  SettingsRootView.swift
//  Wardlume
//
//  Top-level SwiftUI root for the revamped settings window: a forced-dark,
//  TWO-column NavigationSplitView (grouped sidebar | content). Ward status lives
//  in the Overview pane (no redundant persistent side panel). Replaces
//  PreferencesView as the window root.
//
//  Batch A: shell + navigation + a real Overview pane (status / permissions /
//  Touch ID). Pack & assets, Shortcuts, Behavior land in later increments.

import SwiftUI
import AppKit

// MARK: — Navigation model

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case overview, packAssets, shortcuts, behavior   // primary nav
    case about, privacy, terms                        // reached via sidebar footer rows
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:   "Overview"
        case .packAssets: "Pack & assets"
        case .shortcuts:  "Shortcuts"
        case .behavior:   "Behavior"
        case .about:      "About"
        case .privacy:    "Privacy"
        case .terms:      "Terms"
        }
    }

    var symbol: String {
        switch self {
        case .overview:   "shield"
        case .packAssets: "photo"
        case .shortcuts:  "keyboard"
        case .behavior:   "slider.horizontal.3"
        case .about:      "info.circle"
        case .privacy:    "lock.shield"
        case .terms:      "doc.text"
        }
    }
}

/// Sidebar grouping. Only "Core" exists for now; more groups can be added as new
/// categories emerge — the sidebar renders whatever groups are declared here.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case core = "Core"
    var id: String { rawValue }
    var panes: [SettingsPane] {
        switch self {
        case .core: [.overview, .packAssets, .shortcuts, .behavior]
        }
    }
}

// MARK: — Root

struct SettingsRootView: View {
    @EnvironmentObject var wardState: WardState
    @EnvironmentObject var wardPrefs: WardPrefs
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var reactionManager: ReactionManager

    @State private var selection: SettingsPane? = .overview

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(Theme.sidebarWidth)
        } detail: {
            ScrollView {
                centerPane
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.windowBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .tint(Theme.accentTeal)
        .frame(minWidth: 760, minHeight: 560)
    }

    @ViewBuilder private var centerPane: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewPane()
        case .packAssets:
            PackAssetsPane()
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text((selection ?? .overview).title)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("This section is coming together — its controls land in an upcoming step.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: — Overview pane

private struct OverviewPane: View {
    @EnvironmentObject var wardState: WardState
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Overview")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Ward status, permissions, and unlocking.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            statusCard
            permissionsCard
            touchIDCard
        }
    }

    private var statusCard: some View {
        HStack {
            HStack(spacing: 11) {
                Circle()
                    .fill(wardState.isActive ? Theme.statusActive : Theme.statusInactive)
                    .frame(width: 11, height: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wardState.isActive ? "Ward active" : "Ward inactive")
                        .font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                    Text(wardState.isActive ? "Input is locked" : "Your Mac is interactive")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Button { wardState.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: wardState.isActive ? "lock.open" : "lock")
                    Text(wardState.isActive ? "Deactivate" : "Activate")
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 15).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentTealDim))
                .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .wardCard()
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Permissions")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 6)

            permissionRow("Screen recording",
                          desc: "Renders the live desktop behind the glass ward",
                          granted: wardState.screenRecordingGranted,
                          pane: "Privacy_ScreenCapture")
            Divider().overlay(Theme.separator)
            permissionRow("Accessibility",
                          desc: "Locks keyboard, mouse, and trackpad",
                          granted: wardState.accessibilityGranted,
                          pane: "Privacy_Accessibility")
            Divider().overlay(Theme.separator)
            permissionRow("Input monitoring",
                          desc: "Detects intrusion attempts",
                          granted: wardState.inputMonitoringGranted,
                          pane: "Privacy_ListenEvent")
        }
        .wardCard()
    }

    private func permissionRow(_ name: String, desc: String, granted: Bool, pane: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 19))
                .foregroundStyle(granted ? Theme.statusActive : Theme.warning)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13.5)).foregroundStyle(Theme.textPrimary)
                Text(desc).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if granted {
                Text("Enabled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.statusActive)
            } else {
                Button { openSettings(pane) } label: {
                    Text("Enable")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 13).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.warning.opacity(0.16)))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.warning.opacity(0.5), lineWidth: 0.5))
                        .foregroundStyle(Theme.warning)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    private var touchIDCard: some View {
        HStack(alignment: .top, spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(Theme.danger.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "touchid")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.danger)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Unlock with Touch ID")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Rest your finger on the sensor while the ward is active.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    Text("or press")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                    HotkeyKeycaps(combo: hotkeyManager.unlock)
                }
                .padding(.top, 2)
                Text(hotkeyManager.unlock.spokenString)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .wardCard()
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: — Pack & assets pane

private struct PackAssetsPane: View {
    @EnvironmentObject var reactionManager: ReactionManager
    @EnvironmentObject var userAssets: UserAssetManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Pack & assets")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Choose the reaction pack and personalize the ward with your own visuals and sound.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            reactionCard
            assetsCard
        }
    }

    private var reactionCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Reaction pack").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("", selection: $reactionManager.activePackID) {
                    ForEach(ReactionPack.all, id: \.id) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            Divider().overlay(Theme.separator)

            Toggle(isOn: $reactionManager.audioEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play sound on intrusion").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    Text("Plays the pack's audio if available. Some packs are silent.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.accentTeal)

            Divider().overlay(Theme.separator)

            VStack(alignment: .leading, spacing: 7) {
                Text("Cooldown").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                Picker("", selection: $reactionManager.cooldown) {
                    Text("1s").tag(1.0)
                    Text("3s").tag(3.0)
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text("Minimum time between reactions.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }

            Divider().overlay(Theme.separator)

            Button { reactionManager.triggerForPreview() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill").font(.system(size: 11))
                    Text("Test reaction")
                }
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.keycapBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle, lineWidth: 0.5))
                .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .wardCard()
    }

    private var assetsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Text("Custom assets")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Optional")
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            Text("Make the ward your own. Drag a file onto a slot or click Browse — leave blank to use the pack's default.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

            AssetRow(role: .cover,
                     assetURL: userAssets.baseImageURL,
                     set: { try userAssets.setBaseImage(from: $0) },
                     clear: { userAssets.clearBaseImage() })

            Divider().overlay(Theme.separator).padding(.vertical, 2)

            HStack(spacing: 7) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                Text("WHEN SOMEONE TOUCHES YOUR MAC")
                    .font(.system(size: 11)).tracking(0.4)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                AssetRow(role: .reaction,
                         assetURL: userAssets.reactionImageURL,
                         set: { try userAssets.setReactionImage(from: $0) },
                         clear: { userAssets.clearReactionImage() })
                Divider().overlay(Theme.separator.opacity(0.6))
                AssetRow(role: .sound,
                         assetURL: userAssets.audioURL,
                         set: { try userAssets.setAudio(from: $0) },
                         clear: { userAssets.clearAudio() })
            }
            .padding(.leading, 14)
            .overlay(
                Rectangle().fill(Theme.accentTeal.opacity(0.25)).frame(width: 2),
                alignment: .leading)
        }
        .wardCard()
    }
}

// MARK: — Keycaps (reused by the Shortcuts pane)

/// Renders a HotkeyCombo as discrete keyboard keycaps, e.g. ⌘ ⇧ U. Reflects
/// whatever combo the user has chosen.
struct HotkeyKeycaps: View {
    let combo: HotkeyCombo

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(capLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .frame(minWidth: 28, minHeight: 30)
                    .padding(.horizontal, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.keycapBackground))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle, lineWidth: 0.5))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private var capLabels: [String] {
        var labels: [String] = []
        if combo.modifiers.contains(.control) { labels.append("⌃") }
        if combo.modifiers.contains(.option)  { labels.append("⌥") }
        if combo.modifiers.contains(.shift)   { labels.append("⇧") }
        if combo.modifiers.contains(.command) { labels.append("⌘") }
        labels.append(HotkeyCombo.keyName(for: combo.keyCode))
        return labels
    }
}

// MARK: — Shared card styling

private extension View {
    func wardCard() -> some View {
        self
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11).fill(Theme.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.separator, lineWidth: 0.5))
    }
}
