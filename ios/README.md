# BookStack iOS & watchOS Apps

## Project Setup

### Prerequisites
- Xcode 15+ (iOS 17 SDK, watchOS 10 SDK)
- Apple Developer account (for device deployment and Keychain sharing)

### Creating the Xcode Project

1. Open Xcode and create a new **Multiplatform App**:
   - Product Name: `BookStack`
   - Organization Identifier: `com.bookstack`
   - Interface: SwiftUI
   - Language: Swift

2. Add a **watchOS App** target:
   - File > New > Target > watchOS > App
   - Product Name: `BookStackWatch`
   - Include Notification Scene: No

3. **Import the source files** from this directory:
   - Drag `Shared/` into the project (add to both iOS and Watch targets)
   - Drag `BookStack/` into the iOS target
   - Drag `BookStackWatch/` into the Watch target

4. **Configure Keychain Sharing** (for shared JWT between phone and watch):
   - Select the iOS target > Signing & Capabilities > + Capability > Keychain Sharing
   - Add group: `com.bookstack.shared`
   - Do the same for the Watch target

5. **Set the API base URL**:
   - In `Shared/Networking/APIClient.swift`, update the production `baseURL`
   - Debug builds use `localhost:3000` for development

### Project Structure

```
BookStack/
├── Shared/                    # Shared between iOS and Watch
│   ├── Models/Models.swift    # All Codable model structs
│   ├── Networking/APIClient.swift  # REST API client
│   ├── Services/AuthManager.swift  # Auth state management
│   └── Utilities/
│       ├── KeychainManager.swift   # JWT storage
│       └── TimeFormatting.swift    # Duration formatting
├── BookStack/                 # iOS App
│   ├── App/
│   │   ├── BookStackApp.swift     # Entry point
│   │   └── MainTabView.swift      # 5-tab navigation
│   ├── ViewModels/
│   │   ├── DashboardViewModel.swift
│   │   ├── BooksViewModel.swift
│   │   └── SessionsViewModel.swift
│   └── Views/
│       ├── Auth/              # Login, Register
│       ├── Dashboard/         # Today's quotas, stats, streak
│       ├── Books/             # List, Detail, Add
│       ├── Sessions/          # Timer, History, Manual entry
│       ├── Pipeline/          # Swift Charts visualization
│       └── Profile/           # Settings, Stats, Logout
└── BookStackWatch/            # watchOS App
    ├── App/BookStackWatchApp.swift
    └── Views/
        ├── WatchHomeView.swift       # Active books + session
        ├── WatchLoginView.swift      # Email/password login
        ├── WatchStartSessionView.swift
        ├── WatchTimerView.swift      # Timer + Digital Crown page entry
        └── WatchTodayQuotaView.swift
```

### Architecture

- **MVVM** pattern for iOS views
- **Server-authoritative timer**: `started_at` is the source of truth
  - Timer displays computed from server timestamp using SwiftUI `TimelineView`
  - Survives app kills, works across devices
- **Shared Keychain**: JWT stored in shared access group for Watch access
- **Online-only v1**: Caches last-fetched data for display, disables mutations when offline

### Development

Run the Rails API locally:
```bash
cd /path/to/bookstack
bin/dev
```

Then run the iOS app in Xcode Simulator — it will connect to `localhost:3000`.
