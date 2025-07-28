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
  
  
  
    late TabController _tabController;
    DateTime _selectedDate = DateTime.now();
    String _selectedDateType = 'today';


    String? _selectedVehicleType; // 'CAR' or 'BIKE'
    String? _selectedSlotStatus; // 'booked', 'available', 'unbooked'
    List<Map<String, dynamic>> _filteredSlots = [];
    bool _isLoadingFilteredSlots = false;


  // With this:
    Map<String, dynamic> _slotStatistics = {};
  // Add these missing variables to your class:
    List<Map<String, dynamic>> _bookings = [];
    final Map<String, Map<String, dynamic>> _statisticsCache = {};
  
    List<Map<String, dynamic>> _availableSlots = [];
    bool _isLoading = true;
    bool _isLoadingSlots = false;
  
    // Cache management
    final Map<String, List<Map<String, dynamic>>> _bookingsCache = {};
    final Map<String, List<Map<String, dynamic>>> _slotsCache = {};
    final Map<String, DateTime> _cacheTimestamps = {};
    static const Duration _cacheExpiry = Duration(minutes: 5);
  
    // Debouncing for date selection
    Timer? _debounceTimer;
  
  
  
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
  
    // Optimized initial data loading
    Future<void> _loadInitialData() async {
      setState(() => _isLoading = true);
  
      try {
        // Load today's data by default
        await _loadDataForDate('today');
      } catch (e) {
        _showError('Error loading initial data: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  
    String _getCacheKey(DateTime date, String type) {
      return '${DateFormat('yyyy-MM-dd').format(date)}_$type';
    }
  
    // Check if cache is valid
    bool _isCacheValid(String key) {
      final timestamp = _cacheTimestamps[key];
      if (timestamp == null) return false;
      return DateTime.now().difference(timestamp) < _cacheExpiry;
    }
  
  
  
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
        // Fetch from Firestore
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

    Future<void> _fetchSlotStatisticsFromBackend(DateTime targetDate, String cacheKey) async {
      try {
        final bookingBackend = BookingBackend();

        // Use correct methods for each type
        final futures = await Future.wait([
          bookingBackend.getAvailableSlotsForToday(), // All slots
          bookingBackend.getBookingsForDate(targetDate), // Booked slots
          bookingBackend.getAvailableSlotsFromDeclarations(date: targetDate, vehicleTypeFilter: null), // Available slots (with declarations)
        ]);

        final allSlots = futures[0] as List<Map<String, dynamic>>;
        final bookedSlots = futures[1] as List<Map<String, dynamic>>;
        final availableSlots = futures[2] as List<Map<String, dynamic>>; // Available slots from declarations

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

        // ✅ ENHANCED DEBUG: Let's see the structure of availableSlots
        print('🔍 DEBUG Available slots data structure:');
        print('Available slots count: ${availableSlots.length}');
        if (availableSlots.isNotEmpty) {
          print('Sample available slot: ${availableSlots.first}');
          print('Keys in first slot: ${availableSlots.first.keys}');
        }

        // ✅ FIXED: Count available slots properly with enhanced error handling
        Set<String> availableSlotIds = {};
        for (var slot in availableSlots) {
          try {
            final slotId = slot['slotId'] as String;

            // ✅ TRY MULTIPLE POSSIBLE KEYS FOR VEHICLE TYPE
            String vehicleType = 'BIKE'; // Default

            if (slot.containsKey('vehicleType')) {
              vehicleType = (slot['vehicleType'] as String? ?? 'BIKE').toUpperCase();
            } else if (slot.containsKey('slotData') && slot['slotData'] is Map) {
              final slotData = slot['slotData'] as Map<String, dynamic>;
              if (slotData.containsKey('vehicleType')) {
                vehicleType = (slotData['vehicleType'] as String? ?? 'BIKE').toUpperCase();
              }
            }

            // ✅ Additional debug for each slot
            print('Processing available slot: $slotId, vehicleType: $vehicleType');

            availableSlotIds.add(slotId);
            if (vehicleType == 'CAR' || vehicleType == 'BIKE') {
              availableCounts[vehicleType] = (availableCounts[vehicleType] ?? 0) + 1;
              print('Incremented $vehicleType count to ${availableCounts[vehicleType]}');
            }
          } catch (e) {
            print('❌ Error processing available slot: $e');
            print('Slot data: $slot');
          }
        }

        // Calculate unbooked slots (not in BookedToday AND not in AvailableToday)
        final occupiedSlotIds = {...bookedSlotIds, ...availableSlotIds};
        final unbookedSlotIds = allSlotIds.difference(occupiedSlotIds);

        // Count unbooked by vehicle type
        for (var slot in allSlots) {
          final slotId = slot['slotId'] as String;
          if (unbookedSlotIds.contains(slotId)) {
            final vehicleType = (slot['vehicleType'] as String? ?? 'BIKE').toUpperCase();
            if (vehicleType == 'CAR' || vehicleType == 'BIKE') {
              unbookedCounts[vehicleType] = (unbookedCounts[vehicleType] ?? 0) + 1;
            }
          }
        }

        // ✅ ENHANCED DEBUG: Final counts
        print('🔍 FINAL DEBUG Statistics for ${DateFormat('yyyy-MM-dd').format(targetDate)}:');
        print('Booked slots count: $bookedCounts');
        print('Available slots raw count: ${availableSlots.length}');
        print('Available slots by vehicle FINAL: $availableCounts');
        print('Unbooked slots: $unbookedCounts');
        print('Available slot IDs: $availableSlotIds');

        final statistics = {
          'bookedSlots': bookedCounts,
          'availableSlots': availableCounts, // This should now show correct count
          'unbookedSlots': unbookedCounts,
          'date': DateFormat('yyyy-MM-dd').format(targetDate),
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        };

        // Update cache
        _statisticsCache[cacheKey] = statistics;
        _cacheTimestamps[cacheKey] = DateTime.now();

        setState(() => _slotStatistics = statistics);
      } catch (e) {
        print('❌ Error in _fetchSlotStatisticsFromBackend: $e');
        _showError('Error loading slot statistics: $e');
      }
    }


    void _onDateTypeChanged(String dateType) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _loadDataForDate(dateType);
      });
    }
  
  
  
  
    Future<void> _fetchBookingsFromFirestore(DateTime targetDate, String cacheKey) async {
      try {
        final bookings = await BookingBackend().getBookingsForDate(targetDate);
  
        // Update cache
        _bookingsCache[cacheKey] = bookings;
        _cacheTimestamps[cacheKey] = DateTime.now();
  
        setState(() => _bookings = bookings);
      } catch (e) {
        _showError('Error loading bookings: $e');
      }
    }

    // Separate method for fetching available slots
    Future<void> _fetchAvailableSlotsFromFirestore(String cacheKey) async {
      setState(() => _isLoadingSlots = true);

      try {
        final availableSlots = await BookingBackend().getAvailableSlotsForToday();

        // Update cache
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


  
    // Optimized date picker
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
  
    // Helper methods
    bool _isTodayDate(DateTime date) {
      final now = DateTime.now();
      return date.day == now.day &&
          date.month == now.month &&
          date.year == now.year;
    }
  
  
  
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
  
  
  
  
    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
  
      return Scaffold(
        backgroundColor: isDark
            ? theme.scaffoldBackgroundColor       // From your dark theme
            : const Color(0xFFF8F9FA),           // Your original light background
        appBar: AppBar(
          elevation: 0,
          backgroundColor: isDark
              ? theme.appBarTheme.backgroundColor // From your dark theme
              : Colors.white,                     // Your light
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



    Widget _buildDateButton(String title, String type, IconData icon, String date) {
      final isSelected = _selectedDateType == type;
  
      return GestureDetector(
        onTap: () async {
          if (type == 'custom') {
            await _selectDate();
          } else {
            setState(() => _selectedDateType = type);
            await _loadBookings();
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            bool isLargeScreen = constraints.maxWidth > 150;
  
            return Container(
              padding: EdgeInsets.all(isLargeScreen ? 16 : 12),
              // Remove fixed height - let content determine height
              constraints: BoxConstraints(
                minHeight: isLargeScreen ? 90 : 80,
              ),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min, // Important: minimize column size
                children: [
                  Icon(icon, color: Colors.white, size: isLargeScreen ? 24 : 20),
                  SizedBox(height: isLargeScreen ? 6 : 4), // Reduced spacing for smaller screens
                  Flexible( // Wrap text in Flexible to handle overflow
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isLargeScreen ? 13 : 11, // Slightly smaller font for small screens
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis, // Handle text overflow
                    ),
                  ),
                  SizedBox(height: isLargeScreen ? 2 : 1), // Reduced spacing
                  Flexible( // Wrap date text in Flexible
                    child: Text(
                      date,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: isLargeScreen ? 11 : 9, // Smaller font for small screens
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis, // Handle text overflow
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }




    Widget _buildSlotStatistics() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          final colorScheme = theme.colorScheme;
          bool isLargeScreen = constraints.maxWidth > 800;

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

    Widget _buildBeautifulVehicleRow(String vehicleType, Color primaryColor) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
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
            // Vehicle type with colored indicator
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

            // Stats in a clean row
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

            // Total count badge
          ],
        ),
      );
    }

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



    Widget _buildVehicleTypeStatistics(String vehicleType, IconData icon, Color color) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final colorScheme = theme.colorScheme;
  

      final booked = _slotStatistics['bookedSlots']?[vehicleType] ?? 0;
      final available = _slotStatistics['availableSlots']?[vehicleType] ?? 0;
      final unbooked = _slotStatistics['unbookedSlots']?[vehicleType] ?? 0;
  
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? colorScheme.outline.withOpacity(0.3) : const Color(0xFFE2E8F0),
          ),
          color: isDark ? colorScheme.surfaceVariant.withOpacity(0.1) : const Color(0xFFF7FAFC),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  '$vehicleType Slots',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),

              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildClickableStatCard('Booked', booked, Colors.red, Icons.event_busy, vehicleType)),
                const SizedBox(width: 12),
                Expanded(child: _buildClickableStatCard('Available', available, Colors.orange, Icons.event_available, vehicleType)),
                const SizedBox(width: 12),
                Expanded(child: _buildClickableStatCard('Unbooked', unbooked, Colors.grey, Icons.event_note, vehicleType)),
              ],
            ),
          ],
        ),
      );
    }


    Widget _buildClickableStatCard(String label, int count, Color color, IconData icon, String vehicleType) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final isSelected = _selectedVehicleType == vehicleType && _selectedSlotStatus == label.toLowerCase();

      return GestureDetector(
        onTap: () => _onStatCardTapped(label.toLowerCase(), vehicleType),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : color.withOpacity(0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    void _onStatCardTapped(String status, String vehicleType) {
      setState(() {
        if (_selectedVehicleType == vehicleType && _selectedSlotStatus == status) {
          // Deselect if same card is tapped
          _selectedVehicleType = null;
          _selectedSlotStatus = null;
          _filteredSlots = [];
        } else {
          // Select new card
          _selectedVehicleType = vehicleType;
          _selectedSlotStatus = status;
        }
      });

      if (_selectedVehicleType != null && _selectedSlotStatus != null) {
        _loadFilteredSlots();
      }
    }



    Future<void> _loadFilteredSlots() async {
      if (_selectedVehicleType == null || _selectedSlotStatus == null) return;

      setState(() => _isLoadingFilteredSlots = true);

      try {
        DateTime targetDate;
        switch (_selectedDateType) {
          case 'today':
            targetDate = DateTime.now();
            break;
          case 'tomorrow':
            targetDate = DateTime.now().add(const Duration(days: 1));
            break;
          default:
            targetDate = _selectedDate;
        }

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
          // ✅ FIXED: Use the correct method for available slots
            final availableSlots = await BookingBackend().getAvailableSlotsFromDeclarations(
              date: targetDate,
              vehicleTypeFilter: _selectedVehicleType,
            );
            slots = availableSlots;
            break;

          case 'unbooked':
          // You'll need to implement logic to get unbooked slots
          // This requires getting all slots and filtering out booked and available ones
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



    Widget _buildStatCard(String label, int count, Color color, IconData icon) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;

      return GestureDetector(
        onTap: () => _onStatCardTapped(label.toLowerCase(), _getCurrentVehicleTypeFromContext()),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    String _getCurrentVehicleTypeFromContext() {
      // This will be called from within _buildVehicleTypeStatistics context
      // We'll pass this as parameter in the updated method below
      return '';
    }
  
    Widget _buildGridLayout() {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.5,
        ),
        itemCount: _bookings.length,
        itemBuilder: (context, index) {
          final booking = _bookings[index];
          return _buildCompactBookingCard(booking);
        },
      );
    }
  
    Widget _buildListLayout() {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _bookings.length,
        itemBuilder: (context, index) {
          final booking = _bookings[index];
          return _buildBookingCard(booking);
        },
      );
    }

    Widget _buildCompactBookingCard(Map<String, dynamic> booking) {
      final bookingData = booking['bookingData'] as Map<String, dynamic>;
      final slotId = booking['slotId'] as String;
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
  
      return Card(
        elevation: isDark ? 8 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: isDark ? colorScheme.surface : null,
        shadowColor: isDark ? Colors.black.withOpacity(0.3) : null,
        surfaceTintColor: isDark ? colorScheme.surfaceVariant : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? colorScheme.outline.withOpacity(0.3)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.directions_car,
                      color: colorScheme.primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Slot $slotId',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          bookingData['vehicleType'] ?? 'Unknown Vehicle',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Booked',
                      style: TextStyle(
                        color: colorScheme.secondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildCompactDetailItem('User', bookingData['userName'] ?? 'Unknown'),
                  ),
                  Expanded(
                    child: _buildCompactDetailItem('Booked By', bookingData['bookedBy'] ?? 'Unknown'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (bookingData['bookedAt'] != null)
                _buildCompactDetailItem(
                  'Booked At',
                  DateFormat('MMM dd, HH:mm').format(
                    (bookingData['bookedAt'] as Timestamp).toDate(),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  
    Widget _buildCompactDetailItem(String label, String value) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
  
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
  
  
    Widget _buildBookingCard(Map<String, dynamic> booking) {
      final bookingData = booking['bookingData'] as Map<String, dynamic>;
      final slotId = booking['slotId'] as String;
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
  
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          backgroundColor: isDark
              ? colorScheme.surfaceVariant.withOpacity(0.3)
              : const Color(0xFFF7FAFC),
          collapsedBackgroundColor: isDark
              ? colorScheme.surface
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark
                  ? colorScheme.outline.withOpacity(0.3)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark
                  ? colorScheme.outline.withOpacity(0.3)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.directions_car,
              color: colorScheme.primary,
              size: 20,
            ),
          ),
          title: Text(
            'Slot $slotId',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            bookingData['vehicleType'] ?? 'Unknown Vehicle',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.secondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Booked',
              style: TextStyle(
                color: colorScheme.secondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.surfaceVariant.withOpacity(0.3)
                    : const Color(0xFFF7FAFC),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Booked By', bookingData['bookedBy'] ?? 'Unknown'),
                  _buildDetailRow('User Name', bookingData['userName'] ?? 'Unknown'),
                  _buildDetailRow('Vehicle Type', bookingData['vehicleType'] ?? 'Unknown'),
                  _buildDetailRow('Booking Date', bookingData['bookingDate'] ?? 'Unknown'),
                  if (bookingData['bookedAt'] != null)
                    _buildDetailRow(
                      'Booked At',
                      DateFormat('MMM dd, yyyy HH:mm').format(
                        (bookingData['bookedAt'] as Timestamp).toDate(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  
    Widget _buildDetailRow(String label, String value) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
  
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              ': ',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }
  
  
  
  
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
  
    void _showExportDialog() {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Booking Data'),
          content: const Text('Select date range to export booking data to Excel file.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Export functionality to be implemented')),
                );
              },
              child: const Text('Export'),
            ),
          ],
        ),
      );
    }
  
    // Add this to your _BookingDashboardState class variables:
  
  
  // Add this method to load available slots
    Future<void> _loadAvailableSlots() async {
      setState(() => _isLoadingSlots = true);
  
      try {
        DateTime targetDate;
        switch (_selectedDateType) {
          case 'today':
            targetDate = DateTime.now();
            break;
          case 'tomorrow':
            targetDate = DateTime.now().add(const Duration(days: 1));
            break;
          default:
            targetDate = _selectedDate;
        }
  
        // Only show available slots for today, for other dates show empty
        if (targetDate.day == DateTime.now().day &&
            targetDate.month == DateTime.now().month &&
            targetDate.year == DateTime.now().year) {
          final availableSlots = await BookingBackend().getAvailableSlotsForToday();
          setState(() {
            _availableSlots = availableSlots;
            _isLoadingSlots = false;
          });
        } else {
          setState(() {
            _availableSlots = [];
            _isLoadingSlots = false;
          });
        }
      } catch (e) {
        setState(() => _isLoadingSlots = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading available slots: $e')),
        );
      }
    }
  
  // Update your existing _loadBookings method to also load available slots
    Future<void> _loadBookings() async {
      setState(() => _isLoading = true);
  
      try {
        DateTime targetDate;
        switch (_selectedDateType) {
          case 'today':
            targetDate = DateTime.now();
            break;
          case 'tomorrow':
            targetDate = DateTime.now().add(const Duration(days: 1));
            break;
          default:
            targetDate = _selectedDate;
        }
  
        final bookings = await BookingBackend().getBookingsForDate(targetDate);
        setState(() {
          _bookings = bookings;
          _isLoading = false;
        });
  
        // Load available slots after bookings are loaded
        await _loadAvailableSlots();
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading bookings: $e')),
        );
      }
    }
  
  // Add this widget method for available slots





    Widget _buildFilteredSlotsList() {
      if (_selectedVehicleType == null || _selectedSlotStatus == null) {
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(24),
            height: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app, size: 64, color: Colors.grey.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text(
                  'Tap on any statistic card above to view related slots',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                  textAlign: TextAlign.center,
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
        color: isDark ? colorScheme.surface : null,
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [

                  Expanded(
                    child: Text(
                      '${_selectedSlotStatus?.toUpperCase()}  Slots - ${_getDateTitle()}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_filteredSlots.length} Found',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_isLoadingFilteredSlots)
                Container(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_filteredSlots.isEmpty)
                Container(
                  height: 150,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text(
                        'No ${_selectedSlotStatus} ${_selectedVehicleType?.toLowerCase()} slots found for ${_getDateTitle().toLowerCase()}',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                        textAlign: TextAlign.center,
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

    Widget _buildFilteredSlotsContent() {
      if (_selectedSlotStatus == 'booked') {
        // For booked slots, use the booking card since data structure matches
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _filteredSlots.length,
          itemBuilder: (context, index) => _buildBookingCard(_filteredSlots[index]),
        );
      } else {
        // For available and unbooked slots, use a generic slot card
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _filteredSlots.length,
          itemBuilder: (context, index) => _buildGenericSlotCard(_filteredSlots[index]),
        );
      }
    }


    Widget _buildGenericSlotCard(Map<String, dynamic> slot) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;

      // Extract common fields, handle different data structures
      String slotId = '';
      String vehicleType = '';
      String status = _selectedSlotStatus ?? 'unknown';
      List<dynamic>? allotedTo;
      String? slotPriority;

      // Handle different data structures
      if (slot.containsKey('slotId')) {
        slotId = slot['slotId'] as String? ?? '';
      }

      if (slot.containsKey('vehicleType')) {
        vehicleType = (slot['vehicleType'] as String? ?? 'BIKE').toUpperCase();
      }

      if (slot.containsKey('alloted_to')) {
        allotedTo = slot['alloted_to'] as List<dynamic>?;
      }

      if (slot.containsKey('slotPriority')) {
        slotPriority = slot['slotPriority'] as String?;
      }

      // Get status color
      Color statusColor;
      IconData statusIcon;
      switch (status) {
        case 'available':
          statusColor = Colors.orange;
          statusIcon = Icons.event_available;
          break;
        case 'unbooked':
          statusColor = Colors.grey;
          statusIcon = Icons.event_note;
          break;
        default:
          statusColor = Colors.blue;
          statusIcon = Icons.info;
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Card(
          elevation: isDark ? 4 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: isDark ? colorScheme.surface : null,
          shadowColor: isDark ? Colors.black.withOpacity(0.3) : null,
          surfaceTintColor: isDark ? colorScheme.surfaceVariant : null,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: statusColor.withOpacity(0.3),
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
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        vehicleType == 'CAR' ? Icons.directions_car : Icons.two_wheeler,
                        color: statusColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Slot $slotId',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            vehicleType.isEmpty ? 'Unknown Vehicle' : vehicleType,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 12, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Show priority if available
                if (slotPriority != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceVariant.withOpacity(0.3)
                          : const Color(0xFFF7FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.priority_high,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Priority: ${slotPriority!.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Show alloted users if available
                if (allotedTo != null && allotedTo!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceVariant.withOpacity(0.3)
                          : const Color(0xFFF7FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Alloted to: ${allotedTo!.join(', ')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Show additional slot data if available
                if (slot.containsKey('slotData')) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceVariant.withOpacity(0.3)
                          : const Color(0xFFF7FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Additional Information:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          slot['slotData'].toString(),
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

  // Grid layout for available slots (large screens)
    Widget _buildAvailableSlotsGrid() {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.2,
        ),
        itemCount: _availableSlots.length,
        itemBuilder: (context, index) {
          final slot = _availableSlots[index];
          return _buildCompactAvailableSlotCard(slot);
        },
      );
    }
  
  // List layout for available slots (mobile)
    Widget _buildAvailableSlotsListMin() {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _availableSlots.length,
        itemBuilder: (context, index) {
          final slot = _availableSlots[index];
          return _buildAvailableSlotCard(slot);
        },
      );
    }
  
  // Compact card for available slots (grid view)
    Widget _buildCompactAvailableSlotCard(Map<String, dynamic> slot) {
      final slotId = slot['slotId'] as String;
      final slotData = slot['slotData'] as Map<String, dynamic>;
      final vehicleType = slot['vehicleType'] as String;
      final slotPriority = slot['slotPriority'] as String;
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
  
      return Card(
        elevation: isDark ? 4 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: isDark ? colorScheme.surface : null,
        shadowColor: isDark ? Colors.black.withOpacity(0.3) : null,
        surfaceTintColor: isDark ? colorScheme.surfaceVariant : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.secondary.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colorScheme.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      vehicleType == 'CAR' ? Icons.directions_car : Icons.two_wheeler,
                      color: colorScheme.secondary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Slot $slotId',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          vehicleType,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: slotPriority == 'permanent'
                            ? colorScheme.primary.withOpacity(0.1)
                            : colorScheme.tertiary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        slotPriority.toUpperCase(),
                        style: TextStyle(
                          color: slotPriority == 'permanent'
                              ? colorScheme.primary
                              : colorScheme.tertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (slot['alloted_to'] != null && (slot['alloted_to'] as List).isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surfaceVariant.withOpacity(0.3)
                        : const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Alloted to: ${(slot['alloted_to'] as List).join(', ')}',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
            ],
          ),
        ),
      );
    }
  
  // Full card for available slots (list view)
    Widget _buildAvailableSlotCard(Map<String, dynamic> slot) {
      final slotId = slot['slotId'] as String;
      final slotData = slot['slotData'] as Map<String, dynamic>;
      final vehicleType = slot['vehicleType'] as String;
      final slotPriority = slot['slotPriority'] as String;
      final allotedTo = slot['alloted_to'] as List?;
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
  
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Card(
          elevation: isDark ? 4 : 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: isDark ? colorScheme.surface : null,
          shadowColor: isDark ? Colors.black.withOpacity(0.3) : null,
          surfaceTintColor: isDark ? colorScheme.surfaceVariant : null,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.secondary.withOpacity(0.3),
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
                        color: colorScheme.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        vehicleType == 'CAR' ? Icons.directions_car : Icons.two_wheeler,
                        color: colorScheme.secondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Slot $slotId',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            vehicleType,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: slotPriority == 'permanent'
                            ? colorScheme.primary.withOpacity(0.1)
                            : colorScheme.tertiary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        slotPriority.toUpperCase(),
                        style: TextStyle(
                          color: slotPriority == 'permanent'
                              ? colorScheme.primary
                              : colorScheme.tertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (allotedTo != null && allotedTo.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceVariant.withOpacity(0.3)
                          : const Color(0xFFF7FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Alloted to: ${allotedTo.join(', ')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }



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
              const  AnalyticsExportWidget(),
              // Changed from _buildAvailableSlotsList()
            ],
          );
        },
      );
    }



  }