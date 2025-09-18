# Auto-Up Setup Guide

This guide will help you set up and build Auto-Up from source.

## Prerequisites

1. **macOS 13.0 or later**
2. **Xcode 15.0 or later** with Command Line Tools
3. **Homebrew** (for development dependencies)

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Quick Start

1. **Clone and setup:**
```bash
git clone <repository-url>
cd AutoUp
make dev-setup
```

2. **Open in Xcode:**
```bash
open AutoUp.xcodeproj
```

3. **Build and run** (⌘R in Xcode)

## Development Setup

### Option 1: Using Makefile (Recommended)

```bash
# Setup development environment
make setup

# Generate Xcode project
make generate-project

# Build with Xcode
make build-xcode

# Run tests
make test

# Install to /Applications
make install
```

### Option 2: Using Swift Package Manager

```bash
# Build
swift build

# Run tests
swift test

# Run (executable only, no GUI)
swift run
```

### Option 3: Manual Xcode Setup

1. Install XcodeGen:
```bash
brew install xcodegen
```

2. Generate project:
```bash
xcodegen generate
```

3. Open in Xcode:
```bash
open AutoUp.xcodeproj
```

## Configuration

### Environment Variables

Create a `.env` file in the project root for optional configurations:

```bash
# OpenAI API key for AI summaries (optional)
OPENAI_API_KEY=your_openai_api_key_here

# PostHog project key for analytics (optional)
POSTHOG_PROJECT_KEY=your_posthog_key_here
```

### Code Signing

For distribution, update `project.yml`:

```yaml
settings:
  DEVELOPMENT_TEAM: YOUR_TEAM_ID  # Replace with your Apple Developer Team ID
```

## Project Structure

```
AutoUp/
├── Sources/
│   ├── App/                    # App entry point & delegates
│   ├── Core/                   # Core functionality (scanning, updating)
│   ├── Models/                 # Data models
│   ├── Services/               # Background services & AI
│   ├── UI/                     # SwiftUI views
│   └── Resources/              # Assets & data files
├── Tests/                      # Unit tests
├── Package.swift               # Swift Package Manager
├── project.yml                 # XcodeGen configuration
├── Makefile                    # Build automation
└── README.md                   # Main documentation
```

## Key Features Implemented

✅ **Menu Bar App** - SwiftUI-based menu bar application
✅ **App Scanning** - Detects .app bundles in /Applications
✅ **Update Detection** - Sparkle feeds, Homebrew, GitHub releases
✅ **One-Click Updates** - Silent installation with fallback
✅ **Rollback System** - Version caching and restoration
✅ **AI Summaries** - Local MLX and OpenAI changelog processing
✅ **Background Updates** - Scheduled automatic updates
✅ **Tahoe Compatibility** - macOS 26 incompatibility detection
✅ **Health Scores** - Visual app status indicators
✅ **Pro Features** - Multi-Mac sync, version pinning, family sharing
✅ **Database** - Encrypted SQLite storage
✅ **Security** - Sandboxed with proper entitlements

## Testing

Run the test suite:

```bash
make test
# or
swift test
# or in Xcode: ⌘U
```

Tests cover:
- App scanning functionality
- Update detection logic
- Tahoe compatibility checking
- Health score calculation
- Data model serialization
- Performance benchmarks

## Troubleshooting

### Build Issues

1. **Missing dependencies:**
```bash
make setup
```

2. **Swift Package Manager cache issues:**
```bash
swift package clean
swift package resolve
```

3. **Xcode project generation fails:**
```bash
brew upgrade xcodegen
make generate-project
```

### Runtime Issues

1. **App doesn't appear in menu bar:**
   - Check that `LSUIElement` is set to `true` in Info.plist
   - Verify app isn't running in dock mode

2. **Permission errors when scanning apps:**
   - Grant Full Disk Access in System Preferences > Security & Privacy

3. **Background updates not working:**
   - Check Background App Refresh settings
   - Verify Wi-Fi and power requirements

### Common Permissions

Auto-Up requires these permissions:

- **Full Disk Access** - To scan /Applications
- **Accessibility** - For automated installations (optional)
- **Background App Refresh** - For automatic updates
- **Network** - To download updates

## Distribution

### Local Testing

```bash
make build-xcode
make install
```

### Distribution Build

```bash
make package
# Creates dist/AutoUp-1.0.0.zip
```

### App Store / Notarization

1. Update Team ID in `project.yml`
2. Configure signing certificates
3. Build for release:

```bash
make build-xcode
make package
make notarize  # Requires Apple Developer account
```

## Next Steps

1. **Customize the app** for your needs
2. **Test thoroughly** on your Mac setup
3. **Configure Pro features** if needed
4. **Submit feedback** or contribute improvements

## Support

- Check [README.md](README.md) for user documentation
- Review [Tests/](Tests/) for implementation examples
- Open issues for bugs or feature requests

---

**Happy building!** 🚀