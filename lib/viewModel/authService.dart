import 'dart:io';
import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:universal_html/html.dart' as html;

class SignUpService {
  static const String _signupDataKey = 'signup_data';
  static const String _signupStageKey = 'signup_stage';
  static const String _adminStatusKey = 'admin_status';
  static const String _adminCacheExpiryKey = 'admin_cache_expiry';
  static const Duration _adminCacheExpiry = Duration(hours: 24);

  // Signup stages
  static const String stageInitial = 'initial';
  static const String stageEmailSent = 'email_sent';
  static const String stageCompleted = 'completed';

  // In-memory caches
  static String? _webTempId;
  static Map<String, String> _webSignupData = {};
  static String _webSignupStage = stageInitial;
  static bool? _cachedAdminStatus;
  static DateTime? _adminStatusCacheTime;
  static Map<String, dynamic>? _userDocCache;
  static DateTime? _userDocCacheTime;

  // Email verification optimization
  DateTime? _lastVerificationCheck;
  bool? _lastVerificationResult;
  static const Duration _verificationCacheWindow = Duration(seconds: 10);

  // FCM token management
  String? _currentFCMToken;
  DateTime? _fcmTokenTimestamp;
  Timer? _fcmTokenUpdateTimer;

  // Connection state
  bool _isOnline = true;

  // Platform check
  bool get isWeb => kIsWeb;
  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // FIXED: Improved admin status check with better error handling
  Future<bool> getAdminStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // Check in-memory cache first
      if (_cachedAdminStatus != null &&
          _adminStatusCacheTime != null &&
          DateTime.now().difference(_adminStatusCacheTime!) < _adminCacheExpiry) {
        print('✅ Admin status from memory cache: $_cachedAdminStatus');
        return _cachedAdminStatus!;
      }

      if (isWeb) {
        // For web, check Firestore but cache the result
        final adminDoc = await FirebaseFirestore.instance
            .collection('admins')
            .doc(user.email!)
            .get();

        _cachedAdminStatus = adminDoc.exists;
        _adminStatusCacheTime = DateTime.now();

        print('✅ Admin status from Firestore: $_cachedAdminStatus (cached)');
        return adminDoc.exists;
      } else {
        // For mobile, first check SharedPreferences cache
        final prefs = await SharedPreferences.getInstance();
        final cachedStatus = prefs.getString(_adminStatusKey);
        final cacheExpiry = prefs.getInt(_adminCacheExpiryKey) ?? 0;

        if (cachedStatus != null && DateTime.now().millisecondsSinceEpoch < cacheExpiry) {
          _cachedAdminStatus = cachedStatus == 'admin';
          print('✅ Admin status from SharedPreferences cache: $_cachedAdminStatus');
          return _cachedAdminStatus!;
        }

        // If cache expired, check Firestore and update cache
        final adminDoc = await FirebaseFirestore.instance
            .collection('admins')
            .doc(user.email!)
            .get();

        _cachedAdminStatus = adminDoc.exists;
        _adminStatusCacheTime = DateTime.now();

        // Update SharedPreferences cache
        await prefs.setString(_adminStatusKey, adminDoc.exists ? 'admin' : 'user');
        await prefs.setInt(_adminCacheExpiryKey,
            DateTime.now().add(_adminCacheExpiry).millisecondsSinceEpoch);

        print('✅ Admin status from Firestore: $_cachedAdminStatus (cached)');
        return adminDoc.exists;
      }
    } catch (e) {
      print('❌ Error getting admin status: $e');
      // Don't cache errors, return false and let subsequent calls retry
      return false;
    }
  }

  // FIXED: Simplified user/admin check - removed batch operations that might cause issues
  Future<Map<String, dynamic>> checkUserExistsAndGetInfo(String email) async {
    try {
      // Check user document first
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .get();

      // Check admin document separately to avoid batch read issues
      final adminDoc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(email)
          .get();

      return {
        'userExists': userDoc.exists,
        'isAdmin': adminDoc.exists,
        'userData': userDoc.exists ? userDoc.data() : null,
      };
    } catch (e) {
      print('❌ Error checking user existence: $e');
      return {
        'userExists': false,
        'isAdmin': false,
        'userData': null,
      };
    }
  }

  // FIXED: Major improvements to sign-in logic
  Future<Map<String, dynamic>> signInWithEmail(String email, String password) async {
    try {
      print('🔐 Starting sign-in process for: $email');

      // FIXED: Try Firebase Auth first, then check user existence
      // This allows newly created accounts to sign in even if there are Firestore delays
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      User? user = userCredential.user;
      if (user == null) {
        throw Exception("Login failed. Please try again.");
      }

      print('✅ Firebase Auth successful for: $email');

      // Reload user to get latest data
      await user.reload();
      user = FirebaseAuth.instance.currentUser;

      // FIXED: Check email verification status
      if (!(user?.emailVerified ?? false)) {
        print('❌ Email not verified for: $email');
        return {
          'success': false,
          'emailNotVerified': true,
          'message': 'Please verify your email before logging in.',
        };
      }

      print('✅ Email verified for: $email');

      // FIXED: Check user/admin status after successful auth (non-blocking)
      // Don't fail login if Firestore check fails
      bool isAdmin = false;
      try {
        final userInfo = await checkUserExistsAndGetInfo(email);
        isAdmin = userInfo['isAdmin'] ?? false;

        // Cache admin status
        _cachedAdminStatus = isAdmin;
        _adminStatusCacheTime = DateTime.now();

        // For mobile, cache admin status in SharedPreferences
        if (!isWeb) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_adminStatusKey, isAdmin ? 'admin' : 'user');
          await prefs.setInt(_adminCacheExpiryKey,
              DateTime.now().add(_adminCacheExpiry).millisecondsSinceEpoch);
        }

        print('✅ User/Admin status checked: isAdmin=$isAdmin');
      } catch (e) {
        print('⚠️ Warning: Could not check admin status, continuing with login: $e');
        // Don't fail the login just because we can't check admin status
      }

      // Update FCM token on successful login (mobile only) - ASYNC to not block login
      if (isMobile) {
        updateFCMToken(email).catchError((e) => print('❌ FCM token update failed: $e'));
      }

      print('✅ Login successful for: $email');

      if (isAdmin) {
        return {
          'success': true,
          'user': user,
          'isAdmin': true,
          'message': 'Admin login successful!',
        };
      }

      return {
        'success': true,
        'user': user,
        'message': 'Login successful!',
      };
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');

      String msg = 'Login failed. Please try again.';
      if (e.code == 'user-not-found') {
        msg = 'No account found with this email. Please sign up first.';
      } else if (e.code == 'wrong-password') {
        msg = 'Incorrect password. Please try again.';
      } else if (e.code == 'invalid-email') {
        msg = 'Invalid email address format.';
      } else if (e.code == 'user-disabled') {
        msg = 'This account has been disabled.';
      } else if (e.code == 'too-many-requests') {
        msg = 'Too many failed attempts. Please try again later.';
      } else if (e.code == 'network-request-failed') {
        msg = 'Network error. Please check your internet connection.';
      }

      return {
        'success': false,
        'message': msg,
        'error_code': e.code,
      };
    } catch (e) {
      print('❌ General sign-in error: $e');
      return {
        'success': false,
        'message': 'Login failed: ${e.toString()}',
      };
    }
  }

  // FIXED: Improved Firestore user creation with better error handling
  Future<void> saveUserToFirestore(Map<String, String> userData) async {
    final firestore = FirebaseFirestore.instance;
    final email = userData['email'] ?? '';

    if (email.isEmpty) throw Exception('Email required for Firestore user doc');

    String autoGeneratedName = extractNameFromEmail(email);

    // Get FCM token (only for mobile)
    String? fcmToken;
    if (isMobile) {
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        print('⚠️ Warning: Could not get FCM token: $e');
        // Continue without FCM token
      }
    }

    try {
      // FIXED: Use set with merge instead of batch to ensure data is written
      final docRef = firestore.collection('users').doc(email);

      Map<String, dynamic> userDoc = {
        'name': autoGeneratedName,
        'email': email,
        'phone': userData['phone'],
        'vehicle': userData['vehicle'],
        'createdAt': FieldValue.serverTimestamp(),
        'userType': 'normal',
        'emailVerified': true,
        'platform': isWeb ? 'web' : 'mobile',
      };

      if (fcmToken != null) {
        userDoc['fcmToken'] = fcmToken;
        userDoc['tokenUpdatedAt'] = FieldValue.serverTimestamp();
      }

      // FIXED: Use set with merge to ensure the document is created properly
      await docRef.set(userDoc, SetOptions(merge: true));

      // Wait a moment to ensure Firestore write is completed
      await Future.delayed(Duration(milliseconds: 500));

      // Verify the document was created
      final verifyDoc = await docRef.get();
      if (!verifyDoc.exists) {
        throw Exception('Failed to create user document in Firestore');
      }

      // Cache user data to avoid future reads
      _userDocCache = userDoc;
      _userDocCacheTime = DateTime.now();

      print('✅ Firestore user doc created and verified for $email with name: $autoGeneratedName');
      if (fcmToken != null) {
        print('✅ FCM token saved for user: $email');
      }
    } catch (e) {
      print('❌ Error saving user to Firestore: $e');
      throw Exception('Failed to save user data: $e');
    }
  }

  // FIXED: Improved FCM token update with retry logic
  Future<void> updateFCMToken(String email) async {
    if (!isMobile) {
      print('ℹ️ Skipping FCM token update on non-mobile platform');
      return;
    }

    try {
      String? fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken == null) {
        print('❌ Failed to get FCM token');
        return;
      }

      print('📱 FCM Token obtained: ${fcmToken.substring(0, 20)}...');

      final firestore = FirebaseFirestore.instance;
      final docRef = firestore.collection('users').doc(email);

      // FIXED: Add retry logic for FCM token update
      int retryCount = 0;
      const maxRetries = 3;
      bool success = false;

      while (!success && retryCount < maxRetries) {
        try {
          await docRef.set({
            'fcmToken': fcmToken,
            'tokenUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          success = true;
          print('✅ FCM token updated for user: $email');
        } catch (e) {
          retryCount++;
          print('⚠️ FCM token update attempt $retryCount failed: $e');

          if (retryCount < maxRetries) {
            await Future.delayed(Duration(seconds: retryCount * 2));
          }
        }
      }

      if (!success) {
        print('❌ Failed to update FCM token after $maxRetries attempts');
      }
    } catch (e) {
      print('❌ Error updating FCM token: $e');
    }
  }

  // FIXED: Improved Firebase user creation with better error handling
  Future<Map<String, dynamic>> createFirebaseUser(String email, String password) async {
    try {
      print('🔥 Creating Firebase user account for: $email');

      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      User? user = userCredential.user;

      if (user != null) {
        print('✅ Firebase user created successfully: ${user.email}');

        // Send email verification
        try {
          await user.sendEmailVerification();
          print('📧 Email verification sent to: ${user.email}');
        } catch (e) {
          print('⚠️ Warning: Could not send verification email: $e');
          // Don't fail user creation just because email verification failed
        }

        return {
          'success': true,
          'message': 'Account created! Please verify your email.',
          'user': user
        };
      } else {
        throw Exception('Failed to create user account - user is null');
      }
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');

      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'Email is already registered. Please use a different email or try logging in.';
          break;
        case 'weak-password':
          errorMessage = 'Password is too weak. Please use a stronger password (at least 6 characters).';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Email/password accounts are not enabled. Please contact support.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your internet connection and try again.';
          break;
        default:
          errorMessage = 'Account creation failed: ${e.message ?? e.code}';
      }

      return {
        'success': false,
        'message': errorMessage,
        'error_code': e.code
      };
    } catch (e) {
      print('❌ General Error creating user: $e');
      return {
        'success': false,
        'message': 'Account creation failed: ${e.toString()}'
      };
    }
  }

  // FIXED: Improved email verification check with better caching
  Future<bool> checkEmailVerificationOptimized() async {
    try {
      // Use cached result if very recent (within 10 seconds)
      if (_lastVerificationCheck != null &&
          _lastVerificationResult != null &&
          DateTime.now().difference(_lastVerificationCheck!) < _verificationCacheWindow) {
        print('🔍 Email verification from cache: $_lastVerificationResult');
        return _lastVerificationResult!;
      }

      User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        print('🔍 No user found, email not verified');
        _lastVerificationResult = false;
        _lastVerificationCheck = DateTime.now();
        return false;
      }

      // Always reload to get the most current verification status
      await user.reload();
      user = FirebaseAuth.instance.currentUser;

      bool isVerified = user?.emailVerified ?? false;
      _lastVerificationResult = isVerified;
      _lastVerificationCheck = DateTime.now();

      print('🔍 Email verification status: $isVerified for ${user?.email}');
      return isVerified;
    } catch (e) {
      print('❌ Error checking email verification: $e');
      // Don't cache errors
      return false;
    }
  }

  // Use the optimized version instead of the original
  Future<bool> checkEmailVerification() async {
    return await checkEmailVerificationOptimized();
  }

  // FIXED: Improved email verification completion handling
  Future<bool> handleEmailVerificationComplete() async {
    try {
      print('✅ Starting email verification completion process...');

      // Verify that email is actually verified
      bool isVerified = await checkEmailVerification();
      if (!isVerified) {
        print('❌ Email verification not confirmed');
        return false;
      }

      Map<String, String> userData = await loadSignupData();
      if (userData.isEmpty) {
        print('❌ No signup data found');
        return false;
      }

      print('📝 Signup data found, saving to Firestore...');

      // Save to Firestore with retry logic
      try {
        await saveUserToFirestore(userData);
        print('✅ User data saved to Firestore successfully');
      } catch (e) {
        print('❌ Failed to save user data to Firestore: $e');
        throw e;
      }

      await completeSignup();
      print('✅ Email verification completion process finished');
      return true;
    } catch (e) {
      print('❌ Error handling email verification completion: $e');
      return false;
    }
  }

  // Add debugging method to check user document existence
  Future<bool> verifyUserDocumentExists(String email) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .get();

      print('🔍 User document exists for $email: ${doc.exists}');
      if (doc.exists) {
        print('📄 User document data: ${doc.data()}');
      }

      return doc.exists;
    } catch (e) {
      print('❌ Error checking user document: $e');
      return false;
    }
  }

  // OPTIMIZATION 7: Clear caches on logout
  Future<void> clearCaches() async {
    _cachedAdminStatus = null;
    _adminStatusCacheTime = null;
    _userDocCache = null;
    _userDocCacheTime = null;
    _webSignupData.clear();
    _webSignupStage = stageInitial;
    _lastVerificationCheck = null;
    _lastVerificationResult = null;

    if (!isWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_adminStatusKey);
      await prefs.remove(_adminCacheExpiryKey);
    }

    print('🗑️ All caches cleared');
  }

  void setupFCMTokenRefreshListener() {
    if (!isMobile) {
      print('ℹ️ Skipping FCM token refresh listener on non-mobile platform');
      return;
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((String newToken) async {
      print('📱 FCM Token refreshed: ${newToken.substring(0, 20)}...');

      _fcmTokenUpdateTimer?.cancel();
      _fcmTokenUpdateTimer = Timer(Duration(seconds: 5), () async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.email != null) {
          await updateFCMToken(user.email!);
        }
      });
    });
  }

  Future<void> checkAndStoreAdminPriority() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_cachedAdminStatus != null &&
        _adminStatusCacheTime != null &&
        DateTime.now().difference(_adminStatusCacheTime!) < _adminCacheExpiry) {
      print('✅ Using cached admin status: $_cachedAdminStatus');

      if (!isWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('priority', _cachedAdminStatus! ? 'admin' : 'notadmin');
      }
      return;
    }

    final isAdmin = await getAdminStatus();

    if (!isWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('priority', isAdmin ? 'admin' : 'notadmin');
    }
  }

  Future<bool> saveSignupData(Map<String, String> userData) async {
    try {
      if (isWeb) {
        return await _saveSignupDataWeb(userData);
      } else {
        return await _saveSignupDataMobile(userData);
      }
    } catch (e) {
      print('❌ Error saving signup data: $e');
      return false;
    }
  }

  Future<bool> _saveSignupDataMobile(Map<String, String> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = jsonEncode(userData);
      bool result = await prefs.setString(_signupDataKey, userDataJson);
      print('📝 Mobile signup data saved: $result');
      return result;
    } catch (e) {
      print('❌ Error saving mobile signup data: $e');
      return false;
    }
  }

  Future<bool> _saveSignupDataWeb(Map<String, String> userData) async {
    try {
      if (!kIsWeb) {
        print('❌ Web storage called on non-web platform');
        return false;
      }

      final userDataJson = jsonEncode(userData);
      html.window.sessionStorage[_signupDataKey] = userDataJson;
      _webSignupData = Map.from(userData);

      print('📝 Web signup data saved to sessionStorage');
      return true;
    } catch (e) {
      print('❌ Error saving web signup data: $e');
      return false;
    }
  }

  Future<Map<String, String>> loadSignupData() async {
    try {
      if (isWeb) {
        return await _loadSignupDataWeb();
      } else {
        return await _loadSignupDataMobile();
      }
    } catch (e) {
      print('❌ Error loading signup data: $e');
      return {};
    }
  }

  Future<Map<String, String>> _loadSignupDataMobile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = prefs.getString(_signupDataKey);

      if (userDataJson != null) {
        Map<String, dynamic> userData = jsonDecode(userDataJson);
        Map<String, String> result = {};
        userData.forEach((key, value) {
          result[key] = value.toString();
        });
        print('📖 Mobile signup data loaded: ${result.keys.toList()}');
        return result;
      }

      print('📖 No mobile signup data found');
      return {};
    } catch (e) {
      print('❌ Error loading mobile signup data: $e');
      return {};
    }
  }

  Future<Map<String, String>> _loadSignupDataWeb() async {
    try {
      if (!kIsWeb) {
        print('❌ Web storage called on non-web platform');
        return {};
      }

      if (_webSignupData.isNotEmpty) {
        print('📖 Web signup data loaded from memory: ${_webSignupData.keys.toList()}');
        return _webSignupData;
      }

      final userDataJson = html.window.sessionStorage[_signupDataKey];

      if (userDataJson != null) {
        Map<String, dynamic> userData = jsonDecode(userDataJson);
        Map<String, String> result = {};
        userData.forEach((key, value) {
          result[key] = value.toString();
        });
        _webSignupData = result;

        print('📖 Web signup data loaded from sessionStorage: ${result.keys.toList()}');
        return result;
      }

      print('📖 No web signup data found');
      return {};
    } catch (e) {
      print('❌ Error loading web signup data: $e');
      return {};
    }
  }

  Future<bool> clearSignupData() async {
    try {
      if (isWeb) {
        return await _clearSignupDataWeb();
      } else {
        return await _clearSignupDataMobile();
      }
    } catch (e) {
      print('❌ Error clearing signup data: $e');
      return false;
    }
  }

  Future<bool> _clearSignupDataMobile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool dataResult = await prefs.remove(_signupDataKey);
      bool stageResult = await prefs.remove(_signupStageKey);
      bool result = dataResult && stageResult;
      print('🗑️ Mobile signup data cleared: $result');
      return result;
    } catch (e) {
      print('❌ Error clearing mobile signup data: $e');
      return false;
    }
  }

  Future<bool> _clearSignupDataWeb() async {
    try {
      if (!kIsWeb) {
        print('❌ Web storage called on non-web platform');
        return false;
      }

      _webSignupData.clear();
      _webSignupStage = stageInitial;

      html.window.sessionStorage.remove(_signupDataKey);
      html.window.sessionStorage.remove(_signupStageKey);

      print('🗑️ Web signup data cleared from sessionStorage');
      return true;
    } catch (e) {
      print('❌ Error clearing web signup data: $e');
      return false;
    }
  }

  Future<bool> setSignupStage(String stage) async {
    try {
      if (isWeb) {
        return await _setSignupStageWeb(stage);
      } else {
        return await _setSignupStageMobile(stage);
      }
    } catch (e) {
      print('❌ Error setting signup stage: $e');
      return false;
    }
  }

  Future<bool> _setSignupStageMobile(String stage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool result = await prefs.setString(_signupStageKey, stage);
      print('📊 Mobile signup stage set to: $stage, Result: $result');
      return result;
    } catch (e) {
      print('❌ Error setting mobile signup stage: $e');
      return false;
    }
  }

  Future<bool> _setSignupStageWeb(String stage) async {
    try {
      if (!kIsWeb) {
        print('❌ Web storage called on non-web platform');
        return false;
      }

      _webSignupStage = stage;
      html.window.sessionStorage[_signupStageKey] = stage;

      print('📊 Web signup stage set to: $stage');
      return true;
    } catch (e) {
      print('❌ Error setting web signup stage: $e');
      return false;
    }
  }

  Future<String> getSignupStage() async {
    try {
      if (isWeb) {
        return await _getSignupStageWeb();
      } else {
        return await _getSignupStageMobile();
      }
    } catch (e) {
      print('❌ Error getting signup stage: $e');
      return stageInitial;
    }
  }

  Future<String> _getSignupStageMobile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String stage = prefs.getString(_signupStageKey) ?? stageInitial;
      print('📊 Mobile current signup stage: $stage');
      return stage;
    } catch (e) {
      print('❌ Error getting mobile signup stage: $e');
      return stageInitial;
    }
  }

  Future<String> _getSignupStageWeb() async {
    try {
      if (!kIsWeb) {
        print('❌ Web storage called on non-web platform');
        return stageInitial;
      }

      if (_webSignupStage != stageInitial) {
        print('📊 Web current signup stage (memory): $_webSignupStage');
        return _webSignupStage;
      }

      final stage = html.window.sessionStorage[_signupStageKey] ?? stageInitial;
      _webSignupStage = stage;

      print('📊 Web current signup stage (sessionStorage): $stage');
      return stage;
    } catch (e) {
      print('❌ Error getting web signup stage: $e');
      return stageInitial;
    }
  }

  String extractNameFromEmail(String email) {
    if (email.isEmpty) return '';

    String username = email.split('@')[0];
    String name = username.replaceAll('.', ' ');

    List<String> words = name.split(' ');
    words = words.map((word) => word.isEmpty ? '' :
    word[0].toUpperCase() + word.substring(1).toLowerCase()).toList();

    return words.join(' ');
  }








Future<Map<String, dynamic>> resendEmailVerification() async {
  try {
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return {
        'success': false,
        'message': 'No user found. Please sign up again.'
      };
    }

    if (user.emailVerified) {
      return {
        'success': false,
        'message': 'Email is already verified!'
      };
    }

    await user.sendEmailVerification();
    print('📧 Email verification resent to: ${user.email}');

    return {
      'success': true,
      'message': 'Verification email sent successfully!'
    };
  } catch (e) {
    print('❌ Error resending email verification: $e');
    return {
      'success': false,
      'message': 'Failed to resend verification email: ${e.toString()}'
    };
  }
}

Stream<bool> monitorEmailVerification() async* {
  while (true) {
    try {
      bool isVerified = await checkEmailVerification();
      yield isVerified;

      if (isVerified) {
        break;
      }

      await Future.delayed(Duration(seconds: 3));
    } catch (e) {
      print('❌ Error in email verification monitoring: $e');
      yield false;
      await Future.delayed(Duration(seconds: 3));
    }
  }
}

Future<Map<String, dynamic>> sendVerificationEmail(String email) async {
  try {
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return {
        'success': false,
        'message': 'No user found. Please sign up or log in again.'
      };
    }

    if (user.email != email) {
      await user.reload();
      user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email != email) {
        return {
          'success': false,
          'message': 'Logged in user does not match the email provided.'
        };
      }
    }

    if (user.emailVerified) {
      return {
        'success': false,
        'message': 'Email is already verified!'
      };
    }

    await user.sendEmailVerification();
    print('📧 Email verification sent to: ${user.email}');

    return {
      'success': true,
      'message': 'Verification email sent successfully!'
    };
  } catch (e) {
    print('❌ Error sending Firebase verification email: $e');
    return {
      'success': false,
      'message': 'Failed to send verification email: ${e.toString()}'
    };
  }
}

Map<String, String> getFormattedUserData(Map<String, String> rawData) {
  return {
    'email': rawData['email'] ?? '',
    'phone': rawData['phone'] ?? '',
    'vehicle': rawData['vehicle'] ?? '',
    'password': rawData['password'] ?? '',
    'confirmPassword': rawData['confirmPassword'] ?? '',
  };
}

Future<bool> hasPendingSignup() async {
  try {
    String stage = await getSignupStage();
    Map<String, String> data = await loadSignupData();

    bool hasPending = stage == stageEmailSent && data.isNotEmpty;
    print('🔍 Has pending signup: $hasPending');
    return hasPending;
  } catch (e) {
    print('❌ Error checking pending signup: $e');
    return false;
  }
}

Future<Map<String, String>> getPendingSignupData() async {
  try {
    bool hasPending = await hasPendingSignup();
    if (hasPending) {
      return await loadSignupData();
    }
    return {};
  } catch (e) {
    print('❌ Error getting pending signup data: $e');
    return {};
  }
}

Future<bool> completeSignup() async {
  try {
    await setSignupStage(stageCompleted);
    await clearSignupData();

    print('✅ Signup completed and data cleared');
    return true;
  } catch (e) {
    print('❌ Error completing signup: $e');
    return false;
  }
}

Future<void> initialize() async {
  if (!isWeb) {
    setupFCMTokenRefreshListener();
  }
  print('🚀 SignUpService initialized for ${isWeb ? 'web' : 'mobile'}');
}

Future<void> debugPrintState() async {
  print('🔍 === SIGNUP SERVICE DEBUG STATE ===');
  print('📱 Platform: ${isWeb ? 'Web' : 'Mobile'}');
  String stage = await getSignupStage();
  Map<String, String> data = await loadSignupData();
  bool hasPending = await hasPendingSignup();
  bool isVerified = await checkEmailVerification();

  print('📊 Current Stage: $stage');
  print('📝 Stored Data Keys: ${data.keys.toList()}');
  print('⏳ Has Pending: $hasPending');
  print('✅ Email Verified: $isVerified');
  print('💾 Admin Status Cache: $_cachedAdminStatus');
  print('⏰ Admin Cache Time: $_adminStatusCacheTime');
  if (isWeb) {
    print('🌐 Web Temp ID: $_webTempId');
  }
  print('🔍 ================================');
}

Future<void> preloadUserData(String email) async {
  try {
    if (_userDocCache != null && _userDocCacheTime != null &&
        DateTime.now().difference(_userDocCacheTime!) < Duration(minutes: 30)) {
      print('✅ User data already cached');
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(email)
        .get();

    if (userDoc.exists) {
      _userDocCache = userDoc.data();
      _userDocCacheTime = DateTime.now();
      print('✅ User data preloaded and cached for: $email');
    }
  } catch (e) {
    print('❌ Error preloading user data: $e');
  }
}



// FIXED: Corrected syntax error in validateSignupData method
  Map<String, String?> validateSignupData(Map<String, String> data) {
    Map<String, String?> errors = {};

    if (data['email'] == null || data['email']!.isEmpty) {
      errors['email'] = 'Email cannot be empty';
    } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(data['email']!)) {
      errors['email'] = 'Enter a valid email';
    }

    if (data['phone'] == null || data['phone']!.isEmpty) {
      errors['phone'] = 'Phone number cannot be empty';
    } else if (data['phone']!.length < 10) {
      errors['phone'] = 'Enter a valid phone number';
    }

    if (data['vehicle'] == null || data['vehicle']!.isEmpty) {
      errors['vehicle'] = 'Vehicle number cannot be empty';
    }

    if (data['password'] == null || data['password']!.isEmpty) {
      errors['password'] = 'Password cannot be empty';
    } else if (data['password']!.length < 6) {
      errors['password'] = 'Password must be at least 6 characters';
    }

    if (data['confirmPassword'] == null || data['confirmPassword']!.isEmpty) {
      errors['confirmPassword'] = 'Please confirm your password';
    } else if (data['password'] != data['confirmPassword']) {
      errors['confirmPassword'] = 'Passwords do not match';
    }

    return errors;
  }


void invalidateAdminCache() {
  _cachedAdminStatus = null;
  _adminStatusCacheTime = null;
  print('🔄 Admin cache invalidated');
}

void invalidateUserDataCache() {
  _userDocCache = null;
  _userDocCacheTime = null;
  print('🔄 User data cache invalidated');
}

Future<void> logout() async {
  try {
    await FirebaseAuth.instance.signOut();
    await clearCaches();
    _fcmTokenUpdateTimer?.cancel();
    _fcmTokenUpdateTimer = null;

    print('✅ User logged out successfully with all data cleared');
  } catch (e) {
    print('❌ Error during logout: $e');
  }
}

Future<Map<String, dynamic>?> getUserData(String email) async {
  try {
    if (_userDocCache != null && _userDocCacheTime != null &&
        DateTime.now().difference(_userDocCacheTime!) < Duration(minutes: 30)) {
      print('✅ User data retrieved from cache');
      return _userDocCache;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(email)
        .get();

    if (userDoc.exists) {
      _userDocCache = userDoc.data();
      _userDocCacheTime = DateTime.now();
      print('✅ User data retrieved from Firestore and cached');
      return _userDocCache;
    }

    return null;
  } catch (e) {
    print('❌ Error getting user data: $e');
    return null;
  }
}

Future<bool> updateUserProfile(String email, Map<String, dynamic> updates) async {
  try {
    final firestore = FirebaseFirestore.instance;
    final docRef = firestore.collection('users').doc(email);

    updates['updatedAt'] = FieldValue.serverTimestamp();

    await docRef.update(updates);

    if (_userDocCache != null) {
      _userDocCache!.addAll(updates);
      print('✅ User profile updated and cache refreshed');
    } else {
      print('✅ User profile updated');
    }

    return true;
  } catch (e) {
    print('❌ Error updating user profile: $e');
    invalidateUserDataCache();
    return false;
  }
}

void setConnectionState(bool isOnline) {
  _isOnline = isOnline;
  print('🌐 Connection state updated: ${isOnline ? 'Online' : 'Offline'}');
}

bool get isOnline => _isOnline;

Future<T?> retryOperation<T>(
    Future<T> Function() operation, {
      int maxRetries = 3,
      Duration delay = const Duration(seconds: 1),
    }) async {
  for (int i = 0; i < maxRetries; i++) {
    try {
      if (!_isOnline && i == 0) {
        print('📡 Device offline, skipping operation');
        return null;
      }

      return await operation();
    } catch (e) {
      print('❌ Operation failed (attempt ${i + 1}/$maxRetries): $e');

      if (i < maxRetries - 1) {
        await Future.delayed(delay * (i + 1));
      }
    }
  }

  print('❌ Operation failed after $maxRetries retries');
  return null;
}

Future<String?> getFCMToken({bool forceRefresh = false}) async {
  if (!isMobile) return null;

  try {
    if (!forceRefresh &&
        _currentFCMToken != null &&
        _fcmTokenTimestamp != null &&
        DateTime.now().difference(_fcmTokenTimestamp!) < Duration(hours: 1)) {
      return _currentFCMToken;
    }

    String? token = await FirebaseMessaging.instance.getToken();
    _currentFCMToken = token;
    _fcmTokenTimestamp = DateTime.now();

    return token;
  } catch (e) {
    print('❌ Error getting FCM token: $e');
    return null;
  }
}

void dispose() {
  _fcmTokenUpdateTimer?.cancel();
  _fcmTokenUpdateTimer = null;

  _cachedAdminStatus = null;
  _adminStatusCacheTime = null;
  _userDocCache = null;
  _userDocCacheTime = null;
  _webSignupData.clear();
  _currentFCMToken = null;
  _fcmTokenTimestamp = null;
  _lastVerificationCheck = null;
  _lastVerificationResult = null;

  print('🧹 SignUpService disposed and cleaned up');
}


}