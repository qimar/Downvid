<div align="center">

# Downvid

### High Speed Media Downloader for Android

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://developer.android.com)
[![Riverpod](https://img.shields.io/badge/State-Riverpod-00599C?style=for-the-badge&logo=flutter&logoColor=white)](https://riverpod.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)

<br/>

<a href="https://play.google.com/store/apps/details?id=com.fbreels.downloader">
  <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" height="70" alt="Get it on Google Play"/>
</a>

</div>

---

## Overview

Downvid is a consumer Android media utility designed for high speed video and audio extraction across multiple sources. Built with Flutter and Riverpod, it provides background download task queues that continue running through device sleep states, an integrated media player with hardware acceleration, and full compliance with modern Android 13 scoped storage permissions.

---

## Key Features

* **Multi Resolution Extraction:** Extract and download video streams in multiple resolutions (1080p, 720p, 480p) or convert them directly to MP3 audio files.
* **Background Task Persistence:** Background download queues continue downloading even when the user minimizes the app or turns off the screen.
* **Integrated Media Player:** Built in player supporting hardware acceleration, fullscreen playback, aspect ratio adjustment, and gesture volume controls.
* **Android 13 Scoped Storage:** Saves media directly to public gallery collections via Android MediaStore APIs without requesting broad external storage permissions.
* **Resilient Stream Handlers:** Includes Cloudflare wait checks and payload verification routines to prevent broken or corrupted media files.

---

## Tech Stack

| Component | Technology |
|---|---|
| **Framework** | Flutter 3.x (Android) |
| **Language** | Dart |
| **State Management** | Riverpod |
| **Networking** | Dio, HTTP, Custom Scraper Services |
| **Local Database** | ObjectBox |
| **Storage API** | Android MediaStore Plus (Scoped Storage) |
| **Media Player** | Video Player with Hardware Decoding |
| **Monetization** | Google Mobile Ads (AdMob Caching) |

---

## Architecture

The project follows a clean, modular structure separating presentation, state management, and platform services:

```text
lib/
├── core/                  # Utilities, app constants, and storage helpers
├── providers/             # Riverpod state notifiers (download queue, player, theme)
├── screens/               # UI screens (Home, Downloaded Media, Video Player)
├── services/              # Scraping engines, AdMob helpers, and ObjectBox storage
├── widgets/               # Reusable buttons, cards, and bottom sheets
└── main.dart              # Application entrypoint and dependency initialization
```

---

## Engineering Highlights

### Resilient Background Downloads
Android aggressive battery savers kill background network connections when an app leaves the foreground. Downvid implements a background task queue with automated retry logic and partial chunk resumption, keeping downloads alive during sleep states.

### Cloudflare Verification Wait Handlers
Target media endpoints frequently use Cloudflare verification challenges. The scraping service uses a headless controller with asynchronous readiness completers that wait for verification to pass before submitting queries, preventing empty responses.

---

## Getting Started

### Prerequisites
* Flutter SDK (version 3.24.0 or newer)
* Android SDK (API 34 or newer)
* Java 17

### Installation

```bash
# Clone the repository
git clone https://github.com/wackyapps/downvid.git

# Navigate to the project directory
cd downvid

# Install packages
flutter pub get

# Run the app on an Android device or emulator
flutter run
```

---

## License

Distributed under the MIT License. See `LICENSE` for details.
