//  SettingsSidebar.swift
//  Wardlume
//
//  Grouped left navigation + a pinned bottom block: app-identity card, footer
//  rows (Check updates / About / Privacy / Terms), and a Support button.

import SwiftUI
import AppKit

struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(SettingsGroup.allCases) { group in
                    Section {
                        ForEach(group.panes) { pane in
                            Label(pane.title, systemImage: pane.symbol)
                                .tag(pane)
                        }
                    } header: {
                        Text(group.rawValue.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Theme.sidebarBackground)

            footer
        }
        .background(Theme.sidebarBackground)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider().overlay(Theme.separator)

            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(Theme.accentTealDim).frame(width: 30, height: 30)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wardlume \(appVersion)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Made for macOS")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.cardBackground))

            footerRow("Check updates", "arrow.triangle.2.circlepath") {
                open("https://github.com/arpitagarwal1301/wardlume/releases/latest")
            }
            footerRow("About", "info.circle") { selection = .about }
            footerRow("Privacy", "lock.shield") { selection = .privacy }
            footerRow("Terms", "doc.text") { selection = .terms }

            Button {
                open("https://github.com/sponsors/arpitagarwal1301")
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "heart.fill")
                    Text("Support Wardlume")
                }
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accentTeal.opacity(0.16)))
                .foregroundStyle(Theme.accentTeal)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    private func footerRow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 14)).frame(width: 18)
                Text(title).font(.system(size: 12.5))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
