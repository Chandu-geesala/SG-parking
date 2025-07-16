import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../viewModel/authService.dart';
import '../admin/adminHome.dart';
import '../auth_screens/auth_screen.dart';
import '../auth_screens/signUp.dart';
import '../auth_screens/verify.dart';
import '../home.dart';
import 'onboarding_page.dart';
import 'offline_page.dart';

class MysplashScreen extends StatefulWidget {
  const MysplashScreen({super.key});

  @override
  State<MysplashScreen> createState() => _MysplashScreenState();
}

class _MysplashScreenState extends State<MysplashScreen> {
  final SignUpService _signUpService = SignUpService();

  @override
  void initState() {
    super.initState();
    initTimer();
  }

  void initTimer() async {
    Timer(const Duration(seconds: 2), () async {
      await _checkInternetAndNavigate();
    });
  }

  Future<void> _checkInternetAndNavigate() async {
    // Simple and reliable internet check
    bool hasInternet = await _checkInternetConnection();

    if (!hasInternet) {
      print('🌐 No internet connection, navigating to offline page');
      _navigateToPage(OfflinePage());
      return;
    }

    // If internet is available, proceed with normal navigation
    await _navigateBasedOnUserState();
  }

  // SIMPLE AND RELIABLE INTERNET CHECK
  Future<bool> _checkInternetConnection() async {
    try {
      if (kIsWeb) {
        // For web: Try to access Firebase Auth (it's what we need anyway)
        await FirebaseAuth.instance.currentUser?.reload();
        return true;
      } else {
        // For mobile: Quick DNS lookup with multiple fallbacks
        final hosts = ['google.com', 'firebase.google.com', '8.8.8.8'];

        for (String host in hosts) {
          try {
            final result = await InternetAddress.lookup(host)
                .timeout(Duration(seconds: 2));
            if (result.isNotEmpty) {
              return true;
            }
          } catch (e) {
            continue; // Try next host
          }
        }
        return false;
      }
    } catch (e) {
      print('❌ Internet check failed: $e');
      return false;
    }
  }

  Future<void> _navigateBasedOnUserState() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      bool isIntroCompleted = true;

      // Wait for auth state to be ready
      await FirebaseAuth.instance.authStateChanges().first;
      User? user = FirebaseAuth.instance.currentUser;

      // Force reload user data to get latest state
      if (user != null) {
        await user.reload();
        user = FirebaseAuth.instance.currentUser;
      }

      print('🔍 Splash Screen Navigation Check:');
      print('📖 Intro completed: $isIntroCompleted');
      print('👤 User logged in: ${user != null}');
      print('✅ Email verified: ${user?.emailVerified}');

      if (user != null) {
        bool isAdmin = await isCurrentUserAdmin();
        if (isAdmin) {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('priority', 'admin');
          print('🛡️ User is admin, navigating to AdminHomeScreen');
          _navigateToPage(AdminHomeScreen());
          return;
        } else if (user.emailVerified) {
          print('🏠 Navigating to home screen (email verified)');
          _navigateToPage(HomeScreen());
          return;
        } else {
          print('✉️ Navigating to verify email page (user logged in but not verified)');
          _navigateToPage(VerifyEmailPage(email: user.email ?? ''));
          return;
        }
      }

      // No logged in user: check pending signup
      print('🔍 Checking for pending signup data...');
      bool hasPendingSignup = await _signUpService.hasPendingSignup();

      if (hasPendingSignup) {
        Map<String, String> pendingData = await _signUpService.getPendingSignupData();
        String? pendingEmail = pendingData['email'];

        print('⏳ Found pending signup, navigating to verify email page');
        _navigateToPage(VerifyEmailPage(email: pendingEmail ?? ''));
        return;
      }

      // Default to landing page
      print('🔐 No pending signup, navigating to auth screen');
      _navigateToPage(LandingPage());

    } catch (e) {
      print('❌ Error in splash screen navigation: $e');
      _navigateToPage(LandingPage());
    }
  }

  Future<bool> isCurrentUserAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(user.email)
          .get();
      return adminDoc.exists;
    } catch (e) {
      print('❌ Error checking admin status: $e');
      return false;
    }
  }

  void _navigateToPage(Widget page) {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => page),
            (Route<dynamic> route) => false,
      );

    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = MediaQuery.of(context).platformBrightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
            ),
            const SizedBox(height: 20),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                isDarkMode ? Colors.white : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}