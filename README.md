# 💳 CardVault

**CardVault** is a secure, local-first digital wallet built with Flutter, designed to help you manage and organize your credit cards with ease. It combines a beautiful virtual interface with powerful automation like Gmail syncing and cloud backups, ensuring your financial data is always organized and accessible.

## ✨ Key Features

*   **🎨 Virtual Card Interface:** A sleek, interactive UI that digitally recreates your physical cards for easy identification.
*   **📧 Smart Gmail Sync:** Automatically parses credit card statements and transaction alerts from linked Gmail accounts to update spent amounts and due dates.
*   **☁️ Cloud Backup & Restore:** Securely sync your data to Firebase Firestore, allowing for seamless recovery across devices.
*   **🔐 Multi-Layer Security:** Protect your vault with Biometric authentication (Fingerprint/Face ID) and a fallback 4-digit PIN.
*   **🔄 Auto-Rolling Due Dates:** Never miss a payment. CardVault automatically rolls due dates to the next month and keeps a history of your past cycles.
*   **📥 OTA Updates:** Receive the latest features and security patches directly within the app via GitHub release integration.
*   **🌙 Dynamic Theming:** Full support for Light and Dark modes to match your system preference.

## 🛡️ Security & Privacy

*   **AES Encryption:** Sensitive information like CVV and full card numbers are encrypted at rest using the `encrypt` package before being saved to the local database.
*   **Scoped Access:** Cloud data is strictly scoped to your unique Firebase UID, ensuring total privacy.
*   **Offline-First:** Your primary data resides in a local Sqflite database, allowing full functionality even without an internet connection.

## 🛠️ Tech Stack

*   **Framework:** [Flutter](https://flutter.dev/) (Dart)
*   **State Management:** [Provider](https://pub.dev/packages/provider)
*   **Local Database:** [Sqflite](https://pub.dev/packages/sqflite) with AES Encryption
*   **Backend:** [Firebase](https://firebase.google.com/) (Auth, Firestore, Cloud Messaging, Functions)
*   **APIs:** Google Sign-In & Gmail API

## 🚀 Getting Started

### Prerequisites
*   Flutter SDK (Stable channel)
*   Firebase Project setup
*   Google Cloud Console project with Gmail API enabled

### Installation

1.  **Clone the repository**
    ```bash
    git clone https://github.com/Mukulmark42/CardVault.git
    cd cardvault
    ```

2.  **Install dependencies**
    ```bash
    flutter pub get
    ```

3.  **Firebase Setup**
    *   Add your `google-services.json` to `android/app/`.
    *   Run `flutterfire configure` if using the FlutterFire CLI.

4.  **Run the app**
    ```bash
    flutter run
    ```

## 📦 Releases & Updates

CardVault features an in-app update system. When a new version is published to [GitHub Releases](https://github.com/Mukulmark42/CardVault-Updates), a notification badge will appear in the app's settings. You can review release notes and update directly from within the app.

---
*Created with ❤️ by [Mukul](https://github.com/Mukulmark42)*
