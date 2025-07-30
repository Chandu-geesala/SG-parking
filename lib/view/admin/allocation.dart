import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../viewModel/allocation_backend.dart';

/// Main UI for managing parking slot allocations
/// Handles complete database replacement, slot viewing, and individual slot management
class AllocationUI extends StatefulWidget {
  const AllocationUI({Key? key}) : super(key: key);

  @override
  State<AllocationUI> createState() => _AllocationUIState();
}

class _AllocationUIState extends State<AllocationUI> {
  // ============================================================================
  // STATE VARIABLES
  // ============================================================================

  bool isProcessing = false;
  bool _showEmptySlots = false;
  bool _showAllottedSlots = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CombinedUploadService _uploadService = CombinedUploadService();

  // ============================================================================
  // FILE UPLOAD & COMPLETE REPLACE FUNCTIONALITY
  // ============================================================================

  /// Handles file selection and complete database replacement
  /// Supports both CSV and Excel files for web and mobile platforms
  void _pickAndProcessCompleteReplace() async {
    setState(() {
      isProcessing = true;
    });

    try {
      // File selection
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
      );

      if (result == null) {
        _showSnackBar("No file selected", Colors.orange);
        return;
      }

      final file = result.files.single;
      _showSnackBar("Processing file... This may take a while", Colors.blue);

      String log;

      // Platform-specific file processing
      if (kIsWeb) {
        if (file.bytes == null) {
          _showSnackBar("File bytes not available on web", Colors.red);
          return;
        }
        log = await _uploadService.processCompleteReplace(
          fileBytes: file.bytes,
          fileName: file.name,
        );
      } else {
        if (file.path == null) {
          _showSnackBar("File path not available", Colors.red);
          return;
        }
        log = await _uploadService.processCompleteReplace(
          filePath: file.path,
          fileName: file.name,
        );
      }

      // Handle processing results
      if (log.contains("COMPLETE REPLACE SUCCESSFUL")) {
        _showSuccessMessages(log);
      } else if (log.contains("COMPLETE REPLACE FAILED")) {
        final lines = log.split('\n');
        final errorLine = lines.length > 1 ? lines[1] : "Unknown error occurred";
        _showSnackBar("Complete replace failed: $errorLine", Colors.red);
      } else {
        final firstLine = log.split('\n').first;
        _showSnackBar("Replace issue: $firstLine", Colors.orange);
      }

    } catch (e) {
      _showSnackBar("Error during complete replace: ${e.toString()}", Colors.red);
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  /// Displays success messages with statistics after successful upload
  void _showSuccessMessages(String log) {
    final lines = log.split('\n');
    String? usersCount, slotsCount, authCount;

    // Extract statistics from log
    for (String line in lines) {
      if (line.contains('Users uploaded:')) {
        usersCount = RegExp(r'Users uploaded:\s*(\d+)').firstMatch(line)?.group(1);
      } else if (line.contains('Slots uploaded:')) {
        slotsCount = RegExp(r'Slots uploaded:\s*(\d+)').firstMatch(line)?.group(1);
      } else if (line.contains('Firebase Auth accounts created:')) {
        authCount = RegExp(r'Firebase Auth accounts created:\s*(\d+)').firstMatch(line)?.group(1);
      }
    }

    // Show success message
    _showSnackBar("🚀 Complete Replace Successful! Database completely refreshed.", Colors.green);

    // Show detailed statistics
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        String details = "📊 ";
        if (usersCount != null) details += "$usersCount users, ";
        if (slotsCount != null) details += "$slotsCount slots";
        if (authCount != null) details += ", $authCount auth accounts created";
        _showSnackBar(details, Colors.blue);
      }
    });

    // Show auth information
    if (authCount != null && int.tryParse(authCount) != null && int.parse(authCount) > 0) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          _showSnackBar("📧 Password reset emails sent to all new users", Colors.purple);
        }
      });
    }
  }

  /// Shows confirmation dialog before complete database replacement
  void _showCompleteReplaceConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red[600], size: 28),
              const SizedBox(width: 8),
              const Expanded(child: Text('Complete Database Replace')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This action will:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildConfirmationItem('🗑️', 'Delete ALL existing users'),
              _buildConfirmationItem('🗑️', 'Delete ALL existing parking slots'),
              _buildConfirmationItem('📁', 'Upload fresh data from your file'),
              _buildConfirmationItem('🔧', 'Create new Firebase Auth accounts'),
              _buildConfirmationItem('📧', 'Send password reset emails'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[700], size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'This action cannot be undone!',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Are you absolutely sure you want to continue?',
                  style: TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _pickAndProcessCompleteReplace();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, Replace All'),
            ),
          ],
        );
      },
    );
  }

  /// Helper widget for confirmation dialog items
  Widget _buildConfirmationItem(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  // ============================================================================
  // USER MANAGEMENT FUNCTIONALITY
  // ============================================================================

  /// Fetches available users not currently allocated to any slot
  Future<List<Map<String, dynamic>>> _getAvailableUsers() async {
    try {
      // Get all users from Firestore
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
        final allotedTo = data['alloted_to'] as List? ?? [];
        for (final person in allotedTo) {
          if (person is Map) {
            final email = person['email'] as String?;
            if (email != null && email.isNotEmpty) {
              allocatedEmails.add(email);
            }
          }
        }
      }

      // Return users not already allocated
      return allUsers.where((user) => !allocatedEmails.contains(user['email'])).toList();
    } catch (e) {
      print('Error fetching available users: $e');
      return [];
    }
  }

  // ============================================================================
  // UI BUILDING METHODS
  // ============================================================================

  /// Builds the main upload section for complete database replacement
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
                  color: isDarkMode ? Theme.of(context).colorScheme.primary : Colors.blue[600],
                ),
                SizedBox(height: isWide ? 20 : 16),
                Text(
                  'Complete Database Replace',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Theme.of(context).colorScheme.onSurface : Colors.grey[800],
                    fontSize: isWide ? 24 : 20,
                  ),
                ),
                SizedBox(height: isWide ? 12 : 8),
                Text(
                  'Upload Excel (.xlsx) or CSV file to completely replace all users and slots data',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDarkMode ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.grey[600],
                    fontSize: isWide ? 16 : 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isWide ? 20 : 16),
                SizedBox(
                  width: isWide ? 220 : double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: isProcessing ? null : _showCompleteReplaceConfirmation,
                    icon: isProcessing
                        ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                        : const Icon(Icons.refresh, size: 20),
                    label: Text(
                      isProcessing ? 'Processing...' : 'Complete Replace',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDarkMode ? const Color(0xFFFF6B35) : Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                  ),
                ),
                if (isProcessing) ...[
                  SizedBox(height: isWide ? 16 : 12),
                  Text(
                    'This may take several minutes for large datasets...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds the slots data section displaying all parking slots
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
                Text(
                  'Slot Allocation Data',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Theme.of(context).colorScheme.onSurface : Colors.grey[800],
                    fontSize: isWide ? 24 : 20,
                  ),
                ),
                SizedBox(height: isWide ? 20 : 16),
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
                      return _buildErrorState(isWide);
                    }

                    final slots = snapshot.data?.docs ?? [];
                    if (slots.isEmpty) {
                      return _buildEmptyState(isWide);
                    }

                    // Categorize slots by allocation status
                    final emptySlots = <QueryDocumentSnapshot>[];
                    final allottedSlots = <QueryDocumentSnapshot>[];

                    for (final slot in slots) {
                      final data = slot.data() as Map<String, dynamic>;
                      final allotedTo = data['alloted_to'] as List? ?? [];
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
                          onToggle: () => setState(() => _showEmptySlots = !_showEmptySlots),
                          slots: emptySlots,
                          isWide: isWide,
                          isVeryWide: isVeryWide,
                          constraints: constraints,
                        ),
                        SizedBox(height: isWide ? 16 : 12),
                        _buildSlotCategoryCard(
                          title: 'Allotted Slots',
                          count: allottedSlots.length,
                          color: Colors.orange,
                          icon: Icons.person,
                          isExpanded: _showAllottedSlots,
                          onToggle: () => setState(() => _showAllottedSlots = !_showAllottedSlots),
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

  /// Builds expandable card for slot categories (allocated/unallocated)
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
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          // Category header with click to expand
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
                      child: Icon(icon, color: color, size: isWide ? 24 : 20),
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
                      child: Icon(Icons.expand_more, color: color, size: isWide ? 24 : 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Expandable content
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

  /// Builds the list/grid of slots based on screen size
  Widget _buildSlotsList(List<QueryDocumentSnapshot> slots, bool isWide, bool isVeryWide, BoxConstraints constraints) {
    if (isVeryWide) {
      // Grid layout for wide screens
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

    // List layout for mobile/tablet
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: slots.length,
      itemBuilder: (context, index) => Container(
        margin: EdgeInsets.only(bottom: isWide ? 12 : 8),
        child: _buildSlotItem(slots[index], isWide),
      ),
    );
  }

  /// Builds individual slot item widget
  Widget _buildSlotItem(QueryDocumentSnapshot slot, bool isWide) {
    final data = slot.data() as Map<String, dynamic>;
    final slotId = data['slotNo'] ?? slot.id;
    final vehicleType = data['vehicleType'] ?? '';
    final slotPriority = data['slotPriority'] ?? '';
    final allotedTo = data['alloted_to'] as List? ?? [];
    final vehicleCompatibility = data['vehicleCompatibility'] ?? '';

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
            // Show expiry status for allocated slots
            if (allotedTo.isNotEmpty) ...[
              SizedBox(height: isWide ? 8 : 6),
              ...allotedTo.map((allocation) {
                if (allocation is Map) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SlotPeriodManager.getExpiryStatusWidget(
                        allocation as Map<String, dynamic>, context),
                  );
                }
                return const SizedBox.shrink();
              }).toList(),
            ],
          ],
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: isWide ? 16 : 14),
        onTap: () => _showSlotDetailsBottomSheet(
            context, slotId, data, allotedTo),
      ),
    );
  }

  /// Builds error state widget
  Widget _buildErrorState(bool isWide) {
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

  /// Builds empty state widget
  Widget _buildEmptyState(bool isWide) {
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

  /// Builds small chip widget for displaying tags
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

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Shows slot details in a bottom sheet for editing
  void _showSlotDetailsBottomSheet(
      BuildContext context, String slotId, Map<String, dynamic> data, List allotedTo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SlotDetailsBottomSheet(
        slotId: slotId,
        data: data,
        allotedTo: allotedTo,
        getAvailableUsers: _getAvailableUsers,
        onSlotUpdated: () => setState(() {}),
      ),
    );
  }

  /// Displays snackbar messages
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

  /// Formats date string for display
  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  /// Returns color based on vehicle type
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

  /// Returns icon based on vehicle type
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

  // ============================================================================
  // MAIN BUILD METHOD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Slot Allocation Management'),
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
          constraints: const BoxConstraints(maxWidth: 1200),
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
}

// ============================================================================
// SLOT DETAILS BOTTOM SHEET
// ============================================================================

/// Bottom sheet for viewing and editing individual slot details
class SlotDetailsBottomSheet extends StatefulWidget {
  final String slotId;
  final Map<String, dynamic> data;
  final List allotedTo;
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
  // State variables
  List<Map<String, dynamic>> _allocatedPersons = [];
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoading = false;
  static const List<String> _periodUnits = ['Day', 'Month'];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // ============================================================================
  // INITIALIZATION METHODS
  // ============================================================================

  /// Initializes the allocated persons data with migration support
  void _initializeData() {
    _allocatedPersons = widget.allotedTo.map((person) {
      final personMap = person as Map<String, dynamic>;

      // Migrate old period_months to new flexible period system
      if (!personMap.containsKey('period_unit')) {
        if (personMap.containsKey('period_months')) {
          personMap['period_value'] = personMap['period_months'];
          personMap['period_unit'] = 'Month';
        } else {
          personMap['period_value'] = 1;
          personMap['period_unit'] = 'Day';
        }
      }

      return Map<String, dynamic>.from(personMap);
    }).toList();

    _loadAvailableUsers();
  }

  /// Loads available users from the parent widget
  Future<void> _loadAvailableUsers() async {
    final users = await widget.getAvailableUsers();
    setState(() {
      _availableUsers = users;
    });
  }

  // ============================================================================
  // PERSON MANAGEMENT METHODS
  // ============================================================================

  /// Adds a new person to the allocation list
  void _addPerson() async {
    setState(() {
      _allocatedPersons.add({
        'name': '',
        'email': '',
        'period_value': 1,
        'period_unit': 'Day',
        'alloted_date': DateTime.now().toIso8601String(),
        'expiry_date': _calculateExpiryDateFlexible(DateTime.now(), 1, 'Day'),
      });
    });
    await _loadAvailableUsers();
  }

  /// Removes a person from the allocation list
  void _removePerson(int index) {
    setState(() {
      _allocatedPersons.removeAt(index);
    });
    _loadAvailableUsers();
  }

  /// Updates person data and recalculates expiry date if needed
  void _updatePersonData(int index, String field, dynamic value) {
    setState(() {
      _allocatedPersons[index][field] = value;

      // Recalculate expiry date when period changes
      if (field == 'period_value' || field == 'period_unit') {
        final allotedDateStr = _allocatedPersons[index]['alloted_date'];
        final periodValue = _allocatedPersons[index]['period_value'] ?? 1;
        final periodUnit = _allocatedPersons[index]['period_unit'] ?? 'Day';

        if (allotedDateStr != null) {
          final allotedDate = DateTime.parse(allotedDateStr);
          _allocatedPersons[index]['expiry_date'] =
              _calculateExpiryDateFlexible(allotedDate, periodValue, periodUnit);
        }
      }
    });
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Calculates expiry date based on period value and unit
  String _calculateExpiryDateFlexible(DateTime allotedDate, int periodValue, String periodUnit) {
    DateTime expiryDate;
    if (periodUnit == 'Month') {
      expiryDate = DateTime(
        allotedDate.year,
        allotedDate.month + periodValue,
        allotedDate.day,
      );
    } else {
      expiryDate = allotedDate.add(Duration(days: periodValue));
    }
    return expiryDate.toIso8601String();
  }

  /// Determines slot priority based on allocation count
  String _determinePriority() {
    if (_allocatedPersons.isEmpty) {
      return 'UNALLOCATED';
    } else if (_allocatedPersons.length > 1) {
      return 'HYBRID';
    } else {
      return 'PERMANENT';
    }
  }

  /// Converts slot number to valid Firestore document ID
  String _convertSlotNoToDocId(String slotNo) {
    return slotNo
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('/', '-')
        .replaceAll(RegExp(r'[^\w\-]'), '')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .toLowerCase();
  }

  /// Formats date for display
  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  /// Returns color based on vehicle type
  Color _getVehicleTypeColor(String vehicleType) {
    switch (vehicleType.toUpperCase()) {
      case 'CAR': return Colors.blue;
      case 'BIKE': return Colors.green;
      default: return Colors.grey;
    }
  }

  /// Returns icon based on vehicle type
  IconData _getVehicleTypeIcon(String vehicleType) {
    switch (vehicleType.toUpperCase()) {
      case 'CAR': return Icons.directions_car;
      case 'BIKE': return Icons.two_wheeler;
      default: return Icons.local_parking;
    }
  }

  /// Builds chip widget for tags
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

  // ============================================================================
  // SLOT OPERATIONS
  // ============================================================================

  /// Updates slot data in Firestore
  Future<void> _updateSlot() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Validate allocated persons data
      if (_allocatedPersons.isNotEmpty) {
        bool hasValidPersons = _allocatedPersons.every((person) {
          final name = person['name']?.toString().trim() ?? '';
          final email = person['email']?.toString().trim() ?? '';
          final periodValue = person['period_value'];
          final periodUnit = person['period_unit'];

          return name.isNotEmpty &&
              email.isNotEmpty &&
              periodValue != null &&
              periodValue > 0 &&
              periodUnit != null;
        });

        if (!hasValidPersons) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please fill all allocated person details including period or remove empty entries'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      // Prepare updated data
      final updatedData = Map<String, dynamic>.from(widget.data);
      updatedData['alloted_to'] = _allocatedPersons;
      updatedData['slotPriority'] = _determinePriority();
      updatedData['updated_at'] = DateTime.now().toIso8601String();

      // Update Firestore document
      final documentId = _convertSlotNoToDocId(widget.slotId);
      final docRef = FirebaseFirestore.instance.collection('Slots').doc(documentId);

      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        await docRef.set(updatedData);
      } else {
        await docRef.update(updatedData);
      }

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating slot: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Deletes the slot after confirmation
  Future<void> _deleteSlot() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: theme.dialogBackgroundColor,
          surfaceTintColor: colorScheme.surfaceTint,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning, color: colorScheme.error, size: 24),
              const SizedBox(width: 8),
              Text('Delete Slot', style: theme.textTheme.titleLarge?.copyWith(color: colorScheme.onSurface)),
            ],
          ),
          content: Text(
            'Are you sure you want to delete this slot?',
            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: colorScheme.primary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      try {
        final documentId = _convertSlotNoToDocId(widget.slotId);
        await FirebaseFirestore.instance.collection('Slots').doc(documentId).delete();

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

  // ============================================================================
  // BUILD METHOD
  // ============================================================================

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

          // Header section
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
                          if (widget.data['vehicleType'] == 'CAR' &&
                              (widget.data['VehicleCompatibility'] ?? '').isNotEmpty)
                            _buildChip(widget.data['VehicleCompatibility'] ?? '', Colors.purple),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),

          // Main content area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Allocated users header
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
                          side: BorderSide(color: Theme.of(context).colorScheme.primary),
                          foregroundColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Show allocated persons or empty state
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
                  // List of allocated persons
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
                            // Person header with delete button
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

                            // User selection or display
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
                            ] else ...[
                              // User selection dropdown
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  labelText: 'Select User',
                                  labelStyle: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                  return user['email'] == currentEmail ||
                                      !otherSelectedEmails.contains(user['email']);
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
                            ],

                            const SizedBox(height: 12),

                            // Period input
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: person['period_value']?.toString() ?? '1',
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Period',
                                      labelStyle: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      prefixIcon: Icon(
                                        Icons.access_time,
                                        size: 20,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      int period = int.tryParse(value) ?? 1;
                                      if (period < 1) period = 1;
                                      if (person['period_unit'] == 'Month' && period > 36) period = 36;
                                      if (person['period_unit'] == 'Day' && period > 365) period = 365;
                                      _updatePersonData(index, 'period_value', period);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                DropdownButton<String>(
                                  value: person['period_unit'] ?? 'Day',
                                  items: _periodUnits.map((unit) {
                                    return DropdownMenuItem<String>(
                                      value: unit,
                                      child: Text(unit),
                                    );
                                  }).toList(),
                                  onChanged: (selected) {
                                    if (selected != null) {
                                      _updatePersonData(index, 'period_unit', selected);
                                    }
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Date information
                            Row(
                              children: [
                                if (person['alloted_date'] != null)
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.calendar_today, size: 12, color: Colors.green.shade700),
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
                                if (person['expiry_date'] != null)
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.event_busy, size: 12, color: Colors.orange.shade700),
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
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),

          // Bottom action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                // Delete button
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

                // Update button
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _updateSlot,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                              valueColor: AlwaysStoppedAnimation(
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
}

// ============================================================================
// SLOT PERIOD MANAGER UTILITY CLASS
// ============================================================================

/// Utility class for managing slot periods and expiry dates
class SlotPeriodManager {
  /// Checks if a slot allocation is expired
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

  /// Gets days until expiry (negative if expired)
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

  /// Extends slot period by additional months
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

  /// Gets expiry status widget for admin UI
  static Widget getExpiryStatusWidget(
      Map<String, dynamic> allocation,
      BuildContext context,
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
    } else if (daysUntilExpiry < 30) {
      // Expiring soon
      statusColor = daysUntilExpiry <= 7 ? Colors.orange : Colors.amber;
      statusIcon = daysUntilExpiry <= 7 ? Icons.warning : Icons.schedule;
      statusText = 'Expires in $daysUntilExpiry days';
    } else {
      // Active
      int monthsLeft = (daysUntilExpiry / 30).ceil();
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'Active ($monthsLeft month${monthsLeft > 1 ? 's' : ''} left)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
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

  /// Bulk removes expired slot allocations
  static Future<void> bulkRemoveExpiredAllocations() async {
    try {
      final slotsSnapshot = await FirebaseFirestore.instance.collection('Slots').get();
      final batch = FirebaseFirestore.instance.batch();

      for (final doc in slotsSnapshot.docs) {
        final data = doc.data();
        final allotedTo = data['alloted_to'] as List? ?? [];

        final activeAllocations = allotedTo.where((allocation) {
          return !isSlotExpired(allocation as Map<String, dynamic>);
        }).toList();

        if (activeAllocations.length != allotedTo.length) {
          final updatedData = Map<String, dynamic>.from(data);
          updatedData['alloted_to'] = activeAllocations;
          updatedData['updated_at'] = DateTime.now().toIso8601String();

          // Update slot priority
          if (activeAllocations.isEmpty) {
            updatedData['slotPriority'] = 'UNALLOCATED';
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

  /// Gets slots expiring in the next N days
  static Future<List<Map<String, dynamic>>> getSlotsExpiringInDays(int days) async {
    final slotsSnapshot = await FirebaseFirestore.instance.collection('Slots').get();
    final expiringSoon = <Map<String, dynamic>>[];

    for (final doc in slotsSnapshot.docs) {
      final data = doc.data();
      final allotedTo = data['alloted_to'] as List? ?? [];

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

    // Sort by days until expiry
    expiringSoon.sort((a, b) =>
        a['daysUntilExpiry'].compareTo(b['daysUntilExpiry']));

    return expiringSoon;
  }
}
