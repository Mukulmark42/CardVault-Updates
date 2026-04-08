import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/card_model.dart';
import '../database/database_helper.dart';
import '../firebase_options.dart';
import 'package:flutter/material.dart';
import 'dart:io';

// Background message handler must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling a background message: ${message.messageId}');
}

@pragma('vm:entry-point')
void _onNotificationTappedBackground(NotificationResponse details) async {
  if (details.actionId == 'mark_paid') {
    final int? cardId = details.id;
    if (cardId != null) {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }

      final db = DatabaseHelper.instance;
      final cards = await db.getCards();
      try {
        final card = cards.firstWhere((c) => c.id == cardId);
        final updatedCard = card.rollToNextMonth();
        await db.updateCard(updatedCard);

        final FlutterLocalNotificationsPlugin notificationsPlugin =
            FlutterLocalNotificationsPlugin();
        await notificationsPlugin.cancel(cardId);
      } catch (e) {
        debugPrint('Error marking card as paid in background: $e');
      }
    }
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // Notification channel IDs
  static const String _billChannelId = 'bill_channel';
  static const String _txChannelId = 'transaction_channel';
  static const String _fcmChannelId = 'fcm_channel';

  Future<void> init() async {
    await _setupFCM();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTappedBackground,
    );

    await requestPermissions();
  }

  Future<void> _setupFCM() async {
    try {
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted FCM permission');
      }

      // Save token to Firestore so Cloud Functions can send targeted reminders
      final token = await _fcm.getToken();
      debugPrint('🔥 FCM Token: $token');
      if (token != null) await _saveFcmToken(token);

      // Keep token fresh — devices can get a new token at any time
      _fcm.onTokenRefresh.listen((newToken) async {
        debugPrint('🔄 FCM token refreshed');
        await _saveFcmToken(newToken);
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Received foreground message: ${message.notification?.title}');
        _showLocalNotification(message);
      });

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Notification clicked! Data: ${message.data}');
      });
    } catch (e) {
      debugPrint('FCM setup failed: $e');
    }
  }

  /// Saves or updates the FCM token in Firestore under users/{uid}/fcmToken.
  /// This is read by the Cloud Function `dailyBillChecker` to send reminders.
  Future<void> _saveFcmToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'fcmToken': token, 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
      debugPrint('✅ FCM token saved to Firestore for user ${user.uid}');
    } catch (e) {
      debugPrint('⚠️ Failed to save FCM token: $e');
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _notificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _fcmChannelId,
            'Cloud Notifications',
            channelDescription: 'Push notifications from Firebase',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  }

  void _onNotificationTapped(NotificationResponse details) async {
    if (details.actionId == 'mark_paid') {
      final int? cardId = details.id;
      if (cardId != null) {
        final db = DatabaseHelper.instance;
        final cards = await db.getCards();
        try {
          final card = cards.firstWhere((c) => c.id == cardId);
          final updatedCard = card.rollToNextMonth();
          await db.updateCard(updatedCard);
          await _notificationsPlugin.cancel(cardId);
        } catch (e) {
          debugPrint('Error marking card as paid: $e');
        }
      }
    }
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.requestNotificationsPermission();
    }
  }

  // ─── Instant Bill Detected Notification ─────────────────────────────────────

  /// Fires a local notification immediately when a new credit card bill is
  /// detected and parsed from a Gmail email.
  Future<void> showBillDetectedNotification(
    String bank,
    double amount,
    String? dueDate,
  ) async {
    // Skip noisy/incomplete notifications — must have a real amount OR a due date
    if (amount <= 0 && dueDate == null) {
      debugPrint('⏭️ Skipping bill notification — no amount and no due date');
      return;
    }
    try {
      final formattedAmount = amount > 0 ? '₹${amount.toStringAsFixed(0)}' : 'Amount pending';
      final body = dueDate != null
          ? '$formattedAmount due on $dueDate'
          : '$formattedAmount bill detected';

      await _notificationsPlugin.show(
        // Unique ID based on bank name hash to avoid duplicates across re-syncs
        bank.hashCode.abs(),
        '💳 $bank Bill Detected',
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _billChannelId,
            'Bill Alerts',
            channelDescription: 'Notifications for detected credit card bills',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF6366F1),
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
      debugPrint('🔔 Bill notification shown for $bank');
    } catch (e) {
      debugPrint('Error showing bill notification: $e');
    }
  }

  // ─── Instant Transaction Detected Notification ───────────────────────────────

  /// Fires a local notification immediately when a new transaction is
  /// detected and parsed from a Gmail email.
  Future<void> showTransactionDetectedNotification(
    String vendor,
    double amount,
    String bank,
  ) async {
    try {
      final formattedAmount = '₹${amount.toStringAsFixed(0)}';
      final body = '$formattedAmount spent at $vendor via $bank';

      await _notificationsPlugin.show(
        // Unique ID combining vendor and amount hash
        '${vendor}_$amount'.hashCode.abs() % 100000,
        '🛍️ New Transaction',
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _txChannelId,
            'Transaction Alerts',
            channelDescription: 'Notifications for detected transactions',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF10B981),
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
      debugPrint('🔔 Transaction notification shown: $vendor ₹$amount');
    } catch (e) {
      debugPrint('Error showing transaction notification: $e');
    }
  }

  // ─── Due Date Scheduling (delegated to FCM) ──────────────────────────────────

  Future<void> scheduleDueDateNotification(CardModel card) async {
    // No-op for local alarms — reminders come via Firebase Cloud Messaging.
  }

  Future<void> cancelNotification(int cardId) async {
    await _notificationsPlugin.cancel(cardId);
  }

  Future<void> scheduleAllPendingNotifications() async {
    // No-op — handled via FCM.
  }

  // ─── Payment Confirmed Notification ─────────────────────────────────────────

  /// Fires a local notification when a payment confirmation email is detected
  /// and the card has been auto-marked as paid.
  Future<void> showPaymentConfirmedNotification(String bank) async {
    try {
      const paymentChannelId = 'payment_channel';
      await _notificationsPlugin.show(
        '${bank}_paid'.hashCode.abs() % 100000,
        '✅ $bank Payment Confirmed',
        'Your bill has been paid. Due date reset to next cycle.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            paymentChannelId,
            'Payment Confirmations',
            channelDescription: 'Notifications when a bill payment is detected',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            color: Color(0xFF10B981),
          ),
        ),
      );
      debugPrint('🔔 Payment confirmed notification shown for $bank');
    } catch (e) {
      debugPrint('Error showing payment notification: $e');
    }
  }
}
