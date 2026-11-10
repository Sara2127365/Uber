
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:obar/core/widgets/app_custom_bar.dart';
import 'package:obar/feature/home/home_searchbar.dart';
import 'package:obar/feature/home/model/place_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? mapController;
  StreamSubscription<Position>? positionStreamSubscription;

  final LatLng defaultLocation = const LatLng(30.0444, 31.2357);

  LatLng? currentLocation;
  LatLng destinationLocation = const LatLng(30.0131, 31.2089);

  String currentLocationName = 'Getting current location...';
  String destinationName = 'Select destination';
  String destinationAddress = '';

  double? routeDistanceMeters;
  double? routeDurationSeconds;

  LatLng? lastRouteLocation;
  LatLng? lastRouteDestination;
  LatLng? lastAddressLocation;

  bool locationPermissionGranted = false;
  bool isLoadingLocation = false;
  bool isLoadingRoute = false;
  bool isRouteRequestRunning = false;
  bool isAddressRequestRunning = false;
  bool pendingRouteUpdate = false;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      getCurrentLocation();
    });
  }

  // Get current device location
  Future<void> getCurrentLocation() async {
    if (isLoadingLocation || !mounted) return;

    setState(() {
      isLoadingLocation = true;
    });

    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        showMessage('Please enable location services.');
        return;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showMessage(
          'Please allow location permission from app settings.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (!mounted) return;

      debugPrint('========== GPS ==========');
      debugPrint('LAT: ${position.latitude}');
      debugPrint('LNG: ${position.longitude}');
      debugPrint('ACCURACY: ${position.accuracy}');
      debugPrint('TIMESTAMP: ${position.timestamp}');
      debugPrint('=========================');

      currentLocation = LatLng(
        position.latitude,
        position.longitude,
      );

      locationPermissionGranted = true;

      updateMarkers();
      setState(() {
        currentLocationName = 'Getting address...';
      });

      await updateCurrentLocationAddress();
      await fitMapToLocations();
      await getRoute();

      startLiveLocation();
    } catch (e) {
      debugPrint('LOCATION ERROR: $e');
      showMessage('Unable to get current location.');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingLocation = false;
        });
      }
    }
  }

  // Convert coordinates into a readable address
  Future<String> getAddressFromCoordinates(
    LatLng location,
  ) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2'
        '&lat=${location.latitude}'
        '&lon=${location.longitude}',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'ObarFlutterApp/1.0',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('ADDRESS STATUS: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final address = data['address'];

        if (address is Map) {
          final parts = [
            address['road'],
            address['neighbourhood'],
            address['suburb'],
            address['city'] ??
                address['town'] ??
                address['village'] ??
                address['municipality'],
          ]
              .where(
                (part) =>
                    part != null &&
                    part.toString().trim().isNotEmpty,
              )
              .map((part) => part.toString())
              .toSet()
              .toList();

          if (parts.isNotEmpty) {
            return parts.join(', ');
          }
        }

        return data['display_name']?.toString() ??
            'Unknown location';
      }

      debugPrint('ADDRESS BODY: ${response.body}');
    } catch (e) {
      debugPrint('GEOCODING ERROR: $e');
    }

    return 'Unable to get address';
  }

  // Update current location address
  Future<void> updateCurrentLocationAddress() async {
    if (currentLocation == null || isAddressRequestRunning) {
      return;
    }

    isAddressRequestRunning = true;
    final requestedLocation = currentLocation!;

    try {
      final address = await getAddressFromCoordinates(
        requestedLocation,
      );

      if (!mounted || currentLocation == null) return;

      final distance = Geolocator.distanceBetween(
        requestedLocation.latitude,
        requestedLocation.longitude,
        currentLocation!.latitude,
        currentLocation!.longitude,
      );

      // Ignore an old address if the device moved significantly.
      if (distance >= 100) return;

      setState(() {
        currentLocationName = address;
        lastAddressLocation = requestedLocation;
        updateMarkers();
      });
    } finally {
      isAddressRequestRunning = false;
    }
  }

  // Get destination address
  Future<void> updateDestinationAddress() async {
    final requestedLocation = destinationLocation;

    final address = await getAddressFromCoordinates(
      requestedLocation,
    );

    if (!mounted || requestedLocation != destinationLocation) {
      return;
    }

    setState(() {
      destinationAddress = address;
      updateMarkers();
    });
  }

  // Listen to live location updates
  void startLiveLocation() {
    positionStreamSubscription?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1,
    );

    positionStreamSubscription =
        Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        if (!mounted) return;

        currentLocation = LatLng(
          position.latitude,
          position.longitude,
        );

        debugPrint(
          'NEW GPS LOCATION: '
          '${position.latitude}, ${position.longitude}',
        );

        updateMarkers();
        setState(() {});

        mapController?.animateCamera(
          CameraUpdate.newLatLng(currentLocation!),
        );

        if (lastAddressLocation == null) {
          updateCurrentLocationAddress();
        } else {
          final addressDistance =
              Geolocator.distanceBetween(
            lastAddressLocation!.latitude,
            lastAddressLocation!.longitude,
            currentLocation!.latitude,
            currentLocation!.longitude,
          );

          if (addressDistance >= 100) {
            updateCurrentLocationAddress();
          }
        }

        updateRouteIfNeeded();
      },
      onError: (error) {
        debugPrint('LOCATION STREAM ERROR: $error');
      },
    );
  }

  // Update pickup and destination markers
  void updateMarkers() {
    final updatedMarkers = <Marker>{};

    if (currentLocation != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: currentLocation!,
          infoWindow: InfoWindow(
            title: currentLocationName,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    updatedMarkers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: destinationLocation,
        infoWindow: InfoWindow(
          title: destinationName,
          snippet: destinationAddress,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
      ),
    );

    markers = updatedMarkers;
  }

  // Select destination from search
  void onPlaceSelected(PlaceModel place) {
    destinationLocation = LatLng(
      place.latitude,
      place.longitude,
    );

    destinationName = place.name;
    destinationAddress = '';

    routeDistanceMeters = null;
    routeDurationSeconds = null;

    lastRouteDestination = null;

    updateMarkers();

    setState(() {});

    updateDestinationAddress();
    fitMapToLocations();

    if (isRouteRequestRunning) {
      pendingRouteUpdate = true;
    } else {
      getRoute();
    }
  }

  // Fit map to pickup and destination
  Future<void> fitMapToLocations() async {
    if (mapController == null || !mounted) return;

    if (currentLocation == null) {
      await mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          destinationLocation,
          14,
        ),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(
        currentLocation!.latitude <
                destinationLocation.latitude
            ? currentLocation!.latitude
            : destinationLocation.latitude,
        currentLocation!.longitude <
                destinationLocation.longitude
            ? currentLocation!.longitude
            : destinationLocation.longitude,
      ),
      northeast: LatLng(
        currentLocation!.latitude >
                destinationLocation.latitude
            ? currentLocation!.latitude
            : destinationLocation.latitude,
        currentLocation!.longitude >
                destinationLocation.longitude
            ? currentLocation!.longitude
            : destinationLocation.longitude,
      ),
    );

    try {
      await mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    } catch (e) {
      debugPrint('FIT MAP ERROR: $e');
    }
  }

  // Recalculate route when location moves or destination changes
  void updateRouteIfNeeded() {
    if (currentLocation == null) return;

    if (isRouteRequestRunning) {
      pendingRouteUpdate = true;
      return;
    }

    final destinationChanged =
        lastRouteDestination != destinationLocation;

    if (lastRouteLocation == null || destinationChanged) {
      getRoute();
      return;
    }

    final distance = Geolocator.distanceBetween(
      lastRouteLocation!.latitude,
      lastRouteLocation!.longitude,
      currentLocation!.latitude,
      currentLocation!.longitude,
    );

    debugPrint('MOVED FROM LAST ROUTE: $distance meters');

    if (distance >= 20) {
      getRoute();
    }
  }

  // Get driving route from OSRM
  Future<void> getRoute() async {
    if (currentLocation == null ||
        isRouteRequestRunning ||
        !mounted) {
      return;
    }

    isRouteRequestRunning = true;

    final routeOrigin = currentLocation!;
    final routeDestination = destinationLocation;

    setState(() {
      isLoadingRoute = true;
    });

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${routeOrigin.longitude},${routeOrigin.latitude};'
        '${routeDestination.longitude},${routeDestination.latitude}'
        '?overview=full&geometries=geojson&steps=false',
      );

      final response = await http
          .get(url)
          .timeout(const Duration(seconds: 20));

      debugPrint('OSRM HTTP CODE: ${response.statusCode}');
      debugPrint('ROUTE START: $routeOrigin');
      debugPrint('ROUTE DESTINATION: $routeDestination');

      if (response.statusCode != 200) {
        debugPrint('OSRM RESPONSE: ${response.body}');
        throw Exception('OSRM HTTP Error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      if (data['code'] != 'Ok' ||
          (data['routes'] as List).isEmpty) {
        throw Exception('No driving route found.');
      }

      final route = data['routes'][0];
      final coordinates =
          route['geometry']['coordinates'] as List;

      final routePoints = coordinates.map((point) {
        return LatLng(
          (point[1] as num).toDouble(),
          (point[0] as num).toDouble(),
        );
      }).toList();

      if (!mounted) return;

      // Ignore response if destination changed while loading.
      if (routeDestination != destinationLocation) {
        pendingRouteUpdate = true;
        return;
      }

      setState(() {
        polylines = {
          Polyline(
            polylineId: const PolylineId('driving_route'),
            points: routePoints,
            color: Colors.blue,
            width: 7,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };

        routeDistanceMeters =
            (route['distance'] as num).toDouble();

        routeDurationSeconds =
            (route['duration'] as num).toDouble();
      });

      lastRouteLocation = routeOrigin;
      lastRouteDestination = routeDestination;

      debugPrint('ROUTE POINTS: ${routePoints.length}');
      debugPrint('DISTANCE: ${route['distance']} meters');
      debugPrint('DURATION: ${route['duration']} seconds');
    } catch (e) {
      debugPrint('OSRM ROUTE ERROR: $e');

      if (mounted) {
        showMessage('Unable to get driving route.');
      }
    } finally {
      isRouteRequestRunning = false;

      if (mounted) {
        setState(() {
          isLoadingRoute = false;
        });

        if (pendingRouteUpdate) {
          pendingRouteUpdate = false;
          updateRouteIfNeeded();
        }
      }
    }
  }

  // Format distance
  String formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }

    return '${meters.round()} m';
  }

  // Format estimated duration
  String formatDuration(double seconds) {
    final totalMinutes = (seconds / 60).round();

    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (minutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $minutes min';
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Reusable information item
  Widget infoItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    positionStreamSubscription?.cancel();
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppCustomBar(
            title: 'Obar',
            showBackButton: false,
            action: const Icon(Icons.car_crash),
          ),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: defaultLocation,
                    zoom: 13,
                  ),
                  onMapCreated: (controller) {
                    mapController = controller;

                    if (currentLocation != null) {
                      fitMapToLocations();
                    }
                  },
                  myLocationEnabled: locationPermissionGranted,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: markers,
                  polylines: polylines,
                ),

                // Destination search
                Positioned(
                  top: 15,
                  left: 16,
                  right: 16,
                  child: HomeSearchBar(
                    onPlaceSelected: onPlaceSelected,
                  ),
                ),

                // Current location button
                Positioned(
                  right: 16,
                  bottom: 320,
                  child: FloatingActionButton(
                    heroTag: 'current_location',
                    backgroundColor: Colors.white,
                    onPressed: getCurrentLocation,
                    child: isLoadingLocation
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.my_location,
                            color: Colors.black,
                          ),
                  ),
                ),

                // Trip details
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trip Details',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Pickup
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.my_location,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                currentLocationName,
                                style: const TextStyle(fontSize: 15),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const Padding(
                          padding: EdgeInsets.only(
                            left: 10,
                            top: 5,
                            bottom: 5,
                          ),
                          child: SizedBox(
                            height: 20,
                            child: VerticalDivider(
                              thickness: 1.5,
                              color: Colors.grey,
                            ),
                          ),
                        ),

                        // Destination
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    destinationName,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (destinationAddress.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      destinationAddress,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Distance and duration
                        if (isLoadingRoute)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (routeDistanceMeters != null &&
                            routeDurationSeconds != null) ...[
                          const Divider(),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              infoItem(
                                icon: Icons.route,
                                title: 'Distance',
                                value: formatDistance(
                                  routeDistanceMeters!,
                                ),
                              ),
                              const SizedBox(width: 20),
                              infoItem(
                                icon: Icons.access_time,
                                title: 'Estimated time',
                                value: formatDuration(
                                  routeDurationSeconds!,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Confirm pickup
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed:
                                currentLocation == null || isLoadingRoute
                                    ? null
                                    : () {
                                        showMessage(
                                          'Pickup location confirmed.',
                                        );
                                      },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Confirm pickup location',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
