import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/lock_screen.dart';
import 'providers/card_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CardProvider()),
      ],
      child: const CardVault(),
    ),
  );
}

class CardVault extends StatelessWidget {
  const CardVault({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CardVault',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF020617),
        colorSchemeSeed: Colors.blue,
      ),
      home: const LockScreen(),
    );
  }
}
