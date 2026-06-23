import Foundation
import Network

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(IOKit)
import IOKit
#endif

#if canImport(IOKit.ps)
import IOKit.ps
#endif

class BackgroundScheduler: ObservableObject {
    @Published var isScheduled = false
    @Published var lastRunDate: Date?
    @Published var nextRunDate: Date?

    private let backgroundTaskIdentifier = "com.autoup.background-update-check"
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "BackgroundScheduler")

    private var appScanner: AppScanner?
    private var updateDetector: UpdateDetector?
    private var installManager: InstallManager?

    private var supportsBGTasks: Bool {
        #if canImport(BackgroundTasks) && !os(macOS)
        return true
        #else
        return false
        #endif
    }

    init() {
        if supportsBGTasks {
            registerBackgroundTask()
        }
        startNetworkMonitoring()
    }

    deinit {
        pathMonitor.cancel()
    }

    func setupServices(
        appScanner: AppScanner,
        updateDetector: UpdateDetector,
        installManager: InstallManager
    ) {
        self.appScanner = appScanner
        self.updateDetector = updateDetector
        self.installManager = installManager
    }

    func enableBackgroundUpdates() {
        if supportsBGTasks {
            scheduleBackgroundTask()
        }
        isScheduled = supportsBGTasks
    }

    func disableBackgroundUpdates() {
        if supportsBGTasks {
            cancelBackgroundTask()
        }
        isScheduled = false
    }

    #if canImport(BackgroundTasks) && !os(macOS)
    private func registerBackgroundTask() {
        BGTaskScheduler.shared
            .register(forTaskWithIdentifier: backgroundTaskIdentifier, using: queue) { task in
                self.handleBackgroundUpdateCheck(task: task as! BGAppRefreshTask)
            }
    }

    private func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 8 * 60 * 60) // 8 hours from now

        do {
            try BGTaskScheduler.shared.submit(request)
            nextRunDate = request.earliestBeginDate
            print("Background task scheduled for: \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            print("Could not schedule background task: \(error)")
        }
    }

    private func cancelBackgroundTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        nextRunDate = nil
        print("Background task cancelled")
    }

    private func handleBackgroundUpdateCheck(task: BGAppRefreshTask) {
        // Schedule the next background task
        scheduleBackgroundTask()

        // Check if conditions are met for background updates
        guard shouldRunBackgroundUpdate() else {
            print("Background update conditions not met")
            task.setTaskCompleted(success: true)
            return
        }

        let operation = BackgroundUpdateOperation(
            appScanner: appScanner,
            updateDetector: updateDetector,
            installManager: installManager
        )

        task.expirationHandler = {
            operation.cancel()
        }

        operation.completionBlock = {
            DispatchQueue.main.async {
                self.lastRunDate = Date()
            }
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        let operationQueue = OperationQueue()
        operationQueue.addOperation(operation)
    }
    #else
    // Fallbacks for platforms without BackgroundTasks (e.g., macOS)
    private func registerBackgroundTask() { /* no-op */ }
    private func scheduleBackgroundTask() { /* no-op */ }
    private func cancelBackgroundTask() { /* no-op */ }
    #endif

    private func shouldRunBackgroundUpdate() -> Bool {
        // Check if device is plugged in
        if UserDefaults.standard.bool(forKey: "onlyWhenPluggedIn") {
            guard isPluggedIn() else {
                print("Device not plugged in, skipping background update")
                return false
            }
        }

        // Check if on Wi-Fi
        if UserDefaults.standard.bool(forKey: "onlyOnWiFi") {
            guard isOnWiFi() else {
                print("Not on Wi-Fi, skipping background update")
                return false
            }
        }

        return true
    }

    private func isPluggedIn() -> Bool {
        #if canImport(IOKit) && canImport(IOKit.ps)
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return false
        }

        for ps in list {
            guard let dict = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            let isCharging = (dict[kIOPSIsChargingKey as String] as? Bool) ?? false
            let state = dict[kIOPSPowerSourceStateKey as String] as? String
            if isCharging || state == kIOPSACPowerValue { return true }
        }
        return false
        #else
        // If power source APIs are unavailable, assume not plugged in
        return false
        #endif
    }

    private func isOnWiFi() -> Bool {
        // NWPathMonitor exposes currentPath on Apple platforms; guard just in case
        pathMonitor.currentPath.status == .satisfied && pathMonitor.currentPath.usesInterfaceType(.wifi)
    }

    private func startNetworkMonitoring() {
        pathMonitor.start(queue: queue)
    }
}

class BackgroundUpdateOperation: Operation, @unchecked Sendable {
    private let appScanner: AppScanner?
    private let updateDetector: UpdateDetector?
    private let installManager: InstallManager?

    private var _executing = false
    private var _finished = false

    override var isExecuting: Bool {
        _executing
    }

    override var isFinished: Bool {
        _finished
    }

    init(appScanner: AppScanner?, updateDetector: UpdateDetector?, installManager: InstallManager?) {
        self.appScanner = appScanner
        self.updateDetector = updateDetector
        self.installManager = installManager
        super.init()
    }

    override func start() {
        guard !isCancelled else {
            finish()
            return
        }

        willChangeValue(forKey: "isExecuting")
        _executing = true
        didChangeValue(forKey: "isExecuting")

        Task {
            await performBackgroundUpdate()
        }
    }

    override func cancel() {
        super.cancel()
        finish()
    }

    private func finish() {
        willChangeValue(forKey: "isExecuting")
        willChangeValue(forKey: "isFinished")
        _executing = false
        _finished = true
        didChangeValue(forKey: "isExecuting")
        didChangeValue(forKey: "isFinished")
    }

    @MainActor
    private func performBackgroundUpdate() async {
        guard let appScanner,
              let updateDetector,
              let installManager
        else {
            print("Background update: Services not available")
            finish()
            return
        }

        print("Background update: Starting app scan")
        let apps = await appScanner.scanInstalledApps()

        guard !isCancelled else {
            finish()
            return
        }

        print("Background update: Checking for updates")
        let updates = await updateDetector.checkForUpdates(apps: apps)

        guard !isCancelled else {
            finish()
            return
        }

        // Filter updates based on user preferences
        let filteredUpdates = filterUpdatesForBackground(updates)

        if !filteredUpdates.isEmpty {
            print("Background update: Installing \(filteredUpdates.count) updates")

            for update in filteredUpdates {
                guard !isCancelled else {
                    finish()
                    return
                }

                do {
                    try await installManager.installUpdate(update)
                    print("Background update: Successfully updated \(update.appInfo.name)")
                } catch {
                    print("Background update: Failed to update \(update.appInfo.name): \(error)")
                }
            }

            // Send notification about completed updates
            sendUpdateNotification(updatedApps: filteredUpdates.map(\.appInfo.name))
        } else {
            print("Background update: No updates to install")
        }

        finish()
    }

    private func filterUpdatesForBackground(_ updates: [UpdateInfo]) -> [UpdateInfo] {
        let securityOnly = UserDefaults.standard.bool(forKey: "securityUpdatesOnly")

        if securityOnly {
            return updates.filter(\.isSecurityUpdate)
        } else {
            return updates
        }
    }

    private func sendUpdateNotification(updatedApps: [String]) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "Auto-Up"

        if updatedApps.count == 1 {
            content.body = "Updated \(updatedApps.first!)"
        } else {
            content.body = "Updated \(updatedApps.count) apps"
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "background-update-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Error sending notification: \(error)")
            }
        }
        #else
        // Notifications not available on this platform
        print("Notifications not available on this platform. Updated apps: \(updatedApps)")
        #endif
    }
}

// MARK: - Notification Permissions

extension BackgroundScheduler {
    func requestNotificationPermissions() async -> Bool {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Error requesting notification permissions: \(error)")
            return false
        }
        #else
        return false
        #endif
    }

    func checkNotificationPermissions() async -> Any {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
        #else
        return "Unavailable"
        #endif
    }
}
