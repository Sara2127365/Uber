
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:obar/core/style/color_manager.dart';
import 'package:obar/core/widgets/app_custom_bar.dart';
import 'package:obar/feature/home/home_searchbar.dart';
import 'package:obar/feature/home/model/place_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Controllers
  GoogleMapController? mapController;
  StreamSubscription<Position>? positionStreamSubscription;

  // Location
  LatLng? currentLocation;
  LatLng? lastRouteLocation;

  final LatLng defaultLocation =
      const LatLng(30.0444, 31.2357);

  LatLng destinationLocation =
      const LatLng(30.0131, 31.2089);

  String destinationName = 'Destination';

  // Route tracking
  LatLng? lastRouteDestination;

  // API Key
  String get googleApiKey =>
      dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  // States
  bool locationPermissionGranted = false;
  bool isLoadingLocation = false;
  bool isLoadingRoute = false;
  bool isRouteRequestRunning = false;

  // Map Elements
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      getCurrentLocation();
    });
  }

  // 1. Get Current Location
  Future<void> getCurrentLocation() async {
    if (isLoadingLocation) return;

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
        showMessage('Location permission denied.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (!mounted) return;

      currentLocation = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        locationPermissionGranted = true;
      });

      updateMarkers();

      fitMapToLocations();

      await getRoute();

      if (!mounted) return;

      await startLiveLocation();
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

  // 2. Start Live Location Tracking
  Future<void> startLiveLocation() async {
    await positionStreamSubscription?.cancel();

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    positionStreamSubscription =
        Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (Position position) {
        if (!mounted) return;

        final newLocation = LatLng(
          position.latitude,
          position.longitude,
        );

        setState(() {
          currentLocation = newLocation;
        });

        updateMarkers();

        // Follow user location
        mapController?.animateCamera(
          CameraUpdate.newLatLng(newLocation),
        );

        updateRouteIfNeeded();
      },
      onError: (error) {
        debugPrint('LIVE LOCATION ERROR: $error');
      },
    );
  }

  // 3. Select Destination From Search
  void onPlaceSelected(PlaceModel place) {
    final destination = LatLng(
      place.latitude,
      place.longitude,
    );

    setState(() {
      destinationLocation = destination;
      destinationName = place.name;

      polylines = {};
      lastRouteLocation = null;
      lastRouteDestination = null;
    });

    updateMarkers();

    fitMapToLocations();

    if (currentLocation != null) {
      getRoute();
    }
  }

  // 4. Update Markers
  void updateMarkers() {
    if (!mounted) return;

    setState(() {
      markers = {
        if (currentLocation != null)
          Marker(
            markerId: const MarkerId('pickup'),
            position: currentLocation!,
            infoWindow: const InfoWindow(
              title: 'Your Current Location',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
          ),

        Marker(
          markerId: const MarkerId('destination'),
          position: destinationLocation,
          infoWindow: InfoWindow(
            title: destinationName,
          ),
        ),
      };
    });
  }

  // 5. Fit Current Location And Destination
  void fitMapToLocations() {
    if (currentLocation == null || mapController == null) {
      return;
    }

    final south = currentLocation!.latitude <
            destinationLocation.latitude
        ? currentLocation!.latitude
        : destinationLocation.latitude;

    final north = currentLocation!.latitude >
            destinationLocation.latitude
        ? currentLocation!.latitude
        : destinationLocation.latitude;

    final west = currentLocation!.longitude <
            destinationLocation.longitude
        ? currentLocation!.longitude
        : destinationLocation.longitude;

    final east = currentLocation!.longitude >
            destinationLocation.longitude
        ? currentLocation!.longitude
        : destinationLocation.longitude;

    // Avoid invalid bounds when both locations are identical
    if (south == north && west == east) {
      mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(destinationLocation, 16),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );

    mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  // 6. Check Distance Before Updating Route
  void updateRouteIfNeeded() {
    if (currentLocation == null ||
        isRouteRequestRunning) {
      return;
    }

    final destinationChanged =
        lastRouteDestination != destinationLocation;

    if (destinationChanged) {
      getRoute();
      return;
    }

    if (lastRouteLocation != null) {
      final distance = Geolocator.distanceBetween(
        lastRouteLocation!.latitude,
        lastRouteLocation!.longitude,
        currentLocation!.latitude,
        currentLocation!.longitude,
      );

      // Update route after moving 20 meters
      if (distance < 20) return;
    }

    getRoute();
  }

  // 7. Get Actual Driving Route
  
Future<void> getRoute() async {
  if (currentLocation == null || isRouteRequestRunning) {
    return;
  }

  if (googleApiKey.isEmpty) {
    showMessage('Google Maps API key is missing.');
    return;
  }

  isRouteRequestRunning = true;

  final routeOrigin = currentLocation!;
  final routeDestination = destinationLocation;

  bool requestSucceeded = false;

  if (mounted) {
    setState(() {
      isLoadingRoute = true;
    });
  }

  try {
    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      {
        'origin':
            '${routeOrigin.latitude},${routeOrigin.longitude}',
        'destination':
            '${routeDestination.latitude},${routeDestination.longitude}',
        'mode': 'driving',
        'key': googleApiKey,
      },
    );

    final response = await http.get(url);

    debugPrint('DIRECTIONS HTTP CODE: ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception(
        'HTTP Error: ${response.statusCode} - ${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    debugPrint('DIRECTIONS STATUS: ${data['status']}');

    if (data['status'] != 'OK') {
      throw Exception(
        'Google Directions Error: ${data['status']} '
        '${data['error_message'] ?? ''}',
      );
    }

    final routes = data['routes'] as List;

    if (routes.isEmpty) {
      throw Exception('No driving route found.');
    }

    final encodedPoints =
        routes.first['overview_polyline']['points'] as String;

    final routePoints = decodePolyline(encodedPoints);

    if (!mounted) return;

    // Do not display a route for an old destination
    if (routeDestination != destinationLocation) {
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
          geodesic: false,
        ),
      };
    });

    lastRouteLocation = routeOrigin;
    lastRouteDestination = routeDestination;

    requestSucceeded = true;

    debugPrint('DRIVING ROUTE DRAWN: ${routePoints.length} points');

  } catch (e) {
    debugPrint('ROUTE ERROR: $e');

    if (mounted) {
      showMessage('Unable to get driving route. Check API settings.');
    }
  } finally {
    isRouteRequestRunning = false;

    if (mounted) {
      setState(() {
        isLoadingRoute = false;
      });

      // If destination changed while request was running,
      // request the route for the new destination.
      if (routeDestination != destinationLocation) {
        getRoute();
      } else if (requestSucceeded) {
        // Recalculate only if the user moved during the request.
        updateRouteIfNeeded();
      }
    }
  }
}


  // 8. Decode Google Encoded Polyline
  List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> points = [];

    int index = 0;
    int latitude = 0;
    int longitude = 0;

    while (index < encoded.length) {
      int result = 0;
      int shift = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final deltaLat = (result & 1) != 0
          ? ~(result >> 1)
          : (result >> 1);

      latitude += deltaLat;

      result = 0;
      shift = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final deltaLng = (result & 1) != 0
          ? ~(result >> 1)
          : (result >> 1);

      longitude += deltaLng;

      points.add(
        LatLng(
          latitude / 1E5,
          longitude / 1E5,
        ),
      );
    }

    return points;
  }

  // 9. Show Message
  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    positionStreamSubscription?.cancel();
    mapController?.dispose();
    super.dispose();
  }

  // 10. Build UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorManager.backgroundColor,

      appBar: AppCustomBar(
        title: 'Obar',
        showBackButton: false,
        action: const Icon(Icons.car_crash),
      ),

      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: defaultLocation,
              zoom: 14,
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

          // Search Bar
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: HomeSearchBar(
              onPlaceSelected: onPlaceSelected,
            ),
          ),

          // Current Location Button
          Positioned(
            right: 16,
            bottom: 240,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: isLoadingLocation
                  ? null
                  : getCurrentLocation,
              child: isLoadingLocation
                  ? const SizedBox(
                      height: 22,
                      width: 22,
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

          // Pickup Bottom Sheet
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
              ),

              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Your pickup location',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 15),

                  Row(
                    children: [
                      const Icon(
                        Icons.my_location,
                        color: Colors.green,
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          currentLocation == null
                              ? 'Getting current location...'
                              : 'Current Location',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.red,
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          destinationName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,

                    child: ElevatedButton(
                      onPressed: currentLocation == null ||
                              isLoadingRoute
                          ? null
                          : () {
                              showMessage(
                                'Pickup and destination selected.',
                              );
                            },

                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                      ),

                      child: Text(
                        isLoadingRoute
                            ? 'Getting route...'
                            : 'Confirm pickup location',
                      ),
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
