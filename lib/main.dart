import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:in_app_update/in_app_update.dart';

import 'firebase_options.dart';
import 'package:park_sg/view/splashScreen/my_splash_screen.dart';

/// Handles background Firebase messages
@pragma('vm:entry-point')
Future _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
}

/// Checks for Play Store updates
Future checkForPlayStoreUpdates(BuildContext context) async {
  try {
    print('Checking for Play Store updates...');
    AppUpdateInfo updateInfo = await InAppUpdate.checkForUpdate();

    if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
      print("Update available: Version ${updateInfo.availableVersionCode}");
      await InAppUpdate.performImmediateUpdate();
    } else {
      print("No updates available.");
    }
  } catch (e) {
    print("Failed to check for updates: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('App starting...');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print('Firebase initialized');

  // Set persistence for web to maintain login state
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    print('Firebase Auth persistence set to LOCAL for web');
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  print('Firebase messaging background handler set');

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  DateTime? _pausedTime;
  final Duration _minBackgroundDuration = const Duration(seconds: 30);
  bool _isInitialAdShown = false;

  @override
  void initState() {
    super.initState();
    print('MyApp initializing...');
    WidgetsBinding.instance.addObserver(this);

    // Check for updates after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb && Platform.isAndroid) {
        checkForPlayStoreUpdates(context);
      } else {
        print('Skipping Play Store update check — not on Android');
      }
    });


    // Listen to auth state changes for debugging
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      print('🔄 Auth state changed: ${user?.email ?? 'No user'}');
      print('📧 Email verified: ${user?.emailVerified ?? false}');
    });
  }

  @override
  void dispose() {
    print('Disposing MyApp');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SenecaGlobal Parking',

      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      debugShowCheckedModeBanner: false,
      home: const MysplashScreen(),
    );
  }
}