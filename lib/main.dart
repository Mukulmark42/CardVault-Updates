import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_options.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'providers/card_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/update_provider.dart';
import 'providers/security_provider.dart';
import 'services/auth_service.dart';
import 'services/backup_service.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final auth = AuthService();
      if (auth.currentUser != null) {
        await BackupService().onlineBackup();
        debugPrint("Background Sync Successful");
      }
      return Future.value(true);
    } catch (e) {
      debugPrint("Background Sync Failed: $e");
      return Future.value(false);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final firebaseInit = Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Notifications
  await NotificationService().init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CardProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ChangeNotifierProvider(create: (_) => SecurityProvider()),
        Provider<AuthService>(create: (_) => AuthService()),
      ],
      child: CardVault(firebaseInit: firebaseInit),
    ),
  );

  firebaseInit.then((_) {
    Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);
    Workmanager().registerPeriodicTask(
      "1",
      "dailySync",
      frequency: const Duration(hours: 24),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  });
}

class CardVault extends StatefulWidget {
  final Future<FirebaseApp> firebaseInit;
  const CardVault({super.key, required this.firebaseInit});

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

  void _showUpdateDialog(BuildContext context, UpdateProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ListenableProvider.value(
        value: provider,
        child: Consumer<UpdateProvider>(
          builder: (context, update, _) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: const Color(0xFF0F172A),
            title: const Text("Update Available 🚀", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(update.updateMessage, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                if (update.isDownloading) ...[
                  const SizedBox(height: 24),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: update.downloadProgress / 100,
                      backgroundColor: Colors.white10,
                      color: Colors.deepPurpleAccent,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      "${update.downloadProgress.toInt()}% Downloaded",
                      style: const TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!update.isDownloading) ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Later", style: TextStyle(color: Colors.white38)),
                ),
                ElevatedButton(
                  onPressed: () => update.startUpdate(() {
                    Navigator.pop(ctx);
                  }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Update Now"),
                ),
              ] else ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text("Installing soon...", style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final updateProvider = Provider.of<UpdateProvider>(context);

    // Listen for update availability
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
      home: FutureBuilder(
        future: widget.firebaseInit,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScreen();
          }
          
          if (snapshot.hasError) {
            return Scaffold(body: Center(child: Text("Error: ${snapshot.error}")));
          }

          final authService = Provider.of<AuthService>(context, listen: false);
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
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent)),
    );
  }
}
