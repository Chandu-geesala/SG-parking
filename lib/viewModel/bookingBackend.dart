import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  // Book a slot for tomorrow
  Future<Map<String, dynamic>> bookSlotForTomorrow({
    required String slotId,
    required String vehicleType,
    required String userEmail,
    required String userName,
  }) async {
    try {
      if (!isBookingWindowOpen()) {
        return {
          'success': false,
          'message': 'Booking window is closed. Please book between 8:00 AM - 8:00 PM',
        };
      }

      final tomorrowDateStr = _formatDateForDocId(tomorrowDate);

      // Reference to the specific slot document for tomorrow
      final slotRef = _firestore
          .collection('Bookings')
          .doc(tomorrowDateStr)
          .collection('BookedToday')
          .doc(slotId);

      // Check if slot is already booked for tomorrow
      final slotDoc = await slotRef.get();
      if (slotDoc.exists) {
        final bookedBy = slotDoc.data()?['bookedBy'] as String?;
        if (bookedBy == userEmail) {
          return {
            'success': false,
            'message': 'You have already booked this slot for tomorrow',
          };
        } else {
          return {
            'success': false,
            'message': 'This slot is already booked by another user for tomorrow',
          };
        }
      }

      // Check if user has already booked any slot for tomorrow
      final userBookingQuery = await _firestore
          .collection('Bookings')
          .doc(tomorrowDateStr)
          .collection('BookedToday')
          .where('bookedBy', isEqualTo: userEmail)
          .get();

      if (userBookingQuery.docs.isNotEmpty) {
        final bookedSlot = userBookingQuery.docs.first.id;
        return {
          'success': false,
          'message': 'You have already booked slot $bookedSlot for tomorrow',
        };
      }

      // Create the booking
      await slotRef.set({
        'bookedBy': userEmail,
        'bookedAt': FieldValue.serverTimestamp(),
        'userName': userName,
        'vehicleType': vehicleType,
        'bookingDate': tomorrowDateStr,
        'slotId': slotId,
      });

      return {
        'success': true,
        'message': 'Successfully booked slot $slotId for tomorrow!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error booking slot: ${e.toString()}',
      };
    }
  }

  // Cancel booking for tomorrow
  Future<Map<String, dynamic>> cancelBookingForTomorrow({
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

      final tomorrowDateStr = _formatDateForDocId(tomorrowDate);

      // Reference to the specific slot document for tomorrow
      final slotRef = _firestore
          .collection('Bookings')
          .doc(tomorrowDateStr)
          .collection('BookedToday')
          .doc(slotId);

      // Check if slot is booked by current user
      final slotDoc = await slotRef.get();
      if (!slotDoc.exists) {
        return {
          'success': false,
          'message': 'No booking found for this slot tomorrow',
        };
      }

      final bookedBy = slotDoc.data()?['bookedBy'] as String?;
      if (bookedBy != userEmail) {
        return {
          'success': false,
          'message': 'You can only cancel your own booking',
        };
      }

      // Delete the booking
      await slotRef.delete();

      return {
        'success': true,
        'message': 'Successfully cancelled booking for tomorrow!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error cancelling booking: ${e.toString()}',
      };
    }
  }

  // Get user's booking for today
  Future<Map<String, dynamic>?> getTodaysBooking(String userEmail) async {
    try {
      final todayDateStr = _formatDateForDocId(todayDate);

      final todayBookingQuery = await _firestore
          .collection('Bookings')
          .doc(todayDateStr)
          .collection('BookedToday')
          .where('bookedBy', isEqualTo: userEmail)
          .get();

      if (todayBookingQuery.docs.isNotEmpty) {
        final doc = todayBookingQuery.docs.first;
        return {
          'slotId': doc.id,
          'bookingData': doc.data(),
        };
      }

      return null;
    } catch (e) {
      print('Error getting today\'s booking: $e');
      return null;
    }
  }

  // Get user's booking for tomorrow
  Future<Map<String, dynamic>?> getTomorrowsBooking(String userEmail) async {
    try {
      final tomorrowDateStr = _formatDateForDocId(tomorrowDate);

      final tomorrowBookingQuery = await _firestore
          .collection('Bookings')
          .doc(tomorrowDateStr)
          .collection('BookedToday')
          .where('bookedBy', isEqualTo: userEmail)
          .get();

      if (tomorrowBookingQuery.docs.isNotEmpty) {
        final doc = tomorrowBookingQuery.docs.first;
        return {
          'slotId': doc.id,
          'bookingData': doc.data(),
        };
      }

      return null;
    } catch (e) {
      print('Error getting tomorrow\'s booking: $e');
      return null;
    }
  }

  // Check if a specific slot is available for tomorrow
  Future<bool> isSlotAvailableForTomorrow(String slotId) async {
    try {
      final tomorrowDateStr = _formatDateForDocId(tomorrowDate);

      final slotDoc = await _firestore
          .collection('Bookings')
          .doc(tomorrowDateStr)
          .collection('BookedToday')
          .doc(slotId)
          .get();

      return !slotDoc.exists;
    } catch (e) {
      print('Error checking slot availability: $e');
      return false;
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

  // Get booking statistics for a user
  Future<Map<String, int>> getUserBookingStats(String userEmail) async {
    try {
      // Get last 30 days of bookings
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      int totalBookings = 0;
      int currentMonth = DateTime.now().month;
      int currentYear = DateTime.now().year;

      for (int i = 0; i < 30; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = _formatDateForDocId(date);

        final userBookingQuery = await _firestore
            .collection('Bookings')
            .doc(dateStr)
            .collection('BookedToday')
            .where('bookedBy', isEqualTo: userEmail)
            .get();

        if (userBookingQuery.docs.isNotEmpty) {
          totalBookings++;
        }
      }

      return {
        'totalBookingsLast30Days': totalBookings,
        'currentMonth': currentMonth,
        'currentYear': currentYear,
      };
    } catch (e) {
      print('Error getting user booking stats: $e');
      return {'totalBookingsLast30Days': 0};
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




}