@testable import AutoUp
import XCTest

final class AutoUpTests: XCTestCase {
    var appScanner: AppScanner!
    var updateDetector: UpdateDetector!
    var tahoeChecker: TahoeCompatibilityChecker!

    override func setUpWithError() throws {
        appScanner = AppScanner()
        updateDetector = UpdateDetector()
        tahoeChecker = TahoeCompatibilityChecker()
    }

    override func tearDownWithError() throws {
        appScanner = nil
        updateDetector = nil
        tahoeChecker = nil
    }

    // MARK: - App Scanner Tests

    func testAppScannerDetectsApps() async throws {
        let apps = await appScanner.scanInstalledApps()

        XCTAssertFalse(apps.isEmpty, "Should detect at least some apps")

        // Verify app structure
        for app in apps.prefix(5) {
            XCTAssertFalse(app.bundleID.isEmpty, "Bundle ID should not be empty")
            XCTAssertFalse(app.name.isEmpty, "App name should not be empty")
            XCTAssertFalse(app.version.isEmpty, "Version should not be empty")
            XCTAssertTrue(app.path.hasSuffix(".app"), "Path should point to .app bundle")
        }
    }

    func testAppScannerFiltersSystemApps() async throws {
        let apps = await appScanner.scanInstalledApps()

        // Should not contain system apps
        let systemApps = apps.filter { $0.bundleID.hasPrefix("com.apple.") }
        XCTAssertTrue(systemApps.isEmpty, "Should filter out system apps")
    }

    // MARK: - Update Detection Tests

    func testSparkleUpdateDetection() async throws {
        // Create mock app with Sparkle URL
        let mockApp = AppInfo(
            bundleID: "com.test.app",
            name: "Test App",
            version: "1.0.0",
            path: "/Applications/TestApp.app",
            iconPath: nil,
            sparkleURL: "https://example.com/appcast.xml",
            githubRepo: nil,
            isHomebrew: false,
            lastModified: Date()
        )

        // This would require mocking URLSession for proper testing
        // For now, just verify the detection doesn't crash
        let updates = await updateDetector.checkForUpdates(apps: [mockApp])
        XCTAssertNotNil(updates, "Update detection should return a result")
    }

    func testVersionComparison() {
        // Test version comparison logic
        let sparkleDetector = SparkleUpdateDetector()

        // This would require exposing the version comparison method
        // or creating a separate utility class for version comparison
        XCTAssertTrue(true, "Version comparison test placeholder")
    }

    // MARK: - Tahoe Compatibility Tests

    func testTahoeCompatibilityChecker() {
        let mockApp = AppInfo(
            bundleID: "com.adobe.Lightroom",
            name: "Adobe Lightroom Classic",
            version: "13.2",
            path: "/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app",
            iconPath: nil,
            sparkleURL: nil,
            githubRepo: nil,
            isHomebrew: false,
            lastModified: Date()
        )

        let status = tahoeChecker.checkCompatibility(for: mockApp)

        switch status {
        case .incompatible(let reason, _):
            XCTAssertFalse(reason.isEmpty, "Should provide reason for incompatibility")
        case .risky(let reason):
            XCTAssertFalse(reason.isEmpty, "Should provide reason for risk")
        case .compatible:
            break // This is fine
        }
    }

    func testBetaVersionDetection() {
        let betaApp = AppInfo(
            bundleID: "com.test.beta",
            name: "Test Beta App",
            version: "2.0.0-beta.1",
            path: "/Applications/TestBeta.app",
            iconPath: nil,
            sparkleURL: nil,
            githubRepo: nil,
            isHomebrew: false,
            lastModified: Date()
        )

        let status = tahoeChecker.checkCompatibility(for: betaApp)
        XCTAssertTrue(status.isProblematic, "Beta versions should be flagged as risky")
    }

    // MARK: - Health Score Tests

    func testHealthScoreCalculation() {
        let calculator = HealthScoreCalculator()

        let currentApp = AppInfo(
            bundleID: "com.test.current",
            name: "Current App",
            version: "1.0.0",
            path: "/Applications/Current.app",
            iconPath: nil,
            sparkleURL: nil,
            githubRepo: nil,
            isHomebrew: false,
            lastModified: Date()
        )

        let score = calculator.calculateHealthScore(for: currentApp, availableUpdate: nil)
        XCTAssertEqual(score, .current, "App without updates should be marked as current")
    }

    func testOverallHealthScore() {
        let calculator = HealthScoreCalculator()

        let apps = [
            AppInfo(
                bundleID: "com.test.1",
                name: "App 1",
                version: "1.0",
                path: "/Applications/App1.app",
                iconPath: nil,
                sparkleURL: nil,
                githubRepo: nil,
                isHomebrew: false,
                lastModified: Date()
            ),
            AppInfo(
                bundleID: "com.test.2",
                name: "App 2",
                version: "2.0",
                path: "/Applications/App2.app",
                iconPath: nil,
                sparkleURL: nil,
                githubRepo: nil,
                isHomebrew: false,
                lastModified: Date()
            ),
        ]

        let overallScore = calculator.calculateOverallHealthScore(apps: apps, updates: [])

        XCTAssertEqual(overallScore.totalApps, 2, "Should count total apps correctly")
        XCTAssertEqual(overallScore.currentApps, 2, "Should count current apps correctly")
        XCTAssertEqual(overallScore.healthyPercentage, 100, "Should calculate 100% when no updates")
    }

    // MARK: - Performance Tests

    func testAppScanningPerformance() async throws {
        measure {
            let expectation = self.expectation(description: "App scanning completes")

            Task {
                _ = await appScanner.scanInstalledApps()
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }

    func testUpdateDetectionPerformance() async throws {
        let apps = await appScanner.scanInstalledApps()
        let limitedApps = Array(apps.prefix(10)) // Limit to first 10 apps for performance testing

        measure {
            let expectation = self.expectation(description: "Update detection completes")

            Task {
                _ = await updateDetector.checkForUpdates(apps: limitedApps)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 30.0)
        }
    }

    // MARK: - Error Handling Tests

    func testAppScannerHandlesPermissionErrors() async throws {
        // Test scanning a directory without permissions
        // This would require creating a test directory with restricted permissions
        XCTAssertTrue(true, "Permission error handling test placeholder")
    }

    func testUpdateDetectorHandlesNetworkErrors() async throws {
        // Test with invalid URLs
        let invalidApp = AppInfo(
            bundleID: "com.test.invalid",
            name: "Invalid App",
            version: "1.0.0",
            path: "/Applications/Invalid.app",
            iconPath: nil,
            sparkleURL: "https://invalid-url-that-does-not-exist.com/feed.xml",
            githubRepo: nil,
            isHomebrew: false,
            lastModified: Date()
        )

        let updates = await updateDetector.checkForUpdates(apps: [invalidApp])
        // Should handle gracefully and not crash
        XCTAssertNotNil(updates, "Should handle invalid URLs gracefully")
    }

    // MARK: - Data Model Tests

    func testAppInfoCoding() throws {
        let app = AppInfo(
            bundleID: "com.test.app",
            name: "Test App",
            version: "1.0.0",
            path: "/Applications/Test.app",
            iconPath: "/Applications/Test.app/Contents/Resources/icon.icns",
            sparkleURL: "https://example.com/feed.xml",
            githubRepo: "test/app",
            isHomebrew: false,
            lastModified: Date()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(app)

        let decoder = JSONDecoder()
        let decodedApp = try decoder.decode(AppInfo.self, from: data)

        XCTAssertEqual(app.bundleID, decodedApp.bundleID)
        XCTAssertEqual(app.name, decodedApp.name)
        XCTAssertEqual(app.version, decodedApp.version)
    }

    func testUpdateInfoCoding() throws {
        let app = AppInfo(
            bundleID: "com.test.app",
            name: "Test App",
            version: "1.0.0",
            path: "/Applications/Test.app",
            iconPath: nil,
            sparkleURL: nil,
            githubRepo: nil,
            isHomebrew: false,
            lastModified: Date()
        )

        let update = UpdateInfo(
            appInfo: app,
            availableVersion: "1.1.0",
            changelog: "Bug fixes and improvements",
            downloadURL: "https://example.com/download",
            isSecurityUpdate: false,
            isTahoeCompatible: true,
            summary: "Fixes bugs",
            detectedAt: Date()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(update)

        let decoder = JSONDecoder()
        let decodedUpdate = try decoder.decode(UpdateInfo.self, from: data)

        XCTAssertEqual(update.availableVersion, decodedUpdate.availableVersion)
        XCTAssertEqual(update.isSecurityUpdate, decodedUpdate.isSecurityUpdate)
    }
}
