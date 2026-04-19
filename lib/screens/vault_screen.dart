import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/card_provider.dart';
import '../models/card_model.dart';
import '../widgets/credit_card_widget.dart';
import '../services/notification_service.dart';
import 'add_card_screen.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  String _searchQuery = "";
  String? _selectedBank;

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

  void showOptions(CardModel card) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.only(bottom: 32),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A).withOpacity(0.92) : Colors.white.withOpacity(0.94),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Card identifier header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.credit_card_rounded, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.bank.toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            if (card.variant.isNotEmpty)
                              Text(
                                card.variant,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08), height: 1),
                  const SizedBox(height: 8),
                  _buildOptionTile(
                    context: context,
                    icon: Icons.calendar_month_rounded,
                    label: "Update Due Date",
                    color: Colors.orange,
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _selectDueDate(card);
                    },
                  ),
                  _buildOptionTile(
                    context: context,
                    icon: card.isPaid ? Icons.undo_rounded : Icons.check_circle_outline_rounded,
                    label: card.isPaid ? "Mark as Unpaid" : "Mark as Paid",
                    color: const Color(0xFF10B981),
                    isDark: isDark,
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final updatedCard = card.copyWith(isPaid: !card.isPaid);
                      await Provider.of<CardProvider>(context, listen: false).updateCard(updatedCard);
                      if (updatedCard.isPaid) {
                        await NotificationService().cancelNotification(card.id ?? 0);
                      } else {
                        await NotificationService().scheduleDueDateNotification(updatedCard);
                      }
                    },
                  ),
                  _buildOptionTile(
                    context: context,
                    icon: Icons.add_shopping_cart_rounded,
                    label: "Update Spent Amount",
                    color: Colors.teal,
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      showUpdateSpentDialog(card);
                    },
                  ),
                  if (card.linkedEmail != null)
                    _buildOptionTile(
                      context: context,
                      icon: Icons.link_off_rounded,
                      label: "Delink Email (${card.linkedEmail})",
                      color: Colors.amber,
                      isDark: isDark,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await Provider.of<CardProvider>(context, listen: false).delinkEmail(card);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Email delinked from card")),
                          );
                        }
                      },
                    ),
                  _buildOptionTile(
                    context: context,
                    icon: Icons.edit_rounded,
                    label: "Edit Card Details",
                    color: Colors.blueAccent,
                    isDark: isDark,
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AddCardScreen(card: card)),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Divider(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08), height: 1),
                  const SizedBox(height: 4),
                  _buildOptionTile(
                    context: context,
                    icon: Icons.delete_rounded,
                    label: "Delete Card",
                    color: Colors.redAccent,
                    isDark: isDark,
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      _confirmDeletion(card);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: color.withOpacity(0.08),
      highlightColor: color.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          title: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: color == Colors.redAccent
                  ? Colors.redAccent
                  : (isDark ? Colors.white : Colors.black87),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: isDark ? Colors.white.withOpacity(0.16) : Colors.black.withOpacity(0.16),
            size: 20,
          ),
        ),
      ),
    );
  }

  Future<void> _selectDueDate(CardModel card) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: card.dueDate != null ? DateTime.parse(card.dueDate!) : DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF7C3AED),
              onPrimary: Colors.white,
              surface: Color(0xFF0F172A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      final updatedCard = card.copyWith(
        dueDate: () => picked.toIso8601String(),
        isPaid: false,
        isManualDueDate: true,
      );
      await Provider.of<CardProvider>(context, listen: false).updateCard(updatedCard);
      await NotificationService().scheduleDueDateNotification(updatedCard);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Due date updated to ${DateFormat('dd MMM').format(picked)}"),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
    }
  }

  Future<void> _confirmDeletion(CardModel card) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Text("Delete Card", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          "This action cannot be undone. Are you sure you want to permanently delete this card?",
          style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text("Cancel", style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black45)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text("Delete", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await Provider.of<CardProvider>(context, listen: false).deleteCard(card.id!);
      await NotificationService().cancelNotification(card.id ?? 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Card deleted"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void showUpdateSpentDialog(CardModel card) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: card.spent.toString());
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Update Spending", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            labelText: "Total Spent Amount (₹)",
            labelStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            prefixIcon: Icon(Icons.currency_rupee_rounded, size: 18, color: isDark ? Colors.white38 : Colors.black38),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF7C3AED)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text("Cancel", style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black45)),
          ),
          ElevatedButton(
            onPressed: () async {
              String rawText = controller.text.replaceAll(',', '').trim();
              double? val = double.tryParse(rawText);
              if (val != null) {
                final updatedCard = card.copyWith(spent: val);
                await Provider.of<CardProvider>(context, listen: false).updateCard(updatedCard);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text("Update", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
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
                  center: Alignment(0.7, -0.7),
                  radius: 1.4,
                  colors: [Color(0xFF0D1B3E), Color(0xFF020617)],
                )
              : const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFFEEF2FF), Color(0xFFF8FAFF)],
                ),
        ),
        child: SafeArea(
          bottom: false,
          child: Consumer<CardProvider>(
            builder: (context, provider, child) {
              Map<String, int> bankCounts = {};
              for (var card in provider.cards) {
                String shortName = _getAbbreviatedBank(card.bank);
                bankCounts[shortName] = (bankCounts[shortName] ?? 0) + 1;
              }

              List<CardModel> sortedCards = List.from(provider.cards);
              sortedCards.sort((a, b) {
                if (a.dueDate == null && b.dueDate != null) return -1;
                if (a.dueDate != null && b.dueDate == null) return 1;
                return 0;
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
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      "Virtual Vault",
                                      style: GoogleFonts.poppins(
                                        color: isDark ? Colors.white : const Color(0xFF1A1040),
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text("🔐", style: TextStyle(fontSize: 22)),
                                  ],
                                ),
                                Text(
                                  "${provider.cards.length} card${provider.cards.length == 1 ? '' : 's'} stored securely",
                                  style: GoogleFonts.poppins(
                                    color: isDark ? Colors.white38 : Colors.black38,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // ── Add Card button ────────────────────────────
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AddCardScreen()),
                            ),
                            child: Container(
                              height: 44,
                              width: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF7C3AED).withOpacity(0.40),
                                    blurRadius: 14,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        ],
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
                                    hintText: "Search vault…",
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
                                              )
                                            : null,
                                        color: isSelected ? null : bankColor.withOpacity(isDark ? 0.18 : 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: bankColor.withOpacity(isSelected ? 0.0 : 0.4),
                                        ),
                                        boxShadow: isSelected
                                            ? [BoxShadow(color: bankColor.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))]
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
                                              color: isSelected ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.12),
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
                                    _selectedBank == null ? "CARDS" : "$_selectedBank COLLECTION",
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
                      child: Center(
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
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final card = filteredCards[index];
                            return RepaintBoundary(
                              key: ValueKey('vault_${card.id}'),
                              child: GestureDetector(
                                onTap: () => showOptions(card),
                                child: CreditCardWidget(
                                  card: card,
                                  showControls: false,
                                ),
                              ),
                            );
                          },
                          childCount: filteredCards.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

