import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Add these imports at the top of your file
import 'dart:typed_data';
import 'package:flutter/foundation.dart';


import 'package:flutter/services.dart';

import '../../viewModel/allocation_backend.dart';

class AllocationUI extends StatefulWidget {
  const AllocationUI({Key? key}) : super(key: key);

  @override
  State<AllocationUI> createState() => _AllocationUIState();
}

class _AllocationUIState extends State<AllocationUI> {
  bool isProcessing = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _showEmptySlots = false;
  bool _showAllottedSlots = false;

  final CombinedUploadService _uploadService = CombinedUploadService();

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

      // FIXED: Platform-specific file handling
      if (kIsWeb) {
        // WEB: Use bytes only
        if (file.bytes == null) {
          _showSnackBar("File bytes not available on web", Colors.red);
          setState(() {
            isProcessing = false;
          });
          return;
        }

        log = await _uploadService.processCombinedFile(
          fileBytes: file.bytes,
          fileName: file.name,

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

        log = await _uploadService.processCombinedFile(
          filePath: file.path,
          fileName: file.name,
        );
      }

      // Parse the log to show appropriate message
      if (log.contains("Combined Upload Complete")) {
        try {
          final lines = log.split('\n');

          // Extract slots count
          String? slotsLine = lines.firstWhere(
                (line) => line.contains('Successfully uploaded:') && !line.contains('users'),
            orElse: () => '',
          );

          // Extract users count
          String? usersLine = lines.firstWhere(
                (line) => line.contains('Successfully uploaded:') && line.contains('users'),
            orElse: () => '',
          );

          // Extract numbers using regex
          final slotsMatch = RegExp(r'Successfully uploaded:\s*(\d+)').firstMatch(slotsLine);
          final usersMatch = RegExp(r'Successfully uploaded:\s*(\d+)').firstMatch(usersLine);

          final slotsCount = slotsMatch?.group(1) ?? '0';
          final usersCount = usersMatch?.group(1) ?? '0';

          String action = clearExisting ? "replaced" : "uploaded";
          _showSnackBar(
              "Successfully $action $slotsCount slots and $usersCount users",
              Colors.green
          );

          // Show additional info about emails if present
          if (log.contains('Password reset emails sent')) {
            Future.delayed(Duration(seconds: 2), () {
              _showSnackBar("Password reset emails sent to new users", Colors.blue);
            });
          }

          // Show skipped info if present
          if (log.contains('Skipped due to errors:')) {
            final skippedLine = lines.firstWhere(
                  (line) => line.contains('Skipped due to errors:'),
              orElse: () => '',
            );
            if (skippedLine.isNotEmpty) {
              final skippedMatch = RegExp(r'(\d+)').firstMatch(skippedLine);
              final skippedCount = skippedMatch?.group(0) ?? '0';
              if (int.tryParse(skippedCount) != null && int.parse(skippedCount) > 0) {
                Future.delayed(Duration(seconds: 3), () {
                  _showSnackBar("Note: $skippedCount rows had errors", Colors.orange);
                });
              }
            }
          }

        } catch (e) {
          _showSnackBar("Upload completed successfully!", Colors.green);
        }
      } else if (log.contains("Error during combined import")) {
        final lines = log.split('\n');
        final errorLine = lines.isNotEmpty ? lines.first : "Unknown error occurred";
        _showSnackBar("Upload failed: $errorLine", Colors.red);
      } else {
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
                  'Select an Excel (.xlsx) or CSV file to upload both parking slots and users data',
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

                    Text(
                      'Slot Allocation Data',
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

                        _buildSlotCategoryCard(
                          title: 'Unalloted Slots',
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
    final slotId = data['slotNo'] ?? slot.id; // Changed from slotId to slotNo
    final vehicleType = data['vehicleType'] ?? '';
    final slotPriority = data['slotPriority'] ?? '';
    final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];
    final vehicleCompatibility = data['vehicleCompatibility'] ?? ''; // Fixed key name

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
            // Add expiry status for allocated users
            if (allotedTo.isNotEmpty) ...[
              SizedBox(height: isWide ? 8 : 6),
              ...allotedTo.map((allocation) {
                if (allocation is Map<String, dynamic>) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SlotPeriodManager.getExpiryStatusWidget(allocation, context),
                  );
                }
                return SizedBox.shrink();
              }).toList(),
            ],
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
        title: const Text('Slot Allocation Management '),
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

                _buildSlotsDataSection(),
              ],
            ),
          ),
        ),
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



class SlotDetailsBottomSheet extends StatefulWidget {
  final String slotId;
  final Map<String, dynamic> data;
  final List<dynamic> allotedTo;
  final Future<List<Map<String, dynamic>>> Function() getAvailableUsers;
  final VoidCallback onSlotUpdated;

  const SlotDetailsBottomSheet({
    Key? key,
    required this.slotId,
    required this.data,
    required this.allotedTo,
    required this.getAvailableUsers,
    required this.onSlotUpdated,
  }) : super(key: key);

  @override
  _SlotDetailsBottomSheetState createState() => _SlotDetailsBottomSheetState();
}




class _SlotDetailsBottomSheetState extends State<SlotDetailsBottomSheet> {
  List<Map<String, dynamic>> _allocatedPersons = [];
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    // Convert existing allotedTo to mutable list
    _allocatedPersons = widget.allotedTo.map((person) {
      final personMap = person as Map<String, dynamic>;
      return Map<String, dynamic>.from(personMap);
    }).toList();

    _loadAvailableUsers();
  }

  Future<void> _loadAvailableUsers() async {
    final users = await widget.getAvailableUsers();
    setState(() {
      _availableUsers = users;
    });
  }


  Future<void> _deleteSlot() async {
    // Show confirmation dialog
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: theme.dialogBackgroundColor,
          surfaceTintColor: colorScheme.surfaceTint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning,
                color: colorScheme.error, // dynamic red for both themes
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Delete Slot',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this slot?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceVariant.withOpacity(0.8)
                      : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.error.withOpacity(0.24), // semi-transparent red
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Slot ID: ${widget.slotId}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vehicle Type: ${widget.data['vehicleType'] ?? 'Unknown'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (_allocatedPersons.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Allocated to: ${_allocatedPersons.length} person(s)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This action cannot be undone.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: colorScheme.primary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      try {
        print('Deleting slot: ${widget.slotId}');

        // Convert slotId to proper document ID format
        final documentId = _convertSlotNoToDocId(widget.slotId);
        print('Converted Document ID for deletion: $documentId');

        await FirebaseFirestore.instance
            .collection('Slots')
            .doc(documentId)
            .delete();

        print('Slot deleted successfully');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Slot deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );

          widget.onSlotUpdated();
          Navigator.pop(context);
        }
      } catch (e) {
        print('Error deleting slot: $e');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting slot: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }




  void _addPerson() async {
    setState(() {
      _allocatedPersons.add({
        'name': '',
        'email': '',
        'period_months': 6, // Default to 6 months instead of 1
        'alloted_date': DateTime.now().toIso8601String(),
        'expiry_date': _calculateExpiryDate(DateTime.now(), 6), // Calculate expiry for 6 months
      });
    });
    await _loadAvailableUsers();
  }



// 2. Add helper method to calculate expiry date
  String _calculateExpiryDate(DateTime allotedDate, int periodMonths) {
    final expiryDate = DateTime(
      allotedDate.year,
      allotedDate.month + periodMonths,
      allotedDate.day,
    );
    return expiryDate.toIso8601String();
  }


  void _removePerson(int index) {
    setState(() {
      _allocatedPersons.removeAt(index);
    });
    _loadAvailableUsers();
  }

  void _updatePersonData(int index, String field, dynamic value) {
    setState(() {
      _allocatedPersons[index][field] = value;

      // Recalculate expiry date when period changes
      if (field == 'period_months') {
        final allotedDateStr = _allocatedPersons[index]['alloted_date'];
        if (allotedDateStr != null) {
          final allotedDate = DateTime.parse(allotedDateStr);
          _allocatedPersons[index]['expiry_date'] = _calculateExpiryDate(allotedDate, value as int);
        }
      }
    });
  }



  String _determinePriority() {
    if (_allocatedPersons.isEmpty) {
      return 'TEMPORARY';
    } else if (_allocatedPersons.length > 1) {
      return 'HYBRID';
    } else {
      return 'PERMANENT';
    }
  }

  // Add this helper method to convert slotNo to document ID
  String _convertSlotNoToDocId(String slotNo) {
    return slotNo
        .replaceAll(RegExp(r'\s+'), '-')         // Replace spaces with hyphens
        .replaceAll('(', '')                     // Remove (
        .replaceAll(')', '')                     // Remove )
        .replaceAll('/', '-')                    // Replace / with -
        .replaceAll(RegExp(r'[^\w\-]'), '')      // Remove all non-word characters except hyphen
        .replaceAll(RegExp(r'-+'), '-')          // Replace multiple hyphens with single
        .replaceAll(RegExp(r'^-+|-+$'), '')      // Trim leading/trailing hyphens
        .toLowerCase();                          // Convert to lowercase
  }

  Future<void> _updateSlot() async {
    print('Update slot button pressed'); // Debug print

    setState(() {
      _isLoading = true;
    });

    try {
      print('Starting slot update process'); // Debug print

      // Validate that all persons have valid data including period
      bool hasValidPersons = true;

      if (_allocatedPersons.isNotEmpty) {
        for (int i = 0; i < _allocatedPersons.length; i++) {
          final person = _allocatedPersons[i];
          print('Validating person $i: ${person.toString()}'); // Debug print

          final name = person['name']?.toString().trim() ?? '';
          final email = person['email']?.toString().trim() ?? '';
          final period = person['period_months'];

          if (name.isEmpty || email.isEmpty || period == null || period <= 0) {
            hasValidPersons = false;
            print('Validation failed for person $i: name=$name, email=$email, period=$period');
            break;
          }
        }
      }

      if (_allocatedPersons.isNotEmpty && !hasValidPersons) {
        print('Validation failed - showing error message');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill all allocated person details including period or remove empty entries'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      print('Validation passed, updating slot data');

      // Update slot data
      final updatedData = Map<String, dynamic>.from(widget.data);
      updatedData['alloted_to'] = _allocatedPersons;
      updatedData['slotPriority'] = _determinePriority();
      updatedData['updated_at'] = DateTime.now().toIso8601String();

      print('Updated data: ${updatedData.toString()}');
      print('Original Slot ID: ${widget.slotId}');

      // Convert slotId to proper document ID format
      final documentId = _convertSlotNoToDocId(widget.slotId);
      print('Converted Document ID: $documentId');

      // Check if document exists first
      final docRef = FirebaseFirestore.instance.collection('Slots').doc(documentId);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        print('Document does not exist, creating new document');
        // Document doesn't exist, create it
        await docRef.set(updatedData);
      } else {
        print('Document exists, updating existing document');
        // Document exists, update it
        await docRef.update(updatedData);
      }

      print('Firestore operation completed successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Slot updated successfully'),
            backgroundColor: Colors.green,
          ),
        );

        widget.onSlotUpdated();
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error updating slot: $e'); // Debug print
      print('Error stack trace: ${e.toString()}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating slot: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      print('Resetting loading state'); // Debug print
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }




  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8),
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getVehicleTypeColor(widget.data['vehicleType'] ?? ''),
                  child: Icon(
                    _getVehicleTypeIcon(widget.data['vehicleType'] ?? ''),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Slot: ${widget.slotId}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildChip(widget.data['vehicleType'] ?? '', Colors.blue),
                          _buildChip(_determinePriority(), Colors.orange),
                          if (widget.data['vehicleType'] == 'CAR' && (widget.data['VehicleCompatibility'] ?? '').isNotEmpty)
                            _buildChip(widget.data['VehicleCompatibility'] ?? '', Colors.purple),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Allocated Users:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _addPerson,
                        icon: const Icon(Icons.person_add, size: 16),
                        label: const Text('Add'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          foregroundColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_allocatedPersons.isEmpty)
                    Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.person_off_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No allocation',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(_allocatedPersons.length, (index) {
                      final person = _allocatedPersons[index];
                      final hasExistingData = person['name']?.toString().trim().isNotEmpty == true &&
                          person['email']?.toString().trim().isNotEmpty == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).shadowColor.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Person ${index + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => _removePerson(index),
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Show existing user details if available, otherwise show dropdown
                            if (hasExistingData) ...[
                              // Display existing user information
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.person,
                                          size: 16,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            person['name'] ?? 'Unknown',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.email,
                                          size: 16,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            person['email'] ?? 'Unknown',
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Period input for existing users
                              Row(
                                children: [
                                  Expanded(
                                    child: // In the TextFormField for period input, add validation
                                    TextFormField(
                                      initialValue: person['period_months']?.toString() ?? '6',
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Period (Months)',
                                        labelStyle: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.access_time,
                                          size: 20,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        helperText: 'Minimum 1 month, Maximum 36 months',
                                      ),
                                      onChanged: (value) {
                                        int period = int.tryParse(value) ?? 6;
                                        // Add validation
                                        if (period < 1) period = 1;
                                        if (period > 36) period = 36;
                                        _updatePersonData(index, 'period_months', period);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              // Show dropdown for selecting new user
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  labelText: 'Select User',
                                  labelStyle: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                dropdownColor: Theme.of(context).colorScheme.surface,
                                isExpanded: true,
                                value: person['email']?.isEmpty ?? true ? null : person['email'],
                                items: _availableUsers.where((user) {
                                  final currentEmail = person['email'];
                                  final otherSelectedEmails = _allocatedPersons
                                      .asMap()
                                      .entries
                                      .where((entry) => entry.key != index)
                                      .map((entry) => entry.value['email'])
                                      .where((email) => email != null && email.isNotEmpty)
                                      .toSet();

                                  return user['email'] == currentEmail || !otherSelectedEmails.contains(user['email']);
                                }).map((user) {
                                  return DropdownMenuItem<String>(
                                    value: user['email'],
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: Text(
                                        '${user['name']} (${user['email']})',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (selectedEmail) {
                                  if (selectedEmail != null) {
                                    final selectedUser = _availableUsers.firstWhere(
                                          (user) => user['email'] == selectedEmail,
                                    );
                                    _updatePersonData(index, 'name', selectedUser['name']);
                                    _updatePersonData(index, 'email', selectedUser['email']);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              // Period input for new users
// In the TextFormField for period input, add validation
                              TextFormField(
                                initialValue: person['period_months']?.toString() ?? '6',
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Period (Months)',
                                  labelStyle: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.access_time,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  helperText: 'Minimum 1 month, Maximum 36 months',
                                ),
                                onChanged: (value) {
                                  int period = int.tryParse(value) ?? 6;
                                  // Add validation
                                  if (period < 1) period = 1;
                                  if (period > 36) period = 36;
                                  _updatePersonData(index, 'period_months', period);
                                },
                              ),
                            ],

                            // Always show allocation date and expiry date if available
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                // Allocation date
                                if (person['alloted_date'] != null)
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.green.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today,
                                                size: 12,
                                                color: Colors.green.shade700,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Allotted',
                                                style: TextStyle(
                                                  color: Colors.green.shade700,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            _formatDate(person['alloted_date']),
                                            style: TextStyle(
                                              color: Colors.green.shade700,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                // Expiry date
                                if (person['expiry_date'] != null)
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.orange.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.event_busy,
                                                size: 12,
                                                color: Colors.orange.shade700,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Expires',
                                                style: TextStyle(
                                                  color: Colors.orange.shade700,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            _formatDate(person['expiry_date']),
                                            style: TextStyle(
                                              color: Colors.orange.shade700,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),

                            // Period display
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    size: 14,
                                    color: Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Period: ${person['period_months'] ?? 1} month(s)',
                                    style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          // Update Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                // Delete FAB-style Button
                Material(
                  color: Colors.red.withOpacity(0.1),
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 28),
                    tooltip: 'Delete Slot',
                    onPressed: _isLoading ? null : _deleteSlot,
                    splashRadius: 26,
                  ),
                ),
                const SizedBox(width: 16),
                // Modern Update Button (full width)
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _updateSlot,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _isLoading
                              ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          )
                              : const Icon(Icons.save_rounded, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            _isLoading ? 'Updating...' : 'Update Slot',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods (copy from your existing code)
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

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }
}

// Admin utility methods for managing slot periods

class SlotPeriodManager {

  // Check if a slot allocation is expired
  static bool isSlotExpired(Map<String, dynamic> allocation) {
    final expiryDateStr = allocation['expiry_date'];
    if (expiryDateStr == null) return false;

    try {
      final expiryDate = DateTime.parse(expiryDateStr);
      return DateTime.now().isAfter(expiryDate);
    } catch (e) {
      return false;
    }
  }

  // Get days until expiry (negative if expired)
  static int getDaysUntilExpiry(Map<String, dynamic> allocation) {
    final expiryDateStr = allocation['expiry_date'];
    if (expiryDateStr == null) return 0;

    try {
      final expiryDate = DateTime.parse(expiryDateStr);
      return expiryDate.difference(DateTime.now()).inDays;
    } catch (e) {
      return 0;
    }
  }
  static Map<String, dynamic> extendSlotPeriod(
      Map<String, dynamic> allocation,
      int additionalMonths,
      ) {
    final updatedAllocation = Map<String, dynamic>.from(allocation);
    final currentPeriod = (allocation['period_months'] ?? 1) as int;
    final newPeriod = currentPeriod + additionalMonths;

    final allotedDateStr = allocation['alloted_date'];

    if (allotedDateStr != null) {
      try {
        final allotedDate = DateTime.parse(allotedDateStr);
        final newExpiryDate = DateTime(
          allotedDate.year,
          allotedDate.month + newPeriod,
          allotedDate.day,
        );

        updatedAllocation['period_months'] = newPeriod;
        updatedAllocation['expiry_date'] = newExpiryDate.toIso8601String();
        updatedAllocation['updated_at'] = DateTime.now().toIso8601String();
      } catch (e) {
        print('Error extending slot period: $e');
      }
    }

    return updatedAllocation;
  }




  // Get expiry status widget for admin UI
  static Widget getExpiryStatusWidget(
      Map<String, dynamic> allocation,
      BuildContext context
      ) {
    final daysUntilExpiry = getDaysUntilExpiry(allocation);

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (daysUntilExpiry < 0) {
      // Expired
      statusColor = Colors.red;
      statusIcon = Icons.error;
      statusText = 'Expired ${-daysUntilExpiry} days ago';
    } else if (daysUntilExpiry <= 7) {
      // Expiring soon
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
      statusText = 'Expires in $daysUntilExpiry days';
    } else if (daysUntilExpiry <= 30) {
      // Expiring this month
      statusColor = Colors.amber;
      statusIcon = Icons.schedule;
      statusText = 'Expires in $daysUntilExpiry days';
    } else {
      // Active
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'Active ($daysUntilExpiry days left)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            size: 14,
            color: statusColor,
          ),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Bulk update expired slots (for admin cleanup)
  static Future<void> bulkRemoveExpiredAllocations() async {
    try {
      final slotsSnapshot = await FirebaseFirestore.instance
          .collection('Slots')
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (final doc in slotsSnapshot.docs) {
        final data = doc.data();
        final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];

        final activeAllocations = allotedTo.where((allocation) {
          return !isSlotExpired(allocation as Map<String, dynamic>);
        }).toList();

        if (activeAllocations.length != allotedTo.length) {
          // Update the document with only active allocations
          final updatedData = Map<String, dynamic>.from(data);
          updatedData['alloted_to'] = activeAllocations;
          updatedData['updated_at'] = DateTime.now().toIso8601String();

          // Update slot priority based on remaining allocations
          if (activeAllocations.isEmpty) {
            updatedData['slotPriority'] = 'TEMPORARY';
          } else if (activeAllocations.length > 1) {
            updatedData['slotPriority'] = 'HYBRID';
          } else {
            updatedData['slotPriority'] = 'PERMANENT';
          }

          batch.update(doc.reference, updatedData);
        }
      }

      await batch.commit();
      print('Bulk cleanup completed');
    } catch (e) {
      print('Error in bulk cleanup: $e');
    }
  }

  // Get slots expiring in next N days
  static Future<List<Map<String, dynamic>>> getSlotsExpiringInDays(int days) async {
    final slotsSnapshot = await FirebaseFirestore.instance
        .collection('Slots')
        .get();

    final expiringSoon = <Map<String, dynamic>>[];

    for (final doc in slotsSnapshot.docs) {
      final data = doc.data();
      final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];

      for (final allocation in allotedTo) {
        final allocationMap = allocation as Map<String, dynamic>;
        final daysUntilExpiry = getDaysUntilExpiry(allocationMap);

        if (daysUntilExpiry >= 0 && daysUntilExpiry <= days) {
          expiringSoon.add({
            'slotId': doc.id,
            'slotData': data,
            'allocation': allocationMap,
            'daysUntilExpiry': daysUntilExpiry,
          });
        }
      }
    }

    // Sort by days until expiry (ascending)
    expiringSoon.sort((a, b) =>
        a['daysUntilExpiry'].compareTo(b['daysUntilExpiry']));

    return expiringSoon;
  }
}