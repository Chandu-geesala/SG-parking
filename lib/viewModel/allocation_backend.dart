import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

class CombinedUploadService {
  // Cache for processed data to avoid duplicates
  static final Map<String, bool> _processedUsers = {};
  static final Map<String, String> _emailToNameCache = {};
  static final Map<String, String> _dateCache = {};
  static final Map<String, bool> _userExistsCache = {};
  static final Map<String, bool> _firebaseAuthCache = {};

  // Extract name from email (firstname.lastname@domain.com -> Firstname Lastname)
  String extractNameFromEmail(String email) {
    if (email.isEmpty) return 'Unknown User';

    // Use cached result if available
    if (_emailToNameCache.containsKey(email)) {
      return _emailToNameCache[email]!;
    }

    try {
      String username = email.split('@')[0];
      List<String> parts = username.split(RegExp(r'[._]'));

      List<String> capitalizedParts = parts.map((part) {
        if (part.isEmpty) return '';
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      }).where((part) => part.isNotEmpty).toList();

      String name = capitalizedParts.join(' ');
      _emailToNameCache[email] = name;
      return name;
    } catch (e) {
      String fallbackName = 'Unknown User';
      _emailToNameCache[email] = fallbackName;
      return fallbackName;
    }
  }

  // Enhanced cell extraction with better null handling
  String extractCellValue(dynamic cell) {
    if (cell == null) return '';

    if (cell is String) {
      return cell.trim();
    }

    if (cell is Data) {
      if (cell.value == null) return '';
      return cell.value.toString().trim();
    }

    if (cell is num) {
      return cell.toString();
    }

    return cell.toString().trim();
  }

  // Flexible date parsing
  String parseDateFlexible(String input) {
    if (input.isEmpty) return DateTime.now().toIso8601String();

    // Use cached result if available
    if (_dateCache.containsKey(input)) {
      return _dateCache[input]!;
    }

    String result;
    try {
      // Try direct parsing first
      result = DateTime.parse(input).toIso8601String();
    } catch (_) {
      try {
        // Handle various date formats: DD-MM-YYYY, DD/MM/YYYY, MM-DD-YYYY, etc.
        final cleanInput = input.trim().replaceAll(RegExp(r'[^\d\-\/]'), '');
        final parts = cleanInput.split(RegExp(r'[-\/]'));

        if (parts.length == 3) {
          int day, month, year;

          // Detect year position (assume 4-digit year)
          if (parts[0].length == 4) {
            // YYYY-MM-DD or YYYY-DD-MM
            year = int.parse(parts[0]);
            month = int.parse(parts[1]);
            day = int.parse(parts[2]);
          } else if (parts[2].length == 4) {
            // DD-MM-YYYY or MM-DD-YYYY
            year = int.parse(parts[2]);
            // Assume DD-MM-YYYY format (common in India)
            day = int.parse(parts[0]);
            month = int.parse(parts[1]);
          } else {
            // Handle 2-digit years (assume 20XX)
            year = 2000 + int.parse(parts[2]);
            day = int.parse(parts[0]);
            month = int.parse(parts[1]);
          }

          // Validate ranges
          if (month > 12) month = 12;
          if (day > 31) day = 31;
          if (month < 1) month = 1;
          if (day < 1) day = 1;

          result = DateTime(year, month, day).toIso8601String();
        } else {
          result = DateTime.now().toIso8601String();
        }
      } catch (_) {
        result = DateTime.now().toIso8601String();
      }
    }

    _dateCache[input] = result;
    return result;
  }

  // Parse period to months
  int parsePeriodToMonths(String period) {
    if (period.isEmpty) return 6; // Default 6 months

    final periodLower = period.toLowerCase().trim();

    if (periodLower.contains('year')) {
      final yearMatch = RegExp(r'(\d+)').firstMatch(periodLower);
      if (yearMatch != null) {
        return int.parse(yearMatch.group(1)!) * 12;
      }
      return 12; // Default 1 year
    } else if (periodLower.contains('month')) {
      final monthMatch = RegExp(r'(\d+)').firstMatch(periodLower);
      if (monthMatch != null) {
        return int.parse(monthMatch.group(1)!);
      }
      return 6; // Default 6 months
    }

    return 6; // Default fallback
  }

  // Email validation
  bool isValidEmail(String email) {
    if (email.isEmpty) return false;
    final emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  // Phone validation
  bool isValidPhone(String phone) {
    if (phone.isEmpty) return false;
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    return cleanPhone.length >= 10;
  }

  // Map columns with flexible matching
  Map<String, int> mapCombinedColumns(List<String> header) {
    final columnIndices = <String, int>{};

    for (int i = 0; i < header.length; i++) {
      final col = header[i].toLowerCase().trim();

      // Slot columns
      if (col.contains('slot') && col.contains('no')) {
        columnIndices['slotNo'] = i;
      } else if (col.contains('category')) {
        columnIndices['category'] = i;
      } else if (col.contains('vehicle') && col.contains('compatibility')) {
        columnIndices['vehicleCompatibility'] = i;
      } else if (col.contains('dimension')) {
        columnIndices['dimension'] = i;
      } else if (col.contains('remark')) {
        columnIndices['remarks'] = i;
      }
      // Buddy columns
      else if (col.contains('buddy1') || col == 'buddy 1') {
        columnIndices['buddy1'] = i;
      } else if (col.contains('buddy2') || col == 'buddy 2') {
        columnIndices['buddy2'] = i;
      }
      // Date columns (specific to each buddy)
      else if (col.contains('allot') && col.contains('date') && col.contains('buddy') && col.contains('1')) {
        columnIndices['allottedDateBuddy1'] = i;
      } else if (col.contains('allot') && col.contains('date') && col.contains('buddy') && col.contains('2')) {
        columnIndices['allottedDateBuddy2'] = i;
      }
      // Period columns (specific to each buddy)
      else if (col.contains('period') && col.contains('buddy') && col.contains('1')) {
        columnIndices['periodBuddy1'] = i;
      } else if (col.contains('period') && col.contains('buddy') && col.contains('2')) {
        columnIndices['periodBuddy2'] = i;
      }
      // Phone columns (specific to each buddy)
      else if (col.contains('phone') && col.contains('buddy') && col.contains('1')) {
        columnIndices['phoneBuddy1'] = i;
      } else if (col.contains('phone') && col.contains('buddy') && col.contains('2')) {
        columnIndices['phoneBuddy2'] = i;
      }
      // Other columns
      else if (col.contains('vehicle') && !col.contains('compatibility')) {
        columnIndices['vehicles'] = i;
      } else if (col.contains('usertype') || col.contains('user type')) {
        columnIndices['userType'] = i;
      }
    }

    return columnIndices;
  }

  // Batch check Firebase Auth existence
  Future<void> _batchCheckFirebaseAuth(List<String> emails) async {
    try {
      _firebaseAuthCache.clear();

      const int concurrentLimit = 5;
      for (int i = 0; i < emails.length; i += concurrentLimit) {
        final batch = emails.skip(i).take(concurrentLimit).toList();
        final futures = batch.map((email) => _checkSingleEmailInAuth(email));
        await Future.wait(futures);

        if (i + concurrentLimit < emails.length) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      print('✅ Firebase Auth check completed for ${emails.length} emails');
    } catch (e) {
      print('❌ Error in Firebase Auth batch check: $e');
      for (String email in emails) {
        _firebaseAuthCache[email] = false;
      }
    }
  }

  Future<void> _checkSingleEmailInAuth(String email) async {
    try {
      final userRecord = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
      _firebaseAuthCache[email] = userRecord.isNotEmpty;
    } catch (e) {
      _firebaseAuthCache[email] = false;
    }
  }

  bool userExistsInAuth(String email) {
    return _firebaseAuthCache[email] ?? false;
  }

  // Batch check user existence in Firestore
  Future<void> _batchCheckUserExistence(List<String> emails) async {
    try {
      _userExistsCache.clear();

      const int chunkSize = 10;
      for (int i = 0; i < emails.length; i += chunkSize) {
        final chunk = emails.skip(i).take(chunkSize).toList();

        final querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (var doc in querySnapshot.docs) {
          _userExistsCache[doc.id] = true;
        }

        for (String email in chunk) {
          if (!_userExistsCache.containsKey(email)) {
            _userExistsCache[email] = false;
          }
        }
      }

      print('✅ Batch existence check completed for ${emails.length} emails');
    } catch (e) {
      print('❌ Error in batch existence check: $e');
      for (String email in emails) {
        _userExistsCache[email] = false;
      }
    }
  }

  bool userExists(String email) {
    return _userExistsCache[email] ?? false;
  }

  // Create user and send reset email
  Future<bool> createUserAndSendResetEmail(String email) async {
    try {
      String tempPassword = _generateTempPassword();

      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: tempPassword,
      );

      print('✅ Created auth account for: $email');

      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      print('📧 Password reset email sent to: $email');

      return true;
    } catch (e) {
      print('❌ Failed to create account or send reset email to $email: $e');
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

  // Process file to get table rows
  Future<List<List<dynamic>>> _processFileToRows({
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    List<List<dynamic>> tableRows = [];

    String fileExtension;
    if (fileName != null) {
      fileExtension = fileName.toLowerCase().split('.').last;
    } else if (filePath != null) {
      fileExtension = filePath.toLowerCase().split('.').last;
    } else {
      throw Exception("No file information provided");
    }

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
        if (sheet == null || sheet.rows.isEmpty) {
          throw Exception("Empty Excel sheet found.");
        }
        tableRows = sheet.rows.map((row) {
          if (row == null) return <dynamic>[];
          return row.map((cell) => cell?.value).toList();
        }).where((row) => row.isNotEmpty).toList();
      } else if (fileExtension == 'csv') {
        final content = String.fromCharCodes(fileBytes);
        tableRows = const CsvToListConverter(eol: "\n", allowInvalid: false).convert(content);
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
        if (sheet == null || sheet.rows.isEmpty) {
          throw Exception("Empty Excel sheet found.");
        }
        tableRows = sheet.rows.map((row) {
          if (row == null) return <dynamic>[];
          return row.map((cell) => cell?.value).toList();
        }).where((row) => row.isNotEmpty).toList();
      } else if (fileExtension == 'csv') {
        final content = File(filePath).readAsStringSync();
        tableRows = const CsvToListConverter(eol: "\n", allowInvalid: false).convert(content);
      }
    }

    return tableRows;
  }

  // Main combined processing function
  Future<String> processCombinedFile({
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
    bool clearExistingSlots = true,
  }) async {
    try {
      // Clear all caches at start
      _clearAllCaches();

      // Step 1: Process file to get rows
      List<List<dynamic>> tableRows = await _processFileToRows(
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: fileName,
      );

      if (tableRows.isEmpty) return "No data found in file.";

      // Step 2: Parse header and create column index map
      final header = tableRows.first
          .map((cell) => extractCellValue(cell))
          .toList();

      final columnIndices = mapCombinedColumns(header);

      // Step 3: Validate required columns
      if (!columnIndices.containsKey('slotNo')) {
        return "❌ Missing required column: Slot No\n"
            "Expected columns: Slot No, Category, Buddy1, Buddy2, etc.\n"
            "Present columns: ${header.join(', ')}";
      }

      if (!columnIndices.containsKey('buddy1')) {
        return "❌ Missing required column: Buddy1\n"
            "Present columns: ${header.join(', ')}";
      }

      // Step 4: Clear slots collection if requested
      if (clearExistingSlots) {
        await _clearSlotsCollection();
        print('🗑️ Cleared existing slots collection');
      }

      // Step 5: Extract and validate data
      final validatedUsers = <String, Map<String, dynamic>>{};
      final validatedSlots = <Map<String, dynamic>>[];
      final allUserEmails = <String>{};
      final errors = <String>[];
      int skippedRows = 0;

      for (int i = 1; i < tableRows.length; i++) {
        final row = tableRows[i];

        // Skip empty rows
        if (row.isEmpty || row.every((cell) => extractCellValue(cell).isEmpty)) {
          continue;
        }

        try {
          final result = _validateAndParseCombinedRow(row, columnIndices, i);
          if (result['success']) {
            // Add users to collection
            final users = result['users'] as Map<String, Map<String, dynamic>>;
            for (var entry in users.entries) {
              validatedUsers[entry.key] = entry.value;
              allUserEmails.add(entry.key);
            }

            // Add slot to collection
            validatedSlots.add(result['slot']);
          } else {
            errors.add(result['error']);
            skippedRows++;
          }
        } catch (e) {
          errors.add("Row ${i + 1}: Error processing data - $e");
          skippedRows++;
        }
      }

      if (validatedUsers.isEmpty && validatedSlots.isEmpty) {
        return "❌ No valid data found to process.\n"
            "Errors: ${errors.take(5).join('\n')}";
      }

      // Step 6: Process users first
      int usersUploaded = 0;
      int usersSkipped = 0;
      int emailsSent = 0;

      if (allUserEmails.isNotEmpty) {
        print('👥 Processing ${allUserEmails.length} unique users...');

        // Check existing users
        await _batchCheckUserExistence(allUserEmails.toList());
        await _batchCheckFirebaseAuth(allUserEmails.toList());

        // Process users in batches
        final firestore = FirebaseFirestore.instance;
        WriteBatch userBatch = firestore.batch();
        int userBatchCount = 0;
        const int batchSize = 500;

        final newUserEmails = <String>[];

        for (var entry in validatedUsers.entries) {
          final email = entry.key;
          final userData = entry.value;

          if (userExists(email)) {
            usersSkipped++;
            continue;
          }

          final docRef = firestore.collection('users').doc(email);
          userBatch.set(docRef, userData, SetOptions(merge: true));
          usersUploaded++;
          userBatchCount++;

          // Check if user needs Firebase Auth account
          if (!userExistsInAuth(email)) {
            newUserEmails.add(email);
          }

          if (userBatchCount >= batchSize) {
            await userBatch.commit();
            userBatch = firestore.batch();
            userBatchCount = 0;
          }
        }

        if (userBatchCount > 0) {
          await userBatch.commit();
        }

        // Send reset emails to new users
        if (newUserEmails.isNotEmpty) {
          print('🔧 Creating Firebase Auth accounts for ${newUserEmails.length} new users...');

          for (String email in newUserEmails) {
            if (await createUserAndSendResetEmail(email)) {
              emailsSent++;
            }
            await Future.delayed(const Duration(milliseconds: 500)); // Rate limiting
          }
        }

        print('✅ Users processing completed: $usersUploaded uploaded, $usersSkipped skipped');
      }

      // Step 7: Process slots
      int slotsUploaded = 0;
      int slotsSkipped = 0;

      if (validatedSlots.isNotEmpty) {
        print('🅿️ Processing ${validatedSlots.length} slots...');

        final firestore = FirebaseFirestore.instance;
        WriteBatch slotBatch = firestore.batch();
        int slotBatchCount = 0;
        const int batchSize = 450;

        for (var slotData in validatedSlots) {
          try {
            final docName = slotData['docName'];
            final docData = slotData['docData'];

            final docRef = firestore.collection('Slots').doc(docName);
            slotBatch.set(docRef, docData);
            slotsUploaded++;
            slotBatchCount++;

            if (slotBatchCount >= batchSize) {
              await slotBatch.commit();
              slotBatch = firestore.batch();
              slotBatchCount = 0;
            }
          } catch (e) {
            slotsSkipped++;
            errors.add("Failed to process slot ${slotData['docName']}: $e");
          }
        }

        if (slotBatchCount > 0) {
          await slotBatch.commit();
        }

        print('✅ Slots processing completed: $slotsUploaded uploaded, $slotsSkipped skipped');
      }

      // Clear caches
      _clearAllCaches();

      // Step 8: Generate summary report
      String clearMessage = clearExistingSlots
          ? "🗑️ Existing slots cleared and fresh data uploaded.\n"
          : "🔄 Data merged with existing collections.\n";

      String errorReport = errors.isEmpty
          ? ""
          : "\n⚠️ Issues found (first 10):\n${errors.take(10).join('\n')}${errors.length > 10 ? '\n... and ${errors.length - 10} more issues' : ''}";

      return "${clearMessage}"
          "✅ Combined Upload Complete!\n\n"
          "📊 SUMMARY:\n"
          "Total rows processed: ${tableRows.length - 1}\n"
          "Rows skipped due to errors: $skippedRows\n\n"
          "👥 USERS:\n"
          "Users uploaded: $usersUploaded\n"
          "Users skipped (existing): $usersSkipped\n"
          "📧 Firebase Auth accounts created: $emailsSent\n\n"
          "🅿️ SLOTS:\n"
          "Slots uploaded: $slotsUploaded\n"
          "Slots skipped: $slotsSkipped"
          "$errorReport";

    } catch (e, stackTrace) {
      _clearAllCaches();
      return "❌ Error during combined import: $e\n"
          "Please check your file format and try again.";
    }
  }

  // Validate and parse combined row data
  Map<String, dynamic> _validateAndParseCombinedRow(
      List<dynamic> row,
      Map<String, int> columnIndices,
      int rowIndex,
      ) {
    // Safe cell extraction
    String safeExtractCell(String columnKey) {
      final index = columnIndices[columnKey];
      if (index == null || index >= row.length) {
        return '';
      }
      return extractCellValue(row[index]);
    }

    // Extract slot data
    String slotNo = safeExtractCell('slotNo');
    if (slotNo.isEmpty) {
      return {'success': false, 'error': "Row ${rowIndex + 1}: Empty Slot No"};
    }

    String category = safeExtractCell('category').toUpperCase();
    if (category.isEmpty || (!category.contains('BIKE') && !category.contains('CAR'))) {
      category = "BIKE"; // Default fallback
    }

    String buddy1Email = safeExtractCell('buddy1').trim();
    String buddy2Email = safeExtractCell('buddy2').trim();

    if (buddy1Email.isEmpty) {
      return {'success': false, 'error': "Row ${rowIndex + 1}: Buddy1 email is required"};
    }

    if (!isValidEmail(buddy1Email)) {
      return {'success': false, 'error': "Row ${rowIndex + 1}: Invalid Buddy1 email format"};
    }

    if (buddy2Email.isNotEmpty && !isValidEmail(buddy2Email)) {
      return {'success': false, 'error': "Row ${rowIndex + 1}: Invalid Buddy2 email format"};
    }

    // Extract buddy-specific data
    String allottedDateBuddy1 = safeExtractCell('allottedDateBuddy1');
    String allottedDateBuddy2 = safeExtractCell('allottedDateBuddy2');
    String periodBuddy1 = safeExtractCell('periodBuddy1');
    String periodBuddy2 = safeExtractCell('periodBuddy2');
    String phoneBuddy1 = safeExtractCell('phoneBuddy1');
    String phoneBuddy2 = safeExtractCell('phoneBuddy2');

    // Validate and parse dates
    String parsedDateBuddy1 = allottedDateBuddy1.isNotEmpty
        ? parseDateFlexible(allottedDateBuddy1)
        : DateTime.now().toIso8601String();

    String parsedDateBuddy2 = buddy2Email.isNotEmpty && allottedDateBuddy2.isNotEmpty
        ? parseDateFlexible(allottedDateBuddy2)
        : parsedDateBuddy1; // Default to buddy1's date if buddy2 date is missing

    // Extract other slot data
    String vehicleCompatibility = safeExtractCell('vehicleCompatibility').toUpperCase();
    String dimension = safeExtractCell('dimension');
    String remarks = safeExtractCell('remarks');
    String vehicles = safeExtractCell('vehicles');
    String userType = safeExtractCell('userType').toLowerCase();
    if (userType.isEmpty || !['user', 'admin'].contains(userType)) {
      userType = 'user';
    }

    // Build users data
    final usersData = <String, Map<String, dynamic>>{};

    // Buddy1 user data
    Map<String, dynamic> buddy1UserData = {
      'name': extractNameFromEmail(buddy1Email),
      'email': buddy1Email,
      'userType': userType,
      'createdAt': FieldValue.serverTimestamp(),
      'platform': 'bulk_upload',
    };

    if (phoneBuddy1.isNotEmpty && isValidPhone(phoneBuddy1)) {
      buddy1UserData['phone'] = phoneBuddy1;
    }

    if (vehicles.isNotEmpty) {
      buddy1UserData['vehicles'] = _parseVehicleData(vehicles);
    }

    usersData[buddy1Email] = buddy1UserData;

    // Buddy2 user data (if exists)
    if (buddy2Email.isNotEmpty) {
      Map<String, dynamic> buddy2UserData = {
        'name': extractNameFromEmail(buddy2Email),
        'email': buddy2Email,
        'userType': userType,

        'createdAt': FieldValue.serverTimestamp(),
        'platform': 'bulk_upload',
      };

      if (phoneBuddy2.isNotEmpty && isValidPhone(phoneBuddy2)) {
        buddy2UserData['phone'] = phoneBuddy2;
      }

      if (vehicles.isNotEmpty) {
        buddy2UserData['vehicles'] = _parseVehicleData(vehicles);
      }

      usersData[buddy2Email] = buddy2UserData;
    }



    // Build allotted_to array with individual expiry dates
    List<Map<String, dynamic>> allottedTo = [];

// Add buddy1
    int periodMonthsBuddy1 = parsePeriodToMonths(periodBuddy1.isNotEmpty ? periodBuddy1 : '6 months');
    DateTime buddy1ExpiryDate;
    try {
      buddy1ExpiryDate = DateTime.parse(parsedDateBuddy1).add(Duration(days: periodMonthsBuddy1 * 30));
    } catch (e) {
      buddy1ExpiryDate = DateTime.now().add(Duration(days: periodMonthsBuddy1 * 30));
    }

    allottedTo.add({
      "name": extractNameFromEmail(buddy1Email),
      "email": buddy1Email,
      "alloted_date": parsedDateBuddy1,
      "period": periodBuddy1.isNotEmpty ? periodBuddy1 : '6 months',
      "period_months": periodMonthsBuddy1,
      "expiry_date": buddy1ExpiryDate.toIso8601String(),
    });

// Add buddy2 if exists
    if (buddy2Email.isNotEmpty) {
      int periodMonthsBuddy2 = parsePeriodToMonths(periodBuddy2.isNotEmpty ? periodBuddy2 : periodBuddy1.isNotEmpty ? periodBuddy1 : '6 months');
      DateTime buddy2ExpiryDate;
      try {
        buddy2ExpiryDate = DateTime.parse(parsedDateBuddy2).add(Duration(days: periodMonthsBuddy2 * 30));
      } catch (e) {
        buddy2ExpiryDate = DateTime.now().add(Duration(days: periodMonthsBuddy2 * 30));
      }

      allottedTo.add({
        "name": extractNameFromEmail(buddy2Email),
        "email": buddy2Email,
        "alloted_date": parsedDateBuddy2,
        "period": periodBuddy2.isNotEmpty ? periodBuddy2 : (periodBuddy1.isNotEmpty ? periodBuddy1 : '6 months'),
        "period_months": periodMonthsBuddy2,
        "expiry_date": buddy2ExpiryDate.toIso8601String(),
      });
    }

// Determine slot priority
    String slotPriority = allottedTo.length > 1 ? "hybrid" : "permanent";






    // Calculate expiry date (use the latest expiry between buddies)
    DateTime expiryDateTime;
    try {
      DateTime buddy1Expiry = DateTime.parse(parsedDateBuddy1).add(Duration(days: periodMonthsBuddy1 * 30));
      expiryDateTime = buddy1Expiry;

      if (buddy2Email.isNotEmpty) {
        int periodMonthsBuddy2 = parsePeriodToMonths(periodBuddy2.isNotEmpty ? periodBuddy2 : periodBuddy1.isNotEmpty ? periodBuddy1 : '6 months');
        DateTime buddy2Expiry = DateTime.parse(parsedDateBuddy2).add(Duration(days: periodMonthsBuddy2 * 30));
        if (buddy2Expiry.isAfter(expiryDateTime)) {
          expiryDateTime = buddy2Expiry;
        }
      }
    } catch (e) {
      expiryDateTime = DateTime.now().add(const Duration(days: 180));
    }

    // Build slot document data
// Build slot document data
    Map<String, dynamic> slotDocData = {
      "slotNo": slotNo,
      "vehicleType": category,
      "slotPriority": slotPriority,
      "alloted_to": allottedTo,
      "status": "active",
    };

    // Add vehicle compatibility for cars
    if (category == "CAR" && vehicleCompatibility.isNotEmpty) {
      if (vehicleCompatibility.contains("UPPER")) {
        slotDocData["vehicleCompatibility"] = "UPPER";
      } else if (vehicleCompatibility.contains("LOWER")) {
        slotDocData["vehicleCompatibility"] = "LOWER";
      }
    }

    // Add dimension if available
    if (dimension.isNotEmpty) {
      slotDocData["dimension"] = dimension;
    }

    // Add remarks if available
    if (remarks.isNotEmpty) {
      slotDocData["remarks"] = remarks;
    }

// Generate clean document name for slot
    String docName = slotNo
        .replaceAll(RegExp(r'\s+'), '-')         // Replace spaces with hyphens
        .replaceAll('(', '')                     // Remove (
        .replaceAll(')', '')                     // Remove )
        .replaceAll('/', '-')                    // Replace / with -
        .replaceAll(RegExp(r'[^\w\-]'), '')      // Remove all non-word characters except hyphen
        .replaceAll(RegExp(r'-+'), '-')          // Replace multiple hyphens with single
        .replaceAll(RegExp(r'^-+|-+$'), '')      // Trim leading/trailing hyphens
        .toLowerCase();                          // Convert to lowercase

    if (docName.isEmpty) {
      docName = "slot-${rowIndex + 1}";
    }


        return {
        'success': true,
        'users': usersData,
        'slot': {
        'docName': docName,
        'docData': slotDocData,
        }
        };
    }

  // Parse vehicle data from Excel cell
  List<Map<String, dynamic>> _parseVehicleData(String vehicleInput) {
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

  // Clear all caches
  void _clearAllCaches() {
    _processedUsers.clear();
    _emailToNameCache.clear();
    _dateCache.clear();
    _userExistsCache.clear();
    _firebaseAuthCache.clear();
  }

  // File picker for combined files
  Future<FilePickerResult?> pickCombinedFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        allowMultiple: false,
      );
      return result;
    } catch (e) {
      print('File picker error: $e');
      return null;
    }
  }

  // Get format string for combined uploads
  String getCombinedFormatString() {
    return '''Expected columns for Combined Upload:

REQUIRED COLUMNS:
• Slot No - Parking slot identifier (e.g., B2-001, B3-205)
• Buddy1 - Email of first user (mandatory)

OPTIONAL COLUMNS:
• Category - Vehicle type (BIKE/CAR, defaults to BIKE)
• Vehicle Compatibility - For cars: UPPER/LOWER
• Dimension - Slot dimensions
• Remarks - Additional notes
• Buddy2 - Email of second user (optional)
• Allotted Date for Buddy 1 - Date when buddy1 was assigned
• Allotted Date for Buddy 2 - Date when buddy2 was assigned
• Period for Buddy 1 - Duration for buddy1 (e.g., "6 months", "1 year")
• Period for Buddy 2 - Duration for buddy2
• Phone for Buddy 1 - Phone number for buddy1
• Phone for Buddy 2 - Phone number for buddy2
• Vehicles - Comma-separated vehicle numbers
• UserType - user/admin (defaults to user)

IMPORTANT NOTES:
1. Each buddy gets their own separate allotted date and period
2. Names are auto-generated from emails (firstname.lastname@domain.com → Firstname Lastname)
3. Users are created first, then slots are processed
4. Firebase Auth accounts are automatically created for new users
5. Password reset emails are sent to new users''';
  }

  // Usage example method
  Future<String> uploadCombinedFile() async {
    try {
      final result = await pickCombinedFile();
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        if (kIsWeb) {
          return await processCombinedFile(
            fileBytes: file.bytes,
            fileName: file.name,
            clearExistingSlots: true,
          );
        } else {
          return await processCombinedFile(
            filePath: file.path,
            fileName: file.name,
            clearExistingSlots: true,
          );
        }
      } else {
        return "No file selected";
      }
    } catch (e) {
      return "Error uploading file: $e";
    }
  }


  // Add this method to your CombinedUploadService class

  Future<String> processCompleteReplace({
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    try {
      // Clear all caches at start
      _clearAllCaches();

      print('🚀 Starting Complete Replace Process...');

      // Step 1: Process file to get rows
      List<List<dynamic>> tableRows = await _processFileToRows(
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: fileName,
      );

      if (tableRows.isEmpty) return "❌ No data found in file.";

      // Step 2: Parse header and create column index map
      final header = tableRows.first
          .map((cell) => extractCellValue(cell))
          .toList();

      final columnIndices = mapCombinedColumns(header);

      // Step 3: Validate required columns
      if (!columnIndices.containsKey('slotNo')) {
        return "❌ Missing required column: Slot No\n"
            "Expected columns: Slot No, Category, Buddy1, Buddy2, etc.\n"
            "Present columns: ${header.join(', ')}";
      }

      if (!columnIndices.containsKey('buddy1')) {
        return "❌ Missing required column: Buddy1\n"
            "Present columns: ${header.join(', ')}";
      }

      print('✅ File validation passed. Processing ${tableRows.length - 1} rows...');

      // Step 4: Extract and validate data first (before any deletion)
      final validatedUsers = <String, Map<String, dynamic>>{};
      final validatedSlots = <Map<String, dynamic>>[];
      final allUserEmails = <String>{};
      final errors = <String>[];
      int skippedRows = 0;

      for (int i = 1; i < tableRows.length; i++) {
        final row = tableRows[i];

        // Skip empty rows
        if (row.isEmpty || row.every((cell) => extractCellValue(cell).isEmpty)) {
          continue;
        }

        try {
          final result = _validateAndParseCombinedRow(row, columnIndices, i);
          if (result['success']) {
            // Add users to collection
            final users = result['users'] as Map<String, Map<String, dynamic>>;
            for (var entry in users.entries) {
              validatedUsers[entry.key] = entry.value;
              allUserEmails.add(entry.key);
            }

            // Add slot to collection
            validatedSlots.add(result['slot']);
          } else {
            errors.add(result['error']);
            skippedRows++;
          }
        } catch (e) {
          errors.add("Row ${i + 1}: Error processing data - $e");
          skippedRows++;
        }
      }

      if (validatedUsers.isEmpty && validatedSlots.isEmpty) {
        return "❌ No valid data found to process.\n"
            "Errors: ${errors.take(5).join('\n')}";
      }

      print('✅ Data validation completed:');
      print('   - ${validatedUsers.length} unique users validated');
      print('   - ${validatedSlots.length} slots validated');
      print('   - $skippedRows rows skipped due to errors');

      // Step 5: DELETE ALL EXISTING DATA
      print('🗑️ CLEARING ALL EXISTING DATA...');

      // Clear Users collection completely
      await _clearUsersCollection();
      print('✅ Users collection cleared');

      // Clear Slots collection completely
      await _clearSlotsCollection();
      print('✅ Slots collection cleared');

      // Clear Firebase Auth users (optional - be very careful with this!)
      // await _clearFirebaseAuthUsers(); // Uncomment only if you want to delete auth accounts too

      // Step 6: Upload fresh Users data
      print('👥 UPLOADING FRESH USERS DATA...');
      int usersUploaded = 0;
      int emailsSent = 0;

      if (allUserEmails.isNotEmpty) {
        final firestore = FirebaseFirestore.instance;
        WriteBatch userBatch = firestore.batch();
        int userBatchCount = 0;
        const int batchSize = 500;

        final newUserEmails = <String>[];

        for (var entry in validatedUsers.entries) {
          final email = entry.key;
          final userData = entry.value;

          final docRef = firestore.collection('users').doc(email);
          userBatch.set(docRef, userData);
          usersUploaded++;
          userBatchCount++;
          newUserEmails.add(email);

          if (userBatchCount >= batchSize) {
            await userBatch.commit();
            print('   Batch committed: $userBatchCount users');
            userBatch = firestore.batch();
            userBatchCount = 0;
          }
        }

        if (userBatchCount > 0) {
          await userBatch.commit();
          print('   Final batch committed: $userBatchCount users');
        }

        // Create Firebase Auth accounts for all users
        print('🔧 Creating Firebase Auth accounts...');
        for (String email in newUserEmails) {
          if (await createUserAndSendResetEmail(email)) {
            emailsSent++;
          }
          // Rate limiting to avoid Firebase Auth quota issues
          await Future.delayed(const Duration(milliseconds: 500));

          // Progress indicator for large datasets
          if (emailsSent % 10 == 0) {
            print('   Created $emailsSent/${newUserEmails.length} auth accounts...');
          }
        }

        print('✅ Users upload completed: $usersUploaded users, $emailsSent auth accounts created');
      }

      // Step 7: Upload fresh Slots data
      print('🅿️ UPLOADING FRESH SLOTS DATA...');
      int slotsUploaded = 0;

      if (validatedSlots.isNotEmpty) {
        final firestore = FirebaseFirestore.instance;
        WriteBatch slotBatch = firestore.batch();
        int slotBatchCount = 0;
        const int batchSize = 450;

        for (var slotData in validatedSlots) {
          try {
            final docName = slotData['docName'];
            final docData = slotData['docData'];

            final docRef = firestore.collection('Slots').doc(docName);
            slotBatch.set(docRef, docData);
            slotsUploaded++;
            slotBatchCount++;

            if (slotBatchCount >= batchSize) {
              await slotBatch.commit();
              print('   Batch committed: $slotBatchCount slots');
              slotBatch = firestore.batch();
              slotBatchCount = 0;
            }
          } catch (e) {
            errors.add("Failed to process slot ${slotData['docName']}: $e");
          }
        }

        if (slotBatchCount > 0) {
          await slotBatch.commit();
          print('   Final batch committed: $slotBatchCount slots');
        }

        print('✅ Slots upload completed: $slotsUploaded slots');
      }

      // Clear caches
      _clearAllCaches();

      // Step 8: Generate comprehensive report
      String errorReport = errors.isEmpty
          ? ""
          : "\n⚠️ Issues found (first 10):\n${errors.take(10).join('\n')}${errors.length > 10 ? '\n... and ${errors.length - 10} more issues' : ''}";

      return "🚀 COMPLETE REPLACE SUCCESSFUL!\n\n"
          "🗑️ ALL EXISTING DATA CLEARED\n"
          "✅ FRESH DATA UPLOADED\n\n"
          "📊 PROCESSING SUMMARY:\n"
          "Total rows in file: ${tableRows.length - 1}\n"
          "Rows processed successfully: ${validatedUsers.isNotEmpty || validatedSlots.isNotEmpty ? (tableRows.length - 1 - skippedRows) : 0}\n"
          "Rows skipped due to errors: $skippedRows\n\n"
          "👥 USERS SUMMARY:\n"
          "Users uploaded: $usersUploaded\n"
          "Firebase Auth accounts created: $emailsSent\n\n"
          "🅿️ SLOTS SUMMARY:\n"
          "Slots uploaded: $slotsUploaded\n\n"
          "🎉 Database completely refreshed with new data!"
          "$errorReport";

    } catch (e, stackTrace) {
      _clearAllCaches();
      print('❌ Error during complete replace: $e');
      print('Stack trace: $stackTrace');
      return "❌ COMPLETE REPLACE FAILED: $e\n"
          "The database may be in an inconsistent state.\n"
          "Please check your file format and try again.";
    }
  }

// Helper method to clear Users collection completely
  Future<void> _clearUsersCollection() async {
    final firestore = FirebaseFirestore.instance;
    final collection = firestore.collection('users');

    const int pageSize = 100;
    bool hasMore = true;
    DocumentSnapshot? lastDoc;
    int deletedCount = 0;

    print('   Deleting users collection...');

    while (hasMore) {
      Query query = collection.limit(pageSize);
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final querySnapshot = await query.get();

      if (querySnapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      final batch = firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
        deletedCount++;
      }
      await batch.commit();

      print('   Deleted $deletedCount users so far...');

      lastDoc = querySnapshot.docs.last;
      hasMore = querySnapshot.docs.length == pageSize;

      // Small delay to avoid overwhelming Firestore
      await Future.delayed(const Duration(milliseconds: 100));
    }

    print('   ✅ Total users deleted: $deletedCount');
  }

// Enhanced slots clearing with progress tracking
  Future<void> _clearSlotsCollection() async {
    final firestore = FirebaseFirestore.instance;
    final collection = firestore.collection('Slots');

    const int pageSize = 100;
    bool hasMore = true;
    DocumentSnapshot? lastDoc;
    int deletedCount = 0;

    print('   Deleting slots collection...');

    while (hasMore) {
      Query query = collection.limit(pageSize);
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final querySnapshot = await query.get();

      if (querySnapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      final batch = firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
        deletedCount++;
      }
      await batch.commit();

      print('   Deleted $deletedCount slots so far...');

      lastDoc = querySnapshot.docs.last;
      hasMore = querySnapshot.docs.length == pageSize;

      // Small delay to avoid overwhelming Firestore
      await Future.delayed(const Duration(milliseconds: 100));
    }

    print('   ✅ Total slots deleted: $deletedCount');
  }

// DANGEROUS: Only uncomment if you want to delete Firebase Auth users too
/*
Future<void> _clearFirebaseAuthUsers() async {
  print('⚠️  WARNING: This will delete all Firebase Auth users!');
  print('   This operation is irreversible and will log out all users!');

  // This requires Firebase Admin SDK and should be done server-side
  // It's not recommended to do this from client-side Flutter app

  // Instead, you might want to disable users or handle this manually
  // through Firebase Console or server-side admin functions
}
*/

// Method for usage in UI
  Future<String> uploadCompleteReplace() async {
    try {
      final result = await pickCombinedFile();
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        if (kIsWeb) {
          return await processCompleteReplace(
            fileBytes: file.bytes,
            fileName: file.name,
          );
        } else {
          return await processCompleteReplace(
            filePath: file.path,
            fileName: file.name,
          );
        }
      } else {
        return "❌ No file selected";
      }
    } catch (e) {
      return "❌ Error during complete replace: $e";
    }
  }
}
