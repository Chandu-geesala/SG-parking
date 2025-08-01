import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';


// Custom painter for drawing background shapes
class BackgroundPainter extends CustomPainter {
  final Animation<double> animation;

  const BackgroundPainter(this.animation);

  Offset getOffset(Path path) {
    final pms = path.computeMetrics(forceClosed: false).elementAt(0);
    final length = pms.length;
    final offset = pms.getTangentForOffset(length * animation.value)!.position;
    return offset;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.maskFilter = const MaskFilter.blur(
      BlurStyle.normal,
      30,
    );
    drawShape1(canvas, size, paint, Colors.orange);
    drawShape2(canvas, size, paint, Colors.greenAccent);
    drawShape3(canvas, size, paint, Colors.blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate != this;
  }

  void drawShape1(Canvas canvas, Size size, Paint paint, Color color) {
    paint.color = color;
    Path path = Path();

    path.moveTo(size.width, 0);
    path.quadraticBezierTo(
      size.width / 2,
      size.height / 2,
      -100,
      size.height / 4,
    );

    final offset = getOffset(path);
    canvas.drawCircle(offset, 150, paint);
  }

  void drawShape2(Canvas canvas, Size size, Paint paint, Color color) {
    paint.color = color;
    Path path = Path();

    path.moveTo(size.width, size.height);
    path.quadraticBezierTo(
      size.width / 2,
      size.height / 2,
      size.width * 0.9,
      size.height * 0.9,
    );

    final offset = getOffset(path);
    canvas.drawCircle(offset, 250, paint);
  }

  void drawShape3(Canvas canvas, Size size, Paint paint, Color color) {
    paint.color = color;
    Path path = Path();

    path.moveTo(0, 0);
    path.quadraticBezierTo(
      0,
      size.height,
      size.width / 3,
      size.height / 3,
    );

    final offset = getOffset(path);
    canvas.drawCircle(offset, 250, paint);
  }
}