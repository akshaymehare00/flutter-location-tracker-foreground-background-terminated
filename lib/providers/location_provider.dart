import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import '../models/location_model.dart';
import '../services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationProvider extends ChangeNotifier {
  final LocationService _locationService = LocationService.instance;
  bool _isTracking = false;
  List<LocationData> _locations = [];
  bool _isRefreshing = false;
  
  bool get isTracking => _isTracking;
  List<LocationData> get locations => _locations;
  bool get isRefreshing => _isRefreshing;
  
  LocationProvider() {
    _initialize();
  }
  
  Future<void> _initialize() async {
    await _locationService.initialize();
    
    // Check if tracking was active before app termination
    await _checkTrackingStatus();
    
    _locationService.locationStream.listen((updatedLocations) {
      _locations = updatedLocations;
      notifyListeners();
    });
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
  
  Future<void> refreshData() async {
    if (_isRefreshing) return;
    
    _isRefreshing = true;
    notifyListeners();
    
    try {
      // First refresh data from storage
      await _locationService.refreshData();
      
      // Then try to get current location if tracking is active
      if (_isTracking) {
        await _locationService.getCurrentLocation();
      }
    } catch (e) {
      print('Error refreshing data: $e');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _locationService.dispose();
    super.dispose();
  }
} 