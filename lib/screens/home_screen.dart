import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/card_provider.dart';
import '../widgets/credit_card_widget.dart';
import '../services/backup_service.dart';
import '../models/card_model.dart';
import 'email_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchQuery = "";
  String? _selectedBank;
  bool _isSyncing = false;

  // Once-per-session smart alert flag
  static bool _sessionAlertShown = false;

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
    try {
      await BackupService().onlineBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cloud Sync Complete"), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Sync failed: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _checkAndShowSmartAlert(List<CardModel> cards) {
    if (_sessionAlertShown) return;
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
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Colors.orangeAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.link_off_rounded,
                      color: Colors.orangeAccent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email Sync Not Set Up',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black)),
                      Text(
                          '$count card${count > 1 ? 's are' : ' is'} not linked to any email.',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.white54 : Colors.black45)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Text(
                'Link a Gmail account so CardVault can automatically detect bills, transactions, and payment confirmations.',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.orangeAccent.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Later',
                        style: GoogleFonts.poppins(
                            color:
                                isDark ? Colors.white54 : Colors.black38)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const EmailManagementScreen()));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Set Up Now',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.8, -0.6),
            radius: 1.2,
            colors: isDark 
              ? [const Color(0xFF1E293B).withValues(alpha: 0.5), const Color(0xFF020617)]
              : [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Consumer<CardProvider>(
            builder: (context, provider, child) {
              // Trigger once-per-session smart alert after frame is drawn
              _checkAndShowSmartAlert(provider.cards);

              final missingDueDateCount = provider.cards.where((c) => c.dueDate == null).length;

              Map<String, int> bankCounts = {};
              for (var card in provider.cards) {
                String shortName = _getAbbreviatedBank(card.bank);
                bankCounts[shortName] = (bankCounts[shortName] ?? 0) + 1;
              }

              // Sorting logic for Home Screen: by Due Date
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
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    pinned: false,
                    floating: true,
                    snap: true,
                    centerTitle: false,
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Card Vault",
                          style: GoogleFonts.poppins(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _isSyncing ? null : _handleSync,
                          child: AnimatedRotation(
                            duration: const Duration(seconds: 1),
                            turns: _isSyncing ? 1 : 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isSyncing ? Icons.sync : Icons.cloud_done_rounded,
                                color: Colors.blueAccent,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (missingDueDateCount > 0)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.notification_important_rounded, color: Colors.orangeAccent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "$missingDueDateCount card${missingDueDateCount > 1 ? 's' : ''} missing due date. Update them in the Vault section.",
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            style: TextStyle(color: isDark ? Colors.white : Colors.black),
                            decoration: InputDecoration(
                              hintText: "Search cards...",
                              hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26),
                              prefixIcon: Icon(Icons.search, color: isDark ? Colors.white24 : Colors.black26, size: 20),
                              filled: true,
                              fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          if (bankCounts.isNotEmpty)
                            SizedBox(
                              height: 40,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                children: bankCounts.entries.map((e) {
                                  Color bankColor = _getBankColor(e.key);
                                  bool isSelected = _selectedBank == e.key;
                                  
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedBank = isSelected ? null : e.key;
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      margin: const EdgeInsets.only(right: 12),
                                      padding: const EdgeInsets.fromLTRB(14, 2, 2, 2),
                                      decoration: BoxDecoration(
                                        color: isSelected ? bankColor : bankColor.withOpacity(0.25),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            e.key,
                                            style: GoogleFonts.poppins(
                                              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black54), 
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                e.value.toString(),
                                                style: TextStyle(
                                                  color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.black38), 
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold
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
                          
                          const SizedBox(height: 25),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _selectedBank == null ? "ACTIVE CARDS" : "$_selectedBank COLLECTION",
                                style: GoogleFonts.poppins(
                                  color: isDark ? Colors.white38 : Colors.black38, 
                                  fontSize: 11, 
                                  fontWeight: FontWeight.bold, 
                                  letterSpacing: 1.5
                                ),
                              ),
                              if (_selectedBank != null)
                                GestureDetector(
                                  onTap: () => setState(() => _selectedBank = null),
                                  child: const Text("SHOW ALL", style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 15),
                        ],
                      ),
                    ),
                  ),
                  
                  if (filteredCards.isEmpty)
                    SliverFillRemaining(
                      child: Center(child: Text("No cards in vault", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26))),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
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
                  const SliverToBoxAdapter(child: SizedBox(height: 30)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
