import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import '../models/location_model.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LocationProvider extends ChangeNotifier {
  final LocationService _locationService = LocationService.instance;
  final ApiService _apiService = ApiService();
  bool _isTracking = false;
  List<LocationData> _locations = [];
  bool _isRefreshing = false;
  Timer? _periodicRefreshTimer;
  
  bool get isTracking => _isTracking;
  List<LocationData> get locations => _locations;
  bool get isRefreshing => _isRefreshing;
  
  // Statistics
  int get totalLocations => _locations.length;
  int get syncedCount => _locations.where((location) => location.isSynced).length;
  int get pendingCount => _locations.where((location) => !location.isSynced).length;
  
  LocationProvider() {
    _initialize();
  }
  
  Future<void> _initialize() async {
    if (_isRefreshing) return;
    
    // Explicitly silence sounds again
    try {
      await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);
      await bg.BackgroundGeolocation.setConfig(bg.Config(
        debug: false,
        soundId: bg.BackgroundGeolocation.SOUND_SILENCE
      ));
    } catch (e) {
      print('Error silencing sounds: $e');
    }
    
    try {
      await _locationService.initialize();
      
      // Load locations first to ensure UI has data
      await _loadLocations();
      
      // Check if tracking was active before app termination
      await _checkTrackingStatus();
      
      // Listen for location updates
      _locationService.locationStream.listen((updatedLocations) {
        _locations = updatedLocations;
        // Sort locations by timestamp in descending order (newest first)
        _locations.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        notifyListeners();
      });
      
      // Setup periodic refresh when app is in foreground
      _setupPeriodicRefresh();
    } catch (e) {
      print('Error initializing location provider: $e');
      _isRefreshing = false;
      notifyListeners();
    }
  }
  
  // Setup a timer to refresh locations every 30 seconds while app is in foreground
  void _setupPeriodicRefresh() {
    _periodicRefreshTimer?.cancel();
    _periodicRefreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      // Only refresh if not already refreshing
      if (!_isRefreshing) {
        refreshData(showLoadingIndicator: false);
      }
    });
  }
  
  // Load locations from storage
  Future<void> _loadLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationsStr = prefs.getString('locations');
      
      if (locationsStr != null) {
        final List<dynamic> locationsJson = jsonDecode(locationsStr);
        _locations = locationsJson
            .map((json) => LocationData.fromJson(json))
            .toList();
        
        // Sort locations by timestamp in descending order (newest first)
        _locations.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        print('📱 Provider loaded ${_locations.length} locations from storage');
        notifyListeners();
      }
    } catch (e) {
      print('❌ Error loading locations in provider: $e');
    }
  }
  
  Future<void> _checkTrackingStatus() async {
    // Get tracking state from the plugin directly
    final state = await bg.BackgroundGeolocation.state;
    _isTracking = state.enabled;
    
    // If tracking is active but our state doesn't match, synchronize
    if (_isTracking) {
      print("Tracking was already active, syncing state");
    }
    
    notifyListeners();
  }
  
  Future<void> startTracking() async {
    if (!_isTracking) {
      await _locationService.startTracking();
      _isTracking = true;
      
      // Save tracking state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isTracking', true);
      
      // Also refresh to get current location
      await refreshData();
      
      notifyListeners();
    }
  }
  
  Future<void> stopTracking() async {
    if (_isTracking) {
      await _locationService.stopTracking();
      _isTracking = false;
      
      // Save tracking state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isTracking', false);
      
      // Also refresh to make sure UI is updated
      await refreshData();
      
      notifyListeners();
    }
  }
  
  Future<void> refreshData({bool showLoadingIndicator = true}) async {
    if (_isRefreshing) return;
    
    if (showLoadingIndicator) {
      _isRefreshing = true;
      notifyListeners();
    }
    
    try {
      // First refresh data from storage
      await _locationService.refreshData();
      
      // Process any batch queue
      await _apiService.processBatchQueue();
      
      // Retry any failed requests
      await _apiService.retryFailedRequests();
      
      // Then try to get current location if tracking is active
      if (_isTracking) {
        await _locationService.getCurrentLocation();
      }
      
      // Make sure we have the latest data
      await _loadLocations();
    } catch (e) {
      print('Error refreshing data: $e');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }
  
  // Get pending locations count - useful for UI indicators
  Future<int> getPendingLocationsCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get failed requests
      final String? failedRequestsJson = prefs.getString('failed_location_requests');
      int failedCount = 0;
      if (failedRequestsJson != null) {
        final List<dynamic> failedRequests = json.decode(failedRequestsJson);
        failedCount = failedRequests.length;
      }
      
      // Get batch queue
      final String? batchQueueJson = prefs.getString('batch_queue');
      int batchCount = 0;
      if (batchQueueJson != null) {
        final List<dynamic> batchQueue = json.decode(batchQueueJson);
        batchCount = batchQueue.length;
      }
      
      // Get unsent locations from main storage
      int unsentCount = pendingCount;
      
      // Return total
      return failedCount + batchCount + unsentCount;
    } catch (e) {
      print('❌ Error getting pending locations count: $e');
      return 0;
    }
  }
  
  // Delete specified locations
  Future<void> deleteLocations(List<int> locationIds) async {
    try {
      await _locationService.deleteLocations(locationIds);
      
      // Refresh locations after deletion
      await refreshData();
      
      notifyListeners();
    } catch (e) {
      print('Error deleting locations: $e');
    }
  }
  
  // Delete all locations
  Future<void> deleteAllLocations() async {
    try {
      await _locationService.deleteAllLocations();
      
      // Refresh locations after deletion
      await refreshData();
      
      notifyListeners();
    } catch (e) {
      print('Error deleting all locations: $e');
    }
  }
  
  @override
  void dispose() {
    _periodicRefreshTimer?.cancel();
    _locationService.dispose();
    super.dispose();
  }
} 