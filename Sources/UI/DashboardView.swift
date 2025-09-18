import SwiftUI

struct DashboardView: View {
    @StateObject private var appScanner = AppScanner()
    @StateObject private var updateDetector = UpdateDetector()
    @StateObject private var proManager = ProManager()
    @StateObject private var databaseManager = DatabaseManager()

    @State private var overallHealthScore: OverallHealthScore?
    @State private var availableUpdates: [UpdateInfo] = []
    @State private var updateHistory: [UpdateHistory] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Health Score Overview
                if let healthScore = overallHealthScore {
                    HealthScoreCardView(healthScore: healthScore)
                }

                // Quick Actions
                QuickActionsView(
                    onScanApps: {
                        Task { await refreshData() }
                    },
                    onUpdateAll: {
                        Task { await updateAllApps() }
                    }
                )

                // Recent Updates
                if !updateHistory.isEmpty {
                    RecentUpdatesView(history: updateHistory)
                }

                // Available Updates Summary
                if !availableUpdates.isEmpty {
                    AvailableUpdatesView(updates: availableUpdates)
                }

                // Pro Features Banner
                if !proManager.isProUser {
                    ProBannerView()
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .task {
            await refreshData()
        }
    }

    private func refreshData() async {
        let apps = await appScanner.scanInstalledApps()
        let updates = await updateDetector.checkForUpdates(apps: apps)

        await MainActor.run {
            availableUpdates = updates
            updateHistory = databaseManager.loadUpdateHistory(limit: 5)

            let calculator = HealthScoreCalculator()
            overallHealthScore = calculator.calculateOverallHealthScore(apps: apps, updates: updates)
        }
    }

    private func updateAllApps() async {
        let installManager = InstallManager()

        for update in availableUpdates {
            do {
                try await installManager.installUpdate(update)
            } catch {
                print("Failed to update \(update.appInfo.name): \(error)")
            }
        }

        await refreshData()
    }
}

struct HealthScoreCardView: View {
    let healthScore: OverallHealthScore

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Health Score")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(healthScore.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(lineWidth: 8)
                        .opacity(0.1)
                        .foregroundColor(colorForScore)

                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(healthScore.healthyPercentage, 100)) / 100.0)
                        .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        .foregroundColor(colorForScore)
                        .rotationEffect(Angle(degrees: 270.0))
                        .animation(.linear, value: healthScore.healthyPercentage)

                    Text("\(healthScore.healthyPercentage)%")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .frame(width: 60, height: 60)
            }

            HStack(spacing: 20) {
                HealthStatView(
                    title: "Current",
                    count: healthScore.currentApps,
                    color: .green
                )

                HealthStatView(
                    title: "Updates",
                    count: healthScore.updatesAvailable,
                    color: .yellow
                )

                HealthStatView(
                    title: "Security",
                    count: healthScore.securityUpdates,
                    color: .red
                )

                if healthScore.tahoeIncompatible > 0 {
                    HealthStatView(
                        title: "Tahoe Issues",
                        count: healthScore.tahoeIncompatible,
                        color: .purple
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var colorForScore: Color {
        switch healthScore.color {
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        case "purple": return .purple
        default: return .gray
        }
    }
}

struct HealthStatView: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct QuickActionsView: View {
    let onScanApps: () -> Void
    let onUpdateAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: onScanApps) {
                    Label("Scan Apps", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onUpdateAll) {
                    Label("Update All", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RecentUpdatesView: View {
    let history: [UpdateHistory]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Updates")
                .font(.headline)

            ForEach(history.prefix(3)) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.appInfo.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("\(item.fromVersion) → \(item.toVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(item.installedAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                if item.id != history.prefix(3).last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AvailableUpdatesView: View {
    let updates: [UpdateInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Updates")
                    .font(.headline)

                Spacer()

                Text("\(updates.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }

            ForEach(updates.prefix(5)) { update in
                HStack {
                    HealthIndicatorView(
                        healthScore: update.isSecurityUpdate ? .securityUpdate : .updateAvailable
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.appInfo.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("\(update.appInfo.version) → \(update.availableVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

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
                .padding(.vertical, 4)

                if update.id != updates.prefix(5).last?.id {
                    Divider()
                }
            }

            if updates.count > 5 {
                Text("And \(updates.count - 5) more...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ProBannerView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)

                Text("Upgrade to Auto-Up Pro")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Multi-Mac sync")
                    Text("• Version pinning")
                    Text("• One-click rollback")
                    Text("• Family sharing")
                }
                .font(.caption)

                Spacer()

                VStack {
                    Text("$2.99/mo")
                        .font(.subheadline)
                        .fontWeight(.bold)

                    Button("Upgrade") {
                        // Open Pro upgrade sheet
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.blue.opacity(0.1), .purple.opacity(0.1)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    DashboardView()
}