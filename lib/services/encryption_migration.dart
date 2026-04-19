import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import './encryption_service.dart';
import './enhanced_encryption_service.dart';
import '../database/database_helper.dart';
import '../database/database_helper_enhanced.dart';
import '../models/card_model.dart';

/// Utility to migrate from old encryption to new enhanced encryption
class EncryptionMigration {
  /// Check if migration is needed by examining existing data
  static Future<bool> isMigrationNeeded() async {
    try {
      final cards = await DatabaseHelper.instance.getCards();
      if (cards.isEmpty) return false;

      // Check if any card has fields that need re-encryption
      for (final card in cards) {
        // If card has plaintext holder, expiry, bank, or variant fields
        // (these weren't encrypted in old version)
        if (card.holder.isNotEmpty &&
            !card.holder.startsWith('[') &&
            !card.holder.contains(':')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint("Migration check error: $e");
      return false;
    }
  }

  /// Migrate all cards from old encryption to new enhanced encryption
  static Future<void> migrateAllCards() async {
    try {
      debugPrint("Starting encryption migration...");

      final oldCards = await DatabaseHelper.instance.getCards();
      debugPrint("Found ${oldCards.length} cards to migrate");

      // Create enhanced database helper
      final enhancedHelper = DatabaseHelperEnhanced.instance;

      // Migrate each card
      int migratedCount = 0;
      for (final card in oldCards) {
        try {
          // Insert card into enhanced database (will encrypt all fields)
          await enhancedHelper.insertCard(card);
          migratedCount++;

          if (migratedCount % 10 == 0) {
            debugPrint("Migrated $migratedCount cards...");
          }
        } catch (e) {
          debugPrint("Failed to migrate card ${card.id}: $e");
        }
      }

      debugPrint(
        "Migration completed: $migratedCount/${oldCards.length} cards migrated",
      );

      // Verify migration
      final migratedCards = await enhancedHelper.getCards();
      debugPrint("Verified ${migratedCards.length} cards in new database");
    } catch (e) {
      debugPrint("Migration failed: $e");
      rethrow;
    }
  }

  /// Test the new encryption system
  static Future<void> testEncryption() async {
    debugPrint("Testing enhanced encryption...");

    try {
      // Test 1: Basic encryption/decryption
      const testText = "4111111111111111";
      final encrypted = await EnhancedEncryptionService.instance.encryptData(
        testText,
      );
      final decrypted = await EnhancedEncryptionService.instance.decryptData(
        encrypted,
      );

      if (testText == decrypted) {
        debugPrint("✓ Basic encryption test passed");
      } else {
        debugPrint("✗ Basic encryption test failed: $decrypted");
      }

      // Test 2: Different IVs produce different ciphertexts
      const testText2 = "4111111111111111";
      final encrypted1 = await EnhancedEncryptionService.instance.encryptData(
        testText2,
      );
      final encrypted2 = await EnhancedEncryptionService.instance.encryptData(
        testText2,
      );

      if (encrypted1 != encrypted2) {
        debugPrint("✓ Random IV test passed (different ciphertexts)");
      } else {
        debugPrint("✗ Random IV test failed (same ciphertexts)");
      }

      // Test 3: User-specific encryption for Firebase
      await EnhancedEncryptionService.instance.setupUserEncryptionKey(
        "test_password",
        salt: "testsalt12345678",
      );

      const firebaseTestText = "John Doe";
      final firebaseEncrypted = await EnhancedEncryptionService.instance
          .encryptForFirebase(firebaseTestText);

      if (firebaseEncrypted.containsKey('encrypted_data') &&
          firebaseEncrypted.containsKey('iv') &&
          firebaseEncrypted.containsKey('key_id')) {
        debugPrint("✓ Firebase encryption format test passed");

        // Test decryption
        final firebaseDecrypted = await EnhancedEncryptionService.instance
            .decryptFromFirebase(firebaseEncrypted);
        if (firebaseTestText == firebaseDecrypted) {
          debugPrint("✓ Firebase decryption test passed");
        } else {
          debugPrint("✗ Firebase decryption test failed: $firebaseDecrypted");
        }
      } else {
        debugPrint("✗ Firebase encryption format test failed");
      }

      debugPrint("Encryption tests completed");
    } catch (e) {
      debugPrint("Encryption test error: $e");
    }
  }

  /// Get migration status report
  static Future<Map<String, dynamic>> getMigrationReport() async {
    final oldCards = await DatabaseHelper.instance.getCards();
    final needsMigration = await isMigrationNeeded();

    // Check encryption type
    String encryptionType = "Unknown";
    if (oldCards.isNotEmpty) {
      final sampleCard = oldCards.first;
      // Check if number is encrypted (old format)
      if (sampleCard.number.contains(':') &&
          sampleCard.number.split(':').length >= 2) {
        encryptionType = "Enhanced (GCM)";
      } else if (sampleCard.number.isNotEmpty &&
          !sampleCard.number.contains('[')) {
        encryptionType = "Legacy (CBC)";
      } else {
        encryptionType = "Unknown/Plaintext";
      }
    }

    return {
      'total_cards': oldCards.length,
      'needs_migration': needsMigration,
      'current_encryption': encryptionType,
      'recommended_action': needsMigration
          ? 'Run migration to enhanced encryption'
          : 'Encryption is up to date',
    };
  }

  /// Clear all encryption keys (for testing/reset)
  static Future<void> resetEncryption() async {
    debugPrint("Resetting encryption keys...");
    final storage = FlutterSecureStorage();
    await storage.delete(key: 'vault_master_key_v5');
    await storage.delete(key: 'vault_master_key_v6');
    await storage.delete(key: 'vault_key_salt_v1');

    EnhancedEncryptionService.instance.clearUserEncryptionKey();

    debugPrint("Encryption keys reset");
  }
}
