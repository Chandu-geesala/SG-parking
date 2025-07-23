import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:park_sg/utils/slot_allotment_card.dart';

import '../viewModel/bookingBackend.dart';
import 'package:park_sg/utils/theme_provider.dart';
class BookingCards extends StatefulWidget {
  const BookingCards({Key? key}) : super(key: key);

  @override
  State<BookingCards> createState() => _BookingCardsState();
}

class _BookingCardsState extends State<BookingCards> {
  late Future<Map<String, dynamic>?> _userSlotFuture;
  final BookingBackend _backend = BookingBackend();
  bool _isLoadingTodayBooking = false;
  bool _isLoadingTomorrowBooking = false;


  // Booking state variables
  Map<String, dynamic>? _todaysBooking;
  Map<String, dynamic>? _tomorrowsBooking;
  bool _isLoadingBookings = false;
// Add these new state variables after existing ones
  bool _allowRequests = false;
  bool _allowAutoAllotment = false;
  StreamSubscription<DocumentSnapshot>? _toggleSubscription;
  bool _isLoadingToggles = false;


  Map<String, dynamic>? _cachedUserSlot;
  int _cachedWeeklyCount = 0;
  DateTime? _lastWeeklyCountFetch;


  int _weeklyBookingCount = 0;
  bool _isLoadingWeeklyCount = false;

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

// 4. Add method to fetch weekly booking count

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
        // Tomorrow's booking
        FirebaseFirestore.instance
            .collection('Bookings')
            .doc(tomorrow)
            .collection('BookedToday')
            .doc(slotId)
            .get(),
        // Toggle settings
        FirebaseFirestore.instance
            .collection('toggle')
            .doc('settings')
            .get(),
      ];

      // Execute all reads in parallel
      final results = await Future.wait(futures);

      return {
        'todayBooking': _processBookingSnapshot(results[0], slotId, userEmail),
        'tomorrowBooking': _processBookingSnapshot(results[1], slotId, userEmail),
        'toggleSettings': results[2].exists ? results[2].data() : {},
      };
    } catch (e) {
      throw e;
    }
  }






// Initialize toggle listener
  void _initializeToggleListener() {
    _toggleSubscription = FirebaseFirestore.instance
        .collection('toggle')
        .doc('settings')
        .snapshots()
        .listen(
          (DocumentSnapshot snapshot) {
        if (mounted) {
          setState(() {
            if (snapshot.exists) {
              final data = snapshot.data() as Map<String, dynamic>?;
              _allowRequests = data?['allowRequests'] ?? false;
              _allowAutoAllotment = data?['allowAutoAllotment'] ?? false;
            } else {
              _allowRequests = false;
              _allowAutoAllotment = false;
            }
            _isLoadingToggles = false;
          });
        }
      },
      onError: (error) {
        print('Error listening to toggle settings: $error');
        if (mounted) {
          setState(() {
            _isLoadingToggles = false;
          });
        }
      },
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


  @override
  void initState() {
    super.initState();
    _initializeToggleListener(); // Add this line
    _initializeData();
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

  bool isBookingWindowOpen() {
    final now = DateTime.now();
    final open = DateTime(now.year, now.month, now.day, 8, 0, 0);
    final close = DateTime(now.year, now.month, now.day, 20, 0, 0);
    return now.isAfter(open) && now.isBefore(close);
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





  Widget _buildTodaysBookingCard(String slotId) {
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
                  Icons.today_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24
              ),
              const SizedBox(width: 12),
              Text(
                'Today\'s Booking',
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
          if (_isLoadingTodayBooking)
            Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            )
          else
            if (_todaysBooking != null)
              _buildTodaysBookingStatus(_todaysBooking!, slotId)
            else
              _buildLoadingBookingInfo(true),
        ],
      ),
    );
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
          const SizedBox(height: 10),
          _buildrulesCard(),
          const SizedBox(height: 16),
          _buildTodaysBookingCard(slotId),
          const SizedBox(height: 16),
          _buildTomorrowsBookingWidget(slotId, vehicleType, slotPriority),
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
          const SizedBox(height: 20),
          if (vehicleType.toUpperCase() == 'CAR' &&
              vehicleCompatibility != null &&
              vehicleCompatibility.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: _buildInfoTile(
                    'Vehicle Type',
                    vehicleType,
                    _getVehicleColor(vehicleType),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoTile(
                    'Priority',
                    slotPriority,
                    _getPriorityColor(slotPriority),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoTile(
                    'Level',
                    vehicleCompatibility,
                    Colors.indigo,
                  ),
                ),
              ],
            ),
          ] else
            ...[
              Row(
                children: [
                  Expanded(
                    child: _buildInfoTile(
                      'Vehicle Type',
                      vehicleType,
                      _getVehicleColor(vehicleType),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoTile(
                      'Priority',
                      slotPriority,
                      _getPriorityColor(slotPriority),
                    ),
                  ),
                ],
              ),
            ],
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
                  "• Book for tomorrow between 8 AM and 8 PM\n"
                      "• Max 3 bookings per week (Mon–Fri)\n"
                      "• Booking applies only on weekdays",
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


  Widget _buildTomorrowsBookingWidget(String slotId, String vehicleType, String slotPriority) {
    final isWindowOpen = isBookingWindowOpen();
    final hasReachedWeeklyLimit = _weeklyBookingCount >= 3;

    // Determine if slot is available for booking
    bool isSlotAvailable = false;
    bool isBookedByCurrentUser = false;

    if (_tomorrowsBooking != null) {
      final exists = _tomorrowsBooking!['exists'] as bool;
      isBookedByCurrentUser = _tomorrowsBooking!['isBookedByCurrentUser'] as bool;
      isSlotAvailable = !exists; // Slot is available if it doesn't exist in bookings
    }

    // Only show book button if slot is available, window is open, and user hasn't reached weekly limit
    bool shouldShowBookButton = isSlotAvailable && isWindowOpen && !hasReachedWeeklyLimit && !_isLoadingBookings;

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
          // Header Section
          Row(
            children: [
              Icon(
                  Icons.calendar_today_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24
              ),
              const SizedBox(width: 12),
              Text(
                "Tomorrow's Booking",
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

          // Weekly Booking Count Display
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasReachedWeeklyLimit
                  ? (Theme.of(context).brightness == Brightness.dark
                  ? Colors.red[900]?.withOpacity(0.3)
                  : Colors.red[50])
                  : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.green[900]?.withOpacity(0.3)
                  : Colors.green[50]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasReachedWeeklyLimit
                    ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.red[400]!
                    : Colors.red[200]!)
                    : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.green[400]!
                    : Colors.green[200]!),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasReachedWeeklyLimit ? Icons.block_rounded : Icons.timelapse,
                  color: hasReachedWeeklyLimit
                      ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.red[400]
                      : Colors.red[600])
                      : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.green[400]
                      : Colors.green[600]),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly Booking Status',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: hasReachedWeeklyLimit
                              ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.red[300]
                              : Colors.red[700])
                              : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.green[300]
                              : Colors.green[700]),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Used: $_weeklyBookingCount/3 slots this week',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasReachedWeeklyLimit
                              ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.red[400]
                              : Colors.red[600])
                              : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.green[400]
                              : Colors.green[600]),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoadingWeeklyCount)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        hasReachedWeeklyLimit
                            ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors.red[400]!
                            : Colors.red[600]!)
                            : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.green[400]!
                            : Colors.green[600]!),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Booking Status Section
          if (_isLoadingTomorrowBooking)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            )
          else if (_tomorrowsBooking != null)
            Column(
              children: [
                _buildTomorrowBookingStatus(_tomorrowsBooking!, slotId),
                const SizedBox(height: 16),
              ],
            )
          else
            Column(
              children: [
                _buildLoadingBookingInfo(false),
                const SizedBox(height: 16),
              ],
            ),

          // Booking Actions Section
          if (shouldShowBookButton) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _bookSlotForTomorrow(slotId, vehicleType),
                label: const Text("Book Tomorrow's Slot"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (hasReachedWeeklyLimit && isSlotAvailable && isWindowOpen) ...[
            // Show "Reached Weekly Limit" button when user has reached the limit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null, // Disabled button
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text("Reached Max Bookings This Week"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.red[600]
                      : Colors.red[400],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],


        ],
      ),
    );
  }



  void _requestAdminForTodaySlot(String slotId) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Submitting request...'),
              ],
            ),
          );
        },
      );

      // Call the backend method to request today's slot
      final result = await _backend.requestTodaySlot(slotId);

      // Close loading dialog
      Navigator.of(context).pop();

      if (result['success']) {
        // Show success message
        _backend.showSnackBar(context, result['message'], isError: false);

        // Show success dialog
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Request Sent'),
              content: Text('Your request for slot ${slotId.toUpperCase()} has been sent to the admin.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Refresh the UI to reflect the new request
                    setState(() {});
                  },
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      } else {
        // Show error message
        _backend.showSnackBar(context, result['message'], isError: true);

        // Show error dialog
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Request Failed'),
              content: Text(result['message']),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      // Close loading dialog if it's still open
      Navigator.of(context).pop();

      // Show error message
      _backend.showSnackBar(context, 'Error submitting request: ${e.toString()}', isError: true);

      print('Error requesting admin for today slot: $e');
    }
  }


  void _requestAdminForAltSlot(String slotId) async {
    try {

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Submitting request...'),
              ],
            ),
          );
        },
      );

      // Call the backend method to request alternative slot
      final result = await _backend.requestAlternativeSlot(slotId);

      // Close loading dialog
      Navigator.of(context).pop();

      if (result['success']) {
        // Show success message
        _backend.showSnackBar(context, result['message'], isError: false);

        // Show success dialog
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Request Sent'),
              content: Text('Your request for an alternative slot has been sent to the admin.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Refresh the UI to reflect the new request
                    setState(() {});
                  },
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      } else {
        // Show error message
        _backend.showSnackBar(context, result['message'], isError: true);

        // Show error dialog
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Request Failed'),
              content: Text(result['message']),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      // Close loading dialog if it's still open
      Navigator.of(context).pop();

      // Show error message
      _backend.showSnackBar(context, 'Error submitting request: ${e.toString()}', isError: true);

      print('Error requesting admin for alternative slot: $e');
    }
  }






  Widget _buildTodaysBookingStatus(Map<String, dynamic> bookingInfo,
      String slotId) {
    final exists = bookingInfo['exists'] as bool;
    final isBookedByCurrentUser = bookingInfo['isBookedByCurrentUser'] as bool;

    if (!exists) {
      return _buildTodaysSlotAvailableInfo(slotId);
    } else if (isBookedByCurrentUser) {
      return _buildBookingInfo(bookingInfo, true);
    } else {
      return _buildTodaysOtherUserBookingInfo(bookingInfo);
    }
  }




  Widget _buildTodaysSlotAvailableInfo(String slotId) {
    if (_isLoadingToggles) {
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
            Icon(Icons.event_available_rounded, color: Colors.blue[600], size: 32),
            const SizedBox(height: 8),
            Text(
              'Slot Available for Today',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blue[700]),
            ),
            const SizedBox(height: 16),
            CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 8),
            Text('Loading options...', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      );
    }

    // If neither toggle is enabled, show basic info without buttons
    if (!_allowRequests && !_allowAutoAllotment) {
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
            Icon(Icons.event_available_rounded, color: Colors.blue[600], size: 32),
            const SizedBox(height: 8),
            Text(
              'Slot Available for Today',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blue[700]),
            ),
            const SizedBox(height: 4),
            Text(
              'Your slot ${slotId.toUpperCase()} is available today',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'No booking options available at the moment',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

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
          Icon(Icons.event_available_rounded, color: Colors.blue[600], size: 32),
          const SizedBox(height: 8),
          Text(
            'Slot Available for Today',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blue[700]),
          ),
          const SizedBox(height: 4),
          Text(
            'Your slot ${slotId.toUpperCase()} is available today',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Show slot allotment widget if auto allotment is enabled
          if (_allowAutoAllotment) ...[
            FutureBuilder<Map<String, dynamic>>(
              future: _backend.getUserRequestsSummary(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return CircularProgressIndicator();
                }

                final summary = snapshot.data ?? {};
                final todayRequest = _getRequestByType(summary, 'TodReq');
                final status = todayRequest?['status'] ?? 'pending';
                final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';

                return FutureBuilder<Map<String, dynamic>?>(
                  future: _userSlotFuture, // Get user's slot data
                  builder: (context, slotSnapshot) {
                    if (slotSnapshot.connectionState == ConnectionState.waiting) {
                      return CircularProgressIndicator();
                    }

                    // Extract vehicle type from user's assigned slot
                    String vehicleType = 'BIKE'; // Default fallback
                    if (slotSnapshot.hasData && slotSnapshot.data != null) {
                      final slotData = slotSnapshot.data!['slotData'] as Map<String, dynamic>;
                      vehicleType = slotData['vehicleType'] as String? ?? 'BIKE';
                    }

                    return SlotAllotmentWidget(
                      requestId: todayRequest?['id'] ?? '',
                      vehicleType: vehicleType, // ✅ Use actual vehicle type
                      requestData: {
                        'email': userEmail,
                        'vehicleType': vehicleType, // ✅ Use actual vehicle type
                        'currentSlotId': slotId,
                        'type': 'TodReq',
                      },

                      isDesktop: MediaQuery.of(context).size.width > 768,

                      onSlotsRefresh: () async {
                        await _refreshTodayOnly();
                      },
                    );
                  },
                );


              },
            ),


          ],

          // Show request buttons if requests are allowed
          if (_allowRequests) ...[
            if (_allowAutoAllotment) const SizedBox(height: 16), // Add spacing if both are shown

            FutureBuilder<Map<String, dynamic>>(
              future: _backend.getUserRequestsSummary(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ElevatedButton.icon(
                    onPressed: null,
                    icon: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.grey)),
                    ),
                    label: Text('Loading...', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                }

                final summary = snapshot.data ?? {};
                final altRequest = _getRequestByType(summary, 'TodReq');
                bool hasRecentRequest = false;
                String? requestStatus;

                if (altRequest != null) {
                  final timestamp = altRequest['timestamp'];
                  if (timestamp != null) {
                    DateTime requestDate;
                    if (timestamp is Timestamp) {
                      requestDate = timestamp.toDate();
                    } else {
                      requestDate = DateTime.now();
                    }

                    final today = DateTime.now();
                    final isSameDay = requestDate.year == today.year &&
                        requestDate.month == today.month &&
                        requestDate.day == today.day;

                    hasRecentRequest = isSameDay;
                    if (hasRecentRequest) {
                      requestStatus = altRequest['status'];
                    }
                  }
                }

                return SizedBox(
                  width: double.infinity,
                  child: hasRecentRequest
                      ? _buildRequestStatusWidget(requestStatus)
                      : ElevatedButton.icon(
                    onPressed: () => _requestAdminForTodaySlot(slotId),
                    icon: Icon(Icons.admin_panel_settings_rounded, size: 18),
                    label: Text('Request Admin for Today\'s Slot', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                  ),
                );
              },
            ),


          ],
        ],
      ),
    );
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

  Widget _buildTodaysOtherUserBookingInfo(Map<String, dynamic> bookingInfo) {
    final bookingData = bookingInfo['bookingData'] as Map<String, dynamic>;
    final slotId = bookingInfo['slotId'] as String;
    final bookedBy = bookingInfo['bookedBy'] as String;
    final bookedUserName = bookingData['userName'] as String? ?? bookedBy.split('@').first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.block_rounded,
                color: Colors.red[600],
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Slot Already Booked for Today',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Booked by: $bookedUserName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Check toggle states and show appropriate options
          if (_isLoadingToggles) ...[
            CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 8),
            Text('Loading options...', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ] else if (!_allowRequests && !_allowAutoAllotment) ...[
            // Neither toggle is enabled
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'No booking options available at the moment',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
          ] else ...[
            // Show slot allotment widget if auto allotment is enabled
            if (_allowAutoAllotment) ...[
              FutureBuilder<Map<String, dynamic>>(
                future: _backend.getUserRequestsSummary(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }

                  final summary = snapshot.data ?? {};
                  final altRequest = _getRequestByType(summary, 'AltReq');
                  final status = altRequest?['status'] ?? 'pending';
                  final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';

                  // Get vehicle type from user's assigned slot
                  return FutureBuilder<Map<String, dynamic>?>(
                    future: _userSlotFuture, // Get user's slot data
                    builder: (context, slotSnapshot) {
                      if (slotSnapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }

                      // Extract vehicle type from user's assigned slot (not booking data)
                      String vehicleType = 'BIKE'; // Default fallback
                      if (slotSnapshot.hasData && slotSnapshot.data != null) {
                        final slotData = slotSnapshot.data!['slotData'] as Map<String, dynamic>;
                        vehicleType = slotData['vehicleType'] as String? ?? 'BIKE';
                      }

                      return SlotAllotmentWidget(
                        requestId: altRequest != null ? 'alt_request_${DateTime.now().millisecondsSinceEpoch}' : '',
                        vehicleType: vehicleType, // ✅ Use user's assigned slot vehicle type
                        requestData: {
                          'email': userEmail,
                          'vehicleType': vehicleType, // ✅ Use user's assigned slot vehicle type
                          'currentSlotId': slotId,
                          'type': 'AltReq',
                        },

                        isDesktop: MediaQuery.of(context).size.width > 768,

                        onSlotsRefresh: () async {
                          await _refreshTodayOnly();
                        },
                      );
                    },
                  );

                },
              )
            ],

            // Show request buttons if requests are allowed (and auto allotment is not enabled)
            if (_allowRequests && !_allowAutoAllotment) ...[

              FutureBuilder<Map<String, dynamic>>(
                future: _backend.getUserRequestsSummary(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: null,
                        icon: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                          ),
                        ),
                        label: Text(
                          'Loading...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[300],
                          foregroundColor: Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Container(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _requestAdminForAltSlot(slotId);
                        },
                        icon: Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 18,
                        ),
                        label: Text(
                          'Request Admin for Alternate Slot',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                      ),
                    );
                  }

                  final summary = snapshot.data ?? {};
                  final altRequest = _getRequestByType(summary, 'AltReq');

                  bool hasRecentRequest = false;
                  String? requestStatus;

                  if (altRequest != null) {
                    final timestamp = altRequest['timestamp'];
                    if (timestamp != null) {
                      DateTime requestDate;
                      if (timestamp is Timestamp) {
                        requestDate = timestamp.toDate();
                      } else {
                        requestDate = DateTime.now();
                      }
                      final today = DateTime.now();
                      final isSameDay = requestDate.year == today.year &&
                          requestDate.month == today.month &&
                          requestDate.day == today.day;
                      hasRecentRequest = isSameDay;
                      if (hasRecentRequest) {
                        requestStatus = altRequest['status'];
                      }
                    }
                  }

                  return SizedBox(
                    width: double.infinity,
                    child: hasRecentRequest
                        ? _buildRequestStatusWidget(requestStatus)
                        : ElevatedButton.icon(
                      onPressed: () {
                        _requestAdminForAltSlot(slotId);
                      },
                      icon: Icon(
                        Icons.admin_panel_settings_rounded,
                        size: 18,
                      ),
                      label: Text(
                        'Request Admin for Alternate Slot',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 2,
                      ),
                    ),
                  );
                },
              )
            ],
          ],
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


  Widget _buildBookingInfo(Map<String, dynamic> booking, bool isToday) {
    final slotId = booking['slotId'] as String;
    final bookingData = booking['bookingData'] as Map<String, dynamic>;
    final bookedAt = bookingData['bookedAt'] as Timestamp?;
    final vehicleType = bookingData['vehicleType'] as String? ?? 'UNKNOWN';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Colors.green[600],
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isToday ? 'Slot Booked for Today' : 'Slot Booked for Tomorrow',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Slot: ${slotId.toUpperCase()} • Vehicle: ${vehicleType.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (bookedAt != null)
                      Text(
                        'Booked at: ${DateFormat('MMM dd, yyyy - hh:mm a').format(bookedAt.toDate())}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (isToday ? _isLoadingTodayBooking : _isLoadingTomorrowBooking) // ✅ CHANGED: Use appropriate loading variable
                  ? null
                  : () => isToday
                  ? _cancelTodaysBooking(slotId)
                  : _cancelTomorrowsBooking(slotId),
              icon: (isToday ? _isLoadingTodayBooking : _isLoadingTomorrowBooking)
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Icon(Icons.cancel_rounded),
              label:  Text((isToday ? _isLoadingTodayBooking : _isLoadingTomorrowBooking) ? 'Canceling...' : 'Cancel Booking'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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


  // Tomorrow booking status
  Widget _buildTomorrowBookingStatus(Map<String, dynamic> bookingInfo, String slotId) {
    final exists = bookingInfo['exists'] as bool;
    final isBookedByCurrentUser = bookingInfo['isBookedByCurrentUser'] as bool;

    if (!exists) {
      return _buildSlotAvailableInfo(slotId);
    } else if (isBookedByCurrentUser) {
      return _buildBookingInfo(bookingInfo, false);
    } else {
      return _buildOtherUserBookingInfo(bookingInfo);
    }
  }

  Widget _buildCurrentUserBookingInfo(Map<String, dynamic> bookingInfo) {
    return _buildBookingInfo(bookingInfo, false);
  }

  Widget _buildOtherUserBookingInfo(Map<String, dynamic> bookingInfo) {
    final bookingData = bookingInfo['bookingData'] as Map<String, dynamic>;
    final slotId = bookingInfo['slotId'] as String;
    final bookedBy = bookingInfo['bookedBy'] as String;
    final bookedUserName = bookingData['userName'] as String? ?? bookedBy.split('@').first;
    final vehicleType = bookingData['vehicleType'] as String? ?? 'UNKNOWN';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.block_rounded,
                color: Colors.red[600],
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Slot Already Booked',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Booked by: $bookedUserName',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.red[600], size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your assigned slot is not available for tomorrow',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[700],
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



  Widget _buildSlotAvailableInfo(String slotId) {
    final isWindowOpen = isBookingWindowOpen(); // Assume this is a synchronous method

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
          Icon(
            Icons.event_available_rounded,
            color: Colors.blue[600],
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            'Slot Available for Tomorrow',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your slot ${slotId.toUpperCase()} is available for booking tomorrow',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          if (!isWindowOpen) ...[
            const SizedBox(height: 8),
            Text(
              'Booking Open 8am to 8pm, Currently Closed.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red[700],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ]
        ],
      ),
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



  Future<void> _initializeData() async {
    _userSlotFuture = fetchUserSlot();
    await _userSlotFuture;

    final userSlot = await _userSlotFuture;
    if (userSlot != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _fetchWeeklyBookingCountOptimized(userSlot['slotId'], user.email!);
      }
    }

    await _loadBookings();
    await fetchSlotRequest();
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
      _isLoadingTomorrowBooking = true;
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
              _tomorrowsBooking = bookingResults['tomorrow'];
              _isLoadingTodayBooking = false;
              _isLoadingTomorrowBooking = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTodayBooking = false;
          _isLoadingTomorrowBooking = false;
        });
        print('Error loading bookings: $e');
      }
    }
  }




  Future<Map<String, Map<String, dynamic>?>> _checkBothBookingsOptimized(
      String slotId, String userEmail) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final tomorrow = DateFormat('yyyy-MM-dd').format(
          DateTime.now().add(const Duration(days: 1)));

      // Parallel reads instead of sequential
      final futures = await Future.wait([
        FirebaseFirestore.instance
            .collection('Bookings')
            .doc(today)
            .collection('BookedToday')
            .doc(slotId)
            .get(),
        FirebaseFirestore.instance
            .collection('Bookings')
            .doc(tomorrow)
            .collection('BookedToday')
            .doc(slotId)
            .get(),
      ]);

      return {
        'today': _processBookingSnapshot(futures[0], slotId, userEmail),
        'tomorrow': _processBookingSnapshot(futures[1], slotId, userEmail),
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


  void _incrementWeeklyCount() {
    setState(() {
      _weeklyBookingCount++;
    });
  }

  void _decrementWeeklyCount() {
    setState(() {
      _weeklyBookingCount = max(0, _weeklyBookingCount - 1);
    });
  }


  Future<void> refreshData() async {
    // Clear cache to force fresh data
    _cachedUserSlot = null;
    _lastWeeklyCountFetch = null;

    setState(() {
      _userSlotFuture = fetchUserSlot();
    });
    await _userSlotFuture;

    final userSlot = await _userSlotFuture;
    if (userSlot != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _fetchWeeklyBookingCountOptimized(userSlot['slotId'], user.email!);
      }
    }

    await _loadBookings();
    await fetchSlotRequest();
// Refresh toggle settings too
  }


  Future<void> _fetchWeeklyBookingCountOptimized(String slotId, String userEmail) async {
    final now = DateTime.now();
    final today = DateTime.now(); // Add this for clarity

    // Check cache first - only fetch if older than 30 minutes OR new week
    if (_lastWeeklyCountFetch != null &&
        _isSameWeek(now, _lastWeeklyCountFetch!) &&
        now.difference(_lastWeeklyCountFetch!).inMinutes < 30) {
      return; // Use cached value
    }

    setState(() => _isLoadingWeeklyCount = true);

    try {
      final workingDays = _getWorkingDaysOfWeek(now);
      final docRefs = <Future<DocumentSnapshot>>[];

      for (DateTime day in workingDays) {

        if (day.isAfter(today)) continue;

        final dayStr = DateFormat('yyyy-MM-dd').format(day);
        docRefs.add(
            FirebaseFirestore.instance
                .collection('Bookings')
                .doc(dayStr)
                .collection('BookedToday')
                .doc(slotId)
                .get()
        );
      }

      final snapshots = await Future.wait(docRefs);

      int bookingCount = 0;
      for (var snapshot in snapshots) {
        if (snapshot.exists) {
          final data = snapshot.data()! as Map<String, dynamic>;
          if (data['bookedBy'] == userEmail) {
            bookingCount++;
          }
        }
      }

      setState(() {
        _weeklyBookingCount = bookingCount;
        _isLoadingWeeklyCount = false;
        _lastWeeklyCountFetch = now; // Cache timestamp
      });
    } catch (e) {
      print('Error fetching weekly booking count: $e');
      setState(() => _isLoadingWeeklyCount = false);
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

  Future<void> _bookSlotForTomorrow(String slotId, String vehicleType) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingTomorrowBooking = true;
    });

    try {
      final result = await _backend.bookSlotForTomorrow(
        slotId: slotId,
        vehicleType: vehicleType,
        userEmail: user.email!,
        userName: user.displayName ?? getDisplayNameFromEmail(user.email!),
      );

      _backend.showSnackBar(
        context,
        result['message'],
        isError: !result['success'],
      );

      if (result['success']) {
        await _refreshTomorrowOnly();

      }

    } catch (e) {
      _backend.showSnackBar(
        context,
        'Error booking slot: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTomorrowBooking = false;
        });
      }
    }
  }

  Future<void> _cancelTomorrowsBooking(String slotId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingTomorrowBooking = true;
    });

    try {
      final result = await _backend.cancelBookingForTomorrow(
        slotId: slotId,
        userEmail: user.email!,
      );

      _backend.showSnackBar(
        context,
        result['message'],
        isError: !result['success'],
      );

      if (result['success']) {
        await _refreshTomorrowOnly();

      }


    } catch (e) {
      _backend.showSnackBar(
        context,
        'Error canceling booking: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTomorrowBooking = false;
        });
      }
    }
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

  Future<void> _refreshTomorrowOnly() async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userSlot = await _userSlotFuture;
      if (userSlot != null) {
        final slotId = userSlot['slotId'] as String;

        // Only refresh tomorrow's booking
        final tomorrowBooking = await _checkSingleBooking(slotId, user.email!, false);

        if (mounted) {
          setState(() {
            _tomorrowsBooking = tomorrowBooking;
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

  Future<void> _cancelTodaysBooking(String slotId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingTodayBooking = true;
    });

    try {
      final result = await _backend.cancelBookingForToday(
        slotId: slotId,
        userEmail: user.email!,
      );

      if (result['success']) {
        _backend.showSnackBar(context, result['message']);
        await _refreshTodayOnly();
        _decrementWeeklyCount(); // ✅ ADD this line instead
      } else {
        _backend.showSnackBar(context, result['message'], isError: true);
      }
    } catch (e) {
      _backend.showSnackBar(context, 'Error cancelling booking: $e', isError: true);
    } finally {
      setState(() {
        _isLoadingTodayBooking = false;
      });
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
    _toggleSubscription?.cancel(); // Add this line
    super.dispose();
  }



}


