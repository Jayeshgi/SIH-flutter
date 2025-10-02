import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(19.0760, 72.8777); // Default: Mumbai
  bool _showWeatherMap = false;

  @override
  void initState() {
    super.initState();
    _updateLocation(); // Attempt to update location on init
  }

  Future<void> _updateLocation() async {
    bool locationGranted = await Permission.location.request().isGranted;
    if (!locationGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission required')),
      );
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services')),
      );
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _mapController.move(_currentLocation, 10.0);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location updated successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating location: $e')),
      );
    }
  }

  void _toggleWeatherMap() {
    setState(() {
      _showWeatherMap = !_showWeatherMap;
      if (_showWeatherMap) {
        _mapController.move(_currentLocation, 5.0); // Zoom in for weather map
      } else {
        _mapController.move(_currentLocation, 10.0); // Reset zoom
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hazard Map'),
        backgroundColor: Colors.blue,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reports')
            .where('status', isEqualTo: 'verified')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          List<Marker> markers = [];
          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            markers = snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final double lat = data['latitude'] ?? 19.0760;
              final double long = data['longitude'] ?? 72.8777;
              final String hazardType = data['hazardType'] ?? 'Unknown';
              final Timestamp? ts = data['timestamp'];
              final DateTime time = ts?.toDate() ?? DateTime.now();
              final String formattedTime = DateFormat('yyyy-MM-dd HH:mm').format(time);

              return Marker(
                point: LatLng(lat, long),
                width: 80,
                height: 80,
                child: GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(hazardType),
                        content: Text('Location: $lat, $long\nTime: $formattedTime'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
              );
            }).toList();
          } else {
            markers.add(
              Marker(
                point: _currentLocation,
                width: 80,
                height: 80,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 40,
                ),
              ),
            );
          }

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation,
                  initialZoom: _showWeatherMap ? 5.0 : 10.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: _showWeatherMap
                        ? 'https://tile.openweathermap.org/map/temp_new/{z}/{x}/{y}.png?appid=f69a63db7e1bdba5c2c58a3d865975da'
                        : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.example.ocean_hazard123',
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
              Positioned(
                top: 16.0,
                right: 16.0,
                child: Column(
                  children: [
                    FloatingActionButton(
                      onPressed: _updateLocation,
                      backgroundColor: Colors.green,
                      child: const Icon(Icons.my_location, size: 30),
                      tooltip: 'Update Location with GPS',
                    ),
                    const SizedBox(height: 16.0),
                    FloatingActionButton(
                      onPressed: _toggleWeatherMap,
                      backgroundColor: Colors.orange,
                      child: Icon(
                        _showWeatherMap ? Icons.map : Icons.wb_sunny,
                        size: 30,
                      ),
                      tooltip: _showWeatherMap
                          ? 'Switch to Regular Map'
                          : 'Switch to Weather Map',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}