import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
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
import '../services/gmail_service.dart';
import '../database/database_helper.dart';
import '../models/card_model.dart';
import '../providers/profile_provider.dart';
import 'email_management_screen.dart';
import 'profiles_screen.dart';

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFF0F172A),
        title: Text(
          security.isPinSet ? "Change PIN" : "Set 4-Digit PIN",
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "This PIN will be used as a fallback for biometric login.",
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              obscuringCharacter: '•',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                letterSpacing: 14,
              ),
              decoration: InputDecoration(
                counterText: "",
                hintText: "••••",
                hintStyle: const TextStyle(color: Colors.white12, fontSize: 28),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 2),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.04),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.length == 4) {
                security.setPin(controller.text);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("PIN saved successfully"),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text("PIN must be 4 digits")),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text("Save", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _addEmailAccount() async {
    setState(() {
      _isProcessing = true;
      _processMessage = "Connecting to Google...";
    });

    try {
      final account = await GmailService.instance.signIn();
      if (account != null) {
        await DatabaseHelper.instance.insertEmailAccount({
          'email': account.email,
          'display_name': account.displayName,
          'profile_pic': account.photoUrl,
          'last_sync_time': DateTime.now().toIso8601String(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Account ${account.email} added successfully"),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Failed to connect Google account: ${e is SocketException ? 'Network error' : 'Authentication failed'}",
            ),
            action: SnackBarAction(label: "Retry", onPressed: _addEmailAccount),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showLinkEmailDialog(BuildContext context) async {
    final provider = context.read<CardProvider>();
    final db = DatabaseHelper.instance;
    final accounts = await db.getEmailAccounts();

    if (accounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No linked email accounts. Use 'Add Google Account' first."),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LinkCardsDialog(
        accounts: accounts,
        allCards: provider.cards,
        onLink: (selectedCards, selectedEmail) async {
          for (int id in selectedCards) {
            final card = provider.cards.firstWhere((c) => c.id == id);
            await provider.updateCard(
              card.copyWith(linkedEmail: () => selectedEmail),
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Cards linked successfully")),
            );
          }
        },
      ),
    );
  }

  void _showDelinkEmailDialog(BuildContext context) async {
    final provider = context.read<CardProvider>();
    final db = DatabaseHelper.instance;
    final accounts = await db.getEmailAccounts();

    if (accounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No linked email accounts.")),
        );
      }
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delink Email ID"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Select an email to delink from all associated cards.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ...accounts.map((acc) {
              final email = acc['email'] as String;
              return ListTile(
                title: Text(email, style: const TextStyle(fontSize: 14)),
                leading: const Icon(
                  Icons.alternate_email_rounded,
                  size: 20,
                  color: Colors.amber,
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  _confirmDelink(context, email);
                },
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelink(BuildContext context, String email) async {
    final provider = context.read<CardProvider>();
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Delink"),
        content: Text(
          "This will remove $email from all linked cards. Gmail sync for these cards will stop.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Delink Now",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _isProcessing = true;
        _processMessage = "Delinking cards...";
      });

      try {
        final cardsToDelink = provider.cards
            .where((c) => c.linkedEmail == email)
            .toList();
        for (var card in cardsToDelink) {
          await provider.delinkEmail(card);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("All cards delinked from $email")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
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

  Future<void> _runBackupRestore(
    Future<void> Function() action,
    String successMessage,
  ) async {
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showUpdateScreen(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer<UpdateProvider>(
        builder: (context, updateProvider, child) {
          final localVersion = 'v$_appVersion ($_buildNumber)';
          final remoteVersion = updateProvider.remoteVersion.isNotEmpty
              ? updateProvider.remoteVersion
              : 'Unknown';
          final releaseNotes = updateProvider.releaseNotes.isNotEmpty
              ? updateProvider.releaseNotes
              : 'No release notes provided.';

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: const Color(0xFF0F172A),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Text("New Update 🚀",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    )),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Current: $localVersion',
                      style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  Text('Latest:  v$remoteVersion',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                  const SizedBox(height: 16),
                  const Text('Release Notes:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  const Divider(color: Colors.white10),
                  Text(releaseNotes,
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 16),
                  if (updateProvider.isDownloading)
                    Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: updateProvider.downloadProgress / 100,
                            minHeight: 8,
                            backgroundColor: Colors.white10,
                            color: updateProvider.downloadStatus == 'paused'
                                ? Colors.orange
                                : const Color(0xFF7C3AED),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          updateProvider.downloadStatus == 'paused'
                              ? '⏸ Paused — ${updateProvider.downloadProgress.toStringAsFixed(1)}% (screen-off safe, resuming…)'
                              : updateProvider.downloadStatus == 'pending'
                                  ? '⏳ Starting download…'
                                  : 'Downloading: ${updateProvider.downloadProgress.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Download continues even if screen turns off',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withOpacity(0.4)),
                        ),
                      ],
                    ),
                  if (updateProvider.hasError)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              updateProvider.errorMessage,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              if (!updateProvider.isDownloading)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text("Later", style: GoogleFonts.poppins(color: Colors.white54)),
                ),
              if (updateProvider.isDownloading)
                TextButton(
                  onPressed: () {
                    updateProvider.cancelUpdate();
                    Navigator.pop(ctx);
                  },
                  child: Text("Cancel",
                      style: GoogleFonts.poppins(color: Colors.redAccent)),
                ),
              ElevatedButton(
                onPressed: updateProvider.isDownloading
                    ? null
                    : () => updateProvider.startUpdate(() {}),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      updateProvider.hasError ? Colors.orange : const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  updateProvider.isDownloading
                      ? 'Downloading…'
                      : (updateProvider.hasError ? 'Retry' : 'Update Now'),
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final updateProvider = Provider.of<UpdateProvider>(context);
    final security = Provider.of<SecurityProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF0F4FF),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const RadialGradient(
                  center: Alignment(0.0, -0.8),
                  radius: 1.4,
                  colors: [Color(0xFF1A1040), Color(0xFF020617)],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEEF2FF), Color(0xFFF8FAFF)],
                ),
        ),
        child: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Premium App Bar ─────────────────────────────────────
                SliverAppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  pinned: false,
                  floating: true,
                  snap: true,
                  title: Text(
                    "Settings",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: isDark ? Colors.white : const Color(0xFF1A1040),
                      letterSpacing: -0.3,
                    ),
                  ),
                  centerTitle: false,
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),

                        // ── Premium User Profile Card ─────────────────────
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: isDark
                                    ? LinearGradient(
                                        colors: [
                                          const Color(0xFF7C3AED).withOpacity(0.25),
                                          const Color(0xFF4F46E5).withOpacity(0.12),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : LinearGradient(
                                        colors: [
                                          const Color(0xFF7C3AED).withOpacity(0.12),
                                          const Color(0xFF4F46E5).withOpacity(0.06),
                                        ],
                                      ),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: const Color(0xFF7C3AED).withOpacity(isDark ? 0.35 : 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Avatar
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF7C3AED).withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        user?.email?.substring(0, 1).toUpperCase() ?? "U",
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user?.email ?? "Guest User",
                                          style: GoogleFonts.poppins(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: Colors.greenAccent,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.greenAccent.withOpacity(0.6),
                                                    blurRadius: 4,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              "Cloud Sync Active",
                                              style: GoogleFonts.poppins(
                                                color: isDark ? Colors.white54 : Colors.black45,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Logout button
                                  GestureDetector(
                                    onTap: () => _handleLogout(context),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.redAccent.withOpacity(0.2),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.logout_rounded,
                                        color: Colors.redAccent,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── APPEARANCE ──────────────────────────────────────
                        _buildSectionHeader("APPEARANCE", isDark),
                        _buildSettingItem(
                          context: context,
                          icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                          color: isDark ? const Color(0xFFFFB347) : const Color(0xFFFFD700),
                          title: "Dark Mode",
                          subtitle: isDark ? "Dark theme active" : "Light theme active",
                          isDark: isDark,
                          trailing: Switch(
                            value: isDark,
                            onChanged: (v) => themeProvider.toggleTheme(v),
                            activeColor: const Color(0xFF7C3AED),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── PROFILES ────────────────────────────────────────
                        _buildSectionHeader("PROFILES", isDark),
                        Consumer<ProfileProvider>(
                          builder: (context, profileProvider, _) {
                            final count = profileProvider.profiles.length;
                            final defaultProfile = profileProvider.activeProfile;
                            final subtitle = count == 0
                                ? "Create card holder profiles"
                                : "$count profile${count > 1 ? 's' : ''}${defaultProfile != null ? ' • Default: ${defaultProfile.name}' : ''}";

                            return _buildSettingItem(
                              context: context,
                              icon: Icons.people_outline_rounded,
                              color: const Color(0xFFEC4899),
                              title: "Manage Profiles",
                              subtitle: subtitle,
                              isDark: isDark,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ProfilesScreen()),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 20),

                        // ── SECURITY & LINKING ──────────────────────────────
                        _buildSectionHeader("SECURITY & LINKING", isDark),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.alternate_email_rounded,
                          color: const Color(0xFF06B6D4),
                          title: "Manage Gmail Accounts",
                          subtitle: "Add or remove authorized emails",
                          isDark: isDark,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const EmailManagementScreen()),
                          ),
                        ),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.link_rounded,
                          color: const Color(0xFF3B82F6),
                          title: "Link Cards to Email",
                          subtitle: "Select multiple cards to link",
                          isDark: isDark,
                          onTap: () => _showLinkEmailDialog(context),
                        ),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.link_off_rounded,
                          color: const Color(0xFFF59E0B),
                          title: "Delink Email ID",
                          subtitle: "Stop syncing for all linked cards",
                          isDark: isDark,
                          onTap: () => _showDelinkEmailDialog(context),
                        ),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.fingerprint_rounded,
                          color: const Color(0xFF8B5CF6),
                          title: "Biometric Login",
                          subtitle: "Unlock vault with fingerprint",
                          isDark: isDark,
                          trailing: Switch(
                            value: security.isBiometricEnabled,
                            onChanged: (v) => security.setBiometricEnabled(v),
                            activeColor: const Color(0xFF7C3AED),
                          ),
                        ),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.lock_outline_rounded,
                          color: const Color(0xFF3B82F6),
                          title: "Login PIN",
                          subtitle: security.isPinSet ? "Update your 4-digit PIN" : "Set a fallback PIN",
                          isDark: isDark,
                          onTap: () => _showPinDialog(context),
                          trailing: security.isPinSet
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => security.removePin(),
                                )
                              : null,
                        ),

                        const SizedBox(height: 20),

                        // ── NOTIFICATIONS ───────────────────────────────────
                        _buildSectionHeader("NOTIFICATIONS", isDark),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.email_outlined,
                          color: const Color(0xFF6366F1),
                          title: "Link Email Reminder",
                          subtitle: "Notify if cards are not linked",
                          isDark: isDark,
                          trailing: Switch(
                            value: security.showLinkEmailReminder,
                            onChanged: (v) => security.setLinkEmailReminder(v),
                            activeColor: const Color(0xFF7C3AED),
                          ),
                        ),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.calendar_month_outlined,
                          color: const Color(0xFFFF8C00),
                          title: "Due Date Reminder",
                          subtitle: "Notify if due dates are missing",
                          isDark: isDark,
                          trailing: Switch(
                            value: security.showUpdateDueDateReminder,
                            onChanged: (v) => security.setUpdateDueDateReminder(v),
                            activeColor: const Color(0xFF7C3AED),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── CLOUD SYNC ──────────────────────────────────────
                        _buildSectionHeader("CLOUD SYNC", isDark),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.cloud_upload_outlined,
                          color: const Color(0xFF3B82F6),
                          title: "Manual Backup",
                          subtitle: "Push local cards to Firebase",
                          isDark: isDark,
                          onTap: () => _runBackupRestore(
                            _backupService.onlineBackup,
                            "Cloud backup successful",
                          ),
                        ),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.cloud_download_outlined,
                          color: const Color(0xFF10B981),
                          title: "Cloud Restore",
                          subtitle: "Sync data from your account",
                          isDark: isDark,
                          onTap: () => _runBackupRestore(
                            _backupService.onlineRestore,
                            "Cloud restore successful",
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── LOCAL BACKUP ────────────────────────────────────
                        _buildSectionHeader("LOCAL BACKUP", isDark),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.save_alt_rounded,
                          color: const Color(0xFF14B8A6),
                          title: "Export Local Backup",
                          subtitle: "Save cards to a file on your device",
                          isDark: isDark,
                          onTap: () => _runBackupRestore(
                            _backupService.offlineBackup,
                            "Local backup exported successfully",
                          ),
                        ),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.folder_open_rounded,
                          color: const Color(0xFFFF8C00),
                          title: "Import Local Backup",
                          subtitle: "Restore cards from a backup file",
                          isDark: isDark,
                          onTap: () => _runBackupRestore(
                            _backupService.offlineRestore,
                            "Local backup restored successfully",
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── DANGER ZONE ─────────────────────────────────────
                        _buildDangerHeader(isDark),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(isDark ? 0.08 : 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                          ),
                          child: _buildSettingItem(
                            context: context,
                            icon: Icons.delete_forever_rounded,
                            color: Colors.redAccent,
                            title: "Wipe Local Data",
                            subtitle: "Delete all cards from this device",
                            isDark: isDark,
                            noBorder: true,
                            onTap: () async {
                              bool? confirm = await showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                                  title: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Text("Confirm Wipe",
                                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  content: Text(
                                    "This will delete all cards from local storage. Cloud data is safe.",
                                    style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: isDark ? Colors.white60 : Colors.black54),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text("Cancel"),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: Text("Wipe Everything",
                                          style: GoogleFonts.poppins(
                                              color: Colors.white, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await context.read<CardProvider>().clearAllCards();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Local data cleared")),
                                  );
                                }
                              }
                            },
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── ABOUT ───────────────────────────────────────────
                        _buildSectionHeader("ABOUT", isDark),
                        _buildSettingItem(
                          context: context,
                          icon: Icons.info_outline_rounded,
                          color: Colors.blueGrey,
                          title: "App Version",
                          subtitle: updateProvider.isUpdateAvailable
                              ? "Update Available: v${updateProvider.remoteVersion}"
                              : "v$_appVersion ($_buildNumber)",
                          isDark: isDark,
                          trailing: updateProvider.isUpdateAvailable
                              ? Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.redAccent.withOpacity(0.5),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                )
                              : null,
                          onTap: () {
                            if (updateProvider.isUpdateAvailable) {
                              _showUpdateScreen(context);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Checking for updates...")),
                              );
                              updateProvider.checkForUpdates();
                            }
                          },
                        ),

                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Loading Overlay ─────────────────────────────────────────
            if (_isProcessing)
              ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    color: Colors.black.withOpacity(0.55),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF7C3AED).withOpacity(0.3),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: const AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                                backgroundColor: const Color(0xFF7C3AED).withOpacity(0.15),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _processMessage,
                              style: GoogleFonts.poppins(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2, left: 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white.withOpacity(0.45) : Colors.black38,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2, left: 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 14),
          const SizedBox(width: 5),
          Text(
            "DANGER ZONE",
            style: GoogleFonts.poppins(
              color: Colors.redAccent,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.redAccent.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isDark,
    VoidCallback? onTap,
    Widget? trailing,
    bool noBorder = false,
  }) {
    return Container(
      margin: noBorder ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
      decoration: noBorder
          ? null
          : BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06),
              ),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: color.withOpacity(0.06),
          highlightColor: color.withOpacity(0.03),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withOpacity(0.2), color.withOpacity(0.08)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.chevron_right_rounded,
                      color: isDark ? Colors.white.withOpacity(0.16) : Colors.black.withOpacity(0.16),
                      size: 20,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Link Cards Dialog (unchanged logic) ─────────────────────────────────────

class _LinkCardsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final List<CardModel> allCards;
  final Function(Set<int> selectedCards, String selectedEmail) onLink;

  const _LinkCardsDialog({
    required this.accounts,
    required this.allCards,
    required this.onLink,
  });

  @override
  State<_LinkCardsDialog> createState() => _LinkCardsDialogState();
}

class _LinkCardsDialogState extends State<_LinkCardsDialog> {
  late String _selectedEmail;
  String _searchQuery = "";
  final Set<int> _selectedCards = {};
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _selectedEmail = widget.accounts.first['email'];
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = value;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredCards = widget.allCards.where((c) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return c.bank.toLowerCase().contains(query) ||
          c.holder.toLowerCase().contains(query) ||
          (c.last4?.toLowerCase().contains(query) ?? false);
    }).toList();

    final linkedCardsCount = filteredCards
        .where((c) => c.linkedEmail != null && c.linkedEmail!.isNotEmpty)
        .length;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Text(
              "Link Cards to Email",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Choose an email and select cards to associate.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "${filteredCards.length} cards",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "$linkedCardsCount linked",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedEmail,
                  isExpanded: true,
                  items: widget.accounts
                      .map(
                        (acc) => DropdownMenuItem(
                          value: acc['email'] as String,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.alternate_email_rounded,
                                size: 18,
                                color: Colors.blueAccent,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                acc['email'] as String,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _selectedEmail = val!),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: "Search cards by bank, holder, or last 4 digits...",
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: Colors.grey.shade500,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          size: 18,
                          color: Colors.grey.shade500,
                        ),
                        onPressed: () {
                          _onSearchChanged("");
                          setState(() {
                            _searchQuery = "";
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.05),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Colors.deepPurpleAccent.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          if (filteredCards.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    _searchQuery.isEmpty
                        ? Icons.credit_card_off_rounded
                        : Icons.search_off_rounded,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isEmpty
                        ? "No cards available to link"
                        : "No cards match your search",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _searchQuery.isEmpty
                        ? "Add cards first from the Vault screen"
                        : "Try a different search term",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: filteredCards.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  return _buildCardItem(filteredCards[index], isDark);
                },
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedCards.isEmpty
                        ? null
                        : () {
                            widget.onLink(_selectedCards, _selectedEmail);
                            Navigator.pop(context);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.link_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          "Link ${_selectedCards.length} Card${_selectedCards.length == 1 ? '' : 's'}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem(CardModel card, bool isDark) {
    final isSelected = _selectedCards.contains(card.id);
    final firstName = card.holder.split(' ').first;
    final last4 =
        card.last4 ??
        (card.number.length >= 4
            ? card.number.substring(card.number.length - 4)
            : card.number);
    final isLinked = card.linkedEmail != null && card.linkedEmail!.isNotEmpty;
    final isLinkedToSelectedEmail =
        isLinked && card.linkedEmail == _selectedEmail;

    return Theme(
      data: ThemeData(
        checkboxTheme: CheckboxThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.deepPurple.withOpacity(0.1)
              : (isLinkedToSelectedEmail
                    ? Colors.green.withOpacity(0.05)
                    : Colors.transparent),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.deepPurpleAccent.withOpacity(0.3)
                : (isLinkedToSelectedEmail
                      ? Colors.green.withOpacity(0.2)
                      : Colors.transparent),
            width: 1.5,
          ),
        ),
        child: CheckboxListTile(
          value: isSelected,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          activeColor: Colors.deepPurpleAccent,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      card.bank,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (isLinkedToSelectedEmail) ...[
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 80),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "Already linked",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$firstName • **** $last4",
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              if (isLinked && !isLinkedToSelectedEmail)
                Text(
                  "Linked to ${card.linkedEmail}",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isLinked
                  ? Colors.green.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isLinked ? Icons.link_rounded : Icons.link_off_rounded,
              color: isLinked ? Colors.green : Colors.grey,
              size: 18,
            ),
          ),
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedCards.add(card.id!);
              } else {
                _selectedCards.remove(card.id!);
              }
            });
          },
        ),
      ),
    );
  }
}
