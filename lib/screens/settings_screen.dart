import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/card_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/update_provider.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BackupService _backupService = BackupService();
  bool _isProcessingLogout = false;
  String _logoutMessage = "Signing out securely...";
  
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

  void _showUpdateDialog(BuildContext context, UpdateProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer<UpdateProvider>(
        builder: (context, updateProvider, child) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: const Color(0xFF0F172A),
          title: const Text("New Update Available 🚀", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(updateProvider.updateMessage, style: const TextStyle(color: Colors.white70)),
              if (updateProvider.isDownloading) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: updateProvider.downloadProgress / 100,
                  color: Colors.deepPurpleAccent, 
                  backgroundColor: Colors.white10
                ),
                const SizedBox(height: 8),
                Text(
                  "Downloading: ${updateProvider.downloadProgress.toStringAsFixed(0)}%", 
                  style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 12, fontWeight: FontWeight.bold)
                ),
              ],
            ],
          ),
          actions: [
            if (!updateProvider.isDownloading)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Later", style: TextStyle(color: Colors.grey)),
              ),
            if (!updateProvider.isDownloading)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => updateProvider.startUpdate(() {
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                }),
                child: const Text("Update Now"),
              ),
          ],
        ),
      ),
    );
  }

  void _handleLogout(BuildContext context) async {
    setState(() {
      _isProcessingLogout = true;
      _logoutMessage = "Signing out securely...";
    });

    await Future.delayed(const Duration(seconds: 2));

    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.signOut();

    if (mounted) {
      setState(() => _isProcessingLogout = false);
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Future<void> _runBackupRestore(Future<void> Function() action, String successMessage) async {
    setState(() {
      _isProcessingLogout = true;
      _logoutMessage = "Syncing with Vault...";
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
      if (mounted) setState(() => _isProcessingLogout = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final updateProvider = Provider.of<UpdateProvider>(context);
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
              _buildSectionHeader("LOCAL BACKUP"),
              _buildSettingItem(
                context: context,
                icon: Icons.ios_share_rounded,
                color: Colors.orangeAccent,
                title: "Export JSON",
                subtitle: "Share encrypted backup file",
                onTap: () => _runBackupRestore(_backupService.offlineBackup, "Backup file shared"),
              ),
              _buildSettingItem(
                context: context,
                icon: Icons.file_present_rounded,
                color: Colors.tealAccent,
                title: "Import JSON",
                subtitle: "Restore from a shared file",
                onTap: () => _runBackupRestore(_backupService.offlineRestore, "Local restore successful"),
              ),

              const SizedBox(height: 16),
              _buildSectionHeader("SECURITY"),
              _buildSettingItem(
                context: context,
                icon: Icons.fingerprint_rounded,
                color: Colors.purpleAccent,
                title: "Biometric Lock",
                subtitle: "Require fingerprint on start",
                trailing: Switch(value: true, onChanged: (v) {}, activeColor: Colors.deepPurpleAccent),
              ),
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
                trailing: updateProvider.isUpdateAvailable 
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text("UPDATE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  : null,
                onTap: () {
                  if (updateProvider.isUpdateAvailable) {
                    _showUpdateDialog(context, updateProvider);
                  } else {
                    updateProvider.checkForUpdates().then((_) {
                       if (mounted && !updateProvider.isUpdateAvailable) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text("App is up to date! 🚀")),
                         );
                       }
                    });
                  }
                },
              ),
              const SizedBox(height: 40),
            ],
          ),
          if (_isProcessingLogout)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.deepPurpleAccent),
                    const SizedBox(height: 20),
                    Text(_logoutMessage, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500)),
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
