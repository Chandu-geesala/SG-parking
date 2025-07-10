import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/booking_cards.dart';
import '../viewModel/bookingBackend.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}


// Add these new state variables at the top of _HomeScreenState class
class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<String, dynamic>?> _userSlotFuture;
  final BookingBackend _backend = BookingBackend();

  Map<String, dynamic>? _slotRequest;
  bool _isLoadingRequest = false;



  @override
  void initState() {
    super.initState();
    _userSlotFuture = fetchUserSlot();

    fetchSlotRequest(); // <-- add this
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
          .get(); // NO orderBy!

      if (query.docs.isNotEmpty) {
        // If multiple docs, pick the one with 'pending' status first, else the most recent (even if timestamp is null)
        var docs = query.docs;
        docs.sort((a, b) {
          // If both have timestamps, newest first
          final aTime = a.data()['timestamp'];
          final bTime = b.data()['timestamp'];
          if (aTime != null && bTime != null) {
            return bTime.compareTo(aTime);
          }
          // Place those with timestamp at top
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


  // Update the _refreshProfile method
  Future<void> _refreshProfile() async {
    setState(() {
      _userSlotFuture = fetchUserSlot();
    });
    await _userSlotFuture;

    await fetchSlotRequest();
// Add this line
  }



  String getDisplayNameFromEmail(String email) {
    // Get the part before @
    final usernamePart = email.split('@').first;
    // Replace . with space, then capitalize each word
    final words = usernamePart.split('.').map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1);
    }).toList();
    return words.join(' ');
  }


  // Update the _buildSlotDashboard method to include the tomorrow's booking card
  Widget _buildSlotDashboard(Map<String, dynamic> slotData) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [


        const BookingCards(),

        const SizedBox(height: 16),



      ],
    );
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



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.grey.withOpacity(0.1),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.local_parking_rounded,
                color: Colors.blue[600],
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Parking Manager',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.logout_rounded, color: Colors.red, size: 20),
              ),
              tooltip: "Logout",
              onPressed: () async {
                await _backend.signOut(context);
              },
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
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
            final userName = FirebaseAuth.instance.currentUser?.displayName ??
                FirebaseAuth.instance.currentUser?.email?.split('@').first ?? 'User';

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeSection(userName),
                    const SizedBox(height: 24),
                    if (slotData == null)
                      _buildNoSlotAssignedCard()
                    else
                      _buildSlotDashboard(slotData),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(String userName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[600]!, Colors.blue[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome back,',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSlotAssignedCard() {
    if (_isLoadingRequest) {
      return Center(child: CircularProgressIndicator());
    }

    if (_slotRequest != null) {
      // Show status if request exists
      final status = _slotRequest!['status'] ?? 'pending';

      final timestamp = _slotRequest!['timestamp'];
      String dateStr = '';
      if (timestamp is Timestamp) {
        dateStr = DateFormat('MMM dd, yyyy - hh:mm a').format(timestamp.toDate());
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
              'Your request to admin is currently "$status".\n${dateStr.isNotEmpty ? 'Submitted: $dateStr' : ''}',
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

    // Default: show Contact Admin button if no request exists
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
          Container(
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




  Future<void> requestSlotAllocation() async {
    try {
      // Get current user
      User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        throw Exception('No user logged in');
      }

      // Get user email and name
      String userEmail = currentUser.email ?? '';
      // Use displayName if available, else generate from email
      String userName = currentUser.displayName ?? getDisplayNameFromEmail(userEmail);

      // Create request data
      Map<String, dynamic> requestData = {
        'email': userEmail,
        'name': userName,
        'timestamp': FieldValue.serverTimestamp(),
        'text': 'Requested to allot slot',
        'status': 'pending', // Optional: to track request status
      };

      // Add to Firestore 'requests' collection
      await FirebaseFirestore.instance
          .collection('requests')
          .add(requestData);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Slot request submitted successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      await fetchSlotRequest();



    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error submitting request: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }




}