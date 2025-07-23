import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../viewModel/bookingBackend.dart';
import 'dart:async';
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
  List<Map<String, dynamic>> _bookings = [];
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



  // Optimized data loading with caching
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

    final bookingsCacheKey = _getCacheKey(targetDate, 'bookings');
    final slotsCacheKey = _getCacheKey(targetDate, 'slots');

    // Check cache first
    if (_isCacheValid(bookingsCacheKey) && _bookingsCache.containsKey(bookingsCacheKey)) {
      setState(() {
        _bookings = _bookingsCache[bookingsCacheKey]!;
        _selectedDateType = dateType;
      });
    } else {
      // Fetch from Firestore
      await _fetchBookingsFromFirestore(targetDate, bookingsCacheKey);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isLargeScreen = constraints.maxWidth > 800;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: EdgeInsets.all(isLargeScreen ? 24 : 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF6C5CE7), Color(0xFF74B9FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Date',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isLargeScreen ? 20 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: isLargeScreen ? 20 : 16),
                // Responsive button layout
                isLargeScreen
                    ? Row(
                  children: [
                    Expanded(
                      child: _buildDateButton('Today', 'today', Icons.today,
                          DateFormat('MMM dd').format(DateTime.now())),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDateButton('Tomorrow', 'tomorrow', Icons.calendar_month,
                          DateFormat('MMM dd').format(DateTime.now().add(const Duration(days: 1)))),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDateButton('Custom', 'custom', Icons.calendar_today,
                          DateFormat('MMM dd').format(_selectedDate)),
                    ),
                  ],
                )
                    : Row(
                  children: [
                    Expanded(
                      child: _buildDateButton('Today', 'today', Icons.today,
                          DateFormat('MMM dd').format(DateTime.now())),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDateButton('Tomorrow', 'tomorrow', Icons.calendar_month,
                          DateFormat('MMM dd').format(DateTime.now().add(const Duration(days: 1)))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDateButton('Custom', 'custom', Icons.calendar_today,
                          DateFormat('MMM dd').format(_selectedDate)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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



  Widget _buildBookingsList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final colorScheme = theme.colorScheme;

        bool isLargeScreen = constraints.maxWidth > 800;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: isDark ? colorScheme.surface : null, // Card color
          child: Container(
            padding: EdgeInsets.all(isLargeScreen ? 24 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.event_seat,
                      color: isDark
                          ? colorScheme.primary
                          : const Color(0xFF6C5CE7),
                      size: isLargeScreen ? 24 : 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bookings for ${_getDateTitle()}',
                        style: TextStyle(
                          fontSize: isLargeScreen ? 18 : 16,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? colorScheme.onSurface
                              : const Color(0xFF2D3748),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLargeScreen ? 14 : 12,
                        vertical: isLargeScreen ? 6 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? colorScheme.primary.withOpacity(0.16)
                            : const Color(0xFF6C5CE7).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_bookings.length} Bookings',
                        style: TextStyle(
                          color: isDark
                              ? colorScheme.primary
                              : const Color(0xFF6C5CE7),
                          fontSize: isLargeScreen ? 12 : 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isLargeScreen ? 20 : 16),

                if (_isLoading)
                  Container(
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark
                              ? colorScheme.primary
                              : const Color(0xFF6C5CE7),
                        ),
                      ),
                    ),
                  )
                else if (_bookings.isEmpty)
                  Container(
                    height: 200,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: isLargeScreen ? 64 : 48,
                          color: isDark
                              ? colorScheme.onSurface.withOpacity(0.4)
                              : const Color(0xFF718096).withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No bookings found for ${_getDateTitle().toLowerCase()}',
                          style: TextStyle(
                            color: isDark
                                ? colorScheme.onSurfaceVariant
                                : const Color(0xFF718096),
                            fontSize: isLargeScreen ? 16 : 14,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                // Responsive grid layout for large screens
                  (isLargeScreen
                      ? _buildGridLayout()
                      : _buildListLayout()),
              ],
            ),
          ),
        );
      },
    );
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





  Widget _buildAvailableSlotsList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isLargeScreen = constraints.maxWidth > 800;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;

        return Card(
          elevation: isDark ? 8 : 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: isDark ? colorScheme.surface : null,
          shadowColor: isDark ? Colors.black.withOpacity(0.3) : null,
          surfaceTintColor: isDark ? colorScheme.surfaceVariant : null,
          child: Container(
            padding: EdgeInsets.all(isLargeScreen ? 24 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_parking,
                      color: colorScheme.secondary,
                      size: isLargeScreen ? 24 : 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Available Slots for ${_getDateTitle()}',
                        style: TextStyle(
                          fontSize: isLargeScreen ? 18 : 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLargeScreen ? 14 : 12,
                        vertical: isLargeScreen ? 6 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_availableSlots.length} Available',
                        style: TextStyle(
                          color: colorScheme.secondary,
                          fontSize: isLargeScreen ? 12 : 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isLargeScreen ? 20 : 16),

                if (_isLoadingSlots)
                  Container(
                    height: 150,
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.secondary),
                      ),
                    ),
                  )
                else if (_availableSlots.isEmpty)
                  Container(
                    height: 150,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: isLargeScreen ? 64 : 48,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedDateType == 'today'
                              ? 'All slots are booked for today'
                              : 'Available slots only shown for today',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: isLargeScreen ? 16 : 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                // Responsive grid/list layout for available slots
                  isLargeScreen
                      ? _buildAvailableSlotsGrid()
                      : _buildAvailableSlotsListMin(),
              ],
            ),
          ),
        );
      },
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




// Update your _buildOverviewTab method to include the available slots widget
  Widget _buildOverviewTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isLargeScreen = constraints.maxWidth > 800;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateSelector(),
            SizedBox(height: isLargeScreen ? 24 : 20),
            _buildBookingsList(),
            SizedBox(height: isLargeScreen ? 24 : 20),
            _buildAvailableSlotsList(), // Add this line
          ],
        );
      },
    );
  }
}