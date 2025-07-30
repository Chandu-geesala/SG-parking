import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../viewModel/bookingBackend.dart';
import 'dart:async';
import 'analytics.dart';

class BookingDashboard extends StatefulWidget {
  const BookingDashboard({Key? key}) : super(key: key);

  @override
  State<BookingDashboard> createState() => _BookingDashboardState();
}

class _BookingDashboardState extends State<BookingDashboard>
    with SingleTickerProviderStateMixin {

  // ============================================================================
  // CORE DEPENDENCIES & VARIABLES
  // ============================================================================

  final BookingBackend _backend = BookingBackend();
  late TabController _tabController;

  // Date selection variables
  DateTime _selectedDate = DateTime.now();
  String _selectedDateType = 'today';

  // Filter variables
  String? _selectedVehicleType; // 'CAR' or 'BIKE'
  String? _selectedSlotStatus; // 'booked', 'available', 'unbooked'
  List<Map<String, dynamic>> _filteredSlots = [];
  bool _isLoadingFilteredSlots = false;

  // Data variables
  Map<String, dynamic> _slotStatistics = {};
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _availableSlots = [];
  bool _isLoading = true;
  bool _isLoadingSlots = false;

  // Cache management
  final Map<String, List<Map<String, dynamic>>> _bookingsCache = {};
  final Map<String, List<Map<String, dynamic>>> _slotsCache = {};
  final Map<String, Map<String, dynamic>> _statisticsCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  // Debouncing for date selection
  Timer? _debounceTimer;

  // ============================================================================
  // LIFECYCLE METHODS
  // ============================================================================

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ============================================================================
  // DATA LOADING METHODS
  // ============================================================================

  /// Load initial data for today's dashboard
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await _loadDataForDate('today');
    } catch (e) {
      _showError('Error loading initial data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Load data for specific date type (today, tomorrow, custom)
  Future<void> _loadDataForDate(String dateType) async {
    DateTime targetDate;
    switch (dateType) {
      case 'today':
        targetDate = DateTime.now();
        break;
      case 'tomorrow':
        targetDate = DateTime.now().add(const Duration(days: 1));
        break;
      default:
        targetDate = _selectedDate;
    }

    final statisticsCacheKey = _getCacheKey(targetDate, 'statistics');
    final slotsCacheKey = _getCacheKey(targetDate, 'slots');

    // Check cache first for statistics
    if (_isCacheValid(statisticsCacheKey) && _statisticsCache.containsKey(statisticsCacheKey)) {
      setState(() {
        _slotStatistics = _statisticsCache[statisticsCacheKey]!;
        _selectedDateType = dateType;
      });
    } else {
      await _fetchSlotStatisticsFromBackend(targetDate, statisticsCacheKey);
    }

    // Load available slots only for today to reduce reads
    if (_isTodayDate(targetDate)) {
      if (_isCacheValid(slotsCacheKey) && _slotsCache.containsKey(slotsCacheKey)) {
        setState(() => _availableSlots = _slotsCache[slotsCacheKey]!);
      } else {
        await _fetchAvailableSlotsFromFirestore(slotsCacheKey);
      }
    } else {
      setState(() => _availableSlots = []);
    }
  }

  /// Fetch slot statistics from backend and calculate counts
  Future<void> _fetchSlotStatisticsFromBackend(DateTime targetDate, String cacheKey) async {
    try {
      final bookingBackend = BookingBackend();

      final futures = await Future.wait([
        bookingBackend.getAvailableSlotsForToday(),
        bookingBackend.getBookingsForDate(targetDate),
        bookingBackend.getAvailableSlotsFromDeclarations(date: targetDate, vehicleTypeFilter: null),
      ]);

      final allSlots = futures[0] as List<Map<String, dynamic>>;
      final bookedSlots = futures[1] as List<Map<String, dynamic>>;
      final availableSlots = futures[2] as List<Map<String, dynamic>>;

      // Process statistics
      Map<String, int> totalSlots = {'CAR': 0, 'BIKE': 0};
      Map<String, int> bookedCounts = {'CAR': 0, 'BIKE': 0};
      Map<String, int> availableCounts = {'CAR': 0, 'BIKE': 0};
      Map<String, int> unbookedCounts = {'CAR': 0, 'BIKE': 0};

      // Count total slots by vehicle type
      Set<String> allSlotIds = {};
      for (var slot in allSlots) {
        final vehicleType = (slot['vehicleType'] as String? ?? 'BIKE').toUpperCase();
        final slotId = slot['slotId'] as String;
        allSlotIds.add(slotId);
        if (vehicleType == 'CAR' || vehicleType == 'BIKE') {
          totalSlots[vehicleType] = (totalSlots[vehicleType] ?? 0) + 1;
        }
      }

      // Count booked slots by vehicle type
      Set<String> bookedSlotIds = {};
      for (var booking in bookedSlots) {
        final slotId = booking['slotId'] as String;
        final bookingData = booking['bookingData'] as Map<String, dynamic>;
        final vehicleType = (bookingData['vehicleType'] as String? ?? 'BIKE').toUpperCase();

        bookedSlotIds.add(slotId);
        if (vehicleType == 'CAR' || vehicleType == 'BIKE') {
          bookedCounts[vehicleType] = (bookedCounts[vehicleType] ?? 0) + 1;
        }
      }

      // Count available slots properly
      Set<String> availableSlotIds = {};
      for (var slot in availableSlots) {
        try {
          final slotId = slot['slotId'] as String;
          String vehicleType = 'BIKE'; // Default

          if (slot.containsKey('vehicleType')) {
            vehicleType = (slot['vehicleType'] as String? ?? 'BIKE').toUpperCase();
          } else if (slot.containsKey('slotData') && slot['slotData'] is Map) {
            final slotData = slot['slotData'] as Map<String, dynamic>;
            if (slotData.containsKey('vehicleType')) {
              vehicleType = (slotData['vehicleType'] as String? ?? 'BIKE').toUpperCase();
            }
          }

          availableSlotIds.add(slotId);
          if (vehicleType == 'CAR' || vehicleType == 'BIKE') {
            availableCounts[vehicleType] = (availableCounts[vehicleType] ?? 0) + 1;
          }
        } catch (e) {
          print('Error processing available slot: $e');
        }
      }

      // Calculate unbooked slots
      final occupiedSlotIds = {...bookedSlotIds, ...availableSlotIds};
      final unbookedSlotIds = allSlotIds.difference(occupiedSlotIds);

      for (var slot in allSlots) {
        final slotId = slot['slotId'] as String;
        if (unbookedSlotIds.contains(slotId)) {
          final vehicleType = (slot['vehicleType'] as String? ?? 'BIKE').toUpperCase();
          if (vehicleType == 'CAR' || vehicleType == 'BIKE') {
            unbookedCounts[vehicleType] = (unbookedCounts[vehicleType] ?? 0) + 1;
          }
        }
      }

      final statistics = {
        'bookedSlots': bookedCounts,
        'availableSlots': availableCounts,
        'unbookedSlots': unbookedCounts,
        'date': DateFormat('yyyy-MM-dd').format(targetDate),
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      };

      _statisticsCache[cacheKey] = statistics;
      _cacheTimestamps[cacheKey] = DateTime.now();
      setState(() => _slotStatistics = statistics);
    } catch (e) {
      print('Error in _fetchSlotStatisticsFromBackend: $e');
      _showError('Error loading slot statistics: $e');
    }
  }

  /// Fetch available slots from Firestore
  Future<void> _fetchAvailableSlotsFromFirestore(String cacheKey) async {
    setState(() => _isLoadingSlots = true);
    try {
      final availableSlots = await BookingBackend().getAvailableSlotsForToday();
      _slotsCache[cacheKey] = availableSlots;
      _cacheTimestamps[cacheKey] = DateTime.now();
      setState(() {
        _availableSlots = availableSlots;
        _isLoadingSlots = false;
      });
    } catch (e) {
      setState(() => _isLoadingSlots = false);
      _showError('Error loading available slots: $e');
    }
  }

  /// Load filtered slots based on selected criteria
  Future<void> _loadFilteredSlots() async {
    if (_selectedVehicleType == null || _selectedSlotStatus == null) return;

    setState(() => _isLoadingFilteredSlots = true);
    try {
      DateTime targetDate = _getTargetDateFromSelection();
      List<Map<String, dynamic>> slots = [];

      switch (_selectedSlotStatus) {
        case 'booked':
          final bookings = await BookingBackend().getBookingsForDate(targetDate);
          slots = bookings.where((booking) {
            final bookingData = booking['bookingData'] as Map<String, dynamic>;
            final vehicleType = (bookingData['vehicleType'] as String? ?? 'BIKE').toUpperCase();
            return vehicleType == _selectedVehicleType;
          }).toList();
          break;

        case 'available':
          final availableSlots = await BookingBackend().getAvailableSlotsFromDeclarations(
            date: targetDate,
            vehicleTypeFilter: _selectedVehicleType,
          );
          slots = availableSlots;
          break;

        case 'unbooked':
          final allSlots = await BookingBackend().getAvailableSlotsForToday();
          final bookedSlots = await BookingBackend().getBookingsForDate(targetDate);
          final availableSlots = await BookingBackend().getUnbookedAvailableSlotsForDate(date: targetDate);

          final bookedSlotIds = bookedSlots.map((b) => b['slotId'] as String).toSet();
          final availableSlotIds = availableSlots.map((s) => s['slotId'] as String).toSet();
          final occupiedSlotIds = {...bookedSlotIds, ...availableSlotIds};

          slots = allSlots.where((slot) {
            final slotId = slot['slotId'] as String;
            final vehicleType = (slot['vehicleType'] as String? ?? 'BIKE').toUpperCase();
            return vehicleType == _selectedVehicleType && !occupiedSlotIds.contains(slotId);
          }).toList();
          break;
      }

      setState(() {
        _filteredSlots = slots;
        _isLoadingFilteredSlots = false;
      });
    } catch (e) {
      setState(() => _isLoadingFilteredSlots = false);
      _showError('Error loading filtered slots: $e');
    }
  }

  // ============================================================================
  // CACHE MANAGEMENT METHODS
  // ============================================================================

  /// Generate cache key for date and type
  String _getCacheKey(DateTime date, String type) {
    return '${DateFormat('yyyy-MM-dd').format(date)}_$type';
  }

  /// Check if cache is valid (not expired)
  bool _isCacheValid(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheExpiry;
  }

  /// Clean up expired cache entries
  void _cleanupExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    _cacheTimestamps.forEach((key, timestamp) {
      if (now.difference(timestamp) > _cacheExpiry) {
        expiredKeys.add(key);
      }
    });

    for (final key in expiredKeys) {
      _bookingsCache.remove(key);
      _slotsCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  // ============================================================================
  // EVENT HANDLERS
  // ============================================================================

  /// Handle date type change with debouncing
  void _onDateTypeChanged(String dateType) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _loadDataForDate(dateType);
    });
  }

  /// Handle stat card tap for filtering
  void _onStatCardTapped(String status, String vehicleType) {
    setState(() {
      if (_selectedVehicleType == vehicleType && _selectedSlotStatus == status) {
        _selectedVehicleType = null;
        _selectedSlotStatus = null;
        _filteredSlots = [];
      } else {
        _selectedVehicleType = vehicleType;
        _selectedSlotStatus = status;
      }
    });

    if (_selectedVehicleType != null && _selectedSlotStatus != null) {
      _loadFilteredSlots();
    }
  }

  /// Handle date picker selection
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF6C5CE7),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _selectedDateType = 'custom';
      });
      _onDateTypeChanged('custom');
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Check if date is today
  bool _isTodayDate(DateTime date) {
    final now = DateTime.now();
    return date.day == now.day && date.month == now.month && date.year == now.year;
  }

  /// Get target date from current selection
  DateTime _getTargetDateFromSelection() {
    switch (_selectedDateType) {
      case 'today':
        return DateTime.now();
      case 'tomorrow':
        return DateTime.now().add(const Duration(days: 1));
      default:
        return _selectedDate;
    }
  }

  /// Get date title for display
  String _getDateTitle() {
    switch (_selectedDateType) {
      case 'today':
        return 'Today';
      case 'tomorrow':
        return 'Tomorrow';
      default:
        return DateFormat('MMM dd, yyyy').format(_selectedDate);
    }
  }

  /// Extract vehicle type from slot data
  String _extractVehicleType(Map<String, dynamic> slot) {
    if (slot.containsKey('vehicleType')) {
      return (slot['vehicleType'] as String? ?? 'BIKE').toUpperCase();
    } else if (slot.containsKey('slotData') && slot['slotData'] is Map) {
      final slotData = slot['slotData'] as Map<String, dynamic>;
      return (slotData['vehicleType'] as String? ?? 'BIKE').toUpperCase();
    }
    return 'BIKE';
  }

  /// Get user name from email
  String _getUserNameFromEmail(String email) {
    return email.split('@').first;
  }

  /// Get color for reason status
  Color _getReasonColor(String reason) {
    switch (reason.toLowerCase()) {
      case 'wfh':
        return Colors.blue[600]!;
      case 'leave':
        return Colors.orange[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  /// Get display text for reason
  String _getReasonDisplayText(String reason) {
    switch (reason.toLowerCase()) {
      case 'wfh':
        return 'WFH';
      case 'leave':
        return 'Leave';
      default:
        return reason.toUpperCase();
    }
  }

  /// Get vehicle color based on type
  Color _getVehicleColor(String vehicleType) {
    switch (vehicleType.toUpperCase()) {
      case 'CAR':
        return Colors.blue[600]!;
      case 'BIKE':
        return Colors.orange[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  /// Get vehicle icon based on type
  IconData _getVehicleIcon(String vehicleType) {
    switch (vehicleType.toUpperCase()) {
      case 'CAR':
        return Icons.directions_car_rounded;
      case 'BIKE':
        return Icons.two_wheeler_rounded;
      default:
        return Icons.local_parking_rounded;
    }
  }

  /// Get detailed slot information
  Future<Map<String, dynamic>?> _getDetailedSlotInfo(String slotId) async {
    try {
      DateTime targetDate = _getTargetDateFromSelection();
      final detailedSlots = await BookingBackend().getAvailableSlotsWithUserDetails(
        date: targetDate,
        vehicleTypeFilter: null,
      );
      return detailedSlots.firstWhere(
            (slot) => slot['slotId'] == slotId,
        orElse: () => <String, dynamic>{},
      );
    } catch (e) {
      print('Error fetching detailed slot info: $e');
      return null;
    }
  }

  /// Show error message
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  // ============================================================================
  // UI BUILDING METHODS
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? theme.scaffoldBackgroundColor
          : const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark
            ? theme.appBarTheme.backgroundColor
            : Colors.white,
        title: Text(
          'Booking Dashboard',
          style: TextStyle(
            color: isDark
                ? theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface
                : const Color(0xFF2D3748),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isWebView = constraints.maxWidth > 800;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWebView ? 32.0 : 16.0,
              vertical: isWebView ? 24.0 : 16.0,
            ),
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isWebView ? 1000 : double.infinity,
                ),
                child: _buildOverviewTab(),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build main overview tab content
  Widget _buildOverviewTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isLargeScreen = constraints.maxWidth > 800;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateSelector(),
            SizedBox(height: isLargeScreen ? 24 : 20),
            _buildSlotStatistics(),
            SizedBox(height: isLargeScreen ? 24 : 20),
            _buildFilteredSlotsList(),
            SizedBox(height: isLargeScreen ? 24 : 20),
            const AnalyticsExportWidget(),
          ],
        );
      },
    );
  }

  /// Build date selector widget
  Widget _buildDateSelector() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              'Date:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildCompactDateChip('Today', 'today'),
                    const SizedBox(width: 8),
                    _buildCompactDateChip('Tomorrow', 'tomorrow'),
                    const SizedBox(width: 8),
                    _buildCompactDateChipWithIcon('Custom', 'custom', Icons.calendar_today),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build compact date selection chip
  Widget _buildCompactDateChip(String title, String type) {
    final isSelected = _selectedDateType == type;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () async {
        if (type == 'custom') {
          await _selectDate();
        } else {
          setState(() => _selectedDateType = type);
          _onDateTypeChanged(type);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? theme.colorScheme.primary.withOpacity(0.2) : const Color(0xFF6C5CE7).withOpacity(0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (isDark ? theme.colorScheme.primary : const Color(0xFF6C5CE7))
                : (isDark ? theme.colorScheme.outline.withOpacity(0.3) : Colors.grey.withOpacity(0.3)),
            width: 1,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? (isDark ? theme.colorScheme.primary : const Color(0xFF6C5CE7))
                : (isDark ? theme.colorScheme.onSurfaceVariant : Colors.grey[600]),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Build compact date chip with icon
  Widget _buildCompactDateChipWithIcon(String title, String type, IconData icon) {
    final isSelected = _selectedDateType == type;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () async {
        if (type == 'custom') {
          await _selectDate();
        } else {
          setState(() => _selectedDateType = type);
          _onDateTypeChanged(type);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? theme.colorScheme.primary.withOpacity(0.2) : const Color(0xFF6C5CE7).withOpacity(0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (isDark ? theme.colorScheme.primary : const Color(0xFF6C5CE7))
                : (isDark ? theme.colorScheme.outline.withOpacity(0.3) : Colors.grey.withOpacity(0.3)),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: isSelected
                    ? (isDark ? theme.colorScheme.primary : const Color(0xFF6C5CE7))
                    : (isDark ? theme.colorScheme.onSurfaceVariant : Colors.grey[600])),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? (isDark ? theme.colorScheme.primary : const Color(0xFF6C5CE7))
                    : (isDark ? theme.colorScheme.onSurfaceVariant : Colors.grey[600]),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build slot statistics dashboard
  Widget _buildSlotStatistics() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final colorScheme = theme.colorScheme;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: isDark ? colorScheme.surface : null,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live Dashboard - ${_getDateTitle()}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? colorScheme.onSurface : const Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 12),

                if (_isLoading)
                  Container(
                    height: 60,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? colorScheme.primary : const Color(0xFF6C5CE7),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (_slotStatistics.isEmpty)
                  Container(
                    height: 60,
                    child: Center(
                      child: Text(
                        'No data available',
                        style: TextStyle(
                          color: isDark ? colorScheme.onSurfaceVariant : const Color(0xFF718096),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      _buildBeautifulVehicleRow('CAR', const Color(0xFF3B82F6)),
                      const SizedBox(height: 8),
                      _buildBeautifulVehicleRow('BIKE', const Color(0xFF10B981)),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build beautiful vehicle statistics row
  Widget _buildBeautifulVehicleRow(String vehicleType, Color primaryColor) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final booked = _slotStatistics['bookedSlots']?[vehicleType] ?? 0;
    final available = _slotStatistics['availableSlots']?[vehicleType] ?? 0;
    final unbooked = _slotStatistics['unbookedSlots']?[vehicleType] ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withOpacity(0.05),
            primaryColor.withOpacity(0.02),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: primaryColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              vehicleType,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: primaryColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                _buildMiniStatChip('Booked', booked, const Color(0xFFEF4444), vehicleType),
                const SizedBox(width: 6),
                _buildMiniStatChip('Available', available, const Color(0xFFF59E0B), vehicleType),
                const SizedBox(width: 6),
                _buildMiniStatChip('Unbooked', unbooked, const Color(0xFF6B7280), vehicleType),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build mini stat chip for vehicle row
  Widget _buildMiniStatChip(String label, int count, Color color, String vehicleType) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = _selectedVehicleType == vehicleType && _selectedSlotStatus == label.toLowerCase();

    return Expanded(
      child: GestureDetector(
        onTap: () => _onStatCardTapped(label.toLowerCase(), vehicleType),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(0.2)
                : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: isSelected
                ? Border.all(color: color, width: 1.5)
                : Border.all(color: color.withOpacity(0.2), width: 1),
            boxShadow: isSelected ? [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? color : colorScheme.onSurface,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? color : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build filtered slots list
  Widget _buildFilteredSlotsList() {
    if (_selectedVehicleType == null || _selectedSlotStatus == null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 200),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.touch_app, size: 64, color: Colors.grey.withOpacity(0.5)),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Text(
                  'Tap on any statistic card above to view related slots',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: isDark ? 8 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? colorScheme.surface : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedSlotStatus?.toUpperCase()} Slots - ${_getDateTitle()}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_isLoadingFilteredSlots)
              Container(
                width: double.infinity,
                height: 150,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filteredSlots.isEmpty)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 150),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off, size: 48, color: Colors.grey.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Text(
                        'No ${_selectedSlotStatus} ${_selectedVehicleType?.toLowerCase()} slots found for ${_getDateTitle().toLowerCase()}',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )
            else
              _buildFilteredSlotsContent(),
          ],
        ),
      ),
    );
  }

  /// Build filtered slots content with grid/list layout
  Widget _buildFilteredSlotsContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isLargeScreen = constraints.maxWidth > 800;

        if (_selectedSlotStatus == 'available') {
          if (isLargeScreen) {
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth > 900 ? 3 : 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: _filteredSlots.length,
              itemBuilder: (context, index) => _buildEnhancedAvailableSlotCard(_filteredSlots[index], isLargeScreen: true),
            );
          } else {
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredSlots.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _buildEnhancedAvailableSlotCard(_filteredSlots[index], isLargeScreen: false),
            );
          }
        }

        if (isLargeScreen) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: constraints.maxWidth > 900 ? 3 : 2,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              childAspectRatio: _selectedSlotStatus == 'booked' ? 1.7 : 1.6,
            ),
            itemCount: _filteredSlots.length,
            itemBuilder: (context, index) => _buildCompactSlotCard(_filteredSlots[index]),
          );
        } else {
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredSlots.length,
            separatorBuilder: (context, index) => const SizedBox(height: 4),
            itemBuilder: (context, index) => _buildCompactSlotCard(_filteredSlots[index]),
          );
        }
      },
    );
  }

  /// Build compact slot card for filtered results
  Widget _buildCompactSlotCard(Map<String, dynamic> slot) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    String slotId = '';
    String vehicleType = '';
    String primaryInfo = '';
    String secondaryInfo = '';
    List<Widget> detailChips = [];
    List<String> emails = [];

    if (_selectedSlotStatus == 'booked') {
      slotId = slot['slotId'] as String? ?? '';
      final bookingData = slot['bookingData'] as Map<String, dynamic>? ?? {};
      vehicleType = (bookingData['vehicleType'] as String? ?? 'BIKE').toUpperCase();
      primaryInfo = bookingData['userName'] as String? ?? 'Unknown User';
      secondaryInfo = bookingData['bookedBy'] as String? ?? 'Unknown';

      if (bookingData['bookedAt'] != null) {
        final bookedAt = DateFormat('MMM dd, HH:mm').format(
          (bookingData['bookedAt'] as Timestamp).toDate(),
        );
        detailChips.add(_buildDetailChip('Booked At', bookedAt, Icons.access_time));
      }
    } else {
      slotId = slot['slotId'] as String? ?? '';

      if (slot.containsKey('vehicleType')) {
        vehicleType = (slot['vehicleType'] as String? ?? 'BIKE').toUpperCase();
      } else if (slot.containsKey('slotData') && slot['slotData'] is Map) {
        final slotData = slot['slotData'] as Map<String, dynamic>;
        vehicleType = (slotData['vehicleType'] as String? ?? 'BIKE').toUpperCase();
      }

      if (slot.containsKey('slotData') && slot['slotData'] is Map) {
        final slotData = slot['slotData'] as Map<String, dynamic>;
        if (slotData.containsKey('alloted_to') && slotData['alloted_to'] is List) {
          final allotedTo = slotData['alloted_to'] as List;
          if (allotedTo.isNotEmpty) {
            for (var item in allotedTo) {
              if (item is Map<String, dynamic> && item.containsKey('email')) {
                emails.add(item['email'] as String);
              }
            }
          }
        }
      }

      if (slot.containsKey('slotPriority')) {
        secondaryInfo = (slot['slotPriority'] as String? ?? '').toUpperCase();
        if (secondaryInfo.isNotEmpty) {
          detailChips.add(_buildTextOnlyChip('Priority', secondaryInfo));
        }
      }
    }

    Color vehicleColor = vehicleType == 'CAR' ? const Color(0xFF3B82F6) : const Color(0xFF10B981);
    IconData vehicleIcon = vehicleType == 'CAR' ? Icons.directions_car : Icons.two_wheeler;

    return Card(
      margin: const EdgeInsets.all(2),
      elevation: isDark ? 3 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: isDark ? colorScheme.surface : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: vehicleColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: _selectedSlotStatus == 'booked' ? 12.0 : 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: vehicleColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      vehicleIcon,
                      color: vehicleColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Slot $slotId',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),

              if (primaryInfo.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surfaceVariant.withOpacity(0.3)
                        : const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedSlotStatus == 'booked' ? Icons.person : Icons.group,
                        size: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          primaryInfo,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (emails.isNotEmpty && _selectedSlotStatus != 'booked') ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.primaryContainer.withOpacity(0.1)
                        : colorScheme.primaryContainer.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colorScheme.primary.withOpacity(0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.email_outlined,
                            size: 10,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Alloted To:',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...emails.map((email) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Icon(
                              Icons.person_outline,
                              size: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                email,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w400,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ],
                  ),
                ),
              ],

              if (detailChips.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: detailChips,
                ),
              ],

              if (_selectedSlotStatus == 'booked' && secondaryInfo.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings,
                      size: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        'Booked by: $secondaryInfo',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build enhanced available slot card
  Widget _buildEnhancedAvailableSlotCard(Map<String, dynamic> slot, {bool isLargeScreen = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final slotId = slot['slotId'] as String? ?? '';
    final vehicleType = _extractVehicleType(slot);

    return FutureBuilder<Map<String, dynamic>?>(
      future: _getDetailedSlotInfo(slotId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingSlotCard(slotId, vehicleType);
        }

        final detailedSlot = snapshot.data ?? slot;
        return _buildDetailedAvailableSlotCard(detailedSlot, isLargeScreen: isLargeScreen);
      },
    );
  }

  /// Build detailed available slot card
  Widget _buildDetailedAvailableSlotCard(Map<String, dynamic> slot, {bool isLargeScreen = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final slotId = slot['slotId'] as String? ?? '';
    final vehicleType = _extractVehicleType(slot);
    final declarations = List<Map<String, dynamic>>.from(slot['declarations'] ?? []);
    final slotData = slot['slotData'] as Map<String, dynamic>?;
    final allotedUsers = List<Map<String, dynamic>>.from(slot['allotedUsers'] ?? []);
    final isFullyAvailable = slot['isFullyAvailable'] as bool? ?? false;

    final vehicleColor = vehicleType == 'CAR' ? const Color(0xFF3B82F6) : const Color(0xFF10B981);
    final vehicleIcon = vehicleType == 'CAR' ? Icons.directions_car : Icons.two_wheeler;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? colorScheme.surface : Colors.white,
      child: Container(
        padding: EdgeInsets.all(isLargeScreen ? 32 : 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFullyAvailable
                ? Colors.green.withOpacity(0.3)
                : Colors.orange.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: vehicleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    vehicleIcon,
                    color: vehicleColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slotId.toUpperCase(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${slotData?['slotPriority'] ?? 'permanent'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isFullyAvailable ? Colors.green[100] : Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFullyAvailable ? Colors.green[300]! : Colors.orange[300]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isFullyAvailable ? Icons.check_circle : Icons.access_time,
                        size: 14,
                        color: isFullyAvailable ? Colors.green[700] : Colors.orange[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isFullyAvailable ? 'Fully Available' : 'Partially Available',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isFullyAvailable ? Colors.green[700] : Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (allotedUsers.isNotEmpty) ...[
              Text(
                'Slot Users (${allotedUsers.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceVariant.withOpacity(0.3)
                      : const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? colorScheme.outline.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: allotedUsers.map((user) {
                    final userEmail = user['email'] as String? ?? '';
                    final userName = user['name'] as String? ?? _getUserNameFromEmail(userEmail);

                    final userDeclaration = declarations.firstWhere(
                          (d) => d['declaredBy'] == userEmail,
                      orElse: () => <String, dynamic>{},
                    );

                    final hasDeclaration = userDeclaration.isNotEmpty;
                    final reason = userDeclaration['reason'] as String?;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: hasDeclaration
                                  ? _getReasonColor(reason ?? 'unavailable')
                                  : Colors.grey[400],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName.isNotEmpty ? userName : userEmail.split('@').first,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                if (userName.isNotEmpty && userName != userEmail.split('@').first)
                                  Text(
                                    userEmail,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: hasDeclaration
                                  ? _getReasonColor(reason ?? 'unavailable').withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: hasDeclaration
                                    ? _getReasonColor(reason ?? 'unavailable').withOpacity(0.3)
                                    : Colors.grey.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              hasDeclaration
                                  ? _getReasonDisplayText(reason ?? 'unavailable')
                                  : 'Pending',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: hasDeclaration
                                    ? _getReasonColor(reason ?? 'unavailable')
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build loading slot card
  Widget _buildLoadingSlotCard(String slotId, String vehicleType) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final vehicleColor = vehicleType == 'CAR' ? const Color(0xFF3B82F6) : const Color(0xFF10B981);
    final vehicleIcon = vehicleType == 'CAR' ? Icons.directions_car : Icons.two_wheeler;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: vehicleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    vehicleIcon,
                    color: vehicleColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    slotId.toUpperCase(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build detail chip for slot information
  Widget _buildDetailChip(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.primaryContainer.withOpacity(0.3)
            : colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 8,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              '$label: $value',
              style: TextStyle(
                fontSize: 8,
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Build text-only chip for slot information
  Widget _buildTextOnlyChip(String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.primaryContainer.withOpacity(0.3)
            : colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 8,
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
