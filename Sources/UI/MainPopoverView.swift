import SwiftUI

struct MainPopoverView: View {
    @StateObject private var appScanner = AppScanner()
    @StateObject private var updateDetector = UpdateDetector()
    @State private var availableUpdates: [UpdateInfo] = []
    @State private var showingSettings = false
    @State private var isUpdating = false
    @State private var scanProgress: Double = 0.0
    @State private var lastScanDate: Date = .init()
    @State private var streakDays: Int = 7

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if appScanner.isScanning {
                scanningView
            } else if availableUpdates.isEmpty {
                allUpToDateView
            } else {
                updatesListView
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 400, height: 500)
        .task {
            await refreshData()
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if !availableUpdates.isEmpty {
                    let securityCount = availableUpdates.filter(\.isSecurityUpdate).count
                    if securityCount > 0 {
                        Text("⚠️ Don't risk unpatched apps")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        Text("\(securityCount) security fix\(securityCount == 1 ? "" : "es") pending")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Text("Updates Available")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Avoid crashes and bugs")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("✅ All Fresh!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Your Mac is protected")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Button(action: { showingSettings.toggle() }) {
                Image(systemName: "gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .frame(width: 500, height: 400)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            // Progress indicator with Zeigarnik Effect
            VStack(spacing: 8) {
                Text("Step 1/2 • Scanning • Almost there...")
                    .font(.headline)
                    .foregroundColor(.blue)

                ProgressView(value: scanProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(width: 200)

                Text("\(Int(scanProgress * 100))% complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.blue)
                    Text("Scanning installed apps...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("This helps us find security updates")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Animate progress for Zeigarnik Effect
            withAnimation(.easeInOut(duration: 2.0)) {
                scanProgress = 0.7
            }
        }
    }

    private var allUpToDateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("All Fresh!")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Your Mac is protected")
                    .font(.body)
                    .foregroundColor(.secondary)

                // Social Proof + Streak (Goal Gradient)
                Text("Last scan: \(formatRelativeTime(lastScanDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if streakDays > 0 {
                    Text("\(streakDays)-day safe streak — keep it going!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Button("Scan Again") {
                Task {
                    await refreshData()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var updatesListView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(availableUpdates) { update in
                        UpdateRowView(update: update)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        if update.id != availableUpdates.last?.id {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    private var footerView: some View {
        HStack {
            Button("Refresh") {
                Task {
                    await refreshData()
                }
            }
            .buttonStyle(.bordered)
            .disabled(appScanner.isScanning || isUpdating)

            Spacer()

            if !availableUpdates.isEmpty {
                Button("Update All") {
                    Task {
                        await updateAllApps()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func refreshData() async {
        let apps = await appScanner.scanInstalledApps()
        let updates = await updateDetector.checkForUpdates(apps: apps)

        await MainActor.run {
            availableUpdates = updates
        }
    }

    private func updateAllApps() async {
        isUpdating = true
        defer { isUpdating = false }

        let installManager = InstallManager()

        for update in availableUpdates {
            do {
                try await installManager.installUpdate(update)
            } catch {
                print("Failed to install update for \(update.appInfo.name): \(error)")
            }
        }

        await refreshData()
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct UpdateRowView: View {
    let update: UpdateInfo

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            AsyncImage(url: URL(string: "file://\(update.appInfo.iconPath ?? "")")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "app.fill")
                    .foregroundColor(.secondary)
            }
            .frame(width: 32, height: 32)

            // App info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(update.appInfo.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    HealthIndicatorView(
                        healthScore: update
                            .isSecurityUpdate ? .securityUpdate : .updateAvailable
                    )
                }

                HStack {
                    Text("\(update.appInfo.version) → \(update.availableVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if update.isSecurityUpdate {
                        Text("SECURITY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }

                if let summary = update.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Update button
            Button("Update") {
                Task {
                    let installManager = InstallManager()
                    do {
                        try await installManager.installUpdate(update)
                    } catch {
                        print("Failed to install update: \(error)")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

struct HealthIndicatorView: View {
    let healthScore: HealthScore

    var body: some View {
        Circle()
            .fill(colorForHealthScore)
            .frame(width: 12, height: 12)
    }

    private var colorForHealthScore: Color {
        switch healthScore {
        case .current:
            .green
        case .updateAvailable:
            .yellow
        case .securityUpdate:
            .red
        case .tahoeIncompatible:
            .purple
        }
    }
}

#Preview {
    MainPopoverView()
}
