
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:obar/core/style/color_manager.dart';
import 'package:obar/core/widgets/app_custom_bar.dart';
import 'package:obar/feature/home/home_searchbar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? mapController;

  bool locationPermissionGranted = false;
  bool isLoadingLocation = false;
  bool isLoadingRoute = false;

  // Replace with your Google Directions API key.
  static const String googleApiKey = 'YOUR_GOOGLE_API_KEY';

  final LatLng defaultLocation = const LatLng(30.0444, 31.2357);

  final LatLng destinationLocation = const LatLng(
    30.0131,
    31.2089,
  );

  LatLng? currentLocation;

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

      // Move camera to current location
      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(currentLocation!, 16),
      );

      // Update markers
      updateMarkers();

      // Get actual driving route
      await getRoute();

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

  // 2. Update Markers
  void updateMarkers() {
    if (currentLocation == null) return;

    setState(() {
      markers = {
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
          infoWindow: const InfoWindow(
            title: 'Destination',
          ),
        ),
      };
    });
  }

  // 3. Get Actual Route using Directions API
  Future<void> getRoute() async {
    if (currentLocation == null) return;

    setState(() {
      isLoadingRoute = true;
    });

    try {
      final origin =
          '${currentLocation!.latitude},${currentLocation!.longitude}';

      final destination =
          '${destinationLocation.latitude},${destinationLocation.longitude}';

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$origin'
        '&destination=$destination'
        '&mode=driving'
        '&key=$googleApiKey',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Directions request failed');
      }

      final data = jsonDecode(response.body);

      if (data['status'] != 'OK') {
        throw Exception(
          'Directions API: ${data['status']} '
          '${data['error_message'] ?? ''}',
        );
      }

      final encodedPoints =
          data['routes'][0]['overview_polyline']['points'] as String;

      final routePoints = decodePolyline(encodedPoints);

      if (!mounted) return;

      setState(() {
        polylines = {
          Polyline(
            polylineId: const PolylineId('actual_route'),
            points: routePoints,
            color: Colors.blue,
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };
      });

    } catch (e) {
      debugPrint('ROUTE ERROR: $e');
      showMessage('Unable to get actual route.');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingRoute = false;
        });
      }
    }
  }

  // 4. Decode Google Encoded Polyline
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

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

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
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: defaultLocation,
              zoom: 14,
            ),
            onMapCreated: (controller) {
              mapController = controller;

              if (currentLocation != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    currentLocation!,
                    16,
                  ),
                );
              }
            },
            myLocationEnabled: locationPermissionGranted,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: markers,
            polylines: polylines,
          ),

          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: const HomeSearchBar(),
          ),

          Positioned(
            right: 16,
            bottom: 240,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: isLoadingLocation
                  ? null
                  : getCurrentLocation,
              child: isLoadingLocation
                  ? const CircularProgressIndicator(
                      strokeWidth: 2,
                    )
                  : const Icon(
                      Icons.my_location,
                      color: Colors.black,
                    ),
            ),
          ),

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

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: currentLocation == null ||
                              isLoadingRoute
                          ? null
                          : () {},
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
