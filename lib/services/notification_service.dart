import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/card_model.dart';
import '../database/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) async {
        if (details.actionId == 'mark_paid') {
          final int? cardId = details.id;
          if (cardId != null) {
            final db = DatabaseHelper.instance;
            final cards = await db.getCards();
            try {
              final card = cards.firstWhere((c) => c.id == cardId);
              final updatedCard = card.copyWith(isPaid: true);
              await db.updateCard(updatedCard);
              await _notificationsPlugin.cancel(cardId);
            } catch (e) {
              debugPrint("Error marking card as paid from notification: $e");
            }
          }
        } else if (details.actionId == 'will_pay') {
          await _notificationsPlugin.cancel(details.id ?? 0);
        }
      },
    );

    // Request permissions for Android 13+
    await requestPermissions();
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.requestNotificationsPermission();
      await androidImplementation?.requestExactAlarmsPermission();
    }
  }

  Future<void> scheduleDueDateNotification(CardModel card) async {
    if (card.dueDate == null || card.isPaid || card.id == null) return;

    final DateTime dueDateTime = DateTime.parse(card.dueDate!);
    final DateTime notificationTime = dueDateTime.subtract(const Duration(days: 3));

    if (notificationTime.isBefore(DateTime.now())) return;

    await _notificationsPlugin.zonedSchedule(
      card.id!,
      'Bill Payment Reminder 💳',
      'Your ${card.bank} bill is due on ${DateFormat('dd MMMM').format(dueDateTime)}. Don\'t forget to pay!',
      tz.TZDateTime.from(notificationTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'due_date_channel',
          'Due Date Reminders',
          importance: Importance.max,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'mark_paid',
              'Mark as Paid',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'will_pay',
              'Will Pay',
              showsUserInterface: false,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
  
  Future<void> scheduleAllPendingNotifications() async {
    final cards = await DatabaseHelper.instance.getCards();
    for (var card in cards) {
      if (!card.isPaid && card.dueDate != null) {
        await scheduleDueDateNotification(card);
      }
    }
  }
}
