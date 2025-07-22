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



  Future<Map<String, dynamic>> bookSlotForToday({
    required String slotId,
    required String vehicleType,
    required String userEmail,
    required String userName,
  }) async {
    try {
      final todayDateStr = _formatDateForDocId(DateTime.now());

      final slotRef = _firestore
          .collection('Bookings')
          .doc(todayDateStr)
          .collection('BookedToday')
          .doc(slotId);

      final slotDoc = await slotRef.get();

      if (slotDoc.exists) {
        return {
          'success': false,
          'message': 'This slot is already booked for today',
        };
      }

      await slotRef.set({
        'bookedBy': userEmail,
        'bookedAt': FieldValue.serverTimestamp(),
        'userName': userName,
        'doneBy': 'Admin',
        'bookingDate': todayDateStr,
        'slotId': slotId,
      });

      return {
        'success': true,
        'message': 'Successfully booked slot $slotId for today!',
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



  // Cancel today's booking - no API notification needed
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

      // Reference to the specific slot document for today
      final slotRef = _firestore
          .collection('Bookings')
          .doc(todayDateStr)
          .collection('BookedToday')
          .doc(slotId);

      // Check if slot is booked by current user
      final slotDoc = await slotRef.get();
      if (!slotDoc.exists) {
        return {
          'success': false,
          'message': 'No booking found for this slot today',
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
        'message': 'Successfully cancelled today\'s booking!',
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error cancelling booking: ${e.toString()}',
      };
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



// Modified request slot allocation methods with vehicle type

// Helper method to get vehicle type from slot details
  Future<String?> _getSlotVehicleType(String slotId) async {
    try {
      // Query the slots collection to find the slot by slotId
      DocumentSnapshot slotDoc = await _firestore
          .collection('Slots')
          .doc(slotId)
          .get();

      if (slotDoc.exists) {
        Map<String, dynamic> slotData = slotDoc.data() as Map<String, dynamic>;
        return slotData['vehicleType'] as String?;
      }
      return null;
    } catch (e) {
      print('Error fetching slot vehicle type: $e');
      return null;
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

  Future<Map<String, dynamic>> deleteAllUserRequests() async {
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

      // Query all requests for this user
      QuerySnapshot requestsQuery = await _firestore
          .collection('requests')
          .get();

      if (requestsQuery.docs.isEmpty) {
        return {
          'success': true,
          'message': 'No requests found to delete',
        };
      }

      // Create a batch to delete all requests
      WriteBatch batch = _firestore.batch();

      for (QueryDocumentSnapshot doc in requestsQuery.docs) {
        batch.delete(doc.reference);
      }

      // Execute the batch delete
      await batch.commit();

      return {
        'success': true,
        'message': 'All requests deleted successfully! (${requestsQuery.docs.length} requests removed)',
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error deleting requests: ${e.toString()}',
      };
    }
  }


// Modified fetch methods to handle different request types

// Fetch user's slot request by type
  Future<Map<String, dynamic>?> fetchSlotRequestByType(String requestType) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return null;
      }

      final query = await _firestore
          .collection('requests')
          .where('email', isEqualTo: user.email)
          .where('type', isEqualTo: requestType)
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
        return docs.first.data();
      } else {
        return null;
      }
    } catch (e) {
      print('Error fetching slot request by type: $e');
      return null;
    }
  }




// Fetch all user's slot requests
  Future<List<Map<String, dynamic>>> fetchAllSlotRequests() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return [];
      }

      final query = await _firestore
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
        return docs.map((doc) => doc.data()).toList();
      } else {
        return [];
      }
    } catch (e) {
      print('Error fetching all slot requests: $e');
      return [];
    }
  }



// Modified original fetchSlotRequest to get latest request of any type
  Future<Map<String, dynamic>?> fetchSlotRequest() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return null;
      }

      final query = await _firestore
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
        return docs.first.data();
      } else {
        return null;
      }
    } catch (e) {
      print('Error fetching slot request: $e');
      return null;
    }
  }




// Check if user has a specific type of slot request
  Future<bool> hasSlotRequestOfType(String requestType) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final query = await _firestore
          .collection('requests')
          .where('email', isEqualTo: user.email)
          .where('type', isEqualTo: requestType)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print('Error checking slot request of type: $e');
      return false;
    }
  }

// Modified hasSlotRequest to check for any type of request
  Future<bool> hasSlotRequest() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final query = await _firestore
          .collection('requests')
          .where('email', isEqualTo: user.email)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print('Error checking slot request: $e');
      return false;
    }
  }

// Get slot request status by type
  Future<String?> getSlotRequestStatusByType(String requestType) async {
    try {
      final requestData = await fetchSlotRequestByType(requestType);
      return requestData?['status'];
    } catch (e) {
      print('Error getting slot request status by type: $e');
      return null;
    }
  }

// Modified getSlotRequestStatus to get latest request status of any type
  Future<String?> getSlotRequestStatus() async {
    try {
      final requestData = await fetchSlotRequest();
      return requestData?['status'];
    } catch (e) {
      print('Error getting slot request status: $e');
      return null;
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