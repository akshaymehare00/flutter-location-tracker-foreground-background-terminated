import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import '../widgets/location_card.dart';
import '../services/location_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _permissionsGranted = true; // We'll assume permissions are granted initially
  late final AnimationController _animationController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // The background_geolocation package will handle permission requests internally
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animationController.forward();
    
    // Register for lifecycle events
    WidgetsBinding.instance.addObserver(this);
    
    // Initially we are in foreground
    LocationService.instance.isInForeground = true;
    
    // Force refresh data when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Update the service when app lifecycle changes
    switch (state) {
      case AppLifecycleState.resumed:
        LocationService.instance.isInForeground = true;
        // Force refresh data when app is resumed
        _refreshData();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        LocationService.instance.isInForeground = false;
        break;
    }
  }
  
  // Refresh location data
  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      await LocationService.instance.refreshData();
      
      // Get a new location point
      await LocationService.instance.getCurrentLocation();
    } catch (e) {
      print('❌ Error refreshing data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<LocationProvider>(
          builder: (context, provider, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Location Tracker'),
                const SizedBox(width: 10),
                if (provider.locations.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${provider.locations.length}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Refresh button
          IconButton(
            icon: _isRefreshing 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2)
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshData,
            tooltip: 'Refresh Data',
          ),
          // Info button to show tracking status
          Consumer<LocationProvider>(
            builder: (context, provider, child) {
              return IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  _showTrackingInfo(context, provider.isTracking, provider.locations.length);
                },
                tooltip: 'Tracking Info',
              );
            },
          ),
          // Legend info button to explain sync status
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              _showLegendInfo(context);
            },
            tooltip: 'Status Legend',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: _buildLocationsList(),
      ),
      floatingActionButton: Consumer<LocationProvider>(
        builder: (context, provider, child) {
          return FloatingActionButton.extended(
            onPressed: () {
              if (provider.isTracking) {
                _showStopTrackingConfirmation(context, provider);
              } else {
                provider.startTracking();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Location tracking started. Will continue in background.'),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            label: Text(provider.isTracking ? 'Stop Tracking' : 'Start Tracking'),
            icon: Icon(
              provider.isTracking ? Icons.pause : Icons.play_arrow,
            ),
            backgroundColor: provider.isTracking ? Colors.red : Colors.blue,
          );
        },
      ),
    );
  }

  void _showStopTrackingConfirmation(BuildContext context, LocationProvider provider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Stop Location Tracking?'),
          content: const Text(
            'This will completely stop background location tracking. '
            'Are you sure you want to stop?'
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                provider.stopTracking();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Location tracking stopped'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Stop Tracking'),
            ),
          ],
        );
      },
    );
  }
  
  void _showLegendInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Status Legend'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Each location card shows the status of the data:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.cloud_done, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Synced', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          'Location has been successfully sent to the server',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.cloud_off, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Pending', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          'Location is saved locally but not yet sent to the server',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Note: Pending locations will be automatically sent every 10 seconds or when connectivity is restored.',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  void _showTrackingInfo(BuildContext context, bool isTracking, int locationCount) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Background Tracking Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Status: ${isTracking ? "ACTIVE" : "INACTIVE"}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isTracking ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tracked Locations: $locationCount',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'This app tracks your location every 10 seconds and sends updates to the server. '
                'Tracking continues even when the app is closed or in the background.',
              ),
              const SizedBox(height: 16),
              if (isTracking)
                const Text(
                  'Note: You can also stop tracking from the notification.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocationsList() {
    return Consumer<LocationProvider>(
      builder: (context, provider, child) {
        if (provider.locations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.location_searching,
                  size: 80,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No location data yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.isTracking
                      ? 'Tracking is active and will continue in background'
                      : 'Press the button below to start tracking',
                  textAlign: TextAlign.center,
                ),
                if (provider.isTracking) 
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'You can close the app and tracking will continue',
                      style: TextStyle(fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 24),
                if (_isRefreshing)
                  const CircularProgressIndicator()
                else
                  ElevatedButton.icon(
                    onPressed: _refreshData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Data'),
                  ),
              ],
            ),
          );
        }

        // Reverse the list to show newest at top
        final locations = provider.locations.reversed.toList();

        return AnimatedList(
          initialItemCount: locations.length,
          itemBuilder: (context, index, animation) {
            // Get the location for this index
            final location = locations[index];
            
            // Custom fade+slide animation
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            );
            
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.5),
                end: const Offset(0, 0),
              ).animate(curvedAnimation),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0, end: 1).animate(curvedAnimation),
                child: LocationCard(
                  location: location,
                  index: index, 
                  total: locations.length,
                ),
              ),
            );
          },
        );
      },
    );
  }
} 