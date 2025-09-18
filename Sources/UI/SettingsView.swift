import SwiftUI

struct SettingsView: View {
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled = false
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

    var body: some View {
        Form {
            Section("Data Collection") {
                Toggle("Help improve Auto-Up", isOn: $telemetryEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("When enabled, Auto-Up collects anonymous usage data to help improve the app:")
                    Text("• Update success/failure rates")
                    Text("• App scanning performance")
                    Text("• Feature usage statistics")
                    Text("")
                    Text("No personal information or app lists are collected.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section("Local Data") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("All app data is stored locally on your Mac:")
                    Text("• SQLite database in ~/Library/Application Support/AutoUp")
                    Text("• Update history and preferences")
                    Text("• Cached app versions for rollback")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Button("Clear All Data") {
                    // TODO: Implement data clearing
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
            Text("Upgrade to Auto-Up Pro")
                .font(.title)
                .fontWeight(.bold)

            Text("Get the most out of Auto-Up with Pro features")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ProFeatureRow(icon: "icloud", title: "Multi-Mac Sync", description: "Sync settings across all your Macs")
                ProFeatureRow(icon: "pin", title: "Version Pinning", description: "Stay on your preferred app versions")
                ProFeatureRow(icon: "arrow.uturn.backward", title: "One-Click Rollback", description: "Instantly revert to previous versions")
                ProFeatureRow(icon: "person.3", title: "Family Sharing", description: "Cover up to 5 Macs under one plan")
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                VStack {
                    Text("Monthly")
                        .font(.headline)
                    Text("$2.99")
                        .font(.title2)
                        .fontWeight(.bold)
                    Button("Choose Monthly") {
                        // TODO: Implement StoreKit purchase
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                VStack {
                    Text("Yearly")
                        .font(.headline)
                    Text("$24")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Save 33%")
                        .font(.caption)
                        .foregroundColor(.green)
                    Button("Choose Yearly") {
                        // TODO: Implement StoreKit purchase
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()

            Button("Cancel") {
                dismiss()
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 400, height: 500)
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

                Text("Version 1.0.0")
                    .foregroundColor(.secondary)

                Text("Keep your Mac apps fresh and secure")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                Button("Website") {
                    // TODO: Open website
                }

                Button("Support") {
                    // TODO: Open support
                }

                Button("Privacy Policy") {
                    // TODO: Open privacy policy
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