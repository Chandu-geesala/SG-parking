import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:park_sg/view/auth_screens/signUp.dart';
import 'package:park_sg/view/auth_screens/verify.dart';

import '../../viewModel/authService.dart';
import '../forgot_password.dart';
import '../home.dart';
import '../splashScreen/my_splash_screen.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  _LandingPageState createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  bool isExistingUser = true;
  final SignUpService _signUpService = SignUpService();
  bool isLoading = false;

  final GlobalKey<FormState> _formkey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isPasswordVisible = false;
  bool isKeyboardVisible = false;

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

    return Scaffold(
      backgroundColor: Colors.orange.shade400,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.shade400,
                  Colors.white,
                  Colors.green.shade400,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
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
                        // Smoothly reduce top padding and add bottom padding as the keyboard opens
                        padding: EdgeInsets.only(
                          top: isKeyboardOpen ? 30 : 80,
                          left: 0,
                          right: 0,
                          bottom: isKeyboardOpen ? keyboardHeight : 40,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              // Logo (always visible, no more shrinking)
                              FadeTransition(
                                opacity: _fadeAnimation,
                                child: SizedBox(
                                  width: 220,
                                  height: 100,
                                  child: Image.asset(
                                    'assets/txt.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Welcome Texts (always visible)
                              SlideTransition(
                                position: _slideAnimation,
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: Column(
                                    children: [
                                      const Text(
                                        "Welcome Back",
                                        style: TextStyle(
                                          color: Colors.indigo,
                                          fontSize: 26,
                                          fontFamily: "Noto",
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      const Text(
                                        "sign in to access your account",
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              // Login form fields
                              _buildLoginFields(),
                              const SizedBox(height: 16),
                              // Login button
                              _buildLoginButton(),
                              const SizedBox(height: 16),
                              // Sign up section
                              _buildSignUpSection(),
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
  }








  Widget _buildLoginFields() {
    return Container(
      key: const ValueKey("login"),
      width: 300,
      padding: const EdgeInsets.all(10),
      child: Form(
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
            const SizedBox(height: 15),
            _buildTextFieldContainer(
              controller: passwordController,
              focusNode: _passwordFocusNode,
              hintText: 'Password',
              icon: Icons.lock,
              obscureText: !isPasswordVisible,
              isPassword: true,
            ),
            const SizedBox(height: 10),
            _buildForgotPasswordLink(),
          ],
        ),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 290,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: focusNode.hasFocus
                ? Colors.orange.withOpacity(0.3)
                : Colors.black.withOpacity(0.1),
            blurRadius: focusNode.hasFocus ? 10 : 5,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: focusNode.hasFocus
              ? Colors.orange.withOpacity(0.5)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(
          fontFamily: "Noto",
          fontSize: 16,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(
            fontWeight: FontWeight.w300,
            fontFamily: "Noto",
            color: Colors.grey,
          ),
          prefixIcon: Icon(
            icon,
            color: focusNode.hasFocus ? Colors.orange : Colors.grey,
          ),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(
              isPasswordVisible ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey,
            ),
            onPressed: () {
              setState(() {
                isPasswordVisible = !isPasswordVisible;
              });
            },
          )
              : null,
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
              fontFamily: "Noto",
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
              fontFamily: "Noto",
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignUpSection() {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    return AnimatedOpacity(
      opacity: isKeyboardOpen ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: isKeyboardOpen ? 0 : null,
        child: isKeyboardOpen ? const SizedBox.shrink() : Column(
          children: [
            const Text(
              "Or",
              style: TextStyle(color: Colors.black54, fontSize: 16),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const SignUpPage(),
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
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'New Member? ',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 16,
                      fontFamily: 'Sathoshi',
                    ),
                  ),
                  Text(
                    'Register Now',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 18,
                      fontFamily: "Noto",
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}