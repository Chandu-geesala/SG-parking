import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:park_sg/utils/analytics_helper.dart';
import 'package:park_sg/utils/analytics_web.dart';
import 'package:park_sg/utils/analytics_mobile.dart';

/// Advanced analytics export widget for parking slot utilization data
/// Supports comprehensive data export with date range filtering and Excel generation
class AnalyticsExportWidget extends StatefulWidget {
  /// Display title for the export widget
  final String title;

  /// Whether to show date range selection UI
  final bool showDateRange;

  /// Initial start date for data export
  final DateTime? initialStartDate;

  /// Initial end date for data export
  final DateTime? initialEndDate;

  /// Callback triggered when data needs to be refreshed
  final VoidCallback? onRefreshData;

  /// Types of exports to support ['users', 'slots', 'combined']
  final List<String>? exportTypes;

  const AnalyticsExportWidget({
    Key? key,
    this.title = 'Export Analytics',
    this.showDateRange = true,
    this.initialStartDate,
    this.initialEndDate,
    this.onRefreshData,
    this.exportTypes = const ['combined'],
  }) : super(key: key);

  @override
  State<AnalyticsExportWidget> createState() => _AnalyticsExportWidgetState();
}

class _AnalyticsExportWidgetState extends State<AnalyticsExportWidget> {
  // ============================================================================
  // CORE DEPENDENCIES & STATE VARIABLES
  // ============================================================================

  /// Firestore instance for database operations
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Selected date range for analytics export
  DateTime? _startDate;
  DateTime? _endDate;

  /// Export operation state management
  bool _isExporting = false;
  double _exportProgress = 0.0;

  // ============================================================================
  // CACHE MANAGEMENT SYSTEM
  // ============================================================================

  /// Static cache for slots data to reduce Firestore reads
  static Map<String, Map<String, dynamic>> _slotsCache = {};

  /// Timestamp when slots cache was last updated
  static DateTime? _slotsCacheTime;

  /// Cache expiry duration for performance optimization
  static const Duration _cacheExpiry = Duration(minutes: 10);

  /// Checks if the current cache is still valid
  bool get _isCacheValid {
    return _slotsCacheTime != null &&
        DateTime.now().difference(_slotsCacheTime!).inMinutes < _cacheExpiry.inMinutes;
  }

  /// Clears all cached data
  void _clearCaches() {
    _slotsCache.clear();
    _slotsCacheTime = null;
  }

  /// Loads slots data into cache for improved performance
  Future<void> _loadSlotsCache() async {
    // Return early if cache is still valid
    if (_isCacheValid && _slotsCache.isNotEmpty) return;

    try {
      final slotsQuery = await _firestore.collection('Slots').get();
      _slotsCache.clear();

      // Populate cache with slot data
      for (var doc in slotsQuery.docs) {
        _slotsCache[doc.id] = {
          'data': doc.data(),
          'id': doc.id,
        };
      }

      _slotsCacheTime = DateTime.now();
    } catch (e) {
      debugPrint('Error loading slots cache: $e');
    }
  }

  // ============================================================================
  // INITIALIZATION METHODS
  // ============================================================================

  @override
  void initState() {
    super.initState();
    _initializeDateRange();
  }

  /// Initializes the date range based on provided parameters or defaults
  void _initializeDateRange() {
    if (widget.initialStartDate != null && widget.initialEndDate != null) {
      _startDate = widget.initialStartDate;
      _endDate = widget.initialEndDate;
    } else {
      // Default to current month
      final now = DateTime.now();
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month + 1, 0);
    }
  }

  // ============================================================================
  // DATE RANGE MANAGEMENT
  // ============================================================================

  /// Generates optimized date range to prevent excessive Firestore queries
  List<String> _generateOptimizedDateRange(DateTime start, DateTime end) {
    final dates = <String>[];
    final totalDays = end.difference(start).inDays + 1;

    // Limit to maximum 90 days for performance
    final maxDays = totalDays > 90 ? 90 : totalDays;

    for (int i = 0; i < maxDays; i++) {
      final date = start.add(Duration(days: i));
      if (date.isAfter(end)) break;
      dates.add(DateFormat('yyyy-MM-dd').format(date));
    }

    return dates;
  }

  /// Shows date range picker dialog for user selection
  Future<void> _selectDateRange() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(2020);
    final DateTime lastDate = now;

    // Prepare initial range with validation
    DateTimeRange? initialRange;
    if (_startDate != null && _endDate != null) {
      DateTime validStartDate = _startDate!.isBefore(firstDate) ? firstDate : _startDate!;
      DateTime validEndDate = _endDate!.isAfter(lastDate) ? lastDate : _endDate!;

      if (validStartDate.isAfter(validEndDate)) {
        validStartDate = validEndDate;
      }

      initialRange = DateTimeRange(start: validStartDate, end: validEndDate);
    }

    // Show date range picker
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialRange,
      helpText: 'Select Analytics Date Range',
      confirmText: 'Apply',
      cancelText: 'Cancel',
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  // ============================================================================
  // DATA ANALYTICS METHODS
  // ============================================================================

  /// Retrieves comprehensive analytics data for all users
  Future<List<Map<String, dynamic>>> _getAllUsersAnalytics() async {
    if (_startDate == null || _endDate == null) return [];

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
    });

    try {
      // Load slots data into cache
      await _loadSlotsCache();
      setState(() => _exportProgress = 0.2);

      // Create user-slot mapping from allocated slots
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

      // Fetch booking data in optimized batches
      final dates = _generateOptimizedDateRange(_startDate!, _endDate!);
      final userBookings = <String, List<Map<String, dynamic>>>{};

      // Process dates in batches of 5 for better performance
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

        // Process booking results
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

        // Update progress
        setState(() => _exportProgress = 0.4 + (0.4 * (i + 5) / dates.length));
      }

      // Generate comprehensive user analytics
      final userAnalytics = <Map<String, dynamic>>[];
      final totalDays = _endDate!.difference(_startDate!).inDays + 1;

      for (final email in userSlotMap.keys) {
        final slotInfo = userSlotMap[email]!;
        final bookings = userBookings[email] ?? [];
        final utilizationPercentage = totalDays > 0
            ? (bookings.length / totalDays * 100).toDouble()
            : 0.0;

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
      debugPrint('Error getting users analytics: $e');
      _showErrorSnackBar('Failed to fetch user analytics: ${e.toString()}');
      return [];
    }
  }

  /// Retrieves comprehensive analytics data for all parking slots
  Future<List<Map<String, dynamic>>> _getAllSlotsAnalytics() async {
    if (_startDate == null || _endDate == null) return [];

    setState(() {
      _isExporting = true;
      _exportProgress = 0.1;
    });

    try {
      // Load slots data into cache
      await _loadSlotsCache();
      setState(() => _exportProgress = 0.2);

      // Fetch all booking data within date range
      final dates = _generateOptimizedDateRange(_startDate!, _endDate!);
      final allBookings = <String, List<Map<String, dynamic>>>{};

      // Process bookings in batches for performance
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

        // Aggregate bookings by slot
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

        // Update progress
        setState(() => _exportProgress = 0.2 + (0.6 * (i + 5) / dates.length));
      }

      // Generate comprehensive slot analytics
      final slotAnalytics = <Map<String, dynamic>>[];
      final totalDays = _endDate!.difference(_startDate!).inDays + 1;

      for (final slotEntry in _slotsCache.entries) {
        final slotId = slotEntry.key;
        final slotData = slotEntry.value['data'] as Map<String, dynamic>;
        final bookings = allBookings[slotId] ?? [];

        // Calculate user-wise booking frequency
        final userBookingCount = <String, int>{};
        for (final booking in bookings) {
          final bookedBy = booking['bookedBy'] as String;
          userBookingCount[bookedBy] = (userBookingCount[bookedBy] ?? 0) + 1;
        }

        final utilizationPercentage = totalDays > 0
            ? (bookings.length / totalDays * 100).toDouble()
            : 0.0;

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
      debugPrint('Error getting slots analytics: $e');
      _showErrorSnackBar('Failed to fetch slot analytics: ${e.toString()}');
      return [];
    }
  }

  // ============================================================================
  // EXCEL EXPORT FUNCTIONALITY
  // ============================================================================

  /// Creates and exports comprehensive analytics in Excel format
  Future<void> _exportCombinedAnalytics() async {
    try {
      // Check permissions before starting export
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        _showErrorSnackBar('Storage permission is required to save Excel files');
        return;
      }

      setState(() => _exportProgress = 0.05);

      // Fetch analytics data
      final userData = await _getAllUsersAnalytics();
      setState(() => _exportProgress = 0.5);

      final slotData = await _getAllSlotsAnalytics();
      setState(() => _exportProgress = 0.8);

      // Validate data availability
      if (userData.isEmpty && slotData.isEmpty) {
        _showErrorSnackBar('No data found for selected date range');
        return;
      }

      // Create Excel workbook
      final excel = Excel.createExcel();

      // Generate Users Analytics sheet
      if (userData.isNotEmpty) {
        _createUsersAnalyticsSheet(excel, userData);
      }

      // Generate Slots Analytics sheet
      if (slotData.isNotEmpty) {
        _createSlotsAnalyticsSheet(excel, slotData);
      }

      // Remove default sheet
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      setState(() => _exportProgress = 0.95);

      // Generate filename and save
      final fileName = _generateFileName();
      await _saveAndShareExcel(excel, fileName);

    } catch (e) {
      debugPrint('Export error: $e');
      _showErrorSnackBar('Error exporting analytics data: ${e.toString()}');
    } finally {
      setState(() {
        _isExporting = false;
        _exportProgress = 0.0;
      });
    }
  }

  /// Creates Users Analytics sheet in the Excel workbook
  void _createUsersAnalyticsSheet(Excel excel, List<Map<String, dynamic>> userData) {
    final usersSheet = excel['Users Analytics'];

    // Define headers for users sheet
    final userHeaders = [
      'Email', 'Allocated Slot', 'Allotted Date', 'Total Bookings',
      'Utilization %', 'Slot Priority', 'Vehicle Type', 'Date Range'
    ];

    // Create header row with styling
    for (int i = 0; i < userHeaders.length; i++) {
      final cell = usersSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = userHeaders[i];
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: '#4CAF50',
        fontColorHex: '#FFFFFF',
      );
    }

    // Populate data rows
    for (int i = 0; i < userData.length; i++) {
      final user = userData[i];
      final slotData = user['slotData'] as Map<String, dynamic>? ?? {};
      final row = i + 1;

      final rowData = [
        user['email'] ?? 'N/A',
        user['allocatedSlot'] ?? 'N/A',
        _formatDateForExcel(user['allotedDate']),
        user['totalBookings'] ?? 0,
        '${(user['utilizationPercentage'] ?? 0.0).toStringAsFixed(2)}%',
        slotData['slotPriority'] ?? 'N/A',
        slotData['vehicleType'] ?? 'N/A',
        _getDateRangeString(),
      ];

      for (int j = 0; j < rowData.length; j++) {
        usersSheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: row)).value = rowData[j];
      }
    }
  }

  /// Creates Slots Analytics sheet in the Excel workbook
  void _createSlotsAnalyticsSheet(Excel excel, List<Map<String, dynamic>> slotData) {
    final slotsSheet = excel['Slots Analytics'];

    // Define headers for slots sheet
    final slotHeaders = [
      'Slot ID', 'Vehicle Type', 'Priority', 'Allocated Users Count',
      'Total Bookings', 'Utilization %', 'Most Active User', 'Date Range'
    ];

    // Create header row with styling
    for (int i = 0; i < slotHeaders.length; i++) {
      final cell = slotsSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = slotHeaders[i];
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: '#2196F3',
        fontColorHex: '#FFFFFF',
      );
    }

    // Populate data rows
    for (int i = 0; i < slotData.length; i++) {
      final slot = slotData[i];
      final slotInfo = slot['slotData'] as Map<String, dynamic>;
      final userBookingCount = slot['userBookingCount'] as Map<String, int>;

      // Find most active user
      String mostActiveUser = 'N/A';
      if (userBookingCount.isNotEmpty) {
        mostActiveUser = userBookingCount.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
      }

      final row = i + 1;
      final rowData = [
        slot['slotId'] ?? 'N/A',
        slotInfo['vehicleType'] ?? 'N/A',
        slotInfo['slotPriority'] ?? 'N/A',
        (slot['allotedTo'] as List? ?? []).length,
        slot['totalBookings'] ?? 0,
        '${(slot['utilizationPercentage'] ?? 0.0).toStringAsFixed(2)}%',
        mostActiveUser,
        _getDateRangeString(),
      ];

      for (int j = 0; j < rowData.length; j++) {
        slotsSheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: row)).value = rowData[j];
      }
    }
  }

  // ============================================================================
  // FILE OPERATIONS & PERMISSIONS
  // ============================================================================

  /// Saves Excel file and handles platform-specific sharing
  Future<void> _saveAndShareExcel(Excel excel, String fileName) async {
    try {
      setState(() => _exportProgress = 0.1);

      final List<int>? bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Failed to encode Excel file');
      }

      setState(() => _exportProgress = 0.5);

      if (kIsWeb) {
        // Handle web download
        downloadExcelOnWeb(context, bytes, fileName);
      } else {
        // Handle mobile save
        await _saveExcelOnMobile(bytes, fileName);
      }

      setState(() => _exportProgress = 1.0);

    } catch (e) {
      setState(() => _exportProgress = 0.0);
      _showErrorSnackBar('Error saving Excel file: ${e.toString()}');
    }
  }

  /// Handles Excel file saving on mobile platforms
  Future<void> _saveExcelOnMobile(List<int> bytes, String fileName) async {
    try {
      // Check permissions for Android
      if (Platform.isAndroid) {
        final hasPermission = await _checkAndRequestPermissions();
        if (!hasPermission) {
          _showErrorSnackBar('Storage permission required to save files');
          return;
        }
      }

      setState(() => _exportProgress = 0.5);

      // Let user select save directory
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        setState(() => _exportProgress = 0.0);
        return;
      }

      setState(() => _exportProgress = 0.7);

      final file = File('$selectedDirectory/$fileName');

      // Check for existing file and confirm overwrite
      if (await file.exists()) {
        final shouldOverwrite = await _showOverwriteDialog(fileName);
        if (!shouldOverwrite) {
          setState(() => _exportProgress = 0.0);
          return;
        }
      }

      setState(() => _exportProgress = 0.9);

      // Write file to selected location
      await file.writeAsBytes(bytes);

      // Show success message with file location
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Excel file saved successfully!'),
              Text(
                'Location: ${file.path}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Copy Path',
            textColor: Colors.white,
            onPressed: () => _copyFilePathToClipboard(file.path),
          ),
        ),
      );

    } catch (e) {
      throw Exception('Failed to save file on mobile: $e');
    }
  }

  /// Checks and requests necessary storage permissions
  Future<bool> _checkAndRequestPermissions() async {
    if (kIsWeb) return true;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      // Handle different Android permission systems
      if (androidInfo.version.sdkInt >= 30) {
        // Android 11+ - Scoped storage
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          final result = await Permission.manageExternalStorage.request();
          return result.isGranted;
        }
        return true;
      } else {
        // Android 10 and below - Traditional storage permission
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

  /// Requests basic storage permission for file operations
  Future<bool> _requestStoragePermission() async {
    if (kIsWeb) return true;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      // Android 13+ handles permissions differently
      if (androidInfo.version.sdkInt >= 33) {
        return true;
      }

      final status = await Permission.storage.request();
      return status.isGranted;
    }

    return true;
  }

  // ============================================================================
  // DIALOG & UI HELPER METHODS
  // ============================================================================

  /// Shows confirmation dialog for file overwrite
  Future<bool> _showOverwriteDialog(String fileName) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('File Already Exists'),
            ],
          ),
          content: Text(
              'The file "$fileName" already exists in the selected directory. Do you want to overwrite it?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Overwrite'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  /// Copies file path to clipboard for user convenience
  Future<void> _copyFilePathToClipboard(String filePath) async {
    try {
      await Clipboard.setData(ClipboardData(text: filePath));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File path copied to clipboard'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error copying to clipboard: $e');
    }
  }

  /// Shows error messages to user
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ============================================================================
  // UTILITY & FORMATTING METHODS
  // ============================================================================

  /// Generates a descriptive filename for the exported Excel file
  String _generateFileName() {
    if (_startDate == null || _endDate == null) {
      return 'Analytics_Export_${DateFormat('dd_MMM_yyyy').format(DateTime.now())}.xlsx';
    }

    return 'Complete_Analytics_${DateFormat('dd_MMM_yyyy').format(_startDate!)}_to_${DateFormat('dd_MMM_yyyy').format(_endDate!)}.xlsx';
  }

  /// Formats date for Excel display
  String _formatDateForExcel(dynamic dateValue) {
    if (dateValue == null) return 'N/A';

    try {
      if (dateValue is String) {
        final date = DateTime.parse(dateValue);
        return DateFormat('dd-MM-yyyy').format(date);
      }
      return dateValue.toString();
    } catch (e) {
      return 'Invalid Date';
    }
  }

  /// Gets formatted date range string for display
  String _getDateRangeString() {
    if (_startDate == null || _endDate == null) return 'N/A';

    return '${DateFormat('dd-MM-yyyy').format(_startDate!)} to ${DateFormat('dd-MM-yyyy').format(_endDate!)}';
  }

  // ============================================================================
  // UI BUILDING METHODS
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: _buildContainerDecoration(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitle(isDark),
          const SizedBox(height: 16),
          if (widget.showDateRange) ...[
            _buildDateRangeSelector(isDark),
            const SizedBox(height: 16),
          ],
          _buildExportButton(isDark),
          if (_isExporting) ...[
            const SizedBox(height: 16),
            _buildProgressIndicator(isDark),
          ],
        ],
      ),
    );
  }

  /// Builds the container decoration based on theme
  BoxDecoration _buildContainerDecoration(bool isDark) {
    return BoxDecoration(
      gradient: isDark
          ? const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1E293B), Color(0xFF334155)],
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
    );
  }

  /// Builds the widget title
  Widget _buildTitle(bool isDark) {
    return Text(
      widget.title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: isDark ? const Color(0xFF60A5FA) : Colors.indigo,
      ),
    );
  }

  /// Builds the date range selector widget
  Widget _buildDateRangeSelector(bool isDark) {
    return LayoutBuilder(
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
                color: isDark ? const Color(0xFF334155).withOpacity(0.5) : null,
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
                    color: isDark ? const Color(0xFF60A5FA) : Colors.indigo,
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
                    color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the export button with responsive layout
  Widget _buildExportButton(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonStyle = ElevatedButton.styleFrom(
          backgroundColor: isDark ? const Color(0xFF7C3AED) : Colors.deepPurple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          elevation: isDark ? 6 : 2,
          shadowColor: isDark
              ? const Color(0xFF7C3AED).withOpacity(0.3)
              : null,
        );

        if (constraints.maxWidth > 600) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                width: 300,
                child: ElevatedButton.icon(
                  onPressed: _isExporting ? null : _exportCombinedAnalytics,
                  icon: const Icon(Icons.download, color: Colors.white),
                  label: const Text('Export Complete Analytics'),
                  style: buttonStyle,
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
              style: buttonStyle,
            ),
          );
        }
      },
    );
  }

  /// Builds the progress indicator for export operation
  Widget _buildProgressIndicator(bool isDark) {
    return LayoutBuilder(
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
                  isDark ? const Color(0xFF60A5FA) : Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Exporting... ${(_exportProgress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================================
  // PUBLIC METHODS & CLEANUP
  // ============================================================================

  /// Public method to refresh data (can be called from parent widget)
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


class BookingLimitToggleWidget extends StatefulWidget {
  /// Callback when toggle changes, e.g. to save backend setting later.
  final ValueChanged<bool>? onToggleChanged;

  const BookingLimitToggleWidget({
    Key? key,
    this.onToggleChanged,
  }) : super(key: key);

  @override
  State<BookingLimitToggleWidget> createState() =>
      _BookingLimitToggleWidgetState();
}

class _BookingLimitToggleWidgetState extends State<BookingLimitToggleWidget> {
  bool? _isEnabled; // nullable to show loading initially
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchToggleStateFromFirestore();
  }

  Future<void> _fetchToggleStateFromFirestore() async {
    try {
      final docRef = FirebaseFirestore.instance.collection('limit').doc('config');
      final docSnap = await docRef.get();

      final data = docSnap.data();
      final toggleOn = data != null && data['toggleOn'] is bool ? data['toggleOn'] as bool : false;

      // Update the state with the fetched toggle value
      setState(() {
        _isEnabled = toggleOn;
        _isLoading = false;
      });
    } catch (e) {
      // In case of error, default false, but hide loader
      setState(() {
        _isEnabled = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateBookingLimitToggle(bool toggleOn) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final docRef = firestore.collection('limit').doc('config');
    final now = DateTime.now();

    // Fetch existing data so we don't overwrite monthCounts if present
    final docSnap = await docRef.get();
    Map<String, dynamic> data = docSnap.data() ?? {};
    Map<String, dynamic> monthCounts = Map<String, dynamic>.from(data['monthCounts'] ?? {});

    // Add working days counts for months from current to December if not present
    for (int m = now.month; m <= 12; m++) {
      final monthStr = DateFormat('MMMM').format(DateTime(now.year, m));
      if (!monthCounts.containsKey(monthStr)) {
        monthCounts[monthStr] = _workingDaysInMonth(now.year, m);
      }
    }

    // Prepare and save data
    await docRef.set({
      'toggleOn': toggleOn,
      'monthCounts': monthCounts,
    }, SetOptions(merge: true));
  }

  // Helper to calculate working days (excludes Sat, Sun)
  int _workingDaysInMonth(int year, int month) {
    int count = 0;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    for (int d = 1; d <= daysInMonth; d++) {
      final weekday = DateTime(year, month, d).weekday;
      if (weekday != DateTime.saturday && weekday != DateTime.sunday) count++;
    }
    return count;
  }

  void _onToggle(bool newValue) async {
    setState(() {
      _isEnabled = newValue;
    });

    await _updateBookingLimitToggle(newValue);

    widget.onToggleChanged?.call(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final bgColor = isDark ? Colors.grey[850] : Colors.grey[100];
    final cardColor = isDark ? Colors.grey[900] : Colors.white;
    final borderColor = isDark ? Colors.blue[300]! : Colors.blue[600]!;

    if (_isLoading || _isEnabled == null) {
      // Show loading spinner while fetching the toggle status
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ]
            : [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
        border: Border.all(
          color: _isEnabled! ? borderColor : Colors.transparent,
          width: _isEnabled! ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title Row: Label + Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enable Monthly Booking Limit',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _isEnabled! ? primaryColor : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              Switch.adaptive(
                value: _isEnabled!,
                onChanged: _onToggle,
                activeColor: primaryColor,
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.grey.withOpacity(0.4),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Description
          Text(
            'Toggle this to enable fair monthly booking limits per user, excluding weekends',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),

        ],
      ),
    );
  }
}
