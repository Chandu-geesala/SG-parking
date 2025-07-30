import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../../utils/dimensions_card.dart';

class ParkingSlotsPage extends StatefulWidget {
  final String? initialSearch;
  const ParkingSlotsPage({Key? key, this.initialSearch}) : super(key: key);

  @override
  State<ParkingSlotsPage> createState() => _ParkingSlotsPageState();
}

class _ParkingSlotsPageState extends State<ParkingSlotsPage>
    with SingleTickerProviderStateMixin {

  // ============================================================================
  // CORE DEPENDENCIES & VARIABLES
  // ============================================================================

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  // Animation controllers
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Data variables
  List<ParkingSlot> _allSlots = [];
  List<ParkingSlot> _filteredSlots = [];
  List<CarDimension> _carDimensions = [];

  // State variables
  bool _isLoading = true;
  bool _dimensionsLoaded = false;
  String _selectedVehicleTypeChip = 'all'; // 'all', 'CAR', 'BIKE'
  String _sortBy = 'slotNo';
  bool _showFilters = false;
  bool _isDarkMode = false;

  // ============================================================================
  // LIFECYCLE METHODS
  // ============================================================================

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadInitialData();
    _setupSearchListener();
    _handleInitialSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ============================================================================
  // INITIALIZATION METHODS
  // ============================================================================

  /// Initialize animation controllers
  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  /// Load initial data - slots and dimensions
  void _loadInitialData() {
    _fetchParkingSlots();
    _fetchCarDimensions();
  }

  /// Setup search text field listener
  void _setupSearchListener() {
    _searchController.addListener(_filterSlots);
  }

  /// Handle initial search if provided
  void _handleInitialSearch() {
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _searchController.text = widget.initialSearch!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isLoading) {
          _filterSlots();
        } else {
          Future.microtask(() async {
            while (_isLoading) {
              await Future.delayed(const Duration(milliseconds: 50));
            }
            _filterSlots();
          });
        }
      });
    }
  }

  // ============================================================================
  // DATA FETCHING METHODS
  // ============================================================================

  /// Fetch parking slots from Firestore
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

  /// Fetch car dimensions from Firestore (cached)
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

  // ============================================================================
  // FILTERING & SEARCH METHODS
  // ============================================================================

  /// Filter slots based on search query and vehicle type
  void _filterSlots() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      _filteredSlots = _allSlots.where((slot) {
        final matchesSearch = slot.slotNo.toLowerCase().contains(query) ||
            slot.allottedTo.any((user) =>
            user.name.toLowerCase().contains(query) ||
                user.email.toLowerCase().contains(query));

        final matchesVehicleType = _selectedVehicleTypeChip == 'all'
            || slot.vehicleType == _selectedVehicleTypeChip;

        return matchesSearch && matchesVehicleType;
      }).toList();

      // Sort by slot number by default
      _filteredSlots.sort((a, b) => a.slotNo.compareTo(b.slotNo));
    });
  }

  // ============================================================================
  // SLOT MANAGEMENT METHODS
  // ============================================================================

  /// Show dialog to add new parking slot
  void _showAddSlotDialog() {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController slotNoController = TextEditingController();
    final TextEditingController remarksController = TextEditingController();

    String selectedVehicleType = 'CAR';
    String selectedSlotPriority = 'permanent';
    String selectedStatus = 'AVAILABLE';
    String? selectedDimension;
    String? selectedVehicleCompatibility;

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
                        _buildSlotNumberField(slotNoController, isDark),
                        const SizedBox(height: 16),

                        _buildVehicleTypeDropdown(selectedVehicleType, setDialogState, isDark),
                        const SizedBox(height: 16),

                        if (selectedVehicleType == 'CAR') ...[
                          _buildDimensionDropdown(selectedDimension, setDialogState, isDark),
                          const SizedBox(height: 16),

                          _buildCompatibilityDropdown(selectedVehicleCompatibility, setDialogState, isDark, selectedVehicleType),
                          const SizedBox(height: 16),
                        ],

                        _buildRemarksField(remarksController, isDark),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _handleAddSlot(
                    formKey,
                    slotNoController,
                    remarksController,
                    selectedVehicleType,
                    selectedSlotPriority,
                    selectedStatus,
                    selectedDimension,
                    selectedVehicleCompatibility,
                  ),
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

  /// Handle adding new slot to Firestore
  Future<void> _handleAddSlot(
      GlobalKey<FormState> formKey,
      TextEditingController slotNoController,
      TextEditingController remarksController,
      String selectedVehicleType,
      String selectedSlotPriority,
      String selectedStatus,
      String? selectedDimension,
      String? selectedVehicleCompatibility,
      ) async {
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
        final slotData = {
          'slotNo': slotNoController.text.trim(),
          'vehicleType': selectedVehicleType,
          'slotPriority': selectedSlotPriority,
          'status': selectedStatus,
          'vehicleCompatibility': selectedVehicleType == 'CAR'
              ? selectedVehicleCompatibility
              : null,
          'dimension': selectedVehicleType == 'CAR' ? selectedDimension : null,
          'remarks': remarksController.text.trim().isEmpty
              ? null
              : remarksController.text.trim(),
          'alloted_to': [],
          'created_at': FieldValue.serverTimestamp(),
        };

        await _firestore.collection('Slots').doc(slotNoController.text.trim()).set(slotData);

        Navigator.of(context).pop();
        _showSuccessSnackBar('Parking slot added successfully!');
        _fetchParkingSlots();
      } catch (e) {
        _showErrorSnackBar('Error adding slot: $e');
      }
    }
  }

  /// Delete parking slot with confirmation
  Future<void> _deleteSlot(ParkingSlot slot) async {
    final bool? shouldDelete = await _showDeleteConfirmationDialog(slot);

    if (shouldDelete == true) {
      try {
        await _firestore.collection('Slots').doc(slot.id).delete();
        _showSuccessSnackBar('Slot "${slot.slotNo}" deleted successfully!');
        _fetchParkingSlots();
      } catch (e) {
        _showErrorSnackBar('Error deleting slot: $e');
      }
    }
  }

  // ============================================================================
  // DIALOG HELPER METHODS
  // ============================================================================

  /// Show delete confirmation dialog
  Future<bool?> _showDeleteConfirmationDialog(ParkingSlot slot) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
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
            'Are you sure you want to delete slot "${slot.slotNo}"?',
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
  }

  /// Show dimensions management bottom sheet
  void _showDimensionsBottomSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
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
              // Header
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
              // Content
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
      _fetchCarDimensions();
    });
  }

  // ============================================================================
  // FORM FIELD BUILDERS
  // ============================================================================

  /// Build slot number input field
  Widget _buildSlotNumberField(TextEditingController controller, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Enter slot number (e.g., B2-001, B1-203)',
            hintStyle: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[500],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
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
      ],
    );
  }

  /// Build vehicle type dropdown
  Widget _buildVehicleTypeDropdown(String selectedValue, StateSetter setDialogState, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          value: selectedValue,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            prefixIcon: Icon(
              selectedValue == 'CAR' ? Icons.directions_car : Icons.two_wheeler,
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
              selectedValue = value!;
            });
          },
        ),
      ],
    );
  }

  /// Build dimension dropdown for car slots
  Widget _buildDimensionDropdown(String? selectedValue, StateSetter setDialogState, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          value: selectedValue,
          decoration: InputDecoration(
            hintText: 'Select car slot dimension',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
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
              selectedValue = value;
            });
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please select a dimension for car slots';
            }
            return null;
          },
        ),
      ],
    );
  }

  /// Build vehicle compatibility dropdown
  Widget _buildCompatibilityDropdown(String? selectedValue, StateSetter setDialogState, bool isDark, String vehicleType) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vehicle Compatibility Level *',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedValue,
          decoration: InputDecoration(
            hintText: 'Select compatibility level',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          dropdownColor: isDark ? const Color(0xFF374151) : Colors.white,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
          ),
          items: const [
            DropdownMenuItem(value: 'lower', child: Text('Lower')),
            DropdownMenuItem(value: 'upper', child: Text('Upper')),
            DropdownMenuItem(value: 'surface', child: Text('Surface')),
          ],
          onChanged: (value) {
            setDialogState(() {
              selectedValue = value;
            });
          },
          validator: (value) {
            if (vehicleType == 'CAR' && (value == null || value.isEmpty)) {
              return 'Please select a compatibility level';
            }
            return null;
          },
        ),
      ],
    );
  }

  /// Build remarks text field
  Widget _buildRemarksField(TextEditingController controller, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter any additional remarks (optional)',
            hintStyle: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[500],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Get responsive column count for grid
  int _getColumnCount(double screenWidth) {
    if (screenWidth > 1200) return 4;
    if (screenWidth > 800) return 3;
    if (screenWidth > 600) return 2;
    return 1;
  }

  /// Get responsive aspect ratio for grid items
  double _getAspectRatio(double screenWidth) {
    if (screenWidth > 1200) return 0.85;
    if (screenWidth > 800) return 0.8;
    if (screenWidth > 600) return 0.75;
    return 1.1;
  }

  /// Show error message
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show success message
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================================
  // UI BUILDING METHODS
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 600;

    final carCount = _allSlots.where((s) => s.vehicleType == 'CAR').length;
    final bikeCount = _allSlots.where((s) => s.vehicleType == 'BIKE').length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchAndFilterSection(isDark, isWeb, carCount, bikeCount),
            _buildDivider(isDark),
            _buildMainContent(isDark, isWeb),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  /// Build app bar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        'Parking Slots',
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
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: TextButton(
            onPressed: _showDimensionsBottomSheet,
            child: const Text(
              'Car Dimensions',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// Build search and filter section
  Widget _buildSearchAndFilterSection(bool isDark, bool isWeb, int carCount, int bikeCount) {
    return Container(
      color: isDark ? const Color(0xFF111827) : Colors.white,
      padding: EdgeInsets.fromLTRB(
        isWeb ? 24 : 16,
        isWeb ? 20 : 16,
        isWeb ? 24 : 16,
        isWeb ? 24 : 20,
      ),
      child: Column(
        children: [
          _buildSearchBar(isDark, isWeb),
          const SizedBox(height: 16),
          _buildFilterChips(isDark, carCount, bikeCount),
        ],
      ),
    );
  }

  /// Build search bar
  Widget _buildSearchBar(bool isDark, bool isWeb) {
    return Container(
      constraints: BoxConstraints(maxWidth: isWeb ? 600 : double.infinity),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF374151) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[200]!,
        ),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by slot, name, or email...',
          hintStyle: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[500],
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? Colors.grey[400] : Colors.grey[500],
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 14,
        ),
      ),
    );
  }

  /// Build filter chips
  Widget _buildFilterChips(bool isDark, int carCount, int bikeCount) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          _buildFilterChip(
            'Car ($carCount)',
            'CAR',
            Colors.green,
            isDark,
          ),
          _buildFilterChip(
            'Bike ($bikeCount)',
            'BIKE',
            Colors.purple,
            isDark,
          ),
        ],
      ),
    );
  }

  /// Build individual filter chip
  Widget _buildFilterChip(String label, String value, Color color, bool isDark) {
    final isSelected = _selectedVehicleTypeChip == value;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedVehicleTypeChip = isSelected ? 'all' : value;
          _filterSlots();
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color
              : (isDark ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Build divider between sections
  Widget _buildDivider(bool isDark) {
    return Container(
      height: 1,
      color: isDark ? Colors.grey[700] : Colors.grey[200],
    );
  }

  /// Build main content area
  Widget _buildMainContent(bool isDark, bool isWeb) {
    return Expanded(
      child: RefreshIndicator(
        onRefresh: _fetchParkingSlots,
        color: Theme.of(context).colorScheme.primary,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _filteredSlots.isEmpty
            ? _buildEmptyState(isDark, isWeb)
            : _buildSlotsGrid(isWeb),
      ),
    );
  }

  /// Build empty state when no slots found
  Widget _buildEmptyState(bool isDark, bool isWeb) {
    return Center(
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
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: isWeb ? 20 : 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filter criteria',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[500],
              fontSize: isWeb ? 14 : 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Build slots grid
  Widget _buildSlotsGrid(bool isWeb) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = _getColumnCount(constraints.maxWidth);
        final aspectRatio = _getAspectRatio(constraints.maxWidth);

        return GridView.builder(
          padding: EdgeInsets.only(
            left: isWeb ? 16 : 12,
            right: isWeb ? 16 : 12,
            top: isWeb ? 16 : 12,
            bottom: isWeb ? 48 : 36,
          ),
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
              child: _buildSlotCard(slot, isWeb),
            );
          },
        );
      },
    );
  }

  /// Build individual slot card
  Widget _buildSlotCard(ParkingSlot slot, bool isWeb) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Find dimension details if available
    String? dimensionDisplay;
    if (slot.dimension != null) {
      final dimKey = slot.dimension!.replaceAll(' ', '');
      final dim = _carDimensions.firstWhere(
            (d) => d.name.replaceAll(' ', '') == dimKey,
        orElse: () => CarDimension(id: '', name: '', width: 0, height: 0, area: 0),
      );
      if (dim.width > 0 && dim.height > 0) {
        dimensionDisplay = '${dim.width}m × ${dim.height}m';
      } else {
        dimensionDisplay = slot.dimension;
      }
    }

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
          _buildSlotCardHeader(slot, isDark, isWeb),
          _buildSlotCardDetails(slot, dimensionDisplay, isDark, isWeb),
          SizedBox(height: isWeb ? 12 : 8),
          _buildSlotCardUsers(slot, isDark, isWeb),
        ],
      ),
    );
  }

  /// Build slot card header with icon and delete button
  Widget _buildSlotCardHeader(ParkingSlot slot, bool isDark, bool isWeb) {
    return Padding(
      padding: EdgeInsets.all(isWeb ? 16 : 12),
      child: Row(
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
                  slot.slotPriority,
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
    );
  }

  /// Build slot card details section
  Widget _buildSlotCardDetails(ParkingSlot slot, String? dimensionDisplay, bool isDark, bool isWeb) {
    if (dimensionDisplay == null && slot.vehicleCompatibility == null && slot.remarks == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWeb ? 16 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dimensionDisplay != null) ...[
            _buildDetailRow('Dimensions: ', dimensionDisplay, isDark, isWeb),
            const SizedBox(height: 4),
          ],
          if (slot.vehicleCompatibility != null) ...[
            _buildDetailRow('Level: ', slot.vehicleCompatibility!, isDark, isWeb),
            const SizedBox(height: 4),
          ],
          if (slot.remarks != null) ...[
            _buildDetailRow('Remarks: ', slot.remarks!, isDark, isWeb, maxLines: 2),
          ],
        ],
      ),
    );
  }

  /// Build detail row for slot information
  Widget _buildDetailRow(String label, String value, bool isDark, bool isWeb, {int maxLines = 1}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isWeb ? 13 : 11,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: isWeb ? 13 : 11,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Build slot card users section
  Widget _buildSlotCardUsers(ParkingSlot slot, bool isDark, bool isWeb) {
    return Expanded(
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
                    return _buildUserCard(user, isDark, isWeb);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build individual user card
  Widget _buildUserCard(AllottedUser user, bool isDark, bool isWeb) {
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
            ],
          ),
        ],
      ),
    );
  }

  /// Build floating action button
  Widget _buildFloatingActionButton() {
    return FloatingActionButton.extended(
      onPressed: _showAddSlotDialog,
      backgroundColor: Colors.blue,
      icon: const Icon(Icons.add, color: Colors.white),
      label: const Text(
        'Add Slot',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

/// Model for parking slot data
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

/// Model for allotted user data
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

/// Model for car dimension data
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
