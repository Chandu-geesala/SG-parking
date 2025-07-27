import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:park_sg/viewModel/slotBackend.dart';
// Add these imports at the top of your file
import 'dart:typed_data';
import 'package:flutter/foundation.dart';


import 'package:flutter/services.dart';

import '../../utils/Add_Slot_bottomSheet.dart';
import '../../utils/dimensions_card.dart';

class DataUploadUI extends StatefulWidget {
  const DataUploadUI({Key? key}) : super(key: key);

  @override
  State<DataUploadUI> createState() => _DataUploadUIState();
}

class _DataUploadUIState extends State<DataUploadUI> {
  bool isProcessing = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _showEmptySlots = false;
  bool _showAllottedSlots = false;




// Replace your existing _pickAndProcessFile method with this updated version:
  void _pickAndProcessFile({bool clearExisting = false}) async {
    setState(() {
      isProcessing = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
      );

      if (result == null) {
        _showSnackBar("No file selected", Colors.orange);
        setState(() {
          isProcessing = false;
        });
        return;
      }

      final file = result.files.single;
      String log;

      // Check platform and use appropriate method
      if (kIsWeb) {
        // WEB: Use bytes
        if (file.bytes == null) {
          _showSnackBar("File bytes not available", Colors.red);
          setState(() {
            isProcessing = false;
          });
          return;
        }

        log = await processExcelOrCsvFile(
          fileBytes: file.bytes,
          fileName: file.name,
          clearExisting: clearExisting,
        );
      } else {
        // MOBILE/DESKTOP: Use path
        if (file.path == null) {
          _showSnackBar("File path not available", Colors.red);
          setState(() {
            isProcessing = false;
          });
          return;
        }

        log = await processExcelOrCsvFile(
          filePath: file.path,
          clearExisting: clearExisting,
        );
      }

      // Parse the log to show appropriate message with improved parsing
      if (log.contains("Upload Complete")) {
        try {
          final lines = log.split('\n');

          // Look for the "Successfully uploaded:" line with flexible matching
          String? uploadedLine = lines.firstWhere(
                (line) => line.toLowerCase().contains('uploaded:') ||
                line.toLowerCase().contains('successfully uploaded'),
            orElse: () => '',
          );

          if (uploadedLine.isEmpty) {
            // Fallback: look for any line with numbers
            uploadedLine = lines.firstWhere(
                  (line) => RegExp(r'uploaded:\s*\d+').hasMatch(line.toLowerCase()),
              orElse: () => 'Uploaded: 0',
            );
          }

          // Extract number using regex
          final numberMatch = RegExp(r'\d+').firstMatch(uploadedLine);
          final uploadedCount = numberMatch?.group(0) ?? '0';

          String action = clearExisting ? "replaced" : "uploaded";
          _showSnackBar("Successfully $action $uploadedCount slots", Colors.green);

          // Also show summary if there are issues
          if (log.contains('Skipped:')) {
            final skippedLine = lines.firstWhere(
                  (line) => line.toLowerCase().contains('skipped:'),
              orElse: () => '',
            );
            if (skippedLine.isNotEmpty) {
              final skippedMatch = RegExp(r'\d+').firstMatch(skippedLine);
              final skippedCount = skippedMatch?.group(0) ?? '0';
              if (int.tryParse(skippedCount) != null && int.parse(skippedCount) > 0) {
                // Show additional info about skipped rows
                Future.delayed(Duration(seconds: 2), () {
                  _showSnackBar("Note: $skippedCount rows were skipped due to errors", Colors.orange);
                });
              }
            }
          }
        } catch (e) {
          // Fallback parsing if the above fails
          _showSnackBar("Upload completed successfully!", Colors.green);
        }
      } else if (log.contains("Error during import")) {
        // Extract error message more carefully
        final lines = log.split('\n');
        final errorLine = lines.isNotEmpty ? lines.first : "Unknown error occurred";
        _showSnackBar("Upload failed: $errorLine", Colors.red);
      } else {
        // General error case
        final firstLine = log.split('\n').first;
        _showSnackBar("Upload issue: $firstLine", Colors.orange);
      }
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}", Colors.red);
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }




  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }


  Widget _buildUploadSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWide = constraints.maxWidth > 600;
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.all(isWide ? 32.0 : 24.0),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  size: isWide ? 64 : 48,
                  color: isDarkMode
                      ? Theme.of(context).colorScheme.primary
                      : Colors.blue[600],
                ),
                SizedBox(height: isWide ? 20 : 16),
                Text(
                  'Upload Slots Data',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.grey[800],
                    fontSize: isWide ? 24 : 20,
                  ),
                ),
                SizedBox(height: isWide ? 12 : 8),
                Text(
                  'Select an Excel (.xlsx) or CSV file to upload parking slots data',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDarkMode
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Colors.grey[600],
                    fontSize: isWide ? 16 : 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isWide ? 32 : 24),

                // Responsive button layout
                isWide
                    ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [

                    SizedBox(
                      width: 180,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: isProcessing ? null : () => _showReplaceConfirmation(),
                        icon: const Icon(Icons.refresh, size: 20),
                        label: const Text(
                          'Replace All',
                          style: TextStyle(fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDarkMode
                              ? const Color(0xFFFF8C00) // Bright orange for dark mode
                              : Colors.orange[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                )
                    : Row(
                  children: [
                    // Upload Button (Merge with existing)

                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: isProcessing ? null : () => _showReplaceConfirmation(),
                          icon: const Icon(Icons.refresh, size: 20),
                          label: const Text(
                            'Replace All',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDarkMode
                                ? const Color(0xFFFF8C00) // Bright orange for dark mode
                                : Colors.orange[600],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: isWide ? 16 : 12),


              ],
            ),
          ),
        );
      },
    );
  }



  void _showReplaceConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange[600]),
              const SizedBox(width: 8),
              const Text('Replace All Slots?'),
            ],
          ),
          content: const Text(
            'This will permanently delete all existing slots and replace them with data from the new file. This action cannot be undone.\n\nAre you sure you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _pickAndProcessFile(clearExisting: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Replace All'),
            ),
          ],
        );
      },
    );
  }




  Widget _buildSlotsDataSection() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWide = constraints.maxWidth > 600;
        bool isVeryWide = constraints.maxWidth > 900;

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.all(isWide ? 32.0 : 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_parking,
                      color: Colors.blue[600],
                      size: isWide ? 32 : 28,
                    ),
                    SizedBox(width: isWide ? 16 : 12),
                    Text(
                      'Parking Slots Data',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.grey[800],
                        fontSize: isWide ? 24 : 20,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isWide ? 20 : 16),

                // StreamBuilder for slot data
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('Slots').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: isWide ? 64 : 48,
                                color: Colors.red[400],
                              ),
                              SizedBox(height: isWide ? 20 : 16),
                              Text(
                                'Error loading data',
                                style: TextStyle(
                                  color: Colors.red[600],
                                  fontSize: isWide ? 18 : 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final slots = snapshot.data?.docs ?? [];

                    if (slots.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: isWide ? 64 : 48,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: isWide ? 20 : 16),
                              Text(
                                'No slots data available',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: isWide ? 18 : 16,
                                ),
                              ),
                              SizedBox(height: isWide ? 12 : 8),
                              Text(
                                'Upload a file to see slots data here',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: isWide ? 16 : 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // Categorize slots
                    final emptySlots = <QueryDocumentSnapshot>[];
                    final allottedSlots = <QueryDocumentSnapshot>[];

                    for (final slot in slots) {
                      final data = slot.data() as Map<String, dynamic>;
                      final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];

                      if (allotedTo.isEmpty) {
                        emptySlots.add(slot);
                      } else {
                        allottedSlots.add(slot);
                      }
                    }

                    return Column(
                      children: [
                        // Empty Slots Section
                        _buildSlotCategoryCard(
                          title: 'Empty Slots',
                          count: emptySlots.length,
                          color: Colors.green,
                          icon: Icons.circle_outlined,
                          isExpanded: _showEmptySlots,
                          onToggle: () {
                            setState(() {
                              _showEmptySlots = !_showEmptySlots;
                            });
                          },
                          slots: emptySlots,
                          isWide: isWide,
                          isVeryWide: isVeryWide,
                          constraints: constraints,
                        ),

                        SizedBox(height: isWide ? 16 : 12),

                        // Allotted Slots Section
                        _buildSlotCategoryCard(
                          title: 'Allotted Slots',
                          count: allottedSlots.length,
                          color: Colors.orange,
                          icon: Icons.person,
                          isExpanded: _showAllottedSlots,
                          onToggle: () {
                            setState(() {
                              _showAllottedSlots = !_showAllottedSlots;
                            });
                          },
                          slots: allottedSlots,
                          isWide: isWide,
                          isVeryWide: isVeryWide,
                          constraints: constraints,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSlotCategoryCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<QueryDocumentSnapshot> slots,
    required bool isWide,
    required bool isVeryWide,
    required BoxConstraints constraints,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode
            ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3)
            : color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Category Header
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.all(isWide ? 20 : 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        color: color,
                        size: isWide ? 24 : 20,
                      ),
                    ),
                    SizedBox(width: isWide ? 16 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isWide ? 18 : 16,
                              color: isDarkMode
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count slot${count != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: color,
                              fontSize: isWide ? 14 : 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        count.toString(),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: isWide ? 16 : 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: color,
                        size: isWide ? 24 : 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expandable Content
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: isExpanded ? (slots.isEmpty ? 100 : (isWide ? 400 : 300)) : 0,
            child: isExpanded
                ? Container(
              margin: EdgeInsets.fromLTRB(
                isWide ? 20 : 16,
                0,
                isWide ? 20 : 16,
                isWide ? 20 : 16,
              ),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Theme.of(context).colorScheme.surface
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                ),
              ),
              child: slots.isEmpty
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No ${title.toLowerCase()}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              )
                  : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildSlotsList(slots, isWide, isVeryWide, constraints),
              ),
            )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSlotsList(List<QueryDocumentSnapshot> slots, bool isWide, bool isVeryWide, BoxConstraints constraints) {
    // For wide screens, use grid layout
    if (isVeryWide) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: constraints.maxWidth > 1200 ? 3 : 2,
          childAspectRatio: 3.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: slots.length,
        itemBuilder: (context, index) => _buildSlotItem(slots[index], isWide),
      );
    }

    // For mobile and tablet, use list layout
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: slots.length,
      itemBuilder: (context, index) => Container(
        margin: EdgeInsets.only(bottom: isWide ? 12 : 8),
        child: _buildSlotItem(slots[index], isWide),
      ),
    );
  }

  Widget _buildSlotItem(QueryDocumentSnapshot slot, bool isWide) {
    final data = slot.data() as Map<String, dynamic>;
    final slotId = data['slotId'] ?? slot.id;
    final vehicleType = data['vehicleType'] ?? '';
    final slotPriority = data['slotPriority'] ?? '';
    final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];
    final vehicleCompatibility = data['VehicleCompatibility'] ?? '';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.all(isWide ? 16 : 12),
        leading: CircleAvatar(
          backgroundColor: _getVehicleTypeColor(vehicleType),
          radius: isWide ? 20 : 16,
          child: Icon(
            _getVehicleTypeIcon(vehicleType),
            color: Colors.white,
            size: isWide ? 20 : 16,
          ),
        ),
        title: Text(
          'Slot: $slotId',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isWide ? 16 : 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: isWide ? 6 : 4),
            Wrap(
              spacing: isWide ? 6 : 4,
              runSpacing: isWide ? 4 : 2,
              children: [
                _buildChip(vehicleType, Colors.blue),
                _buildChip(slotPriority, Colors.orange),
                if (vehicleType == 'CAR' && vehicleCompatibility.isNotEmpty)
                  _buildChip(vehicleCompatibility, Colors.purple),
              ],
            ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: isWide ? 16 : 14,
        ),
        onTap: () => _showSlotDetailsBottomSheet(context, slotId, data, allotedTo),
      ),
    );
  }







  void _showSlotDetailsBottomSheet(BuildContext context, String slotId, Map<String, dynamic> data, List<dynamic> allotedTo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SlotDetailsBottomSheet(
        slotId: slotId,
        data: data,
        allotedTo: allotedTo,
        getAvailableUsers: _getAvailableUsers,
        onSlotUpdated: () {
          // Refresh the slots list when slot is updated
          setState(() {});
        },
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Unknown';

    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getVehicleTypeColor(String vehicleType) {
    switch (vehicleType.toUpperCase()) {
      case 'CAR':
        return Colors.blue;
      case 'BIKE':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getVehicleTypeIcon(String vehicleType) {
    switch (vehicleType.toUpperCase()) {
      case 'CAR':
        return Icons.directions_car;
      case 'BIKE':
        return Icons.two_wheeler;
      default:
        return Icons.local_parking;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Slots Data Management'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
      ),



      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1200, // Maximum width for web
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.of(context).size.width > 600 ? 24.0 : 16.0,
            ),
            child: Column(
              children: [
                _buildUploadSection(),
                const SizedBox(height: 16),
              _buildDimensionsSection(),

                const SizedBox(height: 16),

                _buildSlotsDataSection(),
              ],
            ),
          ),
        ),
      ),


      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSlotBottomSheet,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),


    );
  }


  Widget _buildDimensionsSection() {
    return const CarSlotDimensionsWidget();
  }

  void _showAddSlotBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddSlotBottomSheet(
        getAvailableUsers: _getAvailableUsers,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getAvailableUsers() async {
    try {
      // Get all users
      final usersSnapshot = await _firestore.collection('users').get();
      final allUsers = usersSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'email': data['email'] ?? '',
          'name': data['name'] ?? '',
          'id': doc.id,
        };
      }).toList();

      // Get all allocated emails from slots
      final slotsSnapshot = await _firestore.collection('Slots').get();
      final allocatedEmails = <String>{};

      for (final slot in slotsSnapshot.docs) {
        final data = slot.data();
        final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];
        for (final person in allotedTo) {
          if (person is Map<String, dynamic>) {
            final email = person['email'] as String?;
            if (email != null && email.isNotEmpty) {
              allocatedEmails.add(email);
            }
          }
        }
      }

      // Filter out already allocated users
      return allUsers.where((user) => !allocatedEmails.contains(user['email'])).toList();
    } catch (e) {
      print('Error fetching available users: $e');
      return [];
    }
  }

  Future<bool> _addSlotToFirestore(Map<String, dynamic> slotData, String slotId) async {
    try {
      await _firestore.collection('Slots').doc(slotId).set(slotData);
      _showSnackBar("Slot added successfully", Colors.green);
      return true;
    } catch (e) {
      _showSnackBar("Error adding slot: ${e.toString()}", Colors.red);
      return false;
    }
  }
}


