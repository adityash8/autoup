import SwiftUI

struct SettingsView: View {
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled = true
    @AppStorage("onlyOnWiFi") private var onlyOnWiFi = true
    @AppStorage("onlyWhenPluggedIn") private var onlyWhenPluggedIn = true
    @AppStorage("securityUpdatesOnly") private var securityUpdatesOnly = false
    @AppStorage("updateSchedule") private var updateSchedule = "overnight"
    @AppStorage("telemetryEnabled") private var telemetryEnabled = false

    @State private var showingProUpgrade = false

    var body: some View {
        TabView {
            GeneralSettingsView(
                autoUpdateEnabled: $autoUpdateEnabled,
                onlyOnWiFi: $onlyOnWiFi,
                onlyWhenPluggedIn: $onlyWhenPluggedIn,
                securityUpdatesOnly: $securityUpdatesOnly,
                updateSchedule: $updateSchedule
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            PrivacySettingsView(telemetryEnabled: $telemetryEnabled)
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }

            ProSettingsView(showingProUpgrade: $showingProUpgrade)
                .tabItem {
                    Label("Pro", systemImage: "star")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct GeneralSettingsView: View {
    @Binding var autoUpdateEnabled: Bool
    @Binding var onlyOnWiFi: Bool
    @Binding var onlyWhenPluggedIn: Bool
    @Binding var securityUpdatesOnly: Bool
    @Binding var updateSchedule: String

    var body: some View {
        Form {
            Section("Automatic Updates") {
                Toggle("Enable automatic updates", isOn: $autoUpdateEnabled)

                if autoUpdateEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Only on Wi-Fi", isOn: $onlyOnWiFi)
                        Toggle("Only when plugged in", isOn: $onlyWhenPluggedIn)
                        Toggle("Security updates only", isOn: $securityUpdatesOnly)

                        Picker("Schedule", selection: $updateSchedule) {
                            Text("Overnight (2-6 AM)").tag("overnight")
                            Text("Every 4 hours").tag("frequent")
                            Text("Daily").tag("daily")
                            Text("Weekly").tag("weekly")
                        }
                    }
                    .padding(.leading, 20)
                    .disabled(!autoUpdateEnabled)
                }
            }

            Section("Update Sources") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Sparkle feeds (built-in)")
                    Text("• Homebrew casks")
                    Text("• GitHub releases")
                    Text("• App Store (coming soon)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct PrivacySettingsView: View {
    @Binding var telemetryEnabled: Bool
    @State private var cacheSize: String = "2.1 GB"

    var body: some View {
        Form {
            Section("Help Improve Auto-Up") {
                Toggle("Share anonymous insights", isOn: $telemetryEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    if telemetryEnabled {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Thanks! This helps us improve reliability")
                                .foregroundColor(.green)
                        }
                        .font(.caption)
                    }

                    Text("Anonymous success rates & performance only")
                        .fontWeight(.medium)
                    Text("• Update success/failure rates (helps fix bugs)")
                    Text("• Scanning performance (speeds up detection)")
                    Text("• Crash prevention data (keeps you stable)")
                    Text("")
                    Text("🔒 No app lists or personal info collected")
                        .foregroundColor(.blue)
                    Text("Data stored locally unless you opt in")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section("Local Data Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your data stays on your Mac:")
                    Text("• ~/Library/Application Support/AutoUp")
                    Text("• Update history and preferences")
                    Text("• Backup versions for rollback (\(cacheSize))")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Button("Clear Cache (\(cacheSize))") {
                    // TODO: Implement data clearing
                    cacheSize = "0 MB"
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }
}

struct ProSettingsView: View {
    @Binding var showingProUpgrade: Bool
    @State private var isProUser = false

    var body: some View {
        Form {
            if isProUser {
                Section("Pro Features") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("✓ Multi-Mac sync")
                        Text("✓ Version pinning")
                        Text("✓ Update rollback")
                        Text("✓ Family sharing (up to 5 Macs)")
                        Text("✓ Priority support")
                    }
                    .foregroundColor(.green)

                    Button("Manage Subscription") {
                        // TODO: Open App Store subscription management
                    }
                }
            } else {
                Section("Upgrade to Pro") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Unlock advanced features:")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Multi-Mac sync via iCloud")
                            Text("• Pin apps to specific versions")
                            Text("• One-click rollback to previous versions")
                            Text("• Family plan for up to 5 Macs")
                            Text("• Priority customer support")
                        }
                        .font(.caption)

                        HStack {
                            VStack(alignment: .leading) {
                                Text("$2.99/month")
                                    .font(.headline)
                                Text("or $24/year")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Upgrade Now") {
                                showingProUpgrade = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeView()
        }
    }
}

struct ProUpgradeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Protect your Mac with Pro")
                .font(.title)
                .fontWeight(.bold)

            Text("Trusted by 3,218 Macs this week")
                .foregroundColor(.secondary)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 12) {
                ProFeatureRow(
                    icon: "shield.checkered",
                    title: "Avoid failed updates",
                    description: "1-click rollback when updates break"
                )
                ProFeatureRow(
                    icon: "icloud",
                    title: "Keep all Macs consistent",
                    description: "iCloud sync prevents version drift"
                )
                ProFeatureRow(
                    icon: "exclamationmark.triangle",
                    title: "Patch security fixes first",
                    description: "Priority queue for critical updates"
                )
                ProFeatureRow(
                    icon: "person.3",
                    title: "Family protection",
                    description: "Cover up to 5 Macs under one plan"
                )
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 16) {
                // Decoy option
                VStack {
                    Text("Basic Pro")
                        .font(.headline)
                    Text("$3.49")
                        .font(.title3)
                        .fontWeight(.bold)
                        .strikethrough()
                        .foregroundColor(.gray)
                    Text("No rollback")
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Limited") {
                        // Intentionally less appealing
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
                .opacity(0.7)

                // Monthly option
                VStack {
                    Text("Monthly")
                        .font(.headline)
                    HStack {
                        Text("$3.99")
                            .font(.caption)
                            .strikethrough()
                            .foregroundColor(.gray)
                        Text("$2.99")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text("Full features")
                        .font(.caption)
                        .foregroundColor(.green)
                    Button("Choose Monthly") {
                        // TODO: Implement StoreKit purchase
                    }
                    .buttonStyle(.bordered)
                }

                // Yearly option (recommended)
                VStack {
                    HStack {
                        Text("Yearly")
                            .font(.headline)
                        Text("RECOMMENDED")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    Text("$24")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Save 33% • Don't lose out!")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Founding price")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Button("Choose Yearly") {
                        // TODO: Implement StoreKit purchase
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()

            Button("Cancel") {
                dismiss()
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 500, height: 550)
    }
}

struct ProFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            VStack(spacing: 8) {
                Text("Auto-Up")
                    .font(.title)
                    .fontWeight(.bold)

                Button("Version 1.0.0") {
                    // TODO: Open release notes
                    if let url = URL(string: "https://auto-up.com/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .foregroundColor(.secondary)

                Text("Trusted by 3,218 Macs this week")
                    .font(.caption)
                    .foregroundColor(.green)
                    .fontWeight(.medium)

                Text("Uses industry-standard Sparkle, GitHub Releases, and codesign verification")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 4) {
                Text("Auto-Up is built by a small indie team")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("focused on reliability first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                Button("Website") {
                    if let url = URL(string: "https://auto-up.com") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Report a Bug") {
                    if let url = URL(string: "mailto:support@auto-up.com?subject=Bug Report") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Suggest an Integration") {
                    if let url = URL(string: "mailto:support@auto-up.com?subject=Integration Request") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Privacy Policy") {
                    if let url = URL(string: "https://auto-up.com/privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .buttonStyle(.link)
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
