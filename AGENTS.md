# CardVault AI Agent Guidelines

## Architecture Overview
CardVault is a Flutter app using Provider for state management, Sqflite for local encrypted storage, and Firebase (Auth, Firestore, Functions, Messaging) for cloud features. Core data flow: local-first cards with automatic Gmail syncing for transactions/bills, cloud backup/restore via Firestore.

## Key Components
- **State Management**: Provider pattern with `CardProvider`, `ThemeProvider`, `SecurityProvider`, `UpdateProvider` in `lib/providers/`
- **Data Layer**: `DatabaseHelper` singleton (`lib/database/`) manages Sqflite DB with tables: cards, email_accounts, transactions
- **Services**: Singleton services in `lib/services/` handle auth, backups, Gmail sync, encryption, notifications
- **Models**: `CardModel` with auto-rolling due dates, `TransactionModel` in `lib/models/`
- **Firebase Functions**: Node.js functions in `functions/` for FCM bill reminders

## Data Flows & Patterns
- **Card Lifecycle**: Cards stored locally in Sqflite, encrypted via `EncryptionService`. Due dates auto-roll monthly on refresh (see `CardModel.rollToNextMonth()`), saving history via `HistoryService`
- **Gmail Sync**: `GmailService` parses emails for statements/transactions, updates spent amounts/due dates. Tracks processed emails in Firestore `users/{uid}/processed_emails`
- **Cloud Backup**: `BackupService` syncs cards/transactions to Firestore `users/{uid}/cards` on changes
- **Notifications**: FCM via `NotificationService` for bill reminders, triggered by functions or local scheduling
- **Auth Flow**: Firebase Auth with Google Sign-In, app shows `LockScreen` if authenticated, `LoginScreen` otherwise

## Critical Workflows
- **Build App**: `flutter build apk` or `flutter build ios` (requires Android Studio/VS Code with Flutter extensions)
- **Deploy Functions**: `cd functions && npm install && firebase deploy --only functions`
- **Test Locally**: `firebase emulators:start` for functions, `flutter test` for unit tests
- **Gmail OAuth**: Use `getToken.js` for refresh tokens, store in DB `email_accounts` table
- **Background Sync**: Workmanager runs daily `BackupService.onlineBackup()` if logged in

## Project Conventions
- **Encryption**: Sensitive fields (CVV, full number) encrypted at rest using `encrypt` package
- **Error Handling**: Use `debugPrint` for logging, catch errors in async operations
- **Imports**: Relative imports within lib/, absolute for external packages
- **Database Migrations**: Versioned in `DatabaseHelper._onUpgrade()`, add columns/tables as needed
- **Firebase Security**: User data scoped to `users/{uid}` collections, no cross-user access
- **UI Patterns**: Material3 theme with deep purple seed, dark/light mode via `ThemeProvider`

## Key Files
- `lib/main.dart`: App init with Firebase early, MultiProvider setup, background tasks
- `lib/providers/card_provider.dart`: Core card CRUD, sync triggers, due date rolling
- `lib/services/gmail_service.dart`: Email parsing logic, query: `subject:(credit card statement OR payment due OR "transaction alert"...)`
- `lib/database/database_helper.dart`: DB schema, encryption integration
- `functions/index.js`: FCM notification sender for bill reminders</content>
<parameter name="filePath">c:\Users\Mukul\cardvault\AGENTS.md
