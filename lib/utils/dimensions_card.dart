import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CarSlotDimensionsWidget extends StatefulWidget {
  const CarSlotDimensionsWidget({Key? key}) : super(key: key);

  @override
  State<CarSlotDimensionsWidget> createState() => _CarSlotDimensionsWidgetState();
}

class _CarSlotDimensionsWidgetState extends State<CarSlotDimensionsWidget> {
  List<SlotDimension> _dimensions = [];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Add this line
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDimensionsFromFirestore();
  }

  Future<void> _loadDimensionsFromFirestore() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final snapshot = await _firestore
          .collection('dimensions')
          .orderBy(FieldPath.documentId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _dimensions.clear();

          for (int i = 0; i < snapshot.docs.length; i++) {
            final doc = snapshot.docs[i];
            final data = doc.data();

            final dimension = SlotDimension(
              id: 'dim${i + 1}',
              name: 'Dimension ${i + 1}',
            );

            // Set the values from Firestore
            dimension.widthController.text = data['width']?.toString() ?? '';
            dimension.heightController.text = data['height']?.toString() ?? '';

            _dimensions.add(dimension);
          }
        });
      }
    } catch (e) {
      _showSnackBar('Error loading dimensions: ${e.toString()}', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }



  @override
  void dispose() {
    for (final dimension in _dimensions) {
      dimension.dispose();
    }
    super.dispose();
  }

  void _addDimension() {
    setState(() {
      _dimensions.add(SlotDimension(
        id: 'dim${_dimensions.length + 1}',
        name: 'Dimension ${_dimensions.length + 1}',
      ));
    });
    HapticFeedback.lightImpact();
  }


  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(isWide ? 20.0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Simple Header
                Row(
                  children: [
                    Icon(
                      Icons.straighten,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Car Slot Dimensions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    // Add button
                    TextButton.icon(
                      onPressed: _addDimension,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                    ),
                  ],
                ),

                if (_dimensions.isNotEmpty) ...[
                  const SizedBox(height: 16),

                  // Dimensions List
                  ...List.generate(_dimensions.length, (index) {
                    final dimension = _dimensions[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? colorScheme.surfaceVariant.withOpacity(0.3)
                            : colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Dimension name
                          SizedBox(
                            width: isWide ? 100 : 70,
                            child: Text(
                              dimension.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: isWide ? 14 : 12,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Width input
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: TextFormField(
                                controller: dimension.widthController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                ],
                                style: TextStyle(
                                  fontSize: isWide ? 14 : 12,
                                  color: colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Width (m)',
                                  hintStyle: TextStyle(
                                    fontSize: isWide ? 12 : 10,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                      color: colorScheme.outline.withOpacity(0.5),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                      color: colorScheme.outline.withOpacity(0.3),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Height input
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: TextFormField(
                                controller: dimension.heightController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                ],
                                style: TextStyle(
                                  fontSize: isWide ? 14 : 12,
                                  color: colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Height (m)',
                                  hintStyle: TextStyle(
                                    fontSize: isWide ? 12 : 10,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                      color: colorScheme.outline.withOpacity(0.5),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                      color: colorScheme.outline.withOpacity(0.3),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Save button
                          SizedBox(
                            height: 32,
                            child: ElevatedButton(
                              onPressed: () => _saveDimension(index),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                minimumSize: Size.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: Text(
                                'Save',
                                style: TextStyle(
                                  fontSize: isWide ? 12 : 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 4),

                          // Delete button
                          SizedBox(
                            height: 32,
                            width: 32,
                            child: IconButton(
                              onPressed: () => _removeDimension(index),
                              icon: Icon(
                                Icons.delete_outline,
                                color: colorScheme.error,
                                size: 16,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 12),


                ] else ...[
                  const SizedBox(height: 12),

                  // Empty state
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surfaceVariant.withOpacity(0.3)
                          : colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.straighten,
                          size: 32,
                          color: colorScheme.onSurface.withOpacity(0.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No dimensions defined',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Click "Add" to define slot dimensions',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveDimension(int index) async {
    final dimension = _dimensions[index];

    if (!dimension.isValid()) {
      _showSnackBar('Please enter valid width and height for ${dimension.name}', Colors.red);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dimensionData = {
        'width': double.parse(dimension.widthController.text),
        'height': double.parse(dimension.heightController.text),
        'area': dimension.getArea(),
      };

      await _firestore
          .collection('dimensions')
          .doc(dimension.name.replaceAll(' ', '')) // "Dimension1", "Dimension2", etc.
          .set(dimensionData, SetOptions(merge: true));

      _showSnackBar('${dimension.name} saved successfully!', Colors.green);
    } catch (e) {
      _showSnackBar('Error saving ${dimension.name}: ${e.toString()}', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  // 6. Replace the _removeDimension method with this:
  void _removeDimension(int index) async {
    if (index >= 0 && index < _dimensions.length) {
      final dimensionToDelete = _dimensions[index];

      setState(() {
        _isLoading = true;
      });

      try {
        // Delete from Firestore
        await _firestore
            .collection('dimensions')
            .doc(dimensionToDelete.name.replaceAll(' ', ''))
            .delete();

        setState(() {
          _dimensions[index].dispose();
          _dimensions.removeAt(index);

          // Rename remaining dimensions and update Firestore
          _renameAndUpdateRemainingDimensions();
        });

        _showSnackBar('${dimensionToDelete.name} deleted successfully!', Colors.green);
        HapticFeedback.mediumImpact();
      } catch (e) {
        _showSnackBar('Error deleting dimension: ${e.toString()}', Colors.red);
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 7. Add this new method to handle renaming after deletion:
  Future<void> _renameAndUpdateRemainingDimensions() async {
    final batch = _firestore.batch();

    // Get all existing documents to delete them
    final existingDocs = await _firestore.collection('dimensions').get();
    for (final doc in existingDocs.docs) {
      batch.delete(doc.reference);
    }

    // Create new documents with correct names
    for (int i = 0; i < _dimensions.length; i++) {
      final oldName = _dimensions[i].name;
      final newName = 'Dimension ${i + 1}';
      final newId = 'dim${i + 1}';

      _dimensions[i].updateName(newName);
      _dimensions[i].updateId(newId);

      // Only save if the dimension has valid data
      if (_dimensions[i].isValid()) {
        final dimensionData = {
          'width': double.parse(_dimensions[i].widthController.text),
          'height': double.parse(_dimensions[i].heightController.text),
          'area': _dimensions[i].getArea(),

        };

        final docRef = _firestore
            .collection('dimensions')
            .doc(newName.replaceAll(' ', ''));

        batch.set(docRef, dimensionData);
      }
    }

    try {
      await batch.commit();
    } catch (e) {
      print('Error renaming dimensions: $e');
    }
  }



}

class SlotDimension {
  String id;
  String name;
  final TextEditingController widthController;
  final TextEditingController heightController;
  List<SlotDimension> _dimensions = [];

  SlotDimension({
    required this.id,
    required this.name,
  })  : widthController = TextEditingController(),
        heightController = TextEditingController();

  void updateName(String newName) {
    name = newName;
  }

  void updateId(String newId) {
    id = newId;
  }

  bool isValid() {
    final width = double.tryParse(widthController.text);
    final height = double.tryParse(heightController.text);
    return width != null && height != null && width > 0 && height > 0;
  }

  double getArea() {
    final width = double.tryParse(widthController.text) ?? 0;
    final height = double.tryParse(heightController.text) ?? 0;
    return width * height;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'width': double.tryParse(widthController.text) ?? 0,
      'height': double.tryParse(heightController.text) ?? 0,
      'area': getArea(),
    };
  }






  // 8. Add this method to load dimensions from Firestore:


  void dispose() {
    widthController.dispose();
    heightController.dispose();
  }
}