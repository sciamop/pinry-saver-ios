# PinrySaver iOS App

A SwiftUI iOS app with share extension for saving images and URLs to Pinry instances.

## Features

- **Modern UI**: Clean, minimalist design with vibrant magenta branding and striped logo
- **Main App**: Settings screen to configure Pinry Base URL, API Token, and Default Board ID
- **Share Extension**: Appears in iOS share sheets for images (`public.image`) and URLs (`public.url`)
- **Secure Storage**: API token stored in shared Keychain between app and extension
- **Shared Settings**: Uses App Group UserDefaults to share settings between targets
- **Image Processing**: Automatic HEIC to JPEG conversion before upload
- **Server Validation**: Built-in validation checks your Pinry server connection on first setup
- **Smart Onboarding**: API token is optional for browsing public pins (only required for saving)

## Screenshots

<img src="https://pinry.whistlehog.com/media/2/a/2a541952ec40f7b97529a60b5c772faa/image.jpg" width="300" alt="PinrySaver Screenshot 1"> <img src="https://pinry.whistlehog.com/media/c/9/c93e8557739e6dca4b3feaa3776a8692/image.jpg" width="300" alt="PinrySaver Screenshot 2">

## Setting Up Your Pinry Server

This iOS app connects to a self-hosted [Pinry server](https://github.com/pinry/pinry). You'll need to set up your own Pinry instance first.

### Quick Server Setup with Docker

The easiest way to get Pinry running is with Docker. From the [Pinry project](https://github.com/pinry/pinry):

```bash
# Clone the Pinry repository
git clone https://github.com/pinry/pinry.git
cd pinry

# Start with docker-compose
docker-compose -f docker-compose.example.yml up -d
```

Your Pinry server will be available at `http://localhost` (or your server's IP).

### Getting Your API Token

1. Access your Pinry web interface
2. Create an account or log in
3. Go to your account settings
4. Generate an API token
5. Copy this token for use in the iOS app

### Configuration Tips

- **Public Pins**: If your Pinry instance allows public viewing, you can browse pins without an API token
- **Saving Pins**: API token is required to save new images/URLs to your Pinry
- **HTTPS Recommended**: Use HTTPS in production for secure API token transmission

For detailed Pinry server setup, visit the [official documentation](https://pinry.github.io/pinry/).

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

1. Open `PinrySaver.xcodeproj` in Xcode
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
   - Right-click on project > Add Files to "Pinry Saver"
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
