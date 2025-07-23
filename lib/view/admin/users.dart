import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
        Text(
          'User Details',
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
    );
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