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
  
  // Selection mode for deletion
  bool _isInSelectionMode = false;
  final Set<int> _selectedLocationIds = {};

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
    
    try {
      final provider = Provider.of<LocationProvider>(context, listen: false);
      await provider.refreshData();
    } catch (e) {
      print('Error refreshing data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }
  
  // Toggle selection mode
  void _toggleSelectionMode() {
    setState(() {
      _isInSelectionMode = !_isInSelectionMode;
      // Clear selections when exiting selection mode
      if (!_isInSelectionMode) {
        _selectedLocationIds.clear();
      }
    });
  }
  
  // Toggle location selection
  void _toggleLocationSelection(int locationId) {
    setState(() {
      if (_selectedLocationIds.contains(locationId)) {
        _selectedLocationIds.remove(locationId);
      } else {
        _selectedLocationIds.add(locationId);
      }
      
      // If no locations selected, exit selection mode
      if (_selectedLocationIds.isEmpty && _isInSelectionMode) {
        _isInSelectionMode = false;
      }
    });
  }
  
  // Delete selected locations
  Future<void> _deleteSelectedLocations() async {
    if (_selectedLocationIds.isEmpty) return;
    
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_selectedLocationIds.length == 1 
            ? 'Delete Location' 
            : 'Delete ${_selectedLocationIds.length} Locations'),
        content: Text(_selectedLocationIds.length == 1
            ? 'Are you sure you want to delete this location?'
            : 'Are you sure you want to delete these ${_selectedLocationIds.length} locations?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    
    if (shouldDelete == true) {
      final provider = Provider.of<LocationProvider>(context, listen: false);
      await provider.deleteLocations(List<int>.from(_selectedLocationIds));
      
      setState(() {
        _selectedLocationIds.clear();
        _isInSelectionMode = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectedLocationIds.length == 1
              ? 'Location deleted'
              : '${_selectedLocationIds.length} locations deleted'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  // Delete a single location
  Future<void> _deleteLocation(int locationId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Location'),
        content: const Text('Are you sure you want to delete this location?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    
    if (shouldDelete == true) {
      final provider = Provider.of<LocationProvider>(context, listen: false);
      await provider.deleteLocations([locationId]);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location deleted'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  
  // Delete all locations
  Future<void> _confirmDeleteAllLocations() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Locations'),
        content: const Text('Are you sure you want to delete all locations? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE ALL'),
          ),
        ],
      ),
    );
    
    if (shouldDelete == true) {
      final provider = Provider.of<LocationProvider>(context, listen: false);
      await provider.deleteAllLocations();
      
      setState(() {
        _selectedLocationIds.clear();
        _isInSelectionMode = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All locations deleted'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocationProvider>(context);
    final isTracking = provider.isTracking;
    final hasLocations = provider.locations.isNotEmpty;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _isInSelectionMode 
                ? Text('${_selectedLocationIds.length} selected')
                : const Text('Location Tracker'),
            if (!_isInSelectionMode && provider.totalLocations > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Container(
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
              ),
          ],
        ),
        actions: [
          // Show cancel button in selection mode
          if (_isInSelectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSelectionMode,
              tooltip: 'Cancel selection',
            )
          // Show refresh indicator while refreshing
          else if (_isRefreshing)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ),
          
          // Show delete button when items are selected
          if (_isInSelectionMode && _selectedLocationIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelectedLocations,
              tooltip: 'Delete selected',
            )
          // Show refresh button when not in selection mode
          else if (!_isInSelectionMode)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshData,
              tooltip: 'Refresh data',
            ),
          
          // Show menu button for additional options
          if (!_isInSelectionMode && hasLocations)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'select') {
                  _toggleSelectionMode();
                } else if (value == 'delete_all') {
                  _confirmDeleteAllLocations();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'select',
                  child: Row(
                    children: [
                      Icon(Icons.check_box_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Select multiple'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete all', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(context, provider),
      floatingActionButton: _buildFloatingActionButton(context, provider),
    );
  }
  
  Widget _buildBody(BuildContext context, LocationProvider provider) {
    final isTracking = provider.isTracking;
    final locations = provider.locations;
    
    return Column(
      children: [
        // Status indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                isTracking ? Icons.gps_fixed : Icons.gps_off,
                color: isTracking ? Colors.green : Colors.grey,
                size: 20,
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
        
        // Stats row
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      context,
                      'Total',
                      provider.totalLocations.toString(),
                      Icons.location_on,
                      Colors.blue,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      context,
                      'Synced',
                      provider.syncedCount.toString(),
                      Icons.cloud_done,
                      Colors.green,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      context,
                      'Pending',
                      provider.pendingCount.toString(),
                      Icons.cloud_upload,
                      Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Location list
        Expanded(
          child: locations.isEmpty
              ? _buildEmptyView(context)
              : _buildLocationsList(context, provider),
        ),
      ],
    );
  }
  
  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
  
  Widget _buildEmptyView(BuildContext context) {
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
  
  Widget _buildLocationsList(BuildContext context, LocationProvider provider) {
    final locations = provider.locations;
    
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100), // Add padding for FAB
        itemCount: locations.length,
        itemBuilder: (context, index) {
          final location = locations[index];
          final isSelected = _selectedLocationIds.contains(location.id);
          
          return LocationCard(
            location: location,
            index: index,
            total: locations.length,
            onRefresh: _refreshData,
            // onDelete: _isInSelectionMode ? null : () => _deleteLocation(location.id),
            isSelected: isSelected,
            onSelectionChanged: _isInSelectionMode 
                ? () => _toggleLocationSelection(location.id)
                : _isInSelectionMode ? null : () => _startSelectionWithLocation(location.id),
          );
        },
      ),
    );
  }
  
  void _startSelectionWithLocation(int locationId) {
    setState(() {
      _isInSelectionMode = true;
      _selectedLocationIds.add(locationId);
    });
  }
  
  Widget _buildFloatingActionButton(BuildContext context, LocationProvider provider) {
    final isTracking = provider.isTracking;
    
    if (_isInSelectionMode) {
      return FloatingActionButton(
        onPressed: _deleteSelectedLocations,
        backgroundColor: Colors.red,
        child: const Icon(Icons.delete),
      );
    } else {
      return FloatingActionButton.extended(
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
      );
    }
  }
  
  Future<void> _confirmStopTracking(BuildContext context) async {
    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Tracking?'),
        content: const Text('Are you sure you want to stop tracking your location?'),
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
    
    if (shouldStop == true) {
      final provider = Provider.of<LocationProvider>(context, listen: false);
      provider.stopTracking();
    }
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