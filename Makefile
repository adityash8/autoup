.PHONY: build clean install test setup generate-project help

# Default target
help:
	@echo "Auto-Up Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  setup           - Install dependencies and setup development environment"
	@echo "  generate-project - Generate Xcode project from project.yml"
	@echo "  build           - Build the application"
	@echo "  test            - Run tests"
	@echo "  install         - Install the application to /Applications"
	@echo "  clean           - Clean build artifacts"
	@echo "  package         - Create distribution package"
	@echo "  notarize        - Notarize the application for distribution"

# Setup development environment
setup:
	@echo "Setting up Auto-Up development environment..."
	@command -v brew >/dev/null 2>&1 || { echo >&2 "Homebrew is required but not installed. Please install Homebrew first."; exit 1; }
	@command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
	@command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
	@echo "Dependencies installed successfully!"

# Generate Xcode project
generate-project: setup
	@echo "Generating Xcode project..."
	@xcodegen generate
	@echo "Xcode project generated successfully!"

# Build using Swift Package Manager
build:
	@echo "Building Auto-Up..."
	@swift build -c release

# Build using Xcode (requires project generation)
build-xcode: generate-project
	@echo "Building Auto-Up with Xcode..."
	@xcodebuild -project AutoUp.xcodeproj -scheme AutoUp -configuration Release build

# Run tests
test:
	@echo "Running tests..."
	@swift test

# Install to Applications folder
install: build-xcode
	@echo "Installing Auto-Up to /Applications..."
	@sudo cp -R build/Release/AutoUp.app /Applications/
	@echo "Auto-Up installed successfully!"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@swift package clean
	@rm -rf build/
	@rm -rf .build/
	@rm -rf DerivedData/
	@echo "Clean completed!"

# Create distribution package
package: build-xcode
	@echo "Creating distribution package..."
	@mkdir -p dist
	@cp -R build/Release/AutoUp.app dist/
	@cd dist && zip -r AutoUp-1.0.0.zip AutoUp.app
	@echo "Distribution package created at dist/AutoUp-1.0.0.zip"

# Notarize for distribution (requires Apple Developer account)
notarize: package
	@echo "Notarizing Auto-Up..."
	@echo "Note: Requires valid Apple Developer account and credentials"
	@xcrun notarytool submit dist/AutoUp-1.0.0.zip --keychain-profile "AutoUp-Notarization" --wait
	@echo "Notarization completed!"

# Development run
run: generate-project
	@echo "Running Auto-Up in development mode..."
	@xcodebuild -project AutoUp.xcodeproj -scheme AutoUp -configuration Debug build
	@open build/Debug/AutoUp.app

# Lint code
lint:
	@echo "Running SwiftLint..."
	@swiftlint

# Format code
format:
	@echo "Formatting code..."
	@swiftformat Sources/

# Quick development setup
dev-setup: setup generate-project
	@echo "Development environment ready!"
	@echo "Open AutoUp.xcodeproj in Xcode to start developing."

# GitHub Actions CI/CD helper
ci-build: setup build test lint
	@echo "CI build completed successfully!"