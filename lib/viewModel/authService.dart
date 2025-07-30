import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  // SECTION 1: CONSTANTS AND CONFIGURATION

  static const Duration _cacheExpiry = Duration(minutes: 30);
  static const Duration _fcmTokenExpiry = Duration(hours: 12);
  static const int _maxRetryAttempts = 3;

  // SECTION 2: PLATFORM AND CONNECTION STATE

  bool get isWeb => kIsWeb;
  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  // SECTION 3: CACHE MANAGEMENT (Firebase Cost Reduction)

  static Map<String, dynamic>? _userDataCache;
  static DateTime? _userDataCacheTime;
  static Map<String, bool> _adminStatusCache = {};
  static Map<String, String> _userTypeCache = {};
  static Map<String, DateTime> _cacheTimestamps = {};

  // SECTION 4: FCM TOKEN MANAGEMENT

  String? _currentFCMToken;
  DateTime? _fcmTokenTimestamp;

  // SECTION 5: INITIALIZATION AND CONFIGURATION

  /// Initialize the service
  void initialize() {
    _clearExpiredCaches();
  }

  /// Set connection state
  void setConnectionState(bool isOnline) {
    _isOnline = isOnline;
  }

  // SECTION 6: MAIN AUTHENTICATION METHODS

  /// Main sign-in method with optimized Firebase calls
  Future<Map<String, dynamic>> signInWithEmail(String email, String password) async {
    try {
      // Step 1: Firebase Auth (single operation)
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      User? user = userCredential.user;
      if (user == null) {
        throw Exception("Authentication failed");
      }

      // Step 2: Single Firestore read operation
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .get();

      if (!userDoc.exists) {
        await FirebaseAuth.instance.signOut();
        return {
          'success': false,
          'message': 'User not found in system. Contact admin.',
        };
      }

      final userData = userDoc.data()!;
      final userType = userData['userType']?.toString().toLowerCase() ?? 'user';
      final isAdmin = userType == 'admin';

      // Step 3: Cache all relevant data in single operation
      await _cacheUserData(email, userData, userType, isAdmin);

      // Step 4: Update last login (fire-and-forget to reduce wait time)
      _updateLastLoginAsync(email);

      return {
        'success': true,
        'user': user,
        'userData': userData,
        'isAdmin': isAdmin,
        'userType': userType,
        'message': isAdmin ? 'Admin login successful!' : 'Login successful!',
      };

    } on FirebaseAuthException catch (e) {
      return _handleAuthError(e);
    } catch (e) {
      return {
        'success': false,
        'message': 'Login failed: ${e.toString()}',
      };
    }
  }

  /// Sign out user and clear all caches
  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      _clearAllCaches();

      if (isMobile) {
        final prefs = await SharedPreferences.getInstance();
        await Future.wait([
          prefs.remove('userType'),
          prefs.remove('userEmail'),
        ]);
      }
    } catch (e) {
      // Silent fail for sign out
    }
  }

  // SECTION 7: USER DATA RETRIEVAL (Optimized Caching)

  /// Get cached user data or fetch from Firestore with intelligent caching
  Future<Map<String, dynamic>?> getUserData(String email) async {
    try {
      // Check cache validity first
      if (_isUserDataCacheValid(email)) {
        return _userDataCache;
      }

      // Fetch from Firestore only if cache is invalid
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        _userDataCache = userData;
        _userDataCacheTime = DateTime.now();
        _cacheTimestamps[email] = DateTime.now();
        return userData;
      }

      return null;
    } catch (e) {
      return _userDataCache; // Return cached data on error
    }
  }

  /// Get current user type with multi-level caching
  Future<String> getCurrentUserType() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'user';

      final email = user.email!;

      // Level 1: Memory cache
      if (_userTypeCache.containsKey(email) && _isCacheValid(email)) {
        return _userTypeCache[email]!;
      }

      // Level 2: Local storage (mobile only)
      if (isMobile) {
        final prefs = await SharedPreferences.getInstance();
        final cachedType = prefs.getString('userType');
        if (cachedType != null) {
          _userTypeCache[email] = cachedType;
          _cacheTimestamps[email] = DateTime.now();
          return cachedType;
        }
      }

      // Level 3: Firestore (last resort)
      final userData = await getUserData(email);
      if (userData == null) return 'user';

      final userType = userData['userType']?.toString().toLowerCase() ?? 'user';
      _userTypeCache[email] = userType;
      _cacheTimestamps[email] = DateTime.now();

      return userType;
    } catch (e) {
      return 'user';
    }
  }

  /// Check if current user is admin with caching
  Future<bool> isCurrentUserAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final email = user.email!;

      // Check memory cache first
      if (_adminStatusCache.containsKey(email) && _isCacheValid(email)) {
        return _adminStatusCache[email]!;
      }

      // Get user type and determine admin status
      final userType = await getCurrentUserType();
      final isAdmin = userType == 'admin';

      // Cache the result
      _adminStatusCache[email] = isAdmin;
      _cacheTimestamps[email] = DateTime.now();

      return isAdmin;
    } catch (e) {
      return false;
    }
  }

  // SECTION 8: ERROR HANDLING

  /// Handle Firebase Auth errors with user-friendly messages
  Map<String, dynamic> _handleAuthError(FirebaseAuthException e) {
    String message;
    switch (e.code) {
      case 'user-not-found':
        message = 'No account found with this email. Contact admin.';
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
        message = 'Too many failed attempts. Try again later.';
        break;
      case 'network-request-failed':
        message = 'Network error. Check your internet connection.';
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

  // SECTION 9: CACHE MANAGEMENT UTILITIES

  /// Cache user data efficiently
  Future<void> _cacheUserData(String email, Map<String, dynamic> userData, String userType, bool isAdmin) async {
    // Memory cache
    _userDataCache = userData;
    _userDataCacheTime = DateTime.now();
    _userTypeCache[email] = userType;
    _adminStatusCache[email] = isAdmin;
    _cacheTimestamps[email] = DateTime.now();

    // Local storage cache (mobile only)
    if (isMobile) {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString('userType', userType),
        prefs.setString('userEmail', email),
      ]);
    }
  }

  /// Check if user data cache is valid
  bool _isUserDataCacheValid(String email) {
    return _userDataCache != null &&
        _userDataCacheTime != null &&
        DateTime.now().difference(_userDataCacheTime!) < _cacheExpiry &&
        _cacheTimestamps.containsKey(email) &&
        DateTime.now().difference(_cacheTimestamps[email]!) < _cacheExpiry;
  }

  /// Check if general cache is valid for email
  bool _isCacheValid(String email) {
    return _cacheTimestamps.containsKey(email) &&
        DateTime.now().difference(_cacheTimestamps[email]!) < _cacheExpiry;
  }

  /// Clear expired caches to free memory
  void _clearExpiredCaches() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (var entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheExpiry) {
        expiredKeys.add(entry.key);
      }
    }

    for (String key in expiredKeys) {
      _cacheTimestamps.remove(key);
      _userTypeCache.remove(key);
      _adminStatusCache.remove(key);
    }
  }

  /// Clear all caches
  void _clearAllCaches() {
    _userDataCache = null;
    _userDataCacheTime = null;
    _userTypeCache.clear();
    _adminStatusCache.clear();
    _cacheTimestamps.clear();
  }

  /// Manual cache clearing
  void clearCaches() {
    _clearAllCaches();
  }

  // SECTION 10: BACKGROUND OPERATIONS

  /// Update last login asynchronously to reduce wait time
  void _updateLastLoginAsync(String email) {
    // Fire-and-forget operation to avoid blocking sign-in
    FirebaseFirestore.instance
        .collection('users')
        .doc(email)
        .update({
      'lastLoginAt': FieldValue.serverTimestamp(),
      'platform': isWeb ? 'web' : 'mobile',
    }).catchError((error) {
      // Silent fail - not critical for user experience
    });
  }

  // SECTION 11: CLEANUP AND DISPOSAL

  /// Dispose and cleanup
  void dispose() {
    _clearAllCaches();
  }
}
