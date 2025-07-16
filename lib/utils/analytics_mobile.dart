// analytics_mobile_helper.dart (Enhanced version)
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';


// Comprehensive mobile save function with Downloads folder fallback
Future<void> saveExcelOnMobile(
    BuildContext context,
    List<int> bytes,
    String fileName,
    {required Function(double) onProgress}
    ) async {
  try {
    onProgress(0.1);

    // First try: Save to Downloads folder (Android only)
    if (Platform.isAndroid) {
      final success = await _saveToDownloadsFolder(bytes, fileName);
      if (success) {
        onProgress(1.0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel file saved to Downloads folder!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    onProgress(0.3);

    // Fallback: Use directory picker
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory == null) {
      onProgress(0.0);
      return;
    }

    onProgress(0.7);

    final file = File('$selectedDirectory/$fileName');

    // Check if file exists and ask for confirmation
    if (await file.exists()) {
      final shouldOverwrite = await _showOverwriteDialog(context, fileName);
      if (!shouldOverwrite) {
        onProgress(0.0);
        return;
      }
    }

    onProgress(0.9);

    await file.writeAsBytes(bytes);

    onProgress(1.0);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Excel file saved successfully!'),
            Text('Location: ${file.path}',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 5),
      ),
    );

  } catch (e) {
    onProgress(0.0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error saving Excel file: ${e.toString()}'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }
}

// Helper function to save to Downloads folder
Future<bool> _saveToDownloadsFolder(List<int> bytes, String fileName) async {
  try {
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        final file = File('${downloadsDir.path}/$fileName');
        await file.writeAsBytes(bytes);
        return true;
      }
    }
    return false;
  } catch (e) {
    print('Failed to save to Downloads folder: $e');
    return false;
  }
}

// Helper function to show overwrite dialog
Future<bool> _showOverwriteDialog(BuildContext context, String fileName) async {
  return await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('File Exists'),
      content: Text('$fileName already exists. Do you want to overwrite it?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Overwrite'),
        ),
      ],
    ),
  ) ?? false;
}