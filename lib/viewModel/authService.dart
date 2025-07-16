import 'dart:io';
import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignUpService {
  static const String _signupDataKey = 'signup_data';
  static const String _signupStageKey = 'signup_stage';
  static const String _tempIdKey = 'temp_id';

  // Signup stages
  static const String stageInitial = 'initial';
  static const String stageEmailSent = 'email_sent';
  static const String stageCompleted = 'completed';

  // In-memory storage for web
  static String? _webTempId;
  static Map<String, String> _webSignupData = {};
  static String _webSignupStage = stageInitial;

  // Platform check
  bool get isWeb => kIsWeb;
  bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Generate random temp ID for web users
  String _generateTempId() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomNum = random.nextInt(999999);
    return 'temp_${timestamp}_$randomNum';
  }

  /// Save signup data (platform-specific)
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

  /// Save signup data for mobile (SharedPreferences)
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

  /// Save signup data for web (Firestore temp storage)
  Future<bool> _saveSignupDataWeb(Map<String, String> userData) async {
    try {
      // Generate temp ID if not exists
      if (_webTempId == null) {
        _webTempId = _generateTempId();
      }

      final firestore = FirebaseFirestore.instance;
      final docRef = firestore.collection('temp_data').doc(_webTempId);

      // Save to Firestore with auto-delete timestamp
      await docRef.set({
        'userData': userData,
        'stage': _webSignupStage,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(Duration(days: 2))),
      });

      // Also store in memory for quick access
      _webSignupData = Map.from(userData);

      print('📝 Web signup data saved with temp ID: $_webTempId');
      return true;
    } catch (e) {
      print('❌ Error saving web signup data: $e');
      return false;
    }
  }

  /// Load signup data (platform-specific)
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

  /// Load signup data for mobile
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

  /// Load signup data for web
  Future<Map<String, String>> _loadSignupDataWeb() async {
    try {
      // First check memory
      if (_webSignupData.isNotEmpty) {
        print('📖 Web signup data loaded from memory: ${_webSignupData.keys.toList()}');
        return _webSignupData;
      }

      // If memory is empty and we have temp ID, try to load from Firestore
      if (_webTempId != null) {
        final firestore = FirebaseFirestore.instance;
        final docRef = firestore.collection('temp_data').doc(_webTempId);
        final doc = await docRef.get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          final userData = Map<String, String>.from(data['userData'] ?? {});
          _webSignupData = userData;
          _webSignupStage = data['stage'] ?? stageInitial;

          print('📖 Web signup data loaded from Firestore: ${userData.keys.toList()}');
          return userData;
        }
      }

      print('📖 No web signup data found');
      return {};
    } catch (e) {
      print('❌ Error loading web signup data: $e');
      return {};
    }
  }

  /// Clear signup data (platform-specific)
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

  /// Clear signup data for mobile
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

  /// Clear signup data for web
  Future<bool> _clearSignupDataWeb() async {
    try {
      // Clear memory
      _webSignupData.clear();
      _webSignupStage = stageInitial;

      // Clear Firestore temp data
      if (_webTempId != null) {
        final firestore = FirebaseFirestore.instance;
        final docRef = firestore.collection('temp_data').doc(_webTempId);
        await docRef.delete();
        _webTempId = null;
      }

      print('🗑️ Web signup data cleared');
      return true;
    } catch (e) {
      print('❌ Error clearing web signup data: $e');
      return false;
    }
  }

  /// Set signup stage (platform-specific)
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

  /// Set signup stage for mobile
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

  /// Set signup stage for web
  Future<bool> _setSignupStageWeb(String stage) async {
    try {
      _webSignupStage = stage;

      // Update in Firestore if temp ID exists
      if (_webTempId != null) {
        final firestore = FirebaseFirestore.instance;
        final docRef = firestore.collection('temp_data').doc(_webTempId);
        await docRef.update({'stage': stage});
      }

      print('📊 Web signup stage set to: $stage');
      return true;
    } catch (e) {
      print('❌ Error setting web signup stage: $e');
      return false;
    }
  }

  /// Get current signup stage (platform-specific)
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

  /// Get signup stage for mobile
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

  /// Get signup stage for web
  Future<String> _getSignupStageWeb() async {
    try {
      // First check memory
      if (_webSignupStage != stageInitial) {
        print('📊 Web current signup stage (memory): $_webSignupStage');
        return _webSignupStage;
      }

      // If memory is empty and we have temp ID, try to load from Firestore
      if (_webTempId != null) {
        final firestore = FirebaseFirestore.instance;
        final docRef = firestore.collection('temp_data').doc(_webTempId);
        final doc = await docRef.get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          _webSignupStage = data['stage'] ?? stageInitial;
          print('📊 Web current signup stage (Firestore): $_webSignupStage');
          return _webSignupStage;
        }
      }

      print('📊 Web current signup stage (default): $stageInitial');
      return stageInitial;
    } catch (e) {
      print('❌ Error getting web signup stage: $e');
      return stageInitial;
    }
  }

  /// Clean up expired temp data (call this periodically or on app start)
  Future<void> cleanupExpiredTempData() async {
    if (!isWeb) return; // Only for web

    try {
      final firestore = FirebaseFirestore.instance;
      final now = Timestamp.now();

      final expiredDocs = await firestore
          .collection('temp_data')
          .where('expiresAt', isLessThan: now)
          .get();

      for (var doc in expiredDocs.docs) {
        await doc.reference.delete();
      }

      print('🧹 Cleaned up ${expiredDocs.docs.length} expired temp data entries');
    } catch (e) {
      print('❌ Error cleaning up expired temp data: $e');
    }
  }

  /// Initialize web temp ID (call this on app start for web)
  Future<void> initializeWebTempId() async {
    if (!isWeb) return;

    try {
      // Try to load existing temp data to restore session
      final firestore = FirebaseFirestore.instance;

      // Clean up expired data first
      await cleanupExpiredTempData();

      // For now, we'll generate a new temp ID each time
      // In a real app, you might want to store this in browser storage
      _webTempId = _generateTempId();

      print('🔄 Web temp ID initialized: $_webTempId');
    } catch (e) {
      print('❌ Error initializing web temp ID: $e');
    }
  }

  String extractNameFromEmail(String email) {
    if (email.isEmpty) return '';

    // Get the part before @ symbol
    String username = email.split('@')[0];

    // Replace dots with spaces and format as proper name
    String name = username.replaceAll('.', ' ');

    // Capitalize first letter of each word
    List<String> words = name.split(' ');
    words = words.map((word) => word.isEmpty ? '' :
    word[0].toUpperCase() + word.substring(1).toLowerCase()).toList();

    return words.join(' ');
  }

  /// Checks if the current user is admin, saves priority to SharedPreferences.
  /// Call after successful login.
  Future<void> checkAndStoreAdminPriority() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final String email = user.email!;

    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(email)
          .get();

      if (isWeb) {
        // For web, store in memory (you might want to use browser storage here)
        if (adminDoc.exists) {
          // Store in memory or implement browser storage
          print('✅ Admin user detected (web)');
        } else {
          print('ℹ️ Not an admin (web)');
        }
      } else {
        // For mobile, use SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (adminDoc.exists) {
          await prefs.setString('priority', 'admin');
          print('✅ Admin user detected & saved in prefs');
        } else {
          await prefs.setString('priority', 'notadmin');
          print('ℹ️ Not an admin, priority set to notadmin in prefs');
        }
      }
    } catch (e) {
      if (!isWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('priority', 'notadmin');
      }
      print('❌ Error checking admin priority: $e');
    }
  }

  /// Check if user has pending signup
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

  /// Get user data for restoration
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

  /// Process signup completion
  Future<bool> completeSignup() async {
    try {
      // Set stage to completed
      await setSignupStage(stageCompleted);

      // Clear signup data as it's no longer needed
      await clearSignupData();

      print('✅ Signup completed and data cleared');
      return true;
    } catch (e) {
      print('❌ Error completing signup: $e');
      return false;
    }
  }

  /// Check if email is verified using Firebase Auth
  Future<bool> checkEmailVerification() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        print('🔍 No user found, email not verified');
        return false;
      }

      // Reload user to get latest verification status
      await user.reload();
      user = FirebaseAuth.instance.currentUser;

      bool isVerified = user?.emailVerified ?? false;
      print('🔍 Email verification status: $isVerified');
      return isVerified;
    } catch (e) {
      print('❌ Error checking email verification: $e');
      return false;
    }
  }

  /// Start continuous email verification monitoring
  Stream<bool> monitorEmailVerification() async* {
    while (true) {
      try {
        bool isVerified = await checkEmailVerification();
        yield isVerified;

        // If verified, stop monitoring
        if (isVerified) {
          break;
        }

        // Wait 3 seconds before next check
        await Future.delayed(Duration(seconds: 3));
      } catch (e) {
        print('❌ Error in email verification monitoring: $e');
        yield false;
        await Future.delayed(Duration(seconds: 3));
      }
    }
  }

  /// Create Firebase user account (call this during signup)
  Future<Map<String, dynamic>> createFirebaseUser(String email, String password) async {
    try {
      print('🔥 Creating Firebase user account...');

      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      User? user = userCredential.user;

      if (user != null) {
        // Send email verification
        await user.sendEmailVerification();
        print('📧 Email verification sent to: ${user.email}');

        return {
          'success': true,
          'message': 'Account created! Please verify your email.',
          'user': user
        };
      } else {
        throw Exception('Failed to create user account');
      }
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error: ${e.code} - ${e.message}');

      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'Email is already registered. Please use a different email.';
          break;
        case 'weak-password':
          errorMessage = 'Password is too weak. Please use a stronger password.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        default:
          errorMessage = 'Account creation failed: ${e.message}';
      }

      return {
        'success': false,
        'message': errorMessage,
        'error_code': e.code
      };
    } catch (e) {
      print('❌ General Error: $e');
      return {
        'success': false,
        'message': 'Account creation failed: ${e.toString()}'
      };
    }
  }

  /// Resend email verification
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

  /// Validate user input data
  Map<String, String?> validateSignupData(Map<String, String> data) {
    Map<String, String?> errors = {};

    // Remove name validation - name will be auto-generated from email

    // Email validation
    if (data['email'] == null || data['email']!.isEmpty) {
      errors['email'] = 'Email cannot be empty';
    } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(data['email']!)) {
      errors['email'] = 'Enter a valid email';
    }

    // Phone validation
    if (data['phone'] == null || data['phone']!.isEmpty) {
      errors['phone'] = 'Phone number cannot be empty';
    } else if (data['phone']!.length < 10) {
      errors['phone'] = 'Enter a valid phone number';
    }

    // Vehicle validation
    if (data['vehicle'] == null || data['vehicle']!.isEmpty) {
      errors['vehicle'] = 'Vehicle number cannot be empty';
    }

    // Password validation
    if (data['password'] == null || data['password']!.isEmpty) {
      errors['password'] = 'Password cannot be empty';
    } else if (data['password']!.length < 6) {
      errors['password'] = 'Password must be at least 6 characters';
    }

    // Confirm password validation
    if (data['confirmPassword'] == null || data['confirmPassword']!.isEmpty) {
      errors['confirmPassword'] = 'Please confirm your password';
    } else if (data['password'] != data['confirmPassword']) {
      errors['confirmPassword'] = 'Passwords do not match';
    }

    return errors;
  }

  /// Send Firebase email verification to current user
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
        // Optionally reload user (you may remove this check if you are sure user is always up-to-date)
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

  /// Get formatted user data for display
  Map<String, String> getFormattedUserData(Map<String, String> rawData) {
    return {
      // Remove 'name' field since it will be auto-generated
      'email': rawData['email'] ?? '',
      'phone': rawData['phone'] ?? '',
      'vehicle': rawData['vehicle'] ?? '',
      'password': rawData['password'] ?? '',
      'confirmPassword': rawData['confirmPassword'] ?? '',
    };
  }

  /// Debug method to print current state
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
    if (isWeb) {
      print('🌐 Web Temp ID: $_webTempId');
    }
    print('🔍 ================================');
  }

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

      await docRef.update({
        'fcmToken': fcmToken,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ FCM token updated for user: $email');
    } catch (e) {
      print('❌ Error updating FCM token: $e');

      // Attempt to set document if update fails (e.g., doc doesn't exist)
      try {
        String? fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          final firestore = FirebaseFirestore.instance;
          final docRef = firestore.collection('users').doc(email);

          await docRef.set({
            'fcmToken': fcmToken,
            'tokenUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          print('✅ FCM token set for new user: $email');
        }
      } catch (createError) {
        print('❌ Error creating document with FCM token: $createError');
      }
    }
  }

  void setupFCMTokenRefreshListener() {
    if (!isMobile) {
      print('ℹ️ Skipping FCM token refresh listener on non-mobile platform');
      return;
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((String newToken) async {
      print('📱 FCM Token refreshed: ${newToken.substring(0, 20)}...');

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        await updateFCMToken(user.email!);
      }
    });
  }

  // Update the saveUserToFirestore method to include FCM token
  Future<void> saveUserToFirestore(Map<String, String> userData) async {
    final firestore = FirebaseFirestore.instance;
    final email = userData['email'] ?? '';

    if (email.isEmpty) throw Exception('Email required for Firestore user doc');

    // Extract name from email automatically
    String autoGeneratedName = extractNameFromEmail(email);

    // Get FCM token (only for mobile)
    String? fcmToken;
    if (isMobile) {
      fcmToken = await FirebaseMessaging.instance.getToken();
    }

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

    // Add FCM token if available (mobile only)
    if (fcmToken != null) {
      userDoc['fcmToken'] = fcmToken;
      userDoc['tokenUpdatedAt'] = FieldValue.serverTimestamp();
    }

    await docRef.set(userDoc, SetOptions(merge: true));

    print('✅ Firestore user doc created for $email with name: $autoGeneratedName');
    if (fcmToken != null) {
      print('✅ FCM token saved for user: $email');
    }
  }

  Future<Map<String, dynamic>> signInWithEmail(String email, String password) async {
    try {
      // First check if user exists in either users or admins collection
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(email).get();
      final adminDoc = await firestore.collection('admins').doc(email).get();

      if (!userDoc.exists && !adminDoc.exists) {
        return {
          'success': false,
          'message': 'User doesn\'t exist. Please sign up first.',
        };
      }

      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      User? user = userCredential.user;
      if (user == null) {
        throw Exception("Login failed. Please try again.");
      }

      await user.reload();
      user = FirebaseAuth.instance.currentUser;

      // Check admin status first
      await checkAndStoreAdminPriority();

      // For mobile, check SharedPreferences for admin status
      bool isAdmin = false;
      if (!isWeb) {
        final prefs = await SharedPreferences.getInstance();
        isAdmin = prefs.getString('priority') == 'admin';
      } else {
        // For web, use the adminDoc we already fetched
        isAdmin = adminDoc.exists;
      }

      if (!(user?.emailVerified ?? false)) {
        // DON'T sign out - keep user logged in for verification
        return {
          'success': false,
          'emailNotVerified': true,
          'message': 'Please verify your email before logging in.',
        };
      }

      // Update FCM token on successful login (mobile only)
      if (isMobile) {
        await updateFCMToken(email);
      }

      // Email is verified - check if admin for navigation
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
      String msg = 'Login failed. Please try again.';
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-email') {
        msg = 'Incorrect credentials. Please check your email and password.';
      }
      return {
        'success': false,
        'message': msg,
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  // Update the handleEmailVerificationComplete method
  Future<bool> handleEmailVerificationComplete() async {
    try {
      print('✅ Email verification completed successfully!');
      // Get user data
      Map<String, String> userData = await loadSignupData();
      // Write user data to Firestore before clearing (now includes FCM token)
      await saveUserToFirestore(userData);
      // Complete the signup process (stage & clear prefs)
      await completeSignup();
      return true;
    } catch (e) {
      print('❌ Error handling email verification completion: $e');
      return false;
    }
  }

  /// Initialize the service (call this on app start)
  Future<void> initialize() async {
    if (isWeb) {
      await initializeWebTempId();
      await cleanupExpiredTempData();
    } else {
      setupFCMTokenRefreshListener();
    }
    print('🚀 SignUpService initialized for ${isWeb ? 'web' : 'mobile'}');
  }

  /// Get admin status (platform-specific)
  Future<bool> getAdminStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      if (isWeb) {
        // For web, check Firestore directly
        final adminDoc = await FirebaseFirestore.instance
            .collection('admins')
            .doc(user.email!)
            .get();
        return adminDoc.exists;
      } else {
        // For mobile, check SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString('priority') == 'admin';
      }
    } catch (e) {
      print('❌ Error getting admin status: $e');
      return false;
    }
  }

  /// Set up Firestore security rules for temp_data collection
  /// Add these rules to your Firestore security rules:
  /*
  rules_version = '2';
  service cloud.firestore {
    match /databases/{database}/documents {
      // Existing rules...

      // Temp data rules
      match /temp_data/{tempId} {
        allow read, write: if request.auth != null;
        allow delete: if request.auth != null ||
                     resource.data.expiresAt < request.time;
      }
    }
  }
  */

  /// Cleanup method to be called periodically (e.g., via Cloud Functions)
  static Future<void> cleanupExpiredTempDataBatch() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final now = Timestamp.now();

      final expiredQuery = firestore
          .collection('temp_data')
          .where('expiresAt', isLessThan: now)
          .limit(500); // Process in batches

      final expiredDocs = await expiredQuery.get();

      if (expiredDocs.docs.isEmpty) {
        print('🧹 No expired temp data to clean up');
        return;
      }

      final batch = firestore.batch();
      for (var doc in expiredDocs.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('🧹 Batch cleaned up ${expiredDocs.docs.length} expired temp data entries');
    } catch (e) {
      print('❌ Error in batch cleanup: $e');
    }
  }

  /// Restore web session (call this when user returns to web app)
  Future<bool> restoreWebSession() async {
    if (!isWeb) return false;

    try {
      // Check if user is already logged in
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // Try to restore temp data if available
      await loadSignupData();

      print('🔄 Web session restored for user: ${user.email}');
      return true;
    } catch (e) {
      print('❌ Error restoring web session: $e');
      return false;
    }
  }

  /// Enhanced error handling for web-specific issues
  Future<void> handleWebStorageError(dynamic error) async {
    print('❌ Web storage error: $error');

    try {
      // Try to reinitialize
      await initializeWebTempId();
      print('🔄 Web storage reinitialized after error');
    } catch (e) {
      print('❌ Failed to reinitialize web storage: $e');
    }
  }

}