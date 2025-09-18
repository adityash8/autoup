# Auto-Up

🖥 **Auto-Up — Mac App Auto-Updater**
*"Your Mac, always fresh & safe — without lifting a finger."*

A beautiful, lightweight menu bar utility that keeps all your Mac apps up to date — App Store + non-App Store — with MacPaw-level polish and CleanShot-style simplicity.

## Features

### Core MVP Features
- **One-Click Update All**: Big friendly button in a minimal UI with update count always visible in menu bar
- **Silent Auto-Update Mode**: Background updates on a schedule (default: overnight), runs only on Wi-Fi & while plugged in
- **Plain-Language Change Logs**: Auto-summarized with AI: "Safari is faster and fixes a crash bug"
- **Security Fix Priority**: Detect CVE/security-related updates & install ASAP
- **Update History + Undo**: Timeline of updates with one-tap rollback (last version cached)
- **Tahoe Compatibility**: Flags macOS 26 incompatible apps to prevent crashes

### Pro Features ($2.99/mo or $24/year)
- **Multi-Mac Sync**: Same update rules on all devices via iCloud
- **Family Mode**: Covers household Macs under one plan ($39/year for 5 devices)
- **App Health Score**: Green (up-to-date), Yellow (optional), Red (urgent)
- **Version Pinning**: Stay on a preferred version
- **Silent Installer Support**: No dialogs for supported apps

## Supported Update Sources

- **Sparkle feeds** (built-in updaters)
- **Homebrew casks** (`brew outdated --cask`)
- **GitHub releases** (API v3 for open-source apps)
- **App Store** (coming soon)

## System Requirements

- macOS 13.0 or later
- Apple Silicon (M1/M2/M3) or Intel processor
- 50MB free disk space

## Installation

### From Source

1. Clone the repository:
```bash
git clone https://github.com/your-username/autoup.git
cd autoup
```

2. Open in Xcode:
```bash
open AutoUp.xcodeproj
```

3. Build and run (⌘R)

### From Package Manager

```bash
swift build
swift run
```

## Configuration

Auto-Up creates its configuration files in:
- Database: `~/Library/Application Support/AutoUp/autoup.db`
- Cache: `~/Library/Application Support/AutoUp/Cache/`
- Preferences: Stored in macOS UserDefaults

### Background Updates

To enable automatic background updates:

1. Open Auto-Up settings
2. Enable "Automatic updates"
3. Configure schedule (overnight recommended)
4. Set constraints (Wi-Fi only, plugged in only)

### AI Summaries

Auto-Up can summarize changelogs using:

1. **Local MLX model** (privacy-first, requires M1+)
2. **OpenAI GPT-4o-mini** (set `OPENAI_API_KEY` environment variable)
3. **Keyword extraction** (fallback)

```bash
export OPENAI_API_KEY="your-api-key-here"
```

### Tahoe Compatibility

The app includes a built-in database of known macOS 26 (Tahoe) compatibility issues:

- Adobe Lightroom Classic v13.0-13.2 (crashes on startup)
- Fuji Camera Tethering (broken until September end)
- Parallels Desktop v18.0-18.1 (VM startup failures)
- VMware Fusion v13.0 (kernel panics)

## Architecture

### Core Components

- **AppScanner**: Discovers .app bundles in `/Applications` and `~/Applications`
- **UpdateDetector**: Checks Sparkle feeds, Homebrew, and GitHub APIs
- **InstallManager**: Handles DMG/PKG/ZIP installations with rollback support
- **ChangelogSummarizer**: AI-powered changelog processing
- **BackgroundScheduler**: Manages automatic update scheduling
- **TahoeCompatibilityChecker**: Prevents incompatible app updates

### Tech Stack

- **UI**: SwiftUI with menu bar integration
- **Database**: SQLite with encryption (SQLCipher)
- **AI**: MLX Swift for local processing, OpenAI for cloud fallback
- **Background**: BGTaskScheduler + network monitoring
- **Monetization**: StoreKit 2 for Pro subscriptions

## Development

### Project Structure

```
AutoUp/
├── Sources/
│   ├── App/                    # App entry point & delegates
│   ├── Core/                   # Scanner, detector, installer
│   ├── Models/                 # Data models
│   ├── Services/               # AI, background, Pro features
│   ├── UI/                     # SwiftUI views
│   └── Resources/              # Assets, Tahoe compatibility data
├── Tests/                      # Unit tests
└── Package.swift               # Dependencies
```

### Dependencies

- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) - Database layer
- [MLX Swift](https://github.com/ml-explore/mlx-swift) - Local AI processing
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Self-updating
- [PostHog](https://github.com/PostHog/posthog-ios) - Analytics (opt-in)

### Running Tests

```bash
swift test
```

### Building for Release

```bash
swift build -c release
```

## Privacy

Auto-Up respects your privacy:

- **Local-first**: All data stored on your Mac
- **Opt-in telemetry**: Anonymous usage stats only if enabled
- **No app lists**: We never see what apps you have installed
- **Encrypted storage**: Local database is encrypted with Keychain

### Data Collection (Optional)

When telemetry is enabled, we collect:
- Update success/failure rates (anonymized)
- App scanning performance metrics
- Feature usage statistics

We **never** collect:
- Personal information
- App names or lists
- File paths or system details

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Open Source Components

The core **UpdaterEngine** is open-source under MIT license to encourage community contributions:

- Custom update sources
- Improved version detection
- New installer formats

## Roadmap

### Phase 1 (MVP - October 2025)
- [x] Core app scanning & update detection
- [x] One-click updates with rollback
- [x] AI changelog summarization
- [x] Tahoe compatibility checking
- [x] Background scheduling

### Phase 2 (Q1 2026)
- [ ] App Store update detection
- [ ] Advanced silent installation
- [ ] iOS companion app
- [ ] Enhanced family sharing

### Phase 3 (Q2 2026)
- [ ] Enterprise features (MDM integration)
- [ ] Custom update sources
- [ ] Advanced reporting & analytics

## Support

- **Website**: [autoup.app](https://autoup.app)
- **Support**: [support@autoup.app](mailto:support@autoup.app)
- **Twitter**: [@autoUpApp](https://twitter.com/autoUpApp)

## License

- **App**: Proprietary (commercial software)
- **UpdaterEngine**: MIT License (see [LICENSE-ENGINE.md](LICENSE-ENGINE.md))

---

**Auto-Up** — Keep your Mac fresh, secure, and running smoothly. ✨