import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

// Cache for email generation to avoid repeated processing
final Map<String, String> _emailCache = {};

String makeSenecaMail(String name) {
  if (name.isEmpty) return "";

  // Use cached result if available
  if (_emailCache.containsKey(name)) {
    return _emailCache[name]!;
  }

  final parts = name.trim().split(RegExp(r'\s+'));
  final email = parts.map((e) => e.toLowerCase()).join('.') + '@senecaglobal.com';
  _emailCache[name] = email;
  return email;
}

// Optimized cell extraction with early returns
String extractCellValue(dynamic cell) {
  if (cell == null) return '';
  if (cell is String) return cell.trim();
  if (cell is Data) return cell.value?.toString().trim() ?? '';
  return cell.toString().trim();
}

// Cache for parsed dates
final Map<String, String> _dateCache = {};

String parseDateOrNow(String input) {
  if (input.isEmpty) return DateTime.now().toIso8601String();

  // Use cached result if available
  if (_dateCache.containsKey(input)) {
    return _dateCache[input]!;
  }

  String result;
  try {
    result = DateTime.parse(input).toIso8601String();
  } catch (_) {
    try {
      final parts = input.trim().split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        int year = int.parse(parts[0].length == 4 ? parts[0] : parts[2]);
        int month = int.parse(parts[1]);
        int day = int.parse(parts[0].length == 4 ? parts[2] : parts[0]);
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

// Optimized batch deletion with streaming
Future<void> clearSlotsCollection() async {
  final firestore = FirebaseFirestore.instance;
  final collection = firestore.collection('Slots');

  // Use pagination to avoid loading all documents at once
  const int pageSize = 100;
  bool hasMore = true;
  DocumentSnapshot? lastDoc;

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

    // Delete in smaller batches to avoid timeout
    final batch = firestore.batch();
    for (var doc in querySnapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    lastDoc = querySnapshot.docs.last;
    hasMore = querySnapshot.docs.length == pageSize;
  }
}

// Check if document exists without reading full document
Future<bool> documentExists(DocumentReference docRef) async {
  try {
    final snapshot = await docRef.get();
    return snapshot.exists;
  } catch (_) {
    return false;
  }
}

// Batch validator for better error handling
class ValidationResult {
  final bool isValid;
  final String? error;
  final Map<String, dynamic>? data;

  ValidationResult.valid(this.data) : isValid = true, error = null;
  ValidationResult.invalid(this.error) : isValid = false, data = null;
}

ValidationResult validateAndParseRow(
    List<dynamic> row,
    List<String> header,
    Map<String, int> columnIndices,
    int rowIndex
    ) {
  if (row.length < header.length) {
    return ValidationResult.invalid(
        "Row ${rowIndex + 1}: Not enough columns (expected ${header.length}, found ${row.length})"
    );
  }

  String slotNo = extractCellValue(row[columnIndices['slotNo']!]);
  if (slotNo.isEmpty) {
    return ValidationResult.invalid("Row ${rowIndex + 1}: Empty Slot No");
  }

  String vehicleType = extractCellValue(row[columnIndices['category']!]).toUpperCase();
  if (vehicleType.isEmpty) vehicleType = "BIKE";

  String buddy1 = extractCellValue(row[columnIndices['buddy1']!]);
  String buddy2 = columnIndices['buddy2'] != null
      ? extractCellValue(row[columnIndices['buddy2']!])
      : "";

  String allotedDate = columnIndices['allotedDate'] != null
      ? parseDateOrNow(extractCellValue(row[columnIndices['allotedDate']!]))
      : DateTime.now().toIso8601String();

  List<Map<String, dynamic>> allotedTo = [];
  if (buddy1.isNotEmpty) {
    allotedTo.add({
      "name": buddy1,
      "email": makeSenecaMail(buddy1),
      "alloted_date": allotedDate
    });
  }
  if (buddy2.isNotEmpty) {
    allotedTo.add({
      "name": buddy2,
      "email": makeSenecaMail(buddy2),
      "alloted_date": allotedDate
    });
  }

  String slotPriority = allotedTo.length > 1 ? "hybrid" : "permanent";

  Map<String, dynamic> docData = {
    "vehicleType": vehicleType,
    "slotPriority": slotPriority,
    "alloted_to": allotedTo,
  };

  // Handle vehicle compatibility for cars
  if (vehicleType == "CAR") {
    String vehicleCompatibility = "";
    final slotLower = slotNo.toLowerCase();

    if (slotLower.contains("upper")) {
      vehicleCompatibility = "UPPER";
    } else if (slotLower.contains("lower")) {
      vehicleCompatibility = "LOWER";
    } else if (columnIndices['vehicleCompatibility'] != null) {
      String compatibilityValue = extractCellValue(
          row[columnIndices['vehicleCompatibility']!]
      ).toUpperCase();
      if (compatibilityValue.contains("UPPER")) {
        vehicleCompatibility = "UPPER";
      } else if (compatibilityValue.contains("LOWER")) {
        vehicleCompatibility = "LOWER";
      }
    }

    if (vehicleCompatibility.isNotEmpty) {
      docData["VehicleCompatibility"] = vehicleCompatibility;
    }
  }

  // Generate clean document name
  String docName = slotNo
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll('(', '')
      .replaceAll(')', '')
      .replaceAll('/', '-')
      .replaceAll(RegExp(r'-+'), '-')  // Replace multiple dashes with single
      .replaceAll(RegExp(r'^-+|-+$'), '')  // Remove leading/trailing dashes
      .toLowerCase();

  return ValidationResult.valid({
    'docName': docName,
    'docData': docData,
  });
}

String correctFormatString() {
  return 'Correct columns: Slot No, Category, Buddy-1, Buddy-2, Vehicle compatibility, Alloted Date';
}

// NEW: File picker function for cross-platform support
Future<FilePickerResult?> pickFile() async {
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

// MODIFIED: Process file using bytes instead of path
Future<String> processExcelOrCsvFile({
  String? filePath,
  Uint8List? fileBytes,
  String? fileName,
  bool clearExisting = true
}) async {
  try {
    // Clear caches at the start of each import
    _emailCache.clear();
    _dateCache.clear();

    if (clearExisting) {
      await clearSlotsCollection();
    }

    List<List<dynamic>> tableRows = [];

    // Determine file type
    String fileExtension;
    if (fileName != null) {
      fileExtension = fileName.toLowerCase().split('.').last;
    } else if (filePath != null) {
      fileExtension = filePath.toLowerCase().split('.').last;
    } else {
      return "No file information provided";
    }

    // Process file based on platform and available data
    if (kIsWeb) {
      // WEB: Use bytes
      if (fileBytes == null) {
        return "File bytes not available for web platform";
      }

      if (fileExtension == 'xlsx') {
        final excel = Excel.decodeBytes(fileBytes);
        if (excel.tables.isEmpty) {
          return "No sheets found in Excel file.";
        }
        final sheet = excel.tables.values.first;
        tableRows = sheet!.rows;
      } else if (fileExtension == 'csv') {
        final content = String.fromCharCodes(fileBytes);
        tableRows = CsvToListConverter(eol: "\n", allowInvalid: false).convert(content);
      } else {
        return "Unsupported file type: $fileExtension";
      }
    } else {
      // MOBILE/DESKTOP: Use file path
      if (filePath == null) {
        return "File path not available for mobile/desktop platform";
      }

      if (fileExtension == 'xlsx') {
        final bytes = File(filePath).readAsBytesSync();
        final excel = Excel.decodeBytes(bytes);
        if (excel.tables.isEmpty) {
          return "No sheets found in Excel file.";
        }
        final sheet = excel.tables.values.first;
        tableRows = sheet!.rows;
      } else if (fileExtension == 'csv') {
        final content = File(filePath).readAsStringSync();
        tableRows = CsvToListConverter(eol: "\n", allowInvalid: false).convert(content);
      } else {
        return "Unsupported file type: $fileExtension";
      }
    }

    if (tableRows.isEmpty) return "No data found in file.";

    // Parse header and create column index map
    final header = tableRows.first.map((cell) => extractCellValue(cell)).toList();
    final columnIndices = <String, int>{};

    for (int i = 0; i < header.length; i++) {
      final col = header[i];
      if (col == "Slot No") columnIndices['slotNo'] = i;
      else if (col == "Category") columnIndices['category'] = i;
      else if (col == "Buddy-1") columnIndices['buddy1'] = i;
      else if (col == "Buddy-2") columnIndices['buddy2'] = i;
      else if (col == "Vehicle compatibility") columnIndices['vehicleCompatibility'] = i;
      else if (col == "Alloted Date") columnIndices['allotedDate'] = i;
    }

    // Validate required columns
    List<String> missingCols = [];
    if (!columnIndices.containsKey('slotNo')) missingCols.add("Slot No");
    if (!columnIndices.containsKey('category')) missingCols.add("Category");
    if (!columnIndices.containsKey('buddy1')) missingCols.add("Buddy-1");

    if (missingCols.isNotEmpty) {
      return "Missing columns: ${missingCols.join(', ')}\n"
          "${correctFormatString()}\n"
          "Present columns: ${header.join(', ')}";
    }

    final firestore = FirebaseFirestore.instance;
    int uploaded = 0, skipped = 0, batchCount = 0;
    final errors = <String>[];
    final validatedData = <Map<String, dynamic>>[];

    // Pre-validate all rows
    for (int i = 1; i < tableRows.length; i++) {
      final result = validateAndParseRow(tableRows[i], header, columnIndices, i);
      if (result.isValid) {
        validatedData.add(result.data!);
      } else {
        skipped++;
        errors.add(result.error!);
      }
    }

    // Process in optimized batches
    const int batchSize = 500; // Firestore batch limit
    WriteBatch? batch;

    for (int i = 0; i < validatedData.length; i++) {
      if (batchCount == 0) {
        batch = firestore.batch();
      }

      final data = validatedData[i];
      final docRef = firestore.collection('Slots').doc(data['docName']);

      batch!.set(docRef, data['docData']);
      uploaded++;
      batchCount++;

      // Commit batch when it reaches the limit or is the last item
      if (batchCount >= batchSize || i == validatedData.length - 1) {
        await batch.commit();
        batchCount = 0;
      }
    }

    // Clear caches after processing
    _emailCache.clear();
    _dateCache.clear();

    String clearMessage = clearExisting
        ? "Collection cleared and fresh data uploaded.\n"
        : "Data merged with existing collection.\n";

    String errorReport = errors.isEmpty
        ? ""
        : "Issues found:\n${errors.take(10).join('\n')}${errors.length > 10 ? '\n... and ${errors.length - 10} more errors' : ''}";

    return "${clearMessage}Upload Complete.\n"
        "Processed: ${tableRows.length - 1} rows\n"
        "Uploaded: $uploaded\n"
        "Skipped: $skipped\n$errorReport";

  } catch (e, stackTrace) {
    // Clear caches on error
    _emailCache.clear();
    _dateCache.clear();
    return "Error during import: $e\nStack trace: $stackTrace";
  }
}

