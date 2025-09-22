import AppKit
import SwiftUI

@main
struct AutoUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarItem: NSStatusItem?
    private var popover: NSPopover?
    private var appScanner: AppScanner?
    private var updateDetector: UpdateDetector?
    private var installManager: InstallManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're a menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Initialize core services
        setupServices()

        // Setup menu bar
        setupMenuBar()

        // Setup popover
        setupPopover()

        // Initial scan
        Task {
            await performInitialScan()
        }
    }

    @MainActor private func setupServices() {
        appScanner = AppScanner()
        updateDetector = UpdateDetector()
        installManager = InstallManager()
    }

    private func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let statusBarItem = statusBarItem, let button = statusBarItem.button {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath",
                accessibilityDescription: "Auto-Up"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }

        updateBadge(count: 0)
    }

    private func setupPopover() {
        let newPopover = NSPopover()
        newPopover.contentSize = NSSize(width: 400, height: 500)
        newPopover.behavior = .transient
        newPopover.contentViewController = NSHostingController(rootView: MainPopoverView())
        popover = newPopover
    }

    @objc private func togglePopover() {
        guard let statusBarItem = statusBarItem,
              let popover = popover,
              let button = statusBarItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateBadge(count: Int) {
        guard let statusBarItem = statusBarItem,
              let button = statusBarItem.button else {
            return
        }

        if count > 0 {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath.circle.fill",
                accessibilityDescription: "Auto-Up - \(count) updates available"
            )
            // Add badge number overlay
            button.title = " \(count)"
        } else {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath",
                accessibilityDescription: "Auto-Up"
            )
            button.title = ""
        }
    }

    private func performInitialScan() async {
        guard let appScanner = appScanner,
              let updateDetector = updateDetector else {
            print("Services not initialized")
            return
        }

        let apps = await appScanner.scanInstalledApps()
        let updates = await updateDetector.checkForUpdates(apps: apps)

        await MainActor.run {
            updateBadge(count: updates.count)
        }
    }
}
