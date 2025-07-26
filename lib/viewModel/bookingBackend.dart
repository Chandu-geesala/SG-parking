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


  // ✅ UPDATED METHOD: Cancel booking and reset status if needed
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

      // ✅ UPDATED: Use transaction for atomic cancellation with status update
      final result = await _firestore.runTransaction((transaction) async {
        final slotRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('BookedToday')
            .doc(slotId);

        // ✅ NEW: Reference to AvailableToday document
        final availabilityRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('AvailableToday')
            .doc(slotId);

        // Read operations within transaction
        final slotDoc = await transaction.get(slotRef);
        final availabilityDoc = await transaction.get(availabilityRef);

        if (!slotDoc.exists) {
          throw Exception('No booking found for this slot on ${_getDateDisplayName(date)}');
        }

        final bookingData = slotDoc.data() as Map<String, dynamic>;
        final bookedBy = bookingData['bookedBy'] as String?;
        if (bookedBy != userEmail) {
          throw Exception('You can only cancel your own booking');
        }

        // ✅ NEW: Check if this is an alternative booking
        final bookingType = bookingData['bookingType'] as String? ?? 'regular';
        final isAlternativeBooking = bookingType == 'alternative';

        // Delete the booking from BookedToday
        transaction.delete(slotRef);

        // ✅ NEW: If it's an alternative booking, reset status in AvailableToday
        if (isAlternativeBooking && availabilityDoc.exists) {
          final availabilityData = availabilityDoc.data() as Map<String, dynamic>;
          final currentStatus = availabilityData['status'] as String? ?? 'notbooked';

          // Only reset if status is currently 'booked' and was booked by this user
          final bookedByInAvailability = availabilityData['bookedBy'] as String?;
          if (currentStatus == 'booked' && bookedByInAvailability == userEmail) {
            transaction.update(availabilityRef, {
              'status': 'notbooked',
              'bookedBy': FieldValue.delete(), // Remove bookedBy field
              'bookedAt': FieldValue.delete(), // Remove bookedAt field
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          }
        }

        return {
          'bookingType': bookingType,
          'wasAlternative': isAlternativeBooking,
        };
      });

      // Fire and forget notification (outside transaction) - only for future dates
      if (!isToday) {
        _notifySlotAvailable(slotId, userEmail);
      }

      // ✅ NEW: Different success messages based on booking type
      final wasAlternative = result['wasAlternative'] as bool;
      final successMessage = wasAlternative
          ? 'Successfully cancelled alternative booking for ${_getDateDisplayName(date)}! Slot is now available for others.'
          : 'Successfully cancelled booking for ${_getDateDisplayName(date)}!';

      return {
        'success': true,
        'message': successMessage,
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
          final declarationsArray = List<Map<String, dynamic>>.from(data['declarations'] ?? []);

          // Find this user's declaration
          for (var declaration in declarationsArray) {
            if (declaration['declaredBy'] == userEmail) {
              declarations[date] = declaration['reason'] as String;
              break;
            }
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



  // ✅ MODIFIED: Add slotUsers count to updateUserAvailabilityDeclaration
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
      // Get vehicle type from cached slot data
      final vehicleType = userSlot['slotData']?['vehicleType'] as String? ?? 'BIKE';
      // ✅ NEW: Get slot users count from cached slot data
      final allotedTo = userSlot['slotData']?['alloted_to'] as List<dynamic>? ?? [];
      final slotUsers = allotedTo.length;

      await _firestore.runTransaction((transaction) async {
        final availabilityRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('AvailableToday')
            .doc(slotId);

        final existingDoc = await transaction.get(availabilityRef);

        if (reason == null) {
          // Remove declaration
          if (existingDoc.exists) {
            final data = existingDoc.data() as Map<String, dynamic>;
            final declarations = List<Map<String, dynamic>>.from(data['declarations'] ?? []);

            // Remove this user's declaration
            declarations.removeWhere((declaration) => declaration['declaredBy'] == userEmail);

            if (declarations.isEmpty) {
              // Delete the document if no declarations left
              transaction.delete(availabilityRef);
            } else {
              // Update with remaining declarations + update timestamp at document level
              transaction.update(availabilityRef, {
                'declarations': declarations,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
            }
          }
        } else {
          // Save/update declaration
          final now = DateTime.now().millisecondsSinceEpoch;
          final newDeclaration = {
            'declaredBy': userEmail,
            'reason': reason,
            'declaredAt': now,
          };

          if (existingDoc.exists) {
            // Document exists, update the declarations array
            final data = existingDoc.data() as Map<String, dynamic>;
            final declarations = List<Map<String, dynamic>>.from(data['declarations'] ?? []);

            // Remove existing declaration from this user if any
            declarations.removeWhere((declaration) => declaration['declaredBy'] == userEmail);

            // Add new declaration
            declarations.add(newDeclaration);

            transaction.update(availabilityRef, {
              'declarations': declarations,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          } else {
            // Document doesn't exist, create new one
            transaction.set(availabilityRef, {
              'date': dateStr,
              'slotId': slotId,
              'vehicleType': vehicleType,
              'slotUsers': slotUsers, // ✅ NEW: Add slot users count
              'declarations': [newDeclaration],
              'createdAt': FieldValue.serverTimestamp(),
              'lastUpdated': FieldValue.serverTimestamp(),
              'status': 'notbooked',
            });
          }
        }
      });

      return {
        'success': true,
        'message': reason == null
            ? 'Thanks for the update! ✅'
            : 'Thanks for informing us! 🎉',
      };

    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableSlotsFromDeclarations({
    required DateTime date,
    String? vehicleTypeFilter,
  }) async {
    try {
      final dateStr = _formatDateForDocId(date);

      // ✅ OPTIMIZED: Filter at database level to reduce data transfer and costs
      Query query = _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('AvailableToday')
          .where('status', isEqualTo: 'notbooked'); // ✅ NEW: Only get unbooked slots

      // ✅ OPTIMIZED: Add vehicle type filter at DB level if specified
      if (vehicleTypeFilter != null) {
        query = query.where('vehicleType', isEqualTo: vehicleTypeFilter.toUpperCase());
      }

      final availabilityQuery = await query.get();

      List<Map<String, dynamic>> availableSlots = [];

      for (var doc in availabilityQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final slotId = data['slotId'] as String;
        final vehicleType = data['vehicleType'] as String? ?? 'BIKE';
        final slotUsers = data['slotUsers'] as int? ?? 0;
        final declarations = List<Map<String, dynamic>>.from(data['declarations'] ?? []);
        final status = data['status'] as String? ?? 'notbooked'; // ✅ NEW: Extract status

        // ✅ OPTIMIZED: Since we already filtered by status at DB level, just check declarations
        final hasDeclarations = declarations.isNotEmpty && slotUsers > 0;
        final isFullyAvailable = declarations.length >= slotUsers && slotUsers > 0;

        // ✅ OPTIMIZED: Removed status check since we filtered at DB level
        if (hasDeclarations) {
          availableSlots.add({
            'slotId': slotId,
            'vehicleType': vehicleType,
            'slotUsers': slotUsers,
            'declarationsCount': declarations.length,
            'declarations': declarations,
            'date': dateStr,
            'isAvailable': true,
            'isFullyAvailable': isFullyAvailable,
            'availabilityScore': isFullyAvailable ? 1 : 0,
            'status': status, // ✅ NEW: Include status in response
          });
        }
      }

      // ✅ OPTIMIZED: Sort by availability score (fully available first), then by slot ID
      availableSlots.sort((a, b) {
        final scoreComparison = (b['availabilityScore'] as int).compareTo(a['availabilityScore'] as int);
        if (scoreComparison != 0) return scoreComparison;
        return a['slotId'].toString().compareTo(b['slotId'].toString());
      });

      return availableSlots;
    } catch (e) {
      print('Error getting available slots from declarations: $e');
      return [];
    }
  }







  Future<Map<DateTime, List<Map<String, dynamic>>>> getAvailableSlotsForDates({
    required List<DateTime> dates,
    String? vehicleTypeFilter,
  }) async {
    try {
      Map<DateTime, List<Map<String, dynamic>>> results = {};

      // ✅ OPTIMIZED: Create optimized futures with status filter
      List<Future<QuerySnapshot>> futures = [];
      List<DateTime> datesList = [];

      for (DateTime date in dates) {
        final dateStr = _formatDateForDocId(date);
        datesList.add(date);

        // ✅ OPTIMIZED: Build query with status filter at DB level
        Query query = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('AvailableToday')
            .where('status', isEqualTo: 'notbooked'); // ✅ NEW: Filter by status

        // ✅ OPTIMIZED: Add vehicle type filter if specified
        if (vehicleTypeFilter != null) {
          query = query.where('vehicleType', isEqualTo: vehicleTypeFilter.toUpperCase());
        }

        futures.add(query.get());
      }

      // ✅ OPTIMIZED: Execute all reads in parallel
      final queryResults = await Future.wait(futures);

      for (int i = 0; i < queryResults.length; i++) {
        final querySnapshot = queryResults[i];
        final date = datesList[i];

        List<Map<String, dynamic>> availableSlots = [];

        for (var doc in querySnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final slotId = data['slotId'] as String;
          final vehicleType = data['vehicleType'] as String? ?? 'BIKE';
          final slotUsers = data['slotUsers'] as int? ?? 0;
          final declarations = List<Map<String, dynamic>>.from(data['declarations'] ?? []);
          final status = data['status'] as String? ?? 'notbooked'; // ✅ NEW: Extract status

          // ✅ OPTIMIZED: Check if all users declared (since status is already filtered)
          final isFullyDeclared = declarations.length >= slotUsers && slotUsers > 0;

          if (isFullyDeclared) {
            availableSlots.add({
              'slotId': slotId,
              'vehicleType': vehicleType,
              'slotUsers': slotUsers,
              'declarationsCount': declarations.length,
              'declarations': declarations,
              'date': _formatDateForDocId(date),
              'isAvailable': true,
              'status': status, // ✅ NEW: Include status
            });
          }
        }

        // ✅ OPTIMIZED: Sort by slot ID for consistent ordering
        availableSlots.sort((a, b) => a['slotId'].toString().compareTo(b['slotId'].toString()));
        results[date] = availableSlots;
      }

      return results;
    } catch (e) {
      print('Error getting available slots for dates: $e');
      return {};
    }
  }


  Future<Map<String, dynamic>> getAvailableSlotsSummary({
    required List<DateTime> dates,
    String? vehicleTypeFilter,
  }) async {
    try {
      final availableSlotsData = await getAvailableSlotsForDates(
        dates: dates,
        vehicleTypeFilter: vehicleTypeFilter,
      );

      // ✅ OPTIMIZED: Single pass calculation
      Map<DateTime, int> availableCountPerDate = {};
      Map<String, int> slotAvailabilityCount = {};
      Set<String> allAvailableSlots = {};

      for (final entry in availableSlotsData.entries) {
        final date = entry.key;
        final slots = entry.value;

        availableCountPerDate[date] = slots.length;

        for (final slot in slots) {
          final slotId = slot['slotId'] as String;
          allAvailableSlots.add(slotId);
          slotAvailabilityCount[slotId] = (slotAvailabilityCount[slotId] ?? 0) + 1;
        }
      }

      // ✅ OPTIMIZED: Find slots available on all requested dates
      final fullyAvailableSlots = slotAvailabilityCount.entries
          .where((entry) => entry.value == dates.length)
          .map((entry) => entry.key)
          .toList();

      return {
        'availableSlotsPerDate': availableSlotsData,
        'availableCountPerDate': availableCountPerDate,
        'totalUniqueSlots': allAvailableSlots.length,
        'fullyAvailableSlots': fullyAvailableSlots,
        'slotAvailabilityCount': slotAvailabilityCount,
        'dateRange': {
          'start': dates.isNotEmpty ? _formatDateForDocId(dates.first) : null,
          'end': dates.isNotEmpty ? _formatDateForDocId(dates.last) : null,
          'totalDays': dates.length,
        },
      };
    } catch (e) {
      print('Error getting available slots summary: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> checkSlotAvailabilityFromDeclarations({
    required String slotId,
    required DateTime date,
  }) async {
    try {
      final dateStr = _formatDateForDocId(date);

      final doc = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('AvailableToday')
          .doc(slotId)
          .get();

      if (!doc.exists) {
        return {
          'isAvailable': false,
          'reason': 'No declarations found for this slot',
          'slotId': slotId,
          'date': dateStr,
          'status': 'unknown',
        };
      }

      final data = doc.data() as Map<String, dynamic>;
      final slotUsers = data['slotUsers'] as int? ?? 0;
      final declarations = List<Map<String, dynamic>>.from(data['declarations'] ?? []);
      final vehicleType = data['vehicleType'] as String? ?? 'BIKE';
      final status = data['status'] as String? ?? 'notbooked'; // ✅ NEW: Extract status

      final isFullyDeclared = declarations.length >= slotUsers && slotUsers > 0;
      final isNotBooked = status == 'notbooked'; // ✅ NEW: Check status

      // ✅ NEW: Only available if fully declared AND not booked
      final isAvailable = isFullyDeclared && isNotBooked;

      return {
        'isAvailable': isAvailable,
        'reason': !isFullyDeclared
            ? 'Only ${declarations.length} of ${slotUsers} users declared'
            : !isNotBooked
            ? 'Slot is already booked'
            : 'All ${slotUsers} users declared unavailability and slot is not booked',
        'slotId': slotId,
        'vehicleType': vehicleType,
        'slotUsers': slotUsers,
        'declarationsCount': declarations.length,
        'declarations': declarations,
        'date': dateStr,
        'status': status, // ✅ NEW: Include status
      };
    } catch (e) {
      print('Error checking slot availability from declarations: $e');
      return {
        'isAvailable': false,
        'reason': 'Error: ${e.toString()}',
        'slotId': slotId,
        'status': 'error',
      };
    }
  }

// ✅ OPTIMIZED: Get available slots with user details and status filter
  Future<List<Map<String, dynamic>>> getAvailableSlotsWithUserDetails({
    required DateTime date,
    String? vehicleTypeFilter,
  }) async {
    try {
      // ✅ OPTIMIZED: Use the already optimized method
      final availableSlots = await getAvailableSlotsFromDeclarations(
        date: date,
        vehicleTypeFilter: vehicleTypeFilter,
      );

      if (availableSlots.isEmpty) return [];

      // ✅ OPTIMIZED: Batch fetch slot details
      final slotIds = availableSlots.map((slot) => slot['slotId'] as String).toList();

      // ✅ OPTIMIZED: Single query to get all slot details
      final slotDetailsQuery = await _firestore
          .collection('Slots')
          .where(FieldPath.documentId, whereIn: slotIds)
          .get();

      // ✅ OPTIMIZED: Create lookup map for O(1) access
      final slotDetailsMap = <String, Map<String, dynamic>>{};
      for (var doc in slotDetailsQuery.docs) {
        slotDetailsMap[doc.id] = doc.data();
      }

      // ✅ OPTIMIZED: Single pass to combine data
      List<Map<String, dynamic>> detailedSlots = [];
      for (final slot in availableSlots) {
        final slotId = slot['slotId'] as String;
        final slotData = slotDetailsMap[slotId];

        if (slotData != null) {
          final allotedTo = slotData['alloted_to'] as List<dynamic>? ?? [];

          detailedSlots.add({
            ...slot,
            'slotData': slotData,
            'allotedUsers': allotedTo,
            'slotPriority': slotData['slotPriority'] ?? 'permanent',
            'vehicleCompatibility': slotData['VehicleCompatibility'],
          });
        }
      }

      return detailedSlots;
    } catch (e) {
      print('Error getting available slots with user details: $e');
      return [];
    }
  }


// ✅ MODIFIED: Add slotUsers count to batchSaveAvailabilityDeclarations
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
      // Get vehicle type from cached slot data
      final vehicleType = userSlot['slotData']?['vehicleType'] as String? ?? 'BIKE';
      // ✅ NEW: Get slot users count from cached slot data
      final allotedTo = userSlot['slotData']?['alloted_to'] as List<dynamic>? ?? [];
      final slotUsers = allotedTo.length;

      // Process declarations in batches due to Firestore transaction limits
      final entries = declarations.entries.toList();
      final batchSize = 400;
      int totalOperations = 0;

      for (int i = 0; i < entries.length; i += batchSize) {
        final batch = entries.skip(i).take(batchSize).toList();

        await _firestore.runTransaction((transaction) async {
          // Read all documents first
          Map<String, DocumentSnapshot> docs = {};
          for (final entry in batch) {
            final dateStr = _formatDateForDocId(entry.key);
            final docRef = _firestore
                .collection('Bookings')
                .doc(dateStr)
                .collection('AvailableToday')
                .doc(slotId);
            docs[dateStr] = await transaction.get(docRef);
          }

          // Then update all documents
          for (final entry in batch) {
            final date = entry.key;
            final reason = entry.value;
            final dateStr = _formatDateForDocId(date);

            final availabilityRef = _firestore
                .collection('Bookings')
                .doc(dateStr)
                .collection('AvailableToday')
                .doc(slotId);

            final existingDoc = docs[dateStr]!;
            final now = DateTime.now().millisecondsSinceEpoch;
            final newDeclaration = {
              'declaredBy': userEmail,
              'reason': reason,
              'declaredAt': now,
            };

            if (existingDoc.exists) {
              // Document exists, update declarations array
              final data = existingDoc.data() as Map<String, dynamic>;
              final declarationsArray = List<Map<String, dynamic>>.from(data['declarations'] ?? []);

              // Remove existing declaration from this user
              declarationsArray.removeWhere((declaration) => declaration['declaredBy'] == userEmail);

              // Add new declaration
              declarationsArray.add(newDeclaration);

              transaction.update(availabilityRef, {
                'declarations': declarationsArray,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
            } else {
              // Document doesn't exist, create new one
              transaction.set(availabilityRef, {
                'date': dateStr,
                'slotId': slotId,
                'vehicleType': vehicleType,
                'slotUsers': slotUsers, // ✅ NEW: Add slot users count
                'declarations': [newDeclaration],
                'createdAt': FieldValue.serverTimestamp(),
                'lastUpdated': FieldValue.serverTimestamp(),
                'status': 'notbooked',
              });
            }
            totalOperations++;
          }
        });
      }

      return {
        'success': true,
        'message': 'Successfully saved $totalOperations availability declarations',
      };

    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }






  Future<Map<String, dynamic>> clearAllUserAvailabilityDeclarationsOptimized(String userEmail) async {
    try {
      final userSlot = await _getUserAssignedSlot(userEmail);
      if (userSlot == null) {
        return {'success': false, 'message': 'User has no assigned slot'};
      }

      final slotId = userSlot['slotId'] as String;
      final today = DateTime.now();

      int deleteCount = 0;

      // Process in batches to avoid transaction limits
      for (int i = 0; i < 30; i += 10) {
        await _firestore.runTransaction((transaction) async {
          // Get documents for this batch
          Map<String, DocumentSnapshot> docs = {};
          List<String> dateStrs = [];

          for (int j = i; j < i + 10 && j < 30; j++) {
            final date = today.add(Duration(days: j));
            final dateStr = _formatDateForDocId(date);
            dateStrs.add(dateStr);

            final docRef = _firestore
                .collection('Bookings')
                .doc(dateStr)
                .collection('AvailableToday')
                .doc(slotId);
            docs[dateStr] = await transaction.get(docRef);
          }

          // Update documents
          for (final dateStr in dateStrs) {
            final availabilityRef = _firestore
                .collection('Bookings')
                .doc(dateStr)
                .collection('AvailableToday')
                .doc(slotId);

            final doc = docs[dateStr]!;
            if (doc.exists) {
              final data = doc.data() as Map<String, dynamic>;
              final declarationsArray = List<Map<String, dynamic>>.from(data['declarations'] ?? []);

              // Check if this user has any declarations
              final userDeclarationExists = declarationsArray.any((declaration) => declaration['declaredBy'] == userEmail);

              if (userDeclarationExists) {
                // Remove this user's declarations
                declarationsArray.removeWhere((declaration) => declaration['declaredBy'] == userEmail);
                deleteCount++;

                if (declarationsArray.isEmpty) {
                  // Delete document if no declarations left
                  transaction.delete(availabilityRef);
                } else {
                  // Update with remaining declarations
                  transaction.update(availabilityRef, {'declarations': declarationsArray});
                }
              }
            }
          }
        });
      }

      return {
        'success': true,
        'message': deleteCount > 0
            ? 'All your availability declarations cleared ($deleteCount removed)'
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


  Future<List<Map<String, dynamic>>> getSlotDeclarationsForDate({
    required String slotId,
    required DateTime date,
  }) async {
    try {
      final dateStr = _formatDateForDocId(date);

      final doc = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('AvailableToday')
          .doc(slotId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final declarationsArray = List<Map<String, dynamic>>.from(data['declarations'] ?? []);

        // Add additional metadata to each declaration
        return declarationsArray.map((declaration) => {
          ...declaration,
          'slotId': slotId,
          'date': dateStr,
        }).toList();
      }

      return [];
    } catch (e) {
      print('Error getting slot declarations for date: $e');
      return [];
    }
  }

// ✅ NEW: Get declarations for multiple dates for a slot
  Future<Map<DateTime, List<Map<String, dynamic>>>> getSlotDeclarationsForDates({
    required String slotId,
    required List<DateTime> dates,
  }) async {
    try {
      Map<DateTime, List<Map<String, dynamic>>> results = {};

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
                .collection('AvailableToday')
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
          final data = snapshot.data() as Map<String, dynamic>;
          final declarationsArray = List<Map<String, dynamic>>.from(data['declarations'] ?? []);

          // Add metadata to each declaration
          results[date] = declarationsArray.map((declaration) => {
            ...declaration,
            'slotId': slotId,
            'date': _formatDateForDocId(date),
          }).toList();
        } else {
          results[date] = [];
        }
      }

      return results;
    } catch (e) {
      print('Error getting slot declarations for dates: $e');
      return {};
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


// ✅ UPDATED METHOD: Book an available slot and update status
  Future<Map<String, dynamic>> bookAvailableSlotForDate({
    required String targetSlotId,
    required String userEmail,
    required String userName,
    required DateTime date,
  }) async {
    try {
      // Check if trying to book past dates
      final yesterday = DateTime.now().subtract(Duration(days: 1));
      if (date.isBefore(yesterday)) {
        return {
          'success': false,
          'message': 'Cannot book slots for past dates',
        };
      }

      final dateStr = _formatDateForDocId(date);

      // First, verify the slot is actually available from declarations
      final availabilityCheck = await checkSlotAvailabilityFromDeclarations(
        slotId: targetSlotId,
        date: date,
      );

      if (!availabilityCheck['isAvailable']) {
        return {
          'success': false,
          'message': 'This slot is not available for booking: ${availabilityCheck['reason']}',
        };
      }

      // Get user's vehicle type for compatibility check
      final userSlot = await _getUserAssignedSlot(userEmail);
      String userVehicleType = 'BIKE'; // default
      if (userSlot != null) {
        final slotData = userSlot['slotData'] as Map<String, dynamic>;
        userVehicleType = slotData['vehicleType'] as String? ?? 'BIKE';
      }

      // Get target slot vehicle type
      final targetSlotVehicleType = availabilityCheck['vehicleType'] as String? ?? 'BIKE';

      // Check vehicle compatibility
      if (userVehicleType.toUpperCase() != targetSlotVehicleType.toUpperCase()) {
        return {
          'success': false,
          'message': 'Vehicle type mismatch. Your vehicle ($userVehicleType) is not compatible with this ${targetSlotVehicleType} slot.',
        };
      }

      final result = await _firestore.runTransaction((transaction) async {
        // ✅ NEW: References for both BookedToday and AvailableToday
        final slotRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('BookedToday')
            .doc(targetSlotId);

        final availabilityRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('AvailableToday')
            .doc(targetSlotId);

        // Read operations within transaction
        final slotDoc = await transaction.get(slotRef);
        final availabilityDoc = await transaction.get(availabilityRef);

        // Check if slot is already booked by someone else
        if (slotDoc.exists) {
          final bookedBy = slotDoc.data()?['bookedBy'] as String?;
          if (bookedBy == userEmail) {
            throw Exception('You have already booked this slot for ${_getDateDisplayName(date)}');
          } else {
            throw Exception('This slot has been booked by another user for ${_getDateDisplayName(date)}');
          }
        }

        // ✅ NEW: Double-check availability status within transaction
        if (availabilityDoc.exists) {
          final availabilityData = availabilityDoc.data() as Map<String, dynamic>;
          final currentStatus = availabilityData['status'] as String? ?? 'notbooked';

          if (currentStatus != 'notbooked') {
            throw Exception('This slot is no longer available (status: $currentStatus)');
          }
        }

        // Check if user has already booked any other slot for this date
        final userBookingsRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('BookedToday')
            .where('bookedBy', isEqualTo: userEmail);

        final userBookings = await userBookingsRef.limit(1).get();
        if (userBookings.docs.isNotEmpty) {
          final bookedSlotId = userBookings.docs.first.id;
          final bookedSlotData = userBookings.docs.first.data();
          throw Exception('already_booked_other:$bookedSlotId:${bookedSlotData['userName'] ?? 'You'}');
        }

        // ✅ NEW: Create the booking in BookedToday
        transaction.set(slotRef, {
          'bookedBy': userEmail,
          'bookedAt': FieldValue.serverTimestamp(),
          'userName': userName,
          'vehicleType': userVehicleType,
          'bookingDate': dateStr,
          'slotId': targetSlotId,
          'bookingType': 'alternative', // Mark as alternative booking
          'originalSlotOwners': availabilityCheck['declarations'], // Store who declared unavailability
        });

        // ✅ NEW: Update status in AvailableToday to 'booked'
        if (availabilityDoc.exists) {
          transaction.update(availabilityRef, {
            'status': 'booked',
            'bookedBy': userEmail,
            'bookedAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }

        return 'success';
      });

      return {
        'success': true,
        'message': 'Successfully booked slot $targetSlotId for ${_getDateDisplayName(date)}!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }


// ✅ NEW METHOD: Get user's booked slot details for a specific date
  Future<Map<String, dynamic>?> getUserBookedSlotForDate({
    required String userEmail,
    required DateTime date,
  }) async {
    try {
      final dateStr = _formatDateForDocId(date);

      final userBookingsQuery = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('BookedToday')
          .where('bookedBy', isEqualTo: userEmail)
          .limit(1)
          .get();

      if (userBookingsQuery.docs.isNotEmpty) {
        final bookingDoc = userBookingsQuery.docs.first;
        final bookingData = bookingDoc.data();

        return {
          'slotId': bookingDoc.id,
          'bookingData': bookingData,
          'bookedBy': bookingData['bookedBy'],
          'userName': bookingData['userName'],
          'vehicleType': bookingData['vehicleType'],
          'bookingType': bookingData['bookingType'] ?? 'regular',
          'exists': true,
        };
      }

      return null;
    } catch (e) {
      print('Error getting user booked slot for date: $e');
      return null;
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





  Future<Map<String, dynamic>> createSlotRequestForDate({
    required DateTime requestDate,
    required String targetSlotId,
    required List<String> slotUsersEmails, // The 2 slot users who declared unavailability
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'No user logged in'};
      }

      final userEmail = currentUser.email!;
      final dateStr = _formatDateForDocId(requestDate);

      // Validate that the slot users actually declared unavailability for this date
      final availabilityCheck = await _validateSlotAvailability(targetSlotId, requestDate, slotUsersEmails);
      if (!availabilityCheck['isValid']) {
        return {
          'success': false,
          'message': availabilityCheck['message'],
        };
      }

      // Check if user already has a request for this slot on this date
      final existingRequest = await _firestore
          .collection('requests')
          .doc(dateStr)
          .collection('slots')
          .doc(targetSlotId)
          .get();

      if (existingRequest.exists) {
        final data = existingRequest.data()!;
        final requestedBy = data['requestedBy'] as String?;

        if (requestedBy == userEmail) {
          return {
            'success': false,
            'message': 'You have already requested this slot for ${_getDateDisplayName(requestDate)}',
          };
        } else {
          return {
            'success': false,
            'message': 'This slot has already been requested by another user for ${_getDateDisplayName(requestDate)}',
          };
        }
      }

      // Create the request structure
      Map<String, dynamic> requestData = {
        'requestedBy': userEmail,
        'requestedAt': FieldValue.serverTimestamp(),
        'requestedTo': {
          for (String email in slotUsersEmails) email: {
            'email': email,
            'notified': false,
            'notifiedAt': null,
          }
        },
        'status': {
          'pending': true,
          'acceptedBy': <String, dynamic>{}, // Will store email -> timestamp when accepted
          'rejectedBy': <String, dynamic>{}, // Will store email -> timestamp when rejected
          'finalStatus': 'pending', // 'approved', 'rejected', 'pending'
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        'slotId': targetSlotId,
        'requestDate': dateStr,
        'metadata': {
          'totalSlotUsers': slotUsersEmails.length,
          'requesterVehicleType': await _getRequesterVehicleType(userEmail),
        }
      };

      // Create the document structure: requests/{date}/slots/{slotId}
      await _firestore
          .collection('requests')
          .doc(dateStr)
          .collection('slots')
          .doc(targetSlotId)
          .set(requestData);

      return {
        'success': true,
        'message': 'Slot request submitted successfully for ${_getDateDisplayName(requestDate)}!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error submitting slot request: ${e.toString()}',
      };
    }
  }

// ✅ HELPER: Validate slot availability for the date
  Future<Map<String, dynamic>> _validateSlotAvailability(
      String slotId,
      DateTime date,
      List<String> expectedEmails
      ) async {
    try {
      final dateStr = _formatDateForDocId(date);

      final availabilityDoc = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('AvailableToday')
          .doc(slotId)
          .get();

      if (!availabilityDoc.exists) {
        return {
          'isValid': false,
          'message': 'This slot is not available for ${_getDateDisplayName(date)}',
        };
      }

      final data = availabilityDoc.data()!;
      final declarations = List<Map<String, dynamic>>.from(data['declarations'] ?? []);
      final slotUsers = data['slotUsers'] as int? ?? 0;

      // Check if all slot users declared unavailability
      if (declarations.length < slotUsers) {
        return {
          'isValid': false,
          'message': 'Not all slot users have declared unavailability for this date',
        };
      }

      // Verify the provided emails match the declared users
      final declaredEmails = declarations.map((d) => d['declaredBy'] as String).toSet();
      final providedEmails = expectedEmails.toSet();

      if (!declaredEmails.containsAll(providedEmails)) {
        return {
          'isValid': false,
          'message': 'Provided slot users do not match declared users',
        };
      }

      return {'isValid': true, 'message': 'Slot is available for request'};
    } catch (e) {
      return {
        'isValid': false,
        'message': 'Error validating slot availability: $e',
      };
    }
  }

// ✅ HELPER: Get requester's vehicle type
  Future<String> _getRequesterVehicleType(String userEmail) async {
    try {
      final userSlot = await _getUserAssignedSlot(userEmail);
      if (userSlot != null) {
        final slotData = userSlot['slotData'] as Map<String, dynamic>;
        return slotData['vehicleType'] as String? ?? 'UNKNOWN';
      }
      return 'UNKNOWN';
    } catch (e) {
      return 'UNKNOWN';
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


}