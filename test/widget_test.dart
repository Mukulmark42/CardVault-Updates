// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cardvault/main.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // We provide a dummy future to satisfy the required parameter.
    // Note: In a real test environment, you would use a mock for Firebase.
    final firebaseInit = Future.value(); 

    // Build our app and trigger a frame.
    // Since we are passing a dynamic future, we use 'as Future<FirebaseApp>' 
    // to match the expected type if necessary, or just use a generic Future.
    await tester.pumpWidget(CardVault(firebaseInit: firebaseInit as Future<FirebaseApp>));

    // Verify that the app starts by showing either a loading indicator or the login screen.
    expect(find.byType(CircularProgressIndicator), findsAny);
  });
}
