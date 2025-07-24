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
  bool _isLoading = true; // Single loading state
  String? _selectedSlotId;
  Map<String, dynamic>? _userTodayBooking;

  // Caching
  DateTime? _lastSlotFetch;
  static const Duration _slotCacheValidDuration = Duration(minutes: 1);

  final BookingBackend _bookingBackend = BookingBackend();

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // ✅ SINGLE INITIALIZATION - Batch all data fetching
  Future<void> _initializeData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 🔥 BATCH BOTH BOOKING CHECK AND SLOT LOADING
      final results = await Future.wait([
        _loadUserTodayBookingOptimized(),
        _loadAvailableSlotsOptimized(),
      ]);

      if (mounted) {
        setState(() {
          _userTodayBooking = results[0] as Map<String, dynamic>?;
          _availableSlots = results[1] as List<Map<String, dynamic>>;
          _lastSlotFetch = DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error initializing slot allotment data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ✅ OPTIMIZED BOOKING CHECK - Single query instead of collection scan
  Future<Map<String, dynamic>?> _loadUserTodayBookingOptimized() async {
    try {
      final userEmail = widget.requestData['email'] ?? '';
      if (userEmail.isEmpty) return null;

      final todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 🔥 QUERY ONLY TODAY'S BOOKINGS FOR THIS USER
      final bookingQuery = await FirebaseFirestore.instance
          .collection('Bookings')
          .doc(todayDateStr)
          .collection('BookedToday')
          .where('bookedBy', isEqualTo: userEmail)
          .limit(1) // Only need to know if ANY booking exists
          .get();

      if (bookingQuery.docs.isNotEmpty) {
        final doc = bookingQuery.docs.first;
        return {
          'slotId': doc.id,
          'bookingData': doc.data(),
          'exists': true,
        };
      }

      return null;
    } catch (e) {
      print('Error loading user today booking: $e');
      return null;
    }
  }

  // ✅ CACHED SLOT LOADING - Avoid unnecessary fetches
  Future<List<Map<String, dynamic>>> _loadAvailableSlotsOptimized() async {
    // Check cache validity
    if (_lastSlotFetch != null &&
        DateTime.now().difference(_lastSlotFetch!) < _slotCacheValidDuration &&
        _availableSlots.isNotEmpty) {
      return _availableSlots; // Return cached data
    }

    try {
      final slots = await _bookingBackend.getAvailableSlotsForToday();
      return slots;
    } catch (e) {
      print('Error loading available slots: $e');
      throw e;
    }
  }

  // ✅ SMART REFRESH - Only refresh if needed
  Future<void> _refreshSlots() async {
    // Don't refresh if recently fetched
    if (_lastSlotFetch != null &&
        DateTime.now().difference(_lastSlotFetch!) < Duration(seconds: 30)) {
      return;
    }

    try {
      final slots = await _loadAvailableSlotsOptimized();
      if (mounted) {
        setState(() {
          _availableSlots = slots;
          _lastSlotFetch = DateTime.now();
          // Clear selection if selected slot is no longer available
          if (_selectedSlotId != null &&
              !slots.any((slot) => slot['slotId'] == _selectedSlotId)) {
            _selectedSlotId = null;
          }
        });
      }
    } catch (e) {
      print('Error refreshing slots: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh slots'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // // ✅ OPTIMISTIC SLOT BOOKING - Immediate UI feedback
  // Future<void> _allotSlotOptimistic() async {
  //   if (_selectedSlotId == null) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('Please select a slot first'),
  //         backgroundColor: Colors.orange,
  //       ),
  //     );
  //     return;
  //   }
  //
  //   final userEmail = widget.requestData['email'] ?? '';
  //   final userName = getDisplayNameFromEmail(userEmail);
  //   final vehicleType = widget.requestData['vehicleType'] ?? '';
  //   final selectedSlotId = _selectedSlotId!;
  //
  //   // 🚀 OPTIMISTIC UPDATE - Immediate UI response
  //   final optimisticBooking = {
  //     'slotId': selectedSlotId,
  //     'bookingData': {
  //       'bookedBy': userEmail,
  //       'userName': userName,
  //       'vehicleType': vehicleType,
  //       'bookedAt': Timestamp.now(),
  //     },
  //     'exists': true,
  //   };
  //
  //   setState(() {
  //     _userTodayBooking = optimisticBooking;
  //     _selectedSlotId = null;
  //     // Remove the slot from available list immediately
  //     _availableSlots.removeWhere((slot) => slot['slotId'] == selectedSlotId);
  //   });
  //
  //   try {
  //     final bookingResult = await _bookingBackend.bookSlotForToday(
  //       slotId: selectedSlotId,
  //       vehicleType: vehicleType,
  //       userEmail: userEmail,
  //       userName: userName,
  //     );
  //
  //     if (bookingResult['success'] == true) {
  //       // Success - call refresh callback
  //       widget.onSlotsRefresh();
  //
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(
  //             content: Text('Slot $selectedSlotId booked successfully!'),
  //             backgroundColor: Colors.green,
  //             duration: Duration(seconds: 2),
  //           ),
  //         );
  //       }
  //     } else {
  //       // 🔄 REVERT OPTIMISTIC UPDATE on failure
  //       await _revertOptimisticUpdate();
  //
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(
  //             content: Text(bookingResult['message'] ?? 'Booking failed'),
  //             backgroundColor: Colors.orange,
  //           ),
  //         );
  //       }
  //     }
  //   } catch (e) {
  //     // 🔄 REVERT OPTIMISTIC UPDATE on error
  //     await _revertOptimisticUpdate();
  //
  //     print('Error allotting slot: $e');
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Failed to book slot: ${e.toString()}'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   }
  // }

  // ✅ REVERT OPTIMISTIC UPDATES
  Future<void> _revertOptimisticUpdate() async {
    try {
      // Re-fetch actual current state
      final results = await Future.wait([
        _loadUserTodayBookingOptimized(),
        _loadAvailableSlotsOptimized(),
      ]);

      if (mounted) {
        setState(() {
          _userTodayBooking = results[0] as Map<String, dynamic>?;
          _availableSlots = results[1] as List<Map<String, dynamic>>;
        });
      }
    } catch (e) {
      print('Error reverting optimistic update: $e');
    }
  }

  // ✅ OPTIMISTIC CANCEL BOOKING
  Future<void> _cancelBookingOptimistic(String slotId) async {
    try {
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
                style: TextButton.styleFrom(foregroundColor: Colors.red[600]),
                child: Text('Yes, Cancel'),
              ),
            ],
          );
        },
      );

      if (confirmCancel == true) {
        // 🚀 OPTIMISTIC UPDATE - Clear booking immediately
        setState(() {
          _userTodayBooking = null;
        });

        // Trigger slot refresh to show the newly available slot
        _refreshSlots();

        final userEmail = widget.requestData['email'] ?? '';
        final result = await _bookingBackend.cancelBookingForToday(
          slotId: slotId,
          userEmail: userEmail,
        );

        if (result['success']) {
          widget.onSlotsRefresh();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Booking cancelled successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          // 🔄 REVERT on failure
          await _revertOptimisticUpdate();

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
      // 🔄 REVERT on error
      await _revertOptimisticUpdate();

      print('Error canceling booking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error canceling booking: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
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
            SizedBox(height: 12),
            Text(
              'Loading slot options...',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Check if user already has a booking
    if (_userTodayBooking != null && _userTodayBooking!['exists'] == true) {
      return _buildAllottedStatus(_userTodayBooking!);
    } else {
      return _buildSlotSelectionInterface();
    }
  }

  // Update the refresh button to use smart refresh
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
              Spacer(),
              IconButton(
                onPressed: _refreshSlots, // Use smart refresh
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
                  onPressed:  null,
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
            ],
          ),
        ],
      ),
    );
  }

  // ✅ IMPROVED ALLOTTED STATUS WITH OPTIMISTIC CANCEL
  Widget _buildAllottedStatus(Map<String, dynamic> bookingInfo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slotId = bookingInfo['slotId'] as String;
    final bookingData = bookingInfo['bookingData'] as Map<String, dynamic>;
    final vehicleType = bookingData['vehicleType'] as String? ?? widget.vehicleType ?? 'Unknown';

    return Container(
      padding: EdgeInsets.all(widget.isDesktop ? 12 : 16),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF064E3B),
            const Color(0xFF065F46),
            const Color(0xFF064E3B).withOpacity(0.8),
          ],
          stops: const [0.0, 0.6, 1.0],
        )
            : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF0FDF4),
            const Color(0xFFDCFCE7),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? const Color(0xFF10B981).withOpacity(0.4)
              : const Color(0xFF84CC16),
          width: isDark ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0xFF10B981).withOpacity(0.2)
                : const Color(0xFF84CC16).withOpacity(0.1),
            offset: const Offset(0, 4),
            blurRadius: isDark ? 12 : 6,
            spreadRadius: 0,
          ),
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
                      ? const Color(0xFF34D399)
                      : const Color(0xFF16A34A),
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
                      'Slot Successfully Booked',
                      style: TextStyle(
                        fontSize: widget.isDesktop ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF34D399)
                            : const Color(0xFF16A34A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          vehicleType.toUpperCase() == 'CAR'
                              ? Icons.directions_car
                              : Icons.motorcycle,
                          size: 14,
                          color: isDark
                              ? const Color(0xFF6EE7B7)
                              : const Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          slotId.toUpperCase(),
                          style: TextStyle(
                            fontSize: widget.isDesktop ? 15 : 16,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFFF0FDF4)
                                : const Color(0xFF15803D),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _cancelBookingOptimistic(slotId),
              icon: Icon(
                Icons.cancel_rounded,
                size: widget.isDesktop ? 16 : 18,
              ),
              label: Text(
                'Cancel Booking',
                style: TextStyle(
                  fontSize: widget.isDesktop ? 13 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
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

  // Keep your existing dropdown methods but with better loading states
  List<DropdownMenuItem<String>> _buildSlotDropdownItems() {
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
              const Icon(Icons.info_outline, size: 14, color: Color(0xFF2D3748)),
              const SizedBox(width: 6),
              Text(
                widget.vehicleType != null
                    ? 'No ${widget.vehicleType!.toLowerCase()} slots available'
                    : 'No slots available',
                style: const TextStyle(fontSize: 13, color: Color(0xFF2D3748)),
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

  // Keep your existing methods
  String getDisplayNameFromEmail(String email) {
    final usernamePart = email.split('@').first;
    final words = usernamePart.split('.').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).toList();
    return words.join(' ');
  }
}