import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

class FCMTestScreen extends StatefulWidget {
  const FCMTestScreen({super.key});

  @override
  State<FCMTestScreen> createState() => _FCMTestScreenState();
}

class _FCMTestScreenState extends State<FCMTestScreen> {
  String? _token;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      setState(() {
        _token = token;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _token = "Error fetching token: $e";
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard() {
    if (_token != null) {
      Clipboard.setData(ClipboardData(text: _token!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Token copied to clipboard!")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        title: const Text("FCM Setup Test", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "FCM Configuration Status",
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStatusItem("Firebase Initialized", true),
            _buildStatusItem("Messaging Permission", true),
            const SizedBox(height: 32),
            const Text(
              "Your FCM Device Token:",
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
                  : Column(
                      children: [
                        Text(
                          _token ?? "No Token Found",
                          style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 12, fontFamily: 'monospace'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _copyToClipboard,
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text("Copy Token"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurpleAccent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 32),
            const Text(
              "Note: Use this token in your Node.js backend with Firebase Admin SDK to test sending notifications to this specific device.",
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String title, bool isOk) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(isOk ? Icons.check_circle : Icons.error, color: isOk ? Colors.greenAccent : Colors.redAccent, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }
}
