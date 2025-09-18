import SwiftUI
import AppKit

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
    private var statusBarItem: NSStatusItem!
    private var popover: NSPopover!
    private var appScanner: AppScanner!
    private var updateDetector: UpdateDetector!
    private var installManager: InstallManager!

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

    private func setupServices() {
        appScanner = AppScanner()
        updateDetector = UpdateDetector()
        installManager = InstallManager()
    }

    private func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Auto-Up")
            button.action = #selector(togglePopover)
            button.target = self
        }

        updateBadge(count: 0)
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MainPopoverView())
    }

    @objc private func togglePopover() {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func updateBadge(count: Int) {
        if let button = statusBarItem.button {
            if count > 0 {
                button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle.fill", accessibilityDescription: "Auto-Up - \(count) updates available")
                // Add badge number overlay
                button.title = " \(count)"
            } else {
                button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Auto-Up")
                button.title = ""
            }
        }
    }

    private func performInitialScan() async {
        let apps = await appScanner.scanInstalledApps()
        let updates = await updateDetector.checkForUpdates(apps: apps)

        await MainActor.run {
            updateBadge(count: updates.count)
        }
    }
}