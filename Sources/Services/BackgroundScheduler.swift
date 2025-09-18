import Foundation
import BackgroundTasks
import Network
import IOKit

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

    init() {
        registerBackgroundTask()
        startNetworkMonitoring()
    }

    deinit {
        pathMonitor.cancel()
    }

    func setupServices(appScanner: AppScanner, updateDetector: UpdateDetector, installManager: InstallManager) {
        self.appScanner = appScanner
        self.updateDetector = updateDetector
        self.installManager = installManager
    }

    func enableBackgroundUpdates() {
        scheduleBackgroundTask()
        isScheduled = true
    }

    func disableBackgroundUpdates() {
        cancelBackgroundTask()
        isScheduled = false
    }

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: queue) { task in
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
        let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        guard let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }

        for powerSource in powerSources {
            guard let powerSourceDescription = IOPSGetPowerSourceDescription(powerSourceInfo, powerSource)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let isCharging = powerSourceDescription[kIOPSIsChargingKey] as? Bool,
               let powerSourceState = powerSourceDescription[kIOPSPowerSourceStateKey] as? String {
                return isCharging || powerSourceState == kIOPSACPowerValue
            }
        }

        return false
    }

    private func isOnWiFi() -> Bool {
        return pathMonitor.currentPath.usesInterfaceType(.wifi)
    }

    private func startNetworkMonitoring() {
        pathMonitor.start(queue: queue)
    }
}

class BackgroundUpdateOperation: Operation {
    private let appScanner: AppScanner?
    private let updateDetector: UpdateDetector?
    private let installManager: InstallManager?

    private var _executing = false
    private var _finished = false

    override var isExecuting: Bool {
        return _executing
    }

    override var isFinished: Bool {
        return _finished
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
        guard let appScanner = appScanner,
              let updateDetector = updateDetector,
              let installManager = installManager else {
            print("Background update: Services not available")
            finish()
            return
        }

        do {
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
                sendUpdateNotification(updatedApps: filteredUpdates.map { $0.appInfo.name })
            } else {
                print("Background update: No updates to install")
            }

            finish()

        } catch {
            print("Background update error: \(error)")
            finish()
        }
    }

    private func filterUpdatesForBackground(_ updates: [UpdateInfo]) -> [UpdateInfo] {
        let securityOnly = UserDefaults.standard.bool(forKey: "securityUpdatesOnly")

        if securityOnly {
            return updates.filter { $0.isSecurityUpdate }
        } else {
            return updates
        }
    }

    private func sendUpdateNotification(updatedApps: [String]) {
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
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }
    }
}

// MARK: - Notification Permissions

extension BackgroundScheduler {
    func requestNotificationPermissions() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Error requesting notification permissions: \(error)")
            return false
        }
    }

    func checkNotificationPermissions() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
}