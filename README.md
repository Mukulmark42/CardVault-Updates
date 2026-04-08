# 💳 CardVault

**CardVault** is a secure, Flutter-based digital wallet designed to help you manage and organize your credit cards in one place. With a focus on speed and privacy, CardVault provides a sleek virtual interface for your cards, ensuring they are always accessible, even offline.

## ✨ Key Features

* **Virtual Card Interface:** A beautiful, intuitive UI that digitally recreates the look and feel of your physical cards.
* **Offline-First Storage:** Your data stays on your device. Access your card information anytime without needing an internet connection.
* **Smart Search:** Instantly find specific cards using the integrated search bar.
* **Cross-Platform:** Built with Flutter for high performance on Android, iOS, Linux, macOS, and Web.
* **Gmail Sync:** Automatically parse credit card statements and transactions from your Gmail.
* **Cloud Backup:** Secure Firebase backup and sync across devices.
* **Bill Reminders:** Get notifications for upcoming credit card due dates.
* **Encrypted Storage:** Sensitive data encrypted at rest using AES encryption.

## 🛡️ Security & Privacy

* **Local Encryption:** All sensitive data (CVV, card numbers) is encrypted and stored locally on your device.
* **Secure Cloud Sync:** Optional Firebase backup with user-scoped security rules.
* **No Cloud Tracking:** Your card details are never uploaded without your permission.

## 🛠️ Tech Stack

* **Framework:** [Flutter](https://flutter.dev/)
* **Language:** Dart
* **Local Database:** Sqflite with encryption
* **State Management:** Provider pattern
* **Backend:** Firebase (Auth, Firestore, Functions, Messaging)
* **Cloud Functions:** Node.js for notifications and email processing
* **Encryption:** AES via encrypt package
* **Build Tools:** Gradle, CocoaPods, CMake

## 🏗️ Architecture

CardVault follows a local-first architecture with cloud sync capabilities:

- **Data Layer:** `DatabaseHelper` singleton manages Sqflite DB with tables: cards, email_accounts, transactions
- **State Management:** Provider pattern with `CardProvider`, `ThemeProvider`, `SecurityProvider`, `UpdateProvider`
- **Services:** Singleton services handle auth, backups, Gmail sync, encryption, notifications
- **Models:** `CardModel` with auto-rolling due dates, `TransactionModel`
- **Firebase Integration:** Auth for login, Firestore for backup, Functions for FCM bill reminders

## 🚀 Getting Started

Follow these steps to get a local copy of CardVault up and running.

### Prerequisites
* Flutter SDK (Stable channel)
* Android Studio / VS Code with Flutter extensions
* Firebase account (for cloud features)
* Google Cloud Project with Gmail API enabled (for email sync)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/Mukulmark42/CardVault-Updates.git
   cd CardVault-Updates
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Create a Firebase project
   - Add your Android/iOS apps to Firebase
   - Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Place them in `android/app/` and `ios/Runner/` respectively

4. **Configure Gmail API** (Optional, for email sync)
   - Enable Gmail API in Google Cloud Console
   - Create OAuth 2.0 credentials
   - Use `getToken.js` to obtain refresh token

5. **Run the app**
   ```bash
   flutter run
   ```

## 📱 Screenshots

* **Vault Screen:** View all your cards in a beautiful grid
* **Add Card Screen:** Securely add new credit cards
* **Dashboard:** See spending insights and due dates
* **Email Management:** Connect Gmail accounts for automatic transaction parsing
* **Settings:** Configure security, backup, and notification preferences

## 🔧 Development

### Project Structure
```
lib/
├── main.dart              # App entry point with Firebase init
├── models/               # Data models (CardModel, TransactionModel)
├── providers/            # State providers (CardProvider, ThemeProvider)
├── screens/              # UI screens
├── services/             # Business logic (AuthService, GmailService)
├── database/             # Database helper and migrations
└── widgets/              # Reusable UI components
```

### Key Workflows
- **Card Lifecycle:** Cards stored locally in Sqflite, encrypted via `EncryptionService`
- **Gmail Sync:** `GmailService` parses emails for statements/transactions
- **Cloud Backup:** `BackupService` syncs cards/transactions to Firestore
- **Notifications:** FCM via `NotificationService` for bill reminders

### Building
```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

### Firebase Functions
```bash
cd functions
npm install
firebase deploy --only functions
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Firebase team for backend services
- All contributors and testers

## 📞 Support

For support, email mukulmark42@gmail.com or create an issue in the GitHub repository.