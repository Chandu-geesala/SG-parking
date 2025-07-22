import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/booking_cards.dart';
import 'package:park_sg/utils/theme_provider.dart';
import '../viewModel/bookingBackend.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<String, dynamic>?> _userSlotFuture;
  final BookingBackend _backend = BookingBackend();

  Map<String, dynamic>? _slotRequest;
  bool _isLoadingRequest = false;

  @override
  void initState() {
    super.initState();
    _userSlotFuture = fetchUserSlot();

  }

  // Helper method to determine if we're on a large screen (web/tablet)
  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width > 800;
  }

  // Get appropriate max width for content
  double _getMaxContentWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) return 1000; // Large desktop
    if (screenWidth > 800) return 800;   // Tablet/small desktop
    return screenWidth;                  // Mobile
  }


  Future<void> _refreshProfile() async {
    setState(() {
      _userSlotFuture = fetchUserSlot();
    });
    await _userSlotFuture;

  }



  Widget _buildSlotDashboard(Map<String, dynamic> slotData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BookingCards(),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 16)),
      ],
    );
  }

  Future<Map<String, dynamic>?> fetchUserSlot() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user logged in');

    final userEmail = user.email!;

    final slotsSnapshot = await FirebaseFirestore.instance
        .collection('Slots')
        .get();

    for (var doc in slotsSnapshot.docs) {
      final data = doc.data();
      final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];

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

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = _isLargeScreen(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: isLargeScreen,
        title: Row(
          mainAxisSize: isLargeScreen ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Image.asset(
              'assets/txt.png',
              height: ResponsiveUtils.isMobile(context) ? 35 : 40,
              fit: BoxFit.contain,
            ),
          ],
        ),
        actions: [
          const ThemeSwitchWidget(),

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
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: _getMaxContentWidth(context),
                  ),
                  padding: const EdgeInsets.all(24),
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
                ),
              );
            }

            final slotData = snapshot.data;
            final currentUser = FirebaseAuth.instance.currentUser;
            final userName = currentUser?.displayName ??
                (currentUser?.email != null
                    ? _backend.getDisplayNameFromEmail(currentUser!.email!)
                    : 'User');


            return Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: _getMaxContentWidth(context),
                ),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isLargeScreen ? 32 : 16,
                      vertical: isLargeScreen ? 32 : 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,


                      children: [
                        if (slotData != null) ...[
                          _buildWelcomeSection(userName),
                          SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 32)),
                        ],
                        if (slotData == null)
                          _buildNoSlotAssignedCard()
                        else
                          _buildSlotDashboard(slotData),
                        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 24)),
                        // Add some bottom padding for web view
                        if (isLargeScreen) const SizedBox(height: 40),
                      ],

                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(String userName) {
    final isLargeScreen = _isLargeScreen(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isLargeScreen ? 28 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isLargeScreen ? 24 : 20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            blurRadius: isLargeScreen ? 16 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isLargeScreen ? 16 : 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(isLargeScreen ? 20 : 16),
            ),
            child: Icon(
              Icons.person_rounded,
              color: Theme.of(context).colorScheme.onPrimary,
              size: isLargeScreen ? 36 : 28,
            ),
          ),
          SizedBox(width: isLargeScreen ? 20 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
                    fontSize: isLargeScreen ? 18 : 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: isLargeScreen ? 28 : 24,
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
    final isLargeScreen = _isLargeScreen(context);

    return FutureBuilder<Map<String, dynamic>?>(
      future: _backend.fetchSlotRequest(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isLargeScreen ? 500 : double.infinity,
              ),
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        }

        final slotRequest = snapshot.data;
        Widget cardContent;

        if (slotRequest != null) {
          final status = slotRequest['status'] ?? 'pending';
          final timestamp = slotRequest['timestamp'];
          String dateStr = '';
          if (timestamp is Timestamp) {
            dateStr = DateFormat('MMM dd, yyyy - hh:mm a').format(timestamp.toDate());
          }

          cardContent = Column(
            children: [
              Container(
                padding: EdgeInsets.all(isLargeScreen ? 20 : 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(isLargeScreen ? 20 : 16),
                ),
                child: Icon(
                  Icons.hourglass_top_rounded,
                  size: isLargeScreen ? 56 : 40,
                  color: status == 'approved'
                      ? Colors.green
                      : status == 'rejected'
                      ? Colors.red
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(height: isLargeScreen ? 24 : 20),
              Text(
                status == 'approved'
                    ? 'Slot Request Approved'
                    : status == 'rejected'
                    ? 'Slot Request Rejected'
                    : 'Slot Request Pending',
                style: TextStyle(
                  fontSize: isLargeScreen ? 26 : 22,
                  fontWeight: FontWeight.bold,
                  color: status == 'approved'
                      ? Colors.green[800]
                      : status == 'rejected'
                      ? Colors.red[800]
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(height: isLargeScreen ? 16 : 12),
              Text(
                'Your request to admin is currently "$status".\n${dateStr.isNotEmpty ? 'Submitted: $dateStr' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isLargeScreen ? 18 : 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  height: 1.4,
                ),
              ),
              if (status == 'rejected') ...[
                SizedBox(height: isLargeScreen ? 20 : 16),
                Text(
                  'You may contact admin for further info.',
                  style: TextStyle(
                    color: Colors.red[400],
                    fontWeight: FontWeight.w600,
                    fontSize: isLargeScreen ? 16 : 14,
                  ),
                ),
              ],
            ],
          );
        } else {
          cardContent = Column(
            children: [
              Container(
                padding: EdgeInsets.all(isLargeScreen ? 20 : 16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(isLargeScreen ? 20 : 16),
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: isLargeScreen ? 56 : 40,
                  color: Colors.orange[600],
                ),
              ),
              SizedBox(height: isLargeScreen ? 24 : 20),
              Text(
                'No Parking Slot Assigned',
                style: TextStyle(
                  fontSize: isLargeScreen ? 26 : 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(height: isLargeScreen ? 16 : 12),
              Text(
                'You don\'t have a parking slot assigned yet.\nContact admin to request one.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isLargeScreen ? 18 : 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  height: 1.4,
                ),
              ),
              SizedBox(height: isLargeScreen ? 32 : 24),
              SizedBox(
                width: isLargeScreen ? 300 : double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _handleSlotRequest();
                  },
                  icon: const Icon(Icons.contact_support_rounded),
                  label: const Text("Contact Admin"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: isLargeScreen ? 18 : 16,
                      horizontal: isLargeScreen ? 24 : 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(isLargeScreen ? 16 : 12),
                    ),
                    textStyle: TextStyle(
                      fontSize: isLargeScreen ? 18 : 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isLargeScreen ? 600 : double.infinity,
            ),
            child: Card(
              elevation: isLargeScreen ? 6 : 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isLargeScreen ? 24 : 16),
              ),
              child: Container(
                padding: EdgeInsets.all(isLargeScreen ? 32 : 20),
                child: cardContent,
              ),
            ),
          ),
        );
      },
    );
  }


  Future<void> _handleSlotRequest() async {
    // Call the requestNewSlot method from your backend
    final result = await _backend.requestNewSlot();

    if (result['success']) {
      _backend.showSnackBar(context, result['message'], isError: false);
      // Refresh the UI to show the new request status
      setState(() {});
    } else {
      _backend.showSnackBar(context, result['message'], isError: true);
    }
  }


}