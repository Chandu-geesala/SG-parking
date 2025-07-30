import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../view/splashScreen/my_splash_screen.dart';

/// BookingBackend
/// Centralized Firebase backend interface for slots, bookings, declarations, and admin utilities.
class BookingBackend {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// ---- SECTION: HELPER Getters and Date Formatting ----

  User? get currentUser => _auth.currentUser;

  String _formatDateForDocId(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  DateTime get tomorrowDate => DateTime.now().add(const Duration(days: 1));
  DateTime get todayDate => DateTime.now();

  String _getDateDisplayName(DateTime date) {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    if (DateUtils.isSameDay(date, today)) return 'today';
    if (DateUtils.isSameDay(date, tomorrow)) return 'tomorrow';
    return DateFormat('MMM dd, yyyy').format(date);
  }

  /// ---- SECTION: AUTHENTICATION / SESSION ----

  Future<void> signOut(BuildContext context) async {
    try {
      await _auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
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

  /// ---- SECTION: USER & SLOT PROFILE ----

  static Map<String, dynamic>? _userSlotCache;
  static DateTime? _userSlotCacheTimestamp;
  static const int USER_SLOT_CACHE_MINUTES = 30;

  Future<Map<String, dynamic>?> getUserAssignedSlot(String userEmail) async {
    try {
      final now = DateTime.now();
      if (_userSlotCache != null &&
          _userSlotCacheTimestamp != null &&
          now.difference(_userSlotCacheTimestamp!).inMinutes <
              USER_SLOT_CACHE_MINUTES) {
        return _userSlotCache;
      }

      // Try Users collection first
      final user = _auth.currentUser;
      if (user != null) {
        final userDoc = await _firestore.collection('Users').doc(user.uid).get();
        if (userDoc.exists && userDoc.data()?['assignedSlotId'] != null) {
          final slotId = userDoc.data()!['assignedSlotId'] as String;
          final slotDoc = await _firestore.collection('Slots').doc(slotId).get();
          if (slotDoc.exists) {
            _userSlotCache = {
              'slotId': slotId,
              'slotData': slotDoc.data()!,
            };
            _userSlotCacheTimestamp = now;
            return _userSlotCache;
          }
        }
      }

      // Fallback: search slots collection by email
      final slotsSnapshot = await _firestore.collection('Slots').get();
      for (var doc in slotsSnapshot.docs) {
        final data = doc.data();
        final allotedTo = data['alloted_to'] as List? ?? [];
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

  Future<Map<String, dynamic>?> getProfileData() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final doc = await _firestore.collection('Users').doc(user.uid).get();
      return doc.data();
    } catch (e) {
      print('Error fetching profile data: $e');
      return null;
    }
  }

  /// ---- SECTION: BOOKING OPERATIONS ----

  Future<Map<String, dynamic>> bookSlotForDate({
    required String slotId,
    required String vehicleType,
    required String userEmail,
    required String userName,
    required DateTime date,
  }) async {
    try {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      if (date.isBefore(yesterday)) {
        return {'success': false, 'message': 'Cannot book slots for past dates'};
      }
      final dateStr = _formatDateForDocId(date);
      await _firestore.runTransaction((transaction) async {
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
        final slotDoc = await transaction.get(slotRef);
        final userBookings = await userBookingsRef.limit(1).get();
        if (slotDoc.exists) {
          final bookedBy = slotDoc.data()?['bookedBy'] as String?;
          if (bookedBy == userEmail) {
            throw Exception(
                'You have already booked this slot for ${_getDateDisplayName(date)}');
          } else {
            throw Exception(
                'This slot is already booked by another user for ${_getDateDisplayName(date)}');
          }
        }
        if (userBookings.docs.isNotEmpty) {
          final bookedSlot = userBookings.docs.first.id;
          throw Exception(
              'You have already booked slot $bookedSlot for ${_getDateDisplayName(date)}');
        }
        transaction.set(slotRef, {
          'bookedBy': userEmail,
          'bookedAt': FieldValue.serverTimestamp(),
          'userName': userName,
          'vehicleType': vehicleType,
          'bookingDate': dateStr,
          'slotId': slotId,
        });
      });
      return {
        'success': true,
        'message':
        'Successfully booked slot $slotId for ${_getDateDisplayName(date)}!',
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  Future<Map<String, dynamic>> cancelBookingForDate({
    required String slotId,
    required String userEmail,
    required DateTime date,
  }) async {
    try {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      if (date.isBefore(yesterday)) {
        return {'success': false, 'message': 'Cannot cancel bookings for past dates'};
      }
      final dateStr = _formatDateForDocId(date);
      final result = await _firestore.runTransaction((transaction) async {
        final slotRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('BookedToday')
            .doc(slotId);
        final availabilityRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('AvailableToday')
            .doc(slotId);
        final slotDoc = await transaction.get(slotRef);
        final availabilityDoc = await transaction.get(availabilityRef);
        if (!slotDoc.exists) {
          throw Exception(
              'No booking found for this slot on ${_getDateDisplayName(date)}');
        }
        final bookingData = slotDoc.data() as Map<String, dynamic>;
        final bookedBy = bookingData['bookedBy'] as String?;
        if (bookedBy != userEmail) {
          throw Exception('You can only cancel your own booking');
        }
        final bookingType = bookingData['bookingType'] as String? ?? 'regular';
        final isAlternativeBooking = bookingType == 'alternative';
        transaction.delete(slotRef);
        if (isAlternativeBooking && availabilityDoc.exists) {
          final availabilityData = availabilityDoc.data() as Map<String, dynamic>;
          final currentStatus =
              availabilityData['status'] as String? ?? 'notbooked';
          final bookedByInAvailability = availabilityData['bookedBy'] as String?;
          if (currentStatus == 'booked' &&
              bookedByInAvailability == userEmail) {
            transaction.update(availabilityRef, {
              'status': 'notbooked',
              'bookedBy': FieldValue.delete(),
              'bookedAt': FieldValue.delete(),
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          }
        }
        return {
          'bookingType': bookingType,
          'wasAlternative': isAlternativeBooking,
        };
      });
      final wasAlternative = result['wasAlternative'] as bool;
      final successMessage = wasAlternative
          ? 'Successfully cancelled alternative booking for ${_getDateDisplayName(date)}! Slot is now available for others.'
          : 'Successfully cancelled booking for ${_getDateDisplayName(date)}!';
      return {'success': true, 'message': successMessage};
    } catch (e) {
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  /// This is used for status on a given slot/date for colored marking.
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
      return {
        'exists': false,
        'isBookedByCurrentUser': false,
        'slotId': slotId,
        'status': 'error',
        'error': e.toString(),
      };
    }
  }

  Future<List<Map<String, dynamic>>> getBookingsForDate(DateTime date) async {
    try {
      final dateStr = _formatDateForDocId(date);
      final bookingsQuery = await _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('BookedToday')
          .get();
      return bookingsQuery.docs
          .map((doc) => {
        'slotId': doc.id,
        'bookingData': doc.data() as Map<String, dynamic>,
      })
          .toList();
    } catch (e) {
      print('Error getting bookings for date: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getUserBookings(String userEmail) async {
    try {
      final todayDateStr = _formatDateForDocId(DateTime.now());
      final tomorrowDateStr =
      _formatDateForDocId(DateTime.now().add(const Duration(days: 1)));
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
            .get(),
      ];
      final results = await Future.wait(futures);
      final todayQuery = results[0] as QuerySnapshot;
      final tomorrowQuery = results[1] as QuerySnapshot;
      return {
        'today': todayQuery.docs.isNotEmpty
            ? {
          'slotId': todayQuery.docs.first.id,
          'bookingData':
          todayQuery.docs.first.data() as Map<String, dynamic>,
        }
            : null,
        'tomorrow': tomorrowQuery.docs.isNotEmpty
            ? {
          'slotId': tomorrowQuery.docs.first.id,
          'bookingData':
          tomorrowQuery.docs.first.data() as Map<String, dynamic>,
        }
            : null,
      };
    } catch (e) {
      print('Error getting user bookings: $e');
      return {'today': null, 'tomorrow': null};
    }
  }

  /// --- MISSING SECTION: ADMIN/REQUESTS/BOOKING CARDS SUPPORT ---

  /// Get unbooked slots from AvailableToday which have NOT been booked for a date.
  Future<List<Map<String, dynamic>>> getUnbookedAvailableSlotsForDate({
    required DateTime date,
    String? vehicleTypeFilter,
  }) async {
    try {
      final dateStr = _formatDateForDocId(date);
      Query query = _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('AvailableToday')
          .where('status', isEqualTo: 'notbooked');
      if (vehicleTypeFilter != null) {
        query = query.where(
            'vehicleType', isEqualTo: vehicleTypeFilter.toUpperCase());
      }
      final availabilityQuery = await query.get();
      List<Map<String, dynamic>> unbookedSlots = [];
      for (var doc in availabilityQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        unbookedSlots.add({
          ...data,
          'slotId': data['slotId'] ?? doc.id,
          'date': dateStr,
        });
      }
      return unbookedSlots;
    } catch (e) {
      print('Error getting unbooked available slots for date: $e');
      return [];
    }
  }

  /// Book an available slot from declarations (ALTERNATIVE booking!).
  Future<Map<String, dynamic>> bookAvailableSlotForDate({
    required String targetSlotId,
    required String userEmail,
    required String userName,
    required DateTime date,
  }) async {
    try {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      if (date.isBefore(yesterday)) {
        return {
          'success': false,
          'message': 'Cannot book slots for past dates',
        };
      }
      final dateStr = _formatDateForDocId(date);

      // First: check from declarations
      final availabilityCheck =
      await checkSlotAvailabilityFromDeclarations(slotId: targetSlotId, date: date);
      if (!availabilityCheck['isAvailable']) {
        return {
          'success': false,
          'message': 'This slot is not available for booking: ${availabilityCheck['reason']}',
        };
      }

      final userSlot = await getUserAssignedSlot(userEmail);
      String userVehicleType = 'BIKE';
      if (userSlot != null) {
        final slotData = userSlot['slotData'] as Map<String, dynamic>;
        userVehicleType = slotData['vehicleType'] as String? ?? 'BIKE';
      }

      final targetSlotVehicleType = availabilityCheck['vehicleType'] as String? ?? 'BIKE';
      if (userVehicleType.toUpperCase() != targetSlotVehicleType.toUpperCase()) {
        return {
          'success': false,
          'message': 'Vehicle type mismatch. Your vehicle ($userVehicleType) is not compatible with this $targetSlotVehicleType slot.',
        };
      }

      await _firestore.runTransaction((transaction) async {
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

        final slotDoc = await transaction.get(slotRef);
        final availabilityDoc = await transaction.get(availabilityRef);

        if (slotDoc.exists) {
          final bookedBy = slotDoc.data()?['bookedBy'] as String?;
          if (bookedBy == userEmail) {
            throw Exception('You have already booked this slot for ${_getDateDisplayName(date)}');
          } else {
            throw Exception('This slot has been booked by another user for ${_getDateDisplayName(date)}');
          }
        }

        if (availabilityDoc.exists) {
          final availabilityData = availabilityDoc.data() as Map<String, dynamic>;
          final currentStatus = availabilityData['status'] as String? ?? 'notbooked';
          if (currentStatus != 'notbooked') {
            throw Exception('This slot is no longer available (status: $currentStatus)');
          }
        }

        // Prevent same user from booking another slot this date:
        final userBookingsRef = _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('BookedToday')
            .where('bookedBy', isEqualTo: userEmail);
        final userBookings = await userBookingsRef.limit(1).get();
        if (userBookings.docs.isNotEmpty) {
          final bookedSlotId = userBookings.docs.first.id;
          final bookedSlotData = userBookings.docs.first.data() as Map<String, dynamic>;
          throw Exception('already_booked_other:$bookedSlotId:${bookedSlotData['userName'] ?? 'You'}');
        }

        // Now do the booking
        transaction.set(slotRef, {
          'bookedBy': userEmail,
          'bookedAt': FieldValue.serverTimestamp(),
          'userName': userName,
          'vehicleType': userVehicleType,
          'bookingDate': dateStr,
          'slotId': targetSlotId,
          'bookingType': 'alternative',
          'originalSlotOwners': availabilityCheck['declarations'],
        });

        // Mark it as "booked" in AvailableToday
        if (availabilityDoc.exists) {
          transaction.update(availabilityRef, {
            'status': 'booked',
            'bookedBy': userEmail,
            'bookedAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
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

  /// Return the user's booked slot on a given date (bookings.dart/booking_cards.dart).
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
        final bookingData = bookingDoc.data() as Map<String, dynamic>;
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

  // Checks if a slot in AvailableToday is *really* available (all declared and not booked).
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
      final status = data['status'] as String? ?? 'notbooked';
      final isFullyDeclared = declarations.length >= slotUsers && slotUsers > 0;
      final isNotBooked = status == 'notbooked';
      final isAvailable = isFullyDeclared && isNotBooked;
      return {
        'isAvailable': isAvailable,
        'reason': !isFullyDeclared
            ? 'Only ${declarations.length} of $slotUsers users declared'
            : !isNotBooked
            ? 'Slot is already booked'
            : 'All $slotUsers users declared unavailability and slot is not booked',
        'slotId': slotId,
        'vehicleType': vehicleType,
        'slotUsers': slotUsers,
        'declarationsCount': declarations.length,
        'declarations': declarations,
        'date': dateStr,
        'status': status,
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

  /// ---- SECTION: SLOTS DASHBOARD & DECLARATIONS ----

  Future<List<Map<String, dynamic>>> getAvailableSlotsForToday() async {
    try {
      final todayDateStr = _formatDateForDocId(todayDate);
      final futures = [
        _firestore.collection('Slots').get(),
        _firestore.collection('Bookings').doc(todayDateStr).collection('BookedToday').get()
      ];
      final results = await Future.wait(futures);
      final slotsQuery = results[0] as QuerySnapshot;
      final bookedSlotsQuery = results[1] as QuerySnapshot;
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
            'alloted_to':
            (slotData['alloted_to'] as List?)?.map((item) => item['name'] ?? 'Unknown').toList() ?? [],
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

  Future<List<Map<String, dynamic>>> getAvailableSlotsFromDeclarations({
    required DateTime date,
    String? vehicleTypeFilter,
    String? dimensionFilter,
  }) async {
    try {
      final dateStr = _formatDateForDocId(date);
      Query query = _firestore
          .collection('Bookings')
          .doc(dateStr)
          .collection('AvailableToday')
          .where('status', isEqualTo: 'notbooked');

      if (vehicleTypeFilter != null) {
        query = query.where('vehicleType', isEqualTo: vehicleTypeFilter.toUpperCase());
      }
      if (dimensionFilter != null) {
        query = query.where('dimension', isEqualTo: dimensionFilter);
      }
      final availabilityQuery = await query.get();
      List<Map<String, dynamic>> availableSlots = [];
      for (var doc in availabilityQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final slotId = data['slotId'] as String;
        final vehicleType = data['vehicleType'] as String? ?? 'BIKE';
        final slotUsers = data['slotUsers'] as int? ?? 0;
        final declarations = List<Map<String, dynamic>>.from(data['declarations'] ?? []);
        final status = data['status'] as String? ?? 'notbooked';
        final isFullyAvailable = declarations.length >= slotUsers && slotUsers > 0;
        if (declarations.isNotEmpty && slotUsers > 0) {
          availableSlots.add({
            'slotId': slotId,
            'vehicleType': vehicleType,
            'slotUsers': slotUsers,
            'declarationsCount': declarations.length,
            'declarations': declarations,
            'date': dateStr,
            'isAvailable': true,
            'isFullyAvailable': isFullyAvailable,
            'status': status,
          });
        }
      }
      availableSlots.sort((a, b) {
        final scoreA = a['isFullyAvailable'] == true ? 1 : 0;
        final scoreB = b['isFullyAvailable'] == true ? 1 : 0;
        if (scoreA != scoreB) return scoreB - scoreA;
        return a['slotId'].compareTo(b['slotId']);
      });
      return availableSlots;
    } catch (e) {
      print('Error getting available slots from declarations: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableSlotsWithUserDetails({
    required DateTime date,
    String? vehicleTypeFilter,
    String? dimensionFilter,
  }) async {
    try {
      final availableSlots = await getAvailableSlotsFromDeclarations(
        date: date,
        vehicleTypeFilter: vehicleTypeFilter,
        dimensionFilter: dimensionFilter,
      );
      if (availableSlots.isEmpty) return [];
      final slotIds = availableSlots.map((slot) => slot['slotId'] as String).toList();
      final slotDetailsQuery = await _firestore
          .collection('Slots')
          .where(FieldPath.documentId, whereIn: slotIds)
          .get();
      final slotDetailsMap = <String, Map<String, dynamic>>{};
      for (var doc in slotDetailsQuery.docs) {
        slotDetailsMap[doc.id] = doc.data() as Map<String, dynamic>;
      }
      List<Map<String, dynamic>> detailedSlots = [];
      for (final slot in availableSlots) {
        final slotId = slot['slotId'] as String;
        final slotData = slotDetailsMap[slotId];
        if (slotData != null) {
          final allotedTo = slotData['alloted_to'] as List? ?? [];
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

  /// ---- SECTION: USER DECLARATIONS (Leave, WFH) ----

  Future<Map<String, dynamic>> getUserSlotAndAvailabilityData(String userEmail) async {
    try {
      final userSlot = await getUserAssignedSlot(userEmail);
      if (userSlot == null) {
        return {
          'success': false,
          'message': 'User has no assigned slot',
          'slotId': null,
          'declarations': <DateTime, String>{}
        };
      }
      final slotId = userSlot['slotId'] as String;
      final today = DateTime.now();
      final normalizedToday = DateTime(today.year, today.month, today.day);
      List<Future<DocumentSnapshot<Map<String, dynamic>>>> futures = [];
      List<DateTime> datesToCheck = [];
      for (int i = 0; i < 14; i++) {
        final date = normalizedToday.add(Duration(days: i));
        if (date.weekday >= DateTime.monday && date.weekday <= DateTime.friday) {
          futures.add(_firestore
              .collection('Bookings')
              .doc(_formatDateForDocId(date))
              .collection('AvailableToday')
              .doc(slotId)
              .get());
          datesToCheck.add(date);
        }
      }
      final results = await Future.wait(futures);
      Map<DateTime, String> declarations = {};
      for (int i = 0; i < results.length; i++) {
        final doc = results[i];
        final date = datesToCheck[i];
        if (doc.exists) {
          final data = doc.data()!;
          final declarationsArray = List<Map<String, dynamic>>.from(data['declarations'] ?? []);
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
        'slotData': userSlot['slotData'],
        'declarations': declarations,
      };
    } catch (e) {
      print('Error getting user slot and availability data: $e');
      return {'success': false, 'message': e.toString(), 'slotId': null, 'declarations': {}};
    }
  }

  Future<Map<String, dynamic>> updateUserAvailabilityDeclaration({
    required DateTime date,
    required String userEmail,
    String? reason,
  }) async {
    try {
      final dateStr = _formatDateForDocId(date);
      final userSlot = await getUserAssignedSlot(userEmail);
      if (userSlot == null) return {'success': false, 'message': 'User has no assigned slot'};
      final dimension = userSlot['slotData']?['dimension'] as String?;
      final slotId = userSlot['slotId'] as String;
      final vehicleType = userSlot['slotData']?['vehicleType'] as String? ?? 'BIKE';
      final allotedTo = userSlot['slotData']?['alloted_to'] as List? ?? [];
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
            declarations.removeWhere((declaration) => declaration['declaredBy'] == userEmail);
            if (declarations.isEmpty) {
              transaction.delete(availabilityRef);
            } else {
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
            final data = existingDoc.data() as Map<String, dynamic>;
            final declarations = List<Map<String, dynamic>>.from(data['declarations'] ?? []);
            declarations.removeWhere((declaration) => declaration['declaredBy'] == userEmail);
            declarations.add(newDeclaration);
            transaction.update(availabilityRef, {
              'declarations': declarations,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          } else {
            transaction.set(availabilityRef, {
              'date': dateStr,
              'slotId': slotId,
              'vehicleType': vehicleType,
              'slotUsers': slotUsers,
              'declarations': [newDeclaration],
              'dimension': dimension,
              'createdAt': FieldValue.serverTimestamp(),
              'lastUpdated': FieldValue.serverTimestamp(),
              'status': 'notbooked',
            });
          }
        }
      });
      return {
        'success': true,
        'message':
        reason == null ? 'Thanks for the update! ✅' : 'Thanks for informing us! 🎉',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString().replaceAll('Exception: ', '')};
    }
  }

  /// ---- SECTION: REQUESTS ----

  Future<Map<String, dynamic>> getUserRequestsSummary() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {};
      final query = await _firestore
          .collection('requests')
          .where('email', isEqualTo: user.email!)
          .orderBy('timestamp', descending: true)
          .get();
      if (query.docs.isEmpty) {
        return {
          'hasRequests': false,
          'totalRequests': 0,
          'pendingRequests': 0,
          'latestRequest': null,
          'requestsByType': {},
          'pendingByType': {},
        };
      }
      Map<String, int> requestsByType = {'NewReq': 0, 'TodReq': 0, 'AltReq': 0};
      Map<String, int> pendingByType = {'NewReq': 0, 'TodReq': 0, 'AltReq': 0};
      int pendingCount = 0;
      Map<String, dynamic>? latestRequest;
      for (var doc in query.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final type = data['type'] as String?;
        final status = data['status'] as String?;
        if (latestRequest == null) latestRequest = data;
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

  Future<Map<String, dynamic>> deleteAllUserRequests() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'No user logged in'};
      }
      final userEmail = currentUser.email ?? '';
      const batchSize = 500;
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

  /// ---- SECTION: UTILITY / UI HELPERS ----

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

  String getDisplayNameFromEmail(String email) {
    final usernamePart = email.split('@').first;
    final words = usernamePart.split('.').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).toList();
    return words.join(' ');
  }
}
