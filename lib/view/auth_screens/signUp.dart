import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:park_sg/view/auth_screens/verify.dart';

import '../../viewModel/authService.dart';
import 'auth_screen.dart';
import 'dart:ui'; // For ImageFilter

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage>
    with TickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final List<TextEditingController> vehicleControllers = [TextEditingController()];

  // Focus Nodes
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmFocusNode = FocusNode();
  final List<FocusNode> vehicleFocusNodes = [FocusNode()];

  // Animation Controllers
  late AnimationController _backgroundAnimationController;
  late AnimationController _cardAnimationController;
  late AnimationController _buttonAnimationController;
  late Animation<double> _backgroundAnimation;
  late Animation<double> _cardAnimation;
  late Animation<double> _buttonAnimation;

  // State variables
  bool isLoadingSignUp = false;
  bool? isVerified;
  StreamSubscription<bool>? emailVerificationSubscription;
  bool isEmailSent = false;
  bool isRestoredFromPending = false;


  // Add these with your existing state variables
  bool isKeyboardVisible = false;
  late AnimationController _keyboardAnimationController;
  late Animation<double> _keyboardAnimation;

  final SignUpService _signUpService = SignUpService();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeSignupState();
    _setupFocusListeners();
  }

  void _initializeAnimations() {
    _backgroundAnimationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    _keyboardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _keyboardAnimation = CurvedAnimation(
      parent: _keyboardAnimationController,
      curve: Curves.easeOutCubic,
    );

    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(_backgroundAnimationController);

    _cardAnimation = CurvedAnimation(
      parent: _cardAnimationController,
      curve: Curves.elasticOut,
    );

    _buttonAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _buttonAnimationController,
      curve: Curves.easeInOut,
    ));

    // Start animations
    _cardAnimationController.forward();
  }

  void _setupFocusListeners() {
    _emailFocusNode.addListener(_onFocusChange);
    _phoneFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
    _confirmFocusNode.addListener(_onFocusChange);
    for (final node in vehicleFocusNodes) {
      node.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    final bool keyboardVisible = _emailFocusNode.hasFocus ||
        _phoneFocusNode.hasFocus ||
        _passwordFocusNode.hasFocus ||
        _confirmFocusNode.hasFocus ||
        vehicleFocusNodes.any((node) => node.hasFocus);

    if (keyboardVisible != isKeyboardVisible) {
      setState(() {
        isKeyboardVisible = keyboardVisible;
      });
      if (keyboardVisible) {
        _keyboardAnimationController.forward();
      } else {
        _keyboardAnimationController.reverse();
      }
    }
  }



  @override
  void dispose() {
    // Dispose controllers
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    phoneController.dispose();
    _keyboardAnimationController.dispose();
    for (final controller in vehicleControllers) {
      controller.dispose();
    }

    // Dispose focus nodes
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    for (final node in vehicleFocusNodes) {
      node.dispose();
    }

    // Dispose animations
    _backgroundAnimationController.dispose();
    _cardAnimationController.dispose();
    _buttonAnimationController.dispose();

    emailVerificationSubscription?.cancel();
    super.dispose();
  }

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

  /// Initialize signup state - check for pending signup
  Future<void> _initializeSignupState() async {
    try {
      print('🔄 Initializing signup state...');
      bool hasPending = await _signUpService.hasPendingSignup();
      if (hasPending) {
        print('⏳ Found pending signup, restoring data...');
        await _restoreSignupData();
      } else {
        print('✅ No pending signup found, starting fresh');
      }
      await _signUpService.debugPrintState();
    } catch (e) {
      print('❌ Error initializing signup state: $e');
    }
  }

  void _startEmailVerificationMonitor() {
    emailVerificationSubscription?.cancel();
    emailVerificationSubscription = _signUpService.monitorEmailVerification().listen((verified) async {
      setState(() {
        isVerified = verified;
      });
      if (verified) {
        await Future.delayed(const Duration(seconds: 1));
        await _signUpService.handleEmailVerificationComplete();
      }
    });
  }

  Future<void> _restoreSignupData() async {
    try {
      Map<String, String> pendingData = await _signUpService.getPendingSignupData();
      if (pendingData.isNotEmpty) {
        emailController.text = pendingData['email'] ?? '';
        phoneController.text = pendingData['phone'] ?? '';
        passwordController.text = pendingData['password'] ?? '';
        confirmPasswordController.text = pendingData['confirmPassword'] ?? '';

        vehicleControllers.clear();
        final vehicles = (pendingData['vehicle'] ?? '').split(',').where((v) => v.isNotEmpty).toList();
        if (vehicles.isNotEmpty) {
          for (var v in vehicles) {
            vehicleControllers.add(TextEditingController(text: v));
          }
        } else {
          vehicleControllers.add(TextEditingController());
        }
        setState(() {
          isEmailSent = true;
          isRestoredFromPending = true;
        });
        _startEmailVerificationMonitor();
        _showMessage('Continuing your signup process...');
      }
    } catch (e) {
      print('❌ Error restoring signup data: $e');
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _signUp() async {
    if (_formKey.currentState!.validate()) {
      if (passwordController.text != confirmPasswordController.text) {
        _showMessage('Passwords do not match');
        return;
      }

      _buttonAnimationController.forward().then((_) {
        _buttonAnimationController.reverse();
      });

      setState(() { isLoadingSignUp = true; });

      try {
        List<String> vehicles = vehicleControllers
            .map((c) => c.text.trim())
            .where((v) => v.isNotEmpty)
            .toList();

        Map<String, String> userData = {
          'email': emailController.text.trim(),
          'phone': phoneController.text.trim(),
          'vehicle': vehicles.join(','),
          'password': passwordController.text,
          'confirmPassword': confirmPasswordController.text,
        };

        Map<String, String?> validationErrors = _signUpService.validateSignupData(userData);
        if (validationErrors.isNotEmpty) {
          String errorMessage = validationErrors.values.first!;
          _showMessage(errorMessage);
          setState(() { isLoadingSignUp = false; });
          return;
        }

        await _signUpService.saveSignupData(userData);
        await _signUpService.setSignupStage(SignUpService.stageEmailSent);

        Map<String, dynamic> createResult = await _signUpService.createFirebaseUser(
          userData['email']!,
          userData['password']!,
        );

        setState(() {
          isLoadingSignUp = false;
          isEmailSent = createResult['success'];
        });

        if (createResult['error_code'] == 'email-already-in-use') {
          await _handleEmailAlreadyInUse(
            userData['email']!,
            userData['password']!,
          );
          setState(() { isLoadingSignUp = false; });
          return;
        }

        if (createResult['success']) {
          _showMessage(createResult['message']);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyEmailPage(email: emailController.text),
            ),
          );
        } else {
          throw Exception(createResult['message']);
        }
      } catch (e) {
        setState(() { isLoadingSignUp = false; });
        _showMessage('Signup failed: ${e.toString()}');
        await _signUpService.clearSignupData();
      }
    }
  }

  Future<void> _handleEmailAlreadyInUse(String email, String password) async {
    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;

      if (user != null && !user.emailVerified) {
        await user.delete();
        await FirebaseAuth.instance.signOut();
        _showMessage("Unverified account removed. You can sign up again with this email.");
      } else {
        _showMessage('Email is already in use and verified. Please log in.');
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        _showMessage('Email already in use. Incorrect password. Please login or reset password.');
      } else {
        _showMessage('Cannot delete account: ${e.message}');
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    try {
      print('📧 Resending verification email...');
      Map<String, dynamic> result = await _signUpService.resendEmailVerification();
      _showMessage(result['message']);
      print('📧 Resend result: ${result['success']}');
    } catch (e) {
      print('❌ Error resending email: $e');
      _showMessage('Error resending email: ${e.toString()}');
    }
  }

  Future<void> _cancelSignUp() async {
    try {
      print('🚫 Cancelling signup...');
      await _signUpService.clearSignupData();
      _resetForm();
      _showMessage('Signup cancelled');
      print('✅ Signup cancelled successfully');
    } catch (e) {
      print('❌ Error cancelling signup: $e');
      _showMessage('Error cancelling signup: ${e.toString()}');
    }
  }

  void _resetForm() {
    setState(() {
      isEmailSent = false;
      isRestoredFromPending = false;
    });

    emailController.clear();
    passwordController.clear();
    confirmPasswordController.clear();
    phoneController.clear();

    for (final controller in vehicleControllers) {
      controller.dispose();
    }
    vehicleControllers
      ..clear()
      ..add(TextEditingController());

    for (final node in vehicleFocusNodes) {
      node.dispose();
    }
    vehicleFocusNodes
      ..clear()
      ..add(FocusNode());
  }

  Future<void> _simulateEmailVerification() async {
    try {
      print('✅ Simulating email verification completion...');
      bool completed = await _signUpService.completeSignup();
      if (completed) {
        _showMessage('Email verified! Account created successfully!');
        await Future.delayed(const Duration(seconds: 2));
        _resetForm();
      }
    } catch (e) {
      print('❌ Error simulating verification: $e');
      _showMessage('Error completing verification: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isDesktop = screenSize.width > 1024;
    final bool isTablet = screenSize.width > 600 && screenSize.width <= 1024;
    final bool isWeb = kIsWeb;
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardHeight > 0;

    return Theme(
      data: _currentTheme,
      child: Scaffold(
        resizeToAvoidBottomInset: false, // KEY CHANGE - prevents automatic resizing
        body: AnimatedBuilder(
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

                  // Main content with smooth keyboard handling
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
                            child: IntrinsicHeight(
                              child: AnimatedPadding(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                                padding: EdgeInsets.only(
                                  top: isKeyboardOpen ? 20 : 40,
                                  left: isDesktop ? 40 : 16,
                                  right: isDesktop ? 40 : 16,
                                  bottom: isKeyboardOpen ? keyboardHeight + 20 : 40,
                                ),
                                child: _buildMainContent(isDesktop, isTablet),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
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
                  .withOpacity(0.3),
              boxShadow: [
                BoxShadow(
                  color: (isDarkMode ? Colors.orange : Colors.white)
                      .withOpacity(0.2),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildMainContent(bool isDesktop, bool isTablet) {
    if (isDesktop) {
      return Row(
        children: [
          // Left side - Welcome content
          Expanded(
            flex: 1,
            child: _buildWelcomeSection(),
          ),
          const SizedBox(width: 40),
          // Right side - Form
          Expanded(
            flex: 1,
            child: Column(
              children: [
                _buildFormSection(),
                const SizedBox(height: 20),
                _buildLoginRedirect(), // Add this for desktop too
              ],
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          if (!isTablet) _buildLogo(),
          const SizedBox(height: 20),
          _buildFormSection(),
          const SizedBox(height: 20),
          _buildLoginRedirect(), // Always show login redirect
        ],
      );
    }
  }



  Widget _buildWelcomeSection() {
    return AnimatedBuilder(
      animation: _cardAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _cardAnimation.value,
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: _currentTheme.cardColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    color: _currentTheme.textTheme.bodyLarge!.color,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'SENECAGLOBAL',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                     color: Colors.green.shade300,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Create your account to get started with seamless parking .',
                  style: TextStyle(
                    fontSize: 18,
                    color: _currentTheme.textTheme.bodyMedium!.color,
                    height: 1.5,
                  ),
                ),

              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _cardAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _cardAnimation.value,
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
      },
    );
  }

  Widget _buildFormSection() {
    return AnimatedBuilder(
      animation: _cardAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _cardAnimation.value,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.15)
                    : Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDarkMode
                      ? Colors.black.withOpacity(0.3)
                      : Colors.black.withOpacity(0.1),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDarkMode
                          ? [
                        Colors.white.withOpacity(0.01),
                        Colors.white.withOpacity(0.02),
                      ]
                          : [
                        Colors.white.withOpacity(0.1),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _currentTheme.textTheme.bodyLarge!.color,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      if (!isEmailSent) ...[
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _buildAnimatedTextField(
                                controller: emailController,
                                hintText: 'Email Address',
                                icon: Icons.email_outlined,
                                focusNode: _emailFocusNode,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Email cannot be empty';
                                  }
                                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                      .hasMatch(value)) {
                                    return 'Enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              _buildAnimatedTextField(
                                controller: phoneController,
                                hintText: 'Phone Number',
                                icon: Icons.phone_outlined,
                                focusNode: _phoneFocusNode,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Phone number cannot be empty';
                                  }
                                  if (value.length < 10) {
                                    return 'Enter a valid phone number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              _buildVehicleSection(),
                              const SizedBox(height: 20),

                              _buildAnimatedTextField(
                                controller: passwordController,
                                hintText: 'Password',
                                icon: Icons.lock_outline,
                                focusNode: _passwordFocusNode,
                                obscureText: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Password cannot be empty';
                                  }
                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              _buildAnimatedTextField(
                                controller: confirmPasswordController,
                                hintText: 'Confirm Password',
                                icon: Icons.lock_outline,
                                focusNode: _confirmFocusNode,
                                obscureText: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please confirm your password';
                                  }
                                  if (value != passwordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 30),

                              _buildAnimatedSignUpButton(),
                            ],
                          ),
                        ),
                      ],


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



  Widget _buildAnimatedTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required FocusNode focusNode,
    required String? Function(String?) validator,
    bool obscureText = false,
  }) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: TextFormField(
                controller: controller,
                obscureText: obscureText,
                focusNode: focusNode,
                style: TextStyle(
                  color: _currentTheme.textTheme.bodyLarge!.color,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(
                    color: _currentTheme.textTheme.bodyMedium!.color,
                  ),
                  prefixIcon: Icon(
                    icon,
                    color: Colors.orange,
                  ),
                  filled: true,
                  fillColor: isDarkMode
                      ? Colors.grey[800]!.withOpacity(0.5)
                      : Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Colors.orange,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Colors.red,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
                validator: validator,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVehicleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vehicle Information',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _currentTheme.textTheme.bodyLarge!.color,
          ),
        ),
        const SizedBox(height: 15),

        ...List.generate(vehicleControllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Row(
              children: [
                Expanded(
                  child: _buildAnimatedTextField(
                    controller: vehicleControllers[index],
                    hintText: 'Vehicle Number ${index + 1}',
                    icon: Icons.directions_car_outlined,
                    focusNode: vehicleFocusNodes[index],
                    validator: (value) =>
                    (value == null || value.isEmpty)
                        ? 'Vehicle number cannot be empty'
                        : null,
                  ),
                ),
                if (vehicleControllers.length > 1 && index != 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          vehicleFocusNodes[index].removeListener(_onFocusChange); // ADD THIS LINE
                          vehicleControllers.removeAt(index);
                          vehicleFocusNodes.removeAt(index);
                        });
                      },
                    ),
                  ),
              ],
            ),
          );
        }),

        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                final newController = TextEditingController();
                final newFocusNode = FocusNode();
                newFocusNode.addListener(_onFocusChange); // ADD THIS LINE
                vehicleControllers.add(newController);
                vehicleFocusNodes.add(newFocusNode);
              });
            },
            icon: const Icon(Icons.add, color: Colors.orange),
            label: const Text(
              'Add Another Vehicle',
              style: TextStyle(color: Colors.orange),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.orange.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedSignUpButton() {
    return AnimatedBuilder(
      animation: _buttonAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _buttonAnimation.value,
          child: GestureDetector(
            onTap: isLoadingSignUp ? null : _signUp,
            child: Container(
              height: 55,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.orange, Colors.deepOrange],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Center(
                child: isLoadingSignUp
                    ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text(
                  'Create Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginRedirect() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Already have an account? ',
              style: TextStyle(
                fontSize: 16,
                color: _currentTheme.textTheme.bodyMedium!.color,
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LandingPage(),
                  ),
                );
              },
              child: const Text(
                'Sign In',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


}