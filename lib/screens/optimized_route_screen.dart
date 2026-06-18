import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import 'customer_detail_screen.dart';

class OptimizedRouteScreen extends StatefulWidget {
  final Map<String, dynamic> route;
  final List<Map<String, dynamic>> customers;

  const OptimizedRouteScreen({
    super.key,
    required this.route,
    required this.customers,
  });

  @override
  State<OptimizedRouteScreen> createState() => _OptimizedRouteScreenState();
}

class _OptimizedRouteScreenState extends State<OptimizedRouteScreen> {
  final MapController _mapController = MapController();

  bool _isOptimizing = false;
  bool _isLoadingLocation = false;
  String? _error;

  Position? _currentPosition;
  List<Map<String, dynamic>> _optimizedStops = [];
  List<LatLng> _routePolyline = [];
  StreamSubscription<Position>? _locationSubscription;
  LatLng? _currentLatLng;

  // Track which stops are completed
  final Set<int> _completedStops = {};

  @override
  void initState() {
    super.initState();
    // Initialize with original customer order
    _optimizedStops = List<Map<String, dynamic>>.from(widget.customers);
    _initLocationAndOptimize();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLocationAndOptimize() async {
    setState(() => _isLoadingLocation = true);

    try {
      // Request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _error = 'Location permission denied. Showing original route order.';
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Location permission permanently denied. Please enable in Settings.';
          _isLoadingLocation = false;
        });
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      setState(() {
        _currentPosition = position;
        _currentLatLng = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
      });

      // Start live location tracking
      _startLocationTracking();

      // Optimize route with current position
      await _optimizeRoute();
    } catch (e) {
      setState(() {
        _error = 'Could not get location: ${e.toString().split(':').first}. Showing original order.';
        _isLoadingLocation = false;
      });
    }
  }

  void _startLocationTracking() {
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20, // Update every 20 metres
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _currentLatLng = LatLng(position.latitude, position.longitude);
        });
      }
    });
  }

  Future<void> _optimizeRoute() async {
    if (_currentPosition == null) return;

    // Filter customers with valid coordinates
    final validCustomers = widget.customers.where((c) {
      final customer = c['customer'] ?? c;
      final lat = double.tryParse(customer['latitude']?.toString() ?? '');
      final lng = double.tryParse(customer['longitude']?.toString() ?? '');
      return lat != null && lng != null && lat != 0 && lng != 0;
    }).toList();

    if (validCustomers.isEmpty) {
      setState(() {
        _error = 'No customers have GPS coordinates. Contact admin to add coordinates.';
      });
      return;
    }

    setState(() {
      _isOptimizing = true;
      _error = null;
    });

    try {
      final customerIds = validCustomers.map((c) {
        final customer = c['customer'] ?? c;
        final id = customer['id'];
        return id is int ? id : int.tryParse(id?.toString() ?? '0') ?? 0;
      }).where((id) => id != 0).toList();

      final result = await ApiService.optimizeRoute(
        customerIds: customerIds,
        startingLatitude: _currentPosition!.latitude,
        startingLongitude: _currentPosition!.longitude,
      );

      if (result != null && result['stops'] != null) {
        final stops = result['stops'] as List;

        // Reorder customers based on optimization result
        final List<Map<String, dynamic>> reordered = [];
        for (final stop in stops) {
          final customerId = stop['customerId'];
          final match = widget.customers.firstWhere(
            (c) {
              final customer = c['customer'] ?? c;
              return customer['id'] == customerId;
            },
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            reordered.add({...match, '_sequence': stop['sequence']});
          }
        }

        // Add customers without coordinates at the end
        for (final c in widget.customers) {
          final customer = c['customer'] ?? c;
          final alreadyAdded = reordered.any((r) {
            final rc = r['customer'] ?? r;
            return rc['id'] == customer['id'];
          });
          if (!alreadyAdded) {
            reordered.add(c);
          }
        }

        // Build polyline from road-following coordinates (GraphHopper)
        // visualization.polylineCoordinates is [[lng, lat], [lng, lat], ...]
        final List<LatLng> polyline = [];
        final visualization = result['visualization'];
        if (visualization != null && visualization['polylineCoordinates'] != null) {
          final coords = visualization['polylineCoordinates'] as List;
          for (final coord in coords) {
            if (coord is List && coord.length >= 2) {
              final lng = double.tryParse(coord[0].toString());
              final lat = double.tryParse(coord[1].toString());
              if (lat != null && lng != null) {
                polyline.add(LatLng(lat, lng));
              }
            }
          }
        }
        // Fallback: straight-line through stops if no polyline from server
        if (polyline.isEmpty) {
          if (_currentLatLng != null) polyline.add(_currentLatLng!);
          for (final stop in stops) {
            final lat = double.tryParse(stop['latitude']?.toString() ?? '');
            final lng = double.tryParse(stop['longitude']?.toString() ?? '');
            if (lat != null && lng != null) {
              polyline.add(LatLng(lat, lng));
            }
          }
        }

        setState(() {
          _optimizedStops = reordered;
          _routePolyline = polyline;
          _isOptimizing = false;
        });

        // Fit map to show all stops
        if (_routePolyline.length > 1) {
          _fitMapBounds();
        }
      } else {
        setState(() {
          _isOptimizing = false;
          _error = 'Optimization returned no results. Showing original order.';
        });
      }
    } catch (e) {
      setState(() {
        _isOptimizing = false;
        _error = 'Optimization failed: ${e.toString().split(':').first}. Showing original order.';
      });
    }
  }

  void _fitMapBounds() {
    if (_routePolyline.isEmpty) return;
    try {
      double minLat = _routePolyline.first.latitude;
      double maxLat = _routePolyline.first.latitude;
      double minLng = _routePolyline.first.longitude;
      double maxLng = _routePolyline.first.longitude;

      for (final point in _routePolyline) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      final bounds = LatLngBounds(
        LatLng(minLat - 0.005, minLng - 0.005),
        LatLng(maxLat + 0.005, maxLng + 0.005),
      );
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Optimized Route', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '${_optimizedStops.length} stops',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (_isOptimizing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Re-optimize from current location',
              onPressed: _optimizeRoute,
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          if (_isLoadingLocation)
            Container(
              color: AppTheme.primaryColor.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text('Getting your location...', style: TextStyle(color: AppTheme.primaryColor, fontSize: 13)),
                ],
              ),
            )
          else if (_isOptimizing)
            Container(
              color: Colors.orange.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
                  SizedBox(width: 10),
                  Text('Optimizing route...', style: TextStyle(color: Colors.orange, fontSize: 13)),
                ],
              ),
            )
          else if (_error != null)
            Container(
              color: Colors.red.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Colors.orange, fontSize: 12))),
                ],
              ),
            )
          else if (_currentPosition != null && _routePolyline.isNotEmpty)
            Container(
              color: Colors.green.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Route optimized from your location',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _optimizeRoute,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    child: const Text('Re-optimize', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),

          // Map view
          SizedBox(
            height: 220,
            child: _buildMap(),
          ),

          // Stops list
          Expanded(
            child: _optimizedStops.isEmpty
                ? Center(child: Text('No stops', style: TextStyle(color: Colors.white.withOpacity(0.5))))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _optimizedStops.length,
                    itemBuilder: (context, index) {
                      return _buildStopCard(index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final center = _currentLatLng ?? 
        (_routePolyline.isNotEmpty ? _routePolyline.first : const LatLng(6.5244, 3.3792));

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'net.fieldscheduler.app',
        ),
        // Route polyline
        if (_routePolyline.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePolyline,
                strokeWidth: 3.5,
                color: AppTheme.primaryColor.withOpacity(0.8),
              ),
            ],
          ),
        // Stop markers
        MarkerLayer(
          markers: [
            // Current location marker
            if (_currentLatLng != null)
              Marker(
                point: _currentLatLng!,
                width: 32,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)],
                  ),
                  child: const Icon(Icons.my_location, color: Colors.white, size: 16),
                ),
              ),
            // Stop markers
            ..._optimizedStops.asMap().entries.map((entry) {
              final index = entry.key;
              final stop = entry.value;
              final customer = stop['customer'] ?? stop;
              final lat = double.tryParse(customer['latitude']?.toString() ?? '');
              final lng = double.tryParse(customer['longitude']?.toString() ?? '');
              if (lat == null || lng == null || lat == 0 || lng == 0) return null;

              final isCompleted = _completedStops.contains(index);
              return Marker(
                point: LatLng(lat, lng),
                width: 28,
                height: 28,
                child: GestureDetector(
                  onTap: () => _navigateToCustomer(stop),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.grey : AppTheme.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              );
            }).whereType<Marker>().toList(),
          ],
        ),
      ],
    );
  }

  Widget _buildStopCard(int index) {
    final stop = _optimizedStops[index];
    final customer = stop['customer'] ?? stop;
    final name = customer['name']?.toString() ?? 'Unknown';
    final address = customer['address']?.toString() ?? '';
    final maf = customer['maf']?.toString() ?? customer['customerCode']?.toString() ?? '';
    final isCompleted = _completedStops.contains(index);
    final sequence = stop['_sequence'] ?? (index + 1);

    // Calculate distance from current location
    String distanceText = '';
    if (_currentPosition != null) {
      final lat = double.tryParse(customer['latitude']?.toString() ?? '');
      final lng = double.tryParse(customer['longitude']?.toString() ?? '');
      if (lat != null && lng != null && lat != 0 && lng != 0) {
        final dist = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          lat,
          lng,
        );
        if (dist < 1000) {
          distanceText = '${dist.toStringAsFixed(0)}m away';
        } else {
          distanceText = '${(dist / 1000).toStringAsFixed(1)}km away';
        }
      }
    }

    return Card(
      color: isCompleted ? AppTheme.bgCard.withOpacity(0.5) : AppTheme.bgCard,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToCustomer(stop),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Sequence number / completion toggle
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_completedStops.contains(index)) {
                      _completedStops.remove(index);
                    } else {
                      _completedStops.add(index);
                    }
                  });
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isCompleted ? Colors.green.withOpacity(0.2) : AppTheme.primaryColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCompleted ? Colors.green : AppTheme.primaryColor,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.green, size: 18)
                        : Text(
                            '$sequence',
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Customer info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: isCompleted ? Colors.white.withOpacity(0.4) : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (maf.isNotEmpty)
                      Text(maf, style: TextStyle(color: AppTheme.primaryColor.withOpacity(0.8), fontSize: 12)),
                    if (address.isNotEmpty)
                      Text(
                        address,
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Distance + arrow
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (distanceText.isNotEmpty)
                    Text(distanceText, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                  const SizedBox(height: 4),
                  Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToCustomer(Map<String, dynamic> stop) {
    final customer = stop['customer'] ?? stop;
    final rawId = customer['id'];
    if (rawId == null) return;
    final customerId = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0;
    if (customerId == 0) return;
    final customerName = customer['name']?.toString() ?? 'Customer';
    final routeId = (widget.route['id'] is int)
        ? widget.route['id'] as int
        : int.tryParse(widget.route['id']?.toString() ?? '0') ?? 0;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(
          customerId: customerId,
          customerName: customerName,
          routeId: routeId,
        ),
      ),
    );
  }
}
