import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../providers/card_provider.dart';
import '../database/database_helper.dart';
import '../models/card_model.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _clearAllData(BuildContext context) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text("Clear All Data"),
        content: const Text("This will permanently delete all your cards. This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete Everything", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final provider = Provider.of<CardProvider>(context, listen: false);
      for (var card in provider.cards) {
        await DatabaseHelper.instance.deleteCard(card.id!);
      }
      provider.refreshCards();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All data cleared")));
    }
  }

  void _exportData(BuildContext context) async {
    final provider = Provider.of<CardProvider>(context, listen: false);
    if (provider.cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export")));
      return;
    }

    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/cardvault_backup.json');
      
      final data = provider.cards.map((c) => c.toMap()).toList();
      await file.writeAsString(jsonEncode(data));

      await Share.shareXFiles([XFile(file.path)], text: 'My CardVault Backup');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Export failed")));
    }
  }

  void _importData(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        List<dynamic> data = jsonDecode(content);

        final provider = Provider.of<CardProvider>(context, listen: false);
        
        int importedCount = 0;
        for (var cardMap in data) {
          // Remove ID to avoid conflicts, let DB generate new IDs
          final map = Map<String, dynamic>.from(cardMap);
          map.remove('id');
          await provider.addCard(CardModel.fromMap(map));
          importedCount++;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully imported $importedCount cards")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Import failed. Ensure the file is a valid CardVault backup.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        children: [
          _buildSectionHeader("Security & Data"),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.blue),
            title: const Text("Export Backup"),
            subtitle: const Text("Save your data to a file"),
            onTap: () => _exportData(context),
          ),
          ListTile(
            leading: const Icon(Icons.upload, color: Colors.green),
            title: const Text("Import Backup"),
            subtitle: const Text("Restore data from a file"),
            onTap: () => _importData(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text("Clear All Data"),
            subtitle: const Text("Permanently delete all cards"),
            onTap: () => _clearAllData(context),
          ),
          const Divider(color: Colors.white10),
          _buildSectionHeader("Appearance"),
          const ListTile(
            leading: Icon(Icons.dark_mode, color: Colors.purple),
            title: Text("Dark Mode"),
            subtitle: Text("Currently always on"),
            trailing: Icon(Icons.check_circle, color: Colors.green, size: 20),
          ),
          const Divider(color: Colors.white10),
          _buildSectionHeader("About"),
          const ListTile(
            leading: Icon(Icons.info_outline, color: Colors.white60),
            title: Text("CardVault v1.0.0"),
            subtitle: Text("Built with Security in Mind"),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
      ),
    );
  }
}
