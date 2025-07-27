import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';




// SHARED utilities to reduce redundancy with slot backend
class FileProcessingUtils {
  // Shared cache for email validation
  static final Map<String, bool> _emailValidationCache = {};

  // Shared cell extraction method
  static String extractCellValue(dynamic cell) {
    if (cell == null) return '';
    if (cell is String) return cell.trim();
    if (cell is Data) return cell.value?.toString().trim() ?? '';
    return cell.toString().trim();
  }

  // Shared file picker method
  static Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions ?? ['xlsx', 'csv'],
        allowMultiple: false,
      );
      return result;
    } catch (e) {
      print('File picker error: $e');
      return null;
    }
  }

  // Shared email validation with caching
  static bool isValidEmail(String email) {
    if (email.isEmpty) return false;

    if (_emailValidationCache.containsKey(email)) {
      return _emailValidationCache[email]!;
    }

    final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');
    final isValid = emailRegex.hasMatch(email);
    _emailValidationCache[email] = isValid;
    return isValid;
  }

  // Clear all shared caches
  static void clearCaches() {
    _emailValidationCache.clear();
  }
}

// Validation result class
class UserValidationResult {
  final bool isValid;
  final String? error;
  final Map<String, dynamic>? data;

  UserValidationResult.valid(this.data) : isValid = true, error = null;
  UserValidationResult.invalid(this.error) : isValid = false, data = null;
}

class UserUploadService {
  // COST OPTIMIZATION: Batch existence checks to reduce reads
  static final Map<String, bool> _userExistsCache = {};
  static final Map<String, bool> _firebaseAuthCache = {};

  // Reuse shared file picker
  Future<FilePickerResult?> pickUserFile() async {
    return FileProcessingUtils.pickFile();
  }

  // Phone number validation
  bool isValidPhone(String phone) {
    if (phone.isEmpty) return false;
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    return cleanPhone.length >= 10;
  }

  // Parse vehicle data from Excel cell
  List<Map<String, dynamic>> parseVehicleData(String vehicleInput) {
    if (vehicleInput.isEmpty) return [];

    final vehicles = <Map<String, dynamic>>[];
    final vehicleStrings = vehicleInput.split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty);

    for (String vehicleStr in vehicleStrings) {
      vehicles.add({
        'type': 'VehicleType.car',
        'number': vehicleStr,
        'width': 2.0,
        'height': 1.8,
      });
    }

    return vehicles;
  }

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


  Future<void> _batchCheckFirebaseAuth(List<String> emails) async {
    try {
      _firebaseAuthCache.clear();

      // Firebase Auth doesn't have a batch check API, so we need to check individually
      // But we can optimize by doing it concurrently
      const int concurrentLimit = 10; // Limit concurrent requests

      for (int i = 0; i < emails.length; i += concurrentLimit) {
        final batch = emails.skip(i).take(concurrentLimit).toList();

        // Check all emails in this batch concurrently
        final futures = batch.map((email) => _checkSingleEmailInAuth(email));
        await Future.wait(futures);

        // Small delay between batches to avoid rate limiting
        if (i + concurrentLimit < emails.length) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      print('✅ Firebase Auth check completed for ${emails.length} emails');
    } catch (e) {
      print('❌ Error in Firebase Auth batch check: $e');
      // Fallback: mark all as not existing to send emails
      for (String email in emails) {
        _firebaseAuthCache[email] = false;
      }
    }
  }

  // Helper method to check single email in Firebase Auth
  Future<void> _checkSingleEmailInAuth(String email) async {
    try {
      // Try to fetch user by email
      final userRecord = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
      _firebaseAuthCache[email] = userRecord.isNotEmpty;
    } catch (e) {
      // If error (like user not found), mark as not existing
      _firebaseAuthCache[email] = false;
    }
  }

  // Check if user exists in Firebase Auth (using cache)
  bool userExistsInAuth(String email) {
    return _firebaseAuthCache[email] ?? false;
  }



  // Enhanced validation with flexible field handling
  UserValidationResult validateAndParseUserRow(
      List<dynamic> row,
      List<String> header,
      Map<String, int> columnIndices,
      int rowIndex,
      ) {
    // FIXED: Safe null checking for all fields
    String providedName = columnIndices['name'] != null &&
        row.length > columnIndices['name']!
        ? FileProcessingUtils.extractCellValue(row[columnIndices['name']!])
        : '';

    String email = columnIndices['email'] != null &&
        row.length > columnIndices['email']!
        ? FileProcessingUtils.extractCellValue(row[columnIndices['email']!])
        : '';

    String phone = columnIndices['phone'] != null &&
        row.length > columnIndices['phone']!
        ? FileProcessingUtils.extractCellValue(row[columnIndices['phone']!])
        : '';

    String vehicleData = columnIndices['vehicles'] != null &&
        row.length > columnIndices['vehicles']!
        ? FileProcessingUtils.extractCellValue(row[columnIndices['vehicles']!])
        : '';

    String userType = columnIndices['userType'] != null &&
        row.length > columnIndices['userType']!
        ? FileProcessingUtils.extractCellValue(row[columnIndices['userType']!]).toLowerCase()
        : 'user';

    // MANDATORY VALIDATION: Only Email is required
    if (email.isEmpty) {
      return UserValidationResult.invalid("Row ${rowIndex + 1}: Email is required");
    }

    if (!FileProcessingUtils.isValidEmail(email)) {
      return UserValidationResult.invalid("Row ${rowIndex + 1}: Invalid email format: $email");
    }

    // SMART NAME GENERATION: Use provided name or extract from email
    String finalName = providedName.isNotEmpty
        ? providedName
        : extractNameFromEmail(email);

    // OPTIONAL FIELD VALIDATION: Only validate if provided
    if (phone.isNotEmpty && !isValidPhone(phone)) {
      return UserValidationResult.invalid("Row ${rowIndex + 1}: Invalid phone format: $phone");
    }

    // Validate user type (default to 'user' if invalid)
    if (!['user', 'admin'].contains(userType)) {
      userType = 'user';
    }

    // Parse vehicles (empty list if no vehicle data)
    List<Map<String, dynamic>> vehicles = parseVehicleData(vehicleData);

    // Create user document data with smart defaults
    Map<String, dynamic> userData = {
      'name': finalName,
      'email': email,
      'userType': userType,
      'emailVerified': true,
      'createdAt': FieldValue.serverTimestamp(),
      'platform': 'bulk_upload',
    };

    // Add optional fields only if they have values
    if (phone.isNotEmpty) {
      userData['phone'] = phone;
    }

    if (vehicles.isNotEmpty) {
      userData['vehicles'] = vehicles;
    }

    return UserValidationResult.valid({
      'email': email,
      'userData': userData,
    });
  }

  // Get correct format string for user uploads
  String getUserFormatString() {
    return 'Required columns: Email (mandatory)\n'
        'Optional columns: Name, Phone, Vehicles, UserType (user/admin)\n'
        'Note: If Name is not provided, it will be auto-generated from email';
  }

  // COST OPTIMIZATION: Batch check user existence to reduce Firestore reads
  Future<void> _batchCheckUserExistence(List<String> emails) async {
    try {
      // Clear previous cache
      _userExistsCache.clear();

      // Process in chunks to avoid large queries
      const int chunkSize = 10; // Firestore 'in' query limit

      for (int i = 0; i < emails.length; i += chunkSize) {
        final chunk = emails.skip(i).take(chunkSize).toList();

        // Use 'where in' query to check multiple emails at once
        final querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(const GetOptions(source: Source.cache)) // Try cache first
            .catchError((_) => FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get()); // Fallback to server

        // Mark existing users
        for (var doc in querySnapshot.docs) {
          _userExistsCache[doc.id] = true;
        }

        // Mark non-existing users
        for (String email in chunk) {
          if (!_userExistsCache.containsKey(email)) {
            _userExistsCache[email] = false;
          }
        }
      }

      print('✅ Batch existence check completed for ${emails.length} emails');
    } catch (e) {
      print('❌ Error in batch existence check: $e');
      // Fallback: mark all as non-existing to allow individual checks
      for (String email in emails) {
        _userExistsCache[email] = false;
      }
    }
  }

  // Check if user exists (using cache)
  bool userExists(String email) {
    return _userExistsCache[email] ?? false;
  }

// Replace the existing sendPasswordResetEmail method with this:
  Future<bool> createUserAndSendResetEmail(String email) async {
    try {
      // Generate random temporary password
      String tempPassword = _generateTempPassword();

      // Create user in Firebase Auth with temp password
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: tempPassword,
      );

      print('✅ Created auth account for: $email');

      // Send password reset email so user can set their own password
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      print('📧 Password reset email sent to: $email');

      return true;
    } catch (e) {
      print('❌ Failed to create account or send reset email to $email: $e');
      return false;
    }
  }

// Add this helper method to generate temporary password:
  String _generateTempPassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    final random = DateTime.now().millisecondsSinceEpoch;
    String password = '';

    for (int i = 0; i < 12; i++) {
      password += chars[(random + i) % chars.length];
    }

    return password + '1A!'; // Ensure it meets Firebase requirements
  }

// Replace the existing batchSendPasswordResetEmails method with this:
  Future<Map<String, int>> batchCreateUsersAndSendResetEmails(List<String> newUserEmails) async {
    int successful = 0;
    int failed = 0;

    // Process emails in small batches to avoid rate limits
    const int batchSize = 3; // Reduced batch size for account creation

    for (int i = 0; i < newUserEmails.length; i += batchSize) {
      final batch = newUserEmails.skip(i).take(batchSize).toList();

      // Process batch with small delay
      final futures = batch.map((email) => createUserAndSendResetEmail(email));
      final results = await Future.wait(futures);

      // Count results
      for (bool success in results) {
        if (success) {
          successful++;
        } else {
          failed++;
        }
      }

      // Longer delay between batches for account creation
      if (i + batchSize < newUserEmails.length) {
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    return {'successful': successful, 'failed': failed};
  }

// Add this new method for single email processing:
  Future<Map<String, dynamic>> processSingleUserEmail(String email) async {
    try {
      // Check if email exists in Firebase Auth
      await _batchCheckFirebaseAuth([email]);

      bool existsInAuth = userExistsInAuth(email);

      if (existsInAuth) {
        return {
          'success': true,
          'message': 'User already exists in Firebase Auth - no action needed',
          'action': 'existing_user'
        };
      } else {
        // Create account and send reset email
        bool success = await createUserAndSendResetEmail(email);

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







  // SHARED file processing logic to reduce redundancy
  Future<List<List<dynamic>>> _processFileToRows({
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    List<List<dynamic>> tableRows = [];

    // Determine file type
    String fileExtension;
    if (fileName != null) {
      fileExtension = fileName.toLowerCase().split('.').last;
    } else if (filePath != null) {
      fileExtension = filePath.toLowerCase().split('.').last;
    } else {
      throw Exception("No file information provided");
    }

    // Process file based on platform
    if (kIsWeb) {
      if (fileBytes == null) {
        throw Exception("File bytes not available for web platform");
      }

      if (fileExtension == 'xlsx') {
        final excel = Excel.decodeBytes(fileBytes);
        if (excel.tables.isEmpty) {
          throw Exception("No sheets found in Excel file.");
        }
        final sheet = excel.tables.values.first;
        tableRows = sheet!.rows;
      } else if (fileExtension == 'csv') {
        final content = String.fromCharCodes(fileBytes);
        tableRows = const CsvToListConverter(eol: "\n", allowInvalid: false)
            .convert(content);
      } else {
        throw Exception("Unsupported file type: $fileExtension");
      }
    } else {
      if (filePath == null) {
        throw Exception("File path not available for mobile/desktop platform");
      }

      if (fileExtension == 'xlsx') {
        final bytes = File(filePath).readAsBytesSync();
        final excel = Excel.decodeBytes(bytes);
        if (excel.tables.isEmpty) {
          throw Exception("No sheets found in Excel file.");
        }
        final sheet = excel.tables.values.first;
        tableRows = sheet!.rows;
      } else if (fileExtension == 'csv') {
        final content = File(filePath).readAsStringSync();
        tableRows = const CsvToListConverter(eol: "\n", allowInvalid: false)
            .convert(content);
      } else {
        throw Exception("Unsupported file type: $fileExtension");
      }
    }

    return tableRows;
  }

  // UPDATED: Main processing function for user uploads with email reset option
  Future<String> processUserFile({
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
    bool skipExisting = true,
  }) async {
    try {
      // Clear caches at start
      FileProcessingUtils.clearCaches();
      _userExistsCache.clear();
      _firebaseAuthCache.clear(); // Clear auth cache too

      // SHARED: Process file to get rows
      List<List<dynamic>> tableRows = await _processFileToRows(
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: fileName,
      );

      if (tableRows.isEmpty) return "No data found in file.";

      // Parse header and create column index map
      final header = tableRows.first
          .map((cell) => FileProcessingUtils.extractCellValue(cell))
          .toList();
      final columnIndices = <String, int>{};

      for (int i = 0; i < header.length; i++) {
        final col = header[i].toLowerCase();
        if (col == "name") columnIndices['name'] = i;
        else if (col == "email") columnIndices['email'] = i;
        else if (col == "phone") columnIndices['phone'] = i;
        else if (col == "vehicles" || col == "vehicle") columnIndices['vehicles'] = i;
        else if (col == "usertype" || col == "user type") columnIndices['userType'] = i;
      }

      // Validate required columns - Only Email is mandatory
      if (!columnIndices.containsKey('email')) {
        return "Missing required column: Email\n"
            "${getUserFormatString()}\n"
            "Present columns: ${header.join(', ')}";
      }

      int uploaded = 0, skipped = 0, existing = 0;
      final errors = <String>[];
      final validatedData = <Map<String, dynamic>>[];

      // STEP 1: Pre-validate all rows and collect emails
      final emailsToCheck = <String>[];
      final tempValidatedData = <Map<String, dynamic>>[];

      for (int i = 1; i < tableRows.length; i++) {
        final result = validateAndParseUserRow(tableRows[i], header, columnIndices, i);
        if (result.isValid) {
          final email = result.data!['email'];
          emailsToCheck.add(email);
          tempValidatedData.add(result.data!);
        } else {
          skipped++;
          errors.add(result.error!);
        }
      }

      // STEP 2: COST OPTIMIZATION - Batch check user existence in Firestore
      if (skipExisting && emailsToCheck.isNotEmpty) {
        await _batchCheckUserExistence(emailsToCheck);
      }

      // STEP 3: NEW - Batch check Firebase Auth existence
      if (emailsToCheck.isNotEmpty) {
        print('🔍 Checking Firebase Authentication for ${emailsToCheck.length} emails...');
        await _batchCheckFirebaseAuth(emailsToCheck);
      }

      // STEP 4: Filter out existing users and collect emails needing reset
      final emailsNeedingReset = <String>[];
      for (var data in tempValidatedData) {
        final email = data['email'];

        if (skipExisting && userExists(email)) {
          existing++;
          continue;
        }

        validatedData.add(data);

        // NEW: Auto-collect emails that need password reset (not in Firebase Auth)
        if (!userExistsInAuth(email)) {
          emailsNeedingReset.add(email);
        }
      }

      // STEP 5: Process in optimized batches
      const int batchSize = 500; // Firestore batch limit
      final firestore = FirebaseFirestore.instance;
      WriteBatch? batch;
      int batchCount = 0;

      for (int i = 0; i < validatedData.length; i++) {
        if (batchCount == 0) {
          batch = firestore.batch();
        }

        final data = validatedData[i];
        final docRef = firestore.collection('users').doc(data['email']);

        batch!.set(docRef, data['userData'], SetOptions(merge: true));
        uploaded++;
        batchCount++;

        // Commit batch when it reaches limit or is the last item
        if (batchCount >= batchSize || i == validatedData.length - 1) {
          await batch.commit();
          batchCount = 0;
          print('✅ Batch ${(i / batchSize).ceil()} committed');
        }
      }

      String emailResetMessage = "";
      if (emailsNeedingReset.isNotEmpty) {
        print('🔧 Creating Firebase Auth accounts for ${emailsNeedingReset.length} new users...');
        final emailResults = await batchCreateUsersAndSendResetEmails(emailsNeedingReset);
        emailResetMessage = "\n🔧 New users - Auth accounts created: ${emailResults['successful']}"
            "${emailResults['failed']! > 0 ? ', failed: ${emailResults['failed']}' : ''}"
            "\n📧 Password reset emails sent to new accounts";
      }

      // Clear caches after processing
      FileProcessingUtils.clearCaches();
      _userExistsCache.clear();
      _firebaseAuthCache.clear();

      String existingMessage = existing > 0
          ? "Existing users skipped: $existing\n"
          : "";

      String errorReport = errors.isEmpty
          ? ""
          : "Issues found:\n${errors.take(10).join('\n')}${errors.length > 10 ? '\n... and ${errors.length - 10} more errors' : ''}";

      return "✅ User Upload Complete!\n"
          "Processed: ${tableRows.length - 1} rows\n"
          "Uploaded: $uploaded\n"
          "Skipped due to errors: $skipped\n"
          "$existingMessage$emailResetMessage\n$errorReport";

    } catch (e, stackTrace) {
      FileProcessingUtils.clearCaches();
      _userExistsCache.clear();
      _firebaseAuthCache.clear();
      return "❌ Error during user import: $e";
    }
  }



  // Clear all caches
  void clearCaches() {
    FileProcessingUtils.clearCaches();
    _userExistsCache.clear();
    _firebaseAuthCache.clear();
  }
}