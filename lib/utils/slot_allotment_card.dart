import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../viewModel/bookingBackend.dart';

class SlotAllotmentWidget extends StatefulWidget {
  final String requestId;
  final String? vehicleType;
  final Map<String, dynamic> requestData;
  final Function() onSlotsRefresh;
  final bool isDesktop;

  const SlotAllotmentWidget({
    Key? key,
    required this.requestId,
    required this.vehicleType,
    required this.requestData,
    required this.onSlotsRefresh,
    this.isDesktop = false,
  }) : super(key: key);

  @override
  State<SlotAllotmentWidget> createState() => _SlotAllotmentWidgetState();
}

class _SlotAllotmentWidgetState extends State<SlotAllotmentWidget> {
  List<Map<String, dynamic>> _availableSlots = [];
  bool _isLoadingSlots = false;
  String? _selectedSlotId;
  final BookingBackend _bookingBackend = BookingBackend();

  // Booking state
  Map<String, dynamic>? _userTodayBooking;
  bool _isLoadingBooking = false;

  @override
  void initState() {
    super.initState();
    _loadUserTodayBooking();
    _loadAvailableSlots();
  }

  String getDisplayNameFromEmail(String email) {
    final usernamePart = email.split('@').first;
    final words = usernamePart.split('.').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).toList();
    return words.join(' ');
  }

  Future<void> _loadUserTodayBooking() async {
    setState(() {
      _isLoadingBooking = true;
    });

    try {
      final userEmail = widget.requestData['email'] ?? '';
      final todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Check if user has any booking for today
      final todayBookingQuery = await FirebaseFirestore.instance
          .collection('Bookings')
          .doc(todayDateStr)
          .collection('BookedToday')
          .where('bookedBy', isEqualTo: userEmail)
          .get();

      if (todayBookingQuery.docs.isNotEmpty) {
        final doc = todayBookingQuery.docs.first;
        setState(() {
          _userTodayBooking = {
            'slotId': doc.id,
            'bookingData': doc.data(),
            'exists': true,
          };
        });
      } else {
        setState(() {
          _userTodayBooking = null;
        });
      }
    } catch (e) {
      print('Error loading user today booking: $e');
      setState(() {
        _userTodayBooking = null;
      });
    } finally {
      setState(() {
        _isLoadingBooking = false;
      });
    }
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

  Future<void> _allotSlot() async {
    if (_selectedSlotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a slot first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final userEmail = widget.requestData['email'] ?? '';
    final userName = getDisplayNameFromEmail(userEmail);
    final vehicleType = widget.requestData['vehicleType'] ?? '';

    // Store the selected slot ID before clearing it
    final selectedSlotId = _selectedSlotId!;

    // Clear the selected slot immediately to prevent dropdown errors
    setState(() {
      _selectedSlotId = null;
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

      Navigator.of(context).pop(); // Close loading dialog

      if (bookingResult['success'] == true) {
        // Refresh both slots and bookings
        await Future.wait([
          _loadAvailableSlots(),
          _loadUserTodayBooking(),
        ]);

        // Call the callback to refresh parent data
        widget.onSlotsRefresh();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Slot $selectedSlotId allotted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // If booking failed, restore the selection
        setState(() {
          _selectedSlotId = selectedSlotId;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(bookingResult['message'] ?? 'Booking failed'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog

      // If there's an error, restore the selection
      setState(() {
        _selectedSlotId = selectedSlotId;
      });

      print('Error allotting slot: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to allot slot: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Build the allotted status display
// ✅ REPLACE THIS ENTIRE METHOD:
  Widget _buildAllottedStatus(Map<String, dynamic> bookingInfo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slotId = bookingInfo['slotId'] as String;
    final bookingData = bookingInfo['bookingData'] as Map<String, dynamic>;
    final vehicleType = bookingData['vehicleType'] as String? ?? widget.vehicleType ?? 'Unknown';

    return Container(
      padding: EdgeInsets.all(widget.isDesktop ? 12 : 16),
      decoration: BoxDecoration(
        // Theme-aware success colors
        gradient: isDark
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF064E3B), // Dark green
            const Color(0xFF065F46), // Slightly lighter
            const Color(0xFF064E3B).withOpacity(0.8),
          ],
          stops: const [0.0, 0.6, 1.0],
        )
            : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF0FDF4), // Light green
            const Color(0xFFDCFCE7), // Slightly different shade
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? const Color(0xFF10B981).withOpacity(0.4) // Emerald border for dark
              : const Color(0xFF84CC16), // Lime border for light
          width: isDark ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0xFF10B981).withOpacity(0.2) // Glow effect for dark
                : const Color(0xFF84CC16).withOpacity(0.1),
            offset: const Offset(0, 4),
            blurRadius: isDark ? 12 : 6,
            spreadRadius: 0,
          ),
          if (isDark) ...[
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              offset: const Offset(0, 2),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF10B981).withOpacity(0.2)
                      : const Color(0xFF16A34A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.check_circle,
                  color: isDark
                      ? const Color(0xFF34D399) // Light emerald for dark mode
                      : const Color(0xFF16A34A), // Dark green for light mode
                  size: widget.isDesktop ? 18 : 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Slot Successfully Allotted',
                      style: TextStyle(
                        fontSize: widget.isDesktop ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF34D399) // Light emerald for dark mode
                            : const Color(0xFF16A34A), // Dark green for light mode
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          vehicleType.toUpperCase() == 'CAR' ? Icons.directions_car : Icons.motorcycle,
                          size: 14,
                          color: isDark
                              ? const Color(0xFF6EE7B7) // Lighter emerald
                              : const Color(0xFF22C55E), // Medium green
                        ),
                        const SizedBox(width: 4),
                        Text(
                          slotId.toUpperCase(),
                          style: TextStyle(
                            fontSize: widget.isDesktop ? 15 : 16,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFFF0FDF4) // Very light green
                                : const Color(0xFF15803D), // Darker green
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Cancel booking button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoadingBooking ? null : () => _cancelBooking(slotId),
              icon: _isLoadingBooking
                  ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : Icon(
                Icons.cancel_rounded,
                size: widget.isDesktop ? 16 : 18,
              ),
              label: Text(
                _isLoadingBooking ? 'Canceling...' : 'Cancel Booking',
                style: TextStyle(
                  fontSize: widget.isDesktop ? 13 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.red[300],
                padding: EdgeInsets.symmetric(
                  vertical: widget.isDesktop ? 8 : 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ✅ ADD THIS NEW METHOD:
  Future<void> _cancelBooking(String slotId) async {
    try {
      // Show confirmation dialog
      bool? confirmCancel = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Cancel Booking'),
            content: Text(
              'Are you sure you want to cancel your booking for slot ${slotId.toUpperCase()}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red[600],
                ),
                child: Text('Yes, Cancel'),
              ),
            ],
          );
        },
      );

      // If user confirmed cancellation
      if (confirmCancel == true) {
        setState(() {
          _isLoadingBooking = true;
        });

        final userEmail = widget.requestData['email'] ?? '';

        // Call the cancel booking method from backend
        final result = await _bookingBackend.cancelBookingForToday(
          slotId: slotId,
          userEmail: userEmail,
        );

        if (result['success']) {
          // Refresh both slots and bookings
          await Future.wait([
            _loadAvailableSlots(),
            _loadUserTodayBooking(),
          ]);

          // Call the callback to refresh parent data
          widget.onSlotsRefresh();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Booking cancelled successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message'] ?? 'Failed to cancel booking'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error canceling booking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error canceling booking: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBooking = false;
        });
      }
    }
  }




  List<DropdownMenuItem<String>> _buildSlotDropdownItems() {
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
                style: TextStyle(fontSize: 13, color: Color(0xFF718096)),
              ),
            ],
          ),
        ),
      ];
    }

    // Filter slots based on vehicle type
    final filteredSlots = _availableSlots.where((slot) {
      final slotVehicleType = slot['vehicleType'] as String? ?? 'BIKE';
      return widget.vehicleType == null ||
          slotVehicleType.toUpperCase() == widget.vehicleType!.toUpperCase();
    }).toList();

    if (filteredSlots.isEmpty) {
      return [
        DropdownMenuItem<String>(
          value: null,
          child: Row(
            children: [
              const Icon(Icons.warning, size: 14, color: Color(0xFFE53E3E)),
              const SizedBox(width: 6),
              Text(
                widget.vehicleType != null
                    ? 'No ${widget.vehicleType!.toLowerCase()} slots available'
                    : 'No slots available',
                style: const TextStyle(fontSize: 13, color: Color(0xFFE53E3E)),
              ),
            ],
          ),
        ),
      ];
    }

    return filteredSlots.map((slot) {
      final slotId = slot['slotId'] as String;
      final vehicleType = slot['vehicleType'] as String? ?? 'BIKE';
      final allotedTo = slot['alloted_to'] as List<dynamic>? ?? [];

      String allotedText = '';
      if (allotedTo.isNotEmpty) {
        allotedText = allotedTo.join(', ');
      }

      // In the SlotAllotmentWidget, update this part:
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
                    Row(
                      children: [
                        Text(
                          slotId,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        // ✅ ADD VEHICLE COMPATIBILITY FOR CAR SLOTS:
                        if (vehicleType == 'CAR' && slot['VehicleCompatibility'] != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              slot['VehicleCompatibility'],
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.indigo,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (allotedTo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Alloted to: $allotedText',
                        style: TextStyle(
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

  Widget _buildSelectedSlotDisplay(String? selectedSlotId) {
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
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      );
    }

    final slotVehicleType = selectedSlot['vehicleType'] as String? ?? 'BIKE';

    return Row(
      children: [
        Icon(
          slotVehicleType == 'CAR' ? Icons.directions_car : Icons.motorcycle,
          size: 14,
          color: slotVehicleType == 'CAR'
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            selectedSlotId,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  // Build the slot selection interface
  Widget _buildSlotSelectionInterface() {
    final isSlotSelected = _selectedSlotId != null;

    return Container(
      padding: EdgeInsets.all(widget.isDesktop ? 12 : 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Book Available Slot (Today) - ${widget.vehicleType ?? 'Unknown'}',
                style: TextStyle(
                  fontSize: widget.isDesktop ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadAvailableSlots,
                icon: Icon(
                  Icons.refresh,
                  size: widget.isDesktop ? 16 : 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                tooltip: 'Refresh slots',
                constraints: BoxConstraints(
                  maxWidth: widget.isDesktop ? 24 : 32,
                  maxHeight: widget.isDesktop ? 24 : 32,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          SizedBox(height: widget.isDesktop ? 8 : 12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: widget.isDesktop ? 12 : 16,
              vertical: widget.isDesktop ? 8 : 12,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                hint: Text(
                  'Select a ${widget.vehicleType?.toLowerCase() ?? 'vehicle'} slot',
                  style: TextStyle(
                    fontSize: widget.isDesktop ? 13 : 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _selectedSlotId,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 18,
                ),
                isExpanded: true,
                isDense: widget.isDesktop,
                items: _buildSlotDropdownItems(),
                selectedItemBuilder: (BuildContext context) {
                  return _buildSlotDropdownItems().map((item) {
                    return _buildSelectedSlotDisplay(item.value);
                  }).toList();
                },
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedSlotId = newValue;
                  });
                },
              ),
            ),
          ),
          SizedBox(height: widget.isDesktop ? 8 : 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isSlotSelected && !_isLoadingSlots ? _allotSlot : null,
                  icon: Icon(Icons.schedule, size: widget.isDesktop ? 16 : 20),
                  label: Text(
                    'Book Slot',
                    style: TextStyle(fontSize: widget.isDesktop ? 13 : 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    disabledBackgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: EdgeInsets.symmetric(vertical: widget.isDesktop ? 8 : 12),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoadingBooking) {
      return Container(
        padding: EdgeInsets.all(widget.isDesktop ? 12 : 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 8),
            Text(
              'Checking booking status...',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Check if the user has already booked a slot for today
    if (_userTodayBooking != null && _userTodayBooking!['exists'] == true) {
      // Show allotted status
      return _buildAllottedStatus(_userTodayBooking!);
    } else {
      // Show slot selection interface
      return _buildSlotSelectionInterface();
    }
  }
}