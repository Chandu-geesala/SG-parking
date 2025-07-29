import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:park_sg/view/admin/requests.dart';
import 'package:park_sg/view/admin/slots.dart';
import 'package:park_sg/view/admin/users.dart';
import 'package:park_sg/viewModel/authService.dart';
import '../../utils/theme_provider.dart';
import '../../viewModel/bookingBackend.dart';
import 'allocation.dart';
import 'analytics.dart';
import 'bookings.dart';
import 'package:park_sg/utils/booking_cards.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final AuthService _authService = AuthService();
  final BookingBackend _backend = BookingBackend();
  User? _currentUser;
  bool _isLoadingProfile = true;
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
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
      await _loadProfileData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Data refreshed successfully'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh data: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  String _getDisplayName() {
    if (_profileData != null && _profileData!['name'] != null && (_profileData!['name'] as String).isNotEmpty) {
      return _profileData!['name'];
    }
    if (_currentUser?.displayName != null && _currentUser!.displayName!.isNotEmpty) {
      return _currentUser!.displayName!;
    }
    if (_currentUser?.email != null && _currentUser!.email!.isNotEmpty) {
      return _currentUser!.email!.split('@').first;
    }
    return 'Admin';
  }

  String? _getPhotoUrl() {
    final pdUrl = _profileData?['photoUrl'];
    if (pdUrl != null && pdUrl is String && pdUrl.isNotEmpty) {
      return pdUrl;
    }
    final cuUrl = _currentUser?.photoURL;
    if (cuUrl != null && cuUrl.isNotEmpty) {
      return cuUrl;
    }
    return null;
  }

  bool _isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width > 768;
  }

  int _getGridCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 4;
    if (width > 768) return 3;
    return 2;
  }

  EdgeInsets _getResponsivePadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return const EdgeInsets.symmetric(horizontal: 80, vertical: 20);
    if (width > 768) return const EdgeInsets.symmetric(horizontal: 40, vertical: 20);
    return const EdgeInsets.all(20);
  }

  double? _getMaxWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 1200;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = _isLargeScreen(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: theme.appBarTheme.elevation ?? 1,
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
          const ThemeSwitchWidget(),
          _buildProfileMenu(context),
          SizedBox(width: isLargeScreen ? 80 : 16),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: colorScheme.primary,
        backgroundColor: theme.cardColor,
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
                  // Admin Controls Section (Quick Actions)
                  Text(
                    'Admin Controls',
                    style: TextStyle(
                      fontSize: isLargeScreen ? 22 : 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: isLargeScreen ? 24 : 20),
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
                            icon: Icons.auto_graph_rounded,
                            title: 'Booking Dashboard',
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
                            icon: Icons.admin_panel_settings,
                            title: 'Slots Allocation',
                            color: Colors.purple,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AllocationUI(),
                                ),
                              );
                            },
                          ),


                          _buildActionCard(
                            icon: Icons.people_outline,
                            title: 'All Users',
                            color: Colors.orangeAccent,
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
                            color: Colors.blueAccent,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ParkingSlotsPage(),
                                ),
                              );
                            },
                          ),

                          // _buildActionCard(
                          //   icon: Icons.remove_from_queue,
                          //   title: 'Requests',
                          //   subtitle: 'Manage privileges',
                          //   color: Colors.orangeAccent,
                          //   onTap: () {
                          //     Navigator.push(
                          //       context,
                          //       MaterialPageRoute(
                          //         builder: (context) => const RequestsPage(),
                          //       ),
                          //     );
                          //   },
                          // ),


                        ],
                      );
                    },
                  ),

                  SizedBox(height: isLargeScreen ? 48 : 32),

                  // User Controls Section (BookingCards)
                  Text(
                    'User Controls',
                    style: TextStyle(
                      fontSize: isLargeScreen ? 22 : 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: isLargeScreen ? 24 : 16),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isLargeScreen ? 32 : 20),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BookingCards(),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoadingProfile) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: colorScheme.surfaceVariant,
          radius: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        ),
      );
    }

    final photoUrl = _getPhotoUrl();
    final displayName = _getDisplayName();

    return PopupMenuButton<String>(
      offset: const Offset(16, 48),
      color: theme.cardColor,
      icon: photoUrl == null || photoUrl.isEmpty
          ? CircleAvatar(
        backgroundColor: colorScheme.surfaceVariant,
        radius: 20,
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: colorScheme.onSurfaceVariant,
          ),
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
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                'Log out',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isLargeScreen = _isLargeScreen(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate responsive dimensions based on available width
        final cardWidth = constraints.maxWidth;
        final isVerySmall = cardWidth < 150;
        final isSmall = cardWidth < 200;

        return Container(
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: isLargeScreen ? 140 : 120,
            maxHeight: isLargeScreen ? 180 : 160,
          ),
          decoration: BoxDecoration(
            // Attractive gradient background for dark mode, solid for light
            gradient: isDark
                ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1E293B), // Dark slate
                const Color(0xFF334155), // Lighter slate
                const Color(0xFF1E293B).withOpacity(0.8), // Subtle variation
              ],
              stops: const [0.0, 0.6, 1.0],
            )
                : null,
            color: isDark ? null : Colors.white,
            borderRadius: BorderRadius.circular(16),

            // Enhanced border with accent color integration
            border: Border.all(
              color: isDark
                  ? color.withOpacity(0.3) // More visible accent color border
                  : Colors.grey.withOpacity(0.1),
              width: isDark ? 1.2 : 0.5,
            ),

            // Multi-layer shadow system for depth
            boxShadow: [
              // Primary shadow
              BoxShadow(
                color: isDark
                    ? color.withOpacity(0.15) // Colored glow effect
                    : Colors.grey.withOpacity(0.1),
                offset: const Offset(0, 4),
                blurRadius: isDark ? 16 : 6,
                spreadRadius: 0,
              ),
              // Secondary depth shadow for dark mode
              if (isDark) ...[
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  offset: const Offset(0, 2),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
                // Subtle inner glow
                BoxShadow(
                  color: color.withOpacity(0.05),
                  offset: const Offset(0, 0),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isVerySmall ? 8 : (isSmall ? 12 : (isLargeScreen ? 20 : 16)),
                  vertical: isVerySmall ? 12 : (isLargeScreen ? 20 : 16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon container with flexible sizing
                    Flexible(
                      flex: 2,
                      child: Container(
                        padding: EdgeInsets.all(
                            isVerySmall ? 8 : (isSmall ? 10 : (isLargeScreen ? 16 : 12))
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icon,
                          size: isVerySmall ? 20 : (isSmall ? 24 : (isLargeScreen ? 28 : 24)),
                          color: theme.brightness == Brightness.dark
                              ? color.withOpacity(0.8)
                              : color,
                        ),
                      ),
                    ),

                    SizedBox(height: isVerySmall ? 8 : (isLargeScreen ? 16 : 12)),

                    // Title with flexible text handling
                    Flexible(
                      flex: 1,
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: isVerySmall ? 11 : (isSmall ? 12 : (isLargeScreen ? 14 : 13)),
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                          height: 1.2, // Tighter line height for better spacing
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                      ),
                    ),

                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }



  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}

