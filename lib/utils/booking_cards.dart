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

  Future<Map<String, dynamic>?> _userSlotFuture = Future.value(null);

  final BookingBackend _backend = BookingBackend();
  bool _isLoadingTodayBooking = false;


  Map<DateTime, Map<String, dynamic>> _weeklySlotData = {};
  bool _isLoadingWeeklyData = false;

  static const List<String> _dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const List<String> _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  // ✅ ADD these helper methods after the constants
  String _getDayName(DateTime date) => _dayNames[date.weekday];
  String _getMonthName(DateTime date) => _monthNames[date.month];

  // ✅ Helper method for formatted date string
  String _getFormattedDateString(DateTime date) {
    return '${_getDayName(date)}, ${_getMonthName(date)} ${date.day}';
  }

  // ✅ Helper method for full date string with year
  String _getFullDateString(DateTime date) {
    return '${_getMonthName(date)} ${date.day}, ${date.year}';
  }




  Map<DateTime, Map<String, dynamic>> _bookingStatuses = {};

  Set<DateTime> _unavailableDates = {};

  Map<DateTime, String> _datePreferences = {}; // 'use', 'leave', 'wfh'



  // Add these state variables after existing ones





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
      fetchSlotRequest(),
      _loadPreferencesFromBackend(),
      _loadWeeklySlotData(), // ✅ NEW: Load weekly slot data
    ]);
  }



  Future<Map<String, dynamic>> _fetchAllDataInBatch(String slotId, String userEmail) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final tomorrow = DateFormat('yyyy-MM-dd').format(
          DateTime.now().add(const Duration(days: 1)));

      // SINGLE BATCH OPERATION instead of multiple reads
      final batch = FirebaseFirestore.instance.batch();

      // Get all required documents in one batch
      final List<Future<DocumentSnapshot>> futures = [
        // Today's booking
        FirebaseFirestore.instance
            .collection('Bookings')
            .doc(today)
            .collection('BookedToday')
            .doc(slotId)
            .get(),



      ];

      // Execute all reads in parallel
      final results = await Future.wait(futures);

      return {
        'todayBooking': _processBookingSnapshot(results[0], slotId, userEmail),

        'toggleSettings': results[2].exists ? results[2].data() : {},
      };
    } catch (e) {
      throw e;
    }
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

    // ✅ NEW: Check if assigned slot is booked by others
    final assignedSlotBookedByOther = slotData?['assignedSlotBookedByOther'] == true;

    // ✅ FIX: Determine slot availability status for UI logic
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
              // ✅ FIXED: User's assigned slot is booked by others (RED state)
              // Only show "See Available Slots" - no leave/WFH options
              _buildSlotBookedByOthersCard(date),
              const SizedBox(height: 16),
              _buildSeeAvailableSlotsOption(date),
            ] else if (isSlotAvailable) ...[
              // ✅ FIXED: Slot is available (BLUE state)
              // Show book slot and leave/WFH options - no "See Available Slots"
              _buildBookSlotOption(date),
              const SizedBox(height: 12),
              _buildPreferenceOption(date, 'leave', 'On Leave', 'I will be on leave this day', Icons.beach_access, Colors.orange),
              const SizedBox(height: 12),
              _buildPreferenceOption(date, 'wfh', 'Work From Home', 'I will be working from home', Icons.home_work, Colors.blue),
            ] else ...[
              // ✅ FALLBACK: Default case for any other state
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



// ✅ UPDATED: Header subtitle method with unavailable status
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

// ✅ NEW: Method for any slot booking card
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

// ✅ NEW: View booking details option
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

          // ✅ IMMEDIATE: Clear weekly cache for this date
          _weeklySlotData.remove(date);

          // ✅ REFRESH: Reload actual slot status
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
// ✅ REPLACE the onTap in _buildRemoveOption with this:
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

        // ✅ IMMEDIATELY update UI to show the selection
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



// Method to update request status in Firestore
  Future<void> _updateRequestStatus(String requestId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({'status': status});
    } catch (e) {
      print('Error updating request status: $e');
      throw e;
    }
  }




// ✅ ADD this new method to load from backend
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
      print('❌ Error loading preferences from backend: $e');
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


  Widget _buildParkingUsageCard() {
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
                  Icons.event_note_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly Parking Preference',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ) ?? TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mark working days when you won\'t use your slot',
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

          const SizedBox(height: 16),

          // Info and Action Buttons
          _buildParkingPreferenceActions(),
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
        // ✅ FIX: Show red for unavailable (booked by others)
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
      // ✅ FIX: Show red border for unavailable
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
      // ✅ FIX: Show red text for unavailable
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
        // ✅ FIX: Show block icon for unavailable
        return Icon(Icons.block, size: 16, color: Colors.red[600]);
      }
    }
    return Icon(Icons.add_circle_outline, size: 14, color: Colors.blue[600]);
  }

  Widget _buildParkingPreferenceActions() {
    return Column(
      children: [
        // Legend
        Container(
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
              _buildLegendItem(Icons.touch_app_rounded, 'Tap to Set', Colors.grey[500]!),
              _buildLegendItem(Icons.beach_access, 'Leave', Colors.orange[600]!),
              _buildLegendItem(Icons.home_work, 'WFH', Colors.blue[600]!),
            ],
          ),
        ),


        // Action Buttons

      ],
    );
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

// Add these methods to your _BookingCardsState class:


// ✅ REPLACE this method
  void _clearAllUnavailableDates() async {
    setState(() {
      _isUpdatingPreferences = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final result = await _backend.clearAllUserAvailabilityDeclarationsOptimized(user.email!);

        if (result['success']) {
          setState(() {
            _datePreferences.clear();
            _unavailableDates.clear();
          });

          _backend.showSnackBar(context, result['message']);
        } else {
          _backend.showSnackBar(context, result['message'], isError: true);
        }
      }
    } catch (e) {
      _backend.showSnackBar(context, 'Error clearing preferences: $e', isError: true);
    } finally {
      setState(() {
        _isUpdatingPreferences = false;
      });
    }
  }





// Add these state variables to your _BookingCardsState class
  DateTime _selectedBookingDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  bool _isLoadingBookingStatus = false;

  Widget _buildWeeklyBookingCard() {
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly Slot Booking',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ) ?? TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select a date to check booking status',
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


          const SizedBox(height: 20),

          // Booking Status Card
          _buildBookingStatusCard(),
        ],
      ),
    );
  }

  Widget _buildBookingStatusCard() {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedSelectedDate = DateTime(_selectedBookingDate.year, _selectedBookingDate.month, _selectedBookingDate.day);
    final isSelectedDateToday = DateUtils.isSameDay(_selectedBookingDate, normalizedToday);

    // ✅ Check if user declared unavailability for this date FIRST
    if (_datePreferences.containsKey(normalizedSelectedDate)) {
      return _buildUserDeclarationCard(normalizedSelectedDate);
    }

    // ✅ NEW: Check if user has booked ANY slot (not just their assigned slot)
    return FutureBuilder<Map<String, dynamic>?>(
      future: _backend.getUserBookedSlotForDate(
        userEmail: FirebaseAuth.instance.currentUser?.email ?? '',
        date: _selectedBookingDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingBookingStatusCard();
        }

        if (snapshot.hasError) {
          return _buildErrorBookingStatusCard();
        }

        final userBookedSlot = snapshot.data;

        if (userBookedSlot != null) {
          // User has booked some slot (either their own or alternative)
          return _buildUserHasBookingCard(userBookedSlot, _selectedBookingDate);
        } else {
          // User hasn't booked any slot, check if their assigned slot is available
          return FutureBuilder<BookingStatus>(
            future: _getBookingStatusForDate(_selectedBookingDate),
            builder: (context, statusSnapshot) {
              BookingStatus bookingStatus = BookingStatus.available;

              if (statusSnapshot.hasData) {
                bookingStatus = statusSnapshot.data!;
              } else if (statusSnapshot.hasError) {
                return _buildErrorBookingStatusCard();
              }

              return _buildBookingStatusCardContent(bookingStatus);
            },
          );
        }
      },
    );
  }

  // ✅ NEW METHOD: Show when user has booked any slot (own or alternative)
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
                  '${vehicleType.toUpperCase()} • ${_getFormattedDateString(date)}',
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

// Add this helper method for error state:
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

// Add this helper method for the actual content:
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
          onPressed: () => _showAvailableSlotsBottomSheet(_selectedBookingDate), // ✅ NEW
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
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
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

              // Header (simplified - no toggle)
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
                            _getFormattedDateString(date),
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
                  future: _userSlotFuture,
                  builder: (context, userSlotSnapshot) {
                    if (userSlotSnapshot.connectionState == ConnectionState.waiting) {
                      return _buildLoadingState();
                    }

                    if (userSlotSnapshot.hasError || userSlotSnapshot.data == null) {
                      return _buildErrorState('Unable to get user vehicle type');
                    }

                    final userSlotData = userSlotSnapshot.data!['slotData'] as Map<String, dynamic>;
                    final userVehicleType = userSlotData['vehicleType'] as String? ?? 'BIKE';

                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: _backend.getAvailableSlotsWithUserDetails(
                        date: date,
                        vehicleTypeFilter: userVehicleType,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return _buildLoadingState();
                        }

                        if (snapshot.hasError) {
                          return _buildErrorState(snapshot.error.toString());
                        }

                        final availableSlots = snapshot.data ?? [];

                        if (availableSlots.isEmpty) {
                          return _buildEmptyState(date);
                        }

                        return _buildAvailableSlotsList(availableSlots, scrollController, date); // ✅ Pass date
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

// ✅ NEW: Error state widget
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

// ✅ NEW: Empty state widget
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
        return _buildAvailableSlotCard(slot, date); // ✅ Pass date parameter
      },
    );
  }

  Widget _buildAvailableSlotCard(Map<String, dynamic> slot, DateTime date)
  {

    final slotId = slot['slotId'] as String;
    final vehicleType = slot['vehicleType'] as String;
    final slotUsers = slot['slotUsers'] as int;
    final declarationsCount = slot['declarationsCount'] as int;
    final declarations = List<Map<String, dynamic>>.from(slot['declarations'] ?? []);
    final slotData = slot['slotData'] as Map<String, dynamic>?;
    final allotedUsers = List<Map<String, dynamic>>.from(slot['allotedUsers'] ?? []);

    // ✅ NEW: Check availability status
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
                      '$vehicleType • ${slotData?['slotPriority'] ?? 'permanent'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // ✅ UPDATED: Availability status badge
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

          // ✅ UPDATED: Availability info with better messaging
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
              // ✅ NEW: Show all users with their status
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
                // ✅ UPDATED: Implement booking logic for fully available slots
                Navigator.pop(context); // Close the bottom sheet
                await _bookAvailableSlot(slot, date); // ✅ Pass the date parameter
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

        // ✅ IMMEDIATE: Update cache with alternative booking data
        await _updateWeeklyCacheForDate(
          date,
          isBooked: true,
          isBookedByCurrentUser: true,
          bookedSlotId: slotId,
          bookingType: 'alternative',
          assignedSlotBookedByOther: false,
        );

        // ✅ REFRESH: Complete data reload
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

// ✅ NEW METHOD: Show current user's booked slot details
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

      // Close loading dialog
      Navigator.pop(context);

      if (bookedSlotDetails != null) {
        _showBookedSlotDetailsDialog(bookedSlotDetails, date);
      } else {
        _backend.showSnackBar(context, 'No booking found for this date', isError: true);
      }
    } catch (e) {
      // Close loading dialog
      Navigator.pop(context);
      _backend.showSnackBar(context, 'Error loading booking details: $e', isError: true);
    }
  }

// ✅ NEW METHOD: Show detailed dialog of booked slot
  void _showBookedSlotDetailsDialog(Map<String, dynamic> slotDetails, DateTime date) {
    final slotId = slotDetails['slotId'] as String;
    final bookingData = slotDetails['bookingData'] as Map<String, dynamic>;
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
              child: Icon(Icons.local_parking, color: Colors.green[600]),
            ),
            const SizedBox(width: 12),
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

            // Booking Details
            _buildDetailRow('Booked By', userName, Icons.person),
            const SizedBox(height: 12),
            _buildDetailRow('Vehicle Type', vehicleType.toUpperCase(), _getVehicleIcon(vehicleType)),
            const SizedBox(height: 12),
            _buildDetailRow('Booking Type', bookingType == 'alternative' ? 'Alternative Slot' : 'Regular Slot',
                bookingType == 'alternative' ? Icons.swap_horiz : Icons.event_available),
            const SizedBox(height: 12),
            _buildDetailRow('Booked At', bookingTimeStr, Icons.access_time),

            if (bookingType == 'alternative') ...[
              const SizedBox(height: 16),
              Container(
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
                        'This is an alternative slot booking. The original slot owners declared unavailability.',
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

// ✅ HELPER METHOD: Build detail row
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




// ✅ NEW: Helper methods
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




// Replace these two methods in your _BookingCardsState class:

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

        // ✅ Use your backend method to get booking status
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

        // ✅ IMMEDIATE: Clear weekly cache completely for this date
        await _updateWeeklyCacheForDate(
          date,
          isBooked: false,
          isBookedByCurrentUser: false,
          bookedSlotId: null,
          bookingType: 'regular',
          assignedSlotBookedByOther: false,
        );

        // ✅ REFRESH: Reload actual status to check if assigned slot is booked by others
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

          const SizedBox(height: 16),
          _buildrulesCard(),

          const SizedBox(height: 16),
          _buildSlotUsersCard(allotedTo),
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

  Widget _buildrulesCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: isDark
              ? [
            Theme.of(context).colorScheme.primary.withOpacity(0.2),
            Theme.of(context).colorScheme.primary.withOpacity(0.1),
          ]
              : [
            Colors.indigo.withOpacity(0.1),
            Colors.indigo.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                  : Colors.indigo.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
                Icons.info_outline_rounded,
                color: isDark
                    ? Theme.of(context).colorScheme.primary
                    : Colors.indigo,
                size: 24
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Booking Guidelines",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? Theme.of(context).colorScheme.primary
                        : Colors.indigo[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "• Eat 5 star Do Nothing 😎 \n",

                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.8)
                        : Colors.indigo[600]!.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



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

        // ✅ IMMEDIATE: Update weekly cache with complete data
        await _updateWeeklyCacheForDate(
          date,
          isBooked: true,
          isBookedByCurrentUser: true,
          bookedSlotId: slotId,
          bookingType: 'regular',
          assignedSlotBookedByOther: false,
        );

        // ✅ REFRESH: Update other data sources
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




  Widget _buildRequestStatusWidget(String? status) {
    // Check if status starts with "allotted-"
    if (status != null && status.startsWith('allotted-')) {
      // Extract the slot info after "allotted-"
      String allottedSlot = status.substring(9); // Remove "allotted-"

      // Format the slot (e.g., "b3--377" becomes "B3 - 377")
      String formattedSlot = allottedSlot
          .replaceAll('--', ' - ')
          .toUpperCase();

      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green[300]!),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: Colors.green[700],
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Admin allotted $formattedSlot for today',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }






    // Default pending state for other statuses
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[300]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.hourglass_top_rounded,
            color: Colors.orange[700],
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'Request Pending',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.orange[700],
            ),
          ),
        ],
      ),
    );





  }


  Map<String, dynamic>? _getRequestByType(Map<String, dynamic> summary, String requestType) {
    final allRequests = summary['allRequests'] as List<Map<String, dynamic>>? ?? [];
    try {
      return allRequests.firstWhere(
            (request) => request['type'] == requestType,
      );
    } catch (e) {
      return null; // Not found
    }
  }



  Widget _buildLoadingBookingInfo(bool isToday) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.schedule_rounded,
                color: Colors.blue[300],
                size: 32,
              ),
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Loading Your Slot Information...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isToday
                ? 'Checking your slot details for today'
                : 'Checking your slot details for tomorrow',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          // Animated dots for extra visual appeal
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildAnimatedDot(0),
              const SizedBox(width: 4),
              _buildAnimatedDot(1),
              const SizedBox(width: 4),
              _buildAnimatedDot(2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return AnimatedBuilder(
          animation: AlwaysStoppedAnimation(value),
          builder: (context, child) {
            return Transform.scale(
              scale: 0.5 + (0.5 * ((sin(value * 2 * pi * 2) + 1) / 2)),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.blue[400],
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      },
    );
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
    // Return cached if available and recent
    if (_cachedUserSlot != null) {
      return _cachedUserSlot;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user logged in');

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data()?['assignedSlotId'] != null) {
        final userSlotId = userDoc.data()!['assignedSlotId'] as String;
        final slotDoc = await FirebaseFirestore.instance
            .collection('Slots')
            .doc(userSlotId)
            .get();

        if (slotDoc.exists) {
          final slotData = slotDoc.data()!;
          final allotedTo = slotData['alloted_to'] as List<dynamic>? ?? [];

          Map<String, dynamic>? userInfo;
          for (var userData in allotedTo) {
            if (userData['email'] == user.email) {
              userInfo = userData;
              break;
            }
          }

          if (userInfo != null) {
            // CACHE the result
            _cachedUserSlot = {
              'slotId': userSlotId,
              'slotData': slotData,
              'userInfo': userInfo,
            };
            return _cachedUserSlot;
          }
        }
      }
    } catch (e) {
      print('Error in optimized slot fetch: $e');
    }

    print('WARNING: Using expensive fallback - consider fixing Users collection');
    return await fetchUserSlotPrev();
  }





  Future<Map<String, dynamic>?> fetchUserSlotPrev() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user logged in');

    final userEmail = user.email!;

    // Query Slots collection to find slot where user email exists in alloted_to array
    final slotsSnapshot = await FirebaseFirestore.instance
        .collection('Slots')
        .get();

    for (var doc in slotsSnapshot.docs) {
      final data = doc.data();
      final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];

      // Check if user email exists in alloted_to array
      for (var user in allotedTo) {
        if (user['email'] == userEmail) {
          return {
            'slotId': doc.id,
            'slotData': data,
            'userInfo': user,
          };
        }
      }
    }

    return null; // User not found in any slot
  }

  Future<void> fetchSlotRequest() async {
    setState(() {
      _isLoadingRequest = true;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _slotRequest = null;
          _isLoadingRequest = false;
        });
        return;
      }

      final query = await FirebaseFirestore.instance
          .collection('requests')
          .where('email', isEqualTo: user.email)
          .get();

      if (query.docs.isNotEmpty) {
        var docs = query.docs;
        docs.sort((a, b) {
          final aTime = a.data()['timestamp'];
          final bTime = b.data()['timestamp'];
          if (aTime != null && bTime != null) {
            return bTime.compareTo(aTime);
          }
          if (aTime != null) return -1;
          if (bTime != null) return 1;
          return 0;
        });
        _slotRequest = docs.first.data();
      } else {
        _slotRequest = null;
      }
    } catch (e) {
      _slotRequest = null;
    }
    setState(() {
      _isLoadingRequest = false;
    });
  }

  Future<void> _loadBookings() async {
    if (!mounted) return;

    setState(() {
      // ✅ For initial loading of both, you can use either variable or create a separate one
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

  Future<void> refreshData() async {
    // Clear cache to force fresh data
    _cachedUserSlot = null;
    _bookingStatuses.clear();
    _weeklySlotData.clear(); // ✅ Clear weekly data cache

    // Reinitialize _userSlotFuture
    setState(() {
      _userSlotFuture = fetchUserSlot();
    });

    await _userSlotFuture;

    // Refresh all data
    await Future.wait([
      _loadBookings(),
      fetchSlotRequest(),
      _loadPreferencesFromBackend(),
      _loadWeeklySlotData(), // ✅ Refresh weekly slot data
    ]);
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

        // ✅ FIX: Check both user's bookings AND assigned slot status
        final futures = workingDays.map((date) async {
          // Check if user has booked any slot
          final userBooking = await _backend.getUserBookedSlotForDate(
            userEmail: userEmail,
            date: date,
          );

          // ✅ NEW: Also check if user's assigned slot is booked by others
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
      await fetchSlotRequest();
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



  @override
  void dispose() {
    super.dispose();
  }



}


