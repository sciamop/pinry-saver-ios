# PinrySaver iOS App

A SwiftUI iOS app with share extension for saving images and URLs to Pinry instances.

## Features

- **Main App**: Settings screen to configure Pinry Base URL, API Token, and Default Board ID
- **Share Extension**: Appears in iOS share sheets for images (`public.image`) and URLs (`public.url`)
- **Secure Storage**: API token stored in shared Keychain between app and extension
- **Shared Settings**: Uses App Group UserDefaults to share settings between targets
- **Image Processing**: Automatic HEIC to JPEG conversion before upload

## Project Structure

```
PinrySaver/
├── PinryShared/                # Shared code between app and extension
│   ├── PinrySettings.swift     # Settings management with App Group UserDefaults
│   ├── KeychainStore.swift     # Secure API token storage
│   └── PinryUploader.swift     # Pinry API upload logic
├── PinrySaver/                 # Main app target
│   └── ContentView.swift       # Settings UI (SwiftUI)
└── PinryShareExtension/        # Share extension target
    ├── ShareViewController.swift # Share extension logic
    └── Info.plist             # Extension configuration
```

## Setup Instructions

### 1. Configure Bundle Identifiers

1. Open `pinry-saver-ios-2.xcodeproj` in Xcode
2. Select the project in the navigator
3. For the main app target:
   - Set Bundle Identifier to: `com.example.pinrysaver`
4. For the Share Extension target:
   - Set Bundle Identifier to: `com.example.pinrysaver.shareextension`

### 2. Configure App Groups

1. Add Capabilities:
   - **Main App**: Add "App Groups" capability
     - Add group: `group.com.example.pinry`
   - **Share Extension**: Add "App Groups" capability
     - Add same group: `group.com.example.pinry`

### 3. Configure Keychain Sharing

1. Add Capabilities:
   - **Main App**: Add "Keychain Sharing" capability
     - Add keychain group: `$(AppIdentifierPrefix)com.example.pinryshared`
   - **Share Extension**: Add "Keychain Sharing" capability
     - Add same keychain group: `$(AppIdentifierPrefix)com.example.pinryshared`

### 4. Add Shared Files to Targets

1. Add `PinryShared` folder to both targets:
   - Right-click on project > Add Files to "pinry-saver-ios-2"
   - Select the `PinryShared` folder
   - Ensure both targets (main app and share extension) are checked

### 5. Deployment Target

- Ensure iOS Deployment Target is set to iOS 14.0 or later (for `async/await` support)

## Usage

### Initial Setup

1. Launch the PinrySaver app
2. Go to Settings tab
3. Enter your Pinry configuration:
   - **Pinry Base URL**: Your Pinry instance URL (e.g., `https://your-pinry.com`)
   - **API Token**: Your Pinry API token
   - **Default Board ID**: Optional board ID for pins
4. Tap "Save Settings"

### Using the Share Extension

1. Open any app with images or URLs (Photos, Safari, etc.)
2. Tap the share button
3. Select "PinrySaver" from the share sheet
4. The extension will automatically upload the content to your configured Pinry instance

## API Requirements

The app communicates with Pinry API at `<base_url>/api/pins/` endpoint using:

- **Method**: POST
- **Authentication**: `Authorization: Token <api_token>`
- **Content-Type**: `multipart/form-data`
- **Fields**:
  - `image`: Image file data (JPEG)
  - `description`: Generated description
  - `source`: Source URL or app
  - `board`: Board ID for the pin

## Security Notes

- API tokens are stored securely in the Keychain using iOS Keychain Services
- Settings are shared between app and extension via App Groups
- All network requests use URLSession with proper error handling

## Development Notes

- Share extension extracts domain names from URLs for source attribution
- Images are automatically converted from HEIC to JPEG for broader compatibility
- Multiple image sharing is supported (up to 10 images)
- URL sharing creates placeholder images with domain names for Pinry upload

## Troubleshooting

- Ensure App Groups and Keychain Sharing are properly configured in both targets
- Verify Bundle Identifiers are unique and correctly formatted
- Check that the Pinry Base URL includes protocol (http/https)
- API tokens should be valid Pinry authentication tokens
