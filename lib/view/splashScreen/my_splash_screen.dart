import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../viewModel/authService.dart';
import '../admin/adminHome.dart';
import '../auth_screens/auth_screen.dart';
import '../auth_screens/signUp.dart';
import '../auth_screens/verify.dart';
import '../home.dart';
import 'onboarding_page.dart';

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
      await _navigateBasedOnUserState();
    });
  }

  Future<void> _navigateBasedOnUserState() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      bool isIntroCompleted =  true;

      User? user = FirebaseAuth.instance.currentUser;
      await user?.reload();

      print('🔍 Splash Screen Navigation Check:');
      print('📖 Intro completed: $isIntroCompleted');
      print('👤 User logged in: ${user != null}');
      print('✅ Email verified: ${user?.emailVerified}');



      if (user != null) {
        bool isAdmin = await isCurrentUserAdmin();
        if (isAdmin) {
          // Optional: Store priority in prefs here if you want
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


      // 2. No logged in user: check pending signup
      print('🔍 Checking for pending signup data...');
      bool hasPendingSignup = await _signUpService.hasPendingSignup();

      if (hasPendingSignup) {
        // Load email from saved data
        Map<String, String> pendingData = await _signUpService.getPendingSignupData();
        String? pendingEmail = pendingData['email'];

        print('⏳ Found pending signup, navigating to verify email page');
        _navigateToPage(VerifyEmailPage(email: pendingEmail ?? ''));
        return;
      }

      // 3. Default to landing page
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

    final adminDoc = await FirebaseFirestore.instance.collection('admins').doc(user.email).get();
    return adminDoc.exists;
  }




  void _navigateToPage(Widget page) {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => page),
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
