import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/card_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/update_provider.dart';
import '../providers/security_provider.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BackupService _backupService = BackupService();
  bool _isProcessing = false;
  String _processMessage = "Processing...";
  
  String _appVersion = "1.0.0";
  String _buildNumber = "1";

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  void _showPinDialog(BuildContext context) {
    final security = context.read<SecurityProvider>();
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF0F172A),
        title: Text(security.isPinSet ? "Change PIN" : "Set 4-Digit PIN", style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("This PIN will be used as a fallback for biometric login.", style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 10),
              decoration: const InputDecoration(
                counterText: "",
                hintText: "••••",
                hintStyle: TextStyle(color: Colors.white10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.length == 4) {
                security.setPin(controller.text);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PIN saved successfully")));
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("PIN must be 4 digits")));
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _handleLogout(BuildContext context) async {
    setState(() {
      _isProcessing = true;
      _processMessage = "Signing out securely...";
    });

    await Future.delayed(const Duration(seconds: 2));

    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.signOut();

    if (mounted) {
      setState(() => _isProcessing = false);
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Future<void> _runBackupRestore(Future<void> Function() action, String successMessage) async {
    setState(() {
      _isProcessing = true;
      _processMessage = "Syncing with Vault...";
    });
    try {
      await action();
      if (mounted) {
        context.read<CardProvider>().refreshCards();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Action failed: ${e.toString()}"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final updateProvider = Provider.of<UpdateProvider>(context);
    final security = Provider.of<SecurityProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text("Settings", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const SizedBox(height: 10),
              // User Profile Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark 
                      ? [Colors.deepPurple.shade900.withOpacity(0.5), Colors.blue.shade900.withOpacity(0.3)]
                      : [Colors.deepPurple.shade100, Colors.blue.shade50],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.deepPurpleAccent,
                      child: Text(
                        user?.email?.substring(0, 1).toUpperCase() ?? "U",
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.email ?? "Guest User",
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            "Pro Account • Cloud Sync Active",
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                      onPressed: () => _handleLogout(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              _buildSectionHeader("APPEARANCE"),
              _buildSettingItem(
                context: context,
                icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: isDark ? Colors.orangeAccent : Colors.amber,
                title: "Dark Mode",
                subtitle: isDark ? "Current: Dark" : "Current: Light",
                trailing: Switch(
                  value: isDark, 
                  onChanged: (v) => themeProvider.toggleTheme(v), 
                  activeColor: Colors.deepPurpleAccent,
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionHeader("SECURITY"),
              _buildSettingItem(
                context: context,
                icon: Icons.fingerprint_rounded,
                color: Colors.purpleAccent,
                title: "Biometric Login",
                subtitle: "Unlock vault with fingerprint",
                trailing: Switch(
                  value: security.isBiometricEnabled, 
                  onChanged: (v) => security.setBiometricEnabled(v), 
                  activeColor: Colors.deepPurpleAccent,
                ),
              ),
              _buildSettingItem(
                context: context,
                icon: Icons.lock_outline_rounded,
                color: Colors.blueAccent,
                title: "Login PIN",
                subtitle: security.isPinSet ? "Update your 4-digit PIN" : "Set a fallback PIN",
                onTap: () => _showPinDialog(context),
                trailing: security.isPinSet 
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => security.removePin(),
                    )
                  : null,
              ),

              const SizedBox(height: 16),
              _buildSectionHeader("CLOUD SYNC"),
              _buildSettingItem(
                context: context,
                icon: Icons.cloud_upload_outlined,
                color: Colors.blueAccent,
                title: "Manual Backup",
                subtitle: "Push local cards to Firebase",
                onTap: () => _runBackupRestore(_backupService.onlineBackup, "Cloud backup successful"),
              ),
              _buildSettingItem(
                context: context,
                icon: Icons.cloud_download_outlined,
                color: Colors.greenAccent,
                title: "Cloud Restore",
                subtitle: "Sync data from your account",
                onTap: () => _runBackupRestore(_backupService.onlineRestore, "Cloud restore successful"),
              ),
              
              const SizedBox(height: 16),
              _buildSectionHeader("DANGER ZONE"),
              _buildSettingItem(
                context: context,
                icon: Icons.delete_forever_rounded,
                color: Colors.redAccent,
                title: "Wipe Local Data",
                subtitle: "Delete all cards from this device",
                onTap: () async {
                  bool? confirm = await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Text("Confirm Wipe"),
                      content: const Text("This will delete all cards from local storage. Cloud data is safe."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text("Wipe Everything", style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await context.read<CardProvider>().clearAllCards();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Local data cleared")));
                  }
                },
              ),

              const SizedBox(height: 16),
              _buildSectionHeader("ABOUT"),
              _buildSettingItem(
                context: context,
                icon: Icons.info_outline_rounded,
                color: Colors.blueGrey,
                title: "App Version",
                subtitle: "v$_appVersion ($_buildNumber)",
                onTap: () {
                  if (updateProvider.isUpdateAvailable) {
                    context.read<UpdateProvider>().checkForUpdates();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Checking for updates...")));
                    updateProvider.checkForUpdates();
                  }
                },
              ),
              const SizedBox(height: 40),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.deepPurpleAccent),
                    const SizedBox(height: 20),
                    Text(_processMessage, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.poppins(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildSettingItem({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        trailing: trailing ?? Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white12 : Colors.black12),
      ),
    );
  }
}
