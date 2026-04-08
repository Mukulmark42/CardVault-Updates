import 'dart:typed_data';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/profile_model.dart';
import '../models/card_model.dart';

/// Structured bill data extracted from a PDF statement.
class BillData {
  final double? totalDue;
  final double? minimumDue;
  final DateTime? dueDate;
  final String? bankName;
  final String? cardHolder;

  /// Last 4 digits of the card number as found in the PDF (used for card matching).
  final String? cardLast4;

  const BillData({
    this.totalDue,
    this.minimumDue,
    this.dueDate,
    this.bankName,
    this.cardHolder,
    this.cardLast4,
  });

  bool get hasAnyData =>
      totalDue != null || minimumDue != null || dueDate != null;

  @override
  String toString() =>
      'BillData(totalDue: $totalDue, minDue: $minimumDue, dueDate: $dueDate, bank: $bankName, last4: $cardLast4)';
}

/// Service for extracting text from bank statement PDFs and parsing bill data.
///
/// Password format detection: reads the email body to detect the bank's stated
/// format (e.g. "first 4 letters of your name + DDMM"), then generates
/// candidate passwords from the matched profile's name + DOB.
class PdfParserService {
  static final PdfParserService instance = PdfParserService._();
  PdfParserService._();

  // ─── Password candidate generation ───────────────────────────────────────

  /// Builds an ordered list of candidate PDF passwords from [profiles] and
  /// [linkedCards]. All 4 standard patterns are always tried:
  ///
  ///   1. First 4 letters UPPERCASE + DDMM   e.g. MUKU2703
  ///   2. First 4 letters lowercase  + DDMM   e.g. muku2703
  ///   3. DDMMYYYY + Last 4 card digits        e.g. 270319951234
  ///   4. First 4 letters UPPERCASE + Last 4   e.g. MUKU1234
  ///
  /// If the email body contains a hint (e.g. "first 4 letters of your name +
  /// DDMM"), the matching format is placed first so it's tried earlier.
  List<String> buildPasswordCandidates({
    required String emailBody,
    required List<ProfileModel> profiles,
    List<CardModel> linkedCards = const [],
  }) {
    final lower = emailBody.toLowerCase();
    final candidates = <String>[];

    // Detect hint in email to decide which format to try first
    final bool hintFirst4DDMM =
        lower.contains('first 4') ||
        lower.contains('first four') ||
        (lower.contains('name') &&
            (lower.contains('ddmm') ||
                lower.contains('date of birth') ||
                lower.contains('dob')));

    final bool hintDobLast4 =
        (lower.contains('date of birth') ||
            lower.contains('ddmmyyyy') ||
            lower.contains('dob')) &&
        (lower.contains('last 4') ||
            lower.contains('last four') ||
            lower.contains('credit card') ||
            lower.contains('card number'));

    for (final profile in profiles) {
      if (hintFirst4DDMM && !hintDobLast4) {
        // Email explicitly says name+DDMM — try patterns 1 & 2 first
        candidates.addAll(_first4PlusDDMM(profile));
        candidates.addAll(_cardBasedFallbacks(profile, linkedCards));
      } else if (hintDobLast4 && !hintFirst4DDMM) {
        // Email explicitly says DOB+Last4 — try patterns 3 & 4 first
        candidates.addAll(_cardBasedFallbacks(profile, linkedCards));
        candidates.addAll(_first4PlusDDMM(profile));
      } else {
        // No clear hint (or both detected) — follow user-specified priority:
        //   1. UPPERCASE name + DDMM
        //   2. lowercase name + DDMM
        //   3. DDMMYYYY + Last4
        //   4. UPPERCASE name + Last4
        candidates.addAll(_first4PlusDDMM(profile));
        candidates.addAll(_cardBasedFallbacks(profile, linkedCards));
      }

      // Always append any profile-defined presets as final fallback
      candidates.addAll(profile.pdfPasswordCandidates);
    }

    // Deduplicate while preserving priority order
    final seen = <String>{};
    return candidates.where((p) => seen.add(p)).toList();
  }

  /// Pattern 3: DDMMYYYY + Last4     →  "270319951234"
  /// Pattern 4: UPPERCASE first-4 + Last4  →  "MUKU1234"
  //  Also tries lowercase + Last4 as extra fallback.
  List<String> _cardBasedFallbacks(
    ProfileModel profile,
    List<CardModel> linkedCards,
  ) {
    final result = <String>[];
    final cleanName = profile.name.toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    final prefix = cleanName.length >= 4
        ? cleanName.substring(0, 4)
        : cleanName;

    String? dobDDMMYYYY;
    if (profile.dob != null) {
      try {
        final dt = DateTime.parse(profile.dob!);
        final dd = dt.day.toString().padLeft(2, '0');
        final mm = dt.month.toString().padLeft(2, '0');
        final yyyy = dt.year.toString();
        dobDDMMYYYY = '$dd$mm$yyyy';
      } catch (_) {}
    }

    for (final card in linkedCards) {
      final last4 =
          card.last4 ??
          (card.number.replaceAll(' ', '').length >= 4
              ? card.number
                    .replaceAll(' ', '')
                    .substring(card.number.replaceAll(' ', '').length - 4)
              : '');

      if (last4.isNotEmpty && last4.length >= 4) {
        // Pattern 3: DDMMYYYY + Last4
        if (dobDDMMYYYY != null) result.add('$dobDDMMYYYY$last4');
        // Pattern 4: UPPERCASE first-4 + Last4
        result.add('${prefix.toUpperCase()}$last4');
        // Extra: lowercase first-4 + Last4
        result.add('$prefix$last4');
      }
    }
    return result;
  }

  /// Pattern 1: UPPERCASE first-4 + DDMM  →  "MUKU2703"
  /// Pattern 2: lowercase first-4 + DDMM  →  "muku2703"
  List<String> _first4PlusDDMM(ProfileModel profile) {
    final result = <String>[];
    final cleanName = profile.name.toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    final prefix = cleanName.length >= 4
        ? cleanName.substring(0, 4)
        : cleanName;

    if (profile.dob != null) {
      try {
        final dt = DateTime.parse(profile.dob!);
        final dd = dt.day.toString().padLeft(2, '0');
        final mm = dt.month.toString().padLeft(2, '0');
        result.add(
          '${prefix.toUpperCase()}$dd$mm',
        ); // Pattern 1 — UPPERCASE first
        result.add('$prefix$dd$mm'); // Pattern 2 — lowercase
      } catch (_) {}
    }
    return result;
  }

  // ─── PDF extraction ───────────────────────────────────────────────────────

  /// Tries to open [pdfBytes] without a password first, then with each
  /// candidate from [passwordCandidates]. Returns the extracted text, or null
  /// if the PDF cannot be opened.
  Future<String?> extractText({
    required Uint8List pdfBytes,
    List<String> passwordCandidates = const [],
  }) async {
    // 1. Try without password
    final noPassResult = await _tryExtract(pdfBytes, null);
    if (noPassResult != null) return noPassResult;

    // 2. Try each candidate password
    for (final pw in passwordCandidates) {
      final result = await _tryExtract(pdfBytes, pw);
      if (result != null) {
        debugPrint('📄 PDF unlocked with password: "$pw"');
        return result;
      }
    }

    debugPrint(
      '❌ PDF could not be unlocked with any candidate password (tried ${passwordCandidates.length})',
    );
    return null;
  }

  Future<String?> _tryExtract(Uint8List bytes, String? password) async {
    return await Isolate.run(() {
      PdfDocument? doc;
      try {
        doc = password != null
            ? PdfDocument(inputBytes: bytes, password: password)
            : PdfDocument(inputBytes: bytes);

        final extractor = PdfTextExtractor(doc);
        final buffer = StringBuffer();

        for (int i = 0; i < doc.pages.count; i++) {
          final text = extractor.extractText(
            startPageIndex: i,
            endPageIndex: i,
          );
          buffer.write(text);
          buffer.write('\n');
        }

        final extracted = buffer.toString().trim();
        return extracted.isNotEmpty ? extracted : null;
      } catch (e) {
        // Wrong password or corrupt PDF — expected, just return null
        return null;
      } finally {
        doc?.dispose();
      }
    });
  }

  // ─── Bill data parsing ────────────────────────────────────────────────────

  /// Validates extracted bill data for reasonableness.
  /// Returns a validated subset (may nullify unrealistic values).
  ({double? totalDue, double? minimumDue, DateTime? dueDate})
  _validateBillData({
    required double? totalDue,
    required double? minimumDue,
    required DateTime? dueDate,
    required String? bankName,
  }) {
    double? validatedTotalDue = totalDue;
    double? validatedMinimumDue = minimumDue;
    DateTime? validatedDueDate = dueDate;

    // Validate total due amount
    if (validatedTotalDue != null) {
      // Minimum amount check (already done in parsing, but double-check)
      if (validatedTotalDue < 10) {
        debugPrint('⚠️ PDF: Total due ₹$validatedTotalDue is too small');
        validatedTotalDue = null;
      }
      // Maximum reasonable amount
      else if (validatedTotalDue > 1000000) {
        debugPrint(
          '⚠️ PDF: Total due ₹$validatedTotalDue exceeds ₹1,000,000 limit',
        );
        validatedTotalDue = null;
      }
      // Check for unrealistic amounts (phone numbers)
      else {
        final amountStr = validatedTotalDue.toStringAsFixed(0);
        if (amountStr.length > 9) {
          debugPrint(
            '⚠️ PDF: Total due has ${amountStr.length} digits (likely phone number)',
          );
          validatedTotalDue = null;
        }
      }
    }

    // Validate minimum due amount
    if (validatedMinimumDue != null) {
      if (validatedMinimumDue < 1) {
        debugPrint('⚠️ PDF: Minimum due ₹$validatedMinimumDue is too small');
        validatedMinimumDue = null;
      } else if (validatedMinimumDue > 100000) {
        debugPrint(
          '⚠️ PDF: Minimum due ₹$validatedMinimumDue exceeds ₹100,000 limit',
        );
        validatedMinimumDue = null;
      }
      // Ensure minimum due is not greater than total due (if both present)
      if (validatedTotalDue != null &&
          validatedMinimumDue != null &&
          validatedMinimumDue! > validatedTotalDue) {
        debugPrint(
          '⚠️ PDF: Minimum due (₹$validatedMinimumDue) > total due (₹$validatedTotalDue)',
        );
        validatedMinimumDue = null;
      }
    }

    // Validate due date
    if (validatedDueDate != null) {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final sixMonthsFuture = now.add(const Duration(days: 180));

      if (validatedDueDate.isBefore(thirtyDaysAgo)) {
        debugPrint(
          '⚠️ PDF: Due date $validatedDueDate is more than 30 days in past',
        );
        validatedDueDate = null;
      } else if (validatedDueDate.isAfter(sixMonthsFuture)) {
        debugPrint(
          '⚠️ PDF: Due date $validatedDueDate is more than 6 months in future',
        );
        validatedDueDate = null;
      }
    }

    return (
      totalDue: validatedTotalDue,
      minimumDue: validatedMinimumDue,
      dueDate: validatedDueDate,
    );
  }

  /// Parses extracted PDF text for bill details.
  BillData parseBillFromText(String text) {
    final lower = text.toLowerCase();

    // Debug: log first 500 chars of extracted text for visibility
    final preview = text.length > 500 ? text.substring(0, 500) + '...' : text;
    debugPrint('📄 PDF text extracted (${text.length} chars):\n$preview');

    // ── Total Due ────────────────────────────────────────────────────────────
    // Strategy: try progressively broader patterns. HDFC and other banks vary
    // in how they format the total-due amount in their PDFs:
    //  • Same line:  "Total Amount Due : 45,231.00"
    //  • With (₹):   "Total Amount Due (₹)  45,231.00"
    //  • Next line:  "Total Amount Due\n45,231.00"
    //  • Lakh fmt:  "1,45,231.00"  (Indian comma grouping)
    double? totalDue;

    // Patterns that expect the amount on the SAME line / within a few chars
    final totalPatterns = [
      // Handle (₹) / (INR) notation: "Total Amount Due (₹) 45,231.00"
      RegExp(
        r'total\s+amount\s+due\s*(?:\([₹inrrs\.]+\))?\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
      // Plain: "Total Due : 45,231.00"
      RegExp(
        r'total\s+due\s*(?:\([₹inrrs\.]+\))?\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
      // "Amount Due : 45,231.00"  (ICICI, Axis)
      RegExp(
        r'(?<!minimum\s)(?<!min\s)amount\s+due\s*(?:\([₹inrrs\.]+\))?\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
      // "Net Amount Due"
      RegExp(
        r'net\s+amount\s+due\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
      // "Amount Payable"
      RegExp(
        r'amount\s+payable\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
      // "Current Outstanding Balance"
      RegExp(
        r'current\s+outstanding(?:\s+balance)?\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
      // "Outstanding Balance"
      RegExp(
        r'outstanding\s+balance\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
      // "₹ 45,231.00 due" / "INR 45,231.00 due"
      RegExp(
        r'(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)\s+due',
        caseSensitive: false,
      ),
    ];

    for (final p in totalPatterns) {
      final m = p.firstMatch(lower);
      if (m != null) {
        final rawValue = m.group(1)!;
        final v = double.tryParse(rawValue.replaceAll(',', ''));
        debugPrint(
          '🔍 Total due pattern matched: "${p.pattern.substring(0, min(p.pattern.length, 50))}..." → "$rawValue" (parsed: $v)',
        );
        if (v != null && v >= 10) {
          totalDue = v;
          debugPrint('✅ Total due found: ₹$totalDue');
          break;
        }
      }
    }

    // Multi-line fallback: label on one line, amount on the next
    // e.g. "Total Amount Due\n  ₹45,231.00" or "Total Amount Due\n45231.00"
    if (totalDue == null) {
      final multiLineTotal = RegExp(
        r'(?:total\s+amount\s+due|total\s+due|net\s+amount\s+due|amount\s+payable|current\s+outstanding)'
        r'[^\n]{0,40}\n[^\n]{0,10}(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ).firstMatch(lower);
      if (multiLineTotal != null) {
        final v = double.tryParse(multiLineTotal.group(1)!.replaceAll(',', ''));
        if (v != null && v >= 10) totalDue = v;
      }
    }

    // Last-resort: find the largest number (≥10) that appears within 120 chars
    // of any billing keyword. This handles edge cases where text extraction
    // scrambles the layout beyond recognition.
    if (totalDue == null) {
      final bigNumRe = RegExp(r'[\d,]+\.\d{2}');
      final billingRe = RegExp(
        r'(?:total|outstanding|amount due|payable|statement)',
        caseSensitive: false,
      );
      double? best;
      for (final bMatch in billingRe.allMatches(lower)) {
        final start = (bMatch.start - 30).clamp(0, lower.length);
        final end = (bMatch.end + 90).clamp(0, lower.length);
        final window = lower.substring(start, end);
        for (final nMatch in bigNumRe.allMatches(window)) {
          final v = double.tryParse(nMatch.group(0)!.replaceAll(',', ''));
          if (v != null && v >= 10) {
            if (best == null || v > best) best = v;
          }
        }
      }
      // Only use if clearly a meaningful amount (≥ 50) to avoid false positives
      if (best != null && best >= 50) totalDue = best;
    }

    // ── Minimum Due ───────────────────────────────────────────────────────────
    double? minimumDue;
    final minPatterns = [
      RegExp(
        r'minimum\s+(?:amount\s+)?due\s*(?:\([₹inrrs\.]+\))?\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
      RegExp(
        r'min(?:imum)?\s+due\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
      RegExp(
        r'\bmad\b\s*[:\-]?\s*(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ),
    ];
    for (final p in minPatterns) {
      final m = p.firstMatch(lower);
      if (m != null) {
        final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null && v >= 1) {
          minimumDue = v;
          break;
        }
      }
    }
    // Multi-line minimum due
    if (minimumDue == null) {
      final mlMin = RegExp(
        r'minimum\s+(?:amount\s+)?due[^\n]{0,40}\n[^\n]{0,10}(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
        caseSensitive: false,
      ).firstMatch(lower);
      if (mlMin != null) {
        final v = double.tryParse(mlMin.group(1)!.replaceAll(',', ''));
        if (v != null && v >= 1) minimumDue = v;
      }
    }

    // ── Due Date ──────────────────────────────────────────────────────────────
    DateTime? dueDate;
    final datePatterns = [
      // Indian format: "Payment Due Date: 15-Jan-2024" / "Due Date: 15 Jan 2024"
      RegExp(
        r'(?:payment\s+due\s+date|due\s+date|pay\s+by|due\s+(?:on|by))\s*[:\-]?\s*(\d{1,2}\s*[-\/\s]\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*[-\/\s,]*\s*\d{2,4})',
        caseSensitive: false,
      ),
      // "Last date for payment: 15th Jan 2024"
      RegExp(
        r'last\s+date\s+(?:for\s+payment|to\s+pay)\s*[:\-]?\s*(\d{1,2}(?:st|nd|rd|th)?\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{2,4})',
        caseSensitive: false,
      ),
      // DD/MM/YYYY or DD-MM-YYYY format
      RegExp(
        r'(?:payment\s+due|due\s+date)\s*[:\-]?\s*(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})',
        caseSensitive: false,
      ),
      // Generic date pattern anywhere near due keywords
      RegExp(
        r'\b(\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{4})\b',
        caseSensitive: false,
      ),
      // Month DD, YYYY format: "January 15, 2024"
      RegExp(
        r'(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+\d{4}',
        caseSensitive: false,
      ),
    ];

    // Try each pattern
    for (final p in datePatterns) {
      final m = p.firstMatch(lower);
      if (m != null) {
        final dateStr = m.group(1)?.trim() ?? m.group(0)?.trim();
        if (dateStr != null) {
          dueDate = _parseDate(dateStr);
          if (dueDate != null) {
            debugPrint('📅 PDF date parsed: "$dateStr" → $dueDate');
            break;
          }
        }
      }
    }

    // Fallback: look for any date within 50 chars of "due" keyword
    if (dueDate == null) {
      final dueKeyword = RegExp(r'\bdue\b', caseSensitive: false);
      final datePattern = RegExp(
        r'(\d{1,2}\s*(?:[-\/]\s*)?(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*(?:[-\/]\s*)?\d{2,4})',
        caseSensitive: false,
      );

      for (final dueMatch in dueKeyword.allMatches(lower)) {
        final start = (dueMatch.start - 50).clamp(0, lower.length);
        final end = (dueMatch.end + 50).clamp(0, lower.length);
        final window = lower.substring(start, end);
        final dateMatch = datePattern.firstMatch(window);
        if (dateMatch != null) {
          dueDate = _parseDate(dateMatch.group(1)!.trim());
          if (dueDate != null) {
            debugPrint(
              '📅 PDF date fallback parsed: "${dateMatch.group(1)!}" → $dueDate',
            );
            break;
          }
        }
      }
    }

    // ── Card Last 4 ───────────────────────────────────────────────────────────
    // Extract the last 4 digits of the card number from the PDF statement.
    // HDFC format: "XXXX XXXX XXXX 1234" or "Card ending with 1234"
    String? cardLast4;
    final last4Patterns = [
      RegExp(
        r'(?:x{4}\s*){3}(\d{4})',
        caseSensitive: false,
      ), // XXXX XXXX XXXX 1234
      RegExp(r'(?:\*{4}\s*){3}(\d{4})'), // **** **** **** 1234
      RegExp(
        r'card\s+(?:ending|no\.?)\s*[:\-]?\s*[x\*]{0,12}\s*(\d{4})',
        caseSensitive: false,
      ),
      RegExp(
        r'\d{4}\s*[x\*]{4}\s*[x\*]{4}\s*[x\*]{2}(\d{2})',
        caseSensitive: false,
      ), // partial fallback
      RegExp(r'ending\s+(?:with\s+|in\s+)?(\d{4})', caseSensitive: false),
    ];
    for (final p in last4Patterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        cardLast4 = m.group(1);
        break;
      }
    }

    // ── Card Holder ───────────────────────────────────────────────────────────
    String? cardHolder;
    final holderPatterns = [
      RegExp(
        r'(?:card\s+holder|account\s+holder|customer\s+name|dear\s+(?:mr\.?|ms\.?|mrs\.?)?\s*)([A-Za-z]+(?:\s+[A-Za-z]+){1,3})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:name|holder)\s*[:\-]\s*([A-Za-z]+(?:\s+[A-Za-z]+){1,3})',
        caseSensitive: false,
      ),
    ];
    for (final p in holderPatterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        final match = m.group(1)?.trim();
        if (match != null && !match.toLowerCase().contains('please find')) {
          cardHolder = match;
          break;
        }
      }
    }

    // ── Bank Name ─────────────────────────────────────────────────────────────
    String? bankName;
    const knownBanks = [
      'HDFC',
      'ICICI',
      'SBI',
      'Axis',
      'Kotak',
      'IndusInd',
      'Yes Bank',
      'IDFC',
      'RBL',
      'Standard Chartered',
      'Citibank',
      'American Express',
      'Federal Bank',
      'AU Bank',
      'PNB',
      'BOB',
      'HSBC',
      'SC Bank',
    ];
    for (final bank in knownBanks) {
      if (text.toLowerCase().contains(bank.toLowerCase())) {
        bankName = bank;
        break;
      }
    }

    // Validate the extracted bill data
    final validatedData = _validateBillData(
      totalDue: totalDue,
      minimumDue: minimumDue,
      dueDate: dueDate,
      bankName: bankName,
    );

    return BillData(
      totalDue: validatedData.totalDue,
      minimumDue: validatedData.minimumDue,
      dueDate: validatedData.dueDate,
      bankName: bankName,
      cardHolder: cardHolder,
      cardLast4: cardLast4,
    );
  }

  DateTime? _parseDate(String raw) {
    try {
      final s = raw.trim().replaceAll(RegExp(r'[,]+'), '').trim();
      const monthMap = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };

      const fullMonthMap = {
        'january': 1,
        'february': 2,
        'march': 3,
        'april': 4,
        'may': 5,
        'june': 6,
        'july': 7,
        'august': 8,
        'september': 9,
        'october': 10,
        'november': 11,
        'december': 12,
      };

      // Remove ordinal suffixes: 15th → 15, 1st → 1, 2nd → 2, 3rd → 3
      String cleaned = s.replaceAll(
        RegExp(r'(\d{1,2})(?:st|nd|rd|th)\b'),
        r'$1',
      );

      // Pattern 1: DD Mon YYYY (e.g., "15 Jan 2024", "15-Jan-2024", "15/Jan/2024")
      final m1 = RegExp(
        r'(\d{1,2})\s*[-\/\s]?\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*[-\/\s,]*\s*(\d{2,4})',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (m1 != null) {
        final day = int.parse(m1.group(1)!);
        final monthStr = m1.group(2)!.toLowerCase().substring(0, 3);
        final month = monthMap[monthStr]!;
        int year = int.parse(m1.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }

      // Pattern 2: Mon DD, YYYY (e.g., "Jan 15, 2024", "January 15 2024")
      final m2 = RegExp(
        r'(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{1,2}),?\s+(\d{2,4})',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (m2 != null) {
        final monthStr = m2.group(1)!.toLowerCase();
        final month = monthStr.length <= 3
            ? monthMap[monthStr.substring(0, 3)]!
            : fullMonthMap[monthStr] ?? monthMap[monthStr.substring(0, 3)]!;
        final day = int.parse(m2.group(2)!);
        int year = int.parse(m2.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }

      // Pattern 3: DD/MM/YYYY or DD-MM-YYYY (Indian format: day first)
      final m3 = RegExp(
        r'(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})',
      ).firstMatch(cleaned);
      if (m3 != null) {
        int d = int.parse(m3.group(1)!);
        int mo = int.parse(m3.group(2)!);
        int y = int.parse(m3.group(3)!);
        if (y < 100) y += 2000;
        // Handle ambiguous formats: if month > 12, assume DD/MM (Indian format)
        if (mo > 12 && d <= 12) {
          // Swap day and month (common in US format misinterpretation)
          final temp = d;
          d = mo;
          mo = temp;
        }
        return DateTime(y, mo, d);
      }

      // Pattern 4: YYYY-MM-DD (ISO format)
      final m4 = RegExp(
        r'(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})',
      ).firstMatch(cleaned);
      if (m4 != null) {
        int y = int.parse(m4.group(1)!);
        int mo = int.parse(m4.group(2)!);
        int d = int.parse(m4.group(3)!);
        return DateTime(y, mo, d);
      }

      debugPrint('❌ Could not parse date: "$raw" (cleaned: "$cleaned")');
      return null;
    } catch (e) {
      debugPrint('❌ Date parsing error for "$raw": $e');
      return null;
    }
  }
}
