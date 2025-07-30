import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter
import 'dart:async';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage>
    with TickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FocusNode _emailFocusNode = FocusNode();

  bool isLoading = false;
  bool isKeyboardVisible = false;
  bool isEmailSent = false;
  bool canResend = true;
  int resendTimer = 0;

  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late AnimationController _backgroundAnimationController;
  late AnimationController _successController;
  late AnimationController _shakeController;

  // Animations
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _backgroundAnimation;
  late Animation<double> _successAnimation;
  late Animation<double> _shakeAnimation;

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
    _setupKeyboardListener();
    _startEntryAnimation();
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

    _successController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

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

    _successAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    ));

    _shakeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticIn,
    ));
  }

  void _setupKeyboardListener() {
    _emailFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final bool keyboardVisible = _emailFocusNode.hasFocus;
    if (keyboardVisible != isKeyboardVisible) {
      setState(() {
        isKeyboardVisible = keyboardVisible;
      });
      if (keyboardVisible) {
        _scaleController.forward();
      } else {
        _scaleController.reverse();
      }
    }
  }

  void _startEntryAnimation() {
    Future.delayed(const Duration(milliseconds: 100), () {
      _fadeController.forward();
      _slideController.forward();
    });
  }

  void _startResendTimer() {
    setState(() {
      canResend = false;
      resendTimer = 60;
    });

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (resendTimer > 0) {
        setState(() {
          resendTimer--;
        });
      } else {
        setState(() {
          canResend = true;
        });
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _backgroundAnimationController.dispose();
    _successController.dispose();
    _shakeController.dispose();
    _emailFocusNode.dispose();
    emailController.dispose();
    super.dispose();
  }

  bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }

  Future<void> resetPassword() async {
    if (!_formKey.currentState!.validate()) {
      _triggerShakeAnimation();
      return;
    }

    HapticFeedback.lightImpact();
    final email = emailController.text.trim();

    setState(() => isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      setState(() {
        isLoading = false;
        isEmailSent = true;
      });

      _successController.forward();
      _startResendTimer();

      _showSnackBar(
        'Password reset link sent to your email!',
        Colors.green,
        icon: Icons.check_circle,
      );

      HapticFeedback.heavyImpact();
    } on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);
      HapticFeedback.mediumImpact();
      _triggerShakeAnimation();

      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email address.';
          break;
        case 'invalid-email':
          errorMessage = 'Please enter a valid email address.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many attempts. Please try again later.';
          break;
        default:
          errorMessage = 'An error occurred. Please try again.';
      }

      _showSnackBar(errorMessage, Colors.red, icon: Icons.error);
    } catch (e) {
      setState(() => isLoading = false);
      HapticFeedback.mediumImpact();
      _triggerShakeAnimation();
      _showSnackBar('An unexpected error occurred.', Colors.red, icon: Icons.error);
    }
  }

  void _triggerShakeAnimation() {
    _shakeController.reset();
    _shakeController.forward();
  }

  void _showSnackBar(String message, Color backgroundColor, {IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _buildProfessionalLightBackground() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: screenWidth,
      height: screenHeight,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF8F9FA), // Very light gray-white
            Color(0xFFFFFFFF), // Pure white
            Color(0xFFF5F7FA), // Light blue-gray
          ],
          stops: [0.0, 0.4, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Subtle geometric patterns
          ...List.generate(8, (index) => _buildGeometricShape(index, screenWidth, screenHeight)),

          // Brand color accents
          _buildBrandAccents(screenWidth, screenHeight),



        ],
      ),
    );
  }




  Widget _buildGeometricShape(int index, double screenWidth, double screenHeight) {
    final shapes = [
      // Large circles
      Positioned(
        top: -50,
        right: -30,
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF8FBC8F).withOpacity(0.08), // Seneca green
          ),
        ),
      ),
      Positioned(
        bottom: -100,
        left: -50,
        child: Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF7F50).withOpacity(0.06), // Seneca orange
          ),
        ),
      ),
      // Medium circles
      Positioned(
        top: screenHeight * 0.3,
        right: 20,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF8FBC8F).withOpacity(0.12),
          ),
        ),
      ),
      Positioned(
        top: screenHeight * 0.6,
        left: 30,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF7F50).withOpacity(0.1),
          ),
        ),
      ),
      // Curved elements inspired by Seneca logo
      Positioned(
        top: screenHeight * 0.2,
        left: screenWidth * 0.7,
        child: CustomPaint(
          size: const Size(100, 100),
          painter: CurvedShapePainter(const Color(0xFFFF7F50).withOpacity(0.08)),
        ),
      ),
      Positioned(
        bottom: screenHeight * 0.3,
        right: screenWidth * 0.8,
        child: CustomPaint(
          size: const Size(80, 80),
          painter: CurvedShapePainter(const Color(0xFF8FBC8F).withOpacity(0.1)),
        ),
      ),
      // Rectangular elements
      Positioned(
        top: screenHeight * 0.15,
        left: 10,
        child: Transform.rotate(
          angle: 0.2,
          child: Container(
            width: 40,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF8FBC8F).withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: screenHeight * 0.2,
        right: 15,
        child: Transform.rotate(
          angle: -0.3,
          child: Container(
            width: 50,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFFF7F50).withOpacity(0.05),
              borderRadius: BorderRadius.circular(25),
            ),
          ),
        ),
      ),
    ];

    return index < shapes.length ? shapes[index] : Container();
  }

  Widget _buildBrandAccents(double screenWidth, double screenHeight) {
    return Stack(
      children: [
        // Seneca swirl-inspired curved accent
        Positioned(
          top: screenHeight * 0.1,
          right: screenWidth * 0.1,
          child: CustomPaint(
            size: const Size(150, 100),
            painter: SenecaSwirlPainter(),
          ),
        ),
        // Bottom left accent
        Positioned(
          bottom: screenHeight * 0.1,
          left: screenWidth * 0.05,
          child: CustomPaint(
            size: const Size(120, 80),
            painter: SenecaSwirlPainter(isReversed: true),
          ),
        ),
      ],
    );
  }

  Widget _buildBrandTextElements(double screenWidth, double screenHeight) {
    return Stack(
      children: [
        // Watermark "SENECA" text
        Positioned(
          top: screenHeight * 0.08,
          left: screenWidth * 0.05,
          child: Opacity(
            opacity: 0.03,
            child: Transform.rotate(
              angle: -0.1,
              child: const Text(
                'SENECA',
                style: TextStyle(
                  fontFamily: "Mont",fontSize: 120,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF8FBC8F),
                  letterSpacing: 8,
                ),
              ),
            ),
          ),
        ),
        // Watermark "GLOBAL" text
        Positioned(
          bottom: screenHeight * 0.1,
          right: screenWidth * 0.05,
          child: Opacity(
            opacity: 0.025,
            child: Transform.rotate(
              angle: 0.05,
              child: const Text(
                'GLOBAL',
                style: TextStyle(
                  fontFamily: "Mont",fontSize: 80,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFF7F50),
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardHeight > 0;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Theme(
      data: _currentTheme,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Container(
          width: screenWidth,
          height: screenHeight,
          child: isDarkMode
              ? AnimatedBuilder(
            animation: _backgroundAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1A1A2E),
                      const Color(0xFF16213E),
                      const Color(0xFF0F3460),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(_backgroundAnimation.value),
                  ),
                ),
                child: Stack(
                  children: [
                    // Animated background particles for dark mode
                    ...List.generate(5, (index) => _buildAnimatedParticle(index)),
                    _buildMainContent(keyboardHeight, isKeyboardOpen, screenHeight),
                  ],
                ),
              );
            },
          )
              : Stack(
            children: [
              // Professional static background for light mode
              _buildProfessionalLightBackground(),
              _buildMainContent(keyboardHeight, isKeyboardOpen, screenHeight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(double keyboardHeight, bool isKeyboardOpen, double screenHeight) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          top: 0,
          left: 20,
          right: 20,
          bottom: math.max(20, keyboardHeight + 20),
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
              SizedBox(height: isKeyboardOpen ? 10 : 30),
              // Logo with glass container
              _buildLogoSection(),
              SizedBox(height: isKeyboardOpen ? 20 : 40),
              // Title section
              _buildTitleSection(),
              SizedBox(height: isKeyboardOpen ? 15 : 25),
              // Reset form with glass effect
              _buildGlassResetContainer(),
              const SizedBox(height: 20),
            ],
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
              color: Colors.orange.withOpacity(0.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
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
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.15)
                  : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.3)
                    : const Color(0xFF8FBC8F).withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.08),
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
                  color: isDarkMode ? Colors.white : const Color(0xFF2E5C2E),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5), // Less vertical padding
        decoration: BoxDecoration(
          color: _currentTheme.cardColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Image.asset(
          'assets/txt.png',
          width: 200,
          height: 100,
        ),
      ),
    );
  }




  Widget _buildTitleSection() {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_reset,
                  color: isDarkMode ? Colors.orange : const Color(0xFF2E5C2E),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  "Reset Password",
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : const Color(0xFF2E5C2E),
                    fontFamily: "Mont",fontSize: 28,

                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildGlassResetContainer() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final double offset = math.sin(_shakeAnimation.value * math.pi * 6) * 5;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 380),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.12)
                  : Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(35),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.2)
                    : const Color(0xFF8FBC8F).withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDarkMode
                      ? Colors.black.withOpacity(0.4)
                      : Colors.black.withOpacity(0.1),
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
                        Colors.white.withOpacity(0.9),
                        Colors.white.withOpacity(0.7),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(35),
                  child: Column(
                    children: [
                      if (!isEmailSent) ...[
                        _buildResetForm(),
                        const SizedBox(height: 25),
                        _buildResetButton(),
                      ] else ...[
                        _buildSuccessSection(),
                        const SizedBox(height: 25),
                        _buildResendButton(),
                      ],
                      const SizedBox(height: 20),
                      _buildBackToLoginLink(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuccessSection() {
    return ScaleTransition(
      scale: _successAnimation,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withOpacity(0.2),
              border: Border.all(color: Colors.green, width: 2),
            ),
            child: const Icon(
              Icons.email_outlined,
              color: Colors.green,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Email Sent Successfully!',
            style: TextStyle(
              color: _currentTheme.textTheme.bodyLarge!.color,
             fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'We\'ve sent a password reset link to ${emailController.text}',
            style: TextStyle(
              color: _currentTheme.textTheme.bodyMedium!.color,
              fontFamily: "Mont",fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResendButton() {
    return GestureDetector(
      onTap: canResend ? resetPassword : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        height: 55,
        decoration: BoxDecoration(
          gradient: canResend
              ? LinearGradient(
            colors: [const Color(0xFFFF7F50), const Color(0xFFFF6347)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: !canResend ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: (canResend ? const Color(0xFFFF7F50) : Colors.grey).withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text(
            canResend ? "RESEND EMAIL" : "RESEND IN ${resendTimer}s",
            style: const TextStyle(
              color: Colors.white,
              fontFamily: "Mont",fontSize: 17,

              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetForm() {
    return Form(
      key: _formKey,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.08),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: TextFormField(
          controller: emailController,
          focusNode: _emailFocusNode,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => resetPassword(),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your email';
            } else if (!isValidEmail(value)) {
              return 'Please enter a valid email address';
            }
            return null;
          },
          style: TextStyle(
            color: isDarkMode
                ? _currentTheme.textTheme.bodyLarge!.color
                : const Color(0xFF2E5C2E),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: 'Enter your Email Id',
            hintStyle: TextStyle(
              color: isDarkMode
                  ? _currentTheme.textTheme.bodyMedium!.color
                  : const Color(0xFF999999),
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.only(right: 10),
              child: Icon(
                Icons.email_outlined,
                color: _emailFocusNode.hasFocus
                    ? (isDarkMode ? Colors.orange.shade600 : const Color(0xFFFF7F50))
                    : (isDarkMode ? Colors.grey.shade400 : const Color(0xFF8FBC8F)),
                size: 22,
              ),
            ),
            filled: true,
            fillColor: isDarkMode
                ? Colors.grey[800]!.withOpacity(0.6)
                : Colors.white.withOpacity(0.9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.orange.shade500 : const Color(0xFFFF7F50),
                width: 2.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: Colors.red,
                width: 2,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: Colors.red,
                width: 2.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return GestureDetector(
      onTap: isLoading ? null : resetPassword,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        height: 55,
        decoration: BoxDecoration(
          gradient: !isLoading
              ? LinearGradient(
            colors: isDarkMode
                ? [Colors.orange.shade400, Colors.orange.shade600]
                : [const Color(0xFFFF7F50), const Color(0xFFFF6347)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: isLoading ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: (!isLoading
                  ? (isDarkMode ? Colors.orange.shade400 : const Color(0xFFFF7F50))
                  : Colors.grey).withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 2.5,
            ),
          )
              : const Text(
            "SEND RESET LINK",
            style: TextStyle(
              color: Colors.white,
              fontFamily: "Mont",fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackToLoginLink() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Back to Login',
              style: TextStyle(
                color: isDarkMode ? Colors.orange : const Color(0xFFFF7F50),
                fontFamily: "Mont",fontSize: 16,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: isDarkMode ? Colors.orange : const Color(0xFFFF7F50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter for curved shapes
class CurvedShapePainter extends CustomPainter {
  final Color color;

  CurvedShapePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.5);
    path.quadraticBezierTo(
        size.width * 0.3,
        0,
        size.width * 0.7,
        size.height * 0.3
    );
    path.quadraticBezierTo(
        size.width,
        size.height * 0.6,
        size.width * 0.6,
        size.height
    );
    path.quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.8,
        0,
        size.height * 0.5
    );
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// Custom painter for Seneca swirl background accents
class SenecaSwirlPainter extends CustomPainter {
  final bool isReversed;

  SenecaSwirlPainter({this.isReversed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF7F50).withOpacity(0.06)
      ..style = PaintingStyle.fill;

    final path = Path();

    if (!isReversed) {
      path.moveTo(size.width * 0.2, 0);
      path.quadraticBezierTo(
          size.width * 0.8,
          size.height * 0.3,
          size.width * 0.9,
          size.height * 0.7
      );
      path.quadraticBezierTo(
          size.width * 0.7,
          size.height,
          size.width * 0.3,
          size.height * 0.9
      );
      path.quadraticBezierTo(
          0,
          size.height * 0.6,
          size.width * 0.1,
          size.height * 0.2
      );
      path.quadraticBezierTo(
          size.width * 0.15,
          0,
          size.width * 0.2,
          0
      );
    } else {
      path.moveTo(size.width * 0.8, 0);
      path.quadraticBezierTo(
          size.width * 0.2,
          size.height * 0.3,
          size.width * 0.1,
          size.height * 0.7
      );
      path.quadraticBezierTo(
          size.width * 0.3,
          size.height,
          size.width * 0.7,
          size.height * 0.9
      );
      path.quadraticBezierTo(
          size.width,
          size.height * 0.6,
          size.width * 0.9,
          size.height * 0.2
      );
      path.quadraticBezierTo(
          size.width * 0.85,
          0,
          size.width * 0.8,
          0
      );
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// Custom painter for Seneca logo swirl
class SenecaLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF7F50)
      ..style = PaintingStyle.fill;

    final path = Path();

    // Create the characteristic Seneca swirl shape
    path.moveTo(size.width * 0.3, size.height * 0.1);
    path.quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.2,
        size.width * 0.9,
        size.height * 0.5
    );
    path.quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.8,
        size.width * 0.6,
        size.height * 0.9
    );
    path.quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.85,
        size.width * 0.1,
        size.height * 0.6
    );
    path.quadraticBezierTo(
        size.width * 0.05,
        size.height * 0.4,
        size.width * 0.2,
        size.height * 0.3
    );
    path.quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.2,
        size.width * 0.3,
        size.height * 0.1
    );

    // Add inner curve
    path.moveTo(size.width * 0.4, size.height * 0.3);
    path.quadraticBezierTo(
        size.width * 0.6,
        size.height * 0.35,
        size.width * 0.7,
        size.height * 0.5
    );
    path.quadraticBezierTo(
        size.width * 0.65,
        size.height * 0.65,
        size.width * 0.5,
        size.height * 0.7
    );
    path.quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.6,
        size.width * 0.3,
        size.height * 0.45
    );
    path.quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.35,
        size.width * 0.4,
        size.height * 0.3
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;

}