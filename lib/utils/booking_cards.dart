import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../viewModel/bookingBackend.dart';

class BookingCards extends StatefulWidget {
  const BookingCards({Key? key}) : super(key: key);

  @override
  State<BookingCards> createState() => _BookingCardsState();
}

class _BookingCardsState extends State<BookingCards> {
  late Future<Map<String, dynamic>?> _userSlotFuture;
  final BookingBackend _backend = BookingBackend();

  // Booking state variables
  Map<String, dynamic>? _todaysBooking;
  Map<String, dynamic>? _tomorrowsBooking;
  bool _isLoadingBookings = false;

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
  Future<void> _fetchWeeklyBookingCount(String slotId, String userEmail) async {
    setState(() {
      _isLoadingWeeklyCount = true;
    });

    try {
      final now = DateTime.now();
      final workingDays = _getWorkingDaysOfWeek(now);
      int bookingCount = 0;

      for (DateTime day in workingDays) {
        // Skip future dates (don't count bookings beyond today)
        if (day.isAfter(now)) continue;

        final dayStr = DateFormat('yyyy-MM-dd').format(day);
        final slotDoc = await FirebaseFirestore.instance
            .collection('Bookings')
            .doc(dayStr)
            .collection('BookedToday')
            .doc(slotId)
            .get();

        if (slotDoc.exists) {
          final data = slotDoc.data()!;
          final bookedBy = data['bookedBy'] as String;
          if (bookedBy == userEmail) {
            bookingCount++;
          }
        }
      }

      setState(() {
        _weeklyBookingCount = bookingCount;
        _isLoadingWeeklyCount = false;
      });
    } catch (e) {
      print('Error fetching weekly booking count: $e');
      setState(() {
        _isLoadingWeeklyCount = false;
      });
    }
  }



  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    _userSlotFuture = fetchUserSlot();
    await _userSlotFuture;

    final userSlot = await _userSlotFuture;
    if (userSlot != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _fetchWeeklyBookingCount(userSlot['slotId'], user.email!);
      }
    }

    await _loadBookings();
    await fetchSlotRequest();
  }


  Future<Map<String, dynamic>?> fetchUserSlot() async {
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
      _isLoadingBookings = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userSlot = await _userSlotFuture;
        String? userAssignedSlotId;
        if (userSlot != null) {
          userAssignedSlotId = userSlot['slotId'] as String;
        }

        Map<String, dynamic>? todaysSlotStatus;
        Map<String, dynamic>? tomorrowsBooking;

        if (userAssignedSlotId != null) {
          todaysSlotStatus =
          await _checkTodaysSlotBooking(userAssignedSlotId, user.email!);
          tomorrowsBooking =
          await _checkTomorrowsSlotBooking(userAssignedSlotId, user.email!);
        }

        if (mounted) {
          setState(() {
            _todaysBooking = todaysSlotStatus;
            _tomorrowsBooking = tomorrowsBooking;
            _isLoadingBookings = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingBookings = false;
        });
        print('Error loading bookings: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> _checkTodaysSlotBooking(String slotId,
      String userEmail) async {
    try {
      final todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final slotDoc = await FirebaseFirestore.instance
          .collection('Bookings')
          .doc(todayDateStr)
          .collection('BookedToday')
          .doc(slotId)
          .get();

      if (slotDoc.exists) {
        final data = slotDoc.data()!;
        final bookedBy = data['bookedBy'] as String;

        return {
          'slotId': slotId,
          'bookingData': data,
          'isBookedByCurrentUser': bookedBy == userEmail,
          'bookedBy': bookedBy,
          'exists': true,
        };
      } else {
        return {
          'slotId': slotId,
          'exists': false,
          'isBookedByCurrentUser': false,
        };
      }
    } catch (e) {
      print('Error checking today\'s slot booking: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _checkTomorrowsSlotBooking(String slotId,
      String userEmail) async {
    try {
      final tomorrowDateStr = DateFormat('yyyy-MM-dd').format(
          DateTime.now().add(const Duration(days: 1)));

      final slotDoc = await FirebaseFirestore.instance
          .collection('Bookings')
          .doc(tomorrowDateStr)
          .collection('BookedToday')
          .doc(slotId)
          .get();

      if (slotDoc.exists) {
        final data = slotDoc.data()!;
        final bookedBy = data['bookedBy'] as String;

        return {
          'slotId': slotId,
          'bookingData': data,
          'isBookedByCurrentUser': bookedBy == userEmail,
          'bookedBy': bookedBy,
          'exists': true,
        };
      } else {
        return {
          'slotId': slotId,
          'exists': false,
          'isBookedByCurrentUser': false,
        };
      }
    } catch (e) {
      print('Error checking tomorrow\'s slot booking: $e');
      return null;
    }
  }

  Future<void> refreshData() async {
    setState(() {
      _userSlotFuture = fetchUserSlot();
    });
    await _userSlotFuture;

    final userSlot = await _userSlotFuture;
    if (userSlot != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _fetchWeeklyBookingCount(userSlot['slotId'], user.email!);
      }
    }

    await _loadBookings();
    await fetchSlotRequest();
  }

  Future<void> _bookSlotForTomorrow(String slotId, String vehicleType) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingBookings = true;
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
        await _loadBookings();
        // Refresh weekly count after successful booking
        await _fetchWeeklyBookingCount(slotId, user.email!);
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
          _isLoadingBookings = false;
        });
      }
    }
  }

  Future<void> _cancelTomorrowsBooking(String slotId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingBookings = true;
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
        await _loadBookings();
        // Refresh weekly count after successful cancellation
        await _fetchWeeklyBookingCount(slotId, user.email!);
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
          _isLoadingBookings = false;
        });
      }
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
      color: Colors.blue[600],
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _userSlotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(color: Colors.red[400], fontSize: 16),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
                  color: _getVehicleColor(vehicleType).withOpacity(0.1),
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
                    const Text(
                      'Your Assigned Slot',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      slotId.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
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

  Widget _buildTodaysBookingCard(String slotId) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
              Icon(Icons.today_rounded, color: Colors.purple[600], size: 24),
              const SizedBox(width: 12),
              const Text(
                'Today\'s Booking',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingBookings)
            const Center(
              child: CircularProgressIndicator(),
            )
          else
            if (_todaysBooking != null)
              _buildTodaysBookingStatus(_todaysBooking!, slotId)
            else
              _buildNoBookingInfo(true),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
              Icon(Icons.calendar_today_rounded, color: Colors.indigo[600], size: 24),
              const SizedBox(width: 12),
              const Text(
                "Tomorrow's Booking",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Weekly Booking Count Display
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasReachedWeeklyLimit ? Colors.red[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasReachedWeeklyLimit ? Colors.red[200]! : Colors.green[200]!,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasReachedWeeklyLimit ? Icons.block_rounded : Icons.timelapse,
                  color: hasReachedWeeklyLimit ? Colors.red[600] : Colors.blue[230],
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
                          color: hasReachedWeeklyLimit ? Colors.red[700] : Colors.green[700],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Used: $_weeklyBookingCount/3 slots this week',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasReachedWeeklyLimit ? Colors.red[600] : Colors.green[600],
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
                        hasReachedWeeklyLimit ? Colors.red[600]! : Colors.green[600]!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Booking Status Section
          if (_isLoadingBookings)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
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
                _buildNoBookingInfo(false),
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
                  backgroundColor: Color(0xFF6C5CE7),
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
          ] else if (hasReachedWeeklyLimit && isSlotAvailable && isWindowOpen) ...[
            // Show "Reached Weekly Limit" button when user has reached the limit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null, // Disabled button
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text("Reached Max Bookings This Week"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[400],
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

          // Info Section - Always show for context
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue[600], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Booking Rules:",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "• Booking window: 8:00 AM - 8:00 PM daily\n• Maximum 3 bookings per week (Mon-Fri)\n• Working days only",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[600],
                        ),
                      ),
                      if (!isWindowOpen) ...[
                        const SizedBox(height: 4),
                        Text(
                          "⚠️ Booking window is currently closed",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
            'Slot Available for Today',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your slot ${slotId.toUpperCase()} is available today',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue[600],
                    size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Contact admin to book this slot for today',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[700],
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

  Widget _buildTodaysOtherUserBookingInfo(Map<String, dynamic> bookingInfo) {
    final bookingData = bookingInfo['bookingData'] as Map<String, dynamic>;
    final slotId = bookingInfo['slotId'] as String;
    final bookedBy = bookingInfo['bookedBy'] as String;
    final bookedUserName = bookingData['userName'] as String? ?? bookedBy
        .split('@')
        .first;

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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                Icon(Icons.info_outline_rounded, color: Colors.red[600],
                    size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your assigned slot is not available for today',
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
          if (!isToday) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoadingBookings
                    ? null
                    : () => _cancelTomorrowsBooking(slotId),
                icon: _isLoadingBookings
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Icon(Icons.cancel_rounded),
                label: Text(_isLoadingBookings ? 'Canceling...' : 'Cancel Booking'),
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
        ],
      ),
    );
  }

  Widget _buildNoBookingInfo(bool isToday) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_busy_rounded,
            color: Colors.orange[600],
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            isToday ? 'No Slot Booked for Today' : 'No Slot Booked for Tomorrow',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isToday
                ? 'You haven\'t booked this slot for today'
                : 'You haven\'t booked this slot for tomorrow',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
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
        ],
      ),
    );
  }

  Widget _buildSlotUsersCard(List<dynamic> allotedTo) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
              Icon(Icons.group_rounded, color: Colors.blue[600], size: 24),
              const SizedBox(width: 12),
              Text(
                'Slot Users (${allotedTo.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
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
}



