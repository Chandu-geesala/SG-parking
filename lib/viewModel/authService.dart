import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  // Platform check
  bool get isWeb => kIsWeb;
  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Cache for user data
  static Map<String, dynamic>? _userDataCache;
  static DateTime? _userDataCacheTime;
  static const Duration _cacheExpiry = Duration(minutes: 30);

  // Connection state
  bool _isOnline = true;

  // FCM token management (mobile only)
  String? _currentFCMToken;
  DateTime? _fcmTokenTimestamp;


  /// Main sign-in method that handles the complete flow
  Future<Map<String, dynamic>> signInWithEmail(String email, String password) async {
    try {
      print('🔐 Starting sign-in process for: $email');

      // Step 1: Authenticate with Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      User? user = userCredential.user;
      if (user == null) {
        throw Exception("Authentication failed. Please try again.");
      }

      print('✅ Firebase Auth successful for: $email');

      // Step 2: Check if user exists in Firestore users collection
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .get();

      if (!userDoc.exists) {
        // User authenticated but no user document found
        await FirebaseAuth.instance.signOut();
        return {
          'success': false,
          'message': 'User not found in system. Please contact admin.',
        };
      }

      final userData = userDoc.data()!;
      print('✅ User document found in Firestore');

      // Step 3: Cache user data
      _userDataCache = userData;
      _userDataCacheTime = DateTime.now();

      // Step 4: Check user type and determine navigation
      final userType = userData['userType']?.toString().toLowerCase() ?? 'user';
      final isAdmin = userType == 'admin';

      print('✅ User type: $userType, isAdmin: $isAdmin');

      // Step 5: Cache user preference (for mobile)
      if (!isWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userType', userType);
        await prefs.setString('userEmail', email);
      }


      return {
        'success': true,
        'user': user,
        'userData': userData,
        'isAdmin': isAdmin,
        'userType': userType,
        'message': isAdmin ? 'Admin login successful!' : 'Login successful!',
      };

    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      return _handleAuthError(e);
    } catch (e) {
      print('❌ General sign-in error: $e');
      return {
        'success': false,
        'message': 'Login failed: ${e.toString()}',
      };
    }
  }

  /// Handle Firebase Auth errors with user-friendly messages
  Map<String, dynamic> _handleAuthError(FirebaseAuthException e) {
    String message;
    switch (e.code) {
      case 'user-not-found':
        message = 'No account found with this email. Please contact admin.';
        break;
      case 'wrong-password':
        message = 'Incorrect password. Please try again.';
        break;
      case 'invalid-email':
        message = 'Invalid email address format.';
        break;
      case 'user-disabled':
        message = 'This account has been disabled.';
        break;
      case 'too-many-requests':
        message = 'Too many failed attempts. Please try again later.';
        break;
      case 'network-request-failed':
        message = 'Network error. Please check your internet connection.';
        break;
      case 'invalid-credential':
        message = 'Invalid email or password. Please try again.';
        break;
      default:
        message = 'Login failed. Please try again.';
    }

    return {
      'success': false,
      'message': message,
      'error_code': e.code,
    };
  }

  /// Get cached user data or fetch from Firestore
  Future<Map<String, dynamic>?> getUserData(String email) async {
    try {
      // Return cached data if still valid
      if (_userDataCache != null &&
          _userDataCacheTime != null &&
          DateTime.now().difference(_userDataCacheTime!) < _cacheExpiry) {
        print('✅ User data retrieved from cache');
        return _userDataCache;
      }

      // Fetch from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .get();

      if (userDoc.exists) {
        _userDataCache = userDoc.data();
        _userDataCacheTime = DateTime.now();
        print('✅ User data retrieved from Firestore and cached');
        return _userDataCache;
      }

      return null;
    } catch (e) {
      print('❌ Error getting user data: $e');
      return null;
    }
  }

  /// Check if current user is admin
  Future<bool> isCurrentUserAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final userData = await getUserData(user.email!);
      if (userData == null) return false;

      final userType = userData['userType']?.toString().toLowerCase() ?? 'user';
      return userType == 'admin';
    } catch (e) {
      print('❌ Error checking admin status: $e');
      return false;
    }
  }

  /// Get current user type from cache or Firestore
  Future<String> getCurrentUserType() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'user';

      // Try cache first (mobile)
      if (!isWeb) {
        final prefs = await SharedPreferences.getInstance();
        final cachedType = prefs.getString('userType');
        if (cachedType != null) {
          return cachedType;
        }
      }

      // Fetch from Firestore
      final userData = await getUserData(user.email!);
      if (userData == null) return 'user';

      return userData['userType']?.toString().toLowerCase() ?? 'user';
    } catch (e) {
      print('❌ Error getting user type: $e');
      return 'user';
    }
  }



  /// Update last login timestamp
  Future<void> updateLastLogin(String email) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .update({
        'lastLoginAt': FieldValue.serverTimestamp(),
        'platform': isWeb ? 'web' : 'mobile',
      });
    } catch (e) {
      print('❌ Error updating last login: $e');
    }
  }

  /// Sign out user and clear all caches
  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();

      // Clear caches
      _userDataCache = null;
      _userDataCacheTime = null;

      // Clear mobile preferences
      if (!isWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('userType');
        await prefs.remove('userEmail');
      }

      print('✅ User signed out and caches cleared');
    } catch (e) {
      print('❌ Error during sign out: $e');
    }
  }



  /// Initialize the service
  void initialize() {
    print('🚀 AuthService initialized for ${isWeb ? 'web' : 'mobile'}');
  }

  /// Set connection state
  void setConnectionState(bool isOnline) {
    _isOnline = isOnline;
    print('🌐 Connection state: ${isOnline ? 'Online' : 'Offline'}');
  }

  /// Get connection state
  bool get isOnline => _isOnline;

  /// Clear all caches
  void clearCaches() {
    _userDataCache = null;
    _userDataCacheTime = null;
    print('🗑️ All caches cleared');
  }

  /// Dispose and cleanup
  void dispose() {
    clearCaches();
    print('🧹 AuthService disposed');
  }

  /// Debug method to print current state
  Future<void> debugPrintState() async {
    print('🔍 === AUTH SERVICE DEBUG STATE ===');
    print('📱 Platform: ${isWeb ? 'Web' : 'Mobile'}');

    final user = FirebaseAuth.instance.currentUser;
    print('👤 Current User: ${user?.email ?? 'None'}');

    if (user != null) {
      final userType = await getCurrentUserType();
      final isAdmin = await isCurrentUserAdmin();
      print('🏷️ User Type: $userType');
      print('🛡️ Is Admin: $isAdmin');
    }

    print('💾 Cache Status: ${_userDataCache != null ? 'Active' : 'Empty'}');
    print('🌐 Online Status: $_isOnline');
    print('🔍 ================================');
  }
}