// analytics_mobile_helper.dart (Fixed directory memory logic)
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class MobileExportHelper {
  static const String _savedDirectoryKey = 'excel_export_directory';

  // Fixed mobile save function with proper directory memory
  static Future<void> saveExcelOnMobile(
      BuildContext context,
      List<int> bytes,
      String fileName,
      {required Function(double) onProgress}
      ) async {
    try {
      onProgress(0.1);

      // First try: Use remembered directory if it exists
      String? rememberedDirectory = await _getRememberedDirectory();
      if (rememberedDirectory != null && await Directory(rememberedDirectory).exists()) {
        onProgress(0.5);
        final success = await _saveToDirectory(rememberedDirectory, bytes, fileName, context);
        if (success) {
          onProgress(1.0);
          final filePath = '$rememberedDirectory/$fileName';
          _showSuccessMessage(context, 'Excel file saved successfully!', filePath);
          return;
        }
      }

      onProgress(0.3);

      // Second try: Save to Downloads folder (Android only) if no remembered directory
      if (Platform.isAndroid && rememberedDirectory == null) {
        final success = await _saveToDownloadsFolder(bytes, fileName);
        if (success) {
          onProgress(1.0);
          _showSuccessMessage(context, 'Excel file saved to Downloads folder!', null);
          return;
        }
      }

      onProgress(0.5);

      // Fallback: Ask user to choose directory and remember it (first time or if previous failed)
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        onProgress(0.0);
        _showErrorMessage(context, 'Export cancelled by user');
        return;
      }

      // Remember this directory for next time
      await _saveDirectoryChoice(selectedDirectory);

      onProgress(0.8);

      final success = await _saveToDirectory(selectedDirectory, bytes, fileName, context);
      if (success) {
        onProgress(1.0);
        final filePath = '$selectedDirectory/$fileName';
        _showSuccessMessage(context, 'Excel file saved successfully!', filePath);

        // Show info about remembering the directory only on first selection
        if (rememberedDirectory == null) {
          Future.delayed(Duration(seconds: 2), () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('📁 This location will be remembered for future exports'),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 3),
              ),
            );
          });
        }
      } else {
        onProgress(0.0);
        _showErrorMessage(context, 'Failed to save file to selected directory');
      }

    } catch (e) {
      onProgress(0.0);
      _showErrorMessage(context, 'Error saving Excel file: ${e.toString()}');
    }
  }

  // Save file to a specific directory with overwrite handling
  static Future<bool> _saveToDirectory(String directory, List<int> bytes, String fileName, BuildContext context) async {
    try {
      final file = File('$directory/$fileName');

      // Check if file exists and ask for confirmation
      if (await file.exists()) {
        final shouldOverwrite = await _showOverwriteDialog(context, fileName);
        if (!shouldOverwrite) {
          return false;
        }
      }

      await file.writeAsBytes(bytes);
      return true;
    } catch (e) {
      print('Failed to save to directory: $e');
      return false;
    }
  }

  // Enhanced Downloads folder save with better Android version handling
  static Future<bool> _saveToDownloadsFolder(List<int> bytes, String fileName) async {
    try {
      if (Platform.isAndroid) {
        // For Android 10+ (API 29+), try the standard Downloads path
        final standardDownloads = Directory('/storage/emulated/0/Download');
        if (await standardDownloads.exists()) {
          final file = File('${standardDownloads.path}/$fileName');
          await file.writeAsBytes(bytes);
          return true;
        }

        // Fallback for older Android versions
        final legacyDownloads = Directory('/sdcard/Download');
        if (await legacyDownloads.exists()) {
          final file = File('${legacyDownloads.path}/$fileName');
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

  // Save directory choice to SharedPreferences
  static Future<void> _saveDirectoryChoice(String directory) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savedDirectoryKey, directory);
      print('Directory saved: $directory'); // For debugging
    } catch (e) {
      print('Failed to save directory choice: $e');
    }
  }

  // Get remembered directory from SharedPreferences
  static Future<String?> _getRememberedDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final directory = prefs.getString(_savedDirectoryKey);
      print('Retrieved directory: $directory'); // For debugging
      return directory;
    } catch (e) {
      print('Failed to get remembered directory: $e');
      return null;
    }
  }

  // Clear remembered directory (useful for settings/reset)
  static Future<void> clearRememberedDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_savedDirectoryKey);
      print('Directory preference cleared');
    } catch (e) {
      print('Failed to clear directory preference: $e');
    }
  }

  // Helper function to show overwrite dialog
  static Future<bool> _showOverwriteDialog(BuildContext context, String fileName) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('File Exists'),
          ],
        ),
        content: Text('$fileName already exists in this location. Do you want to overwrite it?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('Overwrite'),
          ),
        ],
      ),
    ) ?? false;
  }

  // Helper function to show success message
  static void _showSuccessMessage(BuildContext context, String message, String? filePath) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: TextStyle(fontWeight: FontWeight.bold)),
                  if (filePath != null)
                    Text('📁 $filePath',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 5),
        action: filePath != null
            ? SnackBarAction(
          label: 'Open Folder',
          textColor: Colors.white,
          onPressed: () {
            // You can implement opening file manager here if needed
            // This would require additional plugins like open_file
          },
        )
            : null,
      ),
    );
  }

  // Helper function to show error message
  static void _showErrorMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ),
    );
  }

  // Method to show current saved directory in settings
  static Future<String?> getCurrentSavedDirectory() async {
    return await _getRememberedDirectory();
  }

  // Method to change the saved directory (for settings screen)
  static Future<void> changeSavedDirectory(BuildContext context) async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        await _saveDirectoryChoice(selectedDirectory);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.folder, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Export location updated!'),
                      Text(selectedDirectory,
                          style: TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      _showErrorMessage(context, 'Failed to update export location: ${e.toString()}');
    }
  }

  // Check if a directory is already remembered
  static Future<bool> hasRememberedDirectory() async {
    final directory = await _getRememberedDirectory();
    return directory != null && await Directory(directory).exists();
  }

  // Get a user-friendly display of the current export location
  static Future<String> getExportLocationDisplay() async {
    final directory = await _getRememberedDirectory();
    if (directory != null && await Directory(directory).exists()) {
      // Show only the last 2 parts of the path for better readability
      final parts = directory.split('/');
      if (parts.length > 2) {
        return '.../${parts[parts.length - 2]}/${parts[parts.length - 1]}';
      }
      return directory;
    }
    return 'Downloads folder (default)';
  }
}


// Usage example:
// await MobileExportHelper.saveExcelOnMobile(
//   context,
//   bytes,
//   fileName,
//   onProgress: (progress) => setState(() => _progress = progress)
// );

// In your settings screen:
// String currentLocation = await MobileExportHelper.getExportLocationDisplay();
// bool hasCustomLocation = await MobileExportHelper.hasRememberedDirectory();