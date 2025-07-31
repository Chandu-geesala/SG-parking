import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:park_sg/view/admin/slots.dart';
import 'package:park_sg/viewModel/users_backend.dart';

class AllUsersPage extends StatefulWidget {
  const AllUsersPage({Key? key}) : super(key: key);

  @override
  State<AllUsersPage> createState() => _AllUsersPageState();
}

class _AllUsersPageState extends State<AllUsersPage> {

  // ============================================================================
  // CORE DEPENDENCIES & VARIABLES
  // ============================================================================

  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // User form controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // State variables
  String _searchQuery = '';
  String _selectedFilter = 'all';
  String _selectedUserType = 'user';
  bool _isAddingUser = false;
  bool _sendResetEmail = true;

  // Firebase optimization variables
  static const Duration _cacheExpiry = Duration(minutes: 5);
  Map<String, bool> _slotAllocationCache = {};
  Map<String, List<Map<String, dynamic>>> _userSlotsCache = {};
  Map<String, List<Map<String, dynamic>>> _userBookingsCache = {};
  Map<String, int> _totalBookingsCache = {};
  DateTime? _lastCacheUpdate;

  // Batch processing for performance
  Map<String, Map<String, dynamic>>? _allSlots;
  bool _isLoadingSlots = false;

  // Responsive design helpers
  bool get isWeb => MediaQuery.of(context).size.width > 800;
  double get maxWidth => isWeb ? 1200 : double.infinity;

  // ============================================================================
  // LIFECYCLE METHODS
  // ============================================================================

  @override
  void initState() {
    super.initState();
    _setupSearchListener();
    _preloadSlotsData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ============================================================================
  // INITIALIZATION METHODS
  // ============================================================================

  /// Setup search text field listener
  void _setupSearchListener() {
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  // ============================================================================
  // FIREBASE OPTIMIZATION METHODS (COST REDUCTION)
  // ============================================================================

  /// Preload all slots data once and cache it to reduce Firebase reads
  /// This significantly reduces costs by batching reads and using cache
  Future<void> _preloadSlotsData() async {
    if (_isLoadingSlots) return;

    setState(() => _isLoadingSlots = true);

    try {
      // OPTIMIZATION: Try cache first to avoid unnecessary server reads
      QuerySnapshot slotsQuery;
      try {
        slotsQuery = await _firestore
            .collection('Slots')
            .get(const GetOptions(source: Source.cache));
      } catch (e) {
        // Fallback to server only if cache fails
        slotsQuery = await _firestore.collection('Slots').get();
      }

      _processSlotData(slotsQuery.docs);
    } catch (e) {
      print('Error preloading slots: $e');
    } finally {
      setState(() => _isLoadingSlots = false);
    }
  }

  /// Process slot data and build cache for efficient lookups
  void _processSlotData(List<QueryDocumentSnapshot> slotDocs) {
    _allSlots = {};
    _slotAllocationCache.clear();
    _userSlotsCache.clear();

    for (var slotDoc in slotDocs) {
      final slotData = slotDoc.data() as Map<String, dynamic>;
      _allSlots![slotDoc.id] = slotData;

      final allotedTo = slotData['alloted_to'] as List<dynamic>?;
      if (allotedTo != null) {
        for (var allocation in allotedTo) {
          final userEmail = allocation['email'];
          if (userEmail != null) {
            // Cache slot allocation status for instant lookup
            _slotAllocationCache[userEmail] = true;

            // Cache user slots for detailed view
            if (!_userSlotsCache.containsKey(userEmail)) {
              _userSlotsCache[userEmail] = [];
            }
            _userSlotsCache[userEmail]!.add({
              'slotId': slotDoc.id,
              'vehicleType': slotData['vehicleType'],
              'slotPriority': slotData['slotPriority'],
              'vehicleCompatibility': slotData['VehicleCompatibility'],
              'allotedDate': allocation['alloted_date'],
              'allotedName': allocation['name'],
            });
          }
        }
      }
    }
    _lastCacheUpdate = DateTime.now();
  }

  /// Get user bookings with aggressive caching to minimize reads
  Future<List<Map<String, dynamic>>> _getUserBookings(String userEmail, DateTime month) async {
    final cacheKey = '${userEmail}_${month.year}_${month.month}';

    // Return cached data if available
    if (_userBookingsCache.containsKey(cacheKey)) {
      return _userBookingsCache[cacheKey]!;
    }

    try {
      List<Map<String, dynamic>> userBookings = [];
      final firstDay = DateTime(month.year, month.month, 1);
      final lastDay = DateTime(month.year, month.month + 1, 0);

      // OPTIMIZATION: Use concurrent batch reads for better performance
      List<Future<QuerySnapshot>> bookingFutures = [];

      for (int day = firstDay.day; day <= lastDay.day; day++) {
        final dateKey = DateFormat('yyyy-MM-dd').format(DateTime(month.year, month.month, day));

        // Try cache first, fallback to server
        bookingFutures.add(
            _firestore
                .collection('Bookings')
                .doc(dateKey)
                .collection('BookedToday')
                .where('bookedBy', isEqualTo: userEmail)
                .get(const GetOptions(source: Source.cache))
                .catchError((_) => _firestore
                .collection('Bookings')
                .doc(dateKey)
                .collection('BookedToday')
                .where('bookedBy', isEqualTo: userEmail)
                .get())
        );
      }

      // Execute all queries concurrently to reduce total time
      final results = await Future.wait(bookingFutures);

      for (int i = 0; i < results.length; i++) {
        final snapshot = results[i];
        final dateKey = DateFormat('yyyy-MM-dd').format(
            DateTime(month.year, month.month, firstDay.day + i)
        );

        for (var bookingDoc in snapshot.docs) {
          final bookingData = bookingDoc.data() as Map<String, dynamic>;
          userBookings.add({
            'slotId': bookingData['slotId'],
            'bookedBy': bookingData['bookedBy'],
            'userName': bookingData['userName'],
            'vehicleType': bookingData['vehicleType'],
            'bookingDate': bookingData['bookingDate'],
            'dateKey': dateKey,
          });
        }
      }

      // Cache the results to avoid future reads
      _userBookingsCache[cacheKey] = userBookings;
      return userBookings;
    } catch (e) {
      print('Error getting user bookings: $e');
      return [];
    }
  }

  /// Get total user bookings with caching (limited to current year for cost efficiency)
  Future<int> _getTotalUserBookings(String userEmail) async {
    if (_totalBookingsCache.containsKey(userEmail)) {
      return _totalBookingsCache[userEmail]!;
    }

    try {
      // OPTIMIZATION: Limit to current year only to reduce reads
      final now = DateTime.now();
      int totalBookings = 0;

      // Process monthly chunks to balance performance and cost
      for (var month = 1; month <= now.month; month++) {
        final monthBookings = await _getUserBookings(userEmail, DateTime(now.year, month, 1));
        totalBookings += monthBookings.length;
      }

      _totalBookingsCache[userEmail] = totalBookings;
      return totalBookings;
    } catch (e) {
      print('Error getting total bookings: $e');
      return 0;
    }
  }

  /// Refresh cache if expired to maintain data freshness
  void _refreshCacheIfNeeded() {
    if (_lastCacheUpdate == null ||
        DateTime.now().difference(_lastCacheUpdate!) > _cacheExpiry) {
      _preloadSlotsData();
    }
  }

  /// Batch delete user from all slots to minimize writes
  Future<void> _removeUserFromAllSlots(String userEmail) async {
    try {
      final slotsSnapshot = await _firestore.collection('Slots').get();
      final batch = _firestore.batch();
      bool hasUpdates = false;

      for (var slotDoc in slotsSnapshot.docs) {
        final slotData = slotDoc.data();
        final allotedTo = slotData['alloted_to'] as List<dynamic>?;

        if (allotedTo != null) {
          final updatedAllotedTo = allotedTo
              .where((allocation) => allocation['email'] != userEmail)
              .toList();

          // Only update if there was a change
          if (updatedAllotedTo.length != allotedTo.length) {
            batch.update(slotDoc.reference, {
              'alloted_to': updatedAllotedTo,
            });
            hasUpdates = true;
          }
        }
      }

      // OPTIMIZATION: Use batch commit for multiple updates
      if (hasUpdates) {
        await batch.commit();
        print('✅ User removed from all allocated slots');
      }
    } catch (e) {
      print('Error removing user from slots: $e');
    }
  }

  // ============================================================================
  // DATA ACCESS METHODS (USING CACHE)
  // ============================================================================

  /// Check if user has allocated slot using cache
  bool _isUserSlotAllocated(String userEmail) {
    _refreshCacheIfNeeded();
    return _slotAllocationCache[userEmail] ?? false;
  }

  /// Get user allocated slots from cache
  List<Map<String, dynamic>> _getUserAllocatedSlots(String userEmail) {
    _refreshCacheIfNeeded();
    return _userSlotsCache[userEmail] ?? [];
  }

  // ============================================================================
  // FILTERING & SEARCH METHODS
  // ============================================================================

  /// Filter users synchronously using cached data
  List<QueryDocumentSnapshot> _filterUsersSync(List<QueryDocumentSnapshot> users) {
    return users.where((doc) {
      final userData = doc.data() as Map<String, dynamic>;
      final userEmail = doc.id;
      return _matchesSearch(userData) && _matchesFilter(userData, userEmail);
    }).toList();
  }

  /// Check if user matches current filter
  bool _matchesFilter(Map<String, dynamic> user, String userEmail) {
    switch (_selectedFilter) {
      case 'alloted':
        return _isUserSlotAllocated(userEmail);
      case 'unalloted':
        return !_isUserSlotAllocated(userEmail);
      default:
        return true;
    }
  }

  /// Check if user matches search query
  bool _matchesSearch(Map<String, dynamic> user) {
    if (_searchQuery.isEmpty) return true;

    final name = (user['name'] ?? '').toString().toLowerCase();
    final email = (user['email'] ?? '').toString().toLowerCase();
    final phone = (user['phone'] ?? '').toString().toLowerCase();

    return name.contains(_searchQuery) ||
        email.contains(_searchQuery) ||
        phone.contains(_searchQuery);
  }

  // ============================================================================
  // USER MANAGEMENT METHODS
  // ============================================================================

  /// Handle adding new user with Firebase Auth processing
  Future<void> _handleAddUser(StateSetter setModalState) async {
    if (_emailController.text.trim().isEmpty) {
      _showMessage('Email is required', isError: true);
      return;
    }

    setModalState(() => _isAddingUser = true);

    try {
      final userService = UserUploadService();
      final email = _emailController.text.trim();

      // Create user data
      final userData = {
        'name': userService.extractNameFromEmail(email),
        'email': email,
        'userType': _selectedUserType,
        'emailVerified': true,
        'createdAt': FieldValue.serverTimestamp(),
        'platform': 'manual_add',
      };

      // Add optional fields
      if (_phoneController.text.trim().isNotEmpty) {
        userData['phone'] = _phoneController.text.trim();
      }

      // Add user to Firestore
      await _firestore.collection('users').doc(email).set(userData);

      // Close the sheet
      Navigator.pop(context);

      // Process Firebase Auth and email if requested
      String emailMessage = '';
      if (_sendResetEmail) {
        final result = await userService.processSingleUserEmail(email);

        if (result['success']) {
          switch (result['action']) {
            case 'existing_user':
              emailMessage = ' (User already has Firebase account - no action needed)';
              break;
            case 'new_user_created':
              emailMessage = ' Firebase account created & password reset email sent!';
              break;
          }
        } else {
          emailMessage = ' (Failed to process Firebase Auth: ${result['message']})';
        }
      }

      // Clear form
      _clearAddUserForm();
      _showMessage('User added successfully!$emailMessage', isError: false);

      // Refresh cache
      _preloadSlotsData();
    } catch (e) {
      print('❌ Error adding user: $e');
      _showMessage('Failed to add user: $e', isError: true);
    } finally {
      setModalState(() => _isAddingUser = false);
    }
  }

  /// Delete user with confirmation
  Future<void> _deleteUser(String userEmail, String userName) async {
    try {
      _showMessage('Deleting user...', isError: false);

      // Delete user from Firestore
      await _firestore.collection('users').doc(userEmail).delete();

      // Remove user from all allocated slots
      await _removeUserFromAllSlots(userEmail);

      // Close the user details sheet
      Navigator.of(context).pop();

      _showMessage('User "$userName" deleted successfully', isError: false);

      // Refresh data
      _preloadSlotsData();
      setState(() {});
    } catch (e) {
      print('Error deleting user: $e');
      _showMessage('Failed to delete user: $e', isError: true);
    }
  }

  /// Clear add user form
  void _clearAddUserForm() {
    _emailController.clear();
    _phoneController.clear();
    _selectedUserType = 'user';
    _sendResetEmail = true;
  }

  // ============================================================================
  // NAVIGATION METHODS
  // ============================================================================

  /// Navigate to slots page with user email search
  void _navigateToSlotsPageWithSearch(String email) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ParkingSlotsPage(
          initialSearch: email,
        ),
      ),
    );
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Format date from various timestamp formats
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';

    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is String) {
      date = DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      return 'N/A';
    }

    return DateFormat('MMM dd, yyyy').format(date);
  }

  /// Show success or error message
  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ============================================================================
  // DIALOG METHODS
  // ============================================================================

  /// Show delete confirmation dialog
  Future<void> _showDeleteConfirmation(String userEmail, String userName) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade600,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Delete User',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete this user?',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 16,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete, size: 16),
                  SizedBox(width: 4),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      await _deleteUser(userEmail, userName);
    }
  }

  /// Show add user bottom sheet
  void _showAddUserBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Add New User',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildAddUserForm(isDark, setModalState),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show user details bottom sheet or dialog
  void _showUserBottomSheet(Map<String, dynamic> user, String userEmail) {
    if (isWeb) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: Container(
            width: 800,
            height: 600,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'User Information',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
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
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildUserDetailsSection(user, userEmail),
                        const SizedBox(height: 24),
                        _buildSlotDetailsSection(user, userEmail),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildUserDetailsSection(user, userEmail),
                          const SizedBox(height: 24),
                          _buildSlotDetailsSection(user, userEmail),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
  }

  // ============================================================================
  // UI BUILDING METHODS
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: Center(
        child: Container(
          width: maxWidth,
          child: Column(
            children: [
              _buildSearchAndFilterSection(isDark, colorScheme),
              _buildUsersList(isDark, colorScheme),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildAddUserFAB(),
    );
  }

  /// Build app bar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        'All Users',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: const Color(0xFF6C5CE7),
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  /// Build search and filter section
  Widget _buildSearchAndFilterSection(bool isDark, ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.all(isWeb ? 24 : 16),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E1E2E),
            Color(0xFF2A2A3A),
            Color(0xFF1A1A2E),
          ],
        )
            : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFF6C5CE7).withOpacity(0.02),
            Colors.white,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0xFF6C5CE7).withOpacity(0.1)
                : colorScheme.shadow.withOpacity(0.08),
            blurRadius: isDark ? 15 : 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: isDark
            ? Border.all(
          color: const Color(0xFF6C5CE7).withOpacity(0.2),
          width: 1,
        )
            : null,
      ),
      child: Column(
        children: [
          _buildSearchBar(isDark, colorScheme),
          const SizedBox(height: 16),
          _buildFilterChips(),
        ],
      ),
    );
  }

  /// Build search bar
  Widget _buildSearchBar(bool isDark, ColorScheme colorScheme) {
    return Container(
      width: isWeb ? 600 : double.infinity,
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          color: isDark ? Colors.white : colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Search users by name, email, or phone...',
          hintStyle: TextStyle(
            color: isDark
                ? Colors.white.withOpacity(0.6)
                : colorScheme.onSurface.withOpacity(0.6),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: isDark
                ? const Color(0xFF6C5CE7).withOpacity(0.8)
                : const Color(0xFF6C5CE7),
          ),
          filled: true,
          fillColor: isDark
              ? const Color(0xFF2A2A3A).withOpacity(0.8)
              : Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: isDark
                ? BorderSide(
              color: const Color(0xFF6C5CE7).withOpacity(0.3),
              width: 1,
            )
                : BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: isDark
                ? BorderSide(
              color: const Color(0xFF6C5CE7).withOpacity(0.3),
              width: 1,
            )
                : BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF6C5CE7),
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  /// Build filter chips
  Widget _buildFilterChips() {
    return isWeb
        ? Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildFilterChip('All', 'all'),
        const SizedBox(width: 8),
        _buildFilterChip('Alloted', 'alloted'),
        const SizedBox(width: 8),
        _buildFilterChip('Unalloted', 'unalloted'),
      ],
    )
        : SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('All', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('Alloted', 'alloted'),
          const SizedBox(width: 8),
          _buildFilterChip('Unalloted', 'unalloted'),
        ],
      ),
    );
  }

  /// Build individual filter chip
  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C5CE7) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF6C5CE7) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// Build users list with StreamBuilder
  Widget _buildUsersList(bool isDark, ColorScheme colorScheme) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D1117) : Colors.grey.shade50,
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('users').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState(isDark, colorScheme, snapshot.error.toString());
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingState(isDark);
            }

            final users = snapshot.data?.docs ?? [];

            if (users.isEmpty) {
              return _buildEmptyState(isDark, colorScheme, 'No users found');
            }

            final filteredUsers = _filterUsersSync(users);

            if (filteredUsers.isEmpty) {
              return _buildEmptyState(isDark, colorScheme, 'No users match your search criteria');
            }

            return _buildUsersGrid(filteredUsers);
          },
        ),
      ),
    );
  }

  /// Build error state
  Widget _buildErrorState(bool isDark, ColorScheme colorScheme, String error) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.red.withOpacity(0.1)
                  : colorScheme.shadow.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: isDark ? Colors.red.shade400 : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error: $error',
              style: TextStyle(
                color: isDark ? Colors.white : colorScheme.onSurface,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Build loading state
  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C5CE7)),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading users...',
            style: TextStyle(
              color: isDark ? Colors.white.withOpacity(0.7) : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  /// Build empty state
  Widget _buildEmptyState(bool isDark, ColorScheme colorScheme, String message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? const Color(0xFF6C5CE7).withOpacity(0.1)
                  : colorScheme.shadow.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: isDark
                  ? const Color(0xFF6C5CE7).withOpacity(0.8)
                  : const Color(0xFF6C5CE7),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: isDark ? Colors.white : colorScheme.onSurface,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Build users grid or list based on screen size
  Widget _buildUsersGrid(List<QueryDocumentSnapshot> filteredUsers) {
    return isWeb
        ? GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 3 : 2,
        childAspectRatio: 4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final doc = filteredUsers[index];
        final userData = doc.data() as Map<String, dynamic>;
        return _buildUserCard(userData, doc.id);
      },
    )
        : ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final doc = filteredUsers[index];
        final userData = doc.data() as Map<String, dynamic>;
        return _buildUserCard(userData, doc.id);
      },
    );
  }

  /// Build individual user card
  Widget _buildUserCard(Map<String, dynamic> user, String userEmail) {
    final isAlloted = _isUserSlotAllocated(userEmail);

    return Container(
      margin: EdgeInsets.only(bottom: isWeb ? 0 : 12),
      padding: EdgeInsets.all(isWeb ? 20 : 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showUserBottomSheet(user, userEmail),
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            children: [
              CircleAvatar(
                radius: isWeb ? 28 : 24,
                backgroundColor: isAlloted
                    ? Colors.green.withOpacity(0.15)
                    : Theme.of(context).colorScheme.surfaceVariant,
                child: Icon(
                  Icons.person,
                  color: isAlloted
                      ? Colors.green
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: isWeb ? 28 : 24,
                ),
              ),
              SizedBox(width: isWeb ? 16 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user['name'] ?? 'No Name',
                      style: TextStyle(
                        fontSize: isWeb ? 18 : 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userEmail,
                      style: TextStyle(
                        fontSize: isWeb ? 16 : 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isWeb ? 12 : 8,
                  vertical: isWeb ? 6 : 4,
                ),
                decoration: BoxDecoration(
                  color: isAlloted
                      ? Colors.green.withOpacity(0.15)
                      : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isAlloted ? 'Alloted' : 'Unalloted',
                  style: TextStyle(
                    color: isAlloted
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    fontSize: isWeb ? 12 : 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build user details section
  Widget _buildUserDetailsSection(Map<String, dynamic> user, String userEmail) {
    final vehicles = user['vehicles'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'User Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            IconButton(
              onPressed: () => _showDeleteConfirmation(userEmail, user['name'] ?? 'Unknown User'),
              icon: Icon(
                Icons.delete_outline,
                color: Colors.red.shade600,
                size: 24,
              ),
              tooltip: 'Delete User',
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              _buildDetailRow('Name', user['name'] ?? 'N/A'),
              _buildDetailRow('Email', userEmail),
              _buildDetailRow('Phone', user['phone'] ?? 'N/A'),
              _buildDetailRow('User Type', user['userType'] ?? 'N/A'),
              _buildDetailRow('Email Verified', user['emailVerified'] == true ? 'Yes' : 'No'),
              _buildDetailRow('Joined', _formatDate(user['createdAt'])),
              _buildUserVehiclesSection(vehicles),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserVehiclesSection(List<dynamic> vehicles) {
    if (vehicles.isEmpty) {
      return Text(
        'No vehicles added',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Colors.grey,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vehicles',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        ...vehicles.map((vehicle) {
          final Map<String, dynamic> v = vehicle as Map<String, dynamic>;
          final vehicleNumber = (v['number'] ?? '').toString().toUpperCase();
          final dimensions = v['dimensions']?.toString() ?? 'Size N/A';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.directions_car_rounded,
                  size: 20,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicleNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Size: $dimensions',
                        style: const TextStyle(
                          fontSize: 14,

                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }




  /// Build slot details section using cached data
  Widget _buildSlotDetailsSection(Map<String, dynamic> user, String userEmail) {
    final userSlots = _getUserAllocatedSlots(userEmail);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Slot Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            if (userSlots.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextButton.icon(
                  onPressed: () => _navigateToSlotsPageWithSearch(userEmail),
                  icon: Icon(Icons.open_in_new, size: 16, color: Theme.of(context).colorScheme.primary),
                  label: const Text(
                    'View More',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: userSlots.isNotEmpty ? Column(
            children: userSlots.map((slot) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildDetailRow('Slot ID', slot['slotId']),
                  _buildDetailRow('Vehicle Type', slot['vehicleType']),
                  _buildDetailRow('Priority', slot['slotPriority']),
                  if (slot['vehicleCompatibility'] != null)
                    _buildDetailRow('Compatibility', slot['vehicleCompatibility']),
                  _buildDetailRow('Alloted Date', _formatDate(slot['allotedDate'])),
                  _buildDetailRow('Status', 'Active'),
                ],
              ),
            )).toList(),
          ) : Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No slots allocated to this user',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build detail row for user information
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build add user form
  Widget _buildAddUserForm(bool isDark, StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFormField(
          'Email *',
          _emailController,
          'Enter email address',
          Icons.email,
          isDark,
        ),
        const SizedBox(height: 16),
        _buildFormField(
          'Phone',
          _phoneController,
          'Enter phone number',
          Icons.phone,
          isDark,
        ),
        const SizedBox(height: 16),
        _buildUserTypeDropdown(isDark, setModalState),
        const SizedBox(height: 16),
        _buildResetEmailSwitch(isDark, setModalState),
        const SizedBox(height: 32),
        _buildAddButton(setModalState),
        const SizedBox(height: 20),
      ],
    );
  }

  /// Build form field
  Widget _buildFormField(
      String label,
      TextEditingController controller,
      String hint,
      IconData icon,
      bool isDark,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white.withOpacity(0.6) : Colors.grey,
            ),
            prefixIcon: Icon(
              icon,
              color: const Color(0xFF6C5CE7),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF2A2A3A) : Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: isDark
                  ? BorderSide(color: const Color(0xFF6C5CE7).withOpacity(0.3))
                  : BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: isDark
                  ? BorderSide(color: const Color(0xFF6C5CE7).withOpacity(0.3))
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  /// Build user type dropdown
  Widget _buildUserTypeDropdown(bool isDark, StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'User Type',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A3A) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF6C5CE7).withOpacity(0.3) : Colors.grey.shade300,
            ),
          ),
          child: DropdownButtonFormField<String>(
            value: _selectedUserType,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            dropdownColor: isDark ? const Color(0xFF2A2A3A) : Colors.white,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            items: const [
              DropdownMenuItem(value: 'user', child: Text('User')),
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
            ],
            onChanged: (value) {
              setModalState(() {
                _selectedUserType = value!;
              });
            },
          ),
        ),
      ],
    );
  }

  /// Build reset email switch
  Widget _buildResetEmailSwitch(bool isDark, StateSetter setModalState) {
    return Row(
      children: [
        Switch(
          value: _sendResetEmail,
          onChanged: (value) {
            setModalState(() {
              _sendResetEmail = value;
            });
          },
          activeColor: const Color(0xFF6C5CE7),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Send password reset email',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  /// Build add button
  Widget _buildAddButton(StateSetter setModalState) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isAddingUser ? null : () => _handleAddUser(setModalState),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C5CE7),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isAddingUser
            ? const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 8),
            Text('Adding User...'),
          ],
        )
            : const Text(
          'Add User',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Build floating action button
  Widget _buildAddUserFAB() {
    return FloatingActionButton.extended(
      onPressed: _showAddUserBottomSheet,
      backgroundColor: const Color(0xFF6C5CE7),
      foregroundColor: Colors.white,
      elevation: 6,
      icon: Icon(Icons.person_add, size: isWeb ? 24 : 20),
      label: Text(
        'Add User',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: isWeb ? 16 : 14,
        ),
      ),
    );
  }
}
