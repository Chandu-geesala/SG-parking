import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:park_sg/view/splashScreen/my_splash_screen.dart';
import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter
import '../../viewModel/authService.dart';
import 'auth_screen.dart';

class VerifyEmailPage extends StatefulWidget {
  final String email;
  const VerifyEmailPage({Key? key, required this.email}) : super(key: key);

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage>
    with TickerProviderStateMixin {
  final SignUpService _signUpService = SignUpService();
  bool? isVerified;
  bool isResending = false;
  bool isCancelling = false; // Add flag to prevent multiple cancel operations
  StreamSubscription<bool>? emailVerificationSubscription;
  Timer? pendingSignupTimer; // Store timer reference

  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late AnimationController _backgroundAnimationController;
  late AnimationController _pulseController;

  // Animations
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _backgroundAnimation;
  late Animation<double> _pulseAnimation;

  // Add theme-related getters
  ThemeData get _currentTheme {
    final brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark ? _darkTheme : _lightTheme;
  }

  bool get isDarkMode {
    final brightness = MediaQuery.of(context).platformBrightness;
    return brightness == Brightness.dark;
  }

  ThemeData get _lightTheme => ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.orange,
    scaffoldBackgroundColor: Colors.grey.shade50,
    cardColor: Colors.white,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.black87),
      bodyMedium: TextStyle(color: Colors.black54),
    ),
  );

  ThemeData get _darkTheme => ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.orange,
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardColor: const Color(0xFF1E1E1E),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white70),
    ),
  );

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startEntryAnimation();
    _startEmailVerificationMonitor();

    // FIXED: Store timer reference and add better error handling
    pendingSignupTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        bool hasPendingSignup = await _signUpService.hasPendingSignup();
        if (!hasPendingSignup) {
          timer.cancel();
          print('⚠️ Signup data disappeared, auto-cancelling');
          await _cancelSignUpSafely();
        }
      } catch (e) {
        print('❌ Error checking pending signup: $e');
        // Don't auto-cancel on error, just log it
      }
    });
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _backgroundAnimationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));

    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(_backgroundAnimationController);

    _pulseAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _startEntryAnimation() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _fadeController.forward();
        _slideController.forward();
      }
    });
  }

  @override
  void dispose() {
    // FIXED: Proper cleanup to prevent memory leaks and errors
    emailVerificationSubscription?.cancel();
    pendingSignupTimer?.cancel();
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _backgroundAnimationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _startEmailVerificationMonitor() {
    emailVerificationSubscription?.cancel();
    emailVerificationSubscription = _signUpService.monitorEmailVerification().listen(
          (verified) async {
        if (!mounted) return;

        setState(() {
          isVerified = verified;
        });

        try {
          bool hasPendingSignup = await _signUpService.hasPendingSignup();

          if (!hasPendingSignup) {
            print('⚠️ No signup data found, cancelling verification process');
            await _cancelSignUpSafely();
            return;
          }

          if (verified) {
            await Future.delayed(const Duration(seconds: 1));
            await _signUpService.handleEmailVerificationComplete();
            _showMessage('Email verified! Account created successfully!');
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => MysplashScreen()),
                    (route) => false,
              );
            }
          }
        } catch (e) {
          print('❌ Error in email verification monitor: $e');
          if (mounted) {
            _showMessage('An error occurred during verification. Please try again.');
          }
        }
      },
      onError: (error) {
        print('❌ Email verification stream error: $error');
        if (mounted) {
          _showMessage('Verification monitoring error. Please refresh the page.');
        }
      },
    );
  }

  Future<void> _resendVerificationEmail() async {
    if (isResending) return; // Prevent multiple simultaneous requests

    setState(() => isResending = true);
    HapticFeedback.lightImpact();

    try {
      final result = await _signUpService.resendEmailVerification();
      if (mounted) {
        _showMessage(result['message'] ?? 'Verification email sent');
      }
    } catch (e) {
      print('❌ Error resending verification email: $e');
      if (mounted) {
        _showMessage('Failed to resend email. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => isResending = false);
      }
    }
  }

  // FIXED: Add safer cancel method to prevent multiple operations
  Future<void> _cancelSignUpSafely() async {
    if (isCancelling) {
      print('⚠️ Cancel already in progress, ignoring duplicate request');
      return;
    }
    await _cancelSignUp();
  }

  Future<void> _cancelSignUp() async {
    if (isCancelling) return; // Prevent multiple cancel operations

    setState(() => isCancelling = true);

    try {
      HapticFeedback.mediumImpact();

      // FIXED: Show loading dialog with proper error handling
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _buildLoadingDialog(),
        );
      }

      // FIXED: Cancel subscriptions and timers first
      emailVerificationSubscription?.cancel();
      pendingSignupTimer?.cancel();

      // FIXED: Add timeout to prevent hanging
      await Future.wait([
        _signUpService.clearSignupData(),
        _deleteFirebaseUserSafely(),
      ]).timeout(
        Duration(seconds: 15),
        onTimeout: () {
          print('⚠️ Cancel operation timed out');
          throw TimeoutException('Operation timed out', Duration(seconds: 15));
        },
      );

      // FIXED: Ensure Firebase signout
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        print('⚠️ Firebase signout error (non-critical): $e');
      }

      // FIXED: Always dismiss loading dialog before navigation
      if (mounted) {
        Navigator.of(context).pop(); // Dismiss loading dialog
      }

      // FIXED: Navigate with better error handling
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MysplashScreen()),
              (route) => false,
        );
      }

      _showMessage('Signup cancelled successfully');

    } catch (e) {
      print('❌ Error during signup cancellation: $e');

      // FIXED: Always dismiss loading dialog on error
      if (mounted) {
        try {
          Navigator.of(context).pop(); // Dismiss loading dialog
        } catch (popError) {
          print('⚠️ Error dismissing dialog: $popError');
        }
      }

      // FIXED: Still try to navigate even if cleanup failed
      if (mounted) {
        _showMessage('Error cancelling signup, but returning to main screen');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MysplashScreen()),
              (route) => false,
        );
      }
    } finally {
      if (mounted) {
        setState(() => isCancelling = false);
      }
    }
  }

  // FIXED: Safer Firebase user deletion
  Future<void> _deleteFirebaseUserSafely() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && !currentUser.emailVerified) {
        await currentUser.delete();
        print('✅ Unverified Firebase user deleted');
      }
    } catch (e) {
      print('⚠️ Could not delete Firebase user (non-critical): $e');
      // This is non-critical - user might be already deleted or have different state
    }
  }

  Widget _buildLoadingDialog() {
    return WillPopScope(
      onWillPop: () async => false, // Prevent dismissing with back button
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 50),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.white.withOpacity(0.12)
                : Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.15),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Padding(
                padding: const EdgeInsets.all(35),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Cancelling signup...',
                      style: TextStyle(
                        color: _currentTheme.textTheme.bodyLarge!.color,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMessage(String msg) {
    if (!mounted) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('❌ Error showing message: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Theme(
      data: _currentTheme,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Container(
          width: screenWidth,
          height: screenHeight,
          child: AnimatedBuilder(
            animation: _backgroundAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDarkMode
                        ? [
                      const Color(0xFF1A1A2E),
                      const Color(0xFF16213E),
                      const Color(0xFF0F3460),
                    ]
                        : [
                      const Color(0xFFE67E22), // SenecaGlobal Orange
                      const Color(0x7E6DDC94), // Lighter Orange variant
                      const Color(0xFF8FBC8F), // SenecaGlobal Olive Green
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(_backgroundAnimation.value),
                  ),
                ),
                child: Stack(
                  children: [
                    // Animated background particles
                    ...List.generate(5, (index) => _buildAnimatedParticle(index)),

                    // Main content
                    SafeArea(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 20 : 40,
                          vertical: 20,
                        ),
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: screenHeight - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - 40,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              // Back button
                              _buildBackButton(),
                              SizedBox(height: isSmallScreen ? 20 : 40),
                              // Main verification card
                              _buildGlassVerificationContainer(isSmallScreen),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedParticle(int index) {
    return AnimatedBuilder(
      animation: _backgroundAnimation,
      builder: (context, child) {
        final double offset = index * 0.5;
        final double x = 50 + (index * 80) + 30 * math.sin(_backgroundAnimation.value + offset);
        final double y = 100 + (index * 120) + 20 * math.cos(_backgroundAnimation.value + offset);

        return Positioned(
          left: x,
          top: y,
          child: Container(
            width: 6 + (index * 2),
            height: 6 + (index * 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isDarkMode ? Colors.orange : Colors.white)
                  .withOpacity(0.4),
              boxShadow: [
                BoxShadow(
                  color: (isDarkMode ? Colors.orange : Colors.white)
                      .withOpacity(0.3),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBackButton() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Align(
        alignment: Alignment.topLeft,
        child: GestureDetector(
          onTap: isCancelling ? null : () {
            HapticFeedback.lightImpact();
            _cancelSignUpSafely();
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCancelling
                  ? Colors.grey.withOpacity(0.3)
                  : isDarkMode
                  ? Colors.white.withOpacity(0.15)
                  : Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Icon(
                  Icons.arrow_back_ios,
                  color: isCancelling
                      ? Colors.grey
                      : isDarkMode
                      ? Colors.white
                      : Colors.indigo.shade700,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassVerificationContainer(bool isSmallScreen) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxWidth: isSmallScreen ? 380 : 450),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.white.withOpacity(0.12)
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(35),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white.withOpacity(0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isDarkMode
                    ? Colors.black.withOpacity(0.4)
                    : Colors.black.withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(35),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDarkMode
                        ? [
                      Colors.white.withOpacity(0.05),
                      Colors.white.withOpacity(0.02),
                    ]
                        : [
                      Colors.white.withOpacity(0.15),
                      Colors.white.withOpacity(0.08),
                    ],
                  ),
                ),
                padding: EdgeInsets.all(isSmallScreen ? 30 : 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    _buildTitle(),
                    SizedBox(height: isSmallScreen ? 15 : 20),

                    // Description and email
                    _buildEmailDescription(),
                    SizedBox(height: isSmallScreen ? 20 : 25),

                    // Spam warning
                    _buildSpamWarning(),
                    SizedBox(height: isSmallScreen ? 20 : 25),

                    // Verification status
                    _buildVerificationStatus(),
                    SizedBox(height: isSmallScreen ? 25 : 30),

                    // Action buttons
                    _buildActionButtons(isSmallScreen),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      'Email Verification',
      style: TextStyle(
        color: isDarkMode ? Colors.white : Colors.indigo.shade700,
        fontSize: 28,
        fontFamily: "Noto",
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildEmailDescription() {
    return Column(
      children: [
        Text(
          'We sent a verification email to:',
          style: TextStyle(
            color: _currentTheme.textTheme.bodyMedium!.color,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 15),
        Text(
          'After clicking the link, please return to this page to continue.',
          style: TextStyle(
            color: Colors.orange,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: Colors.orange.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Text(
            widget.email,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.orange,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildSpamWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.amber.withOpacity(0.2)
            : Colors.amber.shade50,
        border: Border.all(
          color: Colors.amber.withOpacity(0.5),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_amber,
            color: Colors.amber.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Please check your SPAM folder!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.amber.shade800,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationStatus() {
    if (isVerified == null) {
      return Column(
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            strokeWidth: 3,
          ),
          const SizedBox(height: 15),
          AnimatedCheckingText(),
        ],
      );
    } else if (isVerified == true) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withOpacity(0.2),
              border: Border.all(
                color: Colors.green.withOpacity(0.5),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.verified,
              color: Colors.green,
              size: 40,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            '🎉 Your email is verified!',
            style: TextStyle(
              fontSize: 18,
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orange.withOpacity(0.2),
              border: Border.all(
                color: Colors.orange.withOpacity(0.5),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.warning_amber,
              color: Colors.orange,
              size: 40,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            'Email not verified yet!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          AnimatedCheckingText(),
        ],
      );
    }
  }

  Widget _buildActionButtons(bool isSmallScreen) {
    return isSmallScreen
        ? Column(
      children: [
        _buildResendButton(),
        const SizedBox(height: 15),
        _buildCancelButton(),
      ],
    )
        : Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _buildResendButton(),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _buildCancelButton(),
          ),
        ),
      ],
    );
  }

  Widget _buildResendButton() {
    return GestureDetector(
      onTap: (isResending || isCancelling) ? null : _resendVerificationEmail,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          gradient: !(isResending || isCancelling)
              ? LinearGradient(
            colors: [Colors.orange.shade400, Colors.orange.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: (isResending || isCancelling) ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: (!(isResending || isCancelling) ? Colors.orange.shade400 : Colors.grey).withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isResending
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 2,
            ),
          )
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.refresh, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                "RESEND EMAIL",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontFamily: "Noto",
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: isCancelling ? null : _cancelSignUpSafely,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          gradient: !isCancelling
              ? LinearGradient(
            colors: [Colors.red.shade400, Colors.red.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: isCancelling ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: (!isCancelling ? Colors.red.shade400 : Colors.grey).withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isCancelling
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 2,
            ),
          )
              : Text(
            "CANCEL",
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontFamily: "Noto",
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedCheckingText extends StatefulWidget {
  @override
  State<AnimatedCheckingText> createState() => _AnimatedCheckingTextState();
}

class _AnimatedCheckingTextState extends State<AnimatedCheckingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int dotCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 600),
    )..addListener(() {
      if (_controller.status == AnimationStatus.completed) {
        if (mounted) {
          setState(() {
            dotCount = (dotCount + 1) % 4;
          });
          _controller.forward(from: 0.0);
        }
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String dots = '.' * dotCount;
    return Text(
      "Checking for verification$dots",
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: Colors.grey[600],
      ),
      textAlign: TextAlign.center,
    );
  }
}