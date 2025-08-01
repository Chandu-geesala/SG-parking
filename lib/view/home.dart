import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/backgroundAnimations.dart';
import '../utils/booking_cards.dart';
import 'package:park_sg/utils/theme_provider.dart';
import '../viewModel/bookingBackend.dart';
import 'dart:math' as math;




import 'dart:ui';



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
                          fontFamily: "Mont",fontSize: 16,
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

// Replace the _buildWelcomeSection method with this minimal design:

  Widget _buildWelcomeSection(String userName) {
    return _WelcomeSectionState(userName: userName);
  }


  Widget _buildNoSlotAssignedCard() {
    final isLargeScreen = _isLargeScreen(context);

    return FutureBuilder<Map<String, dynamic>>(
      future: _backend.getUserRequestsSummary(),
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

        final summary = snapshot.data ?? {};
        final slotRequest = summary['latestRequest'] as Map<String, dynamic>?;
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
                  fontFamily: "Mont",fontSize: isLargeScreen ? 26 : 22,
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
                  fontFamily: "Mont",fontSize: isLargeScreen ? 18 : 16,
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
                    fontFamily: "Mont",fontSize: isLargeScreen ? 16 : 14,
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
                  fontFamily: "Mont",fontSize: isLargeScreen ? 26 : 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(height: isLargeScreen ? 16 : 12),
              Text(
                'You don\'t have a parking slot assigned yet.\nContact admin to request one.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: "Mont",fontSize: isLargeScreen ? 18 : 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  height: 1.4,
                ),
              ),
              SizedBox(height: isLargeScreen ? 32 : 24),
              SizedBox(
                width: isLargeScreen ? 300 : double.infinity,
                child: ElevatedButton.icon(
                  onPressed: null,
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
                      fontFamily: "Mont",fontSize: isLargeScreen ? 18 : 16,
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




}



class _WelcomeSectionState extends StatefulWidget {
  final String userName;

  const _WelcomeSectionState({required this.userName});

  @override
  State<_WelcomeSectionState> createState() => _WelcomeSectionStateImpl();
}

class _WelcomeSectionStateImpl extends State<_WelcomeSectionState>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _fadeController;
  late AnimationController _shimmerController;

  late Animation<double> _waveAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _shimmerController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _waveAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _waveController,
      curve: Curves.easeInOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));

    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    ));

    _fadeController.forward();
  }

  @override
  void dispose() {
    _waveController.dispose();
    _fadeController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        margin: EdgeInsets.all(isLargeScreen ? 16 : 12),
        child: Stack(
          children: [
            // Glass container (with internal background animation)
            _buildGlassContainer(isLargeScreen, isDark),

            // Shimmer effect
            _buildShimmerEffect(isLargeScreen),
          ],
        ),
      ),
    );
  }


  Widget _buildGlassContainer(bool isLargeScreen, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(isLargeScreen ? 24 : 20),
      child: Stack(
        children: [
          // Animated background particles - INSIDE the glass container
          if (isDark) _buildBackgroundParticles(isDark),

          // Glass effect with backdrop filter
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              width: double.infinity, // Ensure the container has explicit width
              padding: EdgeInsets.symmetric(
                horizontal: isLargeScreen ? 24 : 20,
                vertical: isLargeScreen ? 20 : 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.05),
                  ]
                      : [
                    Colors.white.withOpacity(0.25),
                    Colors.white.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(isLargeScreen ? 24 : 20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withOpacity(0.3)
                        : Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: _buildContent(isLargeScreen, isDark),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildContent(bool isLargeScreen, bool isDark) {
    final greetings = _getTimeBasedGreeting();

    return Row(
      children: [

        // Text content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Greeting text
              _buildGreetingText(greetings['greeting']!, isLargeScreen, isDark),

              const SizedBox(height: 4),

              // Welcome message
              _buildWelcomeText(
                greetings['message']!.replaceFirst('{name}', widget.userName),
                isLargeScreen,
                isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedIcon(bool isLargeScreen, bool isDark) {
    return AnimatedBuilder(
      animation: _waveAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + math.sin(_waveAnimation.value * 2 * math.pi) * 0.1,
          child: Container(
            padding: EdgeInsets.all(isLargeScreen ? 12 : 10),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: isDark
                    ? [
                  const Color(0xFF6366F1).withOpacity(0.8),
                  const Color(0xFF8B5CF6).withOpacity(0.6),
                  const Color(0xFFA855F7).withOpacity(0.4),
                ]
                    : [
                  const Color(0xFF3B82F6).withOpacity(0.8),
                  const Color(0xFF6366F1).withOpacity(0.6),
                  const Color(0xFF8B5CF6).withOpacity(0.4),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0xFF6366F1).withOpacity(0.3)
                      : const Color(0xFF3B82F6).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _getTimeBasedIcon(),
              color: Colors.white,
              size: isLargeScreen ? 24 : 20,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGreetingText(String greeting, bool isLargeScreen, bool isDark) {
    return Text(
      greeting,
      style: TextStyle(
        color: isDark
            ? Colors.white.withOpacity(0.8)
            : Colors.black.withOpacity(0.7),
        fontSize: isLargeScreen ? 14 : 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildWelcomeText(String message, bool isLargeScreen, bool isDark) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: isDark
            ? [
          const Color(0xFFFFFFFF),
          const Color(0xFFF1F5F9),
          const Color(0xFFE2E8F0),
        ]
            : [
          const Color(0xFF1E293B),
          const Color(0xFF334155),
          const Color(0xFF475569),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Text(
        message,
        style: TextStyle(
          color: Colors.white,
          fontSize: isLargeScreen ? 18 : 16,
          fontWeight: FontWeight.w700,
          height: 1.3,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildBackgroundParticles(bool isDark) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _waveAnimation,
        builder: (context, child) {
          return CustomPaint(
            painter: BackgroundPainter(_waveAnimation),
            // Remove Size.infinite - let it inherit from parent constraints
          );
        },
      ),
    );
  }


  Widget _buildShimmerEffect(bool isLargeScreen) {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(isLargeScreen ? 24 : 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white.withOpacity(0.1),
                  Colors.transparent,
                ],
                stops: [
                  (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                  _shimmerAnimation.value.clamp(0.0, 1.0),
                  (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        );
      },
    );
  }

  Map<String, String> _getTimeBasedGreeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return {
        'greeting': '🌅 Good Morning',
        'message': 'Ready for today, {name}?',
      };
    } else if (hour < 17) {
      return {
        'greeting': '☀️ Good Afternoon',
        'message': 'Great to see you, {name}!',
      };
    } else if (hour < 21) {
      return {
        'greeting': '🌆 Good Evening',
        'message': 'Welcome back, {name}!',
      };
    } else {
      return {
        'greeting': '🌙 Good Night',
        'message': 'Working late, {name}?',
      };
    }
  }

  IconData _getTimeBasedIcon() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return Icons.wb_sunny_outlined;
    } else if (hour < 17) {
      return Icons.brightness_high_outlined;
    } else if (hour < 21) {
      return Icons.brightness_6_outlined;
    } else {
      return Icons.bedtime_outlined;
    }
  }
}
