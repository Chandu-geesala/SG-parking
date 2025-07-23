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
    // OPTIMIZATION 3: Initialize SignUpService for optimizations
    _signUpService.initialize();
    initTimer();
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }


  void initTimer() async {
    // OPTIMIZATION 4: Reduced splash delay for better UX
    Timer(const Duration(milliseconds: 1500), () async {
      await _checkInternetAndNavigate();
    });
  }

  bool _isOnline = true;
  Timer? _connectivityTimer;

  // OPTIMIZATION 2: Cache admin status to prevent repeated Firestore calls
  static bool? _cachedAdminStatus;
  static String? _cachedAdminEmail;
  static DateTime? _adminCacheTime;
  static const Duration _adminCacheExpiry = Duration(hours: 1); // Cache for 1 hour




  Future<void> _checkInternetAndNavigate() async {
    // OPTIMIZATION 5: Enhanced internet check with caching
    bool hasInternet = await _checkInternetConnection();
    _isOnline = hasInternet;

    // Update SignUpService connectivity state
    _signUpService.setConnectionState(hasInternet);

    if (!hasInternet) {
      print('🌐 No internet connection, navigating to offline page');
      _navigateToPage(OfflinePage());
      return;
    }

    // If internet is available, proceed with optimized navigation
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

      if (user != null) {
        // Enhanced user reload with retry logic
        for (int i = 0; i < 3; i++) {
          try {
            await user?.reload();
            user = FirebaseAuth.instance.currentUser;
            print('🔄 User reload attempt ${i + 1}: emailVerified = ${user?.emailVerified}');

            if (user?.emailVerified == true) {
              break; // Successfully got verified state
            }

            if (i < 2) { // Don't delay on last attempt
              await Future.delayed(Duration(milliseconds: 500));
            }
          } catch (e) {
            print('⚠️ User reload attempt ${i + 1} failed: $e');
          }
        }
      }

      print('🔍 Splash Screen Navigation Check:');
      print('📖 Intro completed: $isIntroCompleted');
      print('👤 User logged in: ${user != null}');
      print('✅ Email verified: ${user?.emailVerified}');

      if (user != null) {
        bool isAdmin = await _signUpService.getAdminStatus();

        if (isAdmin) {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('priority', 'admin');
          print('🛡️ User is admin, navigating to AdminHomeScreen');
          _navigateToPage(AdminHomeScreen());
          return;
        } else if (user.emailVerified) {
          // NEW: Check for pending signup data even when logged in and verified
          print('🔍 User verified, checking for pending signup data...');
          bool hasPendingSignup = await _signUpService.hasPendingSignup();

          if (hasPendingSignup) {
            Map<String, String> pendingData = await _signUpService.getPendingSignupData();
            String? pendingEmail = pendingData['email'];

            print('⏳ Found pending signup for verified user, navigating to verify email page');
            _navigateToPage(VerifyEmailPage(email: pendingEmail ?? ''));
            return;
          } else {
            print('🏠 No pending signup, navigating to home screen (email verified)');
            _navigateToPage(HomeScreen());
            return;
          }
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
      // Clear any pending timers
      _connectivityTimer?.cancel();

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