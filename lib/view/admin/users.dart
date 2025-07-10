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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Check if user has any slot allocated by checking Slots collection
  Future<bool> _isUserSlotAllocated(String userEmail) async {
    try {
      final slotsQuery = await _firestore.collection('Slots').get();

      for (var slotDoc in slotsQuery.docs) {
        final slotData = slotDoc.data();
        final allotedTo = slotData['alloted_to'] as List<dynamic>?;

        if (allotedTo != null) {
          for (var allocation in allotedTo) {
            if (allocation['email'] == userEmail) {
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      print('Error checking slot allocation: $e');
      return false;
    }
  }

  // Get user's allocated slots
  Future<List<Map<String, dynamic>>> _getUserAllocatedSlots(String userEmail) async {
    try {
      final slotsQuery = await _firestore.collection('Slots').get();
      List<Map<String, dynamic>> userSlots = [];

      for (var slotDoc in slotsQuery.docs) {
        final slotData = slotDoc.data();
        final allotedTo = slotData['alloted_to'] as List<dynamic>?;

        if (allotedTo != null) {
          for (var allocation in allotedTo) {
            if (allocation['email'] == userEmail) {
              userSlots.add({
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
      return userSlots;
    } catch (e) {
      print('Error getting user slots: $e');
      return [];
    }
  }

  // Get user's bookings for a specific month
  Future<List<Map<String, dynamic>>> _getUserBookings(String userEmail, DateTime month) async {
    try {
      List<Map<String, dynamic>> userBookings = [];

      // Get all days in the month
      final firstDay = DateTime(month.year, month.month, 1);
      final lastDay = DateTime(month.year, month.month + 1, 0);

      for (int day = firstDay.day; day <= lastDay.day; day++) {
        final dateKey = DateFormat('yyyy-MM-dd').format(DateTime(month.year, month.month, day));

        try {
          final bookingsDoc = await _firestore
              .collection('Bookings')
              .doc(dateKey)
              .collection('BookedToday')
              .where('bookedBy', isEqualTo: userEmail)
              .get();

          for (var bookingDoc in bookingsDoc.docs) {
            final bookingData = bookingDoc.data();
            userBookings.add({
              'slotId': bookingData['slotId'],
              'bookedBy': bookingData['bookedBy'],
              'userName': bookingData['userName'],
              'vehicleType': bookingData['vehicleType'],
              'bookingDate': bookingData['bookingDate'],
              'dateKey': dateKey,
            });
          }
        } catch (e) {
          // Continue if date doesn't exist
          continue;
        }
      }

      return userBookings;
    } catch (e) {
      print('Error getting user bookings: $e');
      return [];
    }
  }

  // Get total user bookings count
  Future<int> _getTotalUserBookings(String userEmail) async {
    try {
      int totalBookings = 0;

      // This is a simplified approach - in production, you might want to optimize this
      final now = DateTime.now();
      final startDate = DateTime(now.year - 1, now.month, now.day); // Last year

      for (var date = startDate; date.isBefore(now); date = date.add(const Duration(days: 1))) {
        final dateKey = DateFormat('yyyy-MM-dd').format(date);

        try {
          final bookingsDoc = await _firestore
              .collection('Bookings')
              .doc(dateKey)
              .collection('BookedToday')
              .where('bookedBy', isEqualTo: userEmail)
              .get();

          totalBookings += bookingsDoc.docs.length;
        } catch (e) {
          continue;
        }
      }

      return totalBookings;
    } catch (e) {
      print('Error getting total bookings: $e');
      return 0;
    }
  }

  // Filter users based on search and filter type
  Future<bool> _matchesFilter(Map<String, dynamic> user, String userEmail) async {
    switch (_selectedFilter) {
      case 'alloted':
        return await _isUserSlotAllocated(userEmail);
      case 'unalloted':
        return !(await _isUserSlotAllocated(userEmail));
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

  Widget _buildUserCard(Map<String, dynamic> user, String userEmail) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showUserBottomSheet(user, userEmail),
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<bool>(
          future: _isUserSlotAllocated(userEmail),
          builder: (context, snapshot) {
            final isAlloted = snapshot.data ?? false;
            final vehicles = _parseVehicles(user['vehicle']);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: isAlloted ? Colors.green.shade100 : Colors.grey.shade100,
                      child: Icon(
                        Icons.person,
                        color: isAlloted ? Colors.green : Colors.grey,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user['name'] ?? 'No Name',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userEmail,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isAlloted ? Colors.green.shade100 : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAlloted ? 'Alloted' : 'Unalloted',
                        style: TextStyle(
                          color: isAlloted ? Colors.green : Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showUserBottomSheet(Map<String, dynamic> user, String userEmail) {
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
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Content
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
                        const SizedBox(height: 24),
                        _buildBookingDataSection(user, userEmail),
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

  Widget _buildUserDetailsSection(Map<String, dynamic> user, String userEmail) {
    final vehicles = _parseVehicles(user['vehicle']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'User Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
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

  Widget _buildSlotDetailsSection(Map<String, dynamic> user, String userEmail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Slot Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _getUserAllocatedSlots(userEmail),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: CircularProgressIndicator()),
              );
            }

            final userSlots = snapshot.data ?? [];

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: userSlots.isNotEmpty ? Column(
                children: userSlots.map((slot) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
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
              ) : const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No slots allocated to this user',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBookingDataSection(Map<String, dynamic> user, String userEmail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Booking Data',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
            ),
            GestureDetector(
              onTap: _selectMonth,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF6C5CE7)),
                ),
                child: Text(
                  DateFormat('MMM yyyy').format(_selectedMonth),
                  style: const TextStyle(
                    color: Color(0xFF6C5CE7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<dynamic>>(
          future: Future.wait([
            _getTotalUserBookings(userEmail),
            _getUserBookings(userEmail, _selectedMonth),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: CircularProgressIndicator()),
              );
            }

            final totalBookings = snapshot.data?[0] as int? ?? 0;
            final monthlyBookings = snapshot.data?[1] as List<Map<String, dynamic>>? ?? [];

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildBookingStatCard(
                          'Total Bookings',
                          totalBookings.toString(),
                          Icons.event_seat,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildBookingStatCard(
                          'This Month',
                          monthlyBookings.length.toString(),
                          Icons.calendar_today,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (monthlyBookings.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Bookings (${DateFormat('MMM yyyy').format(_selectedMonth)})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D3748),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...monthlyBookings.take(10).map((booking) => _buildBookingItem(booking)).toList(),
                      ],
                    )
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No bookings found for selected month',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          const Text(': ', style: TextStyle(color: Colors.grey)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2D3748),
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
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
      ),
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search users by name, email, phone, or vehicle...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // Filter Chips
                SingleChildScrollView(
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
          // Users List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 64, color: Colors.red.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading users',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.red.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C5CE7)),
                    ),
                  );
                }

                final users = snapshot.data?.docs ?? [];

                return FutureBuilder<List<QueryDocumentSnapshot>>(
                  future: _filterUsers(users),
                  builder: (context, filterSnapshot) {
                    if (filterSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C5CE7)),
                        ),
                      );
                    }

                    final filteredUsers = filterSnapshot.data ?? [];

                    if (filteredUsers.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty ? 'No users found' : 'No users match your search',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
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
        ],
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