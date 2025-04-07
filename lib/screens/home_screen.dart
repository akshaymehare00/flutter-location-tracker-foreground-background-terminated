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
    
    // Update the foreground status for the location service
    if (state == AppLifecycleState.resumed) {
      LocationService.instance.isInForeground = true;
      // Refresh data when coming to foreground
      _refreshData();
    } else if (state == AppLifecycleState.paused) {
      LocationService.instance.isInForeground = false;
    }
  }
  
  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    final provider = Provider.of<LocationProvider>(context, listen: false);
    await provider.refreshData();
    
    setState(() {
      _isRefreshing = false;
    });
  }
  
  Future<void> _confirmStopTracking(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Tracking?'),
        content: const Text('Are you sure you want to stop location tracking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('STOP'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      final provider = Provider.of<LocationProvider>(context, listen: false);
      await provider.stopTracking();
    }
  }
  
  Widget _buildDashboardHeader(BuildContext context, LocationProvider provider) {
    final int totalCount = provider.totalLocations;
    final int pendingCount = provider.pendingLocations;
    final int syncedCount = provider.syncedLocations;
    
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location Stats',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  context, 
                  'Total', 
                  totalCount.toString(),
                  Icons.pin_drop,
                  Colors.blue
                ),
                _buildStatItem(
                  context, 
                  'Synced', 
                  syncedCount.toString(),
                  Icons.cloud_done,
                  Colors.green
                ),
                _buildStatItem(
                  context, 
                  'Pending', 
                  pendingCount.toString(),
                  Icons.cloud_upload,
                  Colors.orange
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildLocationsList(BuildContext context, LocationProvider provider) {
    final locations = provider.locations;
    
    if (locations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No locations tracked yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100), // Add padding for FAB
        itemCount: locations.length,
        itemBuilder: (context, index) {
          return LocationCard(
            location: locations[index],
            index: index,
            total: locations.length,
            onRefresh: _refreshData,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocationProvider>(context);
    final isTracking = provider.isTracking;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Location Tracker'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isTracking ? Colors.green : Colors.grey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${provider.totalLocations} locations',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_isRefreshing)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh data',
          ),
        ],
      ),
      body: Column(
        children: [
          // Dashboard stats card
          _buildDashboardHeader(context, provider),
          
          // Tracking status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isTracking ? Icons.gps_fixed : Icons.gps_off,
                  color: isTracking ? Colors.green : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  isTracking 
                      ? 'Tracking active - updates every 10 seconds' 
                      : 'Tracking inactive',
                  style: TextStyle(
                    color: isTracking ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Locations list
          Expanded(
            child: _buildLocationsList(context, provider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (isTracking) {
            _confirmStopTracking(context);
          } else {
            provider.startTracking();
          }
        },
        backgroundColor: isTracking ? Colors.red : Colors.green,
        icon: Icon(isTracking ? Icons.stop : Icons.play_arrow),
        label: Text(isTracking ? 'Stop Tracking' : 'Start Tracking'),
      ),
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
} 