import 'dart:async';
import 'dart:convert';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/location_model.dart';
import 'api_service.dart';

class LocationService {
  final ApiService _apiService = ApiService();
  final List<LocationData> _locationHistory = [];
  final StreamController<List<LocationData>> _locationStreamController = 
      StreamController<List<LocationData>>.broadcast();
  
  Timer? _apiTimer;
  int _lastApiCallTimestamp = 0;
  
  // Fixed interval of exactly 10 seconds (10000ms)
  static const int API_CALL_INTERVAL = 10000; 
  
  // Track last sent location to prevent duplicates
  double? _lastSentLatitude;
  double? _lastSentLongitude;
  int _lastSentTimestamp = 0;
  
  // This will be used by app to tell the service if we're in foreground or not
  bool _isInForeground = true;
  set isInForeground(bool value) {
    _isInForeground = value;
    print('📱 App is in ${value ? "foreground" : "background"}');
    
    // Immediately load saved locations when app comes to foreground
    if (value) {
      _loadSavedLocations();
    }
  }

  Stream<List<LocationData>> get locationStream => _locationStreamController.stream;
  List<LocationData> get locationHistory => _locationHistory;

  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();

  LocationService._();

  // Initialize location tracking service
  Future<void> initialize() async {
    print('📱 Initializing location service');
    
    // CRUCIAL: First silence all sounds before anything else
    await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);
    
    // CRUCIAL: Initialize with all sounds fully disabled
    await bg.BackgroundGeolocation.ready(bg.Config(
      // Completely disable debug - debug sounds are a major source of the sound issue
      debug: false,
      // Disable all sounds
      soundId: bg.BackgroundGeolocation.SOUND_SILENCE,
      
      // Common config
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      distanceFilter: 10.0,
      locationUpdateInterval: 10000, // 10 seconds
      fastestLocationUpdateInterval: 5000, // 5 seconds
      
      // Activity Recognition
      isMoving: true,
      
      // Critical settings for background operation
      stopOnTerminate: false,
      startOnBoot: true,
      enableHeadless: true,
      heartbeatInterval: 60, // 1 minute
      
      // All debug off - crucial to prevent sounds
      debug: false,
      logLevel: bg.Config.LOG_LEVEL_OFF,
      
      // Sound disabling
      disableElasticity: true,
      disableMotionActivityUpdates: true,
      pausesLocationUpdatesAutomatically: false,
      
      // Notification with sound explicitly disabled
      notification: bg.Notification(
        title: "Location Tracking",
        text: "Tracking your location in background",
        priority: bg.Config.NOTIFICATION_PRIORITY_MIN,
        channelName: "Background Location",
        channelId: "background_location",
        sticky: true,
        sound: false
      ),
      
      // Foreground service notification with sound disabled
      foregroundService: true,
      foregroundServiceNotification: bg.Notification(
        title: "Location Tracking",
        text: "Tracking your location",
        priority: bg.Config.NOTIFICATION_PRIORITY_MIN,
        channelName: "Foreground Location",
        channelId: "foreground_location",
        sticky: true,
        sound: false
      )
    ));
    
    // Listen to events - register listeners after configuration
    bg.BackgroundGeolocation.onLocation(_onLocation);
    bg.BackgroundGeolocation.onMotionChange(_onMotionChange);
    bg.BackgroundGeolocation.onProviderChange(_onProviderChange);
    bg.BackgroundGeolocation.onHeartbeat(_onHeartbeat);
    bg.BackgroundGeolocation.onActivityChange(_onActivityChange);
    bg.BackgroundGeolocation.onEnabledChange(_onEnabledChange);
    bg.BackgroundGeolocation.onConnectivityChange(_onConnectivityChange);
    bg.BackgroundGeolocation.onNotificationAction(_onNotificationAction);

    // Double-ensure sound is silenced
    await bg.BackgroundGeolocation.setConfig(bg.Config(
      soundId: bg.BackgroundGeolocation.SOUND_SILENCE,
      debug: false
    ));
    
    // Explicitly silence again
    await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);

    // Load saved locations
    await _loadSavedLocations();
    
    // Check if we should auto-start tracking
    final prefs = await SharedPreferences.getInstance();
    final shouldTrack = prefs.getBool('isTracking') ?? false;
    if (shouldTrack) {
      await startTracking();
    }
  }

  // Start tracking location
  Future<void> startTracking() async {
    final state = await bg.BackgroundGeolocation.state;
    
    // Always silence first
    await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);
    
    if (!state.enabled) {
      // Silence sound again
      await bg.BackgroundGeolocation.setConfig(bg.Config(
        soundId: bg.BackgroundGeolocation.SOUND_SILENCE,
        debug: false,
        logLevel: bg.Config.LOG_LEVEL_OFF,
        foregroundServiceNotification: bg.Notification(
          sound: false,
          priority: bg.Config.NOTIFICATION_PRIORITY_MIN
        ),
        notification: bg.Notification(
          sound: false,
          priority: bg.Config.NOTIFICATION_PRIORITY_MIN
        )
      ));
      
      // Play silence again
      await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);
      
      // Start tracking - IMPORTANT: Start tracking AFTER silencing
      await bg.BackgroundGeolocation.start();
      print('📱 Location tracking started - sound disabled');
      
      // Set up API timer
      _setupApiTimer();
      
      // Save tracking state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isTracking', true);
    } else {
      // Ensure sounds remain silenced for running service
      await bg.BackgroundGeolocation.setConfig(bg.Config(
        soundId: bg.BackgroundGeolocation.SOUND_SILENCE,
        debug: false
      ));
      
      // Play silence once more
      await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);
      
      print('📱 Location tracking was already running - sound disabled');
      
      // Setup API timer
      _setupApiTimer();
    }
  }

  // Stop tracking location
  Future<void> stopTracking() async {
    final state = await bg.BackgroundGeolocation.state;
    if (state.enabled) {
      await bg.BackgroundGeolocation.stop();
      print('📱 Location tracking stopped');
      
      // Cancel API timer
      _apiTimer?.cancel();
      _apiTimer = null;
      
      // Save tracking state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isTracking', false);
    } else {
      print('📱 Location tracking was already stopped');
    }
  }

  // Setup API timer to call exactly every 10 seconds
  void _setupApiTimer() {
    // Cancel existing timer if any
    _apiTimer?.cancel();
    
    // Create a new timer that fires exactly every 10 seconds
    _apiTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      print('⏰ API timer triggered - sending locations to API');
      _sendLocationsToApi();
      
      // Also get a new location on timer trigger, but only if we haven't received one recently
      if (DateTime.now().millisecondsSinceEpoch - _lastSentTimestamp > 8000) {
        _getCurrentPositionAndSave();
      }
    });
    
    // Send immediately on setup, but don't get a new position yet
    _sendLocationsToApi();
  }

  // Manually refresh data from storage and send to API
  Future<void> refreshData() async {
    print('🔄 Manually refreshing location data');
    await _loadSavedLocations();
    
    // Only get current position during manual refresh if tracking is active
    final state = await bg.BackgroundGeolocation.state;
    if (state.enabled) {
      await _getCurrentPositionAndSave(isManualRefresh: true);
    }
    
    // Always send to API
    await _sendLocationsToApi();
  }
  
  // Get current location and save it
  Future<void> _getCurrentPositionAndSave({bool isManualRefresh = false}) async {
    try {
      final location = await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
        persist: true,
        extras: {'timer': true, 'manual': isManualRefresh}
      );
      
      final locationTimestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Check if this is a duplicate location (same coordinates within a short time frame)
      final isDuplicate = _checkIfDuplicateLocation(
        location.coords.latitude, 
        location.coords.longitude, 
        locationTimestamp
      );
      
      if (isDuplicate && !isManualRefresh) {
        print('🔄 Skipping duplicate location from timer at: ${location.coords.latitude}, ${location.coords.longitude}');
        return;
      }
      
      // Update last sent location
      _lastSentLatitude = location.coords.latitude;
      _lastSentLongitude = location.coords.longitude;
      _lastSentTimestamp = locationTimestamp;
      
      print('📍 ${isManualRefresh ? "Manual" : "Timer"} location check: ${location.coords.latitude}, ${location.coords.longitude}');
      
      final locationData = LocationData(
        id: locationTimestamp,
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
        timestamp: DateTime.now(),
      );
      
      _addLocation(locationData);
    } catch (e) {
      print('❌ Error getting ${isManualRefresh ? "manual" : "timer"} location: $e');
    }
  }
  
  // Check if this location is a duplicate of the last sent location
  bool _checkIfDuplicateLocation(double latitude, double longitude, int timestamp) {
    if (_lastSentLatitude == null || _lastSentLongitude == null) {
      return false;
    }
    
    // Check if coordinates are the same (allowing for tiny float variations)
    final sameCoordinates = 
        (latitude - _lastSentLatitude!).abs() < 0.0000001 && 
        (longitude - _lastSentLongitude!).abs() < 0.0000001;
    
    // Check if the timestamp is within a short window (8 seconds)
    final shortTimeWindow = timestamp - _lastSentTimestamp < 8000;
    
    return sameCoordinates && shortTimeWindow;
  }
  
  // Get current location and send to API
  Future<LocationData?> getCurrentLocation() async {
    try {
      final location = await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
        persist: true,
        extras: {'manual': true}
      );
      
      final locationTimestamp = DateTime.now().millisecondsSinceEpoch;
      
      print('📍 Manual location check: ${location.coords.latitude}, ${location.coords.longitude}');
      
      // Update last sent location
      _lastSentLatitude = location.coords.latitude;
      _lastSentLongitude = location.coords.longitude;
      _lastSentTimestamp = locationTimestamp;
      
      final locationData = LocationData(
        id: locationTimestamp,
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
        timestamp: DateTime.now(),
      );
      
      _addLocation(locationData);
      
      // Force API call after manual refresh
      _sendLocationsToApi();
      
      return locationData;
    } catch (e) {
      print('❌ Error getting current location: $e');
      return null;
    }
  }

  // Handle location update
  void _onLocation(bg.Location location) async {
    final locationTimestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Check if this is a duplicate location
    final isDuplicate = _checkIfDuplicateLocation(
      location.coords.latitude, 
      location.coords.longitude, 
      locationTimestamp
    );
    
    if (isDuplicate) {
      print('🔄 Skipping duplicate location update at: ${location.coords.latitude}, ${location.coords.longitude}');
      return;
    }
    
    // Update last sent location
    _lastSentLatitude = location.coords.latitude;
    _lastSentLongitude = location.coords.longitude;
    _lastSentTimestamp = locationTimestamp;
    
    print('📍 Location update: ${location.coords.latitude}, ${location.coords.longitude}');
    
    final locationData = LocationData(
      id: locationTimestamp,
      latitude: location.coords.latitude,
      longitude: location.coords.longitude,
      timestamp: DateTime.now(),
    );
    
    _addLocation(locationData);
  }

  // Handle heartbeat event
  void _onHeartbeat(bg.HeartbeatEvent event) {
    print('💓 Heartbeat received');
    
    // Check if it's been at least 8 seconds since the last location
    final now = DateTime.now().millisecondsSinceEpoch;
    final shouldGetLocation = now - _lastSentTimestamp > 8000;
    
    if (shouldGetLocation) {
      // Always get location on heartbeat if it's been a while
      bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1,
        persist: true,
        extras: {'heartbeat': true}
      ).then((bg.Location location) {
        final locationTimestamp = now;
        
        // Update last sent location
        _lastSentLatitude = location.coords.latitude;
        _lastSentLongitude = location.coords.longitude;
        _lastSentTimestamp = locationTimestamp;
        
        print('💓 Heartbeat location: ${location.coords.latitude}, ${location.coords.longitude}');
        
        // Create location data
        final locationData = LocationData(
          id: locationTimestamp,
          latitude: location.coords.latitude,
          longitude: location.coords.longitude,
          timestamp: DateTime.now(),
        );
        
        // Add to tracked locations
        _addLocation(locationData);
        
        // Always send on heartbeat
        _sendLocationsToApi();
      }).catchError((error) {
        print('❌ Error getting heartbeat location: $error');
      });
    } else {
      print('💓 Heartbeat received, but skipping location (too soon after last update)');
      // Always send any pending locations on heartbeat
      _sendLocationsToApi();
    }
    
    // Always retry failed requests on heartbeat
    _apiService.retryFailedRequests();
  }

  // Other event handlers
  void _onMotionChange(bg.Location location) {
    print('📱 Motion changed: ${location.isMoving}');
  }

  void _onProviderChange(bg.ProviderChangeEvent event) {
    print('📱 Provider changed: ${event.status}');
  }
  
  void _onActivityChange(bg.ActivityChangeEvent event) {
    print('📱 Activity changed: ${event.activity}, confidence: ${event.confidence}');
  }
  
  void _onEnabledChange(bool enabled) {
    print('📱 Enabled changed: $enabled');
    
    // After enabled state changes, make sure we reload locations
    _loadSavedLocations();
    
    // Reset API timer if enabled
    if (enabled) {
      _setupApiTimer();
    } else {
      _apiTimer?.cancel();
      _apiTimer = null;
    }
  }
  
  void _onConnectivityChange(bg.ConnectivityChangeEvent event) {
    print('📱 Connectivity changed: ${event.connected}');
    if (event.connected) {
      // Retry failed requests when connectivity is restored
      _apiService.retryFailedRequests();
      
      // Send any pending locations
      _sendLocationsToApi();
    }
  }
  
  void _onNotificationAction(String action) {
    print('📱 Notification action: $action');
    if (action == 'Stop Tracking') {
      stopTracking();
    }
  }

  // Add location to history and update stream
  void _addLocation(LocationData location) {
    // Check for existing location with same ID to avoid duplicates
    final existingIndex = _locationHistory.indexWhere((loc) => loc.id == location.id);
    if (existingIndex != -1) {
      print('📝 Location with ID ${location.id} already exists, updating');
      _locationHistory[existingIndex] = location;
    } else {
      _locationHistory.add(location);
      print('📝 Location added: ${location.latitude}, ${location.longitude}');
    }
    
    _locationStreamController.add(_locationHistory);
    _saveLocations();
  }

  // Send pending locations to API
  Future<void> _sendLocationsToApi() async {
    if (_locationHistory.isEmpty) return;
    
    // Get unsent locations
    final unsentLocations = _locationHistory.where((loc) => !loc.isSynced).toList();
    if (unsentLocations.isEmpty) {
      print('📡 No pending locations to send');
      return;
    }
    
    print('📡 Sending ${unsentLocations.length} locations to API in batch');
    
    // To avoid flooding, only send up to 10 locations (prioritizing the most recent ones)
    final locationsToSend = unsentLocations.length > 10 
        ? unsentLocations.sublist(unsentLocations.length - 10) 
        : unsentLocations;
    
    // Create a single batch payload instead of individual requests
    final batchSuccess = await _apiService.sendBatchLocationData(locationsToSend);
    
    if (batchSuccess) {
      // Mark all as synced
      for (final location in locationsToSend) {
        final index = _locationHistory.indexWhere((loc) => loc.id == location.id);
        if (index != -1) {
          _locationHistory[index] = LocationData(
            id: location.id,
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: location.timestamp,
            isSynced: true,
          );
        }
      }
      
      // Update timestamp after batch sending
      _lastApiCallTimestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Update UI and save
      _locationStreamController.add(_locationHistory);
      _saveLocations();
      
      print('✅ Successfully sent ${locationsToSend.length} locations to API');
    } else {
      print('❌ Failed to send batch locations to API');
    }
  }

  // Save locations to shared preferences
  Future<void> _saveLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Limit saved locations to the most recent 100 to prevent performance issues
      final locationsToSave = _locationHistory.length > 100 
          ? _locationHistory.sublist(_locationHistory.length - 100) 
          : _locationHistory;
          
      final locationsJson = locationsToSave.map((loc) => loc.toJson()).toList();
      await prefs.setString('locations', jsonEncode(locationsJson));
    } catch (e) {
      print('❌ Error saving locations: $e');
    }
  }

  // Load saved locations from shared preferences
  Future<void> _loadSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationsStr = prefs.getString('locations');
      
      if (locationsStr != null) {
        final List<dynamic> locationsJson = jsonDecode(locationsStr);
        final locations = locationsJson
            .map((json) => LocationData.fromJson(json))
            .toList();
        
        // Only replace if we have data to preserve any new locations
        if (locations.isNotEmpty) {
          // Merge with existing locations (keep only unique IDs)
          final existingIds = Set.from(_locationHistory.map((loc) => loc.id));
          final newLocations = locations.where((loc) => !existingIds.contains(loc.id)).toList();
          
          if (newLocations.isNotEmpty) {
            _locationHistory.addAll(newLocations);
            print('📝 Added ${newLocations.length} new locations from storage');
          }
          
          // Sort locations by timestamp
          _locationHistory.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          
          _locationStreamController.add(_locationHistory);
          
          print('📝 Loaded ${locations.length} locations from storage, merged ${newLocations.length} new ones');
        }
      }
    } catch (e) {
      print('❌ Error loading locations: $e');
    }
  }

  void dispose() {
    _locationStreamController.close();
    _apiTimer?.cancel();
  }
  
  // Static method for headless task in background/terminated mode
  static Future<void> headlessTask(bg.HeadlessEvent event) async {
    final String eventName = event.name;
    print('📱 [Headless] $eventName');
    
    // CRITICAL: Disable sounds in headless task
    await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);
    await bg.BackgroundGeolocation.setConfig(bg.Config(
      soundId: bg.BackgroundGeolocation.SOUND_SILENCE,
      debug: false,
      notification: bg.Notification(sound: false),
      foregroundServiceNotification: bg.Notification(sound: false)
    ));
    
    // Additional silence for debug sounds
    await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);
    
    // Process location event
    if (eventName == bg.Event.LOCATION) {
      try {
        final bg.Location location = event.event;
        print('📱 [Headless] location: ${location.coords.latitude}, ${location.coords.longitude}');
        
        // ... rest of headless task ...
      } catch (e) {
        print('❌ [Headless] Error handling location: $e');
      }
    }
  }

  // Delete specific locations
  Future<void> deleteLocations(List<int> locationIds) async {
    if (locationIds.isEmpty) return;
    
    try {
      // Remove from location history in memory
      _locationHistory.removeWhere((loc) => locationIds.contains(loc.id));
      
      // Update stream
      _locationStreamController.add(_locationHistory);
      
      // Save updated list to storage
      await _saveLocations();
      
      print('🗑️ Deleted ${locationIds.length} locations');
    } catch (e) {
      print('❌ Error deleting locations: $e');
    }
  }
  
  // Delete all locations
  Future<void> deleteAllLocations() async {
    try {
      // Clear location history
      _locationHistory.clear();
      
      // Update stream
      _locationStreamController.add(_locationHistory);
      
      // Save updated list to storage
      await _saveLocations();
      
      // Clear shared preferences data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('locations', '[]');
      
      print('🗑️ All locations deleted');
    } catch (e) {
      print('❌ Error deleting all locations: $e');
    }
  }
}
