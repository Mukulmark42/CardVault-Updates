import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/card_provider.dart';
import '../providers/security_provider.dart';
import '../widgets/credit_card_widget.dart';
import '../services/backup_service.dart';
import '../models/card_model.dart';
import 'email_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _searchQuery = "";
  String? _selectedBank;
  bool _isSyncing = false;
  late AnimationController _syncController;
  late AnimationController _pulseController;
  static bool _sessionAlertShown = false;

  @override
  void initState() {
    super.initState();
    _syncController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _syncController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String _getAbbreviatedBank(String bank) {
    String name = bank.toUpperCase();
    if (name.contains("HDFC")) return "HDFC";
    if (name.contains("ICICI")) return "ICICI";
    if (name.contains("SBI") || name.contains("STATE BANK")) return "SBI";
    if (name.contains("AXIS")) return "AXIS";
    if (name.contains("KOTAK")) return "KOTAK";
    if (name.contains("IDFC")) return "IDFC";
    if (name.contains("INDUSIND")) return "INDUSIND";
    if (name.contains("AMEX") || name.contains("AMERICAN")) return "AMEX";
    if (name.contains("YES")) return "YES";
    if (name.contains("RBL")) return "RBL";
    if (name.contains("BOB") || name.contains("BARODA")) return "BOB";
    if (name.contains("CITI")) return "CITI";
    if (name.contains("SC ") || name.contains("STANDARD")) return "SC";
    if (name.contains("HSBC")) return "HSBC";
    if (name.contains("FEDERAL")) return "FEDERAL";
    if (name.contains("IDBI")) return "IDBI";
    return bank.split(' ').first.toUpperCase();
  }

  Color _getBankColor(String bank) {
    String name = bank.toUpperCase();
    if (name.contains("HDFC")) return const Color(0xFF004C8F);
    if (name.contains("ICICI")) return const Color(0xFFF27020);
    if (name.contains("SBI") || name.contains("STATE BANK")) return const Color(0xFF25A8E0);
    if (name.contains("AXIS")) return const Color(0xFF97144D);
    if (name.contains("KOTAK")) return const Color(0xFFED1C24);
    if (name.contains("IDFC")) return const Color(0xFF91171A);
    if (name.contains("AMEX") || name.contains("AMERICAN")) return const Color(0xFF007BC1);
    if (name.contains("YES")) return const Color(0xFF0054A6);
    if (name.contains("RBL")) return const Color(0xFF005697);
    if (name.contains("INDUSIND")) return const Color(0xFF622424);
    if (name.contains("BOB") || name.contains("BARODA")) return const Color(0xFFFF6600);
    if (name.contains("FEDERAL")) return const Color(0xFF004082);
    return Colors.blueGrey.shade700;
  }

  Future<void> _handleSync() async {
    setState(() => _isSyncing = true);
    _syncController.repeat();
    try {
      await BackupService().onlineBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text("Cloud Sync Complete", style: GoogleFonts.poppins(fontSize: 13)),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sync failed: ${e.toString()}"),
            backgroundColor: Colors.redAccent.withOpacity(0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      _syncController.stop();
      _syncController.reset();
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _checkAndShowSmartAlert(BuildContext context, List<CardModel> cards) {
    if (_sessionAlertShown) return;
    // Respect the user's Settings toggle — if reminder is disabled, skip
    final security = context.read<SecurityProvider>();
    if (!security.showLinkEmailReminder) return;

    final unlinked = cards.where((c) => c.linkedEmail == null).toList();
    if (unlinked.isEmpty) return;
    _sessionAlertShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showUnlinkedEmailAlert(unlinked.length);
    });
  }

  void _showUnlinkedEmailAlert(int count) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.07)
                    : Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.orangeAccent.withOpacity(0.35),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orangeAccent.withOpacity(0.3),
                            Colors.orange.withOpacity(0.15),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.link_off_rounded, color: Colors.orangeAccent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Email Sync Not Set Up',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            '$count card${count > 1 ? 's are' : ' is'} not linked to any email.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Text(
                    'Link a Gmail account so CardVault can automatically detect bills, transactions, and payment confirmations.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.orangeAccent.withOpacity(0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: Text(
                          'Later',
                          style: GoogleFonts.poppins(
                            color: isDark ? Colors.white54 : Colors.black38,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.orangeAccent, Color(0xFFFF8C00)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orangeAccent.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const EmailManagementScreen()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: Text(
                            'Set Up Now',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF020617) : const Color(0xFFF0F4FF),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const RadialGradient(
                  center: Alignment(-0.7, -0.7),
                  radius: 1.4,
                  colors: [Color(0xFF1A1040), Color(0xFF020617)],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEEF2FF), Color(0xFFF8FAFF)],
                ),
        ),
        child: SafeArea(
          bottom: false,
          child: Consumer<CardProvider>(
            builder: (context, provider, child) {
              _checkAndShowSmartAlert(context, provider.cards);

              final security = context.read<SecurityProvider>();
              final missingDueDateCount = provider.cards.where((c) => c.dueDate == null).length;

              Map<String, int> bankCounts = {};
              for (var card in provider.cards) {
                String shortName = _getAbbreviatedBank(card.bank);
                bankCounts[shortName] = (bankCounts[shortName] ?? 0) + 1;
              }

              List<CardModel> sortedCards = List.from(provider.cards);
              sortedCards.sort((a, b) {
                if (a.dueDate == null && b.dueDate == null) return 0;
                if (a.dueDate == null) return 1;
                if (b.dueDate == null) return -1;
                return DateTime.parse(a.dueDate!).compareTo(DateTime.parse(b.dueDate!));
              });

              final filteredCards = sortedCards.where((card) {
                final query = _searchQuery.toLowerCase();
                final matchesSearch = card.bank.toLowerCase().contains(query) ||
                    card.holder.toLowerCase().contains(query) ||
                    card.variant.toLowerCase().contains(query);
                if (!matchesSearch) return false;
                if (_selectedBank != null) {
                  return _getAbbreviatedBank(card.bank) == _selectedBank;
                }
                return true;
              }).toList();

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Premium Header ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Card Vault",
                                  style: GoogleFonts.poppins(
                                    color: isDark ? Colors.white : const Color(0xFF1A1040),
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                Text(
                                  "${provider.cards.length} card${provider.cards.length == 1 ? '' : 's'} in your wallet",
                                  style: GoogleFonts.poppins(
                                    color: isDark ? Colors.white38 : Colors.black38,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Sync button
                          GestureDetector(
                            onTap: _isSyncing ? null : _handleSync,
                            child: AnimatedBuilder(
                              animation: _pulseController,
                              builder: (_, child) {
                                return Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: _isSyncing
                                          ? [const Color(0xFF4F46E5), const Color(0xFF7C3AED)]
                                          : [
                                              const Color(0xFF4F46E5).withOpacity(0.15),
                                              const Color(0xFF7C3AED).withOpacity(0.15),
                                            ],
                                    ),
                                    border: Border.all(
                                      color: _isSyncing
                                          ? const Color(0xFF7C3AED).withOpacity(0.6 + 0.4 * _pulseController.value)
                                          : const Color(0xFF7C3AED).withOpacity(0.25),
                                      width: 1.5,
                                    ),
                                    boxShadow: _isSyncing
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF7C3AED).withOpacity(0.4 * _pulseController.value),
                                              blurRadius: 16,
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: AnimatedRotation(
                                    turns: _isSyncing ? _syncController.value : 0,
                                    duration: Duration.zero,
                                    child: Icon(
                                      _isSyncing ? Icons.sync_rounded : Icons.cloud_done_rounded,
                                      color: _isSyncing ? Colors.white : const Color(0xFF7C3AED),
                                      size: 20,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Missing Due Date Alert ───────────────────────────────
                  if (missingDueDateCount > 0 && security.showUpdateDueDateReminder)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.orangeAccent.withOpacity(isDark ? 0.15 : 0.1),
                                    Colors.orange.withOpacity(isDark ? 0.08 : 0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.orangeAccent.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.notification_important_rounded, color: Colors.orangeAccent, size: 16),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "$missingDueDateCount card${missingDueDateCount > 1 ? 's' : ''} missing due date — update in Vault",
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ── Search + Filter ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Glass search bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.white.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                                  ),
                                ),
                                child: TextField(
                                  onChanged: (v) => setState(() => _searchQuery = v),
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 14,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: "Search cards, banks, holders…",
                                    hintStyle: TextStyle(
                                      color: isDark ? Colors.white24 : Colors.black26,
                                      fontSize: 13.5,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search_rounded,
                                      color: isDark ? Colors.white24 : Colors.black26,
                                      size: 20,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Bank filter chips
                          if (bankCounts.isNotEmpty)
                            SizedBox(
                              height: 38,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                children: bankCounts.entries.map((e) {
                                  final bankColor = _getBankColor(e.key);
                                  final isSelected = _selectedBank == e.key;

                                  return GestureDetector(
                                    onTap: () => setState(() => _selectedBank = isSelected ? null : e.key),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      margin: const EdgeInsets.only(right: 10),
                                      padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                                      decoration: BoxDecoration(
                                        gradient: isSelected
                                            ? LinearGradient(
                                                colors: [bankColor, bankColor.withOpacity(0.7)],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              )
                                            : null,
                                        color: isSelected ? null : bankColor.withOpacity(isDark ? 0.18 : 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: bankColor.withOpacity(isSelected ? 0.0 : 0.4),
                                          width: 1,
                                        ),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: bankColor.withOpacity(0.35),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                )
                                              ]
                                            : [],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            e.key,
                                            style: GoogleFonts.poppins(
                                              color: isSelected ? Colors.white : (isDark ? Colors.white70 : bankColor),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            width: 26,
                                            height: 26,
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Colors.white.withOpacity(0.2)
                                                  : Colors.black.withOpacity(0.12),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                e.value.toString(),
                                                style: TextStyle(
                                                  color: isSelected ? Colors.white : (isDark ? Colors.white54 : bankColor.withOpacity(0.8)),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),

                          const SizedBox(height: 22),

                          // Section label
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 14,
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
                                    _selectedBank == null ? "ACTIVE CARDS" : "$_selectedBank COLLECTION",
                                    style: GoogleFonts.poppins(
                                      color: isDark ? Colors.white54 : Colors.black45,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                              if (_selectedBank != null)
                                GestureDetector(
                                  onTap: () => setState(() => _selectedBank = null),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      "SHOW ALL",
                                      style: GoogleFonts.poppins(
                                        color: const Color(0xFF7C3AED),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                  ),

                  // ── Card List ────────────────────────────────────────────
                  if (filteredCards.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(isDark),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final card = filteredCards[index];
                            return RepaintBoundary(
                              key: ValueKey('home_${card.id}'),
                              child: CreditCardWidget(
                                card: card,
                                isCompact: true,
                              ),
                            );
                          },
                          childCount: filteredCards.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 160)),
                ],
              );
            },
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
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF7C3AED).withOpacity(0.15),
                  const Color(0xFF4F46E5).withOpacity(0.08),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.credit_card_off_rounded,
              size: 36,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "No cards found",
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Try adjusting your search or filters",
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white24 : Colors.black26,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
