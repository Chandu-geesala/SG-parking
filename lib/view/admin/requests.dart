import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../viewModel/bookingBackend.dart';

class RequestsPage extends StatefulWidget {
  const RequestsPage({Key? key}) : super(key: key);

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  String _selectedFilter = 'latest';
  bool _isLoading = true;
  final BookingBackend _bookingBackend = BookingBackend();
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _filteredRequests = [];

  List<Map<String, dynamic>> _availableSlots = [];
  bool _isLoadingSlots = false;
  Map<String, String?> _selectedSlots = {};

  bool _allowRequests = false;
  bool _allowAutoAllotment = false;
  StreamSubscription<DocumentSnapshot>? _toggleSubscription;

  String getDisplayNameFromEmail(String email) {
    final usernamePart = email.split('@').first;
    final words = usernamePart.split('.').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).toList();
    return words.join(' ');
  }



  @override
  void initState() {
    super.initState();
    _loadAvailableSlots();
    _loadRequests();
    _initializeToggleListener(); // Add this line
  }

  @override
  void dispose() {
    _toggleSubscription?.cancel(); // Add this line
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);

    try {
      final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('requests')
          .orderBy('timestamp', descending: true)
          .get();

      final List<Map<String, dynamic>> loadedRequests = querySnapshot.docs
          .map((doc) => {
        'id': doc.id,
        'data': doc.data() as Map<String, dynamic>,
      })
          .toList();

      setState(() {
        _requests = loadedRequests;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Error loading requests: ${e.toString()}', true);
    }
  }

  void _applyFilter() {
    setState(() {
      List<Map<String, dynamic>> filtered = [];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      if (_selectedFilter == 'latest') {
        // Show all requests from today (all types)
        filtered = _requests.where((request) {
          final timestamp = request['data']['timestamp'] as Timestamp?;
          if (timestamp == null) return false;

          final requestDate = timestamp.toDate();
          final requestDay = DateTime(requestDate.year, requestDate.month, requestDate.day);

          return requestDay.isAtSameMomentAs(today);
        }).toList();
      } else if (_selectedFilter == 'old') {
        // Show only TodReq and AltReq requests that are NOT from today
        filtered = _requests.where((request) {
          final type = request['data']['type'];
          if (type != 'TodReq' && type != 'AltReq') return false;

          final timestamp = request['data']['timestamp'] as Timestamp?;
          if (timestamp == null) return false;

          final requestDate = timestamp.toDate();
          final requestDay = DateTime(requestDate.year, requestDate.month, requestDate.day);

          return !requestDay.isAtSameMomentAs(today);
        }).toList();
      } else if (_selectedFilter == 'newUsers') {
        // Show all NewReq requests regardless of date
        filtered = _requests
            .where((request) => request['data']['type'] == 'NewReq')
            .toList();
      }

      _filteredRequests = filtered;
    });
  }

// Initialize real-time listener for toggle settings
  void _initializeToggleListener() {
    _toggleSubscription = FirebaseFirestore.instance
        .collection('toggle')
        .doc('settings') // Using a single document for settings
        .snapshots()
        .listen(
          (DocumentSnapshot snapshot) {
        if (mounted) {
          setState(() {
            if (snapshot.exists) {
              final data = snapshot.data() as Map<String, dynamic>?;
              _allowRequests = data?['allowRequests'] ?? false;
              _allowAutoAllotment = data?['allowAutoAllotment'] ?? false;
            } else {
              // Document doesn't exist, create it with default values
              _createDefaultToggleSettings();
            }
          });
        }
      },
      onError: (error) {
        print('Error listening to toggle settings: $error');
        if (mounted) {
          _showSnackBar('Error loading toggle settings: ${error.toString()}', true);
        }
      },
    );
  }

// Create default toggle settings document
  Future<void> _createDefaultToggleSettings() async {
    try {
      await FirebaseFirestore.instance
          .collection('toggle')
          .doc('settings')
          .set({
        'allowRequests': false,
        'allowAutoAllotment': false,

      });
    } catch (e) {
      print('Error creating default toggle settings: $e');
    }
  }

// Save toggle settings to Firestore
  Future<void> _saveToggleSettings() async {
    try {
      await FirebaseFirestore.instance
          .collection('toggle')
          .doc('settings')
          .set({
        'allowRequests': _allowRequests,
        'allowAutoAllotment': _allowAutoAllotment,
      }, SetOptions(merge: true));

      // Optional: Show success message
      if (mounted) {
        _showSnackBar('Settings updated successfully', false);
      }
    } catch (e) {
      print('Error saving toggle settings: $e');
      if (mounted) {
        _showSnackBar('Error saving settings: ${e.toString()}', true);
      }
    }
  }



  void _showSnackBar(String message, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _getRequestTypeDisplayName(String type) {
    switch (type) {
      case 'NewReq':
        return 'New Slot Request';
      case 'TodReq':
        return 'Today Slot Request';
      case 'AltReq':
        return 'Alternative Slot Request';
      default:
        return 'Unknown Request';
    }
  }

  IconData _getRequestTypeIcon(String type) {
    switch (type) {
      case 'NewReq':
        return Icons.add_circle_outline;
      case 'TodReq':
        return Icons.today;
      case 'AltReq':
        return Icons.swap_horiz;
      default:
        return Icons.help_outline;
    }
  }

  Color _getRequestTypeColor(String type) {
    switch (type) {
      case 'NewReq':
        return const Color(0xFF6C5CE7);
      case 'TodReq':
        return const Color(0xFF48BB78);
      case 'AltReq':
        return const Color(0xFFED8936);
      default:
        return const Color(0xFF718096);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use theme-aware background color instead of hardcoded
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        title: const Text('Slots Requests'),
        actions: [
          // Export Button - Responsive based on screen width
          LayoutBuilder(
            builder: (context, constraints) {
              // Get screen width
              final screenWidth = MediaQuery.of(context).size.width;
              final isTablet = screenWidth > 600;
              final isDesktop = screenWidth > 1024;

              return Container(
                margin: EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: isTablet ? 8.0 : 4.0,
                ),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(isDesktop ? 12.0 : 8.0),
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.red[400]!
                            : Colors.red[600]!,
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.red[400]!.withOpacity(0.8)
                            : Colors.red[600]!.withOpacity(0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.red[400]!.withOpacity(0.3)
                            : Colors.red[600]!.withOpacity(0.3),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(isDesktop ? 12.0 : 8.0),
                      onTap: () {
                        // Add your export logic here
                        _handleDeleteAllRequests();
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 20.0 : (isTablet ? 16.0 : 12.0),
                          vertical: isDesktop ? 12.0 : (isTablet ? 10.0 : 8.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: isDesktop ? 20.0 : (isTablet ? 18.0 : 16.0),
                              color: Colors.white, // White icon on red background
                            ),
                            if (screenWidth > 480) // Show text on larger screens
                              Padding(
                                padding: EdgeInsets.only(left: 6.0),
                                child:Text(
                                  'Delete All',
                                  style: TextStyle(
                                    color: Colors.white, // White text on red background
                                    fontSize: isDesktop ? 14.0 : (isTablet ? 13.0 : 12.0),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Refresh Button
          IconButton(
            onPressed: _loadRequests,
            icon: Icon(
              Icons.refresh,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 768;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 1200 : double.infinity,
              ),

              child: RefreshIndicator(
                onRefresh: _handleRefresh, // 👈 ADD THIS
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(context).cardTheme.color,
                displacement: 40,
                strokeWidth: 2.5,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(), // 👈 ADD THIS
                  child: Column(
                    children: [
                      _buildToggleSection(isDesktop),
                      _buildFilterSection(isDesktop),
                      _buildStatsSection(isDesktop),
                      _buildRequestsList(isDesktop),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }




  Widget _buildToggleSection(bool isDesktop) {
    return Container(
      margin: EdgeInsets.all(isDesktop ? 32 : 16),
      padding: EdgeInsets.all(isDesktop ? 32 : 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          width: 0.5,
        )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.settings,
                size: isDesktop ? 24 : 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: 12),
              Text(
                'Request Settings',
                style: TextStyle(
                  fontSize: isDesktop ? 24 : 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          SizedBox(height: isDesktop ? 24 : 20),

          // Toggle Options
          isDesktop ? _buildDesktopToggles() : _buildMobileToggles(),

          // Info text
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Note: Only one option can be enabled at a time',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
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

  Widget _buildDesktopToggles() {
    return Row(
      children: [
        Expanded(
          child: _buildToggleCard(
            title: 'Allow Requests',
            subtitle: 'Users can submit new requests',
            icon: Icons.assignment_turned_in,
            isEnabled: _allowRequests,
            onToggle: (value) => _onToggleChanged('requests', value),
          ),
        ),
        SizedBox(width: 20),
        Expanded(
          child: _buildToggleCard(
            title: 'Auto Available Slot Allotment',
            subtitle: 'Automatically allot available slots for today',
            icon: Icons.auto_awesome,
            isEnabled: _allowAutoAllotment,
            onToggle: (value) => _onToggleChanged('auto', value),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileToggles() {
    return Column(
      children: [
        _buildToggleCard(
          title: 'Allow Requests',
          subtitle: 'Users can submit new requests',
          icon: Icons.assignment_turned_in,
          isEnabled: _allowRequests,
          onToggle: (value) => _onToggleChanged('requests', value),
        ),
        SizedBox(height: 16),
        _buildToggleCard(
          title: 'Auto Free Slot Allotment',
          subtitle: 'Automatically allot available slots for today',
          icon: Icons.auto_awesome,
          isEnabled: _allowAutoAllotment,
          onToggle: (value) => _onToggleChanged('auto', value),
        ),
      ],
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isEnabled,
    required Function(bool) onToggle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E293B),
            const Color(0xFF334155),
            const Color(0xFF1E293B).withOpacity(0.8),
          ],
          stops: const [0.0, 0.6, 1.0],
        )
            : null,
        color: isDark ? null : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
              : Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: isEnabled ? 1.5 : 0.5,
        ),
        boxShadow: [
          if (isEnabled) ...[
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              offset: const Offset(0, 4),
              blurRadius: 12,
              spreadRadius: 0,
            ),
          ],
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            offset: const Offset(0, 2),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Theme.of(context).colorScheme.outline.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isEnabled
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                        : Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  icon,
                  color: isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
              Spacer(),
              Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: isEnabled,
                  onChanged: onToggle,
                  activeColor: Theme.of(context).colorScheme.primary,
                  activeTrackColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  inactiveThumbColor: Theme.of(context).colorScheme.outline,
                  inactiveTrackColor: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isEnabled
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }


  void _onToggleChanged(String type, bool value) async {
    // Show loading state (optional)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Updating settings...'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: Duration(seconds: 1),
        ),
      );
    }

    // Update local state immediately for better UX
    setState(() {
      if (value) {
        // If turning on, turn off the other option
        if (type == 'requests') {
          _allowRequests = true;
          _allowAutoAllotment = false;
        } else if (type == 'auto') {
          _allowAutoAllotment = true;
          _allowRequests = false;
        }
      } else {
        // If turning off, just turn off this option
        if (type == 'requests') {
          _allowRequests = false;
        } else if (type == 'auto') {
          _allowAutoAllotment = false;
        }
      }
    });

    // Save to backend
    await _saveToggleSettings();
  }



  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return; // Prevent multiple simultaneous refreshes

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Show haptic feedback
      HapticFeedback.mediumImpact();

      // Refresh all data in parallel
      await Future.wait([
        _loadRequests(),
        _loadAvailableSlots(),
        _refreshToggleSettings(),
      ]);

      // Small delay for smooth UX
      await Future.delayed(Duration(milliseconds: 300));

      if (mounted) {
        _showSnackBar('✅ All data refreshed', false);
      }
    } catch (e) {
      print('Error during refresh: $e');
      if (mounted) {
        _showSnackBar('❌ Refresh failed: ${e.toString()}', true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _refreshToggleSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('toggle')
          .doc('settings')
          .get();

      if (mounted) {
        setState(() {
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>?;
            _allowRequests = data?['allowRequests'] ?? false;
            _allowAutoAllotment = data?['allowAutoAllotment'] ?? false;
          }
        });
        _showSnackBar('Settings refreshed', false);
      }
    } catch (e) {
      print('Error refreshing toggle settings: $e');
      if (mounted) {
        _showSnackBar('Error refreshing settings: ${e.toString()}', true);
      }
    }
  }



  void _handleDeleteAllRequests() async {
    // Show confirmation dialog first
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete All Requests'),
          content: Text(
            'Are you sure you want to delete all your requests? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.red[300]
                    : Colors.red[600],
              ),
              child: Text('Delete All'),
            ),
          ],
        );
      },
    );

    // If user confirmed deletion
    if (confirmDelete == true) {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Text('Deleting requests...'),
            ],
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.red[400]
              : Colors.red[600],
          duration: Duration(seconds: 3),
        ),
      );

      // Call the delete method
      Map<String, dynamic> result = await _bookingBackend.deleteAllUserRequests();

      // Hide the loading snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Show result message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: result['success']
              ? Colors.green
              : Colors.red,
          duration: Duration(seconds: 3),
        ),
      );

      // If deletion was successful, you might want to refresh the UI
      if (result['success']) {
        _loadRequests();
      }
    }
  }


  Widget _buildFilterSection(bool isDesktop) {
    return Container(
      margin: EdgeInsets.all(isDesktop ? 32 : 16),
      padding: EdgeInsets.all(isDesktop ? 32 : 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color, // Theme-aware card color
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.3) // Darker shadow for dark mode
                : Colors.black.withOpacity(0.05), // Light shadow for light mode
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        // Add subtle border for dark mode
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          width: 0.5,
        )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filter Requests by Type',
                style: TextStyle(
                  fontSize: isDesktop ? 24 : 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface, // Theme-aware text color
                ),
              ),
              if (isDesktop)
                Text(
                  'Total: ${_requests.length} requests',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware secondary text
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          isDesktop ? _buildDesktopChips() : _buildMobileChips(),
        ],
      ),
    );
  }



  Widget _buildDesktopChips() {
    return Wrap(
      spacing: 20,
      runSpacing: 12,
      children: [
        _buildFilterChip('Latest', 'latest'),
        _buildFilterChip('Old', 'old'),
        _buildFilterChip('New Users', 'newUsers'),
      ],
    );
  }

// Replace the _buildMobileChips method:
  Widget _buildMobileChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildFilterChip('Latest', 'latest'),
          const SizedBox(width: 8),
          _buildFilterChip('Old', 'old'),
          const SizedBox(width: 8),
          _buildFilterChip('New Users', 'newUsers'),
        ],
      ),
    );
  }




  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedFilter = value);
        _applyFilter();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C5CE7) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF6C5CE7) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF718096),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
  Widget _buildStatsSection(bool isDesktop) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Latest count - all requests from today
    final latestCount = _requests.where((r) {
      final timestamp = r['data']['timestamp'] as Timestamp?;
      if (timestamp == null) return false;

      final requestDate = timestamp.toDate();
      final requestDay = DateTime(requestDate.year, requestDate.month, requestDate.day);

      return requestDay.isAtSameMomentAs(today);
    }).length;

    // Old count - TodReq and AltReq requests not from today
    final oldCount = _requests.where((r) {
      final type = r['data']['type'];
      if (type != 'TodReq' && type != 'AltReq') return false;

      final timestamp = r['data']['timestamp'] as Timestamp?;
      if (timestamp == null) return false;

      final requestDate = timestamp.toDate();
      final requestDay = DateTime(requestDate.year, requestDate.month, requestDate.day);

      return !requestDay.isAtSameMomentAs(today);
    }).length;

    // New Users count - all NewReq requests
    final newUsersCount = _requests.where((r) => r['data']['type'] == 'NewReq').length;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16),
      child: isDesktop ? _buildDesktopStats(latestCount, oldCount, newUsersCount)
          : _buildMobileStats(latestCount, oldCount, newUsersCount),
    );
  }



  Widget _buildDesktopStats(int latestCount, int oldCount, int newUsersCount) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total',
            _requests.length.toString(),
            Icons.assignment,
            Theme.of(context).colorScheme.primary, // Theme-aware primary color
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildStatCard(
            'Latest',
            latestCount.toString(),
            Icons.today,
            Theme.of(context).colorScheme.secondary, // Theme-aware secondary color
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildStatCard(
            'Old',
            oldCount.toString(),
            Icons.schedule,
            Theme.of(context).colorScheme.tertiary, // Theme-aware tertiary color
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildStatCard(
            'New Users',
            newUsersCount.toString(),
            Icons.add_circle_outline,
            Theme.of(context).colorScheme.primary, // Theme-aware primary color
          ),
        ),
      ],
    );
  }

  Widget _buildMobileStats(int latestCount, int oldCount, int newUsersCount) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total',
                _requests.length.toString(),
                Icons.assignment,
                Theme.of(context).colorScheme.primary, // Theme-aware primary color
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Latest',
                latestCount.toString(),
                Icons.today,
                Theme.of(context).colorScheme.secondary, // Theme-aware secondary color
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Old',
                oldCount.toString(),
                Icons.schedule,
                Theme.of(context).colorScheme.tertiary, // Theme-aware tertiary color
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'New Users',
                newUsersCount.toString(),
                Icons.add_circle_outline,
                Theme.of(context).colorScheme.primary, // Theme-aware primary color
              ),
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildStatCard(String title, String count, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Attractive gradient background for dark mode, solid for light
        gradient: isDark
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E293B), // Dark slate
            const Color(0xFF334155), // Lighter slate
            const Color(0xFF1E293B).withOpacity(0.8), // Subtle variation
          ],
          stops: const [0.0, 0.6, 1.0],
        )
            : null,
        color: isDark ? null : Colors.white,

        borderRadius: BorderRadius.circular(16),

        // Enhanced border with accent color integration
        border: Border.all(
          color: isDark
              ? color.withOpacity(0.3) // More visible accent color border
              : Colors.grey.withOpacity(0.1),
          width: isDark ? 1.2 : 0.5,
        ),

        // Multi-layer shadow system for depth
        boxShadow: [
          // Primary shadow
          BoxShadow(
            color: isDark
                ? color.withOpacity(0.15) // Colored glow effect
                : Colors.grey.withOpacity(0.1),
            offset: const Offset(0, 4),
            blurRadius: isDark ? 16 : 6,
            spreadRadius: 0,
          ),
          // Secondary depth shadow for dark mode
          if (isDark) ...[
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              offset: const Offset(0, 2),
              blurRadius: 8,
              spreadRadius: 0,
            ),
            // Subtle inner glow
            BoxShadow(
              color: color.withOpacity(0.05),
              offset: const Offset(0, 0),
              blurRadius: 20,
              spreadRadius: 0,
            ),
          ],
        ],
      ),
      child: Column(
        children: [
          // Icon with enhanced styling for dark mode
          Container(
            padding: const EdgeInsets.all(8),
            decoration: isDark
                ? BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withOpacity(0.2),
                width: 0.5,
              ),
            )
                : null,
            child: Icon(
              icon,
              color: isDark ? color.withOpacity(0.9) : color,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),

          // Count text with theme-aware styling
          Text(
            count,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? const Color(0xFFF8FAFC) // Bright white for dark mode
                  : const Color(0xFF2D3748), // Keep original for light mode
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),

          // Title text with enhanced contrast
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? const Color(0xFFCBD5E1) // Light grey for dark mode
                  : const Color(0xFF718096), // Keep original for light mode
              fontWeight: isDark ? FontWeight.w500 : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList(bool isDesktop) {
    return Container(
      margin: EdgeInsets.all(isDesktop ? 32 : 16),
      child: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C5CE7)),
        ),
      )
          : _filteredRequests.isEmpty
          ? _buildEmptyState()
          : isDesktop ? _buildDesktopRequestsList() : _buildMobileRequestsList(),
    );
  }



  Widget _buildDesktopRequestsList() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // Changed from 2 to 3
        childAspectRatio: 1.1, // Adjusted aspect ratio
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _filteredRequests.length,
      itemBuilder: (context, index) {
        final request = _filteredRequests[index];
        return _buildRequestCard(request, true);
      },
    );
  }

  Widget _buildMobileRequestsList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredRequests.length,
      itemBuilder: (context, index) {
        final request = _filteredRequests[index];
        return _buildRequestCard(request, false);
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 80,
            color: const Color(0xFF718096).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No requests found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF718096),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFilter == 'all'
                ? 'No requests available'
                : 'No ${_getRequestTypeDisplayName(_selectedFilter).toLowerCase()} available',
            style: TextStyle(
              fontSize: 14,
              color: const Color(0xFF718096).withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }



  Widget _buildRequestCard(Map<String, dynamic> request, bool isDesktop) {
    final requestData = request['data'] as Map<String, dynamic>;
    final requestId = request['id'] as String;
    final status = requestData['status'] ?? 'pending';
    final type = requestData['type'] ?? 'unknown';
    final timestamp = requestData['timestamp'] as Timestamp?;
    final currentSlotId = requestData['currentSlotId'] as String?;
    final vehicleType = requestData['vehicleType'] as String?;

    return Container(
      margin: EdgeInsets.only(bottom: isDesktop ? 0 : 16),
      padding: EdgeInsets.all(isDesktop ? 12 : 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color, // Theme-aware card color
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.3) // Darker shadow for dark mode
                : Colors.black.withOpacity(0.05), // Light shadow for light mode
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        // Add subtle border for dark mode
        border: Theme.of(context).brightness == Brightness.dark
            ? Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
          width: 0.5,
        )
            : null,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getRequestTypeColor(type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getRequestTypeIcon(type),
                    color: _getRequestTypeColor(type),
                    size: isDesktop ? 20 : 24,
                  ),
                ),
                const SizedBox(width: 16),

                Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          getDisplayNameFromEmail(requestData['email'] ?? 'No email'),
                          style: TextStyle(
                            fontSize: isDesktop ? 14 : 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface, // Theme-aware text color
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          requestData['email'] ?? 'No email',
                          style: TextStyle(
                            fontSize: isDesktop ? 12 : 10,
                            color: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware secondary text
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                ),

                _buildRequestTypeBadge(type),
              ],
            ),

            SizedBox(height: isDesktop ? 8 : 16),

            Container(
              padding: EdgeInsets.all(isDesktop ? 12 : 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant, // Theme-aware surface variant
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Request Details',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware text
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (currentSlotId != null) ...[
                    Text(
                      'Current Slot: $currentSlotId',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface, // Theme-aware text
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  const SizedBox(height: 8),

                  if (currentSlotId != null) ...[
                    Text(
                      'Vehicle Type: $vehicleType',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface, // Theme-aware text
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  if (timestamp != null) ...[
                    Text(
                      'Submitted: ${DateFormat('MMM dd, yyyy HH:mm').format(timestamp.toDate())}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware secondary text
                      ),
                    ),
                  ],

                ],
              ),
            ),

            SizedBox(height: isDesktop ? 8 : 16),

            if (_isRequestAllotted(status)) ...[
              // Show allotted status
              _buildAllottedStatus(_getAllottedSlotId(status), isDesktop),
            ] else if (type != 'NewReq') ...[
              if (type == 'TodReq' || type == 'AltReq') ...[
                if (timestamp != null && _isRequestFromToday(timestamp)) ...[
                  // Show action buttons for today's requests
                  isDesktop
                      ? _buildDesktopActionButtons(requestId, vehicleType)
                      : _buildMobileActionButtons(requestId, vehicleType),
                ] else ...[
                  // Show expired status for old requests
                  _buildExpiredStatus(isDesktop),
                ]
              ],
            ],





            // REMOVED the NewReq section that was showing action buttons
            // } else if (type == 'NewReq') ...[
            //   // Always show action buttons for NewReq regardless of date
            //   isDesktop
            //       ? _buildDesktopActionButtons(requestId, vehicleType)
            //       : _buildMobileActionButtons(requestId, vehicleType),
            // ],
          ],
        ),
      ),
    );
  }



  Widget _buildAllottedStatus(String slotId, bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF84CC16),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle,
            color: Color(0xFF16A34A),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Allotted Slot $slotId',
            style: TextStyle(
              fontSize: isDesktop ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF16A34A),
            ),
          ),
        ],
      ),
    );
  }




  bool _isRequestFromToday(Timestamp timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final requestDate = timestamp.toDate();
    final requestDay = DateTime(requestDate.year, requestDate.month, requestDate.day);
    return requestDay.isAtSameMomentAs(today);
  }

  Widget _buildExpiredStatus(bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 8 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFEB2B2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.schedule,
            color: Color(0xFFE53E3E),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            'Expired',
            style: TextStyle(
              fontSize: isDesktop ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFE53E3E),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAvailableSlots() async {
    setState(() {
      _isLoadingSlots = true;
    });

    try {
      final slots = await _bookingBackend.getAvailableSlotsForToday();
      setState(() {
        _availableSlots = slots;
        _isLoadingSlots = false;
      });
    } catch (e) {
      print('Error loading available slots: $e');
      setState(() {
        _isLoadingSlots = false;
      });

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load available slots'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }





  // Method to handle slot selection
  void _onSlotSelected(String requestId, String? slotId) {
    setState(() {
      _selectedSlots[requestId] = slotId;
    });
  }




  Future<void> _allotSlot(String requestId) async {
    final selectedSlotId = _selectedSlots[requestId];

    if (selectedSlotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a slot first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Map<String, dynamic>? request;
    try {
      request = _requests.firstWhere((r) => r['id'] == requestId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final requestData = request['data'] as Map<String, dynamic>;
    final userEmail = requestData['email'] ?? '';
    final userName = getDisplayNameFromEmail(userEmail);
    final vehicleType = requestData['vehicleType'] ?? '';

    // Clear the selected slot immediately to prevent dropdown errors
    setState(() {
      _selectedSlots.remove(requestId);
    });

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()),
      );

      final bookingResult = await _bookingBackend.bookSlotForToday(
        slotId: selectedSlotId,
        vehicleType: vehicleType,
        userEmail: userEmail,
        userName: userName,
      );

      Navigator.of(context).pop(); // Close loading

      if (bookingResult['success'] == true) {
        // Update status with allotted slot ID
        await _updateRequestStatus(requestId, 'allotted-$selectedSlotId');

        // Refresh both slots and requests
        await Future.wait([
          _loadAvailableSlots(),
          _loadRequests(),
        ]);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Slot $selectedSlotId allotted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // If booking failed, we can restore the selection
        setState(() {
          _selectedSlots[requestId] = selectedSlotId;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bookingResult['message'] ?? 'Booking failed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      Navigator.of(context).pop();

      // If there's an error, restore the selection
      setState(() {
        _selectedSlots[requestId] = selectedSlotId;
      });

      print('Error allotting slot: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to allot slot: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }



// Helper method to check if request is allotted
  bool _isRequestAllotted(String status) {
    return status.startsWith('allotted-');
  }

// Helper method to extract slot ID from allotted status
  String _getAllottedSlotId(String status) {
    if (status.startsWith('allotted-')) {
      return status.substring(9); // Remove 'allotted-' prefix
    }
    return '';
  }




  // Method to update request status
// Add this method to update request status in Firestore


  Future<void> _updateRequestStatus(String requestId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({'status': status});
    } catch (e) {
      print('Error updating request status: $e');
      throw e;
    }
  }




  // Method to build slot dropdown items
// Method to build slot dropdown items - UPDATED VERSION
// Method to build slot dropdown items - UPDATED VERSION

  // Method to build slot dropdown items - UPDATED VERSION



  List<DropdownMenuItem<String>> _buildSlotDropdownItems(String? requestVehicleType) {
    if (_isLoadingSlots) {
      return [
        DropdownMenuItem<String>(
          value: null,
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 6),
              const Text(
                'Loading slots...',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF718096),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    // Filter slots based on vehicle type
    final filteredSlots = _availableSlots.where((slot) {
      final slotVehicleType = slot['vehicleType'] as String? ?? 'BIKE';
      return requestVehicleType == null ||
          slotVehicleType.toUpperCase() == requestVehicleType.toUpperCase();
    }).toList();

    if (filteredSlots.isEmpty) {
      return [
        DropdownMenuItem<String>(
          value: null,
          child: Row(
            children: [
              const Icon(
                Icons.warning,
                size: 14,
                color: Color(0xFFE53E3E),
              ),
              const SizedBox(width: 6),
              Text(
                requestVehicleType != null
                    ? 'No ${requestVehicleType.toLowerCase()} slots available'
                    : 'No slots available',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFE53E3E),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return filteredSlots.map((slot) {
      final slotId = slot['slotId'] as String;
      final slotData = slot['slotData'] as Map<String, dynamic>;
      final vehicleType = slot['vehicleType'] as String? ?? 'BIKE';
      final allotedTo = slot['alloted_to'] as List<dynamic>? ?? [];

      // Create display text for the slot
      String displayText = slotId;
      String allotedText = '';
      if (allotedTo.isNotEmpty) {
        allotedText = allotedTo.join(', ');
      }

      return DropdownMenuItem<String>(
        value: slotId,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                vehicleType == 'CAR' ? Icons.directions_car : Icons.motorcycle,
                size: 14,
                color: vehicleType == 'CAR' ? Color(0xFF4299E1) : Color(0xFF48BB78),
              ),
              const SizedBox(width: 8),

              Expanded(

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayText,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,

                    ),


                    if (allotedTo.isNotEmpty) ...[
                      const SizedBox(height: 2),

                      Text(
                        'Alloted to: $allotedText',
                        style:  TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        softWrap: true,

                        overflow: TextOverflow.ellipsis,
                      ),
                    ],


                  ],
                ),
              ),


            ],
          ),
        ),
      );
    }).toList();
  }



// Updated _buildDesktopActionButtons method

  Widget _buildDesktopActionButtons(String requestId, String? vehicleType) {
    final selectedSlotId = _selectedSlots[requestId];
    final isSlotSelected = selectedSlotId != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant, // Theme-aware surface variant
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3), // Theme-aware border
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Allot Available Slot (Today) - ${vehicleType ?? 'Unknown'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface, // Theme-aware text
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadAvailableSlots,
                icon: Icon(
                  Icons.refresh,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface, // Theme-aware icon
                ),
                tooltip: 'Refresh slots',
                constraints: BoxConstraints(maxWidth: 24, maxHeight: 24),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface, // Theme-aware surface
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3), // Theme-aware border
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                hint: Text(
                  'Select a ${vehicleType?.toLowerCase() ?? 'vehicle'} slot',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware hint text
                  ),
                ),
                value: selectedSlotId,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  color: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware icon
                  size: 18,
                ),
                isExpanded: true,
                isDense: true,
                items: _buildSlotDropdownItems(vehicleType),
                selectedItemBuilder: (BuildContext context) {
                  return _buildSlotDropdownItems(vehicleType).map((item) {
                    return _buildSelectedSlotDisplay(item.value, vehicleType);
                  }).toList();
                },
                onChanged: (String? newValue) {
                  _onSlotSelected(requestId, newValue);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isSlotSelected && !_isLoadingSlots ? () => _allotSlot(requestId) : null,
                  icon: const Icon(Icons.schedule, size: 16),
                  label: const Text(
                    'Allot Slot',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary, // Theme-aware primary
                    foregroundColor: Theme.of(context).colorScheme.onPrimary, // Theme-aware text on primary
                    disabledBackgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.2), // Theme-aware disabled
                    disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware disabled text
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }

// Updated _buildSelectedSlotDisplay method
  Widget _buildSelectedSlotDisplay(String? selectedSlotId, String? vehicleType) {
    if (selectedSlotId == null) return const SizedBox.shrink();

    // Find the selected slot from available slots
    final selectedSlot = _availableSlots.firstWhere(
          (slot) => slot['slotId'] == selectedSlotId,
      orElse: () => {},
    );

    if (selectedSlot.isEmpty) {
      return Text(
        selectedSlotId,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface, // Theme-aware text
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }

    final slotVehicleType = selectedSlot['vehicleType'] as String? ?? 'BIKE';
    final allotedTo = selectedSlot['alloted_to'] as List<dynamic>? ?? [];

    return Row(
      children: [
        Icon(
          slotVehicleType == 'CAR' ? Icons.directions_car : Icons.motorcycle,
          size: 14,
          color: slotVehicleType == 'CAR'
              ? Theme.of(context).colorScheme.primary // Theme-aware primary for cars
              : Theme.of(context).colorScheme.secondary, // Theme-aware secondary for bikes
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            selectedSlotId,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface, // Theme-aware text
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

// Updated _buildMobileActionButtons method
  Widget _buildMobileActionButtons(String requestId, String? vehicleType) {
    final selectedSlotId = _selectedSlots[requestId];
    final isSlotSelected = selectedSlotId != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant, // Theme-aware surface variant
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3), // Theme-aware border
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Allot Available Slot (Today) - ${vehicleType ?? 'Unknown'}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface, // Theme-aware text
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadAvailableSlots,
                icon: Icon(
                  Icons.refresh,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface, // Theme-aware icon
                ),
                tooltip: 'Refresh slots',
                constraints: BoxConstraints(maxWidth: 32, maxHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface, // Theme-aware surface
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3), // Theme-aware border
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                hint: Text(
                  'Select a ${vehicleType?.toLowerCase() ?? 'vehicle'} slot',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware hint text
                  ),
                ),
                value: selectedSlotId,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  color: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware icon
                ),
                isExpanded: true,
                items: _buildSlotDropdownItems(vehicleType),
                selectedItemBuilder: (BuildContext context) {
                  return _buildSlotDropdownItems(vehicleType).map((item) {
                    return _buildSelectedSlotDisplay(item.value, vehicleType);
                  }).toList();
                },
                onChanged: (String? newValue) {
                  _onSlotSelected(requestId, newValue);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isSlotSelected && !_isLoadingSlots ? () => _allotSlot(requestId) : null,
              icon: const Icon(Icons.schedule),
              label: const Text('Allot Slot'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary, // Theme-aware primary
                foregroundColor: Theme.of(context).colorScheme.onPrimary, // Theme-aware text on primary
                disabledBackgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.2), // Theme-aware disabled
                disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant, // Theme-aware disabled text
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }


// Replace the _buildStatusBadge method with this:
  Widget _buildRequestTypeBadge(String type) {
    String displayText;
    Color backgroundColor;
    Color textColor = Colors.white;
    IconData icon;

    switch (type) {
      case 'NewReq':
        displayText = 'New Slot';
        backgroundColor = const Color(0xFF6C5CE7);
        icon = Icons.add_circle_outline;
        break;
      case 'TodReq':
        displayText = 'Own Slot';
        backgroundColor = const Color(0xFF48BB78);
        icon = Icons.today;
        break;
      case 'AltReq':
        displayText = 'Alternate Slot';
        backgroundColor = const Color(0xFFED8936);
        icon = Icons.swap_horiz;
        break;
      default:
        displayText = 'Unknown';
        backgroundColor = const Color(0xFF718096);
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 16),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }




}