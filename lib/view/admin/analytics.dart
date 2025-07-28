import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:park_sg/utils/analytics_helper.dart';
import 'package:park_sg/utils/analytics_web.dart';
import 'package:park_sg/utils/analytics_mobile.dart';
import 'dart:convert';

class AnalyticsExportWidget extends StatefulWidget {
  final String title;
  final bool showDateRange;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final VoidCallback? onRefreshData;
  final List<String>? exportTypes; // ['users', 'slots', 'combined']

  const AnalyticsExportWidget({
    Key? key,
    this.title = 'Export Analytics',
    this.showDateRange = true,
    this.initialStartDate,
    this.initialEndDate,
    this.onRefreshData,
    this.exportTypes = const ['combined'], // Default to combined export
  }) : super(key: key);

  @override
  _AnalyticsExportWidgetState createState() => _AnalyticsExportWidgetState();
}

class _AnalyticsExportWidgetState extends State<AnalyticsExportWidget> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime? _startDate;
  DateTime? _endDate;
  bool _isExporting = false;
  double _exportProgress = 0.0;

  // Cache management
  static Map<String, Map<String, dynamic>> _slotsCache = {};
  static DateTime? _slotsCacheTime;
  static const Duration _cacheExpiry = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();

    // Initialize dates
    if (widget.initialStartDate != null && widget.initialEndDate != null) {
      _startDate = widget.initialStartDate;
      _endDate = widget.initialEndDate;
    } else {
      final now = DateTime.now();
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month + 1, 0);
    }
  }

  // Cache management methods
  bool get _isCacheValid {
    return _slotsCacheTime != null &&
        DateTime.now().difference(_slotsCacheTime!).inMinutes < _cacheExpiry.inMinutes;
  }

  void _clearCaches() {
    _slotsCache.clear();
    _slotsCacheTime = null;
  }

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
    }
  }

  List<String> _generateOptimizedDateRange(DateTime start, DateTime end) {
    final dates = <String>[];
    final totalDays = end.difference(start).inDays + 1;
    final maxDays = totalDays > 90 ? 90 : totalDays;

    for (int i = 0; i < maxDays; i++) {
      final date = start.add(Duration(days: i));
      if (date.isAfter(end)) break;
      dates.add(DateFormat('yyyy-MM-dd').format(date));
    }

    return dates;
  }

  Future<void> _selectDateRange() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(2020);
    final DateTime lastDate = now;

    DateTimeRange? initialRange;
    if (_startDate != null && _endDate != null) {
      DateTime validStartDate = _startDate!.isBefore(firstDate) ? firstDate : _startDate!;
      DateTime validEndDate = _endDate!.isAfter(lastDate) ? lastDate : _endDate!;

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

  Future<List<Map<String, dynamic>>> _getAllUsersAnalytics() async {
    if (_startDate == null || _endDate == null) return [];

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
    });

    try {
      await _loadSlotsCache();
      setState(() => _exportProgress = 0.2);

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

      final dates = _generateOptimizedDateRange(_startDate!, _endDate!);
      final userBookings = <String, List<Map<String, dynamic>>>{};

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

  Future<List<Map<String, dynamic>>> _getAllSlotsAnalytics() async {
    if (_startDate == null || _endDate == null) return [];

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
    });

    try {
      await _loadSlotsCache();
      setState(() => _exportProgress = 0.2);

      final dates = _generateOptimizedDateRange(_startDate!, _endDate!);
      final allBookings = <String, List<Map<String, dynamic>>>{};

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

      final slotAnalytics = <Map<String, dynamic>>[];
      final totalDays = _endDate!.difference(_startDate!).inDays + 1;

      for (final slotEntry in _slotsCache.entries) {
        final slotId = slotEntry.key;
        final slotData = slotEntry.value['data'] as Map<String, dynamic>;
        final bookings = allBookings[slotId] ?? [];

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

  Future<void> _saveAndShareExcel(Excel excel, String fileName) async {
    try {
      setState(() => _exportProgress = 0.1);

      final List<int>? bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Failed to encode Excel file');
      }

      setState(() => _exportProgress = 0.5);

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

  Future<void> _saveExcelOnMobile(List<int> bytes, String fileName) async {
    try {
      if (Platform.isAndroid) {
        final hasPermission = await _checkAndRequestPermissions();
        if (!hasPermission) {
          _showErrorSnackBar('Storage permission required to save files');
          return;
        }
      }

      setState(() => _exportProgress = 0.5);

      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        setState(() => _exportProgress = 0.0);
        return;
      }

      setState(() => _exportProgress = 0.7);

      final file = File('$selectedDirectory/$fileName');

      if (await file.exists()) {
        final shouldOverwrite = await _showOverwriteDialog(fileName);
        if (!shouldOverwrite) {
          setState(() => _exportProgress = 0.0);
          return;
        }
      }

      setState(() => _exportProgress = 0.9);

      await file.writeAsBytes(bytes);

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
    if (kIsWeb) return true;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      if (androidInfo.version.sdkInt >= 30) {
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          final result = await Permission.manageExternalStorage.request();
          return result.isGranted;
        }
        return true;
      } else {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final result = await Permission.storage.request();
          return result.isGranted;
        }
        return true;
      }
    }
    return true;
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

  Future<void> _openFileLocation(String filePath) async {
    try {
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File has been downloaded to your default download folder'),
            backgroundColor: Colors.blue,
          ),
        );
      } else {
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

  Future<bool> _requestStoragePermission() async {
    if (kIsWeb) return true;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        return true;
      }

      final status = await Permission.storage.request();
      return status.isGranted;
    } else {
      return true;
    }
  }

  Future<void> _exportCombinedAnalytics() async {
    try {
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        _showErrorSnackBar('Storage permission is required to save Excel files');
        return;
      }

      setState(() => _exportProgress = 0.05);

      final userData = await _getAllUsersAnalytics();
      setState(() => _exportProgress = 0.5);

      final slotData = await _getAllSlotsAnalytics();
      setState(() => _exportProgress = 0.8);

      if (userData.isEmpty && slotData.isEmpty) {
        _showErrorSnackBar('No data found for selected date range');
        return;
      }

      final excel = Excel.createExcel();

      if (userData.isNotEmpty) {
        final usersSheet = excel['Users Analytics'];

        final userHeaders = [
          'Email', 'Allocated Slot', 'Allotted Date', 'Total Bookings',
          'Utilization %', 'Slot Priority', 'Vehicle Type', 'Date Range'
        ];

        for (int i = 0; i < userHeaders.length; i++) {
          final cell = usersSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
          cell.value = userHeaders[i];
          cell.cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: '#4CAF50',
            fontColorHex: '#FFFFFF',
          );
        }

        for (int i = 0; i < userData.length; i++) {
          final user = userData[i];
          final slotData = user['slotData'] as Map<String, dynamic>? ?? {};
          final row = i + 1;

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
            usersSheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: row)).value = rowData[j];
          }
        }
      }

      if (slotData.isNotEmpty) {
        final slotsSheet = excel['Slots Analytics'];

        final slotHeaders = [
          'Slot ID', 'Vehicle Type', 'Priority', 'Allocated Users Count',
          'Total Bookings', 'Utilization %', 'Most Active User', 'Date Range'
        ];

        for (int i = 0; i < slotHeaders.length; i++) {
          final cell = slotsSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
          cell.value = slotHeaders[i];
          cell.cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: '#2196F3',
            fontColorHex: '#FFFFFF',
          );
        }

        for (int i = 0; i < slotData.length; i++) {
          final slot = slotData[i];
          final slotInfo = slot['slotData'] as Map<String, dynamic>;
          final userBookingCount = slot['userBookingCount'] as Map<String, int>;

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
            slotsSheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: row)).value = rowData[j];
          }
        }
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      setState(() => _exportProgress = 0.95);

      final fileName = 'Complete_Analytics_${DateFormat('dd_MMM_yyyy').format(_startDate!)}_to_${DateFormat('dd_MMM_yyyy').format(_endDate!)}.xlsx';
      await _saveAndShareExcel(excel, fileName);

    } catch (e) {
      _showErrorSnackBar('Error exporting analytics data: ${e.toString()}');
    } finally {
      setState(() {
        _isExporting = false;
        _exportProgress = 0.0;
      });
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

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
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
            widget.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? const Color(0xFF60A5FA)
                  : Colors.indigo,
            ),
          ),
          const SizedBox(height: 16),

          // Date range selection (conditionally shown)
          if (widget.showDateRange) ...[
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
          ],

          // Export buttons
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 600) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 300,
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportCombinedAnalytics,
                        icon: Icon(
                          Icons.download,
                          color: Colors.white,
                        ),
                        label: const Text('Export Complete Analytics'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF7C3AED)
                              : Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: isDark ? 6 : 2,
                          shadowColor: isDark
                              ? const Color(0xFF7C3AED).withOpacity(0.3)
                              : null,
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportCombinedAnalytics,
                    icon: const Icon(Icons.download),
                    label: const Text('Export Complete Analytics'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFF7C3AED)
                          : Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: isDark ? 6 : 2,
                      shadowColor: isDark
                          ? const Color(0xFF7C3AED).withOpacity(0.3)
                          : null,
                    ),
                  ),
                );
              }
            },
          ),

          // Progress indicator
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

  // Public method to refresh data (can be called from parent)
  void refreshData() {
    _clearCaches();
    widget.onRefreshData?.call();
  }

  @override
  void dispose() {
    _clearCaches();
    super.dispose();
  }
}