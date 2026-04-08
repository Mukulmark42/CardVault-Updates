import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static final UserService instance = UserService._internal();
  factory UserService() => instance;
  UserService._internal();

  Future<void> updateUserNotificationData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint("UserService: No user logged in. Skipping FCM sync.");
        return;
      }

      // Ensure we have notification permissions before getting token
      NotificationSettings settings = await _fcm.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint("UserService: Notification permission not granted by system yet.");
        // We don't return here because we want to try getting the token anyway if possible
      }

      String? token = await _fcm.getToken();
      if (token == null) {
        debugPrint("UserService: Failed to get FCM token.");
        return;
      }

      await _firestore.collection('users').doc(user.uid).set({
        'email': user.email,
        'fcmToken': token,
        'lastActive': FieldValue.serverTimestamp(),
        'platform': 'android',
      }, SetOptions(merge: true));

      debugPrint("UserService: FCM data synced for ${user.email}");
    } catch (e) {
      debugPrint("UserService: Error updating user data (Check Firestore Rules): $e");
    }
  }

  Future<void> clearUserToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint("UserService: Error clearing token: $e");
    }
  }
}
