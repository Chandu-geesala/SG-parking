import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../view/splashScreen/my_splash_screen.dart';

class BookingBackend {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;


  // Helper method to get current user
  User? get currentUser => _auth.currentUser;

  // Helper method to format date for document ID
  String _formatDateForDocId(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  // Helper method to get tomorrow's date
  DateTime get tomorrowDate => DateTime.now().add(const Duration(days: 1));

  // Helper method to get today's date
  DateTime get todayDate => DateTime.now();

  // Check if booking window is open (8 AM to 8 PM)
  bool isBookingWindowOpen() {
    final now = DateTime.now();
    final open = DateTime(now.year, now.month, now.day, 8, 0, 0);
    final close = DateTime(now.year, now.month, now.day, 20, 0, 0);
    return now.isAfter(open) && now.isBefore(close);
  }



// ✅ ADD - Single unified booking method
  Future<Map<String, dynamic>> bookSlotForDate({
    required String slotId,
    required String vehicleType,
    required String userEmail,
    required String userName,
    required DateTime date,
  }) async {
    try {
      // Only check booking window for today's bookings
      final today = DateTime.now();
      final isToday = DateUtils.isSameDay(date, today);

      if (isToday && !isBookingWindowOpen()) {
        return {
          'success': false,
          'message': 'Booking window is closed. Please book between 8:00 AM - 8:00 PM',
        };
      }

      // Check if trying to book past dates
      final yesterday = today.subtract(Duration(days: 1));
      if (date.isBefore(yesterday)) {
        return {
          'success': false,
          'message': 'Cannot book slots for past dates',
        };
      }

      final dateStr = _formatDateForDocId(date);

      final result = await _firestore.runTransaction((transaction) async {
        // OPTIMIZATION: Single transaction with batch reads
        final slotRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('BookedToday')
            .doc(slotId);

        final userBookingsRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('BookedToday')
            .where('bookedBy', isEqualTo: userEmail);

        // Read operations within transaction
        final slotDoc = await transaction.get(slotRef);
        final userBookings = await userBookingsRef.limit(1).get();

        // Check if slot is already booked
        if (slotDoc.exists) {
          final bookedBy = slotDoc.data()?['bookedBy'] as String?;
          if (bookedBy == userEmail) {
            throw Exception('You have already booked this slot for ${_getDateDisplayName(date)}');
          } else {
            throw Exception('This slot is already booked by another user for ${_getDateDisplayName(date)}');
          }
        }

        // Check if user has already booked any slot for this date
        if (userBookings.docs.isNotEmpty) {
          final bookedSlot = userBookings.docs.first.id;
          throw Exception('You have already booked slot $bookedSlot for ${_getDateDisplayName(date)}');
        }

        // Create the booking within transaction
        transaction.set(slotRef, {
          'bookedBy': userEmail,
          'bookedAt': FieldValue.serverTimestamp(),
          'userName': userName,
          'vehicleType': vehicleType,
          'bookingDate': dateStr,
          'slotId': slotId,
        });

        return 'success';
      });

      return {
        'success': true,
        'message': 'Successfully booked slot $slotId for ${_getDateDisplayName(date)}!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

// ✅ ADD - Single unified cancellation method
  Future<Map<String, dynamic>> cancelBookingForDate({
    required String slotId,
    required String userEmail,
    required DateTime date,
  }) async {
    try {
      // Only check booking window for today's cancellations
      final today = DateTime.now();
      final isToday = DateUtils.isSameDay(date, today);

      if (isToday && !isBookingWindowOpen()) {
        return {
          'success': false,
          'message': 'Booking window is closed. Please cancel between 8:00 AM - 8:00 PM',
        };
      }

      // Check if trying to cancel past dates
      final yesterday = today.subtract(Duration(days: 1));
      if (date.isBefore(yesterday)) {
        return {
          'success': false,
          'message': 'Cannot cancel bookings for past dates',
        };
      }

      final dateStr = _formatDateForDocId(date);

      // OPTIMIZATION: Use transaction for atomic cancellation
      final result = await _firestore.runTransaction((transaction) async {
        final slotRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('BookedToday')
            .doc(slotId);

        final slotDoc = await transaction.get(slotRef);

        if (!slotDoc.exists) {
          throw Exception('No booking found for this slot on ${_getDateDisplayName(date)}');
        }

        final bookedBy = slotDoc.data()?['bookedBy'] as String?;
        if (bookedBy != userEmail) {
          throw Exception('You can only cancel your own booking');
        }

        // Delete within transaction
        transaction.delete(slotRef);
        return 'success';
      });

      // Fire and forget notification (outside transaction) - only for future dates
      if (!isToday) {
        _notifySlotAvailable(slotId, userEmail);
      }

      return {
        'success': true,
        'message': 'Successfully cancelled booking for ${_getDateDisplayName(date)}!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

// ✅ ADD - Helper method to get user-friendly date names
  String _getDateDisplayName(DateTime date) {
    final today = DateTime.now();
    final tomorrow = today.add(Duration(days: 1));

    if (DateUtils.isSameDay(date, today)) {
      return 'today';
    } else if (DateUtils.isSameDay(date, tomorrow)) {
      return 'tomorrow';
    } else {
      return DateFormat('MMM dd, yyyy').format(date);
    }
  }

// ✅ ADD - Get booking status for a specific date and slot
  Future<Map<String, dynamic>> getBookingStatusForDate({
    required String slotId,
    required String userEmail,
    required DateTime date,
  }) async {
    try {
      final dateStr = _formatDateForDocId(date);

      final slotDoc = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('BookedToday')
          .doc(slotId)
          .get();

      if (slotDoc.exists) {
        final data = slotDoc.data()!;
        final bookedBy = data['bookedBy'] as String;

        return {
          'exists': true,
          'isBookedByCurrentUser': bookedBy == userEmail,
          'bookedBy': bookedBy,
          'bookingData': data,
          'slotId': slotId,
          'status': bookedBy == userEmail ? 'booked' : 'unavailable',
        };
      } else {
        return {
          'exists': false,
          'isBookedByCurrentUser': false,
          'slotId': slotId,
          'status': 'available',
        };
      }
    } catch (e) {
      print('Error getting booking status for date: $e');
      return {
        'exists': false,
        'isBookedByCurrentUser': false,
        'slotId': slotId,
        'status': 'error',
        'error': e.toString(),
      };
    }
  }

// ✅ ADD - Get booking statuses for multiple dates (for weekly view)
  Future<Map<DateTime, Map<String, dynamic>>> getBookingStatusesForDates({
    required String slotId,
    required String userEmail,
    required List<DateTime> dates,
  }) async {
    try {
      Map<DateTime, Map<String, dynamic>> results = {};

      // Create futures for parallel execution
      List<Future<DocumentSnapshot>> futures = [];
      List<DateTime> datesList = [];

      for (DateTime date in dates) {
        final dateStr = _formatDateForDocId(date);
        datesList.add(date);
        futures.add(
            _firestore
                .collection('Bookings')
                .doc(dateStr)
                .collection('BookedToday')
                .doc(slotId)
                .get()
        );
      }

      // Execute all reads in parallel
      final snapshots = await Future.wait(futures);

      for (int i = 0; i < snapshots.length; i++) {
        final snapshot = snapshots[i];
        final date = datesList[i];

        if (snapshot.exists) {
          final data = snapshot.data()! as Map<String, dynamic>;
          final bookedBy = data['bookedBy'] as String;

          results[date] = {
            'exists': true,
            'isBookedByCurrentUser': bookedBy == userEmail,
            'bookedBy': bookedBy,
            'bookingData': data,
            'slotId': slotId,
            'status': bookedBy == userEmail ? 'booked' : 'unavailable',
          };
        } else {
          results[date] = {
            'exists': false,
            'isBookedByCurrentUser': false,
            'slotId': slotId,
            'status': 'available',
          };
        }
      }

      return results;
    } catch (e) {
      print('Error getting booking statuses for dates: $e');
      return {};
    }
  }


// ✅ OPTIMIZED: Single method to get user slot + availability declarations
  Future<Map<String, dynamic>> getUserSlotAndAvailabilityData(String userEmail) async {
    try {
      // Get user's assigned slot (reuse existing cached method)
      final userSlot = await _getUserAssignedSlot(userEmail);
      if (userSlot == null) {
        return {
          'success': false,
          'message': 'User has no assigned slot',
          'slotId': null,
          'declarations': <DateTime, String>{},
        };
      }

      final slotId = userSlot['slotId'] as String;
      final today = DateTime.now();
      final normalizedToday = DateTime(today.year, today.month, today.day);

      // Get declarations for the next 14 days in parallel
      List<Future<DocumentSnapshot>> futures = [];
      List<DateTime> datesToCheck = [];

      for (int i = 0; i < 14; i++) {
        final date = normalizedToday.add(Duration(days: i));
        if (date.weekday >= DateTime.monday && date.weekday <= DateTime.friday) {
          final dateStr = _formatDateForDocId(date);
          datesToCheck.add(date);
          futures.add(
              _firestore
                  .collection('Bookings')
                  .doc(dateStr)
                  .collection('AvailableToday')
                  .doc(slotId)
                  .get()
          );
        }
      }

      // Execute all reads in parallel
      final results = await Future.wait(futures);
      Map<DateTime, String> declarations = {};

      for (int i = 0; i < results.length; i++) {
        final doc = results[i];
        final date = datesToCheck[i];

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['declaredBy'] == userEmail) {
            declarations[date] = data['reason'] as String;
          }
        }
      }

      return {
        'success': true,
        'slotId': slotId,
        'slotData': userSlot['slotData'], // Include slot data if available
        'declarations': declarations,
      };

    } catch (e) {
      print('Error getting user slot and availability data: $e');
      return {
        'success': false,
        'message': e.toString(),
        'slotId': null,
        'declarations': <DateTime, String>{},
      };
    }
  }




  // ✅ OPTIMIZED: Batch save multiple declarations at once
  Future<Map<String, dynamic>> batchSaveAvailabilityDeclarations({
    required Map<DateTime, String> declarations, // Map of date -> reason
    required String userEmail,
  }) async {
    try {
      if (declarations.isEmpty) {
        return {'success': true, 'message': 'No declarations to save'};
      }

      // Get user's assigned slot once
      final userSlot = await _getUserAssignedSlot(userEmail);
      if (userSlot == null) {
        return {'success': false, 'message': 'User has no assigned slot'};
      }

      final slotId = userSlot['slotId'] as String;

      // Use batch write for multiple declarations
      final batch = _firestore.batch();
      int operationCount = 0;

      for (final entry in declarations.entries) {
        final date = entry.key;
        final reason = entry.value;
        final dateStr = _formatDateForDocId(date);

        final availabilityRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('AvailableToday')
            .doc(slotId);

        batch.set(availabilityRef, {
          'declaredBy': userEmail,
          'reason': reason,
          'slotId': slotId,
          'declaredAt': FieldValue.serverTimestamp(),
          'date': dateStr,
        }, SetOptions(merge: true)); // Use merge to update if exists

        operationCount++;

        // Firestore batch limit is 500 operations
        if (operationCount >= 500) break;
      }

      await batch.commit();

      return {
        'success': true,
        'message': 'Successfully saved $operationCount availability declarations',
      };

    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }



  // ✅ OPTIMIZED: Clear all declarations with batch delete
  Future<Map<String, dynamic>> clearAllUserAvailabilityDeclarationsOptimized(String userEmail) async {
    try {
      final userSlot = await _getUserAssignedSlot(userEmail);
      if (userSlot == null) {
        return {'success': false, 'message': 'User has no assigned slot'};
      }

      final slotId = userSlot['slotId'] as String;
      final today = DateTime.now();

      // Create batch for deletion
      final batch = _firestore.batch();
      int deleteCount = 0;

      // Check next 30 days and batch delete
      List<Future<DocumentSnapshot>> futures = [];
      List<DocumentReference> refsToCheck = [];

      for (int i = 0; i < 30; i++) {
        final date = today.add(Duration(days: i));
        final dateStr = _formatDateForDocId(date);

        final availabilityRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('AvailableToday')
            .doc(slotId);

        refsToCheck.add(availabilityRef);
        futures.add(availabilityRef.get());
      }

      // Get all documents in parallel
      final results = await Future.wait(futures);

      for (int i = 0; i < results.length; i++) {
        final doc = results[i];
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data?['declaredBy'] == userEmail) {
            batch.delete(refsToCheck[i]);
            deleteCount++;
          }
        }
      }

      if (deleteCount > 0) {
        await batch.commit();
      }

      return {
        'success': true,
        'message': deleteCount > 0
            ? 'All availability declarations cleared ($deleteCount removed)'
            : 'No availability declarations found to clear',
      };

    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

// ✅ OPTIMIZED: Enhanced user slot fetching with better caching
  static Map<String, dynamic>? _userSlotCache;
  static DateTime? _userSlotCacheTimestamp;
  static const int USER_SLOT_CACHE_MINUTES = 30; // Cache for 30 minutes

  Future<Map<String, dynamic>?> _getUserAssignedSlot(String userEmail) async {
    try {
      final now = DateTime.now();

      // Return cached result if valid
      if (_userSlotCache != null &&
          _userSlotCacheTimestamp != null &&
          now.difference(_userSlotCacheTimestamp!).inMinutes < USER_SLOT_CACHE_MINUTES) {
        return _userSlotCache;
      }

      // Try Users collection first (most efficient)
      final user = _auth.currentUser;
      if (user != null) {
        final userDoc = await _firestore.collection('Users').doc(user.uid).get();
        if (userDoc.exists && userDoc.data()?['assignedSlotId'] != null) {
          final slotId = userDoc.data()!['assignedSlotId'] as String;

          // Get slot data in same call
          final slotDoc = await _firestore.collection('Slots').doc(slotId).get();
          if (slotDoc.exists) {
            _userSlotCache = {
              'slotId': slotId,
              'slotData': slotDoc.data(),
            };
            _userSlotCacheTimestamp = now;
            return _userSlotCache;
          }
        }
      }

      // Fallback: Query Slots collection
      final slotsSnapshot = await _firestore.collection('Slots').get();

      for (var doc in slotsSnapshot.docs) {
        final data = doc.data();
        final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];

        for (var userObj in allotedTo) {
          if (userObj['email'] == userEmail) {
            _userSlotCache = {
              'slotId': doc.id,
              'slotData': data,
            };
            _userSlotCacheTimestamp = now;
            return _userSlotCache;
          }
        }
      }

      return null;
    } catch (e) {
      print('Error getting user assigned slot: $e');
      return null;
    }
  }

// ✅ OPTIMIZED: Single method to handle save/remove based on action
  Future<Map<String, dynamic>> updateUserAvailabilityDeclaration({
    required DateTime date,
    required String userEmail,
    String? reason, // null means remove, non-null means save/update
  }) async {
    try {
      final dateStr = _formatDateForDocId(date);

      // Get user's assigned slot (uses cache)
      final userSlot = await _getUserAssignedSlot(userEmail);
      if (userSlot == null) {
        return {'success': false, 'message': 'User has no assigned slot'};
      }

      final slotId = userSlot['slotId'] as String;

      await _firestore.runTransaction((transaction) async {
        final availabilityRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('AvailableToday')
            .doc(slotId);

        if (reason == null) {
          // Remove declaration
          final existingDoc = await transaction.get(availabilityRef);
          if (existingDoc.exists) {
            final existingData = existingDoc.data();
            if (existingData?['declaredBy'] == userEmail) {
              transaction.delete(availabilityRef);
            }
          }
        } else {
          // Save/update declaration
          transaction.set(availabilityRef, {
            'declaredBy': userEmail,
            'reason': reason,
            'slotId': slotId,
            'declaredAt': FieldValue.serverTimestamp(),
            'date': dateStr,
          }, SetOptions(merge: true));
        }
      });

      return {
        'success': true,
        'message': reason == null ? 'Declaration removed' : 'Declaration saved',
      };

    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }





//method to notify API about slot availability
  void _notifySlotAvailable(String slotId, String cancelledBy) async {
    try {
      final response = await http.post(
        Uri.parse('https://chandugeesala0-parksgnotify.hf.space/notify-slot-available'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'slot_id': slotId,
          'cancelled_by': cancelledBy,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('Notification API response: ${responseData['message']}');
        print('Notified users: ${responseData['successful_sends']}');
      } else {
        print('Failed to notify API: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error calling notification API: $e');
      // Don't fail the cancellation if notification fails
    }
  }



  Future<Map<String, dynamic>> cancelBookingForToday({
    required String slotId,
    required String userEmail,
  }) async {
    try {
      if (!isBookingWindowOpen()) {
        return {
          'success': false,
          'message': 'Booking window is closed. Please cancel between 8:00 AM - 8:00 PM',
        };
      }

      final todayDateStr = _formatDateForDocId(todayDate);

      // OPTIMIZATION: Use transaction
      final result = await _firestore.runTransaction((transaction) async {
        final slotRef = _firestore
            .collection('Bookings')
            .doc(todayDateStr)
            .collection('BookedToday')
            .doc(slotId);

        final slotDoc = await transaction.get(slotRef);

        if (!slotDoc.exists) {
          throw Exception('No booking found for this slot today');
        }

        final bookedBy = slotDoc.data()?['bookedBy'] as String?;
        if (bookedBy != userEmail) {
          throw Exception('You can only cancel your own booking');
        }

        transaction.delete(slotRef);
        return 'success';
      });

      return {
        'success': true,
        'message': 'Successfully cancelled today\'s booking!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }



  Future<List<Map<String, dynamic>>> getAvailableSlotsForToday() async {
    try {
      final todayDateStr = _formatDateForDocId(todayDate);

      // OPTIMIZATION: Use batch read with Future.wait instead of sequential reads
      final futures = [
        _firestore.collection('Slots').get(),
        _firestore
            .collection('Bookings')
            .doc(todayDateStr)
            .collection('BookedToday')
            .get()
      ];

      final results = await Future.wait(futures);
      final slotsQuery = results[0] as QuerySnapshot;
      final bookedSlotsQuery = results[1] as QuerySnapshot;

      // Rest of the logic remains the same
      final bookedSlotIds = bookedSlotsQuery.docs.map((doc) => doc.id).toSet();

      List<Map<String, dynamic>> availableSlots = [];
      for (var slotDoc in slotsQuery.docs) {
        String slotId = slotDoc.id;
        if (!bookedSlotIds.contains(slotId)) {
          Map<String, dynamic> slotData = slotDoc.data() as Map<String, dynamic>;
          availableSlots.add({
            'slotId': slotId,
            'slotData': slotData,
            'vehicleType': slotData['vehicleType'] ?? 'BIKE',
            'slotPriority': slotData['slotPriority'] ?? 'permanent',
            'alloted_to': (slotData['alloted_to'] as List?)?.map((item) => item['name'] ?? 'Unknown').toList() ?? [],
            'VehicleCompatibility': slotData['VehicleCompatibility'],
          });
        }
      }

      availableSlots.sort((a, b) => a['slotId'].compareTo(b['slotId']));
      return availableSlots;
    } catch (e) {
      print('Error getting available slots for today: $e');
      return [];
    }
  }





// Optional: Get available slots by vehicle type for today
  Future<List<Map<String, dynamic>>> getAvailableSlotsByVehicleType(String vehicleType) async {
    try {
      final allAvailableSlots = await getAvailableSlotsForToday();

      // Filter by vehicle type
      return allAvailableSlots.where((slot) {
        final slotVehicleType = slot['slotData']['vehicleType']?.toString().toUpperCase() ?? 'BIKE';
        return slotVehicleType == vehicleType.toUpperCase();
      }).toList();

    } catch (e) {
      print('Error getting available slots by vehicle type: $e');
      return [];
    }
  }


  Future<Map<String, Map<String, dynamic>?>> getUserBookings(String userEmail) async {
    try {
      final todayDateStr = _formatDateForDocId(DateTime.now());
      final tomorrowDateStr = _formatDateForDocId(DateTime.now().add(Duration(days: 1)));

      // OPTIMIZATION: Parallel execution of both queries
      final futures = [
        _firestore
            .collection('Bookings')
            .doc(todayDateStr)
            .collection('BookedToday')
            .where('bookedBy', isEqualTo: userEmail)
            .limit(1)
            .get(),
        _firestore
            .collection('Bookings')
            .doc(tomorrowDateStr)
            .collection('BookedToday')
            .where('bookedBy', isEqualTo: userEmail)
            .limit(1)
            .get()
      ];

      final results = await Future.wait(futures);
      final todayQuery = results[0] as QuerySnapshot;
      final tomorrowQuery = results[1] as QuerySnapshot;

      return {
        'today': todayQuery.docs.isNotEmpty ? {
          'slotId': todayQuery.docs.first.id,
          'bookingData': todayQuery.docs.first.data(),
        } : null,
        'tomorrow': tomorrowQuery.docs.isNotEmpty ? {
          'slotId': tomorrowQuery.docs.first.id,
          'bookingData': tomorrowQuery.docs.first.data(),
        } : null,
      };
    } catch (e) {
      print('Error getting user bookings: $e');
      return {'today': null, 'tomorrow': null};
    }
  }





  Future<Map<String, bool>> checkMultipleSlotsAvailability(List<String> slotIds, DateTime date) async {
    try {
      final dateStr = _formatDateForDocId(date);
      Map<String, bool> availability = {};

      // OPTIMIZATION: Single query to get all bookings for the date
      final allBookingsQuery = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('BookedToday')
          .get();

      final bookedSlotIds = allBookingsQuery.docs.map((doc) => doc.id).toSet();

      // Check availability for all requested slots
      for (String slotId in slotIds) {
        availability[slotId] = !bookedSlotIds.contains(slotId);
      }

      return availability;
    } catch (e) {
      print('Error checking multiple slots availability: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> getUserRequestsSummary() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {};

      // OPTIMIZATION: Single query with composite index
      final query = await _firestore
          .collection('requests')
          .where('email', isEqualTo: user.email!)
          .orderBy('timestamp', descending: true) // Order by timestamp
          .get();

      if (query.docs.isEmpty) {
        return {
          'hasRequests': false,
          'totalRequests': 0,
          'pendingRequests': 0,
          'latestRequest': null,
          'requestsByType': <String, int>{},
          'pendingByType': <String, int>{},
        };
      }

      // Process all data in single pass
      Map<String, int> requestsByType = {'NewReq': 0, 'TodReq': 0, 'AltReq': 0};
      Map<String, int> pendingByType = {'NewReq': 0, 'TodReq': 0, 'AltReq': 0};
      int pendingCount = 0;
      Map<String, dynamic>? latestRequest;

      for (var doc in query.docs) {
        final data = doc.data();
        final type = data['type'] as String?;
        final status = data['status'] as String?;

        if (latestRequest == null) {
          latestRequest = data; // First doc is latest due to orderBy
        }

        if (type != null && requestsByType.containsKey(type)) {
          requestsByType[type] = requestsByType[type]! + 1;

          if (status == 'pending') {
            pendingCount++;
            pendingByType[type] = pendingByType[type]! + 1;
          }
        }
      }

      return {
        'hasRequests': true,
        'totalRequests': query.docs.length,
        'pendingRequests': pendingCount,
        'latestRequest': latestRequest,
        'requestsByType': requestsByType,
        'pendingByType': pendingByType,
        'allRequests': query.docs.map((doc) => doc.data()).toList(),
      };
    } catch (e) {
      print('Error getting user requests summary: $e');
      return {};
    }
  }





  // Get all bookings for a specific date
  Future<List<Map<String, dynamic>>> getBookingsForDate(DateTime date) async {
    try {
      final dateStr = _formatDateForDocId(date);

      final bookingsQuery = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('BookedToday')
          .get();

      return bookingsQuery.docs.map((doc) => {
        'slotId': doc.id,
        'bookingData': doc.data(),
      }).toList();
    } catch (e) {
      print('Error getting bookings for date: $e');
      return [];
    }
  }


  Future<Map<String, int>> getUserBookingStats(String userEmail, {int days = 30}) async {
    try {
      final endDate = DateTime.now();
      final startDate = endDate.subtract(Duration(days: days));

      // OPTIMIZATION: Use date range instead of individual day queries
      List<String> dateStrings = [];
      for (int i = 0; i < days; i++) {
        final date = endDate.subtract(Duration(days: i));
        dateStrings.add(_formatDateForDocId(date));
      }

      // OPTIMIZATION: Parallel queries for all dates
      final futures = dateStrings.map((dateStr) =>
          _firestore
              .collection('Bookings')
              .doc(dateStr)
              .collection('BookedToday')
              .where('bookedBy', isEqualTo: userEmail)
              .limit(1) // User can only have one booking per day
              .get()
      ).toList();

      final results = await Future.wait(futures);
      int totalBookings = results.where((query) => query.docs.isNotEmpty).length;

      return {
        'totalBookingsLast${days}Days': totalBookings,
        'currentMonth': endDate.month,
        'currentYear': endDate.year,
        'averageBookingsPerWeek': ((totalBookings / days) * 7).round(),
      };
    } catch (e) {
      print('Error getting user booking stats: $e');
      return {'totalBookingsLast${days}Days': 0};
    }
  }



  // Helper method to show snackbar
  void showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }


  Future<void> signOut(BuildContext context) async {
    try {
      await _auth.signOut();

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // This clears all stored preferences

      // Navigate to MySplashScreen and clear the navigation stack
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => MysplashScreen()),
            (route) => false,
      );

    } catch (e) {
      print('Error signing out: $e');
      throw e;
    }
  }




  Future<Map<String, dynamic>?> getProfileData() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      // Get user type from SharedPreferences (cached)
      //final userType = await _authService.getUserTypeFromPrefs();
      final userType = 'await _authService.getUserTypeFromPrefs()';

      String collectionName;
      if (userType == 'admin') {
        collectionName = 'admins';
      } else {
        collectionName = 'allowed_persons';
      }

      final doc = await _firestore.collection(collectionName).doc(user.email).get();
      return doc.data();
    } catch (e) {
      print('Error fetching profile data: $e');
      return null;
    }
  }

  // Add these methods to your BookingBackend class

// Helper method to generate display name from email
  String getDisplayNameFromEmail(String email) {
    final usernamePart = email.split('@').first;
    final words = usernamePart.split('.').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).toList();
    return words.join(' ');
  }

  static Map<String, String> _vehicleTypeCache = {};
  static DateTime? _cacheTimestamp;
  static const int CACHE_DURATION_MINUTES = 10; // Short cache for vehicle types



  Future<Map<String, String?>> getMultipleSlotVehicleTypes(List<String> slotIds) async {
    try {
      // OPTIMIZATION: Refresh cache if expired (vehicle types rarely change)
      final now = DateTime.now();
      if (_cacheTimestamp == null ||
          now.difference(_cacheTimestamp!).inMinutes > CACHE_DURATION_MINUTES) {

        final slotsQuery = await _firestore.collection('Slots').get();
        _vehicleTypeCache.clear();

        for (var doc in slotsQuery.docs) {
          final data = doc.data();
          _vehicleTypeCache[doc.id] = data['vehicleType'] as String? ?? 'BIKE';
        }
        _cacheTimestamp = now;
      }

      // Return vehicle types for requested slots
      Map<String, String?> result = {};
      for (String slotId in slotIds) {
        result[slotId] = _vehicleTypeCache[slotId];
      }

      return result;
    } catch (e) {
      print('Error fetching multiple slot vehicle types: $e');
      return {};
    }
  }





// 1. New Request - for users who don't have any slot
  Future<Map<String, dynamic>> requestNewSlot() async {
    try {
      // Get current user
      User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        return {
          'success': false,
          'message': 'No user logged in',
        };
      }

      // Get user email
      String userEmail = currentUser.email ?? '';

      // Create request data (no vehicle type for new requests since no slot exists yet)
      Map<String, dynamic> requestData = {
        'email': userEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'NewReq',
        'status': 'pending',
        // No vehicleType for new requests since they don't have a slot yet
      };

      // Add to Firestore 'requests' collection
      await _firestore.collection('requests').add(requestData);

      return {
        'success': true,
        'message': 'New slot request submitted successfully!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error submitting new slot request: ${e.toString()}',
      };
    }
  }

// 2. Today Request - for users who want to request today's slot
  Future<Map<String, dynamic>> requestTodaySlot(String currentSlotId) async {
    try {
      // Get current user
      User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        return {
          'success': false,
          'message': 'No user logged in',
        };
      }

      // Get user email
      String userEmail = currentUser.email ?? '';

      // Get vehicle type from the current slot
      String? vehicleType = await _getSlotVehicleType(currentSlotId);

      // Create request data
      Map<String, dynamic> requestData = {
        'email': userEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'TodReq',
        'status': 'pending',
        'currentSlotId': currentSlotId,
        'vehicleType': vehicleType ?? 'Unknown', // Add vehicle type from slot
      };

      // Add to Firestore 'requests' collection
      await _firestore.collection('requests').add(requestData);

      return {
        'success': true,
        'message': 'Today slot request submitted successfully!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error submitting today slot request: ${e.toString()}',
      };
    }
  }

// 3. Alternative Request - for users who want alternative slot
  Future<Map<String, dynamic>> requestAlternativeSlot(String slotId) async {
    try {
      // Get current user
      User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        return {
          'success': false,
          'message': 'No user logged in',
        };
      }

      // Get user email
      String userEmail = currentUser.email ?? '';

      // Get vehicle type from the current slot
      String? vehicleType = await _getSlotVehicleType(slotId);

      // Create request data
      Map<String, dynamic> requestData = {
        'email': userEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'AltReq',
        'status': 'pending',
        'currentSlotId': slotId, // Added missing currentSlotId
        'vehicleType': vehicleType ?? 'Unknown', // Add vehicle type from slot
      };

      // Add to Firestore 'requests' collection
      await _firestore.collection('requests').add(requestData);

      return {
        'success': true,
        'message': 'Alternative slot request submitted successfully!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error submitting alternative slot request: ${e.toString()}',
      };
    }
  }





  Future<String?> _getSlotVehicleType(String slotId) async {
    try {
      // Use the batch method for single slot (still benefits from caching)
      final vehicleTypes = await getMultipleSlotVehicleTypes([slotId]);
      return vehicleTypes[slotId];
    } catch (e) {
      print('Error fetching slot vehicle type: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> deleteAllUserRequests() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'No user logged in'};
      }

      final userEmail = currentUser.email ?? '';

      // OPTIMIZATION: Query with limit and use batch delete
      const batchSize = 500; // Firestore batch limit
      int totalDeleted = 0;

      while (true) {
        final requestsQuery = await _firestore
            .collection('requests')
            .where('email', isEqualTo: userEmail)
            .limit(batchSize)
            .get();

        if (requestsQuery.docs.isEmpty) break;

        final batch = _firestore.batch();
        for (var doc in requestsQuery.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
        totalDeleted += requestsQuery.docs.length;

        // If we got less than batch size, we're done
        if (requestsQuery.docs.length < batchSize) break;
      }

      return {
        'success': true,
        'message': totalDeleted > 0
            ? 'All requests deleted successfully! ($totalDeleted requests removed)'
            : 'No requests found to delete',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error deleting requests: ${e.toString()}',
      };
    }
  }



// Helper method to get request type display name
  String getRequestTypeDisplayName(String requestType) {
    switch (requestType) {
      case 'NewReq':
        return 'New Slot Request';
      case 'TodReq':
        return 'Today Slot Request';
      case 'AltReq':
        return 'Alternative Slot Request';
      default:
        return 'Unknown Request Type';
    }
  }

// Helper method to get all pending requests count by type
  Future<Map<String, int>> getPendingRequestsCountByType() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {};

      final query = await _firestore
          .collection('requests')
          .where('email', isEqualTo: user.email)
          .where('status', isEqualTo: 'pending')
          .get();

      Map<String, int> counts = {
        'NewReq': 0,
        'TodReq': 0,
        'AltReq': 0,
      };

      for (var doc in query.docs) {
        final type = doc.data()['type'] as String?;
        if (type != null && counts.containsKey(type)) {
          counts[type] = counts[type]! + 1;
        }
      }

      return counts;
    } catch (e) {
      print('Error getting pending requests count: $e');
      return {};
    }
  }




}