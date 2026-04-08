import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/transaction_model.dart';
import '../database/database_helper.dart';
import 'transaction_service.dart';
import 'notification_service.dart';
import 'pdf_parser_service.dart';

class GmailService {
  static final GmailService instance = GmailService._internal();
  GmailService._internal();

  // Primary GoogleSignIn instance (for the main linked account)
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '570240799272-rqor298og17tegpvlblinnipta58gvqe.apps.googleusercontent.com',
    scopes: [GmailApi.gmailReadonlyScope],
  );

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ─── Validation helpers ──────────────────────────────────────────────────────

  /// Validates a bill amount for reasonableness.
  /// Returns true if the amount passes all validation checks.
  bool _validateBillAmount(double amount, String bank) {
    // Minimum amount already checked (≥ ₹10)
    if (amount < 10) return false;

    // Bank-specific maximum limits (in rupees)
    final bankMaxLimits = {
      'HDFC': 500000.0, // Typical HDFC card limit
      'ICICI': 1000000.0, // ICICI often has higher limits
      'Axis': 750000.0,
      'SBI': 500000.0,
      'IDFC': 300000.0,
      'Kotak': 500000.0,
      'Standard Chartered': 1000000.0,
      'Yes Bank': 300000.0,
      'Citibank': 1000000.0,
      'RBL': 300000.0,
    };

    // Get bank-specific limit or use default
    final bankKey = bank.toLowerCase();
    double maxLimit = 1000000.0; // Default 1 million
    for (final entry in bankMaxLimits.entries) {
      if (bankKey.contains(entry.key.toLowerCase())) {
        maxLimit = entry.value;
        break;
      }
    }

    // Maximum reasonable bill amount
    if (amount > maxLimit) {
      debugPrint(
        '⚠️ $bank: Bill amount ₹$amount exceeds bank-specific limit (₹${maxLimit.toInt()})',
      );
      return false;
    }

    // Check for unrealistic amounts that might be phone numbers or IDs
    // (e.g., ₹9,215,676,766 which has 10+ digits)
    final amountStr = amount.toStringAsFixed(0);
    if (amountStr.length > 9) {
      // Over 1 billion rupees - unrealistic for credit card bills
      debugPrint(
        '⚠️ $bank: Bill amount ₹$amount has ${amountStr.length} digits - likely a phone number/ID',
      );
      return false;
    }

    // Check for suspicious round numbers that might be false positives
    // (e.g., ₹1000, ₹5000 are common in marketing emails)
    final rounded = amount.round();
    final commonMarketingAmounts = [1000, 2000, 5000, 10000, 500, 100, 50];
    if (commonMarketingAmounts.contains(rounded) && rounded <= 10000) {
      // Common marketing amounts: ₹1000, ₹2000, ₹5000, ₹10000
      // These could be cashback offers or rewards, not actual bills
      debugPrint(
        '⚠️ $bank: Bill amount ₹$amount matches common marketing amount - may be false positive',
      );
      // Don't reject outright, but log strong warning
    }

    // Check for suspiciously perfect round numbers (multiples of 1000 above 10k)
    if (rounded % 1000 == 0 && rounded > 10000) {
      debugPrint(
        'ℹ️ $bank: Bill amount ₹$amount is a large round number (₹${rounded ~/ 1000}k)',
      );
    }

    // Check for typical bill amounts (multiples of 100 or 500 are common)
    // This is just informational
    if (amount % 100 == 0 || amount % 500 == 0) {
      debugPrint('ℹ️ $bank: Bill amount ₹$amount is a typical round amount');
    }

    // Additional validation: check if amount looks like a concatenated number
    // (e.g., 123456789 which is too sequential)
    if (_looksLikeConcatenatedNumber(amountStr)) {
      debugPrint(
        '⚠️ $bank: Bill amount ₹$amount looks like a concatenated number (phone/ID)',
      );
      return false;
    }

    return true;
  }

  /// Checks if a number string looks like a concatenated phone number or ID.
  /// Returns true if it has repeating patterns or is too sequential.
  bool _looksLikeConcatenatedNumber(String numStr) {
    if (numStr.length < 8) return false;

    // Check for repeating digits (e.g., 11111111, 12341234)
    final repeatingPattern = RegExp(r'^(\d{3,})\1+$');
    if (repeatingPattern.hasMatch(numStr)) {
      return true;
    }

    // Check for sequential digits (e.g., 12345678, 98765432)
    bool allSequential = true;
    bool allReverseSequential = true;
    for (int i = 1; i < numStr.length; i++) {
      final current = int.parse(numStr[i]);
      final prev = int.parse(numStr[i - 1]);
      if (current != prev + 1) allSequential = false;
      if (current != prev - 1) allReverseSequential = false;
      if (!allSequential && !allReverseSequential) break;
    }
    if (allSequential || allReverseSequential) {
      return true;
    }

    // Check for common Indian phone number patterns (starts with 7,8,9)
    if (numStr.length == 10 && ['7', '8', '9'].contains(numStr[0])) {
      // Could be a phone number
      return true;
    }

    return false;
  }

  /// Validates a transaction amount for reasonableness.
  /// Returns true if the amount passes all validation checks.
  bool _validateTransactionAmount(double amount, String vendor) {
    // Minimum amount already checked (≥ ₹1)
    if (amount < 1) return false;

    // Maximum reasonable transaction amount: ₹500,000
    if (amount > 500000) {
      debugPrint(
        '⚠️ Transaction at $vendor: Amount ₹$amount exceeds maximum limit (₹500,000)',
      );
      return false;
    }

    // Check for unrealistic amounts that might be phone numbers or IDs
    final amountStr = amount.toStringAsFixed(0);
    if (amountStr.length > 8) {
      // Over 100 million rupees - unrealistic for single transactions
      debugPrint(
        '⚠️ Transaction at $vendor: Amount ₹$amount has ${amountStr.length} digits - likely a phone number/ID',
      );
      return false;
    }

    // Check if amount looks like a concatenated number (phone/ID)
    if (_looksLikeConcatenatedNumber(amountStr)) {
      debugPrint(
        '⚠️ Transaction at $vendor: Amount ₹$amount looks like concatenated number',
      );
      return false;
    }

    // Check for suspiciously small amounts that might be fees or false positives
    if (amount < 10) {
      // Very small transactions could be bank fees or test transactions
      debugPrint(
        '⚠️ Transaction at $vendor: Amount ₹$amount is very small (could be fee/test)',
      );
      // Still allow it, just log warning
    }

    // Enhanced common false positive amounts (including marketing amounts)
    final commonFalseAmounts = [
      1.0,
      2.0,
      5.0,
      10.0,
      20.0,
      50.0,
      100.0,
      200.0,
      500.0,
      1000.0,
      2000.0,
      5000.0,
      10000.0,
    ];
    if (commonFalseAmounts.contains(amount)) {
      debugPrint(
        '⚠️ Transaction at $vendor: Amount ₹$amount is a common false positive/marketing amount',
      );
      // Don't reject outright, but be cautious
    }

    // Check for suspicious round numbers (multiples of 1000 above 1000)
    final rounded = amount.round();
    if (rounded % 1000 == 0 && rounded >= 1000 && rounded <= 10000) {
      debugPrint(
        '⚠️ Transaction at $vendor: Amount ₹$amount is a suspicious round number (common in marketing)',
      );
    }

    // Check for amounts ending with .00 or .99 (common pricing patterns)
    if (amount.toString().endsWith('.00') ||
        amount.toString().endsWith('.99')) {
      debugPrint(
        'ℹ️ Transaction at $vendor: Amount ₹$amount has common pricing pattern',
      );
    }

    // Additional validation: check if amount is too perfect (e.g., 1234.56)
    // This is often a test amount
    final decimalPart = amount - amount.truncate();
    if (decimalPart == 0.56 || decimalPart == 0.78 || decimalPart == 0.12) {
      debugPrint(
        '⚠️ Transaction at $vendor: Amount ₹$amount has suspicious decimal pattern',
      );
    }

    return true;
  }

  /// Validates a due date for reasonableness.
  /// Returns true if the date passes all validation checks.
  bool _validateDueDate(DateTime? dueDate, String bank) {
    if (dueDate == null) {
      // Bills without due dates are acceptable (some banks don't specify)
      return true;
    }

    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final sixMonthsFuture = now.add(const Duration(days: 180));

    // Due date should not be too far in the past (more than 30 days)
    if (dueDate.isBefore(thirtyDaysAgo)) {
      debugPrint(
        '⚠️ $bank: Due date $dueDate is more than 30 days in the past',
      );
      return false;
    }

    // Due date should not be too far in the future (more than 6 months)
    if (dueDate.isAfter(sixMonthsFuture)) {
      debugPrint(
        '⚠️ $bank: Due date $dueDate is more than 6 months in the future',
      );
      return false;
    }

    // Due date should generally be in the future (but allow up to 7 days past due)
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    if (dueDate.isBefore(sevenDaysAgo)) {
      debugPrint('⚠️ $bank: Due date $dueDate is more than 7 days overdue');
      // Still allow it (might be processing old emails)
    }

    return true;
  }

  /// Validates a transaction date for reasonableness.
  /// Returns true if the date passes all validation checks.
  bool _validateTransactionDate(DateTime? txDate, String vendor) {
    if (txDate == null) {
      // Transactions without dates are acceptable (will use email date)
      return true;
    }

    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final oneDayFuture = now.add(const Duration(days: 1));

    // Transaction date should not be too far in the past (more than 30 days)
    if (txDate.isBefore(thirtyDaysAgo)) {
      debugPrint(
        '⚠️ Transaction at $vendor: Date $txDate is more than 30 days in the past',
      );
      return false;
    }

    // Transaction date should not be in the future (except maybe 1 day for timezone issues)
    if (txDate.isAfter(oneDayFuture)) {
      debugPrint('⚠️ Transaction at $vendor: Date $txDate is in the future');
      return false;
    }

    return true;
  }

  /// Validates a vendor name for transaction.
  /// Returns true if the vendor passes all validation checks.
  bool _validateVendorName(String vendor) {
    final lowerVendor = vendor.toLowerCase();

    // Already filtered month names, dates, etc. in transaction parsing
    // Add more comprehensive filtering

    // Enhanced common false positive vendor patterns
    final falsePatterns = [
      r'^\d+$', // Pure numbers
      r'^\d+[a-z]*$', // Numbers with letters
      r'^[a-z]\d+$', // Letter followed by numbers
      r'\d{1,2}(?:st|nd|rd|th)?\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)', // Date patterns
      r'(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}', // Month date patterns
      r'\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}', // Date format DD/MM/YYYY
      r'card$', // Ends with "card"
      r'bank$', // Ends with "bank"
      r'payment$', // Ends with "payment"
      r'transaction$', // Ends with "transaction"
      r'upi$', // UPI
      r'alert$', // Alert
      r'notification$', // Notification
      r'info$', // Info
      r'date$', // Date
      r'time$', // Time
      r'amount$', // Amount
      r'rs\.', // Rs.
      r'₹', // ₹ symbol
      r'inr', // INR
      r'debit$', // Debit
      r'credit$', // Credit
      r'charge$', // Charge
      r'spent$', // Spent
      r'at$', // "at" (common in "spent at")
      r'to$', // "to" (common in "paid to")
      r'on$', // "on" (common in "transaction on")
      r'for$', // "for" (common in "payment for")
      r'your$', // Your
      r'has$', // Has
      r'been$', // Been
      r'successful$', // Successful
      r'failed$', // Failed
      r'declined$', // Declined
      r'approved$', // Approved
      r'with$', // With
      r'via$', // Via
      r'using$', // Using
      r'through$', // Through
    ];

    for (final pattern in falsePatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lowerVendor)) {
        debugPrint(
          '⚠️ Vendor "$vendor" matches false positive pattern: $pattern',
        );
        return false;
      }
    }

    // Check for vendor names that are too short (after removing common suffixes)
    final cleanVendor = vendor.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (cleanVendor.length < 3) {
      debugPrint('⚠️ Vendor "$vendor" is too short after cleaning');
      return false;
    }

    // Check for vendor names that are too long (likely concatenated text)
    if (vendor.length > 50) {
      debugPrint('⚠️ Vendor "$vendor" is too long (${vendor.length} chars)');
      return false;
    }

    // Check for vendor names that are too short even before cleaning
    if (vendor.trim().length < 2) {
      debugPrint('⚠️ Vendor "$vendor" is too short');
      return false;
    }

    // Check for vendor names that contain only common English stop words
    final stopWords = [
      'the',
      'a',
      'an',
      'and',
      'or',
      'but',
      'in',
      'on',
      'at',
      'to',
      'for',
      'of',
      'with',
      'by',
      'is',
      'was',
      'are',
      'were',
      'be',
      'been',
      'being',
      'have',
      'has',
      'had',
      'do',
      'does',
      'did',
      'will',
      'would',
      'shall',
      'should',
      'may',
      'might',
      'must',
      'can',
      'could',
    ];
    final words = vendor.toLowerCase().split(RegExp(r'[^a-zA-Z0-9]+'));
    if (words.length == 1 && stopWords.contains(words[0])) {
      debugPrint('⚠️ Vendor "$vendor" is a common stop word');
      return false;
    }

    // Check for vendor names that are too similar to common bank names
    final commonBanks = [
      'hdfc',
      'icici',
      'axis',
      'sbi',
      'idfc',
      'kotak',
      'standard chartered',
      'yes bank',
      'citibank',
      'rbl',
      'indusind',
      'federal',
      'bank of baroda',
      'pnb',
      'canara',
      'union bank',
    ];
    for (final bank in commonBanks) {
      if (lowerVendor.contains(bank) && lowerVendor.length < 10) {
        debugPrint('⚠️ Vendor "$vendor" contains bank name "$bank"');
        return false;
      }
    }

    // Check for vendor names that are all uppercase (might be transaction codes)
    if (vendor == vendor.toUpperCase() && vendor.length <= 8) {
      debugPrint(
        '⚠️ Vendor "$vendor" is all uppercase and short (might be code)',
      );
      // Don't reject outright, just warn
    }

    return true;
  }

  // ─── Auth ────────────────────────────────────────────────────────────────────

  Future<GoogleSignInAccount?> signIn() async {
    try {
      await _googleSignIn.signOut();
      return await _googleSignIn.signIn();
    } catch (e) {
      debugPrint('Error signing in: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  // ─── Sync entry points ───────────────────────────────────────────────────────

  /// Syncs ALL email accounts stored in the local DB.
  ///
  /// **Background mode** (`isManual = false`): Uses silent sign-in to get
  /// whichever account the OS has cached. Syncs only that account.
  /// (google_sign_in cannot silently switch between accounts — this is an
  /// OS-level limitation.)
  ///
  /// **Manual mode** (`isManual = true`): Signs out completely before each
  /// account and prompts the user to sign in fresh (clean token, full scopes).
  /// This guarantees the correct access token for every linked account.
  Future<void> syncAllLinkedAccounts({bool isManual = false}) async {
    final storedAccounts = await DatabaseHelper.instance.getEmailAccounts();

    if (storedAccounts.isEmpty) {
      debugPrint(
        '📭 No linked email accounts. Trying currently signed-in account...',
      );
      await syncAllAccounts(isManual: isManual);
      return;
    }

    if (!isManual) {
      // ── Background: only sync whichever account the OS has cached ──────────
      debugPrint(
        '🔄 Background sync: checking for silently signed-in account...',
      );
      final current = await _googleSignIn.signInSilently();
      if (current == null) {
        debugPrint(
          '⏭️ No account cached for silent sign-in. Skipping background sync.',
        );
        return;
      }
      final isLinked = storedAccounts.any((a) => a['email'] == current.email);
      if (isLinked) {
        debugPrint('🔄 Background syncing: ${current.email}');
        await syncEmails(current.email);
      } else {
        debugPrint(
          '⏭️ Silently signed-in account (${current.email}) has no linked cards. Skipping.',
        );
      }
      return;
    }

    // ── Manual: sign out → sign in fresh for EACH account ────────────────────
    debugPrint('🔄 Manual sync: ${storedAccounts.length} account(s) queued');

    for (int i = 0; i < storedAccounts.length; i++) {
      final email = storedAccounts[i]['email'] as String?;
      if (email == null) continue;

      try {
        debugPrint('\n── Account ${i + 1}/${storedAccounts.length}: $email ──');

        // Sign out completely to clear any existing token
        await _googleSignIn.signOut();
        await Future.delayed(const Duration(milliseconds: 400));

        // Fresh sign-in — user picks account from the OS picker
        debugPrint('🔐 Please select: $email');
        final signedIn = await _googleSignIn.signIn();

        if (signedIn == null) {
          debugPrint('⏭️ Sign-in cancelled for $email. Skipping.');
          continue;
        }

        if (signedIn.email != email) {
          debugPrint('⚠️ Selected ${signedIn.email} instead of $email.');
          debugPrint(
            '   Will sync ${signedIn.email} — its linked cards will be updated.',
          );
        }

        await syncEmails(signedIn.email, isManual: true);
      } catch (e) {
        debugPrint('❌ Failed syncing $email: $e');
      }
    }

    debugPrint('\n✅ All accounts processed.');
  }

  /// Legacy method — syncs only the current primary Google account.
  /// Kept for backward compat. Use syncAllLinkedAccounts() instead.
  Future<void> syncAllAccounts({bool isManual = false}) async {
    GoogleSignInAccount? currentUser = await _googleSignIn.signInSilently();

    if (currentUser == null) {
      if (isManual) {
        debugPrint('Silent sign-in failed. Attempting interactive...');
        currentUser = await _googleSignIn.signIn();
      } else {
        debugPrint('No account signed in. Skipping sync.');
        return;
      }
    }

    if (currentUser != null) {
      await syncEmails(currentUser.email, isManual: isManual);
    }
  }

  Future<void> syncEmails(
    String email, {
    bool isRetry = false,
    bool isManual = false,
  }) async {
    try {
      // Use whoever is currently signed-in — the caller is responsible for
      // ensuring the right account was signed in before calling this.
      final account = _googleSignIn.currentUser;
      if (account == null) {
        debugPrint(
          '⏭️ syncEmails($email): no account currently signed in. Aborting.',
        );
        return;
      }

      // If the signed-in account doesn't match, log it but proceed using
      // the signed-in account's token (avoids Access Denied from token mismatch).
      final activeEmail = account.email;
      if (activeEmail != email) {
        debugPrint(
          '⚠️ syncEmails: expected $email but signed in as $activeEmail.'
          ' Using $activeEmail (token must match the signed-in account).',
        );
      }
      // Force a fresh access token — critical after multiple sign-out/sign-in
      // cycles, otherwise authenticatedClient() may use a stale cached token
      // and return invalid_token (403) for the 3rd+ account.
      try {
        await account.authentication;
      } catch (e) {
        debugPrint('❌ Token refresh failed for $activeEmail: $e');
        return;
      }

      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) {
        debugPrint(
          '❌ Could not get authenticated client for $activeEmail. Aborting.',
        );
        return;
      }

      final gmailApi = GmailApi(authClient);
      final allCards = await DatabaseHelper.instance.getCards();
      // Use activeEmail (the real signed-in account) to find linked cards
      // — ensures we scan the inbox that matches the OAuth token
      final linkedCards = allCards
          .where((c) => c.linkedEmail == activeEmail)
          .toList();

      if (linkedCards.isEmpty) {
        debugPrint('📭 No cards linked to $activeEmail. Skipping.');
        return;
      }

      // Pre-fetch profiles for PDF password candidates (used in bill processing)
      final profiles = await DatabaseHelper.instance.getProfiles();

      debugPrint(
        '🔍 Scanning Gmail for $activeEmail (${linkedCards.length} linked card(s))...',
      );

      // Broader query to catch Indian bank emails
      const query =
          'subject:(statement OR "payment due" OR "amount due" OR transaction OR alert OR '
          '"spent on" OR "purchase" OR "credit card" OR "debit card" OR recharge OR bill)';

      final messagesResponse = await gmailApi.users.messages.list(
        'me',
        q: query,
        maxResults: 50,
      );

      if (messagesResponse.messages == null ||
          messagesResponse.messages!.isEmpty) {
        debugPrint('📭 No messages found matching the query for $email.');

        // Update last sync time
        await DatabaseHelper.instance.updateEmailAccountSyncTime(email);
        return;
      }

      final user = _auth.currentUser;
      if (user == null) return;

      int processedCount = 0;
      for (var messageSummary in messagesResponse.messages!) {
        final String messageId = messageSummary.id!;

        final docRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('processed_emails')
            .doc(messageId);

        final doc = await docRef.get();
        if (doc.exists) continue;

        // Step 1: Use snippet from list response for initial filtering
        // This avoids downloading the full message for obviously irrelevant emails
        final listSnippet = _decodeHtmlEntities(messageSummary.snippet ?? '');
        final lowerSnippet = listSnippet.toLowerCase();

        // Quick check: if snippet contains reward/offer keywords, skip entirely
        final bool isRewardOrOfferSnippet =
            lowerSnippet.contains('reward') ||
            lowerSnippet.contains('offer') ||
            lowerSnippet.contains('cashback') ||
            lowerSnippet.contains('discount') ||
            lowerSnippet.contains('activation') ||
            lowerSnippet.contains('welcome') ||
            lowerSnippet.contains('bonus') ||
            lowerSnippet.contains('points') ||
            lowerSnippet.contains('voucher') ||
            lowerSnippet.contains('coupon') ||
            lowerSnippet.contains('promo') ||
            lowerSnippet.contains('referral') ||
            lowerSnippet.contains('thank you for applying') ||
            lowerSnippet.contains('your application') ||
            lowerSnippet.contains('card dispatched') ||
            lowerSnippet.contains('card delivered');

        if (isRewardOrOfferSnippet) {
          debugPrint('🎁 Reward/offer email skipped based on snippet.');
          await docRef.set({
            'processedAt': FieldValue.serverTimestamp(),
            'email': email,
            'type': 'skip',
          });
          continue;
        }

        // Download full message for detailed parsing
        final message = await gmailApi.users.messages.get('me', messageId);
        final snippet = _decodeHtmlEntities(message.snippet ?? '');
        final body = _getDecodedBody(message) ?? snippet;
        final internalDate = DateTime.fromMillisecondsSinceEpoch(
          int.parse(message.internalDate ?? '0'),
        );

        debugPrint(
          '📝 Analyzing: "${snippet.length > 100 ? snippet.substring(0, 100) : snippet}"',
        );

        final lowerBody = body.toLowerCase();

        // ── Priority 0: Payment confirmation (highest priority) ────────────────
        // If this is a payment receipt, mark the card as paid and skip further
        // processing — no need to parse a bill amount from a payment confirmation.
        bool isPayment =
            lowerBody.contains('payment received') ||
            lowerBody.contains('payment successful') ||
            lowerBody.contains('payment confirmed') ||
            lowerBody.contains('payment credited') ||
            lowerBody.contains('successfully paid') ||
            lowerBody.contains('your payment of') ||
            lowerBody.contains('payment of ₹') ||
            lowerBody.contains('payment done') ||
            lowerBody.contains('amount credited') ||
            lowerBody.contains('payment posted') ||
            lowerBody.contains('bill paid') ||
            lowerBody.contains('auto debit success') ||
            lowerBody.contains('auto-debit') ||
            lowerBody.contains('emi paid') ||
            lowerBody.contains('settled successfully') ||
            lowerBody.contains('has been refunded') ||
            lowerBody.contains('refund credited') ||
            lowerBody.contains('refund of') ||
            lowerBody.contains('amount refunded');

        // ── Priority 0.2: Reward, offer, activation emails (skip entirely) ─────
        bool isRewardOrOffer =
            lowerBody.contains('reward') ||
            lowerBody.contains('offer') ||
            lowerBody.contains('cashback') ||
            lowerBody.contains('discount') ||
            lowerBody.contains('activation') ||
            lowerBody.contains('welcome') ||
            lowerBody.contains('bonus') ||
            lowerBody.contains('points') ||
            lowerBody.contains('voucher') ||
            lowerBody.contains('coupon') ||
            lowerBody.contains('promo') ||
            lowerBody.contains('referral') ||
            lowerBody.contains('thank you for applying') ||
            lowerBody.contains('your application') ||
            lowerBody.contains('card dispatched') ||
            lowerBody.contains('card delivered');

        // ── Priority 0.5: Debit transaction (overrides isBill) ────────────────
        // e.g. "Rs.22134.00 is debited from your HDFC Bank Credit Card"
        // These alerts typically contain "outstanding" in the footer which
        // would otherwise trigger a false-positive isBill classification.
        bool isDebitTransaction =
            !isPayment &&
            !isRewardOrOffer &&
            (lowerBody.contains('is debited from your') ||
                lowerBody.contains('has been debited from your') ||
                lowerBody.contains('spent on your credit card') ||
                lowerBody.contains('spent on your') &&
                    lowerBody.contains('credit card') ||
                lowerBody.contains('transaction alert') ||
                lowerBody.contains('transaction on your card') ||
                lowerBody.contains('purchase of') ||
                lowerBody.contains('used at') ||
                lowerBody.contains('charged to') ||
                lowerBody.contains('payment to') ||
                (lowerBody.contains('transaction of') &&
                    !lowerBody.contains('total amount due') &&
                    !lowerBody.contains('payment due')));

        // ── Priority 1: Bill classification ───────────────────────────────────
        // Debit transaction emails are excluded — they often have 'outstanding'
        // in the footer which would falsely match the bill keywords.
        bool isBill =
            !isPayment &&
            !isRewardOrOffer &&
            !isDebitTransaction &&
            (lowerBody.contains('statement') ||
                lowerBody.contains('amount due') ||
                lowerBody.contains('bill summary') ||
                lowerBody.contains('payment due') ||
                lowerBody.contains('total due') ||
                lowerBody.contains('bill amount') ||
                lowerBody.contains(
                  'credit card bill',
                ) || // e.g. "your Credit Card bill of Rs 340 is due"
                lowerBody.contains('minimum amount due') ||
                lowerBody.contains('total amount due') ||
                lowerBody.contains('outstanding amount') ||
                lowerBody.contains('current outstanding') ||
                lowerBody.contains('please find enclosed') ||
                lowerBody.contains('e-statement') ||
                lowerBody.contains('billing date'));

        // ── Skip reward/offer/activation emails entirely ──────────────────────
        if (isRewardOrOffer) {
          debugPrint('🎁 Reward/offer/activation email skipped.');
          await docRef.set({
            'processedAt': FieldValue.serverTimestamp(),
            'email': email,
            'type': 'skip',
          });
          continue;
        }

        bool processed = false;

        // ── Handle payment confirmation ───────────────────────────────────────
        if (isPayment) {
          processed = await _detectAndSavePayment(body, linkedCards);
          if (processed) {
            debugPrint(
              '💰 Payment confirmation processed — card(s) marked as paid',
            );
          }
        }

        // ── PDF attachment processing (bills only) ────────────────────────────
        if (isBill) {
          final pdfAttachment = _findFirstPdfAttachment(message.payload);
          if (pdfAttachment != null &&
              pdfAttachment.body?.attachmentId != null) {
            debugPrint('📎 PDF attachment found: ${pdfAttachment.filename}');
            try {
              // Download PDF bytes
              final attachment = await gmailApi.users.messages.attachments.get(
                'me',
                messageId,
                pdfAttachment.body!.attachmentId!,
              );
              if (attachment.data != null) {
                final pdfBytes = base64Url.decode(
                  attachment.data!.replaceAll('-', '+').replaceAll('_', '/'),
                );

                // Use pre-fetched profiles to build password candidates
                final passwordCandidates = PdfParserService.instance
                    .buildPasswordCandidates(
                      emailBody: body,
                      profiles: profiles,
                      linkedCards: linkedCards,
                    );

                // Extract PDF text (auto-unlock)
                final pdfText = await PdfParserService.instance.extractText(
                  pdfBytes: pdfBytes,
                  passwordCandidates: passwordCandidates,
                );

                if (pdfText != null) {
                  debugPrint('📄 PDF text extracted (${pdfText.length} chars)');
                  // Parse bill data from PDF text
                  final billData = PdfParserService.instance.parseBillFromText(
                    pdfText,
                  );
                  debugPrint('📊 Parsed bill: $billData');

                  if (billData.hasAnyData) {
                    // Auto-match profile to card holder
                    processed = await _savePdfBillData(
                      billData: billData,
                      linkedCards: linkedCards,
                      emailBody: body,
                    );
                  }
                }
              }
            } catch (e) {
              debugPrint('❌ PDF processing error: $e');
            }
          }

          // If PDF didn't yield results, fall back to email body parsing
          if (!processed) {
            processed = await _parseAndSaveBill(body, linkedCards);
          }
        } else if (!isPayment) {
          // Only parse as transaction if it's not a payment confirmation
          processed = await _parseAndSaveTransaction(
            body,
            linkedCards,
            internalDate,
            snippet,
          );
        }

        if (processed) {
          await docRef.set({
            'processedAt': FieldValue.serverTimestamp(),
            'email': email,
            'type': isBill ? 'bill' : 'transaction',
          });
          processedCount++;
        } else {
          debugPrint('❌ No valid match or amount found in this email.');
        }
      }

      // Update last sync time in DB
      await DatabaseHelper.instance.updateEmailAccountSyncTime(email);

      debugPrint(
        '✅ Sync complete for $email. Processed $processedCount new items.',
      );
    } catch (e) {
      debugPrint('Error syncing emails for $email: $e');
      if (!isRetry &&
          (e.toString().contains('401') || e.toString().contains('denied'))) {
        await _googleSignIn.signInSilently(reAuthenticate: true);
        return await syncEmails(email, isRetry: true, isManual: isManual);
      }
    }
  }

  // ─── PDF helpers ─────────────────────────────────────────────────────────────

  /// Recursively searches the MIME tree for the first `application/pdf` part.
  MessagePart? _findFirstPdfAttachment(MessagePart? payload) {
    if (payload == null) return null;
    if (payload.mimeType == 'application/pdf' &&
        (payload.filename?.isNotEmpty ?? false)) {
      return payload;
    }
    if (payload.parts != null) {
      for (final part in payload.parts!) {
        final found = _findFirstPdfAttachment(part);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Saves bill data extracted from a PDF to the best-matching card.
  /// Auto-matches by card holder name ↔ PDF-detected card holder ↔ profile.
  Future<bool> _savePdfBillData({
    required dynamic billData, // BillData from PdfParserService
    required List<CardModel> linkedCards,
    required String emailBody,
  }) async {
    if (linkedCards.isEmpty) return false;

    List<CardModel> targetCards = linkedCards;

    // ── Priority 1: match by card last-4 digits from the PDF ─────────────────
    final String? last4 = billData.cardLast4 as String?;
    if (last4 != null && last4.isNotEmpty) {
      final byLast4 = linkedCards.where((c) {
        final cardEnd = c.number.length >= 4
            ? c.number
                  .replaceAll(' ', '')
                  .substring(c.number.replaceAll(' ', '').length - 4)
            : '';
        final storedLast4 = c.last4 ?? cardEnd;
        return storedLast4.endsWith(last4) || last4.endsWith(storedLast4);
      }).toList();
      if (byLast4.isNotEmpty) {
        targetCards = byLast4;
        debugPrint('🎯 Matched ${byLast4.length} card(s) by last-4 "$last4"');
      }
    }

    // ── Priority 2: match by cardholder name ────────────────────────────────
    final holderFromPdf = billData.cardHolder as String?;
    if (targetCards.length > 1 &&
        holderFromPdf != null &&
        holderFromPdf.isNotEmpty) {
      final byHolder = targetCards.where((c) {
        final cardHolder = c.holder.toLowerCase().trim();
        final pdfHolder = holderFromPdf.toLowerCase().trim();
        return cardHolder.contains(pdfHolder.split(' ').first) ||
            pdfHolder.contains(cardHolder.split(' ').first);
      }).toList();
      if (byHolder.isNotEmpty) targetCards = byHolder;
    }

    // ── Priority 3: if still multiple, filter by bank then take only the first ─
    // Prevent mass-updating every HDFC card when we don't know which one.
    if (targetCards.length > 1) {
      final pdfBank = billData.bankName as String?;
      if (pdfBank != null) {
        final byBank = targetCards
            .where(
              (c) =>
                  c.bank.toLowerCase().contains(pdfBank.toLowerCase()) ||
                  pdfBank.toLowerCase().contains(c.bank.toLowerCase()),
            )
            .toList();
        if (byBank.isNotEmpty) targetCards = byBank;
      }
      // If still ambiguous after bank filter, update only the FIRST match to
      // avoid setting wrong due dates on unrelated cards.
      if (targetCards.length > 1) {
        debugPrint(
          '⚠️ ${targetCards.length} cards match — updating only the first to avoid false saves. '
          'Link cards to specific emails for precise matching.',
        );
        targetCards = [targetCards.first];
      }
    }

    bool updatedAny = false;
    final Set<String> notified = {};

    for (final card in targetCards) {
      // Skip if bank explicitly doesn't match
      final pdfBank = billData.bankName as String?;
      if (pdfBank != null &&
          !card.bank.toLowerCase().contains(pdfBank.toLowerCase()) &&
          !pdfBank.toLowerCase().contains(card.bank.toLowerCase())) {
        continue;
      }

      final amount = billData.totalDue as double?;
      final dueDate = billData.dueDate as DateTime?;

      if (amount == null && dueDate == null) continue;

      // Skip updating if amount is null — only update due date when we have it
      final updatedCard = card.copyWith(
        dueDate: dueDate != null ? () => dueDate.toIso8601String() : null,
        spent: amount != null ? amount : null,
        isPaid: false,
      );
      await DatabaseHelper.instance.updateCard(updatedCard);

      final notifyKey =
          '${card.bank.toLowerCase()}_${amount?.toStringAsFixed(0) ?? "pdf"}';
      if (!notified.contains(notifyKey)) {
        final dueDateStr = dueDate != null
            ? DateFormat('dd MMM yyyy').format(dueDate)
            : null;
        // Only notify if there's a real amount OR a due date
        if (amount != null && amount > 0 || dueDateStr != null) {
          NotificationService().showBillDetectedNotification(
            card.bank,
            amount ?? 0,
            dueDateStr,
          );
        }
        notified.add(notifyKey);
      }

      updatedAny = true;
      debugPrint(
        '📄 PDF BILL SAVED: ${card.bank} ₹$amount${dueDate != null ? " due $dueDate" : ""}',
      );
    }
    return updatedAny;
  }

  // ─── Body decoding ───────────────────────────────────────────────────────────

  String? _getDecodedBody(Message message) {
    String? plainText;
    String? htmlText;

    void parsePart(MessagePart part) {
      if (part.mimeType == 'text/plain' && part.body?.data != null) {
        plainText = _decodeBase64(part.body!.data!);
      } else if (part.mimeType == 'text/html' && part.body?.data != null) {
        htmlText = _decodeBase64(part.body!.data!);
      }
      if (part.parts != null) {
        for (var sub in part.parts!) {
          parsePart(sub);
        }
      }
    }

    if (message.payload != null) {
      parsePart(message.payload!);
    }

    if (plainText != null && plainText!.isNotEmpty) {
      return _decodeHtmlEntities(plainText!);
    }
    if (htmlText != null && htmlText!.isNotEmpty) {
      final stripped = htmlText!
          .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), ' ')
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), ' ')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return _decodeHtmlEntities(stripped);
    }
    return null;
  }

  String _decodeBase64(String data) =>
      utf8.decode(base64Url.decode(data), allowMalformed: true);

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'&#\d+;'), '');
  }

  // ─── Card matching ───────────────────────────────────────────────────────────

  bool _isCardMatch(String content, CardModel card) {
    final last4 =
        card.last4 ??
        (card.number.length >= 4
            ? card.number.substring(card.number.length - 4)
            : '');

    if (last4.isNotEmpty && content.contains(last4)) return true;

    if (last4.length >= 2) {
      final last2 = last4.substring(last4.length - 2);
      final last4Pat = RegExp(r'[Xx*]{2,}' + last4, caseSensitive: false);
      final last2Pat = RegExp(r'[Xx*]{2,}' + last2, caseSensitive: false);
      if (last4Pat.hasMatch(content)) return true;
      if (last2Pat.hasMatch(content) &&
          content.toLowerCase().contains(card.bank.toLowerCase()))
        return true;
    }

    if (content.toLowerCase().contains(card.bank.toLowerCase())) return true;

    return false;
  }

  // ─── Bank detection ─────────────────────────────────────────────────────────

  /// Detects which bank an email is from based on content patterns.
  /// Returns the bank name (e.g., 'HDFC', 'ICICI', 'Axis') or null if unknown.
  String? _detectBankFromContent(String content) {
    final lower = content.toLowerCase();

    // Bank-specific patterns (ordered by specificity)
    final bankPatterns = [
      // HDFC patterns
      (RegExp(r'hdfc\s+bank', caseSensitive: false), 'HDFC'),
      (RegExp(r'from\s+hdfc', caseSensitive: false), 'HDFC'),
      (RegExp(r'hdfc\s+credit\s+card', caseSensitive: false), 'HDFC'),
      (RegExp(r'hdfc\s+statement', caseSensitive: false), 'HDFC'),

      // ICICI patterns
      (RegExp(r'icici\s+bank', caseSensitive: false), 'ICICI'),
      (RegExp(r'from\s+icici', caseSensitive: false), 'ICICI'),
      (RegExp(r'icici\s+credit\s+card', caseSensitive: false), 'ICICI'),
      (RegExp(r'icici\s+statement', caseSensitive: false), 'ICICI'),

      // Axis patterns
      (RegExp(r'axis\s+bank', caseSensitive: false), 'Axis'),
      (RegExp(r'from\s+axis', caseSensitive: false), 'Axis'),
      (RegExp(r'axis\s+credit\s+card', caseSensitive: false), 'Axis'),
      (RegExp(r'axis\s+statement', caseSensitive: false), 'Axis'),

      // SBI patterns
      (RegExp(r'sbi\s+card', caseSensitive: false), 'SBI'),
      (RegExp(r'state\s+bank\s+of\s+india', caseSensitive: false), 'SBI'),
      (RegExp(r'from\s+sbi', caseSensitive: false), 'SBI'),
      (RegExp(r'sbi\s+statement', caseSensitive: false), 'SBI'),

      // IDFC patterns
      (RegExp(r'idfc\s+first\s+bank', caseSensitive: false), 'IDFC'),
      (RegExp(r'idfc\s+bank', caseSensitive: false), 'IDFC'),
      (RegExp(r'from\s+idfc', caseSensitive: false), 'IDFC'),
      (RegExp(r'idfc\s+statement', caseSensitive: false), 'IDFC'),

      // Kotak patterns
      (RegExp(r'kotak\s+bank', caseSensitive: false), 'Kotak'),
      (RegExp(r'from\s+kotak', caseSensitive: false), 'Kotak'),
      (RegExp(r'kotak\s+credit\s+card', caseSensitive: false), 'Kotak'),
      (RegExp(r'kotak\s+statement', caseSensitive: false), 'Kotak'),

      // Standard Chartered patterns
      (
        RegExp(r'standard\s+chartered', caseSensitive: false),
        'Standard Chartered',
      ),
      (RegExp(r'stanchart', caseSensitive: false), 'Standard Chartered'),
      (RegExp(r'from\s+standard', caseSensitive: false), 'Standard Chartered'),

      // Yes Bank patterns
      (RegExp(r'yes\s+bank', caseSensitive: false), 'Yes Bank'),
      (RegExp(r'from\s+yes\s+bank', caseSensitive: false), 'Yes Bank'),
      (RegExp(r'yes\s+credit\s+card', caseSensitive: false), 'Yes Bank'),

      // Citibank patterns
      (RegExp(r'citi\s+bank', caseSensitive: false), 'Citibank'),
      (RegExp(r'citibank', caseSensitive: false), 'Citibank'),
      (RegExp(r'from\s+citi', caseSensitive: false), 'Citibank'),

      // RBL patterns
      (RegExp(r'rbl\s+bank', caseSensitive: false), 'RBL'),
      (RegExp(r'from\s+rbl', caseSensitive: false), 'RBL'),
      (RegExp(r'rbl\s+credit\s+card', caseSensitive: false), 'RBL'),
    ];

    for (final (pattern, bank) in bankPatterns) {
      if (pattern.hasMatch(lower)) {
        return bank;
      }
    }

    return null;
  }

  // ─── Bank-specific parsing strategies ──────────────────────────────────────

  /// Applies bank-specific parsing strategies to improve accuracy.
  /// Returns a map of adjustments or hints for parsing.
  Map<String, dynamic> _getBankSpecificParsingStrategy(String bank) {
    final strategies = {
      'HDFC': {
        'amountKeywords': ['total amount due', 'amount due', 'total due'],
        'dateFormat': 'dd MMM yyyy', // "15 Jan 2024"
        'prefersAmountBeforeDate': true,
        'commonPhrases': ['HDFC Bank Credit Card', 'statement for'],
      },
      'ICICI': {
        'amountKeywords': [
          'current outstanding',
          'outstanding amount',
          'amount due',
        ],
        'dateFormat': 'dd/MM/yyyy', // "15/01/2024"
        'prefersAmountBeforeDate': false,
        'commonPhrases': ['ICICI Bank Credit Card', 'outstanding balance'],
      },
      'Axis': {
        'amountKeywords': ['minimum amount due', 'total due', 'amount payable'],
        'dateFormat': 'dd-MMM-yyyy', // "15-Jan-2024"
        'prefersAmountBeforeDate': true,
        'commonPhrases': ['Axis Bank Credit Card', 'minimum due'],
      },
      'SBI': {
        'amountKeywords': ['amount due', 'bill amount', 'total due'],
        'dateFormat': 'dd-MM-yyyy', // "15-01-2024"
        'prefersAmountBeforeDate': false,
        'commonPhrases': ['SBI Card', 'statement of account'],
      },
      'IDFC': {
        'amountKeywords': ['bill amount', 'statement amount', 'amount due'],
        'dateFormat': 'dd MMM yyyy', // "15 Jan 2024"
        'prefersAmountBeforeDate': true,
        'commonPhrases': ['IDFC First Bank', 'credit card statement'],
      },
      'Kotak': {
        'amountKeywords': ['total payment due', 'total due', 'amount payable'],
        'dateFormat': 'dd/MM/yyyy', // "15/01/2024"
        'prefersAmountBeforeDate': false,
        'commonPhrases': ['Kotak Mahindra Bank', 'credit card'],
      },
      'Standard Chartered': {
        'amountKeywords': ['pay', 'amount due', 'total due'],
        'dateFormat': 'dd MMM yyyy', // "15 Jan 2024"
        'prefersAmountBeforeDate': true,
        'commonPhrases': ['Standard Chartered', 'please pay'],
      },
    };

    return strategies[bank] ?? {};
  }

  // ─── Bill parsing ────────────────────────────────────────────────────────────

  Future<bool> _parseAndSaveBill(String content, List<CardModel> cards) async {
    bool updatedAny = false;
    final lowerContent = content.toLowerCase();

    // Detect bank from email content for bank-specific parsing
    final detectedBank = _detectBankFromContent(content);
    final bankStrategy = detectedBank != null
        ? _getBankSpecificParsingStrategy(detectedBank)
        : {};
    // TODO: Use bankStrategy for bank-specific parsing optimizations
    // Currently used for debugging/logging only
    if (bankStrategy.isNotEmpty) {
      debugPrint('ℹ️ Bank-specific strategy detected for $detectedBank');
    }

    // Track (bank_lc + amount) pairs already notified in this email to prevent
    // duplicate notifications when several cards match the same bank name.
    final Set<String> notifiedBills = {};

    // Per-bank save dedup: when the email doesn't identify a specific card
    // (no last-4 in body), only update the FIRST matching card per bank.
    // This prevents triple-saving "HDFC bill ₹340" to all 3 HDFC cards.
    final Set<String> savedBanks = {};

    for (var card in cards) {
      if (card.isManualDueDate || !_isCardMatch(content, card)) continue;

      final bankKey = card.bank.toLowerCase();
      final cardLast4 =
          card.last4 ??
          (card.number.replaceAll(' ', '').length >= 4
              ? card.number
                    .replaceAll(' ', '')
                    .substring(card.number.replaceAll(' ', '').length - 4)
              : '');
      // Does the email body explicitly name this card's last-4?
      final hasSpecificMatch =
          cardLast4.isNotEmpty && lowerContent.contains(cardLast4);

      if (!hasSpecificMatch && savedBanks.contains(bankKey)) {
        debugPrint(
          '⏭️ ${card.bank}: already saved for this bank in this email — skipping duplicate.',
        );
        continue;
      }

      // ── Amount extraction ──────────────────────────────────────────────────
      double? amount;

      // ⚠️  Patterns are in PRIORITY ORDER — most specific first.
      // Enhanced for Indian bank formats (HDFC, ICICI, Axis, SBI, IDFC, etc.)
      final List<RegExp> amountPatterns = [
        // HDFC: "Total Amount Due: ₹4,500" / "Total Amount Due (INR): 4,500"
        RegExp(
          r'total amount due\s*(?:\(inr\))?\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // ICICI: "Current Outstanding: ₹3,200" / "Outstanding Amount (INR): 3,200"
        RegExp(
          r'(?:current )?outstanding\s*(?:\(inr\))?\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // Axis: "Minimum Amount Due: ₹500" / "Minimum Due: 500"
        RegExp(
          r'minimum\s*(?:amount\s*)?due\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // SBI: "Amount Due: ₹2,000" / "Amount Payable: 2,000"
        RegExp(
          r'(?<!minimum\s)(?:amount\s*(?:due|payable))\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // IDFC: "Bill Amount: ₹1,800" / "Statement Amount: 1,800"
        RegExp(
          r'(?:bill|statement)\s*amount\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // Kotak: "Total Due: ₹5,900" / "Total Payment Due: 5,900"
        RegExp(
          r'total\s*(?:payment\s*)?due\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // Standard Chartered: "Pay ₹4,000 by ..." / "Please pay INR 4,000"
        RegExp(
          r'(?:please\s+)?pay\s+(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // Yes Bank: "bill of Rs 340 for ..." / "invoice of INR 340"
        RegExp(
          r'(?:bill|invoice)\s+of\s+(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // Indian format: "Rs 340 is due" / "Rs 340 for XXXX is due"
        RegExp(
          r'(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)(?:\s+for[^.]{0,20})?\s+is\s+(?:due|payable)',
          caseSensitive: false,
        ),
        // "rs 11276 due on" — note: must appear right before due keyword
        RegExp(
          r'(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)\s+due',
          caseSensitive: false,
        ),
        // HDFC/ICICI specific: "Your card statement for ₹4,567 is ready"
        RegExp(
          r'statement\s+(?:for|of)\s+(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // Amount with "INR" prefix and colon: "INR: 2,500.00"
        RegExp(
          r'(?:₹|rs\.?|inr)\s*[:\-]\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
      ];

      for (final pattern in amountPatterns) {
        final m = pattern.firstMatch(lowerContent);
        if (m != null) {
          final parsed = double.tryParse(m.group(1)!.replaceAll(',', ''));
          // ₹10 minimum — filters out tiny promo amounts (₹1 coins, ₹5 cashback)
          // but still captures small legitimate bills
          if (parsed != null && parsed >= 10) {
            amount = parsed;
            break;
          }
        }
      }

      // Fallback 1: scan for the largest decimal amount within 80 chars of a
      // billing label. Handles layouts where HTML stripping adds extra spaces
      // between the label and the amount (e.g. Axis Bank tabular emails).
      // NOTE: also handles integer amounts (no decimal) like "Total Amount Due INR 45000"
      if (amount == null) {
        final billingLabelRe = RegExp(
          r'(?:total amount due|amount due|total due|outstanding amount|current outstanding|bill amount|amount payable)',
          caseSensitive: false,
        );
        // Match any number with optional Indian lakh comma formatting,
        // [\d,]+ handles Indian comma grouping; decimal is optional.
        // Simple greedy match avoids the "40 from 405.42" split bug.
        final numRe = RegExp(r'[\d,]+(?:\.\d{1,2})?');
        double? best;
        for (final lm in billingLabelRe.allMatches(lowerContent)) {
          final end = (lm.end + 120).clamp(0, lowerContent.length);
          final window = lowerContent.substring(lm.start, end);
          for (final nm in numRe.allMatches(window)) {
            final v = double.tryParse(nm.group(0)!.replaceAll(',', ''));
            if (v != null && v >= 10) {
              if (best == null || v > best) best = v;
            }
          }
        }
        if (best != null) amount = best;
      }

      // Fallback 2: Aggressive last-resort scanning - find any amount ≥ ₹10
      // in the entire email that appears near any bill/statement related keywords
      if (amount == null) {
        debugPrint('⚠️ ${card.bank}: Trying aggressive fallback parsing...');
        final billKeywords = RegExp(
          r'(?:bill|statement|due|outstanding|payable|payment|amount|invoice|credit\s*card)',
          caseSensitive: false,
        );
        final amountPattern = RegExp(
          r'(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        );

        double? bestAmount;
        int bestScore = 0;

        // Scan through the content looking for bill keywords
        for (final keywordMatch in billKeywords.allMatches(lowerContent)) {
          final start = (keywordMatch.start - 100).clamp(
            0,
            lowerContent.length,
          );
          final end = (keywordMatch.end + 100).clamp(0, lowerContent.length);
          final window = lowerContent.substring(start, end);

          // Find all amounts in this window
          for (final amountMatch in amountPattern.allMatches(window)) {
            final v = double.tryParse(
              amountMatch.group(1)!.replaceAll(',', ''),
            );
            if (v != null && v >= 10) {
              // Additional validation to prevent unrealistic amounts
              // (e.g., ₹9,215,676,766 which are likely phone numbers or IDs)
              if (v > 10000000) {
                // ₹10 million - unrealistic for credit card bills
                debugPrint(
                  '⚠️ ${card.bank}: Skipping unrealistic amount ₹$v in fallback (likely phone number/ID)',
                );
                continue;
              }

              // Check for suspiciously large numbers that might be concatenated digits
              if (v > 1000000 && v.toString().length > 7) {
                // Over 1 million with many digits
                debugPrint(
                  '⚠️ ${card.bank}: Skipping suspiciously large amount ₹$v with ${v.toString().length} digits',
                );
                continue;
              }

              // Score based on proximity to keyword and amount size
              final distance = (amountMatch.start - keywordMatch.start).abs();
              final score =
                  (v * 100) ~/
                  (distance +
                      1); // Larger amounts and closer distance get higher score
              if (bestAmount == null || score > bestScore) {
                bestAmount = v;
                bestScore = score;
              }
            }
          }
        }

        if (bestAmount != null) {
          amount = bestAmount;
          debugPrint(
            '✅ ${card.bank}: Fallback found amount ₹$bestAmount (score: $bestScore)',
          );
        }
      }

      if (amount == null) {
        debugPrint(
          '⏭️ ${card.bank}: no valid bill amount ≥ ₹10 found. Skipping.',
        );
        continue;
      }

      // ── Due date extraction ────────────────────────────────────────────────
      DateTime? dueDate;

      final List<RegExp> datePatterns = [
        // Indian format: "Due on: 15 Jan 2024" / "Payment due by 15-Jan-2024"
        RegExp(
          r'(?:due\s+(?:on|by|date)?|payment\s+due\s+(?:by|on)?)\s*[:\-]?\s*'
          r'(\d{1,2}\s*(?:[-\s])?\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*(?:[-\s])?\s*\d{2,4})',
          caseSensitive: false,
        ),
        // "Due date: Jan 15, 2024" / "Due: January 15, 2024"
        RegExp(
          r'(?:due\s+(?:on|by|date)?|payment\s+due\s+(?:by|on)?)\s*[:\-]?\s*'
          r'((?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2},?\s+\d{2,4})',
          caseSensitive: false,
        ),
        // DD/MM/YYYY or DD-MM-YYYY format: "15/01/2024" / "15-01-2024"
        RegExp(
          r'(?:due\s+(?:on|by|date)?|payment\s+due\s+(?:by|on)?)\s*[:\-]?\s*'
          r'(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})',
          caseSensitive: false,
        ),
        // Full month name: "Payment due by January 15, 2024"
        RegExp(
          r'payment\s+due\s+by\s+'
          r'((?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+\d{2,4})',
          caseSensitive: false,
        ),
        // Generic date pattern anywhere in email (fallback)
        RegExp(
          r'\b(\d{1,2}\s*(?:[-\s])?\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*(?:[-\s])?\s*\d{2,4})\b',
          caseSensitive: false,
        ),
        // Indian banks often use: "Last date for payment: 15th Jan 2024"
        RegExp(
          r'(?:last\s+date\s+for\s+payment|last\s+date\s+to\s+pay)\s*[:\-]?\s*'
          r'(\d{1,2}(?:st|nd|rd|th)?\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{2,4})',
          caseSensitive: false,
        ),
        // "Pay by 15th January 2024"
        RegExp(
          r'pay\s+by\s+(\d{1,2}(?:st|nd|rd|th)?\s*(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{2,4})',
          caseSensitive: false,
        ),
      ];

      for (final pattern in datePatterns) {
        final m = pattern.firstMatch(lowerContent);
        if (m != null) {
          try {
            dueDate = _parseFlexibleDate(m.group(1)!.trim());
            if (dueDate != null) break;
          } catch (_) {}
        }
      }

      // ── Validation of extracted values ──────────────────────────────────────
      if (!_validateBillAmount(amount, card.bank)) {
        debugPrint(
          '❌ ${card.bank}: Bill amount ₹$amount failed validation. Skipping.',
        );
        continue;
      }

      if (!_validateDueDate(dueDate, card.bank)) {
        debugPrint(
          '❌ ${card.bank}: Due date $dueDate failed validation. Skipping.',
        );
        continue;
      }

      // Additional validation: check if this bill is significantly different from previous amount
      // (e.g., more than 5x or less than 0.2x of previous spent amount)
      final previousSpent = card.spent ?? 0;
      if (previousSpent > 0) {
        final ratio = amount / previousSpent;
        if (ratio > 5.0 || ratio < 0.2) {
          debugPrint(
            '⚠️ ${card.bank}: Bill amount ₹$amount is significantly different '
            'from previous ₹$previousSpent (ratio: ${ratio.toStringAsFixed(1)}x). '
            'This could be a parsing error.',
          );
          // Don't reject, just log warning
        }
      }

      await DatabaseHelper.instance.updateCard(
        card.copyWith(
          dueDate: dueDate != null ? () => dueDate!.toIso8601String() : null,
          spent: amount, // keep card 'Amount' in sync with the bill total
          isPaid: false,
        ),
      );

      // 🔔 Notify once per unique bank+amount combo (prevents duplicate toasts
      //    when 2+ cards from the same bank all match the same statement email)
      final notifyKey =
          '${card.bank.toLowerCase()}_${amount.toStringAsFixed(0)}';
      if (!notifiedBills.contains(notifyKey)) {
        final dueDateStr = dueDate != null
            ? DateFormat('dd MMM yyyy').format(dueDate)
            : null;
        NotificationService().showBillDetectedNotification(
          card.bank,
          amount,
          dueDateStr,
        );
        notifiedBills.add(notifyKey);
      }

      updatedAny = true;
      savedBanks.add(bankKey); // mark: one card for this bank already saved
      debugPrint(
        '📅 BILL: ${card.bank} ₹$amount${dueDate != null ? " due $dueDate" : ""}',
      );
    }
    return updatedAny;
  }

  // ─── Transaction parsing ─────────────────────────────────────────────────────

  Future<bool> _parseAndSaveTransaction(
    String content,
    List<CardModel> cards,
    DateTime internalDate,
    String snippet,
  ) async {
    bool foundAny = false;
    final cleanContent = content.replaceAll(RegExp(r'\s+'), ' ');

    for (var card in cards) {
      if (!_isCardMatch(cleanContent, card)) continue;

      double? amount;
      String? vendor;

      final List<RegExp> txPatterns = [
        // HDFC: "You have spent ₹1,234.56 at AMAZON"
        RegExp(
          r'(?:you\s+have\s+)?(?:spent|debited|charged)\s+(?:(?:₹|rs\.?|inr)\s*)?([\d,]+(?:\.\d{1,2})?)\s+(?:at|to|on|for)\s+([A-Za-z0-9 _\-\./\*]{3,50}?)(?=\s+(?:on|at|using|via|,|\.|$))',
          caseSensitive: false,
        ),
        // ICICI: "Purchase of ₹1,234.56 at AMAZON"
        RegExp(
          r'purchase\s+(?:of|for)\s+(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)\s+(?:at|to|on|for)\s+([A-Za-z0-9 _\-\./\*]{3,50}?)(?=\s+(?:on|at|using|via|,|\.|$))',
          caseSensitive: false,
        ),
        // Axis: "Transaction at AMAZON for ₹1,234.56"
        RegExp(
          r'transaction\s+(?:at|to|on|for)\s+([A-Za-z0-9 _\-\./\*]{3,50}?)\s+for\s+(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ),
        // SBI: "₹1,234.56 debited at AMAZON"
        RegExp(
          r'(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)\s+(?:debited|charged|spent)\s+(?:at|to|on|for)\s+([A-Za-z0-9 _\-\./\*]{3,50}?)(?=\s+(?:on|at|using|via|,|\.|$))',
          caseSensitive: false,
        ),
        // IDFC: "Alert: ₹1,234.56 spent at AMAZON"
        RegExp(
          r'(?:info[:\s]+|alert[:\s]+|notification[:\s]+)?(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)\s+(?:spent|used|paid|transacted)\s+(?:at|to|on|for)\s+([A-Za-z0-9 _\-\./\*]{3,50}?)(?=\s+(?:on|at|using|via|,|\.|$))',
          caseSensitive: false,
        ),
        // Kotak: "Paid ₹1,234.56 to AMAZON"
        RegExp(
          r'paid\s+(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)\s+to\s+([A-Za-z0-9 _\-\./\*@]{3,50}?)(?=\s+(?:on|via|using|,|\.|$))',
          caseSensitive: false,
        ),
        // Standard Chartered: "Your card ending XXXX was used for ₹1,234.56 at AMAZON"
        RegExp(
          r'used\s+(?:for|at)\s+(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)\s+(?:at|to|on|for)\s+([A-Za-z0-9 _\-\./\*]{3,50}?)(?=\s+(?:on|at|using|via|,|\.|$))',
          caseSensitive: false,
        ),
        // Yes Bank: "INR 500.00 has been spent on your Credit Card ending with XXXX at MERCHANT"
        RegExp(
          r'(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)\s+(?:has\s+been\s+)?(?:spent|used|paid|transacted)\s+(?:on\s+(?:your\s+)?(?:[A-Za-z\s]+)?credit\s+card\s+(?:ending\s+with\s+\d+)?\s+)?at\s+([A-Za-z0-9 _\-\./\*]{3,50}?)(?=\s*(?:\b(?:on|at|using|via)\b|,|\.|$))',
          caseSensitive: false,
        ),
        // Yes Bank: "A transaction of ₹1,234.56 has been made at AMAZON"
        RegExp(
          r'transaction\s+(?:of|for)\s+(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)\s+(?:has\s+been\s+)?(?:made|done)\s+(?:at|to|on|for)\s+([A-Za-z0-9 _\-\./\*]{3,50}?)(?=\s+(?:on|at|using|via|,|\.|$))',
          caseSensitive: false,
        ),
        // Indian format with merchant first: "AMAZON ₹1,234.56"
        RegExp(
          r'([A-Za-z0-9 _\-\./\*]{3,50}?)\s+(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)(?=\s+(?:on|at|using|via|,|\.|$))',
          caseSensitive: false,
        ),
        // UPI transaction: "UPI payment of ₹1,234.56 to AMAZON"
        RegExp(
          r'upi\s+(?:payment|transaction)\s+(?:of|for)\s+(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)\s+to\s+([A-Za-z0-9 _\-\./\*@]{3,50}?)(?=\s+(?:on|via|using|,|\.|$))',
          caseSensitive: false,
        ),
      ];

      for (final pattern in txPatterns) {
        final m = pattern.firstMatch(cleanContent);
        if (m == null) continue;

        double? parsed;
        String? rawVendor;

        if (pattern.pattern.startsWith(r'transaction')) {
          rawVendor = m.group(1)?.trim();
          parsed = double.tryParse((m.group(2) ?? '').replaceAll(',', ''));
        } else {
          parsed = double.tryParse((m.group(1) ?? '').replaceAll(',', ''));
          rawVendor = m.group(2)?.trim();
        }

        if (parsed == null || parsed < 1.0 || rawVendor == null) continue;

        rawVendor = rawVendor
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll(RegExp(r'[,\.]$'), '')
            .trim();

        final forbiddenVendors = {
          'oct',
          'nov',
          'dec',
          'jan',
          'feb',
          'mar',
          'apr',
          'may',
          'jun',
          'jul',
          'aug',
          'sep',
          'date',
          'on',
          'the',
          'a',
          'an',
        };
        if (forbiddenVendors.contains(rawVendor.toLowerCase())) continue;
        if (RegExp(r'^\d').hasMatch(rawVendor)) continue;

        amount = parsed;
        vendor = rawVendor;
        break;
      }

      // Fallback transaction detection: if no pattern matched, try to find
      // any amount with transaction keywords in the email
      if (amount == null || vendor == null) {
        debugPrint('⚠️ ${card.bank}: Trying fallback transaction detection...');

        // Look for transaction keywords near amounts
        final txKeywords = RegExp(
          r'(?:transaction|purchase|payment|spent|charged|debited|paid|billed|upi|card\s*usage)',
          caseSensitive: false,
        );
        final amountPattern = RegExp(
          r'(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        );

        double? bestAmount;
        String? bestVendor;
        int bestScore = 0;

        // Scan through content for transaction keywords
        for (final keywordMatch in txKeywords.allMatches(
          cleanContent.toLowerCase(),
        )) {
          final start = (keywordMatch.start - 150).clamp(
            0,
            cleanContent.length,
          );
          final end = (keywordMatch.end + 150).clamp(0, cleanContent.length);
          final window = cleanContent.substring(start, end);

          // Find amounts in this window
          for (final amountMatch in amountPattern.allMatches(window)) {
            final v = double.tryParse(
              amountMatch.group(1)!.replaceAll(',', ''),
            );
            if (v != null && v >= 1.0) {
              // Additional validation to prevent unrealistic transaction amounts
              // (e.g., ₹9,215,676,766 which are likely phone numbers or IDs)
              if (v > 1000000) {
                // ₹1 million - unrealistic for single transaction
                debugPrint(
                  '⚠️ ${card.bank}: Skipping unrealistic transaction amount ₹$v (likely phone number/ID)',
                );
                continue;
              }

              // Check for suspiciously large numbers that might be concatenated digits
              if (v > 100000 && v.toString().length > 6) {
                // Over 100k with many digits
                debugPrint(
                  '⚠️ ${card.bank}: Skipping suspiciously large transaction amount ₹$v with ${v.toString().length} digits',
                );
                continue;
              }

              // Try to extract vendor name - look for capitalized words near the amount
              final vendorStart = (amountMatch.start - 50).clamp(
                0,
                window.length,
              );
              final vendorEnd = (amountMatch.end + 50).clamp(0, window.length);
              final vendorWindow = window.substring(vendorStart, vendorEnd);

              // Look for capitalized merchant names (common in transaction emails)
              final vendorMatch = RegExp(
                r'[A-Z][A-Za-z0-9&\.\-_]{2,}(?:\s+[A-Z][A-Za-z0-9&\.\-_]{2,})*',
              ).firstMatch(vendorWindow);

              String? candidateVendor = vendorMatch?.group(0);
              if (candidateVendor != null) {
                // Filter out common false positives
                final lowerVendor = candidateVendor.toLowerCase();
                if (lowerVendor.contains('transaction') ||
                    lowerVendor.contains('payment') ||
                    lowerVendor.contains('card') ||
                    lowerVendor.contains('bank') ||
                    lowerVendor.contains('date') ||
                    lowerVendor.contains('time') ||
                    lowerVendor.length < 3) {
                  candidateVendor = null;
                }
              }

              // If no vendor found, use generic "Unknown"
              candidateVendor ??= 'Unknown Merchant';

              // Score based on amount size and proximity to keyword
              final distance = (amountMatch.start - keywordMatch.start).abs();
              final score = (v * 100) ~/ (distance + 1);

              if (bestAmount == null || score > bestScore) {
                bestAmount = v;
                bestVendor = candidateVendor;
                bestScore = score;
              }
            }
          }
        }

        if (bestAmount != null && bestVendor != null) {
          amount = bestAmount;
          vendor = bestVendor;
          debugPrint(
            '✅ ${card.bank}: Fallback transaction detected: $bestVendor - ₹$bestAmount',
          );
        }
      }

      if (amount == null || vendor == null) continue;

      // ── Validation of extracted transaction values ──────────────────────────
      if (!_validateTransactionAmount(amount, vendor)) {
        debugPrint(
          '❌ ${card.bank}: Transaction amount ₹$amount at $vendor failed validation. Skipping.',
        );
        continue;
      }

      if (!_validateVendorName(vendor)) {
        debugPrint(
          '❌ ${card.bank}: Vendor "$vendor" failed validation. Skipping.',
        );
        continue;
      }

      // Validate transaction date (use email internal date)
      if (!_validateTransactionDate(internalDate, vendor)) {
        debugPrint(
          '❌ ${card.bank}: Transaction date $internalDate failed validation. Skipping.',
        );
        continue;
      }

      // Additional validation: check for duplicate-like transactions
      // (same vendor + similar amount within last 7 days)
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      if (internalDate.isAfter(sevenDaysAgo)) {
        // This is a recent transaction, could check for duplicates
        // (implementation would require querying DB, but we'll just log)
        debugPrint(
          'ℹ️ ${card.bank}: Recent transaction detected at $vendor for ₹$amount',
        );
      }

      final tx = TransactionModel(
        cardId: card.id!,
        bank: card.bank,
        vendor: vendor,
        amount: amount,
        date: internalDate,
        rawSnippet: snippet,
        category: _guessCategory(vendor, cleanContent),
      );

      if (await DatabaseHelper.instance.insertTransaction(tx) != -1) {
        foundAny = true;
        debugPrint('✅ TRANSACTION DETECTED: $vendor - ₹$amount (${card.bank})');

        // 🔔 Fire instant local notification
        NotificationService().showTransactionDetectedNotification(
          vendor,
          amount,
          card.bank,
        );

        await TransactionService.instance.saveTransactionToFirebase(tx);
      }
    }
    return foundAny;
  }

  // ─── Date parsing ────────────────────────────────────────────────────────────

  DateTime? _parseFlexibleDate(String raw) {
    final s = raw.trim();

    final formats = [
      'dd MMM yyyy',
      'dd MMMM yyyy',
      'MMM dd, yyyy',
      'MMMM dd, yyyy',
      'MMMM d, yyyy',
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'MM/dd/yyyy',
    ];

    for (final fmt in formats) {
      try {
        return DateFormat(fmt).parseLoose(s);
      } catch (_) {}
    }

    final numericMatch = RegExp(
      r'(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})',
    ).firstMatch(s);
    if (numericMatch != null) {
      final d = numericMatch.group(1)!.padLeft(2, '0');
      final mo = numericMatch.group(2)!.padLeft(2, '0');
      String y = numericMatch.group(3)!;
      if (y.length == 2) y = '20$y';
      try {
        return DateFormat('dd/MM/yyyy').parse('$d/$mo/$y');
      } catch (_) {}
    }

    return null;
  }

  // ─── Payment detection ───────────────────────────────────────────────────────

  /// Detects a payment confirmation email and marks all matching linked cards
  /// as paid. Also fires a local notification confirming the payment.
  Future<bool> _detectAndSavePayment(
    String content,
    List<CardModel> linkedCards,
  ) async {
    bool updatedAny = false;

    for (final card in linkedCards) {
      if (!_isCardMatch(content, card)) continue;
      if (card.isPaid) {
        debugPrint('⏭️ ${card.bank} already marked as paid — skipping.');
        continue;
      }

      // Mark card as paid and roll due date to next cycle
      final paidCard = card.copyWith(isPaid: true);
      await DatabaseHelper.instance.updateCard(paidCard);

      // Notify the user
      await NotificationService().showPaymentConfirmedNotification(card.bank);

      debugPrint('✅ PAYMENT AUTO-DETECTED: ${card.bank} marked as paid');
      updatedAny = true;
    }
    return updatedAny;
  }

  // ─── Category guesser ────────────────────────────────────────────────────────

  String _guessCategory(String v, String c) {
    v = v.toLowerCase();
    c = c.toLowerCase();

    if (v.contains('amazon') ||
        v.contains('flipkart') ||
        v.contains('blinkit') ||
        v.contains('meesho') ||
        v.contains('myntra'))
      return 'Shopping';

    if (v.contains('swiggy') ||
        v.contains('zomato') ||
        v.contains('restaurant') ||
        v.contains('cafe') ||
        v.contains('food'))
      return 'Food';

    if (v.contains('uber') ||
        v.contains('ola') ||
        v.contains('fuel') ||
        v.contains('petrol') ||
        v.contains('rapido') ||
        v.contains('irctc'))
      return 'Travel';

    if (v.contains('netflix') ||
        v.contains('hotstar') ||
        v.contains('spotify') ||
        v.contains('prime') ||
        v.contains('youtube'))
      return 'Entertainment';

    if (v.contains('jio') ||
        v.contains('airtel') ||
        v.contains('bsnl') ||
        v.contains('recharge') ||
        v.contains('vi ') ||
        c.contains('bill'))
      return 'Bills';

    if (v.contains('apollo') ||
        v.contains('medplus') ||
        v.contains('pharma') ||
        v.contains('hospital') ||
        v.contains('clinic'))
      return 'Health';

    return 'Other';
  }
}
