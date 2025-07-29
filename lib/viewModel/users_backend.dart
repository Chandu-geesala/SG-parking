import 'package:firebase_auth/firebase_auth.dart';

class UserUploadService {
  // Extract name from email (firstname.lastname@company.com format)
  String extractNameFromEmail(String email) {
    if (email.isEmpty) return 'Unknown User';
    try {
      String username = email.split('@')[0];
      List<String> parts = username.split(RegExp(r'[._]'));
      List<String> capitalizedParts = parts.map((part) {
        if (part.isEmpty) return '';
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      }).where((part) => part.isNotEmpty).toList();
      return capitalizedParts.join(' ');
    } catch (e) {
      return 'Unknown User';
    }
  }

  // Helper method to check if user exists in Firebase Auth
  Future<bool> _userExistsInAuth(String email) async {
    try {
      final userRecord = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
      return userRecord.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Create user and send reset email if not exists
  Future<Map<String, dynamic>> processSingleUserEmail(String email) async {
    try {
      bool existsInAuth = await _userExistsInAuth(email);
      if (existsInAuth) {
        return {
          'success': true,
          'message': 'User already exists in Firebase Auth - no action needed',
          'action': 'existing_user'
        };
      } else {
        bool success = await _createUserAndSendResetEmail(email);
        if (success) {
          return {
            'success': true,
            'message': 'New user account created and password reset email sent',
            'action': 'new_user_created'
          };
        } else {
          return {
            'success': false,
            'message': 'Failed to create account or send reset email',
            'action': 'failed'
          };
        }
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error processing email: $e',
        'action': 'error'
      };
    }
  }

  Future<bool> _createUserAndSendResetEmail(String email) async {
    try {
      String tempPassword = _generateTempPassword();
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: tempPassword,
      );
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      return false;
    }
  }

  String _generateTempPassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    final random = DateTime.now().millisecondsSinceEpoch;
    String password = '';
    for (int i = 0; i < 12; i++) {
      password += chars[(random + i) % chars.length];
    }
    return password + '1A!';
  }
}