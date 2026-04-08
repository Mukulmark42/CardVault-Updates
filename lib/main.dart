import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_options.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'providers/card_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/update_provider.dart';
import 'providers/security_provider.dart';
import 'providers/profile_provider.dart';
import 'services/auth_service.dart';
import 'services/backup_service.dart';
import 'services/notification_service.dart';
import 'services/user_service.dart';
import 'services/gmail_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final auth = AuthService();
      if (auth.currentUser != null) {
        // Cloud backup
        await BackupService().onlineBackup();
        // Silent Gmail sync (background — no interactive sign-in)
        await GmailService.instance.syncAllLinkedAccounts(isManual: false);
        debugPrint('Background Sync Successful');
      }
      return true;
    } catch (e, stack) {
      debugPrint("Background Sync Failed: $e");
      debugPrint("Stack trace: $stack");
      return false;
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ ONLY Firebase init before UI
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ Run app immediately (VERY IMPORTANT)
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CardProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(create: (_) => SecurityProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        Provider<AuthService>(create: (_) => AuthService()),
      ],
      child: const CardVault(),
    ),
  );

  // ✅ Run everything else in background (NO BLOCKING)
  Future.microtask(() async {
    try {
      // 🔔 Notification service
      await NotificationService().init();

      // 🗺️ Update user notification mapping if logged in
      await UserService.instance.updateUserNotificationData();

      // 🔄 Workmanager
      Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);

      // Only register periodic task in release mode
      if (!kDebugMode) {
        Workmanager().registerPeriodicTask(
          "1",
          "dailySync",
          frequency: const Duration(hours: 12),
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: true,
          ),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      }
    } catch (e) {
      print("❌ Background init error: $e");
    }
  });
}

class CardVault extends StatefulWidget {
  const CardVault({super.key});

  @override
  State<CardVault> createState() => _CardVaultState();
}

class _CardVaultState extends State<CardVault> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UpdateProvider>().checkForUpdates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final updateProvider = Provider.of<UpdateProvider>(context);

    if (updateProvider.isUpdateAvailable && !updateProvider.isDownloading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          _showUpdateDialog(context, updateProvider);
        }
      });
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CardVault',
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.deepPurple,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF020617),
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: Consumer<AuthService>(
        builder: (context, authService, _) {
          return StreamBuilder(
            stream: authService.authStateChanges,
            builder: (context, authSnapshot) {
              if (authSnapshot.connectionState == ConnectionState.waiting) {
                return const LoadingScreen();
              }
              if (authSnapshot.hasData) {
                return const LockScreen();
              }
              return const LoginScreen();
            },
          );
        },
      ),
    );
  }

  void _showUpdateDialog(BuildContext context, UpdateProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Update Available 🚀"),
        content: Text(provider.updateMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Later"),
          ),
          ElevatedButton(
            onPressed: () => provider.startUpdate(() {
              Navigator.pop(ctx);
            }),
            child: const Text("Update Now"),
          ),
        ],
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
