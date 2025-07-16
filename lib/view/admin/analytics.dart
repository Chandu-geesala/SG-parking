import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border ;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';


import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:park_sg/utils/analytics_helper.dart'; // Your platform-safe function
import 'package:park_sg/utils/analytics_web.dart'; // Web-specific download function
import 'package:park_sg/utils/analytics_mobile.dart'; // Mobile-specific save function
import 'dart:convert';


class AnalyticsPage extends StatefulWidget {
  final String? initialEmail;
  final String? initialSlotId;


  const AnalyticsPage({
    Key? key,
    this.initialEmail,
    this.initialSlotId,
  }) : super(key: key);

  @override
  _AnalyticsPageState createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  String _searchType = 'user'; // 'user' or 'slot'
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isExporting = false;
  double _exportProgress = 0.0;


  Map<String, dynamic>? _analyticsData;
  String? _currentQuery;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);

    if (widget.initialEmail != null) {
      _searchController.text = widget.initialEmail!;
      _searchType = 'user';
      _performSearch();
    } else if (widget.initialSlotId != null) {
      _searchController.text = widget.initialSlotId!;
      _searchType = 'slot';
      _performSearch();
    }
  }

  Future<void> _selectDateRange() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(2020);
    final DateTime lastDate = now;

    // Validate and fix the initial date range
    DateTimeRange? initialRange;
    if (_startDate != null && _endDate != null) {
      // Ensure start date is not before firstDate
      DateTime validStartDate = _startDate!.isBefore(firstDate) ? firstDate : _startDate!;

      // Ensure end date is not after lastDate
      DateTime validEndDate = _endDate!.isAfter(lastDate) ? lastDate : _endDate!;

      // Ensure start is not after end
      if (validStartDate.isAfter(validEndDate)) {
        validStartDate = validEndDate;
      }

      initialRange = DateTimeRange(start: validStartDate, end: validEndDate);
    }

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialRange,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

// Alternative: Even safer approach with debug info
  Future<void> _selectDateRangeSafe() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(2020);
    final DateTime lastDate = now;

    print('DEBUG: Current date: $now');
    print('DEBUG: _startDate: $_startDate');
    print('DEBUG: _endDate: $_endDate');

    DateTimeRange? initialRange;

    if (_startDate != null && _endDate != null) {
      // Check if dates are valid
      if (_startDate!.isAfter(lastDate) || _endDate!.isAfter(lastDate)) {
        print('WARNING: Date range is in the future, resetting to null');
        // Reset invalid future dates
        _startDate = null;
        _endDate = null;
      } else if (_startDate!.isBefore(firstDate)) {
        print('WARNING: Start date is before firstDate, adjusting');
        _startDate = firstDate;
      } else if (_startDate!.isAfter(_endDate!)) {
        print('WARNING: Start date is after end date, swapping');
        final temp = _startDate;
        _startDate = _endDate;
        _endDate = temp;
      }

      // Create initial range only if both dates are valid
      if (_startDate != null && _endDate != null) {
        initialRange = DateTimeRange(start: _startDate!, end: _endDate!);
      }
    }

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialRange,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }



  Future<List<Map<String, dynamic>>> _getAllUsersAnalytics() async {
    if (_startDate == null || _endDate == null) return [];

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
    });

    try {
      // Get all slots in one query
      final slotsSnapshot = await _firestore.collection('Slots').get();
      setState(() => _exportProgress = 0.2);

      // Create user-slot mapping
      Map<String, Map<String, dynamic>> userSlotMap = {};
      for (var slotDoc in slotsSnapshot.docs) {
        final slotData = slotDoc.data();
        final allotedTo = slotData['alloted_to'] as List<dynamic>? ?? [];

        for (var user in allotedTo) {
          final email = user['email'] as String;
          userSlotMap[email] = {
            'slotId': slotDoc.id,
            'allotedDate': user['alloted_date'],
            'slotData': slotData,
          };
        }
      }

      setState(() => _exportProgress = 0.4);

      // Get all bookings for date range in batch
      final dates = _generateDateRange(_startDate!, _endDate!);
      final userBookings = <String, List<Map<String, dynamic>>>{};

      // Process all dates concurrently (limited batches to avoid memory issues)
      for (int i = 0; i < dates.length; i += 5) {
        final dateBatch = dates.skip(i).take(5).toList();

        final futures = dateBatch.map((dateStr) async {
          final snapshot = await _firestore
              .collection('Bookings')
              .doc(dateStr)
              .collection('BookedToday')
              .get();

          return {
            'date': dateStr,
            'bookings': snapshot.docs,
          };
        });

        final results = await Future.wait(futures);

        for (final result in results) {
          final dateStr = result['date'] as String;
          final bookings = result['bookings'] as List<QueryDocumentSnapshot>;

          for (final booking in bookings) {
            final data = booking.data() as Map<String, dynamic>;
            final bookedBy = data['bookedBy'] as String;

            if (userSlotMap.containsKey(bookedBy)) {
              userBookings.putIfAbsent(bookedBy, () => []);
              userBookings[bookedBy]!.add({
                'date': dateStr,
                'slotId': booking.id,
                'bookingData': data,
              });
            }
          }
        }

        setState(() => _exportProgress = 0.4 + (0.4 * (i + 5) / dates.length));
      }

      // Build final analytics
      final userAnalytics = <Map<String, dynamic>>[];
      final totalDays = _endDate!.difference(_startDate!).inDays + 1;

      for (final email in userSlotMap.keys) {
        final slotInfo = userSlotMap[email]!;
        final bookings = userBookings[email] ?? [];
        final utilizationPercentage = (bookings.length / totalDays * 100).toDouble();

        userAnalytics.add({
          'email': email,
          'allocatedSlot': slotInfo['slotId'],
          'allotedDate': slotInfo['allotedDate'],
          'totalBookings': bookings.length,
          'utilizationPercentage': utilizationPercentage,
          'bookingHistory': bookings,
          'slotData': slotInfo['slotData'],
        });
      }

      setState(() => _exportProgress = 0.9);
      return userAnalytics;

    } catch (e) {
      print('Error getting all users analytics: $e');
      return [];
    }
  }


  Future<Map<String, dynamic>> _getUserAnalyticsForRange(
      String email,
      Map<String, dynamic> slotInfo
      ) async {
    final dates = _generateDateRange(_startDate!, _endDate!);
    final bookings = <Map<String, dynamic>>[];

    // Process dates in smaller batches
    for (int i = 0; i < dates.length; i += 10) {
      final batch = dates.skip(i).take(10).toList();

      final futures = batch.map((dateStr) =>
          _firestore
              .collection('Bookings')
              .doc(dateStr)
              .collection('BookedToday')
              .where('bookedBy', isEqualTo: email)
              .limit(1) // We only need to know if there's a booking
              .get()
      );

      final results = await Future.wait(futures);

      for (int j = 0; j < results.length; j++) {
        final querySnapshot = results[j];
        if (querySnapshot.docs.isNotEmpty) {
          final booking = querySnapshot.docs.first;
          bookings.add({
            'date': batch[j],
            'slotId': booking.id,
            'bookingData': booking.data(),
          });
        }
      }
    }

    final totalDays = _endDate!.difference(_startDate!).inDays + 1;
    final utilizationPercentage = (bookings.length / totalDays * 100).toDouble();

    return {
      'email': email,
      'allocatedSlot': slotInfo['slotId'],
      'allotedDate': slotInfo['allotedDate'],
      'totalBookings': bookings.length,
      'utilizationPercentage': utilizationPercentage,
      'bookingHistory': bookings,
      'slotData': slotInfo['slotData'],
    };
  }





  Future<List<Map<String, dynamic>>> _getAllSlotsAnalytics() async {
    if (_startDate == null || _endDate == null) return [];

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
    });

    try {
      // Get all slots
      final slotsSnapshot = await _firestore.collection('Slots').get();
      setState(() => _exportProgress = 0.2);

      // Get all bookings for date range
      final dates = _generateDateRange(_startDate!, _endDate!);
      final allBookings = <String, List<Map<String, dynamic>>>{};

      // Process dates in batches
      for (int i = 0; i < dates.length; i += 5) {
        final dateBatch = dates.skip(i).take(5).toList();

        final futures = dateBatch.map((dateStr) async {
          final snapshot = await _firestore
              .collection('Bookings')
              .doc(dateStr)
              .collection('BookedToday')
              .get();

          return {
            'date': dateStr,
            'bookings': snapshot.docs,
          };
        });

        final results = await Future.wait(futures);

        for (final result in results) {
          final dateStr = result['date'] as String;
          final bookings = result['bookings'] as List<QueryDocumentSnapshot>;

          for (final booking in bookings) {
            final slotId = booking.id;
            final data = booking.data() as Map<String, dynamic>;

            allBookings.putIfAbsent(slotId, () => []);
            allBookings[slotId]!.add({
              'date': dateStr,
              'bookedBy': data['bookedBy'],
              'userName': data['userName'],
              'vehicleType': data['vehicleType'],
            });
          }
        }

        setState(() => _exportProgress = 0.2 + (0.6 * (i + 5) / dates.length));
      }

      // Build slot analytics
      final slotAnalytics = <Map<String, dynamic>>[];
      final totalDays = _endDate!.difference(_startDate!).inDays + 1;

      for (final slotDoc in slotsSnapshot.docs) {
        final slotId = slotDoc.id;
        final slotData = slotDoc.data();
        final bookings = allBookings[slotId] ?? [];

        // Count bookings per user
        final userBookingCount = <String, int>{};
        for (final booking in bookings) {
          final bookedBy = booking['bookedBy'] as String;
          userBookingCount[bookedBy] = (userBookingCount[bookedBy] ?? 0) + 1;
        }

        final utilizationPercentage = (bookings.length / totalDays * 100).toDouble();

        slotAnalytics.add({
          'slotId': slotId,
          'slotData': slotData,
          'allotedTo': slotData['alloted_to'] ?? [],
          'totalBookings': bookings.length,
          'utilizationPercentage': utilizationPercentage,
          'bookingHistory': bookings,
          'userBookingCount': userBookingCount,
        });
      }

      setState(() => _exportProgress = 0.9);
      return slotAnalytics;

    } catch (e) {
      print('Error getting all slots analytics: $e');
      return [];
    }
  }


  Future<Map<String, dynamic>> _getSlotAnalyticsForRange(
      String slotId,
      Map<String, dynamic> slotData
      ) async {
    final dates = _generateDateRange(_startDate!, _endDate!);
    final bookings = <Map<String, dynamic>>[];
    final userBookingCount = <String, int>{};

    // Process dates in batches
    for (int i = 0; i < dates.length; i += 10) {
      final batch = dates.skip(i).take(10).toList();

      final futures = batch.map((dateStr) =>
          _firestore
              .collection('Bookings')
              .doc(dateStr)
              .collection('BookedToday')
              .doc(slotId)
              .get()
      );

      final results = await Future.wait(futures);

      for (int j = 0; j < results.length; j++) {
        final bookingDoc = results[j];
        if (bookingDoc.exists) {
          final booking = bookingDoc.data()!;
          final bookedBy = booking['bookedBy'] as String;

          bookings.add({
            'date': batch[j],
            'bookedBy': bookedBy,
            'userName': booking['userName'],
            'vehicleType': booking['vehicleType'],
          });

          userBookingCount[bookedBy] = (userBookingCount[bookedBy] ?? 0) + 1;
        }
      }
    }

    final totalDays = _endDate!.difference(_startDate!).inDays + 1;
    final utilizationPercentage = (bookings.length / totalDays * 100).toDouble();

    return {
      'slotId': slotId,
      'slotData': slotData,
      'allotedTo': slotData['alloted_to'] ?? [],
      'totalBookings': bookings.length,
      'utilizationPercentage': utilizationPercentage,
      'bookingHistory': bookings,
      'userBookingCount': userBookingCount,
    };
  }




  List<String> _generateDateRange(DateTime start, DateTime end) {
    final dates = <String>[];
    for (var date = start; date.isBefore(end.add(const Duration(days: 1))); date = date.add(const Duration(days: 1))) {
      dates.add(DateFormat('yyyy-MM-dd').format(date));
    }
    return dates;
  }


  Future<void> _saveAndShareExcel(Excel excel, String fileName) async {
    try {
      setState(() => _exportProgress = 0.1);

      final List<int>? bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Failed to encode Excel file');
      }

      setState(() => _exportProgress = 0.5);

      // Use the platform-specific helper function
      if (kIsWeb) {
        downloadExcelOnWeb(context, bytes, fileName);
      } else {
        await _saveExcelOnMobile(bytes, fileName);
      }

      setState(() => _exportProgress = 1.0);

    } catch (e) {
      setState(() => _exportProgress = 0.0);
      _showErrorSnackBar('Error saving Excel file: ${e.toString()}');
    }
  }




  // Mobile-specific save method (your existing logic)
  Future<void> _saveExcelOnMobile(List<int> bytes, String fileName) async {
    try {
      // Check and request permissions
      if (Platform.isAndroid) {
        final hasPermission = await _checkAndRequestPermissions();
        if (!hasPermission) {
          _showErrorSnackBar('Storage permission required to save files');
          return;
        }
      }

      setState(() => _exportProgress = 0.5);

      // Let user select directory
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        setState(() => _exportProgress = 0.0);
        return;
      }

      setState(() => _exportProgress = 0.7);

      // Create file in selected directory
      final file = File('$selectedDirectory/$fileName');

      // Check if file already exists
      if (await file.exists()) {
        final shouldOverwrite = await _showOverwriteDialog(fileName);
        if (!shouldOverwrite) {
          setState(() => _exportProgress = 0.0);
          return;
        }
      }

      setState(() => _exportProgress = 0.9);

      // Write file
      await file.writeAsBytes(bytes);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Excel file saved successfully!'),
              Text('Location: ${file.path}',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Open Folder',
            textColor: Colors.white,
            onPressed: () => _openFileLocation(file.path),
          ),
        ),
      );

    } catch (e) {
      throw Exception('Failed to save file on mobile: $e');
    }
  }







  Future<bool> _checkAndRequestPermissions() async {
    if (kIsWeb) {
      // No permissions needed for web downloads
      return true;
    }

    if (Platform.isAndroid) {
      // Check Android version
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      if (androidInfo.version.sdkInt >= 30) {
        // Android 11+ (API 30+) - Request MANAGE_EXTERNAL_STORAGE
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          final result = await Permission.manageExternalStorage.request();
          return result.isGranted;
        }
        return true;
      } else {
        // Android 10 and below - Request normal storage permission
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final result = await Permission.storage.request();
          return result.isGranted;
        }
        return true;
      }
    }
    return true; // iOS doesn't need explicit permission for user-selected directories
  }




  Future<bool> _showOverwriteDialog(String fileName) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('File Already Exists'),
          content: Text('The file "$fileName" already exists in the selected directory. Do you want to overwrite it?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Overwrite'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Future<void> _saveExcelWithFallback(Excel excel, String fileName) async {
    try {
      setState(() => _exportProgress = 0.1);

      final List<int>? bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Failed to encode Excel file');
      }

      setState(() => _exportProgress = 0.3);

      if (kIsWeb) {
        // Web: Use helper function for direct download
        downloadExcelOnWeb(context, bytes, fileName);
        setState(() => _exportProgress = 1.0);
      } else {
        // Mobile: Try Downloads first, then fallback to picker
        if (Platform.isAndroid) {
          try {
            final downloadsDir = Directory('/storage/emulated/0/Download');
            if (await downloadsDir.exists()) {
              final file = File('${downloadsDir.path}/$fileName');
              await file.writeAsBytes(bytes);

              setState(() => _exportProgress = 1.0);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Excel file saved to Downloads folder!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
              return;
            }
          } catch (e) {
            print('Failed to save to Downloads folder: $e');
            // Falls through to directory picker
          }
        }

        // Fallback to directory picker for mobile
        await _saveExcelOnMobile(bytes, fileName);
      }

    } catch (e) {
      setState(() => _exportProgress = 0.0);
      _showErrorSnackBar('Error saving Excel file: ${e.toString()}');
    }
  }





  Future<void> _openFileLocation(String filePath) async {
    try {
      if (kIsWeb) {
        // For web, just show a message since we can't open file location
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File has been downloaded to your default download folder'),
            backgroundColor: Colors.blue,
          ),
        );
      } else {
        // Mobile: copy path to clipboard
        await Clipboard.setData(ClipboardData(text: filePath));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File path copied to clipboard'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      print('Error opening file location: $e');
    }
  }




// Updated permission request method
  Future<bool> _requestStoragePermission() async {
    if (kIsWeb) {
      // No permissions needed for web
      return true;
    }

    if (Platform.isAndroid) {
      // For Android 13+ (API 33+), we don't need WRITE_EXTERNAL_STORAGE
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        return true; // No permission needed for app-specific directory
      }

      // For older Android versions
      final status = await Permission.storage.request();
      return status.isGranted;
    } else {
      // iOS doesn't need explicit permission for app documents
      return true;
    }
  }



// Updated export methods with better error handling

  Future<void> _exportUsersToExcel() async {
    try {
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        _showErrorSnackBar('Storage permission is required to save Excel files');
        return;
      }

      setState(() => _exportProgress = 0.05);

      final userData = await _getAllUsersAnalytics();

      if (userData.isEmpty) {
        _showErrorSnackBar('No user data found for selected date range');
        return;
      }

      setState(() => _exportProgress = 0.95);

      // Create Excel file efficiently
      final excel = Excel.createExcel();
      final sheet = excel['Users Analytics'];

      // Set headers
      final headers = [
        'Email', 'Allocated Slot', 'Alloted Date', 'Total Bookings',
        'Utilization %', 'Slot Priority', 'Vehicle Type', 'Date Range'
      ];

      // Add headers with styling
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = headers[i];
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: '#4CAF50',
          fontColorHex: '#FFFFFF',
        );
      }

      // Add data rows efficiently
      for (int i = 0; i < userData.length; i++) {
        final user = userData[i];
        final slotData = user['slotData'] as Map<String, dynamic>? ?? {};
        final row = i + 1;

        // Use array for faster access
        final rowData = [
          user['email'],
          user['allocatedSlot'] ?? 'N/A',
          user['allotedDate'] ?? 'N/A',
          user['totalBookings'],
          '${user['utilizationPercentage'].toStringAsFixed(2)}%',
          slotData['slotPriority'] ?? 'N/A',
          slotData['vehicleType'] ?? 'N/A',
          '${DateFormat('dd-MM-yyyy').format(_startDate!)} to ${DateFormat('dd-MM-yyyy').format(_endDate!)}'
        ];

        for (int j = 0; j < rowData.length; j++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: row)).value = rowData[j];
        }
      }

      final fileName = 'Users_Analytics_${DateFormat('ddMMyyyy').format(_startDate!)}_to_${DateFormat('ddMMyyyy').format(_endDate!)}.xlsx';
      await _saveAndShareExcel(excel, fileName);

    } catch (e) {
      _showErrorSnackBar('Error exporting users data: ${e.toString()}');
    } finally {
      setState(() {
        _isExporting = false;
        _exportProgress = 0.0;
      });
    }
  }





  Future<void> _exportSlotsToExcel() async {
    try {
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        _showErrorSnackBar('Storage permission is required to save Excel files');
        return;
      }

      setState(() => _exportProgress = 0.05);

      final slotData = await _getAllSlotsAnalytics();

      if (slotData.isEmpty) {
        _showErrorSnackBar('No slot data found for selected date range');
        return;
      }

      setState(() => _exportProgress = 0.95);

      final excel = Excel.createExcel();
      final sheet = excel['Slots Analytics'];

      // Headers
      final headers = [
        'Slot ID', 'Vehicle Type', 'Priority', 'Allocated Users Count',
        'Total Bookings', 'Utilization %', 'Most Active User', 'Date Range'
      ];

      // Add headers with styling
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = headers[i];
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: '#2196F3',
          fontColorHex: '#FFFFFF',
        );
      }

      // Add data rows efficiently
      for (int i = 0; i < slotData.length; i++) {
        final slot = slotData[i];
        final slotInfo = slot['slotData'] as Map<String, dynamic>;
        final userBookingCount = slot['userBookingCount'] as Map<String, int>;

        // Find most active user
        String mostActiveUser = 'N/A';
        if (userBookingCount.isNotEmpty) {
          mostActiveUser = userBookingCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
        }

        final row = i + 1;
        final rowData = [
          slot['slotId'],
          slotInfo['vehicleType'] ?? 'N/A',
          slotInfo['slotPriority'] ?? 'N/A',
          (slot['allotedTo'] as List).length,
          slot['totalBookings'],
          '${slot['utilizationPercentage'].toStringAsFixed(2)}%',
          mostActiveUser,
          '${DateFormat('dd-MM-yyyy').format(_startDate!)} to ${DateFormat('dd-MM-yyyy').format(_endDate!)}'
        ];

        for (int j = 0; j < rowData.length; j++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: row)).value = rowData[j];
        }
      }

      final fileName = 'Slots_Analytics_${DateFormat('ddMMyyyy').format(_startDate!)}_to_${DateFormat('ddMMyyyy').format(_endDate!)}.xlsx';
      await _saveAndShareExcel(excel, fileName);

    } catch (e) {
      _showErrorSnackBar('Error exporting slots data: ${e.toString()}');
    } finally {
      setState(() {
        _isExporting = false;
        _exportProgress = 0.0;
      });
    }
  }

  Future<void> _performSearch() async {
    if (_searchController.text.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _analyticsData = null;
      _currentQuery = _searchController.text.trim();
    });

    try {
      if (_searchType == 'user') {
        final data = await _getUserAnalytics(_currentQuery!);
        setState(() {
          _analyticsData = data;
          _isLoading = false;
        });
      } else {
        final data = await _getSlotAnalytics(_currentQuery!);
        setState(() {
          _analyticsData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Error fetching analytics: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> _getUserAnalytics(String email) async {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    // Get user's slot allocation from Slots collection
    final slotsQuery = await _firestore.collection('Slots').get();
    String? allocatedSlot;
    DateTime? allotedDate;

    for (var doc in slotsQuery.docs) {
      final data = doc.data();
      final allotedTo = data['alloted_to'] as List<dynamic>?;

      if (allotedTo != null) {
        for (var user in allotedTo) {
          if (user['email'] == email) {
            allocatedSlot = doc.id;
            allotedDate = DateTime.tryParse(user['alloted_date'] ?? '');
            break;
          }
        }
      }
      if (allocatedSlot != null) break;
    }

    // Get booking history for current month
    List<Map<String, dynamic>> bookings = [];
    int totalBookings = 0;

    for (int i = 0; i < 31; i++) {
      final date = currentMonth.add(Duration(days: i));
      if (date.isAfter(nextMonth)) break;

      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final bookingQuery = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('BookedToday')
          .where('bookedBy', isEqualTo: email)
          .get();

      if (bookingQuery.docs.isNotEmpty) {
        final booking = bookingQuery.docs.first;
        bookings.add({
          'date': dateStr,
          'slotId': booking.id,
          'bookingData': booking.data(),
        });
        totalBookings++;
      }
    }

    // Calculate utilization percentage
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final workingDays = daysInMonth; // Assuming all days are working days
    final utilizationPercentage = (totalBookings / workingDays * 100).toDouble();

    return {
      'type': 'user',
      'email': email,
      'allocatedSlot': allocatedSlot,
      'allotedDate': allotedDate,
      'totalBookings': totalBookings,
      'utilizationPercentage': utilizationPercentage,
      'bookingHistory': bookings,
      'currentMonth': DateFormat('MMMM yyyy').format(currentMonth),
    };
  }

  Future<Map<String, dynamic>> _getSlotAnalytics(String slotId) async {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    // Get slot details from Slots collection
    final slotDoc = await _firestore.collection('Slots').doc(slotId).get();
    if (!slotDoc.exists) {
      throw Exception('Slot not found');
    }

    final slotData = slotDoc.data()!;
    final allotedTo = slotData['alloted_to'] as List<dynamic>? ?? [];

    // Get booking history for current month
    List<Map<String, dynamic>> bookings = [];
    Map<String, int> userBookingCount = {};
    int totalBookings = 0;

    for (int i = 0; i < 31; i++) {
      final date = currentMonth.add(Duration(days: i));
      if (date.isAfter(nextMonth)) break;

      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final bookingDoc = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('BookedToday')
          .doc(slotId)
          .get();

      if (bookingDoc.exists) {
        final booking = bookingDoc.data()!;
        final bookedBy = booking['bookedBy'] as String;

        bookings.add({
          'date': dateStr,
          'bookedBy': bookedBy,
          'userName': booking['userName'],
          'vehicleType': booking['vehicleType'],
        });

        userBookingCount[bookedBy] = (userBookingCount[bookedBy] ?? 0) + 1;
        totalBookings++;
      }
    }

    // Calculate utilization percentage
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final utilizationPercentage = (totalBookings / daysInMonth * 100).toDouble();

    return {
      'type': 'slot',
      'slotId': slotId,
      'slotData': slotData,
      'allotedTo': allotedTo,
      'totalBookings': totalBookings,
      'utilizationPercentage': utilizationPercentage,
      'bookingHistory': bookings,
      'userBookingCount': userBookingCount,
      'currentMonth': DateFormat('MMMM yyyy').format(currentMonth),
    };
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Center( // Center the content
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200), // Limit max width
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _buildExportSection(),
                _buildSearchSection(),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _analyticsData == null
                    ? _buildEmptyState()
                    : _buildAnalyticsContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }





  Widget _buildExportSection() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export Analytics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 16),

          // Responsive date range selection
          LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth > 600 ? 400 : constraints.maxWidth,
                ),
                child: GestureDetector(
                  onTap: _selectDateRange,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, color: Colors.indigo),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _startDate != null && _endDate != null
                                ? '${DateFormat('dd MMM yyyy').format(_startDate!)} - ${DateFormat('dd MMM yyyy').format(_endDate!)}'
                                : 'Select date range',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // Responsive export buttons
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 600) {
                // Web layout - buttons in a row with max width
                return Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 200,
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportUsersToExcel,
                        icon: const Icon(Icons.people),
                        label: const Text('Export Users'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportSlotsToExcel,
                        icon: const Icon(Icons.local_parking),
                        label: const Text('Export Slots'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                // Mobile layout - original stacked buttons
                return Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportUsersToExcel,
                        icon: const Icon(Icons.people),
                        label: const Text('Export Users'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportSlotsToExcel,
                        icon: const Icon(Icons.local_parking),
                        label: const Text('Export Slots'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                );
              }
            },
          ),

          // Progress indicator with responsive width
          if (_isExporting) ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                return Container(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth > 600 ? 400 : constraints.maxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: _exportProgress,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Exporting... ${(_exportProgress * 100).toInt()}%',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }



  Widget _buildSearchSection() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Responsive search row
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 600) {
                // Web layout - search bar with fixed width
                return Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      width: 400,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: _searchType == 'user'
                              ? 'Enter user email...'
                              : 'Enter slot ID...',
                          prefixIcon: Icon(
                            _searchType == 'user' ? Icons.email : Icons.local_parking,
                            color: Colors.indigo,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _performSearch,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Search'),
                    ),
                  ],
                );
              } else {
                // Mobile layout - original full width
                return Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: _searchType == 'user'
                                ? 'Enter user email...'
                                : 'Enter slot ID...',
                            prefixIcon: Icon(
                              _searchType == 'user' ? Icons.email : Icons.local_parking,
                              color: Colors.indigo,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _performSearch(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _performSearch,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Search'),
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 16),

          // Responsive type selectors
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 600) {
                // Web layout - type selectors with fixed width
                return Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 200,
                      child: _buildTypeSelector('user', 'User Analytics', Icons.person),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      child: _buildTypeSelector('slot', 'Slot Analytics', Icons.local_parking),
                    ),
                  ],
                );
              } else {
                // Mobile layout - original expanded
                return Row(
                  children: [
                    Expanded(
                      child: _buildTypeSelector('user', 'User Analytics', Icons.person),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTypeSelector('slot', 'Slot Analytics', Icons.local_parking),
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }


  Widget _buildTypeSelector(String type, String label, IconData icon) {
    final isSelected = _searchType == type;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _searchType = type;
            _analyticsData = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.transparent,
            border: Border.all(
              color: isSelected ? Colors.indigo : Colors.grey[300]!,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isSelected ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[600],
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Enter ${_searchType == 'user' ? 'user email' : 'slot ID'} to view analytics',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildAnalyticsContent() {
    if (_analyticsData!['type'] == 'user') {
      return _buildUserAnalytics();
    } else {
      return _buildSlotAnalytics();
    }
  }

  Widget _buildUserAnalytics() {
    final data = _analyticsData!;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('User Utilization Analysis'),
          const SizedBox(height: 16),

          // Responsive layout for cards
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                // Web layout - two columns for some cards
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: _buildUserInfoCard(data),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: _buildUtilizationCard(data),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildBookingHistoryCard(data),
                  ],
                );
              } else {
                // Mobile layout - single column
                return Column(
                  children: [
                    _buildUserInfoCard(data),
                    const SizedBox(height: 16),
                    _buildUtilizationCard(data),
                    const SizedBox(height: 16),
                    _buildBookingHistoryCard(data),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }



  Widget _buildSlotAnalytics() {
    final data = _analyticsData!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Slot Utilization Analysis'),
          const SizedBox(height: 16),

          // Responsive layout for slot cards
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                // Web layout - two columns for some cards
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: _buildSlotInfoCard(data),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: _buildUtilizationCard(data),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSlotBookingHistoryCard(data),
                    const SizedBox(height: 16),
                    _buildUserBookingBreakdown(data),
                  ],
                );
              } else {
                // Mobile layout - single column
                return Column(
                  children: [
                    _buildSlotInfoCard(data),
                    const SizedBox(height: 16),
                    _buildUtilizationCard(data),
                    const SizedBox(height: 16),
                    _buildSlotBookingHistoryCard(data),
                    const SizedBox(height: 16),
                    _buildUserBookingBreakdown(data),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    );
  }


  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.indigo,
      ),
    );
  }

  Widget _buildUserInfoCard(Map<String, dynamic> data) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  'User Information',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Email', data['email']),
            _buildInfoRow('Allocated Slot', data['allocatedSlot'] ?? 'Not allocated'),
            if (data['allotedDate'] != null)
              _buildInfoRow('Alloted Date',
                  DateFormat('dd MMM yyyy').format(data['allotedDate'])),
          ],
        ),
      ),
    );
  }



  Widget _buildSlotInfoCard(Map<String, dynamic> data) {
    final slotData = data['slotData'] as Map<String, dynamic>;
    final allotedTo = data['allotedTo'] as List<dynamic>;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_parking, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  'Slot Information',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Slot ID', data['slotId']),
            _buildInfoRow('Vehicle Type', slotData['vehicleType'] ?? 'N/A'),
            _buildInfoRow('Priority', slotData['slotPriority'] ?? 'N/A'),
            if (slotData['VehicleCompatibility'] != null)
              _buildInfoRow('Compatibility', slotData['VehicleCompatibility']),
            _buildInfoRow('Allocated Users', allotedTo.length.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildUtilizationCard(Map<String, dynamic> data) {
    final percentage = data['utilizationPercentage'] as double;
    final totalBookings = data['totalBookings'] as int;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Utilization - ${data['currentMonth']}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Responsive stats layout
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 300) {
                  // Wide layout - side by side
                  return Row(
                    children: [
                      Expanded(
                        child: _buildStatColumn(
                          '${percentage.toStringAsFixed(1)}%',
                          'Utilization Rate',
                          Colors.indigo,
                        ),
                      ),
                      Expanded(
                        child: _buildStatColumn(
                          totalBookings.toString(),
                          'Total Bookings',
                          Colors.green,
                        ),
                      ),
                    ],
                  );
                } else {
                  // Narrow layout - stacked
                  return Column(
                    children: [
                      _buildStatColumn(
                        '${percentage.toStringAsFixed(1)}%',
                        'Utilization Rate',
                        Colors.indigo,
                      ),
                      const SizedBox(height: 16),
                      _buildStatColumn(
                        totalBookings.toString(),
                        'Total Bookings',
                        Colors.green,
                      ),
                    ],
                  );
                }
              },
            ),

            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                percentage > 75 ? Colors.green :
                percentage > 50 ? Colors.orange : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }




  Widget _buildBookingHistoryCard(Map<String, dynamic> data) {
    final bookings = data['bookingHistory'] as List<dynamic>;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  'Booking History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (bookings.isEmpty)
              const Text(
                'No bookings found for this month',
                style: TextStyle(color: Colors.grey),
              )
            else
              Column(
                children: bookings.map<Widget>((booking) {
                  final date = DateTime.parse(booking['date']);

                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[200]!),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.indigo.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              date.day.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('dd MMM yyyy').format(date),
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                'Slot: ${booking['slotId']}',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );


                }).toList(),
              )






          ],
        ),
      ),
    );
  }

  Widget _buildSlotBookingHistoryCard(Map<String, dynamic> data) {
    final bookings = data['bookingHistory'] as List<dynamic>;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  'Booking History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (bookings.isEmpty)
              const Text(
                'No bookings found for this month',
                style: TextStyle(color: Colors.grey),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: bookings.length,
                itemBuilder: (context, index) {
                  final booking = bookings[index];
                  final date = DateTime.parse(booking['date']);
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[200]!),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              date.day.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('dd MMM yyyy').format(date),
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                'Booked by: ${booking['userName']}',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              Text(
                                'Vehicle: ${booking['vehicleType']}',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBookingBreakdown(Map<String, dynamic> data) {
    final userBookingCount = data['userBookingCount'] as Map<String, int>;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  'User Booking Breakdown',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (userBookingCount.isEmpty)
              const Text(
                'No user bookings found',
                style: TextStyle(color: Colors.grey),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: userBookingCount.length,
                itemBuilder: (context, index) {
                  final entry = userBookingCount.entries.toList()[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[200]!),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${entry.value} bookings',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}