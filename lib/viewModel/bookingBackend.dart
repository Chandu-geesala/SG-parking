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

  // Add this to your BookingBackend class

// Simplified cancel booking method - API handles all the notification logic
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

      // Delete the booking first
      await slotRef.delete();

      // Now notify the API about the cancellation - fire and forget
      _notifySlotAvailable(slotId, userEmail);

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

// Private method to notify API about slot availability
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


  // Get all available slots for today
  Future<List<Map<String, dynamic>>> getAvailableSlotsForToday() async {
    try {
      final todayDateStr = _formatDateForDocId(todayDate);

      // Get all slots from the Slots collection
      final slotsQuery = await _firestore
          .collection('Slots')
          .get();

      // Get all booked slots for today
      final bookedSlotsQuery = await _firestore
          .collection('Bookings')
          .doc(todayDateStr)
          .collection('BookedToday')
          .get();

      // Create a set of booked slot IDs for quick lookup
      final bookedSlotIds = bookedSlotsQuery.docs.map((doc) => doc.id).toSet();

      // Filter available slots (slots that are not booked)
      List<Map<String, dynamic>> availableSlots = [];

      for (var slotDoc in slotsQuery.docs) {
        String slotId = slotDoc.id;

        // If slot is not booked today, it's available
        if (!bookedSlotIds.contains(slotId)) {
          Map<String, dynamic> slotData = slotDoc.data() as Map<String, dynamic>;

          availableSlots.add({
            'slotId': slotId,
            'slotData': slotData,
            'vehicleType': slotData['vehicleType'] ?? 'BIKE',
            'slotPriority': slotData['slotPriority'] ?? 'permanent',
            'alloted_to': (slotData['alloted_to'] as List?)?.map((item) => item['name'] ?? 'Unknown').toList() ?? [],
            'VehicleCompatibility': slotData['VehicleCompatibility'], // For CAR type slots
          });
        }
      }

      // Sort by slot ID for better organization
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
}