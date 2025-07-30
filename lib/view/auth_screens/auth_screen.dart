import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';



import '../../viewModel/authService.dart';
import '../forgot_password.dart';
import '../home.dart';
import '../splashScreen/my_splash_screen.dart';
// 1. Add these imports at the top of your file:
import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter


class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  _LandingPageState createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  bool isExistingUser = true;
  final AuthService  _signUpService = AuthService ();
  bool isLoading = false;

  final GlobalKey<FormState> _formkey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isPasswordVisible = false;
  bool isKeyboardVisible = false;
  late AnimationController _backgroundAnimationController;
  late Animation<double> _backgroundAnimation;

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
  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;

  // Animations
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  // Focus Nodes
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

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

    // Add background animation controller
    _backgroundAnimationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

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

    // Add background animation
    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(_backgroundAnimationController);
  }




  void _setupKeyboardListener() {
    _emailFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final bool keyboardVisible = _emailFocusNode.hasFocus || _passwordFocusNode.hasFocus;
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

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _backgroundAnimationController.dispose(); // Add this line
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }



  void _handleLogin() async {
    if (!_formkey.currentState!.validate()) return;

    // Add haptic feedback
    HapticFeedback.lightImpact();

    String email = emailController.text.trim();
    String password = passwordController.text;

    setState(() => isLoading = true);

    final result = await _signUpService.signInWithEmail(email, password);

    setState(() => isLoading = false);

    if (result['success'] == true) {
      _showSuccessAnimation();
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => MysplashScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
            (route) => false,
      );
    } else if (result['emailNotVerified'] == true) {
      _showSnackBar(result['message'], Colors.orange);
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => MysplashScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            );
          },
        ),
      );
    } else {
      _showSnackBar(result['message'], Colors.red);
      // Shake animation for error
      HapticFeedback.mediumImpact();
    }
  }

  void _showSuccessAnimation() {
    HapticFeedback.heavyImpact();
    // You can add more success animations here
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }




  @override
  Widget build(BuildContext context) {
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardHeight > 0;

    return Theme(
      data: _currentTheme,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
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

                  // Main content
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
                                  top: isKeyboardOpen ? 30 : 10,
                                  left: 0,
                                  right: 0,
                                  bottom: isKeyboardOpen ? keyboardHeight : 40,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: <Widget>[
                                      // Logo with glass container
                                      _buildLogoSection(),
                                      const SizedBox(height: 70),
                                      // Welcome Texts
                                      _buildWelcomeSection(),
                                      const SizedBox(height: 28),
                                      // Login form with glass effect
                                      _buildGlassLoginContainer(),
                                      const SizedBox(height: 20),
                                    ],
                                  ),
                                ),
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


  Widget _buildWelcomeSection() {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            Text(
              "Welcome Back",
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.indigo,
                fontSize: 26,
                fontFamily: "Mont",
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              "sign in to access your account",
              style: TextStyle(
                color: _currentTheme.textTheme.bodyMedium!.color,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassLoginContainer() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 350),
      padding: const EdgeInsets.fromLTRB(30, 40, 30, 30), // More top padding
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
        borderRadius: BorderRadius.circular(25), // CHANGE: Reduced from 30 to 25
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
              children: [
                const SizedBox(height: 10), // ADD: Extra spacing at top
                _buildLoginFields(),
                const SizedBox(height: 16),
                _buildLoginButton(),

              ],
            ),
          ),
        ),
      ),
    );
  }




  Widget _buildLoginFields() {
    return Form(
      key: _formkey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTextFieldContainer(
            controller: emailController,
            focusNode: _emailFocusNode,
            hintText: 'Enter your Email',
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              } else if (!isValidEmail(value)) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildTextFieldContainer(
            controller: passwordController,
            focusNode: _passwordFocusNode,
            hintText: 'Password',
            icon: Icons.lock,
            obscureText: !isPasswordVisible,
            isPassword: true,
          ),
          const SizedBox(height: 8),
          _buildForgotPasswordLink(),
        ],
      ),
    );
  }


  Widget _buildTextFieldContainer({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Container(
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
        focusNode: focusNode,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
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
            color: focusNode.hasFocus ? Colors.orange : Colors.grey.shade600,
          ),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(
              isPasswordVisible ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey.shade600,
            ),
            onPressed: () {
              setState(() {
                isPasswordVisible = !isPasswordVisible;
              });
            },
          )
              : null,
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
      ),
    );
  }




  Widget _buildForgotPasswordLink() {
    return Row(
      children: [
        const Spacer(),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const ForgotPasswordPage(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  );
                },
              ),
            );
          },
          child: AnimatedDefaultTextStyle(
            style: TextStyle(
              color: Colors.blue.shade700,
              decoration: TextDecoration.underline,
              fontSize: 14,
            ),
            duration: const Duration(milliseconds: 200),
            child: const Text("Forgot password?"),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return GestureDetector(
      onTap: isLoading ? null : _handleLogin,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 160,
        height: 50,
        decoration: BoxDecoration(
          gradient: !isLoading
              ? LinearGradient(
            colors: [Colors.orange.shade400, Colors.orange.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: isLoading ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: (!isLoading ? Colors.orange : Colors.grey).withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 2,
            ),
          )
              : const Text(
            "LOGIN",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontFamily: "Mont",
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }





}