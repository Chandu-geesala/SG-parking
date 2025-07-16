import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:park_sg/view/auth_screens/verify.dart';

import '../../viewModel/authService.dart';
import 'auth_screen.dart';
// Import your SignUpService here
// import 'package:your_app/services/signup_service.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  final List<TextEditingController> vehicleControllers = [TextEditingController()];

  final ScrollController _scrollController = ScrollController();

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmFocusNode = FocusNode();

  final List<FocusNode> vehicleFocusNodes = [FocusNode()];







  bool isLoadingSignUp = false;

  bool? isVerified;
  StreamSubscription<bool>? emailVerificationSubscription;



  bool isEmailSent = false;
  bool isRestoredFromPending = false;

  final SignUpService _signUpService = SignUpService();

  @override
  void initState() {
    super.initState();
    _initializeSignupState();
  }

  @override
  void dispose() {

    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    phoneController.dispose();
    for (final controller in vehicleControllers) {
      controller.dispose();
    }
    emailVerificationSubscription?.cancel();
    _scrollController.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();

    for (final node in vehicleFocusNodes) {
      node.dispose();
    }


    super.dispose();
  }


  void _scrollToFocusedInput(FocusNode node) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        Scrollable.ensureVisible(
          node.context!,
          duration: const Duration(milliseconds: 400),
          alignment: 0.2, // Adjust as needed: 0.0 = top, 1.0 = bottom
          curve: Curves.easeInOut,
        );
      }
    });
  }






  /// Initialize signup state - check for pending signup
  Future<void> _initializeSignupState() async {
    try {
      print('🔄 Initializing signup state...');

      // Check if user has pending signup
      bool hasPending = await _signUpService.hasPendingSignup();

      if (hasPending) {
        print('⏳ Found pending signup, restoring data...');
        await _restoreSignupData();
      } else {
        print('✅ No pending signup found, starting fresh');
      }

      // Debug current state
      await _signUpService.debugPrintState();
    } catch (e) {
      print('❌ Error initializing signup state: $e');
    }
  }

  void _startEmailVerificationMonitor() {
    // Avoid multiple subscriptions
    emailVerificationSubscription?.cancel();
    emailVerificationSubscription = _signUpService.monitorEmailVerification().listen((verified) async {
      setState(() {
        isVerified = verified;
      });
      if (verified) {
        // Optionally, handle what happens after verification
        await Future.delayed(const Duration(seconds: 1));
        await _signUpService.handleEmailVerificationComplete();
        // _showMessage("Email verified! Account created successfully!"); // Optionally show a message
        // _resetForm(); // Optionally reset form or navigate
      }
    });
  }






  /// Restore signup data from shared preferences
  Future<void> _restoreSignupData() async {
    try {
      Map<String, String> pendingData = await _signUpService.getPendingSignupData();

      if (pendingData.isNotEmpty) {
        emailController.text = pendingData['email'] ?? '';
        phoneController.text = pendingData['phone'] ?? '';
        passwordController.text = pendingData['password'] ?? '';
        confirmPasswordController.text = pendingData['confirmPassword'] ?? '';

        // Restore vehicles as CSV (adjust if you store as List/JSON)
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
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Handle signup process
  Future<void> _signUp() async {
    if (_formKey.currentState!.validate()) {
      if (passwordController.text != confirmPasswordController.text) {
        _showMessage('Passwords do not match');
        return;
      }

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

        // Save to shared prefs if you want (optional)
        await _signUpService.saveSignupData(userData);
        await _signUpService.setSignupStage(SignUpService.stageEmailSent);

        // Create user and send verification
        Map<String, dynamic> createResult = await _signUpService.createFirebaseUser(
          userData['email']!,
          userData['password']!,
        );

        setState(() {
          isLoadingSignUp = false;
          isEmailSent = createResult['success'];
        });

        if (createResult['error_code'] == 'email-already-in-use') {
          // Option 1: Try to delete if not verified
          await _handleEmailAlreadyInUse(
            userData['email']!,
            userData['password']!,
          );
          setState(() { isLoadingSignUp = false; });
          return;
        }



        if (createResult['success']) {
          _showMessage(createResult['message']);
          // Navigate to the verification screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => VerifyEmailPage(email: emailController.text),
            ),
          );
        }
        else {
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
      // Try sign in with the credentials
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;

      if (user != null && !user.emailVerified) {
        // Delete the unverified user
        await user.delete();
        // Optionally, sign out after deletion
        await FirebaseAuth.instance.signOut();

        // Try to sign up again (call _signUp again or proceed in your logic)
        _showMessage("Unverified account removed. You can sign up again with this email.");
        // You can now safely call your signup code again here,
        // but you might want to auto-fill the form or just allow user to submit again
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


  /// Handle verification email resend
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





  /// Handle signup cancellation
  Future<void> _cancelSignUp() async {
    try {
      print('🚫 Cancelling signup...');

      // Clear all stored data
      await _signUpService.clearSignupData();

      // Reset form
      _resetForm();

      _showMessage('Signup cancelled');
      print('✅ Signup cancelled successfully');
    } catch (e) {
      print('❌ Error cancelling signup: $e');
      _showMessage('Error cancelling signup: ${e.toString()}');
    }
  }

  /// Reset form to initial state
  void _resetForm() {
    setState(() {
      isEmailSent = false;
      isRestoredFromPending = false;
    });

    // Clear main form fields
    emailController.clear();
    passwordController.clear();
    confirmPasswordController.clear();
    phoneController.clear();

    // Dispose and clear vehicle text controllers
    for (final controller in vehicleControllers) {
      controller.dispose();
    }
    vehicleControllers
      ..clear()
      ..add(TextEditingController());

    // Dispose and clear associated FocusNodes
    for (final node in vehicleFocusNodes) {
      node.dispose();
    }
    vehicleFocusNodes
      ..clear()
      ..add(FocusNode());
  }





  /// Simulate email verification completion (for testing)
  Future<void> _simulateEmailVerification() async {
    try {
      print('✅ Simulating email verification completion...');

      // Complete the signup process
      bool completed = await _signUpService.completeSignup();

      if (completed) {
        _showMessage('Email verified! Account created successfully!');



        // For demo purposes, just reset the form
        await Future.delayed(Duration(seconds: 2));
        _resetForm();
      }
    } catch (e) {
      print('❌ Error simulating verification: $e');
      _showMessage('Error completing verification: ${e.toString()}');
    }
  }



  @override
  Widget build(BuildContext context) {
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardHeight > 0;
    final Size screenSize = MediaQuery.of(context).size;

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

          // Foreground content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: isKeyboardOpen ? 30 : 0,
                    bottom: isKeyboardOpen ? keyboardHeight : 40,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo
                        Image.asset(
                          'assets/txt.png',
                          width: 240,
                          height: 120,
                        ),
                        const SizedBox(height: 10),

                        if (!isEmailSent) ...[
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                _buildTextFieldContainer(
                                  controller: emailController,
                                  hintText: 'Email',
                                  icon: Icons.email,
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
                                  focusNode: _emailFocusNode,
                                ),
                                const SizedBox(height: 20),
                                _buildTextFieldContainer(
                                  controller: phoneController,
                                  hintText: 'Phone',
                                  icon: Icons.phone,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Phone number cannot be empty';
                                    }
                                    if (value.length < 10) {
                                      return 'Enter a valid phone number';
                                    }
                                    return null;
                                  },
                                  focusNode: _phoneFocusNode,
                                ),
                                const SizedBox(height: 20),
                                _buildVehicleList(),
                                const SizedBox(height: 20),
                                _buildTextFieldContainer(
                                  controller: passwordController,
                                  hintText: 'Password',
                                  icon: Icons.lock,
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
                                  focusNode: _passwordFocusNode,
                                ),
                                const SizedBox(height: 20),
                                _buildTextFieldContainer(
                                  controller: confirmPasswordController,
                                  hintText: 'Confirm Password',
                                  icon: Icons.lock,
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
                                  focusNode: _confirmFocusNode,
                                ),
                                const SizedBox(height: 30),
                                GestureDetector(
                                  onTap: isLoadingSignUp ? null : _signUp,
                                  child: _buildSignUpButton(
                                    isLoadingSignUp ? "Processing..." : "Verify & Sign Up",
                                    isEnabled: !isLoadingSignUp,
                                  ),
                                ),
                              ],
                            ),
                          )
                        ],

                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const Text(
                              'Already a registered user?',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 10),
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
                                'Log In here',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                      ],
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






  Widget _buildVehicleList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: vehicleControllers.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Center(
                child: Container(
                  // Use the same width logic as your text fields
                  width: MediaQuery.of(context).size.width > 600
                      ? 400 // Fixed width for web/desktop
                      : MediaQuery.of(context).size.width - 100, // Responsive for mobile
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTextFieldContainer(
                          controller: vehicleControllers[index],
                          hintText: 'Vehicle Number',
                          icon: Icons.directions_car,
                          focusNode: vehicleFocusNodes[index],
                          validator: (value) =>
                          (value == null || value.isEmpty)
                              ? 'Vehicle number cannot be empty'
                              : null,
                        ),
                      ),
                      if (vehicleControllers.length > 1 && index != 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                vehicleControllers.removeAt(index);
                                vehicleFocusNodes.removeAt(index);
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: MediaQuery.of(context).size.width > 600 ? 220 : MediaQuery.of(context).size.width - 170,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, color: Colors.green),
              label: const Text("Add Vehicle"),
              onPressed: () {
                setState(() {
                  vehicleControllers.add(TextEditingController());
                  vehicleFocusNodes.add(FocusNode());
                });
              },
            ),
          ),
        ),
      ],
    );
  }





  Widget _buildSignUpButton(String buttonText, {required bool isEnabled}) {
    return Container(
      width: 160,
      height: 50,
      decoration: BoxDecoration(
        color: isEnabled ? Colors.orange : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: isLoadingSignUp
            ? const CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        )
            : Text(
          buttonText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontFamily: "Noto",
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

// Replace your existing _buildTextFieldContainer method with this improved version:

  Widget _buildTextFieldContainer({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required String? Function(String?) validator,
    required FocusNode focusNode,
    bool obscureText = false,
  }) {
    return Center(
      child: Container(
        // Set maximum width for web and responsive width for mobile
        width: MediaQuery.of(context).size.width > 600
            ? 400 // Fixed width for web/desktop
            : MediaQuery.of(context).size.width - 100, // Responsive for mobile
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: Colors.black,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.5),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: TextFormField(
          controller: controller,
          obscureText: obscureText,
          cursorColor: const Color.fromRGBO(251, 126, 24, 1.0),
          style: const TextStyle(color: Colors.black),
          focusNode: focusNode,
          onTap: () => _scrollToFocusedInput(focusNode),
          // 👈 key change
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: hintText,
            icon: Icon(icon),
          ),
          validator: validator,
        )

      ),
    );
  }



}