import SwiftUI

struct MainPopoverView: View {
    @StateObject private var appScanner = AppScanner()
    @StateObject private var updateDetector = UpdateDetector()
    @State private var availableUpdates: [UpdateInfo] = []
    @State private var showingSettings = false
    @State private var isUpdating = false

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
                Text("Auto-Up")
                    .font(.title2)
                    .fontWeight(.bold)

                if !availableUpdates.isEmpty {
                    Text("\(availableUpdates.count) updates available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("All apps up to date")
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
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Scanning installed apps...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                Text("Your Mac is up to date")
                    .font(.body)
                    .foregroundColor(.secondary)
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

                    HealthIndicatorView(healthScore: update.isSecurityUpdate ? .securityUpdate : .updateAvailable)
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
            return .green
        case .updateAvailable:
            return .yellow
        case .securityUpdate:
            return .red
        case .tahoeIncompatible:
            return .purple
        }
    }
}

#Preview {
    MainPopoverView()
}