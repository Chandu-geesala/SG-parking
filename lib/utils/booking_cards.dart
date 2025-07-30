import 'dart:async';

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';




import '../viewModel/bookingBackend.dart';


enum BookingStatus {
  available,
  booked,
  unavailable,
  past,
}



class BookingCards extends StatefulWidget {
  const BookingCards({Key? key}) : super(key: key);

  @override
  State<BookingCards> createState() => _BookingCardsState();
}

class _BookingCardsState extends State<BookingCards> {

  String? _selectedVehicleFilter;
  List<CarDimension> _carDimensions = [];
  bool _dimensionsLoaded = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;


  Future<Map<String, dynamic>?> _userSlotFuture = Future.value(null);

  final BookingBackend _backend = BookingBackend();
  bool _isLoadingTodayBooking = false;

  List<Map<String, dynamic>> _userVehicles = [];
  bool _isLoadingVehicles = false;

  Future<List<Map<String, dynamic>>>? _availableSlotsFuture; // For slots fetching


  String? _selectedDimensionFilter;


  Map<DateTime, Map<String, dynamic>> _weeklySlotData = {};
  bool _isLoadingWeeklyData = false;

  static const List<String> _dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const List<String> _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  // âœ… ADD these helper methods after the constants
  String _getDayName(DateTime date) => _dayNames[date.weekday];
  String _getMonthName(DateTime date) => _monthNames[date.month];

  // âœ… Helper method for formatted date string
  String _getFormattedDateString(DateTime date) {
    return '${_getDayName(date)}, ${_getMonthName(date)} ${date.day}';
  }

  // âœ… Helper method for full date string with year
  String _getFullDateString(DateTime date) {
    return '${_getMonthName(date)} ${date.day}, ${date.year}';
  }




  Map<DateTime, Map<String, dynamic>> _bookingStatuses = {};

  Set<DateTime> _unavailableDates = {};

  Map<DateTime, String> _datePreferences = {}; // 'use', 'leave', 'wfh'



  // Add these state variables after existing ones


  void _fetchSlots(DateTime date, String userVehicleType) {
    setState(() {
      _availableSlotsFuture = _backend.getAvailableSlotsWithUserDetails(
        date: date,
        vehicleTypeFilter: userVehicleType,
        dimensionFilter: _selectedDimensionFilter,
      );
    });
  }



  // Booking state variables
  Map<String, dynamic>? _todaysBooking;



  bool _isUpdatingPreferences = false;
  bool _isLoadingPreferences = false;
  Map<String, dynamic>? _cachedUserSlot;







  // Request state variables
  Map<String, dynamic>? _slotRequest;
  bool _isLoadingRequest = false;


  DateTime _getMondayOfWeek(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  List<DateTime> _getWorkingDaysOfWeek(DateTime date) {
    final monday = _getMondayOfWeek(date);
    return List.generate(5, (index) => monday.add(Duration(days: index)));
  }


  @override
  void initState() {
    super.initState();

    _loadUserVehicles();

    // Initialize with normalized today's date
    final today = DateTime.now();
    _selectedBookingDate = DateTime(today.year, today.month, today.day);

    _initializeDataUpdated();
    _loadPreferencesFromBackend();
  }




  Future<void> _initializeDataUpdated() async {
    // Initialize _userSlotFuture first
    setState(() {
      _userSlotFuture = fetchUserSlot();
    });

    // Wait for user slot data
    final userSlot = await _userSlotFuture;

    // Load all data in parallel
    await Future.wait([
      _loadBookings(),

      _loadPreferencesFromBackend(),
      _loadWeeklySlotData(), // âœ… NEW: Load weekly slot data
    ]);
  }





  void _showPreferenceOptions(DateTime date) {

    final currentPreference = _datePreferences[date];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getFormattedDateString(date),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        currentPreference != null ? 'Modify your selection' : 'Won\'t be using parking?',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Options (only 2 now)
            _buildPreferenceOption(
              date,
              'leave',
              'On Leave',
              'I will be on leave this day',
              Icons.beach_access,
              Colors.orange,
            ),
            const SizedBox(height: 12),
            _buildPreferenceOption(
              date,
              'wfh',
              'Work From Home',
              'I will be working from home',
              Icons.home_work,
              Colors.blue,
            ),

            if (currentPreference != null) ...[
              const SizedBox(height: 12),
              _buildRemoveOption(date),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }


  Widget _buildCombinedWeeklyParkingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).cardTheme.shadowColor ??
                (Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.1)),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Let us know when you won\'t need parking ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
                  ),
                ),
              ),

            ],

          ),
          const SizedBox(height: 20),

          // Weekly Calendar with combined functionality
          _buildCombinedWeeklyCalendar(),

          const SizedBox(height: 16),

          // Legend
          _buildCombinedLegend(),
        ],
      ),
    );
  }

  Widget _buildCombinedLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]!.withOpacity(0.5)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem(Icons.add_circle_outline, 'Available', Colors.blue[600]!),
          _buildLegendItem(Icons.check_circle, 'Booked', Colors.green[600]!),
          _buildLegendItem(Icons.block, 'Unavailable', Colors.red[600]!),
          _buildLegendItem(Icons.beach_access, 'Leave/WFH', Colors.orange[600]!),
        ],
      ),
    );
  }

  Widget _buildCombinedDayTile(DateTime date) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final isPast = date.isBefore(DateTime.now().subtract(const Duration(days: 1)));

    // Check user declaration first
    final hasUserDeclaration = _datePreferences.containsKey(date);

    // Get slot status
    final slotData = _weeklySlotData[date];
    final isSlotBooked = slotData?['isBooked'] == true;
    final isBookedByCurrentUser = slotData?['isBookedByCurrentUser'] == true;


    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: isPast ? null : () {
          _showCombinedOptionsSheet(date);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: _getCombinedDayTileColor(
                isToday,
                hasUserDeclaration,
                isSlotBooked,
                isBookedByCurrentUser,
                isPast
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _getCombinedDayTileBorderColor(
                  isToday,
                  hasUserDeclaration,
                  isSlotBooked,
                  isBookedByCurrentUser,
                  isPast
              ),
              width: isToday ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getDayName(date),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _getCombinedDayTileTextColor(
                      isToday,
                      hasUserDeclaration,
                      isSlotBooked,
                      isBookedByCurrentUser,
                      isPast
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _getCombinedDayTileTextColor(
                      isToday,
                      hasUserDeclaration,
                      isSlotBooked,
                      isBookedByCurrentUser,
                      isPast
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _getMonthName(date),
                style: TextStyle(
                  fontSize: 10,
                  color: _getCombinedDayTileTextColor(
                      isToday,
                      hasUserDeclaration,
                      isSlotBooked,
                      isBookedByCurrentUser,
                      isPast
                  ).withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 4),

              // Status icon
              _getCombinedStatusIcon(
                  hasUserDeclaration,
                  isSlotBooked,
                  isBookedByCurrentUser,
                  isPast,
                  date
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildCombinedWeeklyCalendar() {
    final workingDays = _getNextWorkingDays(5);

    return Column(
      children: [
        // Desktop/Tablet Layout - Single row for 5 working days
        if (MediaQuery.of(context).size.width > 600) ...[
          Row(
            children: workingDays.map((date) =>
                Expanded(child: _buildCombinedDayTile(date))
            ).toList(),
          ),
        ] else ...[
          // Mobile Layout - 2 rows (3 + 2)
          Column(
            children: [
              Row(
                children: workingDays.take(3).map((date) =>
                    Expanded(child: _buildCombinedDayTile(date))
                ).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ...workingDays.skip(3).map((date) =>
                      Expanded(child: _buildCombinedDayTile(date))
                  ).toList(),
                  // Fill remaining space to center the 2 items
                  if (workingDays.length > 3)
                    Expanded(child: Container()),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }


  void _showCombinedOptionsSheet(DateTime date) {
    // Check current status
    final hasUserDeclaration = _datePreferences.containsKey(date);
    final slotData = _weeklySlotData[date];
    final isSlotBooked = slotData?['isBooked'] == true;
    final isBookedByCurrentUser = slotData?['isBookedByCurrentUser'] == true;
    final bookedSlotId = slotData?['bookedSlotId'] as String?;
    final bookingType = slotData?['bookingType'] as String? ?? 'regular';

    // âœ… NEW: Check if assigned slot is booked by others
    final assignedSlotBookedByOther = slotData?['assignedSlotBookedByOther'] == true;

    // âœ… FIX: Determine slot availability status for UI logic
    final isSlotAvailable = !isSlotBooked; // Blue state - slot is available
    final isSlotUnavailable = assignedSlotBookedByOther; // Red state - slot booked by others

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getFormattedDateString(date),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        _getCombinedHeaderSubtitle(hasUserDeclaration, isSlotBooked, isBookedByCurrentUser, bookedSlotId, bookingType, assignedSlotBookedByOther),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Options based on current status
            if (hasUserDeclaration) ...[
              // User has declared unavailability
              _buildCurrentDeclarationCard(date),
              const SizedBox(height: 16),
              _buildRemoveDeclarationOption(date),
            ] else if (isBookedByCurrentUser) ...[
              // User has booked some slot
              _buildUserBookedAnySlotCard(date, bookedSlotId, bookingType),
              const SizedBox(height: 16),
              _buildCancelBookingOption(date),
              const SizedBox(height: 12),
              _buildViewBookingDetailsOption(date),
            ] else if (isSlotUnavailable) ...[
              // âœ… FIXED: User's assigned slot is booked by others (RED state)
              // Only show "See Available Slots" - no leave/WFH options
              _buildSlotBookedByOthersCard(date),
              const SizedBox(height: 16),
              _buildSeeAvailableSlotsOption(date),
            ] else if (isSlotAvailable) ...[
              // âœ… FIXED: Slot is available (BLUE state)
              // Show book slot and leave/WFH options - no "See Available Slots"
              _buildBookSlotOption(date),
              const SizedBox(height: 12),
              _buildPreferenceOption(date, 'leave', 'On Leave', 'I will be on leave this day', Icons.beach_access, Colors.orange),
              const SizedBox(height: 12),
              _buildPreferenceOption(date, 'wfh', 'Work From Home', 'I will be working from home', Icons.home_work, Colors.blue),
            ] else ...[
              // âœ… FALLBACK: Default case for any other state
              _buildBookSlotOption(date),
              const SizedBox(height: 12),
              _buildSeeAvailableSlotsOption(date),
              const SizedBox(height: 12),
              _buildPreferenceOption(date, 'leave', 'On Leave', 'I will be on leave this day', Icons.beach_access, Colors.orange),
              const SizedBox(width: 12),
              _buildPreferenceOption(date, 'wfh', 'Work From Home', 'I will be working from home', Icons.home_work, Colors.blue),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }



// âœ… UPDATED: Header subtitle method with unavailable status
  String _getCombinedHeaderSubtitle(bool hasDeclaration, bool isSlotBooked, bool isBookedByUser, String? bookedSlotId, String bookingType, bool assignedSlotBookedByOther) {
    if (hasDeclaration) return 'You have marked unavailability';
    if (isBookedByUser) {
      if (bookingType == 'alternative') {
        return 'You booked alternative slot ${bookedSlotId?.toUpperCase() ?? ''}';
      } else {
        return 'You have booked slot ${bookedSlotId?.toUpperCase() ?? ''}';
      }
    }
    if (assignedSlotBookedByOther) {
      return 'Your assigned slot is booked by another user';
    }
    return 'Available - Choose an option';
  }

// âœ… NEW: Method for any slot booking card
  Widget _buildUserBookedAnySlotCard(DateTime date, String? slotId, String bookingType) {
    final isAlternative = bookingType == 'alternative';
    final color = isAlternative ? Colors.purple[600]! : Colors.green[600]!;
    final bgColor = isAlternative ? Colors.purple[50]! : Colors.green[50]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isAlternative ? Icons.swap_horiz : Icons.check_circle,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAlternative ? 'Alternative Slot Booked' : 'Slot Booked by You',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (slotId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Slot ${slotId.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 14,
                      color: color.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

// âœ… NEW: View booking details option
  Widget _buildViewBookingDetailsOption(DateTime date) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _showMyBookedSlotDetails(date);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue[300]!, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.info_outline, color: Colors.blue[600], size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'View Booking Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'See complete booking information',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildRemoveDeclarationOption(DateTime date) {
    return InkWell(
      onTap: () async {
        Navigator.pop(context);
        await _removeUserDeclaration(date);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.delete_outline, color: Colors.grey[600], size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remove Marking',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Remove your unavailability Marking',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }


  Widget _buildCancelBookingOption(DateTime date) {
    return InkWell(
      onTap: () async {
        Navigator.pop(context);
        await _cancelBookingForDate(date);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red[300]!, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.cancel, color: Colors.red[600], size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cancel Booking',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.red[700],
                    ),
                  ),

                ],
              ),
            ),

          ],
        ),
      ),
    );
  }


  Future<void> _updateWeeklyCacheForDate(DateTime date, {
    required bool isBooked,
    required bool isBookedByCurrentUser,
    String? bookedSlotId,
    String? bookingType,
    bool? assignedSlotBookedByOther,
  }) async {
    setState(() {
      _weeklySlotData[date] = {
        'isBooked': isBooked,
        'isBookedByCurrentUser': isBookedByCurrentUser,
        'bookedSlotId': bookedSlotId,
        'bookingType': bookingType ?? 'regular',
        'assignedSlotBookedByOther': assignedSlotBookedByOther ?? false,
      };
    });
  }

  Future<void> _removeUserDeclaration(DateTime date) async {
    setState(() {
      _isUpdatingPreferences = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final result = await _backend.updateUserAvailabilityDeclaration(
          date: date,
          userEmail: user.email!,
          reason: null,
        );

        if (result['success']) {
          setState(() {
            _datePreferences.remove(date);
            _unavailableDates.remove(date);
          });

          // âœ… IMMEDIATE: Clear weekly cache for this date
          _weeklySlotData.remove(date);

          // âœ… REFRESH: Reload actual slot status
          await _loadSingleDateSlotStatus(date);

          _backend.showSnackBar(context, result['message']);
        } else {
          _backend.showSnackBar(context, result['message'], isError: true);
        }
      }
    } catch (e) {
      _backend.showSnackBar(context, 'Error removing declaration: $e', isError: true);
    } finally {
      setState(() {
        _isUpdatingPreferences = false;
      });
    }
  }

  Future<void> _quickRefreshWeeklyData() async {
    final user = FirebaseAuth.instance.currentUser;
    final userSlot = await _userSlotFuture;

    if (user?.email != null && userSlot != null) {
      final userEmail = user!.email!;
      final assignedSlotId = userSlot['slotId'] as String?;

      if (assignedSlotId == null) return;

      final workingDays = _getNextWorkingDays(5);

      try {
        // Quick parallel refresh for visible days only
        final futures = workingDays.map((date) async {
          try {
            final userBooking = await _backend.getUserBookedSlotForDate(
              userEmail: userEmail,
              date: date,
            );

            final assignedSlotStatus = await _backend.getBookingStatusForDate(
              slotId: assignedSlotId,
              userEmail: userEmail,
              date: date,
            );

            return MapEntry(date, {
              'userBooking': userBooking,
              'assignedSlotStatus': assignedSlotStatus,
            });
          } catch (e) {
            print('Error refreshing data for $date: $e');
            return MapEntry(date, {
              'userBooking': null,
              'assignedSlotStatus': <String, dynamic>{},
            });
          }
        });

        final results = await Future.wait(futures);

        if (mounted) {
          setState(() {
            for (final entry in results) {
              final date = entry.key;
              final data = entry.value as Map<String, dynamic>;
              final userBooking = data['userBooking'] as Map<String, dynamic>?;
              final assignedSlotStatus = data['assignedSlotStatus'] as Map<String, dynamic>? ?? {};

              bool isBooked = false;
              bool isBookedByCurrentUser = false;
              String? bookedSlotId;
              String bookingType = 'regular';

              if (userBooking != null) {
                isBooked = true;
                isBookedByCurrentUser = true;
                bookedSlotId = userBooking['slotId'] as String?;
                final bookingData = userBooking['bookingData'] as Map<String, dynamic>?;
                bookingType = bookingData?['bookingType'] as String? ?? 'regular';
              } else if (assignedSlotStatus['exists'] == true) {
                isBooked = true;
                isBookedByCurrentUser = false;
                bookedSlotId = assignedSlotId;
                bookingType = 'unavailable';
              }

              _weeklySlotData[date] = {
                'isBooked': isBooked,
                'isBookedByCurrentUser': isBookedByCurrentUser,
                'bookedSlotId': bookedSlotId,
                'bookingType': bookingType,
                'assignedSlotBookedByOther': assignedSlotStatus['exists'] == true && !isBookedByCurrentUser,
              };
            }
          });
        }
      } catch (e) {
        print('Error in _quickRefreshWeeklyData: $e');
      }
    }
  }

  Future<void> _loadSingleDateSlotStatus(DateTime date) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final userSlot = await _userSlotFuture;

      if (user != null && userSlot != null) {
        final slotId = userSlot['slotId'] as String;

        final result = await _backend.getBookingStatusForDate(
          slotId: slotId,
          userEmail: user.email!,
          date: date,
        );

        if (mounted) {
          setState(() {
            _weeklySlotData[date] = {
              'isBooked': result['exists'] == true,
              'isBookedByCurrentUser': result['isBookedByCurrentUser'] == true,
            };
          });
        }
      }
    } catch (e) {
      print('Error loading single date slot status: $e');
    }
  }


  Widget _buildUserBookedSlotCard(DateTime date) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[300]!, width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.check_circle, color: Colors.green[600], size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Slot Booked by You',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[700],
                  ),
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeeAvailableSlotsOption(DateTime date) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _showAvailableSlotsBottomSheet(date);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue[300]!, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.search, color: Colors.blue[600], size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'See Available Slots',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Find and request other available slots',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildSlotBookedByOthersCard(DateTime date) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[300]!, width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.block, color: Colors.red[600], size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Slot Booked by Others',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[700],
                  ),
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentDeclarationCard(DateTime date) {
    final preference = _datePreferences[date];
    String title = '';
    String subtitle = '';
    IconData icon = Icons.info_outline;
    Color color = Colors.grey[600]!;

    switch (preference) {
      case 'leave':
        title = 'You Marked Leave';
        icon = Icons.beach_access;
        color = Colors.orange[600]!;
        break;
      case 'wfh':
        title = 'You Marked Work From Home';
        icon = Icons.home_work;
        color = Colors.blue[600]!;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookSlotOption(DateTime date) {
    return InkWell(
      onTap: () async {
        Navigator.pop(context);
        await _bookSlotForDate(date);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[300]!, width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.event_available, color: Colors.green[600], size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Book Parking Slot',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Reserve your parking slot for this day',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildRemoveOption(DateTime date) {
    return InkWell(
// âœ… REPLACE the onTap in _buildRemoveOption with this:
      onTap: () async {
        final normalizedDate = DateTime(date.year, date.month, date.day);

        setState(() {
          _isUpdatingPreferences = true;
        });

        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final result = await _backend.updateUserAvailabilityDeclaration(
              date: normalizedDate,
              userEmail: user.email!,
              reason: null, // null means remove
            );

            if (result['success']) {
              setState(() {
                _datePreferences.remove(normalizedDate);
                _unavailableDates.remove(normalizedDate);
              });

              _backend.showSnackBar(context, result['message']);
            } else {
              _backend.showSnackBar(context, result['message'], isError: true);
            }
          }
        } catch (e) {
          _backend.showSnackBar(context, 'Error removing preference: $e', isError: true);
        } finally {
          setState(() {
            _isUpdatingPreferences = false;
          });
        }

        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.delete_outline, color: Colors.grey[600], size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Will Use Parking',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Remove selection and mark as available',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.remove_circle_outline, color: Colors.grey[600], size: 20),
          ],
        ),
      ),
    );
  }



  Widget _buildPreferenceOption(DateTime date, String value, String title, String subtitle, IconData icon, Color color) {
    final isSelected = _datePreferences[date] == value;

    return InkWell(
      onTap: () async {
        final normalizedDate = DateTime(date.year, date.month, date.day);

        // âœ… IMMEDIATELY update UI to show the selection
        setState(() {
          _isUpdatingPreferences = true;
          // Optimistically update the UI
          _datePreferences[normalizedDate] = value;
          _unavailableDates.add(normalizedDate);
        });

        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final result = await _backend.updateUserAvailabilityDeclaration(
              date: normalizedDate,
              userEmail: user.email!,
              reason: value, // 'leave' or 'wfh'
            );

            if (result['success']) {
              // Success - UI already updated optimistically
              _backend.showSnackBar(context, result['message']);
            } else {
              // Failed - revert the optimistic update
              setState(() {
                _datePreferences.remove(normalizedDate);
                _unavailableDates.remove(normalizedDate);
              });
              _backend.showSnackBar(context, result['message'], isError: true);
            }
          }
        } catch (e) {
          // Error - revert the optimistic update
          setState(() {
            _datePreferences.remove(normalizedDate);
            _unavailableDates.remove(normalizedDate);
          });
          _backend.showSnackBar(context, 'Error saving preference: $e', isError: true);
        } finally {
          setState(() {
            _isUpdatingPreferences = false;
          });
        }

        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? color : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 20),
          ],
        ),
      ),
    );
  }




// âœ… ADD this new method to load from backend
  Future<void> _loadPreferencesFromBackend() async {
    setState(() {
      _isLoadingPreferences = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final result = await _backend.getUserSlotAndAvailabilityData(user.email!);

        if (result['success']) {
          final declarations = result['declarations'] as Map<DateTime, String>;

          setState(() {
            _datePreferences.clear();
            _unavailableDates.clear();

            declarations.forEach((date, reason) {
              final normalizedDate = DateTime(date.year, date.month, date.day);
              _datePreferences[normalizedDate] = reason;
              _unavailableDates.add(normalizedDate);
            });
          });
        }
      }
    } catch (e) {
      print('âŒ Error loading preferences from backend: $e');
    } finally {
      setState(() {
        _isLoadingPreferences = false;
      });
    }
  }





  String getDisplayNameFromEmail(String email) {
    final usernamePart = email
        .split('@')
        .first;
    final words = usernamePart.split('.').map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1);
    }).toList();
    return words.join(' ');
  }


  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: refreshData,

      color: Theme.of(context).colorScheme.primary,
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _userSlotFuture,
        builder: (context, snapshot) {



          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final slotData = snapshot.data;

          if (slotData == null) {
            return _buildNoSlotAssignedCard();
          } else {
            return _buildSlotDashboard(slotData);
          }
        },
      ),
    );
  }

  Widget _buildSlotDashboard(Map<String, dynamic> slotData) {
    final slotId = slotData['slotId'] as String;
    final data = slotData['slotData'] as Map<String, dynamic>;
    final userInfo = slotData['userInfo'] as Map<String, dynamic>;

    final vehicleType = data['vehicleType'] as String? ?? 'UNKNOWN';
    final slotPriority = data['slotPriority'] as String? ?? 'unknown';
    final vehicleCompatibility = data['VehicleCompatibility'] as String?;
    final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSlotInfoCard(
              slotId, vehicleType, slotPriority, vehicleCompatibility),
          const SizedBox(height: 16),
          _buildCombinedWeeklyParkingCard(),

          // const SizedBox(height: 16),
          // _buildrulesCard(),

          const SizedBox(height: 16),
          _buildSlotUsersCard(allotedTo),
          const SizedBox(height: 16),
          _buildVehicleInfoCard(vehicleType),
          const SizedBox(height: 16),

          const SizedBox(height: 20),
        ],
      ),
    );
  }


  Widget _buildSlotInfoCard(String slotId, String vehicleType,
      String slotPriority, String? vehicleCompatibility) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).cardTheme.shadowColor ??
                (Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.1)),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getVehicleColor(vehicleType).withOpacity(
                      Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.1
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getVehicleIcon(vehicleType),
                  color: _getVehicleColor(vehicleType),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Assigned Slot',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      slotId.toUpperCase(),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _getPreferenceIcon(DateTime date) {
    final preference = _datePreferences[date];
    switch (preference) {
      case 'leave':
        return Icon(Icons.beach_access, size: 16, color: Colors.orange[600]);
      case 'wfh':
        return Icon(Icons.home_work, size: 16, color: Colors.blue[600]);
      default:
        return Icon(Icons.close_rounded, size: 16, color: Colors.red[600]);
    }
  }

  Color _getCombinedDayTileColor(bool isToday, bool hasDeclaration, bool isSlotBooked, bool isBookedByUser, bool isPast) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPast) {
      return isDark ? Colors.grey[800]! : Colors.grey[100]!;
    }
    if (hasDeclaration) {
      return isDark ? Colors.orange[900]!.withOpacity(0.3) : Colors.orange[50]!;
    }
    if (isSlotBooked) {
      if (isBookedByUser) {
        return isDark ? Colors.green[900]!.withOpacity(0.3) : Colors.green[50]!;
      } else {
        // âœ… FIX: Show red for unavailable (booked by others)
        return isDark ? Colors.red[900]!.withOpacity(0.3) : Colors.red[50]!;
      }
    }
    if (isToday) {
      return Theme.of(context).colorScheme.primary.withOpacity(isDark ? 0.3 : 0.1);
    }
    return isDark ? Colors.blue[900]!.withOpacity(0.2) : Colors.blue[50]!;
  }

  Color _getCombinedDayTileBorderColor(bool isToday, bool hasDeclaration, bool isSlotBooked, bool isBookedByUser, bool isPast) {
    if (isPast) return Colors.grey[400]!;
    if (hasDeclaration) return Colors.orange[600]!;
    if (isSlotBooked) {
      if (isBookedByUser) return Colors.green[600]!;
      // âœ… FIX: Show red border for unavailable
      return Colors.red[600]!;
    }
    if (isToday) return Theme.of(context).colorScheme.primary;
    return Colors.blue[600]!;
  }

  Color _getCombinedDayTileTextColor(bool isToday, bool hasDeclaration, bool isSlotBooked, bool isBookedByUser, bool isPast) {
    if (isPast) return Colors.grey[500]!;
    if (hasDeclaration) return Colors.orange[700]!;
    if (isSlotBooked) {
      if (isBookedByUser) return Colors.green[700]!;
      // âœ… FIX: Show red text for unavailable
      return Colors.red[700]!;
    }
    if (isToday) return Theme.of(context).colorScheme.primary;
    return Colors.blue[700]!;
  }

  Widget _getCombinedStatusIcon(bool hasDeclaration, bool isSlotBooked, bool isBookedByUser, bool isPast, DateTime date) {
    if (isPast) {
      return Icon(Icons.schedule_rounded, size: 14, color: Colors.grey[400]);
    }
    if (hasDeclaration) {
      return _getPreferenceIcon(date);
    }
    if (isSlotBooked) {
      if (isBookedByUser) {
        return Icon(Icons.check_circle, size: 16, color: Colors.green[600]);
      } else {
        // âœ… FIX: Show block icon for unavailable
        return Icon(Icons.block, size: 16, color: Colors.red[600]);
      }
    }
    return Icon(Icons.add_circle_outline, size: 14, color: Colors.blue[600]);
  }




  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }



// Add these state variables to your _BookingCardsState class
  DateTime _selectedBookingDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  bool _isLoadingBookingStatus = false;





  Widget _buildUserHasBookingCard(Map<String, dynamic> bookedSlot, DateTime date) {
    final slotId = bookedSlot['slotId'] as String;
    final bookingData = bookedSlot['bookingData'] as Map<String, dynamic>;
    final bookingType = bookingData['bookingType'] as String? ?? 'regular';
    final vehicleType = bookingData['vehicleType'] as String? ?? 'BIKE';

    final isAlternativeBooking = bookingType == 'alternative';
    final primaryColor = isAlternativeBooking ? Colors.purple[600]! : Colors.green[600]!;
    final backgroundColor = isAlternativeBooking ? Colors.purple[50]! : Colors.green[50]!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primaryColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Status Icon and Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isAlternativeBooking ? Icons.swap_horiz : Icons.check_circle,
                  color: primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAlternativeBooking ? 'Alternative Slot Booked' : 'Slot Booked',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Slot ${slotId.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Slot Details
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(_getVehicleIcon(vehicleType), size: 16, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  '${vehicleType.toUpperCase()} â€¢ ${_getFormattedDateString(date)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          if (isAlternativeBooking) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is an alternative slot booking. Original owners declared unavailability.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showMyBookedSlotDetails(date),
                  icon: Icon(Icons.info_outline, size: 18),
                  label: Text('View Details'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(color: primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _cancelBookingForDate(date),
                  icon: Icon(Icons.cancel, size: 18),
                  label: Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildUserDeclarationCard(DateTime date) {
    final preference = _datePreferences[date];
    String title = '';
    String subtitle = '';
    IconData icon = Icons.info_outline;
    Color primaryColor = Colors.grey[600]!;
    Color backgroundColor = Colors.grey[50]!;

    switch (preference) {
      case 'leave':
        title = 'You Marked Leave';
        icon = Icons.beach_access;
        primaryColor = Colors.orange[600]!;
        backgroundColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.orange[900]!.withOpacity(0.2)
            : Colors.orange[50]!;
        break;
      case 'wfh':
        title = 'You Marked Work From Home';
        icon = Icons.home_work;
        primaryColor = Colors.blue[600]!;
        backgroundColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.blue[900]!.withOpacity(0.2)
            : Colors.blue[50]!;
        break;
      default:
        title = 'You Marked Unavailable';
        icon = Icons.event_busy;
        primaryColor = Colors.grey[600]!;
        backgroundColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]!
            : Colors.grey[100]!;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primaryColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Status Icon and Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date Info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_getFormattedDateString(date)}, ${date.year}',
                  style: TextStyle(
                    fontSize: 14,
                    color: primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Info Message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]!.withOpacity(0.5)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No booking needed - your slot is available for others to request',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }




  Widget _buildLoadingBookingStatusCard() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Checking booking status...',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildErrorBookingStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!, width: 2),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.red[600], size: 32),
          const SizedBox(height: 8),
          Text(
            'Error Loading Status',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.red[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Please try again',
            style: TextStyle(
              fontSize: 14,
              color: Colors.red[600],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildBookingStatusCardContent(BookingStatus bookingStatus) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _getStatusBackgroundColor(bookingStatus),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getStatusBorderColor(bookingStatus),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: _getStatusBorderColor(bookingStatus).withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Status Icon and Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusBorderColor(bookingStatus).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getStatusIcon(bookingStatus),
                  color: _getStatusBorderColor(bookingStatus),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getStatusTitle(bookingStatus),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _getStatusBorderColor(bookingStatus),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getStatusSubtitle(bookingStatus),
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: _buildStatusActionButton(bookingStatus),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusActionButton(BookingStatus status) {
    switch (status) {
      case BookingStatus.available:
        return ElevatedButton.icon(
          onPressed: () => _bookSlotForDate(_selectedBookingDate),
          icon: Icon(Icons.event_available, size: 20),
          label: Text('Book This Slot'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[600],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 2,
          ),
        );
      case BookingStatus.booked:
        return ElevatedButton.icon(
          onPressed: () => _cancelBookingForDate(_selectedBookingDate),
          icon: Icon(Icons.cancel, size: 20),
          label: Text('Cancel Booking'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[600],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 2,
          ),
        );
      case BookingStatus.unavailable:
        return ElevatedButton.icon(
          onPressed: () => _showAvailableSlotsBottomSheet(_selectedBookingDate), // âœ… NEW
          icon: Icon(Icons.search, size: 20),
          label: Text('Request Available Slots'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 2,
          ),
        );
      case BookingStatus.past:
      default:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history, size: 20, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                'Past Date',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        );
    }
  }

  void _showAvailableSlotsBottomSheet(DateTime date) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return _AvailableSlotsBottomSheetContent(
              date: date,
              scrollController: scrollController,
              backend: _backend,
              getUserCarVehicles: _getUserCarVehicles,
              userSlotFuture: _userSlotFuture,
              // âœ… NEW: Pass actual methods as callbacks
              onBookAvailableSlot: _bookAvailableSlot,
              onShowMyBookedSlotDetails: _showMyBookedSlotDetails,
              onRefreshData: refreshData,
            );
          },
        );
      },
    );
  }




  List<Map<String, dynamic>> _getUserCarVehicles() {
    return _userVehicles.where((vehicle) =>
    vehicle['type']?.toString().toUpperCase() == 'CAR'
    ).toList();
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Finding available slots...',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading slots',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please try again later',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildEmptyState(DateTime date) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: Colors.orange[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Available Slots',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'All slots are currently occupied for this date',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                // You can add request admin functionality here
              },
              icon: Icon(Icons.support_agent),
              label: Text('Contact Admin'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(color: Theme.of(context).colorScheme.primary),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildAvailableSlotsList(List<Map<String, dynamic>> availableSlots, ScrollController scrollController, DateTime date) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
      itemCount: availableSlots.length,
      itemBuilder: (context, index) {
        final slot = availableSlots[index];
        return _buildAvailableSlotCard(slot, date); // âœ… Pass date parameter
      },
    );
  }

  Widget _buildAvailableSlotCard(Map<String, dynamic> slot, DateTime date){

    final slotId = slot['slotId'] as String;
    final vehicleType = slot['vehicleType'] as String;
    final slotUsers = slot['slotUsers'] as int;
    final declarationsCount = slot['declarationsCount'] as int;
    final declarations = List<Map<String, dynamic>>.from(slot['declarations'] ?? []);
    final slotData = slot['slotData'] as Map<String, dynamic>?;
    final allotedUsers = List<Map<String, dynamic>>.from(slot['allotedUsers'] ?? []);

    // âœ… NEW: Check availability status
    final isFullyAvailable = slot['isFullyAvailable'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFullyAvailable
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getVehicleColor(vehicleType).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getVehicleIcon(vehicleType),
                  color: _getVehicleColor(vehicleType),
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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '$vehicleType â€¢ ${slotData?['slotPriority'] ?? 'permanent'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // âœ… UPDATED: Availability status badge
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

          // âœ… UPDATED: Availability info with better messaging
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isFullyAvailable ? Colors.green : Colors.orange).withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isFullyAvailable ? Icons.verified_outlined : Icons.info_outline,
                  size: 16,
                  color: isFullyAvailable ? Colors.green[600] : Colors.orange[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isFullyAvailable
                        ? 'All $slotUsers users marked unavailability '
                        : '$declarationsCount of $slotUsers users marked unavailability',
                    style: TextStyle(
                      fontSize: 13,
                      color: isFullyAvailable ? Colors.green[700] : Colors.orange[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Declared users (collapsible)
          ExpansionTile(
            title: Text(
              'Slot Users ',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            childrenPadding: const EdgeInsets.only(top: 8),
            children: [
              // âœ… NEW: Show all users with their status
              ...allotedUsers.map((user) {
                final userEmail = user['email'] as String;
                final userName = user['name'] as String? ?? _getUserNameFromEmail(userEmail, allotedUsers);

                // Check if this user has declared
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
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: hasDeclaration
                              ? _getReasonColor(reason ?? 'unavailable')
                              : Colors.grey[400],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          userName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasDeclaration
                              ? _getReasonColor(reason ?? 'unavailable').withOpacity(0.1)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          hasDeclaration
                              ? _getReasonDisplayText(reason ?? 'unavailable')
                              : 'Pending',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
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
            ],
          ),

          const SizedBox(height: 16),

          // Action button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isFullyAvailable ? () async {
                // âœ… UPDATED: Implement booking logic for fully available slots
                Navigator.pop(context); // Close the bottom sheet
                await _bookAvailableSlot(slot, date); // âœ… Pass the date parameter
              } : null,
              icon: Icon(
                Icons.event_available,
                size: 18,
                color: isFullyAvailable ? Colors.white : Colors.grey[500],
              ),
              label: Text(
                'Book This Slot',
                style: TextStyle(
                  color: isFullyAvailable ? Colors.white : Colors.grey[500],
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isFullyAvailable
                    ? Colors.green[600]
                    : Colors.grey[300],
                foregroundColor: isFullyAvailable ? Colors.white : Colors.grey[500],
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: isFullyAvailable ? 2 : 0,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[500],
              ),
            ),
          ),


        ],
      ),
    );
  }


  Future<void> _bookAvailableSlot(Map<String, dynamic> slot, DateTime date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final slotId = slot['slotId'] as String;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Booking slot $slotId...'),
          ],
        ),
      ),
    );

    try {
      final result = await _backend.bookAvailableSlotForDate(
        targetSlotId: slotId,
        userEmail: user.email!,
        userName: user.displayName ?? _backend.getDisplayNameFromEmail(user.email!),
        date: date,
      );

      Navigator.pop(context); // Close loading dialog

      if (result['success']) {
        _backend.showSnackBar(context, result['message']);

        // âœ… IMMEDIATE: Update cache with alternative booking data
        await _updateWeeklyCacheForDate(
          date,
          isBooked: true,
          isBookedByCurrentUser: true,
          bookedSlotId: slotId,
          bookingType: 'alternative',
          assignedSlotBookedByOther: false,
        );

        // âœ… REFRESH: Complete data reload
        await refreshData();
      } else {
        final message = result['message'] as String;
        if (message.startsWith('already_booked_other:')) {
          await _showAlreadyBookedDialog(message, date);
        } else {
          _backend.showSnackBar(context, message, isError: true);
        }
      }
    } catch (e) {
      Navigator.pop(context);
      _backend.showSnackBar(context, 'Error booking slot: $e', isError: true);
    }
  }

  Future<void> _showAlreadyBookedDialog(String message, DateTime date) async {
    // Parse the message: "already_booked_other:slotId:userName"
    final parts = message.split(':');
    final bookedSlotId = parts.length > 1 ? parts[1] : 'Unknown';
    final bookedUserName = parts.length > 2 ? parts[2] : 'You';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange[600]),
            const SizedBox(width: 12),
            const Text('Already Booked'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have already booked another slot for ${_getFormattedDateString(date)}:',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_parking, color: Colors.blue[600]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Slot ${bookedSlotId.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Booked by: $bookedUserName',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Date: ${_getFormattedDateString(date)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You can only book one slot per day. Cancel your current booking to book a different slot.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showMyBookedSlotDetails(date);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('View My Booking'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMyBookedSlotDetails(DateTime date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your booking details...'),
          ],
        ),
      ),
    );

    try {
      final bookedSlotDetails = await _backend.getUserBookedSlotForDate(
        userEmail: user.email!,
        date: date,
      );

      if (bookedSlotDetails != null) {
        // Close loading dialog BEFORE showing new dialog
        Navigator.pop(context);

        // Fetch slot document to get remarks (if any)
        final slotId = bookedSlotDetails['slotId'] as String;
        final slotDoc = await FirebaseFirestore.instance
            .collection('Slots') // <-- Change collection name if needed
            .doc(slotId)
            .get();
        final slotRemarks = slotDoc.data()?['remarks'] as String?;

        _showBookedSlotDetailsDialog(bookedSlotDetails, slotRemarks, date);

      } else {
        Navigator.pop(context);
        _backend.showSnackBar(context, 'No booking found for this date', isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      _backend.showSnackBar(context, 'Error loading booking details: $e', isError: true);
    }
  }




  void _showBookedSlotDetailsDialog(
      Map<String, dynamic> bookedSlotDetails,
      String? slotRemarks,
      DateTime date,
      ) {


    final slotId = bookedSlotDetails['slotId'] as String;
    final bookingData = bookedSlotDetails['bookingData'] as Map<String, dynamic>;


    final userName = bookingData['userName'] as String? ?? 'Unknown';
    final vehicleType = bookingData['vehicleType'] as String? ?? 'Unknown';
    final bookingType = bookingData['bookingType'] as String? ?? 'regular';
    final bookedAt = bookingData['bookedAt'];



    String bookingTimeStr = 'Unknown';
    if (bookedAt != null && bookedAt is Timestamp) {
      bookingTimeStr = DateFormat('MMM dd, yyyy - hh:mm a').format(bookedAt.toDate());
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(8),
              ),
            ),

            const Text('Your Booking Details'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slot ID
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Slot ${slotId.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.green[600]),
                      const SizedBox(width: 6),
                      Text(
                        _getFormattedDateString(date),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),


            _buildDetailRow('Booking Type', bookingType == 'alternative' ? 'Alternative Slot' : 'Regular Slot',
                bookingType == 'alternative' ? Icons.swap_horiz : Icons.event_available),

            if (slotRemarks?.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              _buildDetailRow('Slot Remarks', slotRemarks!, Icons.note),
            ],



          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelBookingForDate(date);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
  }


  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }




  String _getUserNameFromEmail(String email, List<Map<String, dynamic>> allotedUsers) {
    try {
      final user = allotedUsers.firstWhere((user) => user['email'] == email);
      return user['name'] ?? _backend.getDisplayNameFromEmail(email);
    } catch (e) {
      return _backend.getDisplayNameFromEmail(email);
    }
  }

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

  List<DateTime> _getNextWorkingDays(int count) {
    final today = DateTime.now();
    final workingDays = <DateTime>[];
    int dayOffset = 0;

    while (workingDays.length < count && dayOffset < 14) {
      final date = today.add(Duration(days: dayOffset));
      if (date.weekday >= DateTime.monday && date.weekday <= DateTime.friday) {
        final normalizedDate = DateTime(date.year, date.month, date.day);
        workingDays.add(normalizedDate);
      }
      dayOffset++;
    }

    return workingDays;
  }

  Future<BookingStatus> _getBookingStatusForDate(DateTime date) async {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedDate = DateTime(date.year, date.month, date.day);

    // Check if it's a past date
    if (normalizedDate.isBefore(normalizedToday)) {
      return BookingStatus.past;
    }

    // Get the cached status or fetch from backend
    if (!_bookingStatuses.containsKey(normalizedDate)) {
      await _loadBookingStatusForDate(normalizedDate);
    }

    final status = _bookingStatuses[normalizedDate];
    if (status == null) return BookingStatus.available;

    if (status['exists'] == true) {
      if (status['isBookedByCurrentUser'] == true) {
        return BookingStatus.booked;
      } else {
        return BookingStatus.unavailable;
      }
    }

    return BookingStatus.available;
  }

  Color _getStatusBackgroundColor(BookingStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (status) {
      case BookingStatus.available:
      // Changed to BLUE for available slots
        return isDark ? Colors.blue[900]!.withOpacity(0.2) : Colors.blue[50]!;
      case BookingStatus.booked:
      // Changed to GREEN for booked slots
        return isDark ? Colors.green[900]!.withOpacity(0.2) : Colors.green[50]!;
      case BookingStatus.unavailable:
        return isDark ? Colors.red[900]!.withOpacity(0.2) : Colors.red[50]!;
      case BookingStatus.past:
        return isDark ? Colors.grey[800]! : Colors.grey[100]!;
    }
  }

  Color _getStatusBorderColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.available:
      // Changed to BLUE for available slots
        return Colors.blue[600]!;
      case BookingStatus.booked:
      // Changed to GREEN for booked slots
        return Colors.green[600]!;
      case BookingStatus.unavailable:
        return Colors.red[600]!;
      case BookingStatus.past:
        return Colors.grey[400]!;
    }
  }


  IconData _getStatusIcon(BookingStatus status) {
    switch (status) {
      case BookingStatus.available:
        return Icons.event_available;
      case BookingStatus.booked:
        return Icons.check_circle_outline;
      case BookingStatus.unavailable:
        return Icons.block;
      case BookingStatus.past:
        return Icons.history;
    }
  }

  String _getStatusTitle(BookingStatus status) {
    switch (status) {
      case BookingStatus.available:
        return 'Slot Available';
      case BookingStatus.booked:
        return 'Slot Booked';
      case BookingStatus.unavailable:
        return 'Slot Not Available';
      case BookingStatus.past:
        return 'Past Date';
    }
  }

  String _getStatusSubtitle(BookingStatus status) {
    switch (status) {
      case BookingStatus.available:
        return 'Your parking slot is available for this date';
      case BookingStatus.booked:
        return 'You have  booked this slot';
      case BookingStatus.unavailable:
        return 'Slot is booked by another user';
      case BookingStatus.past:
        return 'Cannot book slots for past dates';
    }
  }

  Future<void> _loadBookingStatusForDate(DateTime date) async {
    if (!mounted) return;

    setState(() {
      _isLoadingBookingStatus = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final userSlot = await _userSlotFuture;

      if (user != null && userSlot != null) {
        final slotId = userSlot['slotId'] as String;

        // âœ… Use your backend method to get booking status
        final result = await _backend.getBookingStatusForDate(
          slotId: slotId,
          userEmail: user.email!,
          date: date,
        );

        setState(() {
          _bookingStatuses[date] = result;
        });
      }
    } catch (e) {
      print('Error loading booking status for date: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBookingStatus = false;
        });
      }
    }
  }

  Future<void> _cancelBookingForDate(DateTime date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingBookingStatus = true;
    });

    try {
      // Get the actual booked slot details
      final bookedSlotDetails = await _backend.getUserBookedSlotForDate(
        userEmail: user.email!,
        date: date,
      );

      if (bookedSlotDetails == null) {
        _backend.showSnackBar(context, 'No booking found for this date', isError: true);
        return;
      }

      final actualBookedSlotId = bookedSlotDetails['slotId'] as String;

      final result = await _backend.cancelBookingForDate(
        slotId: actualBookedSlotId,
        userEmail: user.email!,
        date: date,
      );

      if (result['success']) {
        _backend.showSnackBar(context, result['message']);

        // âœ… IMMEDIATE: Clear weekly cache completely for this date
        await _updateWeeklyCacheForDate(
          date,
          isBooked: false,
          isBookedByCurrentUser: false,
          bookedSlotId: null,
          bookingType: 'regular',
          assignedSlotBookedByOther: false,
        );

        // âœ… REFRESH: Reload actual status to check if assigned slot is booked by others
        await _loadSingleDateSlotStatus(date);
        _loadBookingStatusForDate(date);
      } else {
        _backend.showSnackBar(context, result['message'], isError: true);
      }
    } catch (e) {
      _backend.showSnackBar(context, 'Error cancelling booking: $e', isError: true);
    } finally {
      setState(() {
        _isLoadingBookingStatus = false;
      });
    }
  }


  Widget _buildNoSlotAssignedCard() {
    if (_isLoadingRequest) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_slotRequest != null) {
      final status = _slotRequest!['status'] ?? 'pending';
      final timestamp = _slotRequest!['timestamp'];
      String dateStr = '';
      if (timestamp is Timestamp) {
        dateStr =
            DateFormat('MMM dd, yyyy - hh:mm a').format(timestamp.toDate());
      }

      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.hourglass_top_rounded,
                size: 48,
                color: status == 'approved'
                    ? Colors.green
                    : status == 'rejected'
                    ? Colors.red
                    : Colors.blue[600],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              status == 'approved'
                  ? 'Slot Request Approved'
                  : status == 'rejected'
                  ? 'Slot Request Rejected'
                  : 'Slot Request Pending',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: status == 'approved'
                    ? Colors.green[800]
                    : status == 'rejected'
                    ? Colors.red[800]
                    : Colors.blue[900],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your request to admin is currently "$status".\n${dateStr
                  .isNotEmpty ? 'Submitted: $dateStr' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
            if (status == 'rejected') ...[
              const SizedBox(height: 16),
              Text(
                'You may contact admin for further info.',
                style: TextStyle(
                  color: Colors.red[400],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              size: 48,
              color: Colors.orange[600],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Parking Slot Assigned',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You are not currently assigned to any parking slot.\nPlease contact the admin for slot allocation.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await requestSlotAllocation();
              },
              icon: const Icon(Icons.contact_support_rounded),
              label: const Text("Contact Admin"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // Widget _buildrulesCard() {
  //   final isDark = Theme.of(context).brightness == Brightness.dark;
  //
  //   return Container(
  //     decoration: BoxDecoration(
  //       borderRadius: BorderRadius.circular(16),
  //       gradient: LinearGradient(
  //         colors: isDark
  //             ? [
  //           Theme.of(context).colorScheme.primary.withOpacity(0.2),
  //           Theme.of(context).colorScheme.primary.withOpacity(0.1),
  //         ]
  //             : [
  //           Colors.indigo.withOpacity(0.1),
  //           Colors.indigo.withOpacity(0.05),
  //         ],
  //         begin: Alignment.topLeft,
  //         end: Alignment.bottomRight,
  //       ),
  //       boxShadow: [
  //         BoxShadow(
  //           color: isDark
  //               ? Colors.black.withOpacity(0.3)
  //               : Colors.black.withOpacity(0.04),
  //           blurRadius: 8,
  //           offset: const Offset(0, 2),
  //         ),
  //       ],
  //     ),
  //     padding: const EdgeInsets.all(16),
  //     child: Row(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Container(
  //           padding: const EdgeInsets.all(10),
  //           decoration: BoxDecoration(
  //             color: isDark
  //                 ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
  //                 : Colors.indigo.withOpacity(0.15),
  //             shape: BoxShape.circle,
  //           ),
  //           child: Icon(
  //               Icons.info_outline_rounded,
  //               color: isDark
  //                   ? Theme.of(context).colorScheme.primary
  //                   : Colors.indigo,
  //               size: 24
  //           ),
  //         ),
  //         const SizedBox(width: 16),
  //         Expanded(
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               Text(
  //                 "Booking Guidelines",
  //                 style: TextStyle(
  //                   fontSize: 16,
  //                   fontWeight: FontWeight.bold,
  //                   color: isDark
  //                       ? Theme.of(context).colorScheme.primary
  //                       : Colors.indigo[800],
  //                 ),
  //               ),
  //               const SizedBox(height: 8),
  //               Text(
  //                 "â€¢ Eat 5 star Do Nothing ðŸ˜Ž \n",
  //
  //                 style: TextStyle(
  //                   fontSize: 13,
  //                   height: 1.5,
  //                   color: isDark
  //                       ? Theme.of(context).colorScheme.primary.withOpacity(0.8)
  //                       : Colors.indigo[600]!.withOpacity(0.85),
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }



  Widget _buildInfoTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _bookSlotForDate(DateTime date) async {
    final user = FirebaseAuth.instance.currentUser;
    final userSlot = await _userSlotFuture;

    if (user == null || userSlot == null) return;

    final slotId = userSlot['slotId'] as String;
    final isToday = DateUtils.isSameDay(date, DateTime.now());

    setState(() {
      if (isToday) {
        _isLoadingTodayBooking = true;
      } else {
        _isLoadingBookingStatus = true;
      }
    });

    try {
      final slotData = userSlot['slotData'] as Map<String, dynamic>;
      final vehicleType = slotData['vehicleType'] as String? ?? 'BIKE';

      final result = await _backend.bookSlotForDate(
        slotId: slotId,
        vehicleType: vehicleType,
        userEmail: user.email!,
        userName: user.displayName ?? _backend.getDisplayNameFromEmail(user.email!),
        date: date,
      );

      if (result['success']) {
        _backend.showSnackBar(context, result['message']);

        // âœ… IMMEDIATE: Update weekly cache with complete data
        await _updateWeeklyCacheForDate(
          date,
          isBooked: true,
          isBookedByCurrentUser: true,
          bookedSlotId: slotId,
          bookingType: 'regular',
          assignedSlotBookedByOther: false,
        );

        // âœ… REFRESH: Update other data sources
        if (isToday) {
          await _refreshTodayOnly();
        } else {
          _loadBookingStatusForDate(date);
        }
      } else {
        _backend.showSnackBar(context, result['message'], isError: true);
      }
    } catch (e) {
      _backend.showSnackBar(context, 'Error booking slot: $e', isError: true);
    } finally {
      setState(() {
        if (isToday) {
          _isLoadingTodayBooking = false;
        } else {
          _isLoadingBookingStatus = false;
        }
      });
    }
  }



  Widget _buildSlotUsersCard(List<dynamic> allotedTo) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).cardTheme.shadowColor ??
                (Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.1)),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  Icons.group_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24
              ),
              const SizedBox(width: 12),
              Text(
                'Slot Users (${allotedTo.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ) ?? TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...allotedTo.map((user) => _buildUserTile(user as Map<String, dynamic>)).toList(),
        ],
      ),
    );
  }



  Future<Map<String, dynamic>?> fetchUserSlot() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final userEmail = user.email!;

      // Get user's assigned slot using the backend instance
      final userSlot = await _backend.getUserAssignedSlot(userEmail);
      if (userSlot == null) return null;

      final slotId = userSlot['slotId'] as String;
      final slotData = userSlot['slotData'] as Map<String, dynamic>;

      // Extract dimension from slot data
      final dimension = slotData['dimension'] as String?;

      // Get additional dimension details if needed
      String? dimensionDetails;
      if (dimension != null) {
        dimensionDetails = await _getDimensionDetails(dimension);
      }

      return {
        'slotId': slotId,
        'slotData': slotData,
        'dimension': dimension,
        'dimensionDetails': dimensionDetails,
        'userInfo': {
          'email': userEmail,
          'name': user.displayName ?? _backend.getDisplayNameFromEmail(userEmail),
        },
      };
    } catch (e) {
      print('Error fetching user slot: $e');
      return null;
    }
  }




// Add this helper method to get dimension details from dimensions collection
  Future<String?> _getDimensionDetails(String dimensionId) async {
    try {
      final doc = await _firestore
          .collection('dimensions')
          .doc(dimensionId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        // Return dimension description or any relevant info
        return data['description'] as String? ?? data['name'] as String?;
      }
      return null;
    } catch (e) {
      print('Error fetching dimension details: $e');
      return null;
    }
  }




  Future<void> _loadBookings() async {
    if (!mounted) return;

    setState(() {
      // âœ… For initial loading of both, you can use either variable or create a separate one
      _isLoadingTodayBooking = true;

    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userSlot = await _userSlotFuture;
        String? userAssignedSlotId;
        if (userSlot != null) {
          userAssignedSlotId = userSlot['slotId'] as String;
        }

        if (userAssignedSlotId != null) {
          final bookingResults = await _checkBothBookingsOptimized(userAssignedSlotId, user.email!);

          if (mounted) {
            setState(() {
              _todaysBooking = bookingResults['today'];

              _isLoadingTodayBooking = false;

            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTodayBooking = false;

        });
        print('Error loading bookings: $e');
      }
    }
  }




  Future<Map<String, Map<String, dynamic>?>> _checkBothBookingsOptimized(
      String slotId, String userEmail) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());


      // Parallel reads instead of sequential
      final futures = await Future.wait([
        FirebaseFirestore.instance
            .collection('Bookings')
            .doc(today)
            .collection('BookedToday')
            .doc(slotId)
            .get(),

      ]);

      return {
        'today': _processBookingSnapshot(futures[0], slotId, userEmail),

      };
    } catch (e) {
      print('Error checking bookings: $e');
      return {'today': null, 'tomorrow': null};
    }
  }

  Map<String, dynamic>? _processBookingSnapshot(
      DocumentSnapshot snapshot, String slotId, String userEmail) {
    if (snapshot.exists) {
      final data = snapshot.data()! as Map<String, dynamic>;
      return {
        'slotId': slotId,
        'bookingData': data,
        'isBookedByCurrentUser': data['bookedBy'] == userEmail,
        'bookedBy': data['bookedBy'],
        'exists': true,
      };
    }
    return {
      'slotId': slotId,
      'exists': false,
      'isBookedByCurrentUser': false,
    };
  }

  Future<void> _loadWeeklySlotData() async {
    if (!mounted) return;

    setState(() {
      _isLoadingWeeklyData = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final userSlot = await _userSlotFuture;

      if (user != null && userSlot != null) {
        final userEmail = user.email!;
        final assignedSlotId = userSlot['slotId'] as String;
        final workingDays = _getNextWorkingDays(5);
        final Map<DateTime, Map<String, dynamic>> weeklyData = {};

        // âœ… FIX: Check both user's bookings AND assigned slot status
        final futures = workingDays.map((date) async {
          // Check if user has booked any slot
          final userBooking = await _backend.getUserBookedSlotForDate(
            userEmail: userEmail,
            date: date,
          );

          // âœ… NEW: Also check if user's assigned slot is booked by others
          final assignedSlotStatus = await _backend.getBookingStatusForDate(
            slotId: assignedSlotId,
            userEmail: userEmail,
            date: date,
          );

          // Determine the final status
          bool isBooked = false;
          bool isBookedByCurrentUser = false;
          String? bookedSlotId;
          String bookingType = 'regular';

          if (userBooking != null) {
            // User has booked some slot (either their own or alternative)
            isBooked = true;
            isBookedByCurrentUser = true;
            bookedSlotId = userBooking['slotId'];
            bookingType = userBooking['bookingData']?['bookingType'] ?? 'regular';
          } else if (assignedSlotStatus['exists'] == true) {
            // User's assigned slot is booked by someone else
            isBooked = true;
            isBookedByCurrentUser = false;
            bookedSlotId = assignedSlotId;
            bookingType = 'unavailable'; // Mark as unavailable
          }

          return MapEntry(date, {
            'isBooked': isBooked,
            'isBookedByCurrentUser': isBookedByCurrentUser,
            'bookedSlotId': bookedSlotId,
            'bookingType': bookingType,
            'assignedSlotBookedByOther': assignedSlotStatus['exists'] == true && !isBookedByCurrentUser,
          });
        });

        final results = await Future.wait(futures);

        for (final entry in results) {
          weeklyData[entry.key] = entry.value;
        }

        if (mounted) {
          setState(() {
            _weeklySlotData = weeklyData;
          });
        }
      }
    } catch (e) {
      print('Error loading weekly slot data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWeeklyData = false;
        });
      }
    }
  }


// ADD this helper method:
  bool _isSameWeek(DateTime date1, DateTime date2) {
    final monday1 = _getMondayOfWeek(date1);
    final monday2 = _getMondayOfWeek(date2);
    return monday1.year == monday2.year &&
        monday1.month == monday2.month &&
        monday1.day == monday2.day;
  }


  Future<void> _refreshTodayOnly() async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userSlot = await _userSlotFuture;
      if (userSlot != null) {
        final slotId = userSlot['slotId'] as String;

        // Only refresh today's booking
        final todayBooking = await _checkSingleBooking(slotId, user.email!, true);

        if (mounted) {
          setState(() {
            _todaysBooking = todayBooking;
          });
        }
      }
    }
  }


  Future<Map<String, dynamic>?> _checkSingleBooking(String slotId, String userEmail, bool isToday) async {
    try {
      final dateStr = isToday
          ? DateFormat('yyyy-MM-dd').format(DateTime.now())
          : DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));

      final snapshot = await FirebaseFirestore.instance
          .collection('Bookings')
          .doc(dateStr)
          .collection('BookedToday')
          .doc(slotId)
          .get();

      return _processBookingSnapshot(snapshot, slotId, userEmail);
    } catch (e) {
      print('Error checking single booking: $e');
      return null;
    }
  }



  Future<void> requestSlotAllocation() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        throw Exception('No user logged in');
      }

      String userEmail = currentUser.email ?? '';
      String userName = currentUser.displayName ??
          getDisplayNameFromEmail(userEmail);

      Map<String, dynamic> requestData = {
        'email': userEmail,
        'name': userName,
        'timestamp': FieldValue.serverTimestamp(),
        'text': 'Requested to allot slot',
        'status': 'pending',
      };

      await FirebaseFirestore.instance
          .collection('requests')
          .add(requestData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Slot request submitted successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error submitting request: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }




  Widget _buildUserTile(Map<String, dynamic> user) {
    final isCurrentUser = user['email'] == FirebaseAuth.instance.currentUser?.email;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrentUser ? Colors.blue[50] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: isCurrentUser ? Border.all(color: Colors.blue.withOpacity(0.3)) : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCurrentUser ? Colors.blue[100] : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.person_rounded,
              color: isCurrentUser ? Colors.blue[600] : Colors.grey[600],
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['name'] ?? 'Unknown User',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isCurrentUser ? Colors.blue[700] : Colors.black87,
                  ),
                ),
                Text(
                  user['email'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (isCurrentUser)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[600],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'You',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Helper for vehicle icons/colors
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

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'permanent':
        return Colors.green[600]!;
      case 'hybrid':
        return Colors.orange[600]!;
      default:
        return Colors.grey[600]!;
    }
  }





  Future<void> refreshData() async {
    // Clear cache to force fresh data
    _cachedUserSlot = null;
    _bookingStatuses.clear();
    _weeklySlotData.clear();

    // Reset dimensions cache
    _dimensionsLoaded = false;
    _carDimensions.clear();

    // Reinitialize _userSlotFuture
    setState(() {
      _userSlotFuture = fetchUserSlot();
    });

    await _userSlotFuture;

    // Refresh all data
    await Future.wait([
      _loadBookings(),
      _loadPreferencesFromBackend(),
      _loadWeeklySlotData(),
      _loadUserVehicles(),
      _fetchCarDimensions(), // Add this line
    ]);
  }

  Future<void> _fetchCarDimensions() async {
    if (_dimensionsLoaded) return; // Use cached data

    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('dimensions')
          .orderBy(FieldPath.documentId)
          .get();

      final List<CarDimension> dimensions = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return CarDimension.fromFirestore(doc.id, data);
      }).toList();

      setState(() {
        _carDimensions = dimensions;
        _dimensionsLoaded = true;
      });
    } catch (e) {
      print('Error fetching car dimensions: $e');
    }
  }




// Method to load user vehicles from Firestore
  Future<void> _loadUserVehicles() async {
    if (!mounted) return;

    setState(() {
      _isLoadingVehicles = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Note: Your backend uses 'users' collection (lowercase)
        final userDoc = await FirebaseFirestore.instance
            .collection('users') // Using lowercase as per your backend
            .doc(user.email) // Your backend uses email as document ID
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          final vehicles = userData['vehicles'] as List<dynamic>? ?? [];

          if (mounted) {
            setState(() {
              _userVehicles = vehicles.cast<Map<String, dynamic>>();
            });
          }
        }
      }
    } catch (e) {
      print('Error loading user vehicles: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading vehicles: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVehicles = false;
        });
      }
    }
  }

  Future<void> _saveVehicle(Map<String, dynamic> vehicleData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Create vehicle data with timestamp as DateTime instead of serverTimestamp()
      final vehicleWithTimestamp = {
        ...vehicleData,
        'createdAt': DateTime.now().toIso8601String(),
      };

      // Your backend uses email as document ID in 'users' collection
      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.email);

      // Check if document exists first
      final docSnapshot = await userDocRef.get();

      if (docSnapshot.exists) {
        // Document exists, update vehicles array
        await userDocRef.update({
          'vehicles': FieldValue.arrayUnion([vehicleWithTimestamp])
        });
      } else {
        // Document doesn't exist, create it with vehicle data
        final userData = {
          'name': user.displayName ?? _extractNameFromEmail(user.email!),
          'email': user.email!,
          'userType': 'user',
          'createdAt': FieldValue.serverTimestamp(),
          'platform': 'mobile_app',
          'vehicles': [vehicleWithTimestamp],
        };

        await userDocRef.set(userData);
      }

      // Reload vehicles to show updated list
      await _loadUserVehicles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Vehicle added successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error saving vehicle: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error adding vehicle: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


// Method to remove vehicle from Firestore
  Future<void> _removeVehicle(Map<String, dynamic> vehicleData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.email);

      await userDocRef.update({
        'vehicles': FieldValue.arrayRemove([vehicleData])
      });

      // Reload vehicles to show updated list
      await _loadUserVehicles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Vehicle removed successfully!"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error removing vehicle: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error removing vehicle: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

// Helper method to extract name from email (matching your backend logic)
  String _extractNameFromEmail(String email) {
    if (email.isEmpty) return 'Unknown User';

    try {
      String username = email.split('@')[0];
      List<String> parts = username.split(RegExp(r'[._]'));

      List<String> capitalizedParts = parts.map((part) {
        if (part.isEmpty) return '';
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      }).where((part) => part.isNotEmpty).toList();

      return capitalizedParts.join(' ');
    } catch (e) {
      return 'Unknown User';
    }
  }

// Updated Vehicle Info Widget with real data
  Widget _buildVehicleInfoCard(String userVehicleType) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).cardTheme.shadowColor ??
                (Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.grey.withOpacity(0.1)),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getVehicleColor(userVehicleType).withOpacity(
                          Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.1
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getVehicleIcon(userVehicleType),
                      color: _getVehicleColor(userVehicleType),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Your Vehicles',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => _showAddVehicleDialog(userVehicleType),
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoadingVehicles)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_userVehicles.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[600]!
                      : Colors.grey[200]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.grey[600],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No vehicles added yet. Add your ${userVehicleType.toLowerCase()} details to get started.',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._userVehicles.map((vehicle) => _buildVehicleTile(vehicle)).toList(),
        ],
      ),
    );
  }

// Updated Vehicle Tile Widget
  Widget _buildVehicleTile(Map<String, dynamic> vehicle) {
    final vehicleType = vehicle['type'] as String;
    final vehicleNumber = vehicle['number'] as String;
    final dimensions = vehicle['dimensions'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getVehicleColor(vehicleType).withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.15 : 0.05
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getVehicleColor(vehicleType).withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getVehicleColor(vehicleType).withOpacity(
                  Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.1
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getVehicleIcon(vehicleType),
              color: _getVehicleColor(vehicleType),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicleNumber.toUpperCase(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _getVehicleColor(vehicleType),
                  ),
                ),
                if (dimensions != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Size: $dimensions',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showRemoveVehicleDialog(vehicle),
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.red[400],
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddVehicleDialog(String userVehicleType) {
    final TextEditingController numberController = TextEditingController();
    CarDimension? selectedDimension;
    bool isLoading = false;
    bool isDimensionsLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Fetch dimensions when dialog opens for cars
          if (userVehicleType.toUpperCase() == 'CAR' && !_dimensionsLoaded) {
            if (!isDimensionsLoading) {
              isDimensionsLoading = true;
              _fetchCarDimensions().then((_) {
                if (mounted) {
                  setDialogState(() {
                    isDimensionsLoading = false;
                  });
                }
              });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getVehicleColor(userVehicleType).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getVehicleIcon(userVehicleType),
                    color: _getVehicleColor(userVehicleType),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Add ${userVehicleType.toLowerCase()}'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: numberController,
                    decoration: InputDecoration(
                      labelText: 'Vehicle Number',
                      hintText: 'e.g., TS 09 EA 1234',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(
                        Icons.confirmation_number_outlined,
                        color: _getVehicleColor(userVehicleType),
                      ),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),

                  if (userVehicleType.toUpperCase() == 'CAR') ...[
                    const SizedBox(height: 16),
                    isDimensionsLoading
                        ? Container(
                      padding: const EdgeInsets.all(16),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Loading car sizes...'),
                        ],
                      ),
                    )
                        : DropdownButtonFormField<CarDimension>(
                      value: selectedDimension,
                      decoration: InputDecoration(
                        labelText: 'Car Size',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: Icon(
                          Icons.straighten_rounded,
                          color: _getVehicleColor(userVehicleType),
                        ),
                      ),
                      items: _carDimensions.map((dimension) => DropdownMenuItem(
                        value: dimension,
                        child: Text(dimension.name),
                      )).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedDimension = value;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),

              ElevatedButton(
                onPressed: isLoading || isDimensionsLoading ? null : () async {
                  if (numberController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter vehicle number'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (userVehicleType.toUpperCase() == 'CAR' && selectedDimension == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select car size'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  setDialogState(() {
                    isLoading = true;
                  });

                  final vehicleData = {
                    'type': userVehicleType.toUpperCase(),
                    'number': numberController.text.trim(),
                    if (selectedDimension != null) ...{
                      'dimensions': selectedDimension!.name,
                      'dimensionId': selectedDimension!.id,
                      'dimensionData': selectedDimension!.data,
                    },
                  };

                  Navigator.pop(context);
                  await _saveVehicle(vehicleData);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getVehicleColor(userVehicleType),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Text('Add Vehicle'),
              ),


            ],
          );
        },
      ),
    );
  }


// Updated Remove Vehicle Dialog with backend integration
  void _showRemoveVehicleDialog(Map<String, dynamic> vehicle) {
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Remove Vehicle'),
            ],
          ),
          content: Text('Are you sure you want to remove ${vehicle['number']}?'),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                setDialogState(() {
                  isLoading = true;
                });

                Navigator.pop(context);
                await _removeVehicle(vehicle);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

}
class _AvailableSlotsBottomSheetContent extends StatefulWidget {
  final DateTime date;
  final ScrollController scrollController;
  final BookingBackend backend;
  final List<Map<String, dynamic>> Function() getUserCarVehicles;
  final Future<Map<String, dynamic>?> userSlotFuture;
  // âœ… NEW: Add callback functions
  final Future<void> Function(Map<String, dynamic>, DateTime) onBookAvailableSlot;
  final Future<void> Function(DateTime) onShowMyBookedSlotDetails;
  final Future<void> Function() onRefreshData;

  const _AvailableSlotsBottomSheetContent({
    required this.date,
    required this.scrollController,
    required this.backend,
    required this.getUserCarVehicles,
    required this.userSlotFuture,
    required this.onBookAvailableSlot, // âœ… NEW
    required this.onShowMyBookedSlotDetails, // âœ… NEW
    required this.onRefreshData, // âœ… NEW
  });

  @override
  _AvailableSlotsBottomSheetContentState createState() =>
      _AvailableSlotsBottomSheetContentState();
}

class _AvailableSlotsBottomSheetContentState
    extends State<_AvailableSlotsBottomSheetContent> {
  String? _selectedVehicleFilter;
  String? _selectedDimensionFilter;
  Future<List<Map<String, dynamic>>>? _availableSlotsFuture;
  bool _isInitialized = false;

  void _fetchSlots(String userVehicleType) {
    _availableSlotsFuture = widget.backend.getAvailableSlotsWithUserDetails(
      date: widget.date,
      vehicleTypeFilter: userVehicleType,
      dimensionFilter: _selectedDimensionFilter,
    );
  }

  void _updateFiltersAndFetch(String userVehicleType, {String? vehicleFilter, String? dimensionFilter}) {
    setState(() {
      _selectedVehicleFilter = vehicleFilter;
      _selectedDimensionFilter = dimensionFilter;
      _fetchSlots(userVehicleType);
    });
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Finding available slots...',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading slots',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please try again later',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(DateTime date) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: Colors.orange[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Available Slots',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'All slots are currently occupied for this date',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: Icon(Icons.support_agent),
              label: Text('Contact Admin'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(color: Theme.of(context).colorScheme.primary),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getFormattedDateString(DateTime date) {
    const dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dayNames[date.weekday]}, ${monthNames[date.month]} ${date.day}';
  }

  Widget _buildAvailableSlotsList(List<Map<String, dynamic>> availableSlots, ScrollController scrollController, DateTime date) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
      itemCount: availableSlots.length,
      itemBuilder: (context, index) {
        final slot = availableSlots[index];
        return _buildAvailableSlotCard(slot, date);
      },
    );
  }

  Widget _buildAvailableSlotCard(Map<String, dynamic> slot, DateTime date) {
    final slotId = slot['slotId'] as String;
    final vehicleType = slot['vehicleType'] as String;
    final slotUsers = slot['slotUsers'] as int;
    final declarationsCount = slot['declarationsCount'] as int;
    final declarations = List<Map<String, dynamic>>.from(slot['declarations'] ?? []);
    final slotData = slot['slotData'] as Map<String, dynamic>?;
    final allotedUsers = List<Map<String, dynamic>>.from(slot['allotedUsers'] ?? []);
    final isFullyAvailable = slot['isFullyAvailable'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFullyAvailable
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getVehicleColor(vehicleType).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getVehicleIcon(vehicleType),
                  color: _getVehicleColor(vehicleType),
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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '$vehicleType â€¢ ${slotData?['slotPriority'] ?? 'permanent'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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

          // Availability info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isFullyAvailable ? Colors.green : Colors.orange).withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isFullyAvailable ? Icons.verified_outlined : Icons.info_outline,
                  size: 16,
                  color: isFullyAvailable ? Colors.green[600] : Colors.orange[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isFullyAvailable
                        ? 'All $slotUsers users marked unavailability'
                        : '$declarationsCount of $slotUsers users marked unavailability',
                    style: TextStyle(
                      fontSize: 13,
                      color: isFullyAvailable ? Colors.green[700] : Colors.orange[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Slot users
          ExpansionTile(
            title: Text(
              'Slot Users',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            childrenPadding: const EdgeInsets.only(top: 8),
            children: [
              ...allotedUsers.map((user) {
                final userEmail = user['email'] as String;
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
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: hasDeclaration
                              ? _getReasonColor(reason ?? 'unavailable')
                              : Colors.grey[400],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          userName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasDeclaration
                              ? _getReasonColor(reason ?? 'unavailable').withOpacity(0.1)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          hasDeclaration
                              ? _getReasonDisplayText(reason ?? 'unavailable')
                              : 'Pending',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
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
            ],
          ),

          const SizedBox(height: 16),

          // Action button - âœ… NOW USES ACTUAL METHOD
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isFullyAvailable ? () async {
                Navigator.pop(context);
                // âœ… FIXED: Use the actual callback method
                await widget.onBookAvailableSlot(slot, date);
              } : null,
              icon: Icon(
                Icons.event_available,
                size: 18,
                color: isFullyAvailable ? Colors.white : Colors.grey[500],
              ),
              label: Text(
                'Book This Slot',
                style: TextStyle(
                  color: isFullyAvailable ? Colors.white : Colors.grey[500],
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isFullyAvailable ? Colors.green[600] : Colors.grey[300],
                foregroundColor: isFullyAvailable ? Colors.white : Colors.grey[500],
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: isFullyAvailable ? 2 : 0,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods
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

  String _getUserNameFromEmail(String email) {
    final usernamePart = email.split('@').first;
    final words = usernamePart.split('.').map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1);
    }).toList();
    return words.join(' ');
  }

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.local_parking,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Available Slots',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        _getFormattedDateString(widget.date),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: widget.userSlotFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }

                if (snapshot.hasError || snapshot.data == null) {
                  return _buildErrorState('Unable to get user vehicle type');
                }

                final userSlotData = snapshot.data!['slotData'] as Map<String, dynamic>? ?? {};
                final userVehicleType = (userSlotData['vehicleType'] as String?)?.toUpperCase() ?? 'BIKE';

                if (!_isInitialized) {
                  _isInitialized = true;
                  _selectedVehicleFilter = null;
                  _selectedDimensionFilter = null;
                  _fetchSlots(userVehicleType);
                }

                final userVehicles = widget.getUserCarVehicles();

                return Column(
                  children: [
                    if (userVehicleType == 'CAR')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.directions_car_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Your Car Sizes:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  // All chip
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      label: const Text('All', style: TextStyle(fontWeight: FontWeight.bold)),
                                      selected: _selectedDimensionFilter == null,
                                      onSelected: (selected) {
                                        _updateFiltersAndFetch(userVehicleType, vehicleFilter: null, dimensionFilter: null);
                                      },
                                      backgroundColor: Colors.blue[50],
                                      selectedColor: Colors.blue[600],
                                      checkmarkColor: Colors.white,
                                      side: BorderSide(
                                        color: (_selectedDimensionFilter == null) ? Colors.blue[600]! : Colors.blue[300]!,
                                        width: 1.5,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  ),

                                  ...userVehicles.map((vehicle) {
                                    final dimensions = vehicle['dimensions']?.toString() ?? 'Unknown';
                                    final vehicleNumber = vehicle['number']?.toString() ?? '';
                                    final isSelected = _selectedVehicleFilter == vehicleNumber;

                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: FilterChip(
                                        label: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              vehicleNumber.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected ? Colors.white : Colors.grey[700],
                                              ),
                                            ),
                                            Text(
                                              dimensions,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isSelected ? Colors.white70 : Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                        selected: isSelected,
                                        onSelected: (selected) {
                                          if (selected) {
                                            _updateFiltersAndFetch(
                                              userVehicleType,
                                              vehicleFilter: vehicleNumber,
                                              dimensionFilter: vehicle['dimensions'],
                                            );
                                          } else {
                                            _updateFiltersAndFetch(userVehicleType, vehicleFilter: null, dimensionFilter: null);
                                          }
                                        },
                                        backgroundColor: Colors.blue[50],
                                        selectedColor: Colors.blue[600],
                                        checkmarkColor: Colors.white,
                                        side: BorderSide(
                                          color: isSelected ? Colors.blue[600]! : Colors.blue[300]!,
                                          width: 1.5,
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Divider(color: Colors.grey[300], height: 1),
                          ],
                        ),
                      ),

                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _availableSlotsFuture,
                        builder: (context, slotSnapshot) {
                          if (slotSnapshot.connectionState == ConnectionState.waiting) {
                            return _buildLoadingState();
                          }
                          if (slotSnapshot.hasError) {
                            return _buildErrorState(slotSnapshot.error.toString());
                          }
                          final availableSlots = slotSnapshot.data ?? [];
                          if (availableSlots.isEmpty) {
                            return _buildEmptyState(widget.date);
                          }
                          return _buildAvailableSlotsList(availableSlots, widget.scrollController, widget.date);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}




class CarDimension {
  final String id;
  final String name;
  final Map<String, dynamic> data;

  CarDimension({
    required this.id,
    required this.name,
    required this.data,
  });

  // Replace this factory method in CarDimension class:
  factory CarDimension.fromFirestore(String id, Map<String, dynamic> data) {
    // Create display name from width x height
    String displayName = id; // fallback

    if (data.containsKey('width') && data.containsKey('height')) {
      final width = data['width']?.toString() ?? '';
      final height = data['height']?.toString() ?? '';
      displayName = '${width}m Ã— ${height}m';
    }

    return CarDimension(
      id: id,
      name: displayName,
      data: data,
    );
  }
}