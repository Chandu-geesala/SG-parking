import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';

String makeSenecaMail(String name) {
  if (name.isEmpty) return "";
  final parts = name.trim().split(RegExp(r'\s+'));
  final email = parts.map((e) => e.toLowerCase()).join('.') + '@senecaglobal.com';
  return email;
}

String extractCellValue(dynamic cell) {
  if (cell == null) return '';
  if (cell is Data) return cell.value?.toString().trim() ?? '';
  return cell.toString().trim();
}

String parseDateOrNow(String input) {
  if (input == null || input.trim().isEmpty) return DateTime.now().toIso8601String();
  try {
    return DateTime.parse(input).toIso8601String();
  } catch (_) {}
  try {
    final parts = input.trim().split(RegExp(r'[-/]'));
    if (parts.length == 3) {
      int year = int.parse(parts[0].length == 4 ? parts[0] : parts[2]);
      int month = int.parse(parts[1]);
      int day = int.parse(parts[0].length == 4 ? parts[2] : parts[0]);
      return DateTime(year, month, day).toIso8601String();
    }
  } catch (_) {}
  return DateTime.now().toIso8601String();
}

Future<void> clearSlotsCollection() async {
  final firestore = FirebaseFirestore.instance;
  final collection = firestore.collection('Slots');
  final querySnapshot = await collection.get();
  final batch = firestore.batch();
  int batchCount = 0;
  for (var doc in querySnapshot.docs) {
    batch.delete(doc.reference);
    batchCount++;
    if (batchCount >= 500) {
      await batch.commit();
      batchCount = 0;
    }
  }
  if (batchCount > 0) await batch.commit();
}

/// Show correct format as a sample string
String correctFormatString() {
  return 'Correct columns: Slot No, Category, Buddy-1, Buddy-2, Vehicle compatibility, Alloted Date';
}

Future<String> processExcelOrCsvFile(String filePath, {bool clearExisting = true}) async {
  final isExcel = filePath.toLowerCase().endsWith('.xlsx');
  final isCsv = filePath.toLowerCase().endsWith('.csv');
  List<List<dynamic>> tableRows = [];

  try {
    if (clearExisting) {
      await clearSlotsCollection();
    }

    if (isExcel) {
      final bytes = File(filePath).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first;
      tableRows = sheet!.rows;
    } else if (isCsv) {
      final content = File(filePath).readAsStringSync();
      tableRows = CsvToListConverter(eol: "\n").convert(content);
    } else {
      return "Unsupported file type: $filePath";
    }

    if (tableRows.isEmpty) return "No data found in file.";

    final header = tableRows.first.map((cell) => extractCellValue(cell)).toList();
    final idxSlotNo = header.indexOf("Slot No");
    final idxCategory = header.indexOf("Category");
    final idxBuddy1 = header.indexOf("Buddy-1");
    final idxBuddy2 = header.indexOf("Buddy-2");
    final idxVehicleCompatibility = header.indexOf("Vehicle compatibility");
    final idxAllotedDate = header.indexOf("Alloted Date");

    // Check required columns and inform user
    List<String> missingCols = [];
    if (idxSlotNo == -1) missingCols.add("Slot No");
    if (idxCategory == -1) missingCols.add("Category");
    if (idxBuddy1 == -1) missingCols.add("Buddy-1");
    if (missingCols.isNotEmpty) {
      return
        "Missing columns: ${missingCols.join(', ')}\n"
            "${correctFormatString()}\n"
            "Present columns: ${header.join(', ')}";
    }

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    int uploaded = 0, skipped = 0;
    final errors = <String>[];

    for (int i = 1; i < tableRows.length; i++) {
      final row = tableRows[i];
      if (row.length < header.length) {
        skipped++;
        errors.add(
            "Row ${i+1}: Not enough columns (expected ${header.length}, found ${row.length})."
                " Format: ${correctFormatString()}");
        continue;
      }

      String slotNo = extractCellValue(row[idxSlotNo]);
      if (slotNo.isEmpty) {
        skipped++;
        errors.add("Row ${i+1}: Empty Slot No (slot number is required).");
        continue;
      }

      String vehicleType = extractCellValue(row[idxCategory]).toUpperCase();
      if (vehicleType.isEmpty) vehicleType = "BIKE";

      String buddy1 = extractCellValue(row[idxBuddy1]);
      String buddy2 = idxBuddy2 != -1 ? extractCellValue(row[idxBuddy2]) : "";
      String allotedDate = idxAllotedDate != -1
          ? parseDateOrNow(extractCellValue(row[idxAllotedDate]))
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

      if (vehicleType == "CAR") {
        String vehicleCompatibility = "";
        if (slotNo.toLowerCase().contains("upper")) vehicleCompatibility = "UPPER";
        else if (slotNo.toLowerCase().contains("lower")) vehicleCompatibility = "LOWER";
        if (vehicleCompatibility.isEmpty && idxVehicleCompatibility != -1) {
          String compatibilityValue = extractCellValue(row[idxVehicleCompatibility]).toUpperCase();
          if (compatibilityValue.contains("UPPER")) vehicleCompatibility = "UPPER";
          else if (compatibilityValue.contains("LOWER")) vehicleCompatibility = "LOWER";
        }
        if (vehicleCompatibility.isNotEmpty) {
          docData["VehicleCompatibility"] = vehicleCompatibility;
        }
      }

      String docName = slotNo
          .replaceAll(RegExp(r'\s+'), '-')
          .replaceAll('(', '')
          .replaceAll(')', '')
          .replaceAll('/', '-')
          .replaceAll('--', '-')
          .toLowerCase();
      docName = docName.replaceAll(RegExp(r'-+$'), '');

      batch.set(firestore.collection('Slots').doc(docName), docData);
      uploaded++;
    }

    await batch.commit();

    String clearMessage = clearExisting
        ? "Collection cleared and fresh data uploaded.\n"
        : "Data merged with existing collection.\n";
    String errorReport = errors.isEmpty
        ? ""
        : "Some rows skipped. Issues:\n${errors.take(10).join('\n')}${errors.length > 10 ? "\n..." : ""}";
    return "${clearMessage}Upload Complete.\nUploaded: $uploaded\nSkipped: $skipped\n$errorReport";
  } catch (e, stk) {
    return "Error during import: $e\n$stk";
  }
}
