import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../models/card_model.dart';
import '../providers/card_provider.dart';
import '../services/gmail_service.dart';

class EmailManagementScreen extends StatefulWidget {
  const EmailManagementScreen({super.key});

  @override
  State<EmailManagementScreen> createState() => _EmailManagementScreenState();
}

class _EmailManagementScreenState extends State<EmailManagementScreen> {
  List<Map<String, dynamic>> _accounts = [];
  List<CardModel> _allCards = [];
  final Map<String, bool> _syncingAccounts = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final accounts = await DatabaseHelper.instance.getEmailAccounts();
    final cards = await DatabaseHelper.instance.getCards();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _allCards = cards;
      });
    }
  }

  int _linkedCardCount(String email) =>
      _allCards.where((c) => c.linkedEmail == email).length;

  String _formatLastSync(String? lastSyncTime) {
    if (lastSyncTime == null) return 'Never synced';
    try {
      final dt = DateTime.parse(lastSyncTime);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return DateFormat('dd MMM, hh:mm a').format(dt);
    } catch (_) {
      return 'Unknown';
    }
  }

  Future<void> _addAccount() async {
    final account = await GmailService.instance.signIn();
    if (account == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign-in cancelled or failed.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Check for duplicate
    final isDuplicate = _accounts.any((a) => a['email'] == account.email);
    if (isDuplicate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${account.email} is already linked.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
      return;
    }

    await DatabaseHelper.instance.insertEmailAccount({
      'email': account.email,
      'display_name': account.displayName ?? account.email,
      'profile_pic': account.photoUrl,
      'last_sync_time': null,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${account.email} linked successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }

    await _loadData();
  }

  Future<void> _removeAccount(String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Account?',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This will unlink all cards associated with $email. Gmail sync for those cards will stop.',
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await DatabaseHelper.instance.deleteEmailAccount(email);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account removed.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
    await _loadData();
  }

  Future<void> _syncAccount(String email) async {
    setState(() => _syncingAccounts[email] = true);

    try {
      // Show instruction dialog before sign-in
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Select Account',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Please select "$email" from the account chooser to sync this specific account.',
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Continue',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

      if (shouldProceed != true) {
        return;
      }

      // Sign out any current session so we get a fresh token for this account
      await GmailService.instance.signOut();
      await Future.delayed(const Duration(milliseconds: 300));

      // Sign in fresh — user picks from the account chooser
      final signedIn = await GmailService.instance.signIn();
      if (signedIn == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign-in cancelled.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        return;
      }

      if (signedIn.email != email) {
        // User picked a different account — show error and abort
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Wrong account selected. Please select "$email". Sync cancelled.',
              ),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      await GmailService.instance.syncEmails(email, isManual: true);

      // ✅ Refresh CardProvider so the dashboard, card widgets, and analytics
      // all update immediately — without this, data stays in DB but UI is stale
      if (mounted) {
        final provider = context.read<CardProvider>();
        await provider.refreshCards();
        await provider.refreshTransactions();
      }

      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync complete for $email'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingAccounts[email] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF020617)
          : const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Linked Gmail Accounts',
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      body: Column(
        children: [
          // ─── Info banner ──────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.deepPurpleAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.deepPurpleAccent.withOpacity(0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.deepPurpleAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Link Gmail accounts to auto-detect credit card bills and transactions from your inbox.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ─── Accounts list ────────────────────────────────────────────────
          Expanded(
            child: _accounts.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _accounts.length,
                    itemBuilder: (context, index) {
                      final acc = _accounts[index];
                      return _buildAccountTile(acc, isDark);
                    },
                  ),
          ),
        ],
      ),

      // ─── Add account FAB ─────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAccount,
        backgroundColor: Colors.deepPurpleAccent,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Link Gmail',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.deepPurpleAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mail_outline_rounded,
              color: Colors.deepPurpleAccent,
              size: 48,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Gmail Accounts Linked',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Link Gmail" below to connect\nyour Gmail for automatic bill scanning.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTile(Map<String, dynamic> acc, bool isDark) {
    final email = acc['email'] as String;
    final displayName = acc['display_name'] as String? ?? email;
    final profilePic = acc['profile_pic'] as String?;
    final lastSync = acc['last_sync_time'] as String?;
    final cardCount = _linkedCardCount(email);
    final isSyncing = _syncingAccounts[email] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Account header ─────────────────────────────────────────
            Row(
              children: [
                // Profile photo
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.deepPurpleAccent.withOpacity(0.2),
                  backgroundImage: profilePic != null
                      ? NetworkImage(profilePic)
                      : null,
                  child: profilePic == null
                      ? Text(
                          displayName[0].toUpperCase(),
                          style: GoogleFonts.poppins(
                            color: Colors.deepPurpleAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                // Name + email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: GoogleFonts.poppins(
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        email,
                        style: GoogleFonts.poppins(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Delete button
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  onPressed: () => _removeAccount(email),
                  tooltip: 'Remove account',
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 14),

            // ── Stats row ──────────────────────────────────────────────
            Row(
              children: [
                // Linked cards badge
                Flexible(
                  child: _buildStatChip(
                    icon: Icons.credit_card_rounded,
                    label: '$cardCount card${cardCount != 1 ? "s" : ""} linked',
                    color: cardCount > 0
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                // Last sync badge
                Flexible(
                  child: _buildStatChip(
                    icon: Icons.access_time_rounded,
                    label: _formatLastSync(lastSync),
                    color: Colors.blueAccent,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                // Sync button - will shrink if needed
                Flexible(
                  fit: FlexFit.loose,
                  child: SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: isSyncing ? null : () => _syncAccount(email),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        disabledBackgroundColor: Colors.deepPurpleAccent
                            .withOpacity(0.3),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      icon: isSyncing
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white54,
                              ),
                            )
                          : const Icon(
                              Icons.sync_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                      label: Text(
                        isSyncing ? 'Syncing...' : 'Sync Now',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ── Linked card names (if any) ─────────────────────────────
            if (cardCount > 0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _allCards
                    .where((c) => c.linkedEmail == email)
                    .map(
                      (c) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.deepPurpleAccent.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.credit_card_rounded,
                              size: 12,
                              color: Colors.deepPurpleAccent,
                            ),
                            const SizedBox(width: 5),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: 120),
                              child: Text(
                                '${c.bank} ••${c.number.length >= 4 ? c.number.substring(c.number.length - 4) : ""}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.deepPurpleAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
