import 'dart:async';
import 'dart:io';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF0F172A),
        title: Text(
          security.isPinSet ? "Change PIN" : "Set 4-Digit PIN",
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "This PIN will be used as a fallback for biometric login.",
              style: TextStyle(color: Colors.white70, fontSize: 13),
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
                fontSize: 24,
                letterSpacing: 10,
              ),
              decoration: const InputDecoration(
                counterText: "",
                hintText: "••••",
                hintStyle: TextStyle(color: Colors.white10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.length == 4) {
                security.setPin(controller.text);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("PIN saved successfully")),
                );
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text("PIN must be 4 digits")),
                );
              }
            },
            child: const Text("Save"),
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
            content: Text(
              "No linked email accounts. Use 'Add Google Account' first.",
            ),
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
            }).toList(),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error: $e")));
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
        title: Text(
          "Settings",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [Colors.deepPurple.shade800, Colors.blue.shade800]
                        : [Colors.deepPurple.shade100, Colors.blue.shade100],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.deepPurpleAccent,
                      child: Text(
                        user?.email?.substring(0, 1).toUpperCase() ?? "U",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
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
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Cloud Sync Active",
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.logout_rounded,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _handleLogout(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionHeader("APPEARANCE"),
              _buildSettingItem(
                context: context,
                icon: isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
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
              _buildSectionHeader("PROFILES"),
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
                    color: Colors.pinkAccent,
                    title: "Manage Profiles",
                    subtitle: subtitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfilesScreen()),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),
              _buildSectionHeader("SECURITY & LINKING"),
              _buildSettingItem(
                context: context,
                icon: Icons.alternate_email_rounded,
                color: Colors.cyanAccent,
                title: "Manage Gmail Accounts",
                subtitle: "Add or remove authorized emails",
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EmailManagementScreen(),
                  ),
                ),
              ),
              _buildSettingItem(
                context: context,
                icon: Icons.link_rounded,
                color: Colors.blueAccent,
                title: "Link Cards to Email",
                subtitle: "Select multiple cards to link",
                onTap: () => _showLinkEmailDialog(context),
              ),
              _buildSettingItem(
                context: context,
                icon: Icons.link_off_rounded,
                color: Colors.amberAccent,
                title: "Delink Email ID",
                subtitle: "Stop syncing for all linked cards",
                onTap: () => _showDelinkEmailDialog(context),
              ),
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
                subtitle: security.isPinSet
                    ? "Update your 4-digit PIN"
                    : "Set a fallback PIN",
                onTap: () => _showPinDialog(context),
                trailing: security.isPinSet
                    ? IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                        onPressed: () => security.removePin(),
                      )
                    : null,
              ),

              const SizedBox(height: 16),
              _buildSectionHeader("NOTIFICATIONS"),
              _buildSettingItem(
                context: context,
                icon: Icons.email_outlined,
                color: Colors.indigoAccent,
                title: "Link Email Reminder",
                subtitle: "Notify if cards are not linked",
                trailing: Switch(
                  value: security.showLinkEmailReminder,
                  onChanged: (v) => security.setLinkEmailReminder(v),
                  activeColor: Colors.deepPurpleAccent,
                ),
              ),
              _buildSettingItem(
                context: context,
                icon: Icons.calendar_month_outlined,
                color: Colors.orangeAccent,
                title: "Due Date Reminder",
                subtitle: "Notify if due dates are missing",
                trailing: Switch(
                  value: security.showUpdateDueDateReminder,
                  onChanged: (v) => security.setUpdateDueDateReminder(v),
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
                onTap: () => _runBackupRestore(
                  _backupService.onlineBackup,
                  "Cloud backup successful",
                ),
              ),
              _buildSettingItem(
                context: context,
                icon: Icons.cloud_download_outlined,
                color: Colors.greenAccent,
                title: "Cloud Restore",
                subtitle: "Sync data from your account",
                onTap: () => _runBackupRestore(
                  _backupService.onlineRestore,
                  "Cloud restore successful",
                ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: const Text("Confirm Wipe"),
                      content: const Text(
                        "This will delete all cards from local storage. Cloud data is safe.",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("Cancel"),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            "Wipe Everything",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await context.read<CardProvider>().clearAllCards();
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Local data cleared")),
                      );
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Checking for updates...")),
                    );
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
                    const CircularProgressIndicator(
                      color: Colors.deepPurpleAccent,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _processMessage,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 4),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          color: Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 10,
          letterSpacing: 1.0,
        ),
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
        trailing:
            trailing ??
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white12 : Colors.black12,
              size: 20,
            ),
      ),
    );
  }
}

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
