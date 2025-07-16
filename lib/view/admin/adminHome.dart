import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:park_sg/view/admin/requests.dart';
import 'package:park_sg/view/admin/slots.dart';
import 'package:park_sg/view/admin/users.dart';
import 'package:park_sg/viewModel/authService.dart';
import '../../viewModel/bookingBackend.dart';
import 'analytics.dart';
import 'bookings.dart';
import 'package:park_sg/utils/booking_cards.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final SignUpService _authService = SignUpService();
  final BookingBackend _backend = BookingBackend();
  User? _currentUser;
  bool _isLoadingProfile = true;
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    // _currentUser = _authService.getCurrentUser();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() {
      _isLoadingProfile = true;
    });

    try {
      final profileData = await _backend.getProfileData();
      setState(() {
        _profileData = profileData;
        _isLoadingProfile = false;
      });
    } catch (e) {
      print('Error loading profile data: $e');
      setState(() {
        _profileData = null;
        _isLoadingProfile = false;
      });
    }
  }

  // Pull-to-refresh handler
  Future<void> _handleRefresh() async {
    try {
      // Refresh profile data
      await _loadProfileData();

      // You can add other refresh operations here if needed
      // For example, refreshing booking cards data, user counts, etc.

      // Show a brief success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data refreshed successfully'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Show error message if refresh fails
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh data: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getDisplayName() {
    // 1. Try profileData name
    if (_profileData != null && _profileData!['name'] != null && (_profileData!['name'] as String).isNotEmpty) {
      return _profileData!['name'];
    }
    // 2. Try FirebaseAuth displayName
    if (_currentUser?.displayName != null && _currentUser!.displayName!.isNotEmpty) {
      return _currentUser!.displayName!;
    }
    // 3. Fallback to email prefix
    if (_currentUser?.email != null && _currentUser!.email!.isNotEmpty) {
      return _currentUser!.email!.split('@').first;
    }
    return 'Admin';
  }

  String? _getPhotoUrl() {
    // 1. Try profileData photoUrl
    final pdUrl = _profileData?['photoUrl'];
    if (pdUrl != null && pdUrl is String && pdUrl.isNotEmpty) {
      return pdUrl;
    }
    // 2. Try FirebaseAuth photoURL
    final cuUrl = _currentUser?.photoURL;
    if (cuUrl != null && cuUrl.isNotEmpty) {
      return cuUrl;
    }
    // 3. No image
    return null;
  }

  // Helper method to determine if we're on a large screen
  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width > 768;
  }

  // Helper method to get responsive grid count
  int _getGridCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 4; // Desktop
    if (width > 768) return 3;  // Tablet
    return 2; // Mobile
  }

  // Helper method to get responsive padding
  EdgeInsets _getResponsivePadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return const EdgeInsets.symmetric(horizontal: 80, vertical: 20);
    if (width > 768) return const EdgeInsets.symmetric(horizontal: 40, vertical: 20);
    return const EdgeInsets.all(20);
  }

  // Helper method to get max width for content
  double? _getMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 1200;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = _isLargeScreen(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: isLargeScreen,
        title: Row(
          mainAxisSize: isLargeScreen ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Image.asset(
              'assets/txt.png',
              height: 40,
              fit: BoxFit.contain,
            ),
          ],
        ),
        actions: [
          _buildProfileMenu(context),
          SizedBox(width: isLargeScreen ? 80 : 16),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: Colors.blue,
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: _getMaxWidth(context) ?? double.infinity,
              ),
              padding: _getResponsivePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Card
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isLargeScreen ? 32 : 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
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
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome back, ${_getDisplayName()}!',
                                    style: TextStyle(
                                      fontSize: isLargeScreen ? 24 : 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _currentUser?.email ?? 'Ready to manage the lot like a pro?',
                                    style: TextStyle(
                                      fontSize: isLargeScreen ? 16 : 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),

                  SizedBox(height: isLargeScreen ? 48 : 32),

                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: isLargeScreen ? 22 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),

                  SizedBox(height: isLargeScreen ? 24 : 20),

                  // Action Cards Grid - Responsive
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = _getGridCount(context);
                      final childAspectRatio = isLargeScreen ? 1.2 : 1.1;

                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: isLargeScreen ? 24 : 16,
                        mainAxisSpacing: isLargeScreen ? 24 : 16,
                        childAspectRatio: childAspectRatio,
                        children: [
                          _buildActionCard(
                            icon: Icons.people_outline,
                            title: 'All Users',
                            subtitle: 'Manage user accounts',
                            color: Colors.blue,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AllUsersPage(),
                                ),
                              );
                            },
                          ),
                          _buildActionCard(
                            icon: Icons.local_parking,
                            title: 'All Slots',
                            subtitle: 'Manage privileges',
                            color: Colors.purple,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const DataUploadUI(),
                                ),
                              );
                            },
                          ),
                          _buildActionCard(
                            icon: Icons.update,
                            title: 'Booking Data',
                            subtitle: 'Manage privileges',
                            color: Colors.greenAccent,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const BookingDashboard(),
                                ),
                              );
                            },
                          ),
                          _buildActionCard(
                            icon: Icons.remove_from_queue,
                            title: 'Requests',
                            subtitle: 'Manage privileges',
                            color: Colors.orangeAccent,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RequestsPage(),
                                ),
                              );
                            },
                          ),
                          _buildActionCard(
                            icon: Icons.analytics_outlined,
                            title: 'Analytics',
                            subtitle: 'View insights',
                            color: Colors.teal,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AnalyticsPage(),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                  SizedBox(height: isLargeScreen ? 48 : 32),

                  // Quick Stats Section
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isLargeScreen ? 32 : 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BookingCards(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileMenu(BuildContext context) {
    if (_isLoadingProfile) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.grey,
          radius: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    final photoUrl = _getPhotoUrl();
    final displayName = _getDisplayName();

    return PopupMenuButton<String>(
      offset: const Offset(16, 48),
      icon: photoUrl == null || photoUrl.isEmpty
          ? CircleAvatar(
        backgroundColor: Colors.blueGrey.shade200,
        radius: 20,
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      )
          : CircleAvatar(
        backgroundImage: NetworkImage(photoUrl),
        radius: 20,
        onBackgroundImageError: (_, __) {},
      ),
      onSelected: (value) async {
        if (value == 'logout') {
          await _backend.signOut(context);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, color: Colors.red),
              SizedBox(width: 8),
              Text('Log out'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isLargeScreen = _isLargeScreen(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(isLargeScreen ? 24 : 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(isLargeScreen ? 20 : 16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: isLargeScreen ? 32 : 28,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: isLargeScreen ? 20 : 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isLargeScreen ? 16 : 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (isLargeScreen) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.black,
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}