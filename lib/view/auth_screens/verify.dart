import 'dart:async';
import 'package:flutter/material.dart';
import '../../viewModel/authService.dart';
import '../home.dart';

class VerifyEmailPage extends StatefulWidget {
  final String email;
  const VerifyEmailPage({Key? key, required this.email}) : super(key: key);

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final SignUpService _signUpService = SignUpService();
  bool? isVerified;
  bool isResending = false;
  StreamSubscription<bool>? emailVerificationSubscription;

  @override
  void initState() {
    super.initState();
    _startEmailVerificationMonitor();
  }

  @override
  void dispose() {
    emailVerificationSubscription?.cancel();
    super.dispose();
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
        _showMessage('Email verified! Account created successfully!');
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => HomeScreen()),
                (route) => false,
          );
        }
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    setState(() => isResending = true);
    final result = await _signUpService.resendEmailVerification();
    setState(() => isResending = false);
    _showMessage(result['message']);
  }

  Future<void> _cancelSignUp() async {
    await _signUpService.clearSignupData();
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use Stack to place gradient behind everything
      body: Stack(
        fit: StackFit.expand,
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
          // Centered card
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    spreadRadius: 3,
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.email_outlined, size: 70, color: Colors.orange),
                  SizedBox(height: 22),
                  Text(
                    'Email Verification',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'We sent a verification email to:',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    widget.email,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 24),
                  if (isVerified == null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)
                        ),
                        SizedBox(width: 10),
                        Text("Checking verification...", style: TextStyle(fontSize: 15)),
                      ],
                    ),
                  ] else if (isVerified == true) ...[
                    Icon(Icons.verified, color: Colors.green, size: 48),
                    SizedBox(height: 10),
                    Text(
                      '🎉 Your email is verified!',
                      style: TextStyle(fontSize: 17, color: Colors.green[700], fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    Icon(Icons.warning_amber, color: Colors.orange, size: 48),
                    SizedBox(height: 10),
                    Text(
                      'Email not verified yet!',
                      style: TextStyle(fontSize: 16, color: Colors.red[700], fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '(Also Check Spam Folder)',
                      style: TextStyle(fontSize: 14, color: Colors.black26, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 5),
                    AnimatedCheckingText(),
                  ],

                  SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: isResending ? null : _resendVerificationEmail,
                        icon: isResending
                            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                            : Icon(Icons.refresh, color: Colors.orange),
                        label: Text(
                          'Resend Email',
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shadowColor: Colors.orange,
                          side: BorderSide(color: Colors.orange),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _cancelSignUp,
                        child: Text('Cancel', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[400],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
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
        setState(() {
          dotCount = (dotCount + 1) % 4;
        });
        _controller.forward(from: 0.0);
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
        color: Colors.grey[800],
      ),
    );
  }
}
