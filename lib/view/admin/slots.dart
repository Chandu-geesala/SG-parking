import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

import '../../utils/dimensions_card.dart';

class ParkingSlotsPage extends StatefulWidget {
  const ParkingSlotsPage({Key? key}) : super(key: key);

  @override
  State<ParkingSlotsPage> createState() => _ParkingSlotsPageState();
}

class _ParkingSlotsPageState extends State<ParkingSlotsPage>
    with SingleTickerProviderStateMixin {
  List<CarDimension> _carDimensions = [];
  bool _dimensionsLoaded = false;


  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<ParkingSlot> _allSlots = [];
  List<ParkingSlot> _filteredSlots = [];
  bool _isLoading = true;
  bool _isDarkMode = false;
  String _selectedFilter = 'all';
  String _sortBy = 'slotNo';
  bool _showFilters = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _fetchParkingSlots();
    _fetchCarDimensions(); // Add this line
    _searchController.addListener(_filterSlots);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }


  Future<void> _fetchCarDimensions() async {
    if (_dimensionsLoaded) return; // Use cached data

    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('dimensions')
          .orderBy(FieldPath.documentId)
          .get();

      final List<CarDimension> dimensions = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return CarDimension.fromFirestore(doc.id, data);
      }).toList();

      setState(() {
        _carDimensions = dimensions;
        _dimensionsLoaded = true;
      });
    } catch (e) {
      print('Error fetching car dimensions: $e');
    }
  }



  Future<void> _fetchParkingSlots() async {
    try {
      setState(() => _isLoading = true);

      final QuerySnapshot snapshot = await _firestore.collection('Slots').get();

      final List<ParkingSlot> slots = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return ParkingSlot.fromFirestore(doc.id, data);
      }).toList();

      setState(() {
        _allSlots = slots;
        _filteredSlots = slots;
        _isLoading = false;
      });

      _animationController.forward();
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error fetching slots: $e');
    }
  }

  void _filterSlots() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      _filteredSlots = _allSlots.where((slot) {
        final matchesSearch = slot.slotNo.toLowerCase().contains(query) ||
            slot.allottedTo.any((user) =>
            user.name.toLowerCase().contains(query) ||
                user.email.toLowerCase().contains(query));

        final matchesFilter = _selectedFilter == 'all' ||
            _selectedFilter == slot.vehicleType.toLowerCase() ||
            _selectedFilter == slot.slotPriority;

        return matchesSearch && matchesFilter;
      }).toList();

      // Sort slots
      _filteredSlots.sort((a, b) {
        switch (_sortBy) {
          case 'slotNo':
            return a.slotNo.compareTo(b.slotNo);
          case 'vehicleType':
            return a.vehicleType.compareTo(b.vehicleType);
          case 'expiry':
            if (a.allottedTo.isEmpty && b.allottedTo.isEmpty) return 0;
            if (a.allottedTo.isEmpty) return 1;
            if (b.allottedTo.isEmpty) return -1;

            final aExpiry = a.allottedTo.map((u) => u.expiryDate).reduce(
                    (a, b) => a.isBefore(b) ? a : b);
            final bExpiry = b.allottedTo.map((u) => u.expiryDate).reduce(
                    (a, b) => a.isBefore(b) ? a : b);
            return aExpiry.compareTo(bExpiry);
          default:
            return 0;
        }
      });
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAddSlotDialog() {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController slotNoController = TextEditingController();
    final TextEditingController remarksController = TextEditingController();
    final TextEditingController vehicleCompatibilityController = TextEditingController();

    String selectedVehicleType = 'CAR';
    String selectedSlotPriority = 'permanent';
    String selectedStatus = 'AVAILABLE';
    String? selectedDimension;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 600;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_circle, color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Add New Parking Slot',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: isWeb ? 20 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Container(
                width: isWeb ? 500 : double.maxFinite,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Slot Number (Required)
                        Text(
                          'Slot Number *',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: slotNoController,
                          decoration: InputDecoration(
                            hintText: 'Enter slot number (e.g., A001, B123)',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[500],
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(
                              Icons.local_parking,
                              color: isDark ? Colors.grey[400] : Colors.grey[500],
                            ),
                          ),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Slot number is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Vehicle Type (Required)
                        Text(
                          'Vehicle Type *',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: selectedVehicleType,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(
                              selectedVehicleType == 'CAR'
                                  ? Icons.directions_car
                                  : Icons.two_wheeler,
                              color: isDark ? Colors.grey[400] : Colors.grey[500],
                            ),
                          ),
                          dropdownColor: isDark ? const Color(0xFF374151) : Colors.white,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'CAR', child: Text('Car')),
                            DropdownMenuItem(value: 'BIKE', child: Text('Bike')),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedVehicleType = value!;
                              // Reset car-specific fields when switching to bike
                              if (value == 'BIKE') {
                                selectedDimension = null;
                                vehicleCompatibilityController.clear();
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // Slot Priority (Required)
                        Text(
                          'Slot Priority *',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: selectedSlotPriority,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(
                              Icons.priority_high,
                              color: isDark ? Colors.grey[400] : Colors.grey[500],
                            ),
                          ),
                          dropdownColor: isDark ? const Color(0xFF374151) : Colors.white,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'permanent', child: Text('Permanent')),
                            DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedSlotPriority = value!;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // Car-specific fields
                        if (selectedVehicleType == 'CAR') ...[
                          // Dimension dropdown for cars
                          Text(
                            'Dimension *',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: selectedDimension,
                            decoration: InputDecoration(
                              hintText: 'Select car slot dimension',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: Icon(
                                Icons.straighten,
                                color: isDark ? Colors.grey[400] : Colors.grey[500],
                              ),
                            ),
                            dropdownColor: isDark ? const Color(0xFF374151) : Colors.white,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            items: _carDimensions.map((dimension) {
                              return DropdownMenuItem<String>(
                                value: dimension.displayText,
                                child: Text(
                                  dimension.displayText,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedDimension = value;
                              });
                            },
                            validator: selectedVehicleType == 'CAR' ? (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please select a dimension for car slots';
                              }
                              return null;
                            } : null,
                          ),
                          const SizedBox(height: 16),

                          // Vehicle Compatibility (Car only)
                          Text(
                            'Vehicle Compatibility Level',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: vehicleCompatibilityController,
                            decoration: InputDecoration(
                              hintText: 'Enter compatibility level (optional)',
                              hintStyle: TextStyle(
                                color: isDark ? Colors.grey[400] : Colors.grey[500],
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: Icon(
                                Icons.settings,
                                color: isDark ? Colors.grey[400] : Colors.grey[500],
                              ),
                            ),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],


                        // Remarks (Always visible)
                        Text(
                          'Remarks',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: remarksController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Enter any additional remarks (optional)',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[500],
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: Icon(
                              Icons.comment,
                              color: isDark ? Colors.grey[400] : Colors.grey[500],
                            ),
                          ),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      // Check if slot number already exists
                      final existingSlot = _allSlots.any(
                            (slot) => slot.slotNo.toLowerCase() == slotNoController.text.trim().toLowerCase(),
                      );

                      if (existingSlot) {
                        _showErrorSnackBar('Slot number already exists!');
                        return;
                      }

                      try {
                        // Prepare slot data
                        final slotData = {
                          'slotNo': slotNoController.text.trim(),
                          'vehicleType': selectedVehicleType,
                          'slotPriority': selectedSlotPriority,
                          'status': selectedStatus,
                          'vehicleCompatibility': selectedVehicleType == 'CAR' && vehicleCompatibilityController.text.trim().isNotEmpty
                              ? vehicleCompatibilityController.text.trim()
                              : null,
                          'dimension': selectedVehicleType == 'CAR' ? selectedDimension : null,
                          'remarks': remarksController.text.trim().isEmpty
                              ? null
                              : remarksController.text.trim(),
                          'alloted_to': [], // Empty array for new slot
                          'created_at': FieldValue.serverTimestamp(),
                        };

                        // Add to Firestore
                        // Add to Firestore with slot number as document ID
                        await _firestore.collection('Slots').doc(slotNoController.text.trim()).set(slotData);

                        Navigator.of(context).pop();
                        _showSuccessSnackBar('Parking slot added successfully!');

                        // Refresh the slots list
                        _fetchParkingSlots();

                      } catch (e) {
                        _showErrorSnackBar('Error adding slot: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Add Slot'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteSlot(ParkingSlot slot) async {
    // Show confirmation dialog
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                'Delete Slot',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete slot "${slot.slotNo}"? This action cannot be undone.',
            style: TextStyle(
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      try {
        // Delete from Firestore
        // Delete from Firestore using the actual document ID
        await _firestore.collection('Slots').doc(slot.id).delete();

        _showSuccessSnackBar('Slot "${slot.slotNo}" deleted successfully!');

        // Refresh the slots list
        _fetchParkingSlots();

      } catch (e) {
        _showErrorSnackBar('Error deleting slot: $e');
      }
    }
  }



  Color _getStatusColor(ParkingSlot slot) {
    if (slot.allottedTo.isEmpty) return Colors.grey;

    final nearestExpiry = slot.allottedTo
        .map((u) => u.expiryDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    if (nearestExpiry.isBefore(DateTime.now())) {
      return Colors.red;
    } else if (nearestExpiry.isBefore(DateTime.now().add(const Duration(days: 30)))) {
      return Colors.orange;
    }
    return Colors.green;
  }

  String _getStatusText(ParkingSlot slot) {
    if (slot.allottedTo.isEmpty) return 'Available';

    final nearestExpiry = slot.allottedTo
        .map((u) => u.expiryDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    if (nearestExpiry.isBefore(DateTime.now())) {
      return 'Expired';
    } else if (nearestExpiry.isBefore(DateTime.now().add(const Duration(days: 30)))) {
      return 'Expiring Soon';
    }
    return 'Active';
  }

  // Helper method to get responsive column count
  int _getColumnCount(double screenWidth) {
    if (screenWidth > 1200) return 4;
    if (screenWidth > 800) return 3;
    if (screenWidth > 600) return 2;
    return 1;
  }

  // Helper method to get responsive aspect ratio
  double _getAspectRatio(double screenWidth) {
    if (screenWidth > 1200) return 0.85;
    if (screenWidth > 800) return 0.8;
    if (screenWidth > 600) return 0.75;
    return 1.1; // Taller cards for mobile
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 600;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB),
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
            surfaceTintColor: Colors.transparent,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Parking Slots',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: isWeb ? 24 : 20,
                  ),
                ),

              ],
            ),
            actions: [
              IconButton(
                onPressed: _fetchParkingSlots,
                icon: Icon(
                  Icons.refresh,
                  color: isDark ? Colors.white : Colors.black,
                ),
                tooltip: 'Refresh',
              ),
              IconButton(
                onPressed: _showDimensionsBottomSheet,
                icon: Icon(
                  Icons.calculate,
                  color: isDark ? Colors.white : Colors.black,
                ),
                tooltip: 'Manage Dimensions',
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _showFilters = !_showFilters;
                  });
                },
                icon: Icon(
                  Icons.filter_list,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(_showFilters ? (isWeb ? 260 : 320) : 100), // Increased heights
              child: Container(
                width: double.infinity,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(isWeb ? 16 : 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Search Bar
                        Container(
                          constraints: BoxConstraints(maxWidth: isWeb ? 800 : double.infinity),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF374151) : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                            ),
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by slot, name, or email...',
                              hintStyle: TextStyle(
                                color: isDark ? Colors.grey[400] : Colors.grey[500],
                                fontSize: isWeb ? 14 : 12,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: isDark ? Colors.grey[400] : Colors.grey[500],
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: isWeb ? 14 : 12,
                              ),
                            ),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: isWeb ? 14 : 12,
                            ),
                          ),
                        ),

                        // Filter Panel
                        if (_showFilters) ...[
                          SizedBox(height: isWeb ? 16 : 12),
                          Container(
                            constraints: BoxConstraints(maxWidth: isWeb ? 800 : double.infinity),
                            padding: EdgeInsets.all(isWeb ? 16 : 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1F2937) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isWeb)
                                  Row(
                                    children: [
                                      Expanded(child: _buildFilterDropdown('Filter by Type', _selectedFilter, [
                                        {'value': 'all', 'text': 'All Types'},
                                        {'value': 'bike', 'text': 'Bike'},
                                        {'value': 'car', 'text': 'Car'},
                                        {'value': 'permanent', 'text': 'Permanent'},
                                        {'value': 'hybrid', 'text': 'Hybrid'},
                                      ], (value) {
                                        setState(() => _selectedFilter = value!);
                                        _filterSlots();
                                      }, isDark)),
                                      const SizedBox(width: 16),
                                      Expanded(child: _buildFilterDropdown('Sort by', _sortBy, [
                                        {'value': 'slotNo', 'text': 'Slot Number'},
                                        {'value': 'vehicleType', 'text': 'Vehicle Type'},
                                        {'value': 'expiry', 'text': 'Expiry Date'},
                                      ], (value) {
                                        setState(() => _sortBy = value!);
                                        _filterSlots();
                                      }, isDark)),
                                    ],
                                  )
                                else
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildFilterDropdown('Filter by Type', _selectedFilter, [
                                        {'value': 'all', 'text': 'All Types'},
                                        {'value': 'bike', 'text': 'Bike'},
                                        {'value': 'car', 'text': 'Car'},
                                        {'value': 'permanent', 'text': 'Permanent'},
                                        {'value': 'hybrid', 'text': 'Hybrid'},
                                      ], (value) {
                                        setState(() => _selectedFilter = value!);
                                        _filterSlots();
                                      }, isDark),
                                      const SizedBox(height: 12),
                                      _buildFilterDropdown('Sort by', _sortBy, [
                                        {'value': 'slotNo', 'text': 'Slot Number'},
                                        {'value': 'vehicleType', 'text': 'Vehicle Type'},
                                        {'value': 'expiry', 'text': 'Expiry Date'},
                                      ], (value) {
                                        setState(() => _sortBy = value!);
                                        _filterSlots();
                                      }, isDark),
                                    ],
                                  ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _selectedFilter = 'all';
                                        _sortBy = 'slotNo';
                                      });
                                      _filterSlots();
                                    },
                                    icon: const Icon(Icons.clear, size: 18),
                                    label: const Text('Clear Filters'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isDark ? Colors.grey[700] : Colors.grey[200],
                                      foregroundColor: isDark ? Colors.white : Colors.black,
                                      padding: EdgeInsets.symmetric(
                                        vertical: isWeb ? 12 : 10,
                                        horizontal: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Stats Cards
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(isWeb ? 16 : 12),
              child: Center(
                child: Container(
                  constraints: BoxConstraints(maxWidth: isWeb ? 1200 : double.infinity),
                  child: isWeb
                      ? Row(
                    children: [
                      Expanded(child: _buildStatCard('Total Slots', '${_allSlots.length}', Icons.local_parking, Colors.blue, isDark, isWeb)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('Car Slots', '${_allSlots.where((s) => s.vehicleType == 'CAR').length}', Icons.directions_car, Colors.green, isDark, isWeb)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('Bike Slots', '${_allSlots.where((s) => s.vehicleType == 'BIKE').length}', Icons.two_wheeler, Colors.purple, isDark, isWeb)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('Hybrid', '${_allSlots.where((s) => s.slotPriority == 'hybrid').length}', Icons.people, Colors.orange, isDark, isWeb)),
                    ],
                  )
                      : GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 1.5,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: [
                      _buildStatCard('Total Slots', '${_allSlots.length}', Icons.local_parking, Colors.blue, isDark, isWeb),
                      _buildStatCard('Car Slots', '${_allSlots.where((s) => s.vehicleType == 'CAR').length}', Icons.directions_car, Colors.green, isDark, isWeb),
                      _buildStatCard('Bike Slots', '${_allSlots.where((s) => s.vehicleType == 'BIKE').length}', Icons.two_wheeler, Colors.purple, isDark, isWeb),
                      _buildStatCard('Hybrid', '${_allSlots.where((s) => s.slotPriority == 'hybrid').length}', Icons.people, Colors.orange, isDark, isWeb),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Slots List
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_filteredSlots.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: isWeb ? 64 : 48,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No slots found',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: isWeb ? 20 : 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try adjusting your search or filter criteria',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                        fontSize: isWeb ? 14 : 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.all(isWeb ? 16 : 12),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: isWeb ? 1400 : double.infinity),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columnCount = _getColumnCount(constraints.maxWidth);
                        final aspectRatio = _getAspectRatio(constraints.maxWidth);

                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columnCount,
                            childAspectRatio: aspectRatio,
                            crossAxisSpacing: isWeb ? 16 : 8,
                            mainAxisSpacing: isWeb ? 16 : 8,
                          ),
                          itemCount: _filteredSlots.length,
                          itemBuilder: (context, index) {
                            final slot = _filteredSlots[index];
                            return FadeTransition(
                              opacity: _fadeAnimation,
                              child: _buildSlotCard(slot, isDark, isWeb),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSlotDialog,
        backgroundColor: Colors.blue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Slot',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }


  void _showDimensionsBottomSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7, // Start at 70% of screen height
        minChildSize: 0.5,     // Minimum 50% of screen height
        maxChildSize: 0.95,    // Maximum 95% of screen height
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header (fixed at top)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Manage Car Slot Dimensions',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: CarSlotDimensionsWidget(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      // Refresh dimensions when bottom sheet is closed
      _fetchCarDimensions();
    });
  }



  Widget _buildFilterDropdown(String title, String value, List<Map<String, String>> items, ValueChanged<String?> onChanged, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            isDense: true,
          ),
          items: items.map((item) => DropdownMenuItem(
            value: item['value'],
            child: Text(item['text']!, style: const TextStyle(fontSize: 14)),
          )).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isDark, bool isWeb) {
    return Container(
      padding: EdgeInsets.all(isWeb ? 16 : 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(isWeb ? 12 : 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: isWeb ? 24 : 20),
          ),
          SizedBox(height: isWeb ? 12 : 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isWeb ? 24 : 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: isWeb ? 14 : 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(ParkingSlot slot, bool isDark, bool isWeb) {
    final statusColor = _getStatusColor(slot);
    final statusText = _getStatusText(slot);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.all(isWeb ? 16 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(isWeb ? 10 : 8),
                      decoration: BoxDecoration(
                        color: slot.vehicleType == 'CAR'
                            ? Colors.green.withOpacity(0.1)
                            : Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        slot.vehicleType == 'CAR'
                            ? Icons.directions_car
                            : Icons.two_wheeler,
                        color: slot.vehicleType == 'CAR'
                            ? Colors.green
                            : Colors.purple,
                        size: isWeb ? 22 : 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slot.slotNo,
                            style: TextStyle(
                              fontSize: isWeb ? 18 : 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${slot.vehicleType} • ${slot.slotPriority}',
                            style: TextStyle(
                              fontSize: isWeb ? 13 : 11,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Add delete button
                    IconButton(
                      onPressed: () => _deleteSlot(slot),
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.withOpacity(0.7),
                        size: isWeb ? 20 : 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      tooltip: 'Delete Slot',
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: isWeb ? 11 : 10,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),


          // Details
          if (slot.dimension != null || slot.vehicleCompatibility != null || slot.remarks != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isWeb ? 16 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (slot.dimension != null) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.straighten,
                          size: isWeb ? 16 : 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            slot.dimension!,
                            style: TextStyle(
                              fontSize: isWeb ? 13 : 11,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],



                  if (slot.vehicleCompatibility != null) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.settings,
                          size: isWeb ? 16 : 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Level: ${slot.vehicleCompatibility}',
                            style: TextStyle(
                              fontSize: isWeb ? 13 : 11,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (slot.remarks != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.comment,
                          size: isWeb ? 16 : 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            slot.remarks!,
                            style: TextStyle(
                              fontSize: isWeb ? 13 : 11,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          SizedBox(height: isWeb ? 12 : 8),

          // Users
          Expanded(
            child: Container(
              margin: EdgeInsets.all(isWeb ? 16 : 12),
              padding: EdgeInsets.all(isWeb ? 12 : 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF374151) : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey[600]! : Colors.grey[200]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.people,
                        size: isWeb ? 16 : 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Users (${slot.allottedTo.length})',
                        style: TextStyle(
                          fontSize: isWeb ? 13 : 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (slot.allottedTo.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'No users assigned',
                          style: TextStyle(
                            fontSize: isWeb ? 12 : 11,
                            color: isDark ? Colors.grey[500] : Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: slot.allottedTo.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final user = slot.allottedTo[index];
                          final daysLeft = user.expiryDate.difference(DateTime.now()).inDays;

                          return Container(
                            padding: EdgeInsets.all(isWeb ? 10 : 8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1F2937) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark ? Colors.grey[600]! : Colors.grey[200]!,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: TextStyle(
                                    fontSize: isWeb ? 12 : 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user.email,
                                  style: TextStyle(
                                    fontSize: isWeb ? 11 : 9,
                                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        user.period,
                                        style: TextStyle(
                                          fontSize: isWeb ? 10 : 9,
                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${daysLeft}d left',
                                      style: TextStyle(
                                        fontSize: isWeb ? 10 : 9,
                                        fontWeight: FontWeight.w600,
                                        color: daysLeft < 0
                                            ? Colors.red
                                            : daysLeft < 30
                                            ? Colors.orange
                                            : Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Data Models
class ParkingSlot {
  final String id;
  final String slotNo;
  final String vehicleType;
  final String slotPriority;
  final String? vehicleCompatibility;
  final String? dimension;
  final String? remarks;
  final List<AllottedUser> allottedTo;

  ParkingSlot({
    required this.id,
    required this.slotNo,
    required this.vehicleType,
    required this.slotPriority,
    this.vehicleCompatibility,
    this.dimension,
    this.remarks,
    required this.allottedTo,
  });

  factory ParkingSlot.fromFirestore(String id, Map<String, dynamic> data) {
    final allottedToList = (data['alloted_to'] as List<dynamic>?)
        ?.map((userData) => AllottedUser.fromMap(userData as Map<String, dynamic>))
        .toList() ?? [];

    return ParkingSlot(
      id: id,
      slotNo: data['slotNo'] ?? '',
      vehicleType: data['vehicleType'] ?? '',
      slotPriority: data['slotPriority'] ?? '',
      vehicleCompatibility: data['vehicleCompatibility'],
      dimension: data['dimension'],
      remarks: data['remarks'],
      allottedTo: allottedToList,
    );
  }
}

class AllottedUser {
  final String name;
  final String email;
  final DateTime allottedDate;
  final String period;
  final int periodMonths;
  final DateTime expiryDate;

  AllottedUser({
    required this.name,
    required this.email,
    required this.allottedDate,
    required this.period,
    required this.periodMonths,
    required this.expiryDate,
  });

  factory AllottedUser.fromMap(Map<String, dynamic> data) {
    return AllottedUser(
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      allottedDate: DateTime.parse(data['alloted_date'] ?? DateTime.now().toIso8601String()),
      period: data['period'] ?? '',
      periodMonths: data['period_months'] ?? 0,
      expiryDate: DateTime.parse(data['expiry_date'] ?? DateTime.now().toIso8601String()),
    );
  }
}


class CarDimension {
  final String id;
  final String name;
  final double width;
  final double height;
  final double area;

  CarDimension({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.area,
  });

  factory CarDimension.fromFirestore(String docId, Map<String, dynamic> data) {
    return CarDimension(
      id: docId,
      name: docId.replaceAllMapped(
        RegExp(r'Dimension(\d+)'),
            (match) => 'Dimension ${match.group(1)}',
      ),
      width: (data['width'] ?? 0).toDouble(),
      height: (data['height'] ?? 0).toDouble(),
      area: (data['area'] ?? 0).toDouble(),
    );
  }

  String get displayText => '$name (${width}m × ${height}m - ${area.toStringAsFixed(1)}m²)';
}

