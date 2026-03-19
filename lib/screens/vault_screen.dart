import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF020617),
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
                title: const Text("Update Spent Amount", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showUpdateSpentDialog(card);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text("Edit Card Details", style: TextStyle(color: Colors.white)),
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
                title: const Text("Delete Card", style: TextStyle(color: Colors.white)),
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
        backgroundColor: const Color(0xFF0F172A),
        title: const Text("Delete Card", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure you want to delete this card?", style: TextStyle(color: Colors.white70)),
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
        backgroundColor: const Color(0xFF0F172A),
        title: const Text("Update Spending", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "Total Spent Amount",
            labelStyle: TextStyle(color: Colors.white60),
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
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        title: const Text("Virtual Vault", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddCardScreen())),
      ),
      body: Consumer<CardProvider>(
        builder: (context, provider, child) {
          final filteredCards = provider.cards.where((card) {
            final query = _searchQuery.toLowerCase();
            return card.bank.toLowerCase().contains(query) || 
                   card.holder.toLowerCase().contains(query) ||
                   card.variant.toLowerCase().contains(query);
          }).toList();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 10),
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Search vault...",
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withAlpha(13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: filteredCards.isEmpty
                    ? const Center(child: Text("No cards found", style: TextStyle(color: Colors.white24)))
                    : ListView.builder(
                        itemCount: filteredCards.length,
                        cacheExtent: 500,
                        padding: const EdgeInsets.only(bottom: 80),
                        itemBuilder: (context, index) {
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
                      ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
