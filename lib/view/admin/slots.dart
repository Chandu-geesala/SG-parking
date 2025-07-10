import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:park_sg/viewModel/slotBackend.dart';

class DataUploadUI extends StatefulWidget {
  const DataUploadUI({Key? key}) : super(key: key);

  @override
  State<DataUploadUI> createState() => _DataUploadUIState();
}

class _DataUploadUIState extends State<DataUploadUI> {
  bool isProcessing = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _pickAndProcessFile({bool clearExisting = false}) async {
    setState(() {
      isProcessing = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
      );

      if (result == null || result.files.single.path == null) {
        _showSnackBar("No file selected", Colors.orange);
        setState(() {
          isProcessing = false;
        });
        return;
      }

      final path = result.files.single.path!;
      final log = await processExcelOrCsvFile(path, clearExisting: clearExisting);

      // Parse the log to show appropriate message
      if (log.contains("Upload Complete")) {
        final lines = log.split('\n');
        final uploadedCount = lines.firstWhere((line) => line.contains('Uploaded:')).split(':')[1].trim();
        String action = clearExisting ? "replaced" : "uploaded";
        _showSnackBar("Successfully $action $uploadedCount slots", Colors.green);
      } else {
        _showSnackBar("Upload failed: ${log.split('\n').first}", Colors.red);
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
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              size: 48,
              color: Colors.blue[600],
            ),
            const SizedBox(height: 16),
            Text(
              'Upload Slots Data',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select an Excel (.xlsx) or CSV file to upload parking slots data',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Two buttons side by side
            Row(
              children: [
                // Upload Button (Merge with existing)
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: isProcessing ? null : () => _pickAndProcessFile(clearExisting: false),
                      icon: isProcessing
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : const Icon(Icons.upload_file, size: 20),
                      label: Text(
                        isProcessing ? 'Processing...' : 'Upload & Merge',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Replace Button (Clear and upload fresh)
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
                        backgroundColor: Colors.orange[600],
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
            const SizedBox(height: 12),
            // Help text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue[600]),
                      const SizedBox(width: 8),
                      Text(
                        'Button Guide:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Upload & Merge: Adds new slots and updates existing ones\n'
                        '• Replace All: Clears all existing slots and uploads fresh data',
                    style: TextStyle(
                      color: Colors.blue[600],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_parking,
                  color: Colors.blue[600],
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Parking Slots Data',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 500,
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('Slots').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading data',
                            style: TextStyle(color: Colors.red[600]),
                          ),
                        ],
                      ),
                    );
                  }

                  final slots = snapshot.data?.docs ?? [];

                  if (slots.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No slots data available',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Upload a file to see slots data here',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: slots.length,
                    itemBuilder: (context, index) {
                      final slot = slots[index];
                      final data = slot.data() as Map<String, dynamic>;
                      final slotId = data['slotId'] ?? slot.id;

                      final vehicleType = data['vehicleType'] ?? '';
                      final slotPriority = data['slotPriority'] ?? '';
                      final allotedTo = data['alloted_to'] as List<dynamic>? ?? [];
                      final vehicleCompatibility = data['VehicleCompatibility'] ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getVehicleTypeColor(vehicleType),
                            child: Icon(
                              _getVehicleTypeIcon(vehicleType),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            'Slot: $slotId',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _buildChip(vehicleType, Colors.blue),
                                  _buildChip(slotPriority, Colors.orange),
                                  if (vehicleType == 'CAR' && vehicleCompatibility.isNotEmpty)
                                    _buildChip(vehicleCompatibility, Colors.purple),
                                ],
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _showSlotDetailsBottomSheet(context, slotId, data, allotedTo),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Slots Data Management'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey[300],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildUploadSection(),
            const SizedBox(height: 16),
            _buildSlotsDataSection(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSlotBottomSheet,
        backgroundColor: Colors.blue[600],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
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



class AddSlotBottomSheet extends StatefulWidget {

  final Future<List<Map<String, dynamic>>> Function() getAvailableUsers;

  const AddSlotBottomSheet({Key? key, required this.getAvailableUsers}) : super(key: key);



  @override
  _AddSlotBottomSheetState createState() => _AddSlotBottomSheetState();
}

class _AddSlotBottomSheetState extends State<AddSlotBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _slotIdController = TextEditingController();
  String _selectedVehicleType = 'CAR';
  String _selectedVehicleCompatibility = '';
  bool _isAllocated = false;
  List<Map<String, dynamic>> _allocatedPersons = [];
  List<Map<String, dynamic>> _availableUsers = [];

  final List<String> _vehicleTypes = ['CAR', 'BIKE'];
  final List<String> _compatibilityOptions = ['UPPER', 'LOWER'];

  @override
  void initState() {
    super.initState();
    _loadAvailableUsers();
  }

  Future<void> _loadAvailableUsers() async {
    final users = await widget.getAvailableUsers();
    setState(() {
      _availableUsers = users;
    });
  }



    @override
  void dispose() {
    _slotIdController.dispose();
    super.dispose();
  }

  void _addPerson() async {
    setState(() {
      _allocatedPersons.add({
        'name': '',
        'email': '',
        'alloted_date': DateTime.now().toIso8601String(),
      });
    });
    // Refresh available users when adding a new person
    await _loadAvailableUsers();
  }

  void _removePerson(int index) {
    setState(() {
      _allocatedPersons.removeAt(index);
    });
  }

  void _updatePersonData(int index, String field, String value) {
    setState(() {
      _allocatedPersons[index][field] = value;
    });
  }

  String _determinePriority() {
    if (!_isAllocated || _allocatedPersons.isEmpty) {
      return 'TEMPORARY';
    } else if (_allocatedPersons.length > 1) {
      return 'HYBRID';
    } else {
      return 'PERMANENT';
    }
  }







  void _saveSlot() async {
    if (_formKey.currentState!.validate()) {
      if (_isAllocated) {
        if (_allocatedPersons.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please add at least one person or turn off allocation'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        bool hasValidPersons = _allocatedPersons.every((person) =>
        person['name'].toString().trim().isNotEmpty &&
            person['email'].toString().trim().isNotEmpty
        );

        if (!hasValidPersons) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please fill all allocated person details'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final slotId = _slotIdController.text.trim();

      // Check if slot ID already exists
      try {
        final existingSlot = await FirebaseFirestore.instance
            .collection('Slots')
            .doc(slotId)
            .get();

        if (existingSlot.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Slot ID already exists. Please choose a different ID.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking slot ID: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final slotData = <String, dynamic>{

        'vehicleType': _selectedVehicleType,
        'slotPriority': _determinePriority(),
        'alloted_to': _isAllocated ? _allocatedPersons : [],
        'created_at': DateTime.now().toIso8601String(),
      };

// Only add VehicleCompatibility if it's a CAR and has a value
      if (_selectedVehicleType == 'CAR' && _selectedVehicleCompatibility.isNotEmpty) {
        slotData['VehicleCompatibility'] = _selectedVehicleCompatibility;
      }

      // Save to Firestore
      try {
        await FirebaseFirestore.instance
            .collection('Slots')
            .doc(slotId)
            .set(slotData);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Slot added successfully'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding slot: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }




  @override
  Widget build(BuildContext context) {


    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
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
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, color: Colors.blue[600], size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Add New Slot',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),


          // Form Content
            Expanded(
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Slot ID
                              TextFormField(
                                controller: _slotIdController,
                                decoration: InputDecoration(
                                  labelText: 'Slot ID',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.tag),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter slot ID';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // Vehicle Type
                              Text(
                                'Vehicle Type',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 8),



                              DropdownButtonFormField<String>(
                                value: _selectedVehicleType,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: Icon(
                                    _selectedVehicleType == 'CAR' ? Icons.directions_car : Icons.two_wheeler,
                                  ),
                                ),
                                items: _vehicleTypes.map((type) {
                                  return DropdownMenuItem(
                                    value: type,
                                    child: Text(type),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedVehicleType = value!;
                                    // Reset compatibility when changing vehicle type
                                    if (value != 'CAR') {
                                      _selectedVehicleCompatibility = '';
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 16),

                              // Vehicle Compatibility
                              // Vehicle Compatibility
                              if (_selectedVehicleType == 'CAR') ...[
                                Text(
                                  'Vehicle Compatibility',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 8),



                                DropdownButtonFormField<String>(
                                  value: _selectedVehicleCompatibility.isEmpty ? null : _selectedVehicleCompatibility,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    prefixIcon: const Icon(Icons.electric_bolt),
                                    hintText: 'Select compatibility',
                                  ),
                                  items: ['UPPER', 'LOWER'].map((option) {
                                    return DropdownMenuItem(
                                      value: option,
                                      child: Text(option),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedVehicleCompatibility = value ?? '';
                                    });
                                  },
                                  validator: (value) {
                                    // Only validate if it's a CAR - no validation needed for BIKE
                                    if (_selectedVehicleType == 'CAR' && (value == null || value.isEmpty)) {
                                      return 'Please select vehicle compatibility for CAR';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 24),
                              ],









                              const SizedBox(height: 24),

                              // Allocation Section
                              Row(
                                children: [
                                  Text(
                                    'Allocate to Person(s)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: _isAllocated,
                                    onChanged: (value) {
                                      setState(() {
                                        _isAllocated = value;
                                        if (!value) {
                                          _allocatedPersons.clear();
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),

                              if (_isAllocated) ...[
                                const SizedBox(height: 16),

                                // Add Person Button
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _addPerson,
                                    icon: const Icon(Icons.person_add),
                                    label: const Text('Add Person'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Allocated Persons List
                                ...List.generate(_allocatedPersons.length, (index) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey[200]!),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Person ${index + 1}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
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


                                        // Replace the TextFormField widgets for Name and Email with this dropdown:
                                        DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            labelText: 'Select User',
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                          isExpanded: true, // This prevents overflow
                                          value: _allocatedPersons[index]['email']?.isEmpty ?? true
                                              ? null
                                              : _allocatedPersons[index]['email'],
                                          items: _availableUsers.where((user) {
                                            // Filter out emails that are already selected in other dropdowns
                                            final currentEmail = _allocatedPersons[index]['email'];
                                            final otherSelectedEmails = _allocatedPersons
                                                .asMap()
                                                .entries
                                                .where((entry) => entry.key != index) // Exclude current index
                                                .map((entry) => entry.value['email'])
                                                .where((email) => email != null && email.isNotEmpty)
                                                .toSet();

                                            // Show user if it's either the currently selected one or not selected elsewhere
                                            return user['email'] == currentEmail || !otherSelectedEmails.contains(user['email']);
                                          }).map((user) {
                                            return DropdownMenuItem<String>(
                                              value: user['email'],
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: Text(
                                                  '${user['name']} (${user['email']})',
                                                  overflow: TextOverflow.ellipsis, // Handle long text
                                                  style: const TextStyle(fontSize: 14),
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
                                          validator: (value) {
                                            if (_isAllocated && (value == null || value.isEmpty)) {
                                              return 'Please select a user';
                                            }
                                            return null;
                                          },
                                        ),




                                      ],
                                    ),
                                  );
                                }),

                                if (_allocatedPersons.length > 1)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.orange[200]!),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline, color: Colors.orange[600]),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Priority will be set to HYBRID (multiple allocations)',
                                            style: TextStyle(color: Colors.orange[700]),
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
                    );
                  },
                ),
              ),
            ),




            // Save Button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saveSlot,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Slot',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );



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
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red[600], size: 24),
              const SizedBox(width: 8),
              const Text('Delete Slot'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this slot?',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Slot ID: ${widget.slotId}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vehicle Type: ${widget.data['vehicleType'] ?? 'Unknown'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    if (_allocatedPersons.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Allocated to: ${_allocatedPersons.length} person(s)',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red[600],
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
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
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
      setState(() {
        _isLoading = true;
      });

      try {
        await FirebaseFirestore.instance
            .collection('Slots')
            .doc(widget.slotId)
            .delete();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Slot ${widget.slotId} deleted successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        widget.onSlotUpdated();
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting slot: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }




  void _addPerson() async {
    setState(() {
      _allocatedPersons.add({
        'name': '',
        'email': '',
        'alloted_date': DateTime.now().toIso8601String(),
      });
    });
    await _loadAvailableUsers();
  }

  void _removePerson(int index) {
    setState(() {
      _allocatedPersons.removeAt(index);
    });
    _loadAvailableUsers();
  }

  void _updatePersonData(int index, String field, String value) {
    setState(() {
      _allocatedPersons[index][field] = value;
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

  Future<void> _updateSlot() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Validate that all persons have valid data
      bool hasValidPersons = _allocatedPersons.every((person) =>
      person['name'].toString().trim().isNotEmpty &&
          person['email'].toString().trim().isNotEmpty);

      if (_allocatedPersons.isNotEmpty && !hasValidPersons) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill all allocated person details or remove empty entries'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Update slot data
      final updatedData = Map<String, dynamic>.from(widget.data);
      updatedData['alloted_to'] = _allocatedPersons;
      updatedData['slotPriority'] = _determinePriority();
      updatedData['updated_at'] = DateTime.now().toIso8601String();

      await FirebaseFirestore.instance
          .collection('Slots')
          .doc(widget.slotId)
          .update(updatedData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Slot updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onSlotUpdated();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating slot: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
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
              color: Colors.grey[300],
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
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
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
                          color: Colors.grey[700],
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
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No allocation',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                  // Replace the existing allocated persons display section in SlotDetailsBottomSheet
// with this improved version that shows existing user details properly

                    ...List.generate(_allocatedPersons.length, (index) {
                      final person = _allocatedPersons[index];
                      final hasExistingData = person['name']?.toString().trim().isNotEmpty == true &&
                          person['email']?.toString().trim().isNotEmpty == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Person ${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
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
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue[200]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.person,
                                          size: 16,
                                          color: Colors.blue[600],
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            person['name'] ?? 'Unknown',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue[700],
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
                                          color: Colors.blue[600],
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            person['email'] ?? 'Unknown',
                                            style: TextStyle(
                                              color: Colors.blue[600],
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
                              // Show dropdown for selecting new user
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  labelText: 'Select User',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
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
                                        style: const TextStyle(fontSize: 14),
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

                            // Always show allocation date if available
                            const SizedBox(height: 8),
                            if (person['alloted_date'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green[100]!),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      size: 14,
                                      color: Colors.green[600],
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Allotted: ${_formatDate(person['alloted_date'])}',
                                      style: TextStyle(
                                        color: Colors.green[700],
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
            child: Row(
              children: [
                // Delete FAB-style Button
                Material(
                  color: Colors.red[50],
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
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _isLoading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                              : const Icon(Icons.save_rounded, size: 22),
                          const SizedBox(width: 10),
                          Text(_isLoading ? 'Updating...' : 'Update Slot',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                letterSpacing: 0.2,
                              )),

                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )




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