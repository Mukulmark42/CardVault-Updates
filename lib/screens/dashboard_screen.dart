import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/card_provider.dart';
import '../models/card_model.dart';
import '../models/transaction_model.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const Map<String, Color> _categoryColors = {
    'Shopping': Color(0xFF6366F1),
    'Food': Color(0xFF10B981),
    'Travel': Color(0xFFF59E0B),
    'Entertainment': Color(0xFFEC4899),
    'Bills': Color(0xFFEF4444),
    'Health': Color(0xFF06B6D4),
    'Other': Color(0xFF64748B),
  };

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
              final now = DateTime.now();

              // ── Categorise cards ──────────────────────────────────────────
              final overdue = provider.cards.where((c) {
                if (c.isPaid || c.dueDate == null) return false;
                return DateTime.parse(c.dueDate!).isBefore(now);
              }).toList()
                ..sort((a, b) => DateTime.parse(a.dueDate!)
                    .compareTo(DateTime.parse(b.dueDate!)));

              final upcoming = provider.cards.where((c) {
                if (c.isPaid || c.dueDate == null) return false;
                final due = DateTime.parse(c.dueDate!);
                return due.isAfter(now) &&
                    due.isBefore(now.add(const Duration(days: 30)));
              }).toList()
                ..sort((a, b) => DateTime.parse(a.dueDate!)
                    .compareTo(DateTime.parse(b.dueDate!)));

              final paid = provider.cards.where((c) => c.isPaid).toList();

              double totalDue = 0;
              for (var c in provider.cards) {
                if (!c.isPaid) totalDue += c.spent;
              }

              // ── This month's transactions ─────────────────────────────────
              final monthStart = DateTime(now.year, now.month, 1);
              final thisMonthTxs = provider.transactions
                  .where((tx) => !tx.date.isBefore(monthStart))
                  .toList();
              final totalTxThisMonth =
                  thisMonthTxs.fold(0.0, (s, tx) => s + tx.amount);
              final txCountThisMonth = thisMonthTxs.length;

              // ── Spending by category ─────────────────────────────────────
              final Map<String, double> spending = {};
              for (var tx in provider.transactions) {
                spending[tx.category] = (spending[tx.category] ?? 0) + tx.amount;
              }

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // App bar
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    pinned: true,
                    title: Text(
                      'Analytics Dashboard',
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(
                          provider.isSyncing ? Icons.sync : Icons.refresh_rounded,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: provider.isSyncing
                            ? null
                            : () => provider.syncWithGmail(),
                      ),
                    ],
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Summary cards (Outstanding + This Month) ─────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildOutstandingCard(
                                  context,
                                  totalDue: totalDue,
                                  unpaid: overdue.length + upcoming.length,
                                  overdue: overdue.length,
                                  paid: paid.length,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildThisMonthCard(
                                  context,
                                  total: totalTxThisMonth,
                                  count: txCountThisMonth,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // ── Spending pie chart ────────────────────────────
                          if (spending.isNotEmpty) ...[
                            _sectionTitle(context, 'SPENDING BY CATEGORY'),
                            const SizedBox(height: 12),
                            _buildPieChart(context, spending, isDark),
                            const SizedBox(height: 28),
                          ],

                          // ── Overdue bills ─────────────────────────────────
                          if (overdue.isNotEmpty) ...[
                            _sectionTitle(context, '🔴 OVERDUE'),
                            const SizedBox(height: 10),
                            ...overdue.map((c) => _buildBillItem(context, c, BillStatus.overdue)),
                            const SizedBox(height: 24),
                          ],

                          // ── Upcoming bills ────────────────────────────────
                          if (upcoming.isNotEmpty) ...[
                            _sectionTitle(context, '🟡 UPCOMING'),
                            const SizedBox(height: 10),
                            ...upcoming.map((c) => _buildBillItem(context, c, BillStatus.upcoming)),
                            const SizedBox(height: 24),
                          ],

                          // ── Paid ──────────────────────────────────────────
                          if (paid.isNotEmpty) ...[
                            _sectionTitle(context, '✅ SETTLED THIS CYCLE'),
                            const SizedBox(height: 10),
                            ...paid.map((c) => _buildBillItem(context, c, BillStatus.paid)),
                            const SizedBox(height: 24),
                          ],

                          if (overdue.isEmpty && upcoming.isEmpty && paid.isEmpty)
                            _buildEmptyBills(isDark),

                          // ── Recent Transactions ───────────────────────────
                          _sectionTitle(context, 'RECENT TRANSACTIONS'),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),

                  // Transactions list
                  _buildTransactionsList(context, provider.transactions),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────────

  Widget _sectionTitle(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: GoogleFonts.poppins(
        color: isDark ? Colors.white38 : Colors.black38,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.4,
      ),
    );
  }

  // ── Outstanding card ─────────────────────────────────────────────────────────

  Widget _buildOutstandingCard(
    BuildContext context, {
    required double totalDue,
    required int unpaid,
    required int overdue,
    required int paid,
  }) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_outlined,
                color: Colors.white60, size: 13),
            const SizedBox(width: 5),
            Text('OUTSTANDING',
                style: GoogleFonts.poppins(
                    color: Colors.white60,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1)),
          ]),
          const SizedBox(height: 8),
          Text(
            fmt.format(totalDue),
            style: GoogleFonts.robotoMono(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _miniChip('$unpaid UNPAID', Colors.orangeAccent),
          const SizedBox(height: 5),
          if (overdue > 0) ...[
            _miniChip('$overdue OVERDUE', Colors.redAccent),
            const SizedBox(height: 5),
          ],
          _miniChip('$paid SETTLED', Colors.greenAccent),
        ],
      ),
    );
  }

  // ── This Month card ───────────────────────────────────────────────────────────

  Widget _buildThisMonthCard(
    BuildContext context, {
    required double total,
    required int count,
  }) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final monthName = DateFormat('MMM yyyy').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF14B8A6), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14B8A6).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, color: Colors.white60, size: 13),
            const SizedBox(width: 5),
            Flexible(
              child: Text('TRANSACTIONS',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      color: Colors.white60,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            fmt.format(total),
            style: GoogleFonts.robotoMono(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _miniChip('$count THIS MONTH', const Color(0xFFA7F3D0)),
          const SizedBox(height: 5),
          _miniChip(monthName.toUpperCase(), Colors.white.withValues(alpha: 0.55)),
        ],
      ),
    );
  }

  // ── Mini chip helper ──────────────────────────────────────────────────────────

  Widget _miniChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                color: color, fontSize: 9.5, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildBillItem(BuildContext context, CardModel card, BillStatus status) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    DateTime? due = card.dueDate != null ? DateTime.tryParse(card.dueDate!) : null;
    final dateStr = due != null ? DateFormat('dd MMM').format(due) : 'No date';

    final color = status == BillStatus.overdue
        ? Colors.redAccent
        : status == BillStatus.upcoming
            ? Colors.orangeAccent
            : Colors.greenAccent;

    final icon = status == BillStatus.overdue
        ? Icons.warning_amber_rounded
        : status == BillStatus.upcoming
            ? Icons.schedule_rounded
            : Icons.check_circle_outline_rounded;

    // Days overdue or until due
    String daysLabel = '';
    if (due != null && status != BillStatus.paid) {
      final diff = due.difference(DateTime.now()).inDays;
      if (status == BillStatus.overdue) {
        daysLabel = '${diff.abs()}d overdue';
      } else if (diff == 0) {
        daysLabel = 'Due today';
      } else {
        daysLabel = 'in ${diff}d';
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                card.bank,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                card.holder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
              Text(
                '•••• ${card.last4 ?? (card.number.length >= 4 ? card.number.substring(card.number.length - 4) : "")}',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Text('Due: $dateStr',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12)),
                if (daysLabel.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(daysLabel,
                        style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            color: color,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmt.format(card.spent),
                  style: GoogleFonts.robotoMono(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              if (status != BillStatus.paid) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 30,
                  child: ElevatedButton(
                    onPressed: () {
                      final provider = Provider.of<CardProvider>(context, listen: false);
                      provider.updateCard(card.copyWith(isPaid: true));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: Text('PAID', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBills(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text('No bills yet. Sync with Gmail to fetch them.',
            style: TextStyle(
                color: isDark ? Colors.white24 : Colors.black26, fontSize: 13)),
      ),
    );
  }

  // ── Pie Chart ─────────────────────────────────────────────────────────────────

  Widget _buildPieChart(
      BuildContext context, Map<String, double> spending, bool isDark) {
    final total = spending.values.fold(0.0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    final sortedEntries = spending.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Build pie slices
    final List<_PieSlice> slices = [];
    double startAngle = -math.pi / 2;
    for (final entry in sortedEntries) {
      final sweep = (entry.value / total) * 2 * math.pi;
      final color = _categoryColors[entry.key] ?? const Color(0xFF64748B);
      slices.add(_PieSlice(
        color: color,
        startAngle: startAngle,
        sweepAngle: sweep,
        label: entry.key,
        value: entry.value,
      ));
      startAngle += sweep;
    }

    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          // Donut chart
          SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: _DonutChartPainter(slices: slices),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('TOTAL',
                        style: GoogleFonts.poppins(
                            fontSize: 8,
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontWeight: FontWeight.bold)),
                    Text(fmt.format(total),
                        style: GoogleFonts.robotoMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Legend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: slices.take(5).map((s) {
                final pct = (s.value / total * 100).toStringAsFixed(0);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: s.color,
                            borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.label,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : Colors.black87)),
                    ),
                    Text('$pct%',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: s.color)),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Transactions list ─────────────────────────────────────────────────────────

  Widget _buildTransactionsList(
      BuildContext context, List<TransactionModel> txs) {
    if (txs.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
              child: Text('No transactions found. Sync Gmail to fetch them.',
                  style: TextStyle(color: Colors.grey))),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildTransactionItem(context, txs[index]),
        childCount: txs.length,
      ),
    );
  }

  Widget _buildTransactionItem(BuildContext context, TransactionModel tx) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _categoryColors[tx.category] ?? const Color(0xFF64748B);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(_getCategoryIcon(tx.category), color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx.vendor,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text('${tx.bank} • ${tx.formattedDate}',
                style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ]),
        ),
        Text(fmt.format(tx.amount),
            style: GoogleFonts.robotoMono(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.redAccent.shade100)),
      ]),
    );
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Shopping': return Icons.shopping_bag_outlined;
      case 'Food': return Icons.restaurant_outlined;
      case 'Travel': return Icons.directions_car_outlined;
      case 'Entertainment': return Icons.movie_outlined;
      case 'Bills': return Icons.receipt_long_outlined;
      case 'Health': return Icons.local_hospital_outlined;
      default: return Icons.credit_card_outlined;
    }
  }
}

// ── Supporting types ──────────────────────────────────────────────────────────

enum BillStatus { overdue, upcoming, paid }

class _PieSlice {
  final Color color;
  final double startAngle;
  final double sweepAngle;
  final String label;
  final double value;
  const _PieSlice({
    required this.color,
    required this.startAngle,
    required this.sweepAngle,
    required this.label,
    required this.value,
  });
}

class _DonutChartPainter extends CustomPainter {
  final List<_PieSlice> slices;
  const _DonutChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 4;
    final innerR = outerR * 0.58;

    for (final s in slices) {
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = (outerR - innerR)
        ..strokeCap = StrokeCap.butt;

      // Draw arc at mid-radius
      final midR = (outerR + innerR) / 2;
      final arcRect = Rect.fromCircle(center: center, radius: midR);
      canvas.drawArc(arcRect, s.startAngle, s.sweepAngle - 0.03, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DonutChartPainter old) => old.slices != slices;
}
