import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:park_sg/viewModel/users_backend.dart';

class AllUsersPage extends StatefulWidget {
  const AllUsersPage({Key? key}) : super(key: key);

  @override
  State<AllUsersPage> createState() => _AllUsersPageState();
}

class _AllUsersPageState extends State<AllUsersPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _searchQuery = '';
  String _selectedFilter = 'all';
  DateTime _selectedMonth = DateTime.now();
  bool _isUploading = false;
  String _uploadStatus = '';

  // Add User Form Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  String _selectedUserType = 'user';
  bool _isAddingUser = false;
  bool _sendResetEmail = true;




  // Caching variables
  Map<String, bool> _slotAllocationCache = {};
  Map<String, List<Map<String, dynamic>>> _userSlotsCache = {};
  Map<String, List<Map<String, dynamic>>> _userBookingsCache = {};
  Map<String, int> _totalBookingsCache = {};
  DateTime? _lastCacheUpdate;
  static const Duration _cacheExpiry = Duration(minutes: 5);

  // Batch processing
  List<QueryDocumentSnapshot>? _allUsers;
  Map<String, Map<String, dynamic>>? _allSlots;
  bool _isLoadingSlots = false;

  bool get isWeb => MediaQuery.of(context).size.width > 800;
  double get maxWidth => isWeb ? 1200 : double.infinity;




  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _preloadSlotsData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }


  // OPTIMIZATION 1: Preload all slots data once and cache it
  Future<void> _preloadSlotsData() async {
    if (_isLoadingSlots) return;

    setState(() {
      _isLoadingSlots = true;
    });

    try {
      // Single query to get all slots
      final slotsQuery = await _firestore
          .collection('Slots')
          .get(const GetOptions(source: Source.cache)); // Try cache first

      _allSlots = {};
      _slotAllocationCache.clear();
      _userSlotsCache.clear();

      for (var slotDoc in slotsQuery.docs) {
        final slotData = slotDoc.data();
        _allSlots![slotDoc.id] = slotData;

        final allotedTo = slotData['alloted_to'] as List<dynamic>?;
        if (allotedTo != null) {
          for (var allocation in allotedTo) {
            final userEmail = allocation['email'];
            if (userEmail != null) {
              // Cache slot allocation status
              _slotAllocationCache[userEmail] = true;

              // Cache user slots
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
    } catch (e) {
      print('Error preloading slots: $e');
      // Fallback to server if cache fails
      try {
        final slotsQuery = await _firestore.collection('Slots').get();
        // Process the same way as above
        _processSlotData(slotsQuery.docs);
      } catch (serverError) {
        print('Error loading from server: $serverError');
      }
    } finally {
      setState(() {
        _isLoadingSlots = false;
      });
    }
  }





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
            _slotAllocationCache[userEmail] = true;

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




  List<QueryDocumentSnapshot> _filterUsersSync(List<QueryDocumentSnapshot> users) {
    return users.where((doc) {
      final userData = doc.data() as Map<String, dynamic>;
      final userEmail = doc.id;

      return _matchesSearch(userData) && _matchesFilter(userData, userEmail);
    }).toList();
  }



  bool _isUserSlotAllocated(String userEmail) {
    _refreshCacheIfNeeded();
    return _slotAllocationCache[userEmail] ?? false;
  }



  List<Map<String, dynamic>> _getUserAllocatedSlots(String userEmail) {
    _refreshCacheIfNeeded();
    return _userSlotsCache[userEmail] ?? [];
  }

  void _refreshCacheIfNeeded() {
    if (_lastCacheUpdate == null ||
        DateTime.now().difference(_lastCacheUpdate!) > _cacheExpiry) {
      _preloadSlotsData();
    }
  }



  Future<List<Map<String, dynamic>>> _getUserBookings(String userEmail, DateTime month) async {
    final cacheKey = '${userEmail}_${month.year}_${month.month}';

    if (_userBookingsCache.containsKey(cacheKey)) {
      return _userBookingsCache[cacheKey]!;
    }

    try {
      List<Map<String, dynamic>> userBookings = [];
      final firstDay = DateTime(month.year, month.month, 1);
      final lastDay = DateTime(month.year, month.month + 1, 0);

      // OPTIMIZATION 4: Use batch reads for better performance
      final batch = _firestore.batch();
      List<Future<QuerySnapshot>> bookingFutures = [];

      for (int day = firstDay.day; day <= lastDay.day; day++) {
        final dateKey = DateFormat('yyyy-MM-dd').format(DateTime(month.year, month.month, day));

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

      // Execute all queries concurrently
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

      _userBookingsCache[cacheKey] = userBookings;
      return userBookings;
    } catch (e) {
      print('Error getting user bookings: $e');
      return [];
    }
  }






  // Get total user bookings count
  Future<int> _getTotalUserBookings(String userEmail) async {
    if (_totalBookingsCache.containsKey(userEmail)) {
      return _totalBookingsCache[userEmail]!;
    }

    try {
      // Instead of checking every day, use aggregation or limit the range
      final now = DateTime.now();
      final startDate = DateTime(now.year, 1, 1); // Current year only
      int totalBookings = 0;

      // Process in chunks of 30 days to avoid too many concurrent requests
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




  bool _matchesSearch(Map<String, dynamic> user) {
    if (_searchQuery.isEmpty) return true;

    final name = (user['name'] ?? '').toString().toLowerCase();
    final email = (user['email'] ?? '').toString().toLowerCase();
    final phone = (user['phone'] ?? '').toString().toLowerCase();
    final vehicle = (user['vehicle'] ?? '').toString().toLowerCase();

    return name.contains(_searchQuery) ||
        email.contains(_searchQuery) ||
        phone.contains(_searchQuery) ||
        vehicle.contains(_searchQuery);
  }




  List<String> _parseVehicles(String? vehicles) {
    if (vehicles == null || vehicles.isEmpty) return [];
    return vehicles.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
  }

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




  Widget _buildUserDetailsSection(Map<String, dynamic> user, String userEmail) {
    final vehicles = _parseVehicles(user['vehicle']);

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
            // Add Delete Button
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
              if (vehicles.isNotEmpty)
                _buildDetailRow('Vehicles', vehicles.join(', ')),
              _buildDetailRow('User Type', user['userType'] ?? 'N/A'),
              _buildDetailRow('Email Verified', user['emailVerified'] == true ? 'Yes' : 'No'),
              _buildDetailRow('Joined', _formatDate(user['createdAt'])),
            ],
          ),
        ),
      ],
    );
  }
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this user?',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User: $userName',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Email: $userEmail',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange.shade700,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This action cannot be undone. All user data and allocated slots will be removed.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete, size: 16),
                  const SizedBox(width: 4),
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


  Future<void> _deleteUser(String userEmail, String userName) async {
    try {
      // Show loading
      _showMessage('Deleting user...', isError: false);

      // Delete user from Firestore
      await _firestore.collection('users').doc(userEmail).delete();

      // TODO: You might want to also remove user from allocated slots
      // This would require checking all slots and removing the user from alloted_to arrays
      await _removeUserFromAllSlots(userEmail);

      // Close the user details sheet
      Navigator.of(context).pop();

      // Show success message
      _showMessage('User "$userName" deleted successfully', isError: false);

      // Refresh the data
      _preloadSlotsData();
      setState(() {}); // Refresh the UI

    } catch (e) {
      print('Error deleting user: $e');
      _showMessage('Failed to delete user: $e', isError: true);
    }
  }


  Future<void> _removeUserFromAllSlots(String userEmail) async {
    try {
      // Get all slots
      final slotsSnapshot = await _firestore.collection('Slots').get();

      final batch = _firestore.batch();
      bool hasUpdates = false;

      for (var slotDoc in slotsSnapshot.docs) {
        final slotData = slotDoc.data();
        final allotedTo = slotData['alloted_to'] as List<dynamic>?;

        if (allotedTo != null) {
          // Remove user from alloted_to array
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

      // Commit batch if there are updates
      if (hasUpdates) {
        await batch.commit();
        print('✅ User removed from all allocated slots');
      }

    } catch (e) {
      print('Error removing user from slots: $e');
      // Don't throw error here as user deletion was successful
    }
  }



  // OPTIMIZATION 8: Use cached slot data instead of async loading
  Widget _buildSlotDetailsSection(Map<String, dynamic> user, String userEmail) {
    final userSlots = _getUserAllocatedSlots(userEmail);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Slot Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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




  Widget _buildBookingStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingItem(Map<String, dynamic> booking) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6C5CE7).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              booking['vehicleType'] == 'CAR' ? Icons.directions_car : Icons.motorcycle,
              color: const Color(0xFF6C5CE7),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Slot ${booking['slotId']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3748),
                  ),
                ),
                Text(
                  booking['dateKey'] ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              booking['vehicleType'] ?? 'N/A',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

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


  Future<void> _selectMonth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF6C5CE7),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'All Users',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: isDark
            ? const Color(0xFF6C5CE7)
            : const Color(0xFF6C5CE7),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      body: Center(
        child: Container(
          width: maxWidth,
          child: Column(
            children: [
              _buildUploadSection(),

              // Search and Filter Section
              Container(
                padding: EdgeInsets.all(isWeb ? 24 : 16),
                decoration: BoxDecoration(
                  gradient: isDark
                      ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1E1E2E),
                      const Color(0xFF2A2A3A),
                      const Color(0xFF1A1A2E),
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
                    // Search Bar - constrain width on web
                    Container(
                      width: isWeb ? 600 : double.infinity,
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          color: isDark ? Colors.white : colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search users by name, email, phone, or vehicle...',
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
                            borderSide: BorderSide(
                              color: const Color(0xFF6C5CE7),
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Filter Chips - center on web
                    isWeb
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
                    ),
                  ],
                ),
              ),
              // Users List - use GridView for web
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0D1117) : Colors.grey.shade50,
                  ),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('users').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
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
                                  'Error: ${snapshot.error}',
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

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  const Color(0xFF6C5CE7),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Loading users...',
                                style: TextStyle(
                                  color: isDark ? Colors.white.withOpacity(0.7) : colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final users = snapshot.data?.docs ?? [];

                      if (users.isEmpty) {
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
                                  'No users found',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : colorScheme.onSurface,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return FutureBuilder<List<QueryDocumentSnapshot>>(
                        future: _filterUsers(users),
                        builder: (context, filterSnapshot) {
                          if (filterSnapshot.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  const Color(0xFF6C5CE7),
                                ),
                              ),
                            );
                          }

                          final filteredUsers = _filterUsersSync(users);

                          if (filteredUsers.isEmpty) {
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
                                      Icons.search_off,
                                      size: 48,
                                      color: isDark
                                          ? const Color(0xFF6C5CE7).withOpacity(0.8)
                                          : const Color(0xFF6C5CE7),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No users match your search criteria',
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

                          // Replace ListView.builder with responsive grid/list
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
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildAddUserFAB(isDark),
    );
  }

  Widget _buildAddUserFAB(bool isDark) {
    return FloatingActionButton.extended(
      onPressed: () => _showAddUserBottomSheet(),
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


  Widget _buildAddUserForm(bool isDark, StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name Field
        _buildFormField(
          'Name',
          _nameController,
          'Enter full name',
          Icons.person,
          isDark,
        ),
        const SizedBox(height: 16),

        // Email Field (Required)
        _buildFormField(
          'Email *',
          _emailController,
          'Enter email address',
          Icons.email,
          isDark,
          isRequired: true,
        ),
        const SizedBox(height: 16),

        // Phone Field
        _buildFormField(
          'Phone',
          _phoneController,
          'Enter phone number',
          Icons.phone,
          isDark,
        ),
        const SizedBox(height: 16),

        // Vehicle Field
        _buildFormField(
          'Vehicles',
          _vehicleController,
          'Enter vehicle numbers (comma separated)',
          Icons.directions_car,
          isDark,
        ),
        const SizedBox(height: 16),

        // User Type Dropdown
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
            items: [
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
        const SizedBox(height: 16),

        // Send Reset Email Switch
        Row(
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
        ),
        const SizedBox(height: 32),

        // Add Button
        SizedBox(
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
                ? Row(
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
                const SizedBox(width: 8),
                Text('Adding User...'),
              ],
            )
                : Text(
              'Add User',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }


  Widget _buildFormField(
      String label,
      TextEditingController controller,
      String hint,
      IconData icon,
      bool isDark, {
        bool isRequired = false,
      }) {
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
              borderSide: BorderSide(color: const Color(0xFF6C5CE7), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleAddUser(StateSetter setModalState) async {
    if (_emailController.text.trim().isEmpty) {
      _showMessage('Email is required', isError: true);
      return;
    }

    setModalState(() {
      _isAddingUser = true;
    });

    try {
      final userService = UserUploadService();
      final email = _emailController.text.trim();

      // Create user data
      final userData = {
        'name': _nameController.text.trim().isEmpty
            ? userService.extractNameFromEmail(email)
            : _nameController.text.trim(),
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

      if (_vehicleController.text.trim().isNotEmpty) {
        userData['vehicles'] = userService.parseVehicleData(_vehicleController.text.trim());
      }

      // Add user to Firestore
      await _firestore.collection('users').doc(email).set(userData);

      // UPDATED: Use the new single email processing logic
      String emailMessage = '';
      if (_sendResetEmail) {
        // Use the new processSingleUserEmail method
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
      _nameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _vehicleController.clear();
      _selectedUserType = 'user';
      _sendResetEmail = true;

      Navigator.pop(context);
      _showMessage('User added successfully!$emailMessage', isError: false);

      // Refresh cache
      _preloadSlotsData();

    } catch (e) {
      print('❌ Error adding user: $e');
      _showMessage('Failed to add user: $e', isError: true);
    } finally {
      setModalState(() {
        _isAddingUser = false;
      });
    }
  }



// You'll also need to update your _buildFilterChip method:
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

  // Add this widget method to your _AllUsersPageState class
  Widget _buildUploadSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: maxWidth,
      margin: EdgeInsets.all(isWeb ? 24 : 16),
      padding: EdgeInsets.all(isWeb ? 24 : 20),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E1E2E),
            const Color(0xFF2A2A3A),
            const Color(0xFF1A1A2E),
          ],
        )
            : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFF6C5CE7).withOpacity(0.03),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: isDark
            ? Border.all(
          color: const Color(0xFF6C5CE7).withOpacity(0.3),
          width: 1,
        )
            : Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0xFF6C5CE7).withOpacity(0.1)
                : colorScheme.shadow.withOpacity(0.08),
            blurRadius: isDark ? 15 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isWeb
          ? Row(
        children: [
          // Icon and Title Section
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.cloud_upload_rounded,
                    color: const Color(0xFF6C5CE7),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bulk Upload Users',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload Excel file to add multiple users',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? Colors.white.withOpacity(0.7)
                              : colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Upload Button
          const SizedBox(width: 24),
          _buildUploadButton(isDark),
        ],
      )
          : Column(
        children: [
          // Mobile Layout
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.cloud_upload_rounded,
                  color: const Color(0xFF6C5CE7),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bulk Upload Users',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Upload Excel file to add multiple users',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withOpacity(0.7)
                            : colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildUploadButton(isDark),
        ],
      ),
    );
  }

  Widget _buildUploadButton(bool isDark) {
    return Container(
      width: isWeb ? 180 : double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isUploading ? null : _handleFileUpload,
        icon: _isUploading
            ? SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : Icon(
          Icons.upload_file_rounded,
          size: 20,
          color: Colors.white,
        ),
        label: Text(
          _isUploading ? 'Uploading...' : 'Choose File',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isUploading
              ? const Color(0xFF6C5CE7).withOpacity(0.7)
              : const Color(0xFF6C5CE7),
          foregroundColor: Colors.white,
          elevation: _isUploading ? 0 : 4,
          padding: EdgeInsets.symmetric(
            horizontal: isWeb ? 20 : 16,
            vertical: isWeb ? 14 : 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ).copyWith(
          elevation: MaterialStateProperty.resolveWith<double>(
                (Set<MaterialState> states) {
              if (states.contains(MaterialState.disabled)) return 0;
              if (states.contains(MaterialState.hovered)) return 8;
              if (states.contains(MaterialState.pressed)) return 2;
              return 4;
            },
          ),
          backgroundColor: MaterialStateProperty.resolveWith<Color>(
                (Set<MaterialState> states) {
              if (states.contains(MaterialState.disabled)) {
                return const Color(0xFF6C5CE7).withOpacity(0.7);
              }
              if (states.contains(MaterialState.hovered)) {
                return const Color(0xFF5A4FCF);
              }
              if (states.contains(MaterialState.pressed)) {
                return const Color(0xFF4C43B8);
              }
              return const Color(0xFF6C5CE7);
            },
          ),
        ),
      ),
    );
  }

  void _handleFileUpload() async {
    try {
      setState(() {
        _isUploading = true;
        _uploadStatus = 'Selecting file...';
      });

      // Show loading snackbar
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
              Text('Selecting file...'),
            ],
          ),
          backgroundColor: const Color(0xFF6C5CE7),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      // Step 1: Pick file
      final userService = UserUploadService();
      FilePickerResult? result = await userService.pickUserFile();

      if (result == null) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });

        _showMessage('No file selected', isError: true);
        return;
      }

      // Step 2: Validate file
      final file = result.files.first;
      final fileName = file.name;
      final fileExtension = fileName.toLowerCase().split('.').last;

      if (!['xlsx', 'csv'].contains(fileExtension)) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });

        _showMessage('Please select an Excel (.xlsx) or CSV file', isError: true);
        return;
      }

      // Step 3: Show simple confirmation dialog (no email checkbox)
      bool? proceed = await _showUploadConfirmationDialog(fileName);
      if (proceed != true) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
        return;
      }

      // Step 4: Process the file with auto email detection
      setState(() {
        _uploadStatus = 'Processing file and checking user accounts...';
      });

      String result_message;

      // Process based on platform (removed sendResetEmails parameter)
      if (kIsWeb) {
        result_message = await userService.processUserFile(
          fileBytes: file.bytes,
          fileName: fileName,
          skipExisting: true,
        );
      } else {
        result_message = await userService.processUserFile(
          filePath: file.path,
          fileName: fileName,
          skipExisting: true,
        );
      }

      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });

      // Step 5: Show detailed result dialog
      _showUploadResultDialog(result_message);

    } catch (e) {
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });

      print('Error during file upload: $e');
      _showMessage('Upload failed: ${e.toString()}', isError: true);
    }
  }


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
            SizedBox(width: 8),
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


  Future<bool?> _showUploadConfirmationDialog(String fileName) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          title: Row(
            children: [
              Icon(
                Icons.upload_file,
                color: const Color(0xFF6C5CE7),
              ),
              SizedBox(width: 8),
              Text(
                'Confirm Upload',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'File: $fileName',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              SizedBox(height: 16),

              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF6C5CE7).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will:',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• Create user accounts in Firestore\n'
                          '• Skip existing users\n'
                          '• Auto-generate names from emails if needed\n'
                          '• Set default userType as "user"',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // NEW: Auto email info container
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_fix_high,
                      color: Colors.green.shade700,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Smart Email Detection',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Password reset emails will be automatically sent only to new users who don\'t have Firebase accounts yet.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Upload'),
            ),
          ],
        );
      },
    );
  }

  void _showUploadResultDialog(String result) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSuccess = result.contains('Complete!');
    final hasEmailResults = result.contains('Password reset emails sent');

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          title: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.warning,
                color: isSuccess ? Colors.green : Colors.orange,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSuccess ? 'Upload Successful' : 'Upload Issues',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Show email indicator if emails were auto-sent
              if (hasEmailResults)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mark_email_read,
                        size: 14,
                        color: Colors.green.shade700,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Auto-Sent',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2A3A)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.grey.shade700
                        : Colors.grey.shade200,
                  ),
                ),
                child: Text(
                  result,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.4,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            if (hasEmailResults)
              TextButton.icon(
                onPressed: () {
                  _showMessage(
                    'Password reset emails were automatically sent to new users! They can check their inbox to set passwords.',
                    isError: false,
                  );
                },
                icon: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: const Color(0xFF6C5CE7),
                ),
                label: Text(
                  'Email Info',
                  style: TextStyle(color: const Color(0xFF6C5CE7)),
                ),
              ),
            if (isSuccess)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Refresh the users list
                  setState(() {});
                },
                child: Text(
                  'Refresh List',
                  style: TextStyle(color: const Color(0xFF6C5CE7)),
                ),
              ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }




  Future<List<QueryDocumentSnapshot>> _filterUsers(List<QueryDocumentSnapshot> users) async {
    List<QueryDocumentSnapshot> filteredUsers = [];

    for (var doc in users) {
      final userData = doc.data() as Map<String, dynamic>;
      final userEmail = doc.id;

      if (_matchesSearch(userData) && await _matchesFilter(userData, userEmail)) {
        filteredUsers.add(doc);
      }
    }

    return filteredUsers;
  }
}