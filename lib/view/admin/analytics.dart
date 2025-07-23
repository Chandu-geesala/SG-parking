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
import 'dart:async';

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


  static Map<String, Map<String, dynamic>> _slotsCache = {};
  static DateTime? _slotsCacheTime;
  static const Duration _cacheExpiry = Duration(minutes: 10);

  final Map<String, Map<String, dynamic>> _analyticsCache = {};
  Timer? _searchDebounce;

  // NEW: Cache management methods
  bool get _isCacheValid {
    return _slotsCacheTime != null &&
        DateTime.now().difference(_slotsCacheTime!).inMinutes < _cacheExpiry.inMinutes;
  }

  void _clearCaches() {
    _slotsCache.clear();
    _slotsCacheTime = null;
    _analyticsCache.clear();
  }

  // NEW: Optimized slots cache loader
  Future<void> _loadSlotsCache() async {
    if (_isCacheValid && _slotsCache.isNotEmpty) return;

    try {
      final slotsQuery = await _firestore.collection('Slots').get();
      _slotsCache.clear();

      for (var doc in slotsQuery.docs) {
        _slotsCache[doc.id] = {
          'data': doc.data(),
          'id': doc.id,
        };
      }
      _slotsCacheTime = DateTime.now();
    } catch (e) {
      print('Error loading slots cache: $e');
      // Continue with empty cache if error occurs
    }
  }

  // NEW: Find user's slot from cache
  Map<String, dynamic>? _findUserSlotFromCache(String email) {
    for (var slotEntry in _slotsCache.entries) {
      final slotData = slotEntry.value['data'] as Map<String, dynamic>;
      final allotedTo = slotData['alloted_to'] as List<dynamic>? ?? [];

      for (var user in allotedTo) {
        if (user['email'] == email) {
          return {
            'slotId': slotEntry.key,
            'slotData': slotData,
            'allotedDate': user['alloted_date'],
          };
        }
      }
    }
    return null;
  }

  // NEW: Generate date range efficiently
  List<String> _generateOptimizedDateRange(DateTime start, DateTime end) {
    final dates = <String>[];
    final totalDays = end.difference(start).inDays + 1;

    // Limit to reasonable range to prevent excessive queries
    final maxDays = totalDays > 90 ? 90 : totalDays;

    for (int i = 0; i < maxDays; i++) {
      final date = start.add(Duration(days: i));
      if (date.isAfter(end)) break;
      dates.add(DateFormat('yyyy-MM-dd').format(date));
    }

    return dates;
  }





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



  // CLEAN VERSION: Replace your _getAllUsersAnalytics method with this
  Future<List<Map<String, dynamic>>> _getAllUsersAnalytics() async {
    if (_startDate == null || _endDate == null) return [];

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
    });

    try {
      // Load slots from cache (much faster than direct query)
      await _loadSlotsCache();
      setState(() => _exportProgress = 0.2);

      // Create user-slot mapping from cache
      final userSlotMap = <String, Map<String, dynamic>>{};
      for (var slotEntry in _slotsCache.entries) {
        final slotData = slotEntry.value['data'] as Map<String, dynamic>;
        final allotedTo = slotData['alloted_to'] as List<dynamic>? ?? [];

        for (var user in allotedTo) {
          final email = user['email'] as String;
          userSlotMap[email] = {
            'slotId': slotEntry.key,
            'allotedDate': user['alloted_date'],
            'slotData': slotData,
          };
        }
      }

      setState(() => _exportProgress = 0.4);

      // Get all bookings for date range in batch
      final dates = _generateOptimizedDateRange(_startDate!, _endDate!);
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

// OPTIMIZED VERSION: Replace your _getAllSlotsAnalytics method with this
  Future<List<Map<String, dynamic>>> _getAllSlotsAnalytics() async {
    if (_startDate == null || _endDate == null) return [];

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
    });

    try {
      // Use cache instead of direct query (much faster)
      await _loadSlotsCache();
      setState(() => _exportProgress = 0.2);

      // Get all bookings for date range
      final dates = _generateOptimizedDateRange(_startDate!, _endDate!);
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

      // Build slot analytics using cached data
      final slotAnalytics = <Map<String, dynamic>>[];
      final totalDays = _endDate!.difference(_startDate!).inDays + 1;

      // Iterate through cached slots instead of fresh query
      for (final slotEntry in _slotsCache.entries) {
        final slotId = slotEntry.key;
        final slotData = slotEntry.value['data'] as Map<String, dynamic>;
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

// BONUS: Add this method for better performance monitoring
  Future<void> _exportUsersToExcelOptimized() async {
    try {
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        _showErrorSnackBar('Storage permission is required to save Excel files');
        return;
      }

      setState(() => _exportProgress = 0.05);

      // Check cache and estimate export size
      await _loadSlotsCache();
      final estimatedUsers = _slotsCache.values
          .expand((slot) => (slot['data']['alloted_to'] as List? ?? []))
          .length;

      // Warn user for large exports
      if (estimatedUsers > 500) {
        final shouldContinue = await _showLargeExportWarning(estimatedUsers);
        if (!shouldContinue) {
          setState(() {
            _isExporting = false;
            _exportProgress = 0.0;
          });
          return;
        }
      }

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

// Helper method for large export warning
  Future<bool> _showLargeExportWarning(int count) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Large Export Warning'),
        content: Text('This will export $count users. This may take several minutes and use significant memory. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')
          ),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue')
          ),
        ],
      ),
    ) ?? false;
  }



  Future<Map<String, dynamic>> _getUserAnalyticsForRange(
      String email,
      Map<String, dynamic> slotInfo
      ) async {
    final dates = _generateOptimizedDateRange(_startDate!, _endDate!);
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







  Future<Map<String, dynamic>> _getSlotAnalyticsForRange(
      String slotId,
      Map<String, dynamic> slotData
      ) async {
    final dates = _generateOptimizedDateRange(_startDate!, _endDate!);
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

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isNotEmpty) {
        _performSearch();
      }
    });
  }



  Future<Map<String, dynamic>> _getUserAnalytics(String email) async {
    // Use date range from UI instead of hardcoded current month
    final startDate = _startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
    final endDate = _endDate ?? DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

    // Create cache key
    final cacheKey = '${email}_${DateFormat('yyyy-MM-dd').format(startDate)}_${DateFormat('yyyy-MM-dd').format(endDate)}';

    // Check cache first
    if (_analyticsCache.containsKey(cacheKey)) {
      return _analyticsCache[cacheKey]!;
    }

    try {
      // Load slots cache if needed
      await _loadSlotsCache();

      // Find user's slot from cache (MUCH faster than querying all slots)
      final userSlotInfo = _findUserSlotFromCache(email);

      String? allocatedSlot = userSlotInfo?['slotId'];
      DateTime? allotedDate;
      if (userSlotInfo?['allotedDate'] != null) {
        allotedDate = DateTime.tryParse(userSlotInfo!['allotedDate']);
      }

      // Generate date range efficiently
      final dates = _generateOptimizedDateRange(startDate, endDate);

      // OPTIMIZED: Batch all booking queries concurrently
      final bookingFutures = dates.map((dateStr) =>
          _firestore
              .collection('Bookings')
              .doc(dateStr)
              .collection('BookedToday')
              .where('bookedBy', isEqualTo: email)
              .limit(1) // Only need to know if booking exists
              .get()
              .then((snapshot) => {
            'date': dateStr,
            'hasBooking': snapshot.docs.isNotEmpty,
            'bookingData': snapshot.docs.isNotEmpty ? {
              'slotId': snapshot.docs.first.id,
              'data': snapshot.docs.first.data(),
            } : null,
          })
      );

      // Execute all queries concurrently (MAJOR performance improvement)
      final bookingResults = await Future.wait(bookingFutures);

      // Process results
      final bookings = <Map<String, dynamic>>[];
      int totalBookings = 0;

      for (final result in bookingResults) {
        if (result['hasBooking'] == true) {
          final bookingData = result['bookingData'] as Map<String, dynamic>;
          bookings.add({
            'date': result['date'],
            'slotId': bookingData['slotId'],
            'bookingData': bookingData['data'],
          });
          totalBookings++;
        }
      }

      // Calculate utilization percentage
      final totalDays = dates.length;
      final utilizationPercentage = totalDays > 0 ? (totalBookings / totalDays * 100).toDouble() : 0.0;

      final result = {
        'type': 'user',
        'email': email,
        'allocatedSlot': allocatedSlot,
        'allotedDate': allotedDate,
        'totalBookings': totalBookings,
        'utilizationPercentage': utilizationPercentage,
        'bookingHistory': bookings,
        'dateRange': '${DateFormat('MMMM yyyy').format(startDate)} - ${DateFormat('MMMM yyyy').format(endDate)}',
        'totalDays': totalDays,
      };

      // Cache the result
      _analyticsCache[cacheKey] = result;

      return result;

    } catch (e) {
      print('Error in _getUserAnalytics: $e');
      throw Exception('Failed to get user analytics: $e');
    }
  }




  Future<Map<String, dynamic>> _getSlotAnalytics(String slotId) async {
    // Use date range from UI instead of hardcoded current month
    final startDate = _startDate ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
    final endDate = _endDate ?? DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

    // Create cache key
    final cacheKey = '${slotId}_${DateFormat('yyyy-MM-dd').format(startDate)}_${DateFormat('yyyy-MM-dd').format(endDate)}';

    // Check cache first
    if (_analyticsCache.containsKey(cacheKey)) {
      return _analyticsCache[cacheKey]!;
    }

    try {
      // Get slot details from cache or fetch if not cached
      Map<String, dynamic>? slotData;

      if (_slotsCache.containsKey(slotId)) {
        slotData = _slotsCache[slotId]!['data'] as Map<String, dynamic>;
      } else {
        // Fallback to direct query if not in cache
        final slotDoc = await _firestore.collection('Slots').doc(slotId).get();
        if (!slotDoc.exists) {
          throw Exception('Slot not found');
        }
        slotData = slotDoc.data()!;
      }

      final allotedTo = slotData['alloted_to'] as List<dynamic>? ?? [];

      // Generate date range efficiently
      final dates = _generateOptimizedDateRange(startDate, endDate);

      // OPTIMIZED: Batch all booking queries concurrently
      final bookingFutures = dates.map((dateStr) =>
          _firestore
              .collection('Bookings')
              .doc(dateStr)
              .collection('BookedToday')
              .doc(slotId)
              .get()
              .then((snapshot) => {
            'date': dateStr,
            'exists': snapshot.exists,
            'data': snapshot.exists ? snapshot.data() : null,
          })
      );

      // Execute all queries concurrently (MAJOR performance improvement)
      final bookingResults = await Future.wait(bookingFutures);

      // Process results
      final bookings = <Map<String, dynamic>>[];
      final userBookingCount = <String, int>{};
      int totalBookings = 0;

      for (final result in bookingResults) {
        if (result['exists'] == true) {
          final booking = result['data'] as Map<String, dynamic>;
          final bookedBy = booking['bookedBy'] as String;

          bookings.add({
            'date': result['date'],
            'bookedBy': bookedBy,
            'userName': booking['userName'] ?? 'Unknown',
            'vehicleType': booking['vehicleType'] ?? 'Unknown',
          });

          userBookingCount[bookedBy] = (userBookingCount[bookedBy] ?? 0) + 1;
          totalBookings++;
        }
      }

      // Calculate utilization percentage
      final totalDays = dates.length;
      final utilizationPercentage = totalDays > 0 ? (totalBookings / totalDays * 100).toDouble() : 0.0;

      final result = {
        'type': 'slot',
        'slotId': slotId,
        'slotData': slotData,
        'allotedTo': allotedTo,
        'totalBookings': totalBookings,
        'utilizationPercentage': utilizationPercentage,
        'bookingHistory': bookings,
        'userBookingCount': userBookingCount,
        'dateRange': '${DateFormat('MMMM yyyy').format(startDate)} - ${DateFormat('MMMM yyyy').format(endDate)}',
        'totalDays': totalDays,
      };

      // Cache the result
      _analyticsCache[cacheKey] = result;

      return result;

    } catch (e) {
      print('Error in _getSlotAnalytics: $e');
      throw Exception('Failed to get slot analytics: $e');
    }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Use theme-aware background colors
      backgroundColor: isDark
          ? const Color(0xFF0F172A) // Dark navy from your theme
          : Colors.grey[100], // Keep original light background

      appBar: AppBar(
        title: const Text('Analytics Dashboard'),

        // Theme-aware AppBar styling
        backgroundColor: isDark
            ? const Color(0xFF1E293B) // Dark slate from your theme
            : Colors.indigo, // Keep original indigo

        foregroundColor: isDark
            ? const Color(0xFFF8FAFC) // Clean white from your theme
            : Colors.white, // Keep original white

        elevation: 0,

        // Enhanced AppBar styling for dark mode
        surfaceTintColor: isDark ? Colors.transparent : null,

        // Add subtle shadow/border for dark mode
        bottom: isDark
            ? PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF334155).withOpacity(0.3),
                  const Color(0xFF334155).withOpacity(0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        )
            : null,
      ),

      body: Container(
        // Add subtle gradient background for dark mode
        decoration: isDark
            ? const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A), // Dark navy
              Color(0xFF1A1B23), // Slightly lighter at bottom
            ],
            stops: [0.0, 1.0],
          ),
        )
            : null,

        child: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                // Add top padding for dark mode visual separation
                vertical: isDark ? 8 : 0,
              ),
              child: Column(
                children: [
                  // Add subtle spacing for dark mode
                  if (isDark) const SizedBox(height: 8),

                  _buildExportSection(),
                  _buildSearchSection(),
                  _isLoading
                      ? Center(
                    child: CircularProgressIndicator(
                      // Theme-aware loading indicator
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark
                            ? const Color(0xFF60A5FA) // Vibrant blue from theme
                            : Theme.of(context).primaryColor,
                      ),
                    ),
                  )
                      : _analyticsData == null
                      ? _buildEmptyState()
                      : _buildAnalyticsContent(),

                  // Add bottom padding for dark mode
                  if (isDark) const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildExportSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Theme-aware background
        gradient: isDark
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E293B),
            const Color(0xFF334155),
          ],
        )
            : null,
        color: isDark ? null : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(
          color: const Color(0xFF60A5FA).withOpacity(0.2),
          width: 1,
        )
            : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            blurRadius: isDark ? 8 : 4,
            offset: const Offset(0, 2),
          ),
          if (isDark)
            BoxShadow(
              color: const Color(0xFF60A5FA).withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 0),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export Analytics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? const Color(0xFF60A5FA) // Theme blue
                  : Colors.indigo,
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
                      color: isDark
                          ? const Color(0xFF334155).withOpacity(0.5)
                          : null,
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF475569)
                            : Colors.grey[300]!,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.date_range,
                          color: isDark
                              ? const Color(0xFF60A5FA)
                              : Colors.indigo,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _startDate != null && _endDate != null
                                ? '${DateFormat('dd MMM yyyy').format(_startDate!)} - ${DateFormat('dd MMM yyyy').format(_endDate!)}'
                                : 'Select date range',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? const Color(0xFFE2E8F0)
                                  : Colors.black87,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : Colors.grey,
                        ),
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
                        icon: Icon(
                          Icons.people,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),

                        label: const Text('Export Users'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF34D399)
                              : Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: isDark ? 6 : 2,
                          shadowColor: isDark
                              ? const Color(0xFF34D399).withOpacity(0.3)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportSlotsToExcel,
                        icon: Icon(
                          Icons.local_parking,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),

                        label: const Text('Export Slots'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF60A5FA)
                              : Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: isDark ? 6 : 2,
                          shadowColor: isDark
                              ? const Color(0xFF60A5FA).withOpacity(0.3)
                              : null,
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
                          backgroundColor: isDark
                              ? const Color(0xFF34D399)
                              : Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: isDark ? 6 : 2,
                          shadowColor: isDark
                              ? const Color(0xFF34D399).withOpacity(0.3)
                              : null,
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
                          backgroundColor: isDark
                              ? const Color(0xFF60A5FA)
                              : Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: isDark ? 6 : 2,
                          shadowColor: isDark
                              ? const Color(0xFF60A5FA).withOpacity(0.3)
                              : null,
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
                        backgroundColor: isDark
                            ? const Color(0xFF475569)
                            : Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark
                              ? const Color(0xFF60A5FA)
                              : Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Exporting... ${(_exportProgress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : Colors.grey,
                        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Theme-aware background
        gradient: isDark
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E293B),
            const Color(0xFF334155),
          ],
        )
            : null,
        color: isDark ? null : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(
          color: const Color(0xFF60A5FA).withOpacity(0.2),
          width: 1,
        )
            : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            blurRadius: isDark ? 8 : 4,
            offset: const Offset(0, 2),
          ),
          if (isDark)
            BoxShadow(
              color: const Color(0xFF60A5FA).withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 0),
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
                        color: isDark
                            ? const Color(0xFF334155)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: isDark
                            ? Border.all(
                          color: const Color(0xFF475569),
                          width: 0.5,
                        )
                            : null,
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFE2E8F0)
                              : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: _searchType == 'user'
                              ? 'Enter user email...'
                              : 'Enter slot ID...',
                          hintStyle: TextStyle(
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : Colors.grey[600],
                          ),
                          prefixIcon: Icon(
                            _searchType == 'user' ? Icons.email : Icons.local_parking,
                            color: isDark
                                ? const Color(0xFF60A5FA)
                                : Colors.indigo,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: _onSearchChanged,
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _performSearch,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? const Color(0xFF60A5FA)
                            : Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        elevation: isDark ? 6 : 2,
                        shadowColor: isDark
                            ? const Color(0xFF60A5FA).withOpacity(0.3)
                            : null,
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
                          color: isDark
                              ? const Color(0xFF334155)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: isDark
                              ? Border.all(
                            color: const Color(0xFF475569),
                            width: 0.5,
                          )
                              : null,
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFE2E8F0)
                                : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: _searchType == 'user'
                                ? 'Enter user email...'
                                : 'Enter slot ID...',
                            hintStyle: TextStyle(
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : Colors.grey[600],
                            ),
                            prefixIcon: Icon(
                              _searchType == 'user' ? Icons.email : Icons.local_parking,
                              color: isDark
                                  ? const Color(0xFF60A5FA)
                                  : Colors.indigo,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _performSearch(),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _performSearch,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? const Color(0xFF60A5FA)
                            : Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        elevation: isDark ? 6 : 2,
                        shadowColor: isDark
                            ? const Color(0xFF60A5FA).withOpacity(0.3)
                            : null,
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
          // Responsive type selectors
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 600;

              if (isDesktop) {
                // Web layout - type selectors with fixed width
                return Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 200,
                      child: _buildTypeSelector('user', 'User Analytics', Icons.person, isDesktop: true),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      child: _buildTypeSelector('slot', 'Slot Analytics', Icons.local_parking, isDesktop: true),
                    ),
                  ],
                );
              } else {
                // Mobile layout - original expanded
                return Row(
                  children: [
                    _buildTypeSelector('user', 'User Analytics', Icons.person, isDesktop: false),
                    const SizedBox(width: 16),
                    _buildTypeSelector('slot', 'Slot Analytics', Icons.local_parking, isDesktop: false),
                  ],
                );
              }
            },
          ),


        ],
      ),
    );
  }


  // ADD this method to your class
  Future<void> refreshData() async {
    _clearCaches();
    if (_currentQuery != null) {
      await _performSearch();
    }
  }

  Widget _buildTypeSelector(String type, String label, IconData icon, {bool isDesktop = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _searchType == type;

    Widget selectorWidget = GestureDetector(
      onTap: () {
        setState(() {
          _searchType = type;
          _analyticsData = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          // Enhanced styling for dark mode
          gradient: isSelected && isDark
              ? LinearGradient(
            colors: [
              const Color(0xFF60A5FA),
              const Color(0xFF3B82F6),
            ],
          )
              : null,
          color: isSelected
              ? (isDark ? null : Colors.indigo)
              : (isDark ? const Color(0xFF334155).withOpacity(0.3) : Colors.transparent),
          border: Border.all(
            color: isSelected
                ? (isDark ? const Color(0xFF60A5FA) : Colors.indigo)
                : (isDark ? const Color(0xFF475569) : Colors.grey[300]!),
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected && isDark
              ? [
            BoxShadow(
              color: const Color(0xFF60A5FA).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Colors.white
                    : (isDark ? const Color(0xFF94A3B8) : Colors.grey[600]),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? const Color(0xFFE2E8F0) : Colors.grey[600]),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Only wrap with Expanded for mobile layout
    if (isDesktop) {
      return selectorWidget;
    } else {
      return Expanded(child: selectorWidget);
    }
  }


  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: isDark
                  ? BoxDecoration(
                color: const Color(0xFF334155).withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF475569),
                  width: 0.5,
                ),
              )
                  : null,
              child: Icon(
                Icons.analytics_outlined,
                size: 64,
                color: isDark
                    ? const Color(0xFF60A5FA).withOpacity(0.7)
                    : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Enter ${_searchType == 'user' ? 'user email' : 'slot ID'} to view analytics',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : Colors.grey[600],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: isDark
                ? color.withOpacity(0.9) // Slightly dimmed for dark mode
                : color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: isDark
                ? const Color(0xFF94A3B8)
                : Colors.grey,
          ),
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
                    'Utilization - ${data['dateRange']}',
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
    _searchDebounce?.cancel();
    _clearCaches(); // Clear caches when widget is disposed
    super.dispose();
  }

}