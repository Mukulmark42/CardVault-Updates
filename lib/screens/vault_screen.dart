import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/card_provider.dart';
import '../models/card_model.dart';
import '../widgets/credit_card_widget.dart';
import 'add_card_screen.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  String _searchQuery = "";

  void showOptions(CardModel card) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF020617) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_shopping_cart, color: Colors.green),
                title: Text("Update Spent Amount", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showUpdateSpentDialog(card);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: Text("Edit Card Details", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddCardScreen(card: card)),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text("Delete Card", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  _confirmDeletion(card);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeletion(CardModel card) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete Card"),
        content: const Text("Are you sure you want to delete this card?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await Provider.of<CardProvider>(context, listen: false).deleteCard(card.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Card deleted")));
      }
    }
  }

  void showUpdateSpentDialog(CardModel card) {
    final controller = TextEditingController(text: card.spent.toString());
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Update Spending"),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Total Spent Amount",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              double? val = double.tryParse(controller.text);
              if (val != null) {
                final updatedCard = card.copyWith(spent: val);
                await Provider.of<CardProvider>(context, listen: false).updateCard(updatedCard);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              }
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.8, -0.6),
            radius: 1.2,
            colors: isDark 
              ? [const Color(0xFF1E293B).withOpacity(0.5), const Color(0xFF020617)]
              : [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Consumer<CardProvider>(
            builder: (context, provider, child) {
              final filteredCards = provider.cards.where((card) {
                final query = _searchQuery.toLowerCase();
                return card.bank.toLowerCase().contains(query) || 
                       card.holder.toLowerCase().contains(query) ||
                       card.variant.toLowerCase().contains(query);
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
                    title: Text(
                      "Virtual Vault",
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            style: TextStyle(color: isDark ? Colors.white : Colors.black),
                            decoration: InputDecoration(
                              hintText: "Search vault...",
                              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black26),
                              prefixIcon: Icon(Icons.search, color: isDark ? Colors.white38 : Colors.black26),
                              filled: true,
                              fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  if (filteredCards.isEmpty)
                    SliverFillRemaining(
                      child: Center(child: Text("No cards found", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26))),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
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
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurpleAccent,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCardScreen())),
      ),
    );
  }
}
