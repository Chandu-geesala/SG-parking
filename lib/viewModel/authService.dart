import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';



class SignUpService {
  static const String _signupDataKey = 'signup_data';
  static const String _signupStageKey = 'signup_stage';

  // Signup stages
  static const String stageInitial = 'initial';
  static const String stageEmailSent = 'email_sent';
  static const String stageCompleted = 'completed';

  /// Save signup data to shared preferences
  Future<bool> saveSignupData(Map<String, String> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = jsonEncode(userData);

      bool result = await prefs.setString(_signupDataKey, userDataJson);
      print('📝 Signup data saved: $result');
      return result;
    } catch (e) {
      print('❌ Error saving signup data: $e');
      return false;
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
    final prefs = await SharedPreferences.getInstance();

    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(email)
          .get();

      if (adminDoc.exists) {
        await prefs.setString('priority', 'admin');
        print('✅ Admin user detected & saved in prefs');
      } else {
        await prefs.setString('priority', 'notadmin');
        print('ℹ️ Not an admin, priority set to notadmin in prefs');
      }
    } catch (e) {
      await prefs.setString('priority', 'notadmin');
      print('❌ Error checking admin priority: $e');
    }
  }



  /// Load signup data from shared preferences
  Future<Map<String, String>> loadSignupData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataJson = prefs.getString(_signupDataKey);

      if (userDataJson != null) {
        Map<String, dynamic> userData = jsonDecode(userDataJson);
        // Convert to Map<String, String>
        Map<String, String> result = {};
        userData.forEach((key, value) {
          result[key] = value.toString();
        });
        print('📖 Signup data loaded: ${result.keys.toList()}');
        return result;
      }

      print('📖 No signup data found');
      return {};
    } catch (e) {
      print('❌ Error loading signup data: $e');
      return {};
    }
  }

  /// Clear signup data from shared preferences
  Future<bool> clearSignupData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool dataResult = await prefs.remove(_signupDataKey);
      bool stageResult = await prefs.remove(_signupStageKey);

      bool result = dataResult && stageResult;
      print('🗑️ Signup data cleared: $result');
      return result;
    } catch (e) {
      print('❌ Error clearing signup data: $e');
      return false;
    }
  }

  /// Set signup stage
  Future<bool> setSignupStage(String stage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool result = await prefs.setString(_signupStageKey, stage);
      print('📊 Signup stage set to: $stage, Result: $result');
      return result;
    } catch (e) {
      print('❌ Error setting signup stage: $e');
      return false;
    }
  }

  /// Get current signup stage
  Future<String> getSignupStage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String stage = prefs.getString(_signupStageKey) ?? stageInitial;
      print('📊 Current signup stage: $stage');
      return stage;
    } catch (e) {
      print('❌ Error getting signup stage: $e');
      return stageInitial;
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




  /// Simulate sending verification email (legacy method - kept for backward compatibility)
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
    String stage = await getSignupStage();
    Map<String, String> data = await loadSignupData();
    bool hasPending = await hasPendingSignup();
    bool isVerified = await checkEmailVerification();

    print('📊 Current Stage: $stage');
    print('📝 Stored Data Keys: ${data.keys.toList()}');
    print('⏳ Has Pending: $hasPending');
    print('✅ Email Verified: $isVerified');
    print('🔍 ================================');
  }



  Future<void> updateFCMToken(String email) async {
    try {
      // Get FCM token
      String? fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken == null) {
        print('❌ Failed to get FCM token');
        return;
      }

      print('📱 FCM Token obtained: ${fcmToken.substring(0, 20)}...');

      // Update user document with FCM token
      final firestore = FirebaseFirestore.instance;
      final docRef = firestore.collection('users').doc(email);

      await docRef.update({
        'fcmToken': fcmToken,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ FCM token updated for user: $email');
    } catch (e) {
      print('❌ Error updating FCM token: $e');

      // If document doesn't exist, create it with FCM token
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

  /// Listen for FCM token refresh and update Firestore
  void setupFCMTokenRefreshListener() {
    FirebaseMessaging.instance.onTokenRefresh.listen((String newToken) async {
      print('📱 FCM Token refreshed: ${newToken.substring(0, 20)}...');

      // Get current user email
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

    // Get FCM token
    String? fcmToken = await FirebaseMessaging.instance.getToken();

    final docRef = firestore.collection('users').doc(email);
    Map<String, dynamic> userDoc = {
      'name': autoGeneratedName,
      'email': email,
      'phone': userData['phone'],
      'vehicle': userData['vehicle'],
      'createdAt': FieldValue.serverTimestamp(),
      'userType': 'normal',
      'emailVerified': true,
    };

    // Add FCM token if available
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

  // Update the signInWithEmail method to update FCM token
  Future<Map<String, dynamic>> signInWithEmail(String email, String password) async {
    try {
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
      final prefs = await SharedPreferences.getInstance();
      bool isAdmin = prefs.getString('priority') == 'admin';

      if (!(user?.emailVerified ?? false)) {
        // DON'T sign out - keep user logged in for verification
        return {
          'success': false,
          'emailNotVerified': true,
          'message': 'Please verify your email before logging in.',
        };
      }

      // Update FCM token on successful login
      await updateFCMToken(email);

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
      if (e.code == 'user-not-found') msg = 'No account found with this email.';
      if (e.code == 'wrong-password') msg = 'Incorrect password.';
      if (e.code == 'invalid-email') msg = 'Invalid email address.';
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

}