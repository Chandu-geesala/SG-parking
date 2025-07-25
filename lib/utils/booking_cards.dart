import 'dart:async';

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:park_sg/utils/slot_allotment_card.dart';


import '../viewModel/bookingBackend.dart';
import 'package:park_sg/utils/theme_provider.dart';

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
// ✅ REPLACE with this
  Future<Map<String, dynamic>?> _userSlotFuture = Future.value(null);

  final BookingBackend _backend = BookingBackend();
  bool _isLoadingTodayBooking = false;


  Map<DateTime, Map<String, dynamic>> _bookingStatuses = {};

  Set<DateTime> _unavailableDates = {};

  Map<DateTime, String> _datePreferences = {}; // 'use', 'leave', 'wfh'
  DateTime? _selectedDateForOptions;


  // Add these state variables after existing ones


  Map<String, List<Map<String, dynamic>>> _userSlotRequests = {};
  bool _isLoadingRequests = false;
  StreamSubscription<QuerySnapshot>? _requestsSubscription;





  // Booking state variables
  Map<String, dynamic>? _todaysBooking;

  bool _isLoadingBookings = false;
// Add these new state variables after existing ones
  bool _allowRequests = false;
  bool _allowAutoAllotment = false;
  StreamSubscription<DocumentSnapshot>? _toggleSubscription;
  bool _isLoadingToggles = false;
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


  Future<void> _loadUserSlotRequests() async {
    print('🔍 _loadUserSlotRequests() called - mounted: $mounted');

    if (!mounted) return;

    setState(() {
      _isLoadingRequests = true;
    });
    print('📱 Set _isLoadingRequests = true');

    try {
      final user = FirebaseAuth.instance.currentUser;
      final userSlot = await _userSlotFuture;

      print('👤 User: ${user?.email}');
      print('🅿️ User slot: $userSlot');

      if (user != null && userSlot != null) {
        final slotId = userSlot['slotId'] as String;
        final userEmail = user.email!;

        print('🎯 Looking for requests for slot: $slotId, user: $userEmail');

        // Get current date and next 5 working days
        final workingDays = _getNextWorkingDays(5);
        print('📅 Working days: ${workingDays.map((d) => DateFormat('yyyy-MM-dd').format(d)).toList()}');

        // Query requests for user's slot for these dates
        List<Future<QuerySnapshot>> futures = [];

        for (DateTime date in workingDays) {
          final dateStr = DateFormat('yyyy-MM-dd').format(date);
          print('🔍 Adding query for date: $dateStr');
          futures.add(
              FirebaseFirestore.instance
                  .collection('requests')
                  .doc(dateStr)
                  .collection('slots')
                  .where('slotId', isEqualTo: slotId)
                  .where('status.finalStatus', isEqualTo: 'pending') // Still filter by pending
                  .get()
          );
        }

        print('⏳ Executing ${futures.length} parallel queries...');
        final results = await Future.wait(futures);
        Map<String, List<Map<String, dynamic>>> requestsByDate = {};

        for (int i = 0; i < results.length; i++) {
          final dateStr = DateFormat('yyyy-MM-dd').format(workingDays[i]);
          final querySnapshot = results[i];

          print('📊 Date $dateStr: Found ${querySnapshot.docs.length} documents');

          List<Map<String, dynamic>> dayRequests = [];
          for (var doc in querySnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            print('📄 Document ${doc.id}: $data');

            // Check if current user is one of the requested users
            final requestedTo = data['requestedTo'] as Map<String, dynamic>? ?? {};
            print('🎯 RequestedTo: $requestedTo');
            print('🔍 User email in requestedTo: ${requestedTo.containsKey(userEmail)}');

            if (requestedTo.containsKey(userEmail)) {
              // ✅ NEW: Check if current user has already responded
              final userRequestData = requestedTo[userEmail] as Map<String, dynamic>? ?? {};
              final hasUserResponded = userRequestData['responded'] == true;

              print('👤 User request data: $userRequestData');
              print('✅ Has user responded: $hasUserResponded');

              // ✅ ONLY show request if user hasn't responded yet
              if (!hasUserResponded) {
                print('✅ Found request for user that needs response!');
                dayRequests.add({
                  ...data,
                  'requestId': doc.id,
                  'dateStr': dateStr,
                  'date': workingDays[i],
                });
              } else {
                print('⏭️ User already responded, skipping request');
              }
            } else {
              print('❌ Request not for this user');
            }
          }

          if (dayRequests.isNotEmpty) {
            requestsByDate[dateStr] = dayRequests;
            print('📝 Added ${dayRequests.length} requests for $dateStr');
          }
        }

        print('🎉 Total requests by date: $requestsByDate');

        if (mounted) {
          setState(() {
            _userSlotRequests = requestsByDate;
          });
          print('✅ Updated state with ${requestsByDate.length} dates having requests');
        }
      } else {
        print('❌ User or userSlot is null');
      }
    } catch (e) {
      print('❌ Error loading user slot requests: $e');
      print('📍 Stack trace: ${StackTrace.current}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRequests = false;
        });
        print('📱 Set _isLoadingRequests = false');
      }
    }
  }


  // Add this method to handle accept/reject responses
  Future<void> _respondToSlotRequest(
      String requestId,
      String dateStr,
      bool isAccepted,
      String slotId,
      ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userEmail = user.email!;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text(isAccepted ? 'Accepting request...' : 'Rejecting request...'),
            ],
          ),
        ),
      );

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final requestRef = FirebaseFirestore.instance
            .collection('requests')
            .doc(dateStr)
            .collection('slots')
            .doc(requestId);

        final requestDoc = await transaction.get(requestRef);
        if (!requestDoc.exists) {
          throw Exception('Request not found');
        }

        final data = requestDoc.data()!;
        final status = Map<String, dynamic>.from(data['status'] ?? {});
        final requestedTo = Map<String, dynamic>.from(data['requestedTo'] ?? {});

        if (isAccepted) {
          status['acceptedBy'] = {
            ...Map<String, dynamic>.from(status['acceptedBy'] ?? {}),
            userEmail: FieldValue.serverTimestamp(),
          };
        } else {
          status['rejectedBy'] = {
            ...Map<String, dynamic>.from(status['rejectedBy'] ?? {}),
            userEmail: FieldValue.serverTimestamp(),
          };
        }

        // Update user's response in requestedTo
        if (requestedTo.containsKey(userEmail)) {
          requestedTo[userEmail]['responded'] = true;
          requestedTo[userEmail]['response'] = isAccepted ? 'accepted' : 'rejected';
          requestedTo[userEmail]['respondedAt'] = FieldValue.serverTimestamp();
        }

        // Check if all users have responded
        final totalUsers = data['metadata']['totalSlotUsers'] as int;
        final acceptedCount = (status['acceptedBy'] as Map? ?? {}).length;
        final rejectedCount = (status['rejectedBy'] as Map? ?? {}).length;

        if (acceptedCount == totalUsers) {
          status['finalStatus'] = 'approved';
        } else if (rejectedCount > 0) {
          status['finalStatus'] = 'rejected';
        }

        status['lastUpdated'] = FieldValue.serverTimestamp();

        transaction.update(requestRef, {
          'status': status,
          'requestedTo': requestedTo,
        });
      });

      Navigator.of(context).pop(); // Close loading dialog

      _backend.showSnackBar(
        context,
        isAccepted ? 'Request accepted successfully!' : 'Request rejected successfully!',
      );

      // Refresh requests
      await _loadUserSlotRequests();

    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      _backend.showSnackBar(
        context,
        'Error responding to request: $e',
        isError: true,
      );
    }
  }





// Add this widget to display slot requests
  Widget _buildSlotRequestsCard() {
    if (_isLoadingRequests) {
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
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading slot requests...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    if (_userSlotRequests.isEmpty) {
      return SizedBox.shrink(); // Don't show card if no requests
    }

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
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.notifications_active,
                  color: Colors.orange[600],
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Slot Requests',
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
                      'Pending requests for your slot',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_userSlotRequests.values.fold(0, (sum, list) => sum + list.length)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Requests List
          ...(_userSlotRequests.entries.map((entry) {
            final dateStr = entry.key;
            final requests = entry.value;
            return Column(
              children: requests.map((request) => _buildRequestTile(request, dateStr)).toList(),
            );
          }).toList()),
        ],
      ),
    );
  }

  Widget _buildRequestTile(Map<String, dynamic> request, String dateStr) {
    final requestedBy = request['requestedBy'] as String;
    final slotId = request['slotId'] as String;
    final requestId = request['requestId'] as String;
    final date = request['date'] as DateTime;
    final requesterVehicleType = request['metadata']?['requesterVehicleType'] as String? ?? 'UNKNOWN';

    final dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final requesterName = _backend.getDisplayNameFromEmail(requestedBy);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]?.withOpacity(0.5)
            : Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.person_outline,
                  color: Colors.orange[600],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      requesterName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'wants to use your slot',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getVehicleColor(requesterVehicleType).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getVehicleIcon(requesterVehicleType),
                      size: 12,
                      color: _getVehicleColor(requesterVehicleType),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      requesterVehicleType,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _getVehicleColor(requesterVehicleType),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Request Details
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '${dayNames[date.weekday]}, ${monthNames[date.month]} ${date.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  'Slot: ${slotId.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _respondToSlotRequest(requestId, dateStr, false, slotId),
                  icon: Icon(Icons.close, size: 18),
                  label: Text('Reject'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _respondToSlotRequest(requestId, dateStr, true, slotId),
                  icon: Icon(Icons.check, size: 18),
                  label: Text('Accept'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }




  @override
  void initState() {
    super.initState();

    // Initialize with normalized today's date
    final today = DateTime.now();
    _selectedBookingDate = DateTime(today.year, today.month, today.day);

    _initializeData();
    _loadPreferencesFromBackend();
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


  void _toggleDateAvailability(DateTime date) {
    setState(() {
      _selectedDateForOptions = date;
    });
    _showPreferenceOptions(date);
  }

  void _showPreferenceOptions(DateTime date) {
    final dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

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
                        '${dayNames[date.weekday]}, ${monthNames[date.month]} ${date.day}',
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
// ✅ REPLACE the onTap in _buildPreferenceOption with this:
      onTap: () async {
        final normalizedDate = DateTime(date.year, date.month, date.day);

        // Show loading state
        setState(() {
          _isUpdatingPreferences = true;
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
              setState(() {
                _datePreferences[normalizedDate] = value;
                _unavailableDates.add(normalizedDate);
              });

              _backend.showSnackBar(context, result['message']);
            } else {
              _backend.showSnackBar(context, result['message'], isError: true);
            }
          }
        } catch (e) {
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
          const SizedBox(height: 20),

          // Weekly Calendar
          _buildWeeklyCalendar(),

          const SizedBox(height: 16),

          // Info and Action Buttons
          _buildParkingPreferenceActions(),
        ],
      ),
    );
  }

  Widget _buildWeeklyCalendar() {
    final workingDays = _getNextWorkingDays(5);

    return Column(
      children: [
        // Desktop/Tablet Layout - Single row for 5 working days
        if (MediaQuery.of(context).size.width > 600) ...[
          Row(
            children: workingDays.map((date) =>
                Expanded(child: _buildDayTile(date))
            ).toList(),
          ),
        ] else ...[
          // Mobile Layout - 2 rows (3 + 2)
          Column(
            children: [
              Row(
                children: workingDays.take(3).map((date) =>
                    Expanded(child: _buildDayTile(date))
                ).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ...workingDays.skip(3).map((date) =>
                      Expanded(child: _buildDayTile(date))
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



  Widget _buildDayTile(DateTime date) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final isUnavailable = _datePreferences.containsKey(date);
    final isPast = date.isBefore(DateTime.now().subtract(const Duration(days: 1)));

    final dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];


    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: isPast ? null : () {
          // Add this method to toggle unavailable dates
          _toggleDateAvailability(date);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: _getDayTileColor(isToday, false, isUnavailable, isPast), // weekends removed
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _getDayTileBorderColor(isToday, false, isUnavailable, isPast), // weekends removed
              width: isToday ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dayNames[date.weekday],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _getDayTileTextColor(isToday, false, isUnavailable, isPast), // weekends removed
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _getDayTileTextColor(isToday, false, isUnavailable, isPast), // weekends removed
                ),
              ),
              const SizedBox(height: 2),
              Text(
                monthNames[date.month],
                style: TextStyle(
                  fontSize: 10,
                  color: _getDayTileTextColor(isToday, false, isUnavailable, isPast).withOpacity(0.8), // weekends removed
                ),
              ),
              const SizedBox(height: 4),

// In _buildDayTile method, replace the bottom icon section with:
              const SizedBox(height: 4),


              if (_datePreferences.containsKey(date))
                _getPreferenceIcon(date)
              else if (!isPast)
                Icon(
                  Icons.add_circle_outline,
                  size: 14,
                  color: Colors.green[600],
                )
              else
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: Colors.grey[400],
                ),


            ],
          ),
        ),
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



  Color _getDayTileColor(bool isToday, bool isWeekend, bool isUnavailable, bool isPast) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPast) {
      return isDark ? Colors.grey[800]! : Colors.grey[100]!;
    }
    if (isUnavailable) {
      return isDark ? Colors.red[900]!.withOpacity(0.3) : Colors.red[50]!;
    }
    if (isToday) {
      return Theme.of(context).colorScheme.primary.withOpacity(isDark ? 0.3 : 0.1);
    }
    return isDark ? Colors.green[900]!.withOpacity(0.2) : Colors.green[50]!;
  }

  Color _getDayTileBorderColor(bool isToday, bool isWeekend, bool isUnavailable, bool isPast) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPast) {
      return isDark ? Colors.grey[600]! : Colors.grey[300]!;
    }
    if (isUnavailable) {
      return isDark ? Colors.red[400]! : Colors.red[300]!;
    }
    if (isToday) {
      return Theme.of(context).colorScheme.primary;
    }
    return isDark ? Colors.green[400]! : Colors.green[300]!;
  }

  Color _getDayTileTextColor(bool isToday, bool isWeekend, bool isUnavailable, bool isPast) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPast) {
      return isDark ? Colors.grey[400]! : Colors.grey[500]!;
    }
    if (isUnavailable) {
      return isDark ? Colors.red[300]! : Colors.red[700]!;
    }
    if (isToday) {
      return Theme.of(context).colorScheme.primary;
    }
    return isDark ? Colors.green[300]! : Colors.green[700]!;
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

          // Date Dropdown Section
          _buildDateDropdown(),

          const SizedBox(height: 20),

          // Booking Status Card
          _buildBookingStatusCard(),
        ],
      ),
    );
  }

  Widget _buildDateDropdown() {
    final workingDays = _getNextWorkingDays(5);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]!.withOpacity(0.5)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.date_range,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Select Date',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<DateTime>(
                value: workingDays.contains(_selectedBookingDate) ? _selectedBookingDate : workingDays.first,
                isExpanded: true,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  color: Theme.of(context).colorScheme.primary,
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                items: workingDays.map((DateTime date) {
                  return DropdownMenuItem<DateTime>(
                    value: date,
                    child: _buildDropdownItem(date),
                  );
                }).toList(),
                onChanged: (DateTime? newDate) {
                  if (newDate != null) {
                    setState(() {
                      _selectedBookingDate = newDate;
                    });
                    // ✅ This will trigger the FutureBuilder to refresh
                    _loadBookingStatusForDate(newDate);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildDropdownItem(DateTime date) {
    final today = DateTime.now();
    final isToday = DateUtils.isSameDay(date, today);
    final dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthNames = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isToday
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            dayNames[date.weekday],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isToday
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${monthNames[date.month]} ${date.day}, ${date.year}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        if (isToday)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Today',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }



  Widget _buildBookingStatusCard() {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedSelectedDate = DateTime(_selectedBookingDate.year, _selectedBookingDate.month, _selectedBookingDate.day);
    final isSelectedDateToday = DateUtils.isSameDay(_selectedBookingDate, normalizedToday);

    // ✅ NEW: Check if user declared unavailability for this date FIRST
    if (_datePreferences.containsKey(normalizedSelectedDate)) {
      return _buildUserDeclarationCard(normalizedSelectedDate);
    }

    // If selected date is today, use _todaysBooking data
    if (isSelectedDateToday) {
      if (_isLoadingTodayBooking) {
        return _buildLoadingBookingStatusCard();
      }

      // Use existing today's booking data
      BookingStatus bookingStatus = BookingStatus.available;

      if (_todaysBooking != null) {
        final exists = _todaysBooking!['exists'] as bool;
        final isBookedByCurrentUser = _todaysBooking!['isBookedByCurrentUser'] as bool;

        if (exists) {
          if (isBookedByCurrentUser) {
            bookingStatus = BookingStatus.booked;
          } else {
            bookingStatus = BookingStatus.unavailable;
          }
        }
      }

      return _buildBookingStatusCardContent(bookingStatus);
    }

    // For other dates, use the existing FutureBuilder logic
    if (_isLoadingBookingStatus) {
      return _buildLoadingBookingStatusCard();
    }

    return FutureBuilder<BookingStatus>(
      future: _getBookingStatusForDate(_selectedBookingDate),
      builder: (context, snapshot) {
        BookingStatus bookingStatus = BookingStatus.available;

        if (snapshot.hasData) {
          bookingStatus = snapshot.data!;
        } else if (snapshot.hasError) {
          return _buildErrorBookingStatusCard();
        }

        return _buildBookingStatusCardContent(bookingStatus);
      },
    );
  }



  Widget _buildUserDeclarationCard(DateTime date) {
    final preference = _datePreferences[date];
    final dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    String title = '';
    String subtitle = '';
    IconData icon = Icons.info_outline;
    Color primaryColor = Colors.grey[600]!;
    Color backgroundColor = Colors.grey[50]!;

    switch (preference) {
      case 'leave':
        title = 'You Declared Leave';
        subtitle = 'You have marked yourself as on leave for this day';
        icon = Icons.beach_access;
        primaryColor = Colors.orange[600]!;
        backgroundColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.orange[900]!.withOpacity(0.2)
            : Colors.orange[50]!;
        break;
      case 'wfh':
        title = 'You Declared Work From Home';
        subtitle = 'You have marked yourself as working from home for this day';
        icon = Icons.home_work;
        primaryColor = Colors.blue[600]!;
        backgroundColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.blue[900]!.withOpacity(0.2)
            : Colors.blue[50]!;
        break;
      default:
        title = 'You Declared Unavailable';
        subtitle = 'You have marked yourself as unavailable for this day';
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
                  '${dayNames[date.weekday]}, ${monthNames[date.month]} ${date.day}, ${date.year}',
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
    final dayNames = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

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
                            '${dayNames[date.weekday]}, ${monthNames[date.month]} ${date.day}',
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
                  future: _userSlotFuture, // ✅ Use existing user slot data
                  builder: (context, userSlotSnapshot) {
                    if (userSlotSnapshot.connectionState == ConnectionState.waiting) {
                      return _buildLoadingState();
                    }

                    if (userSlotSnapshot.hasError || userSlotSnapshot.data == null) {
                      return _buildErrorState('Unable to get user vehicle type');
                    }

                    // ✅ Extract vehicle type from existing cached data
                    final userSlotData = userSlotSnapshot.data!['slotData'] as Map<String, dynamic>;
                    final userVehicleType = userSlotData['vehicleType'] as String? ?? 'BIKE';

                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: _backend.getAvailableSlotsWithUserDetails(
                        date: date,
                        vehicleTypeFilter: userVehicleType, // ✅ Pass user's vehicle type
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

                        return _buildAvailableSlotsList(availableSlots, scrollController);
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

// ✅ NEW: Available slots list widget
  Widget _buildAvailableSlotsList(List<Map<String, dynamic>> availableSlots, ScrollController scrollController) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
      itemCount: availableSlots.length,
      itemBuilder: (context, index) {
        final slot = availableSlots[index];
        return _buildAvailableSlotCard(slot);
      },
    );
  }

// ✅ NEW: Individual slot card widget
  Widget _buildAvailableSlotCard(Map<String, dynamic> slot) {
    final slotId = slot['slotId'] as String;
    final vehicleType = slot['vehicleType'] as String;
    final slotUsers = slot['slotUsers'] as int;
    final declarations = List<Map<String, dynamic>>.from(slot['declarations'] ?? []);
    final slotData = slot['slotData'] as Map<String, dynamic>?;
    final allotedUsers = List<Map<String, dynamic>>.from(slot['allotedUsers'] ?? []);

    final slotPriority = slotData?['slotPriority'] as String? ?? 'permanent';
    final vehicleCompatibility = slotData?['VehicleCompatibility'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
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
                      '$vehicleType • $slotPriority',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Available',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[700],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Availability info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All $slotUsers slot users declared unavailability',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
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
              'Slot Users ($slotUsers)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            childrenPadding: const EdgeInsets.only(top: 8),
            children: declarations.map((declaration) {
              final userEmail = declaration['declaredBy'] as String;
              final reason = declaration['reason'] as String;
              final userName = _getUserNameFromEmail(userEmail, allotedUsers);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _getReasonColor(reason),
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
                        color: _getReasonColor(reason).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getReasonDisplayText(reason),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _getReasonColor(reason),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Action button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _requestSlotFromAvailable(
                slotId,
                _selectedBookingDate, // Pass the selected date
                declarations, // Pass the declarations list
              ),
              icon: Icon(Icons.send, size: 18),
              label: Text('Request This Slot'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
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


  void _requestSlotFromAvailable(String slotId, DateTime requestDate, List<Map<String, dynamic>> declarations) async {
    Navigator.pop(context); // Close bottom sheet

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

      // Extract emails from declarations
      final slotUsersEmails = declarations
          .map((declaration) => declaration['declaredBy'] as String)
          .toList();

      // ✅ Use new method
      final result = await _backend.createSlotRequestForDate(
        requestDate: requestDate,
        targetSlotId: slotId,
        slotUsersEmails: slotUsersEmails,
      );

      Navigator.of(context).pop(); // Close loading dialog

      if (result['success']) {
        _backend.showSnackBar(context, result['message']);
      } else {
        _backend.showSnackBar(context, result['message'], isError: true);
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      _backend.showSnackBar(context, 'Error submitting request: $e', isError: true);
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
    final userSlot = await _userSlotFuture;

    if (user == null || userSlot == null) return;

    final slotId = userSlot['slotId'] as String;

    setState(() {
      _isLoadingBookingStatus = true;
    });

    try {
      final result = await _backend.cancelBookingForDate(
        slotId: slotId,
        userEmail: user.email!,
        date: date,
      );

      if (result['success']) {
        _backend.showSnackBar(context, result['message']);
        _loadBookingStatusForDate(date); // Refresh the status
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
          const SizedBox(height: 10),

          _buildSlotRequestsCard(),
          const SizedBox(height: 16),
          _buildrulesCard(),
          const SizedBox(height: 10),
          _buildParkingUsageCard(),
          const SizedBox(height: 16),
          _buildWeeklyBookingCard(),


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








  Widget _buildTodaysBookingStatus(Map<String, dynamic> bookingInfo,
      String slotId) {
    final exists = bookingInfo['exists'] as bool;
    final isBookedByCurrentUser = bookingInfo['isBookedByCurrentUser'] as bool;

    if (!exists) {
      return _buildTodaysSlotAvailableInfo(slotId);
    } else if (isBookedByCurrentUser) {
      return _buildBookingInfo(bookingInfo);
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
             onPressed: () => _bookSlotForDate(DateTime.now()),
              label: Text('Book Slot for Today'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
              ),
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

    // ✅ Use appropriate loading state based on whether it's today or not
    final isToday = DateUtils.isSameDay(date, DateTime.now());

    setState(() {
      if (isToday) {
        _isLoadingTodayBooking = true;
      } else {
        _isLoadingBookingStatus = true;
      }
    });

    try {
      // ✅ Get the actual vehicle type from slot data
      final slotData = userSlot['slotData'] as Map<String, dynamic>;
      final vehicleType = slotData['vehicleType'] as String? ?? 'BIKE';

      final result = await _backend.bookSlotForDate(
        slotId: slotId,
        vehicleType: vehicleType, // ✅ Use actual vehicle type
        userEmail: user.email!,
        userName: user.displayName ?? _backend.getDisplayNameFromEmail(user.email!),
        date: date,
      );

      if (result['success']) {
        _backend.showSnackBar(context, result['message']);

        // ✅ Refresh appropriate data based on date
        if (isToday) {
          await _refreshTodayOnly();
        } else {
          _loadBookingStatusForDate(date); // Refresh the status
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
                      'Slot  Booked for Today',
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



  Widget _buildCurrentUserBookingInfo(Map<String, dynamic> bookingInfo) {
    return _buildBookingInfo(bookingInfo);
  }



  Widget _buildBookingInfo(Map<String, dynamic> booking) {
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
                      'Slot Booked for Today',
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
              onPressed: _isLoadingTodayBooking
                  ? null
                  : () => _cancelTodaysBooking(slotId),
              icon: _isLoadingTodayBooking
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Icon(Icons.cancel_rounded),
              label: Text(_isLoadingTodayBooking ? 'Canceling...' : 'Cancel Booking'),
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
    // Initialize _userSlotFuture first
    setState(() {
      _userSlotFuture = fetchUserSlot();
    });

    // Wait for user slot data
    final userSlot = await _userSlotFuture;

    // ✅ ADD: Load requests after user slot is ready
    await _loadUserSlotRequests();

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
    _bookingStatuses.clear(); // ✅ ADD this line

    // Reinitialize _userSlotFuture
    setState(() {
      _userSlotFuture = fetchUserSlot();
    });

    await _userSlotFuture;
    await _loadUserSlotRequests();
    await _loadBookings();
    await fetchSlotRequest();
    await _loadPreferencesFromBackend();
    await _loadBookingStatusForDate(_selectedBookingDate); // ✅ ADD this line
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


  Future<void> _cancelTodaysBooking(String slotId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingTodayBooking = true;
    });

    try {
      final result = await _backend.cancelBookingForDate(
        slotId: slotId,
        userEmail: user.email!,
        date: DateTime.now(),
      );

      if (result['success']) {
        _backend.showSnackBar(context, result['message']);
        await _refreshTodayOnly();
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
    _toggleSubscription?.cancel();

    _requestsSubscription?.cancel();
    super.dispose();
  }



}


