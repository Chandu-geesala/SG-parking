import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../viewModel/authService.dart'; // Update import path as needed
import '../admin/adminHome.dart';
import '../auth_screens/auth_screen.dart';
import '../home.dart';
import 'offline_page.dart';

class MysplashScreen extends StatefulWidget {
  const MysplashScreen({super.key});

  @override
  State<MysplashScreen> createState() => _MysplashScreenState();
}

class _MysplashScreenState extends State<MysplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _authService.initialize();
    _initTimer();
  }

  @override
  void dispose() {
    _authService.dispose();
    super.dispose();
  }

  void _initTimer() {
    Timer(const Duration(milliseconds: 1500), () async {
      await _checkInternetAndNavigate();
    });
  }

  /// Check internet connectivity
  Future<bool> _checkInternetConnection() async {
    try {
      if (kIsWeb) {
        // For web: Try to access Firebase Auth
        await FirebaseAuth.instance.currentUser?.reload();
        return true;
      } else {
        // For mobile: Quick DNS lookup
        final result = await InternetAddress.lookup('google.com')
            .timeout(Duration(seconds: 3));
        return result.isNotEmpty;
      }
    } catch (e) {
      print('❌ Internet check failed: $e');
      return false;
    }
  }

  Future<void> _checkInternetAndNavigate() async {
    // Check internet connection
    bool hasInternet = await _checkInternetConnection();
    _authService.setConnectionState(hasInternet);

    if (!hasInternet) {
      print('🌐 No internet connection, navigating to offline page');
      _navigateToPage(OfflinePage());
      return;
    }

    // Navigate based on user authentication state
    await _navigateBasedOnAuthState();
  }

  Future<void> _navigateBasedOnAuthState() async {
    try {
      print('🔍 Checking authentication state...');

      // Wait for auth state to be ready
      await FirebaseAuth.instance.authStateChanges().first;
      User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        print('❌ No authenticated user, navigating to auth screen');
        _navigateToPage(LandingPage());
        return;
      }

      print('✅ User authenticated: ${user.email}');

      // Get user data and check type
      final userData = await _authService.getUserData(user.email!);

      if (userData == null) {
        print('❌ User data not found in Firestore, signing out');
        await _authService.signOut();
        _navigateToPage(LandingPage());
        return;
      }

      final userType = userData['userType']?.toString().toLowerCase() ?? 'user';
      final isAdmin = userType == 'admin';

      print('🏷️ User type: $userType, isAdmin: $isAdmin');

      // Update last login
      _authService.updateLastLogin(user.email!);

      // Navigate based on user type
      if (isAdmin) {
        print('🛡️ Admin user, navigating to AdminHomeScreen');
        _navigateToPage(AdminHomeScreen());
      } else {
        print('👤 Regular user, navigating to HomeScreen');
        _navigateToPage(HomeScreen());
      }

    } catch (e) {
      print('❌ Error in splash screen navigation: $e');
      // Fallback to auth screen on any error
      _navigateToPage(LandingPage());
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
            // App Logo
            Image.asset(
              'assets/logo.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 32),

            // Loading indicator
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                isDarkMode ? Colors.white : const Color(0xFF6C5CE7),
              ),
              strokeWidth: 3,
            ),

            const SizedBox(height: 24),

            // Loading text
            Text(
              'Loading...',
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : Colors.grey[600],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}