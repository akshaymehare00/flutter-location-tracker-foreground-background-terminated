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
    // Listen to events
    bg.BackgroundGeolocation.onLocation(_onLocation);
    bg.BackgroundGeolocation.onMotionChange(_onMotionChange);
    bg.BackgroundGeolocation.onProviderChange(_onProviderChange);
    bg.BackgroundGeolocation.onHeartbeat(_onHeartbeat);
    bg.BackgroundGeolocation.onActivityChange(_onActivityChange);
    bg.BackgroundGeolocation.onEnabledChange(_onEnabledChange);
    bg.BackgroundGeolocation.onConnectivityChange(_onConnectivityChange);
    bg.BackgroundGeolocation.onNotificationAction(_onNotificationAction);
    // These methods aren't available in this version
    // bg.BackgroundGeolocation.onPowerSaveChange(_onPowerSaveChange);
    // bg.BackgroundGeolocation.onAppResume(_onAppResume);
    // bg.BackgroundGeolocation.onAppPause(_onAppPause);

    // Configure the plugin - simplified configuration with critical settings
    await bg.BackgroundGeolocation.ready(bg.Config(
      // Common config
      desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
      distanceFilter: 10.0,
      locationUpdateInterval: 10000, // 10 seconds
      fastestLocationUpdateInterval: 5000, // 5 seconds (allows faster updates when available)
      
      // Activity Recognition
      isMoving: true,
      
      // CRITICAL SETTINGS FOR BACKGROUND OPERATION
      stopOnTerminate: false,
      startOnBoot: true,
      enableHeadless: true,
      heartbeatInterval: 60, // 1 minute for heartbeat
      preventSuspend: true,
      
      // Debug settings
      debug: true,
      logLevel: bg.Config.LOG_LEVEL_VERBOSE,
      
      // Notification configuration
      notification: bg.Notification(
        title: "Location Tracking",
        text: "Tracking your location in background",
        channelName: "Background Location",
        smallIcon: "drawable/ic_launcher",
        sticky: true,
        priority: bg.Config.NOTIFICATION_PRIORITY_HIGH,
        actions: ["Stop Tracking"]
      ),
      
      // Important for battery saving but allow more frequent updates
      pausesLocationUpdatesAutomatically: false,
      
      // Extras to include with each location
      extras: {
        "app_name": "location_tracking",
        "user_id": "111"
      }
    ));

    // Load saved locations
    await _loadSavedLocations();
    
    // Check if we should automatically start tracking
    final prefs = await SharedPreferences.getInstance();
    final shouldTrack = prefs.getBool('isTracking') ?? false;
    if (shouldTrack) {
      await startTracking();
    }
  }

  // Start tracking location
  Future<void> startTracking() async {
    final state = await bg.BackgroundGeolocation.state;
    if (!state.enabled) {
      // Set some enhanced config for this session
      await bg.BackgroundGeolocation.setConfig(bg.Config(
        // Force more frequent tracking
        heartbeatInterval: 60, // 1 minute for heartbeat
        preventSuspend: true,
        locationUpdateInterval: 10000, // 10 seconds
        fastestLocationUpdateInterval: 5000, // 5 seconds (allows faster updates when available)
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        notification: bg.Notification(
          title: "Location Tracking Active",
          text: "Tracking your location in background",
          priority: bg.Config.NOTIFICATION_PRIORITY_HIGH,
          sticky: true
        )
      ));
      
      // Start tracking
      await bg.BackgroundGeolocation.start();
      print('📱 Location tracking started with more frequent updates');
      
      // This timer will force an API call every 10 seconds exactly
      _setupApiTimer();
      
      // Save tracking state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isTracking', true);
    } else {
      print('📱 Location tracking was already running');
      
      // Setup API timer if tracking is already running
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
  
  // Static method to handle headless task
  @pragma('vm:entry-point')
  static Future<void> headlessTask(bg.HeadlessEvent event) async {
    print('📱 Headless task received event: ${event.name}');
    
    try {
      // Create API service
      final ApiService apiService = ApiService();
      
      // Create shared timestamp for all headless events
      final prefs = await SharedPreferences.getInstance();
      int lastHeadlessApiCall = prefs.getInt('last_headless_api_call') ?? 0;
      int now = DateTime.now().millisecondsSinceEpoch;
      
      if (event.name == 'location') {
        // Handle location event
        final bg.Location location = event.event;
        
        // Get previous location data, if any
        String? lastLocationJson = prefs.getString('last_location_headless');
        double? lastLat;
        double? lastLng;
        int? lastTimestamp;
        
        if (lastLocationJson != null) {
          Map<String, dynamic> lastLocation = jsonDecode(lastLocationJson);
          lastLat = double.parse(lastLocation['latitude']);
          lastLng = double.parse(lastLocation['longitude']);
          lastTimestamp = lastLocation['timestamp'];
          
          // Check if this is a duplicate location (same coordinates within 8 seconds)
          bool isDuplicate = (lastLat - location.coords.latitude).abs() < 0.0000001 && 
                            (lastLng - location.coords.longitude).abs() < 0.0000001 && 
                            (now - lastTimestamp!) < 8000;
                            
          if (isDuplicate) {
            print('🔄 Skipping duplicate headless location: ${location.coords.latitude}, ${location.coords.longitude}');
            return;
          }
        }
        
        // Save this location as the last one
        Map<String, dynamic> currentLocation = {
          'latitude': location.coords.latitude.toString(),
          'longitude': location.coords.longitude.toString(),
          'timestamp': now
        };
        await prefs.setString('last_location_headless', jsonEncode(currentLocation));
        
        print('📍 Headless location: ${location.coords.latitude}, ${location.coords.longitude}');
        
        // Create location data
        final locationData = LocationData(
          id: now,
          latitude: location.coords.latitude,
          longitude: location.coords.longitude,
          timestamp: DateTime.now(),
        );
        
        // Save to SharedPreferences - we'll batch process these later
        try {
          final locationsStr = prefs.getString('locations') ?? '[]';
          final List<dynamic> locationsJson = jsonDecode(locationsStr);
          final locations = locationsJson
              .map((json) => LocationData.fromJson(json))
              .toList();
          
          // Check if this location ID already exists
          final existingIndex = locations.indexWhere((loc) => loc.id == locationData.id);
          if (existingIndex != -1) {
            // Update existing location
            locations[existingIndex] = locationData;
          } else {
            // Add new location
            locations.add(locationData);
          }
          
          // Only keep most recent 100 locations
          final locationsToSave = locations.length > 100 
              ? locations.sublist(locations.length - 100) 
              : locations;
          
          await prefs.setString('locations', jsonEncode(locationsToSave.map((loc) => loc.toJson()).toList()));
          print('💾 Saved headless location to storage');
          
          // Force API calls in headless mode every 10 seconds
          if ((now - lastHeadlessApiCall) >= API_CALL_INTERVAL) {
            // Get unsent locations (last 10 at most)
            final unsentLocations = locationsToSave
                .where((loc) => !loc.isSynced)
                .toList();
            
            if (unsentLocations.isNotEmpty) {
              final batchToSend = unsentLocations.length > 10 
                  ? unsentLocations.sublist(unsentLocations.length - 10) 
                  : unsentLocations;
              
              final success = await apiService.sendBatchLocationData(batchToSend);
              
              if (success) {
                // Mark sent locations as synced
                for (final sentLocation in batchToSend) {
                  final index = locationsToSave.indexWhere((loc) => loc.id == sentLocation.id);
                  if (index != -1) {
                    locationsToSave[index] = LocationData(
                      id: sentLocation.id,
                      latitude: sentLocation.latitude,
                      longitude: sentLocation.longitude,
                      timestamp: sentLocation.timestamp,
                      isSynced: true,
                    );
                  }
                }
                
                // Save updated sync status
                await prefs.setString('locations', jsonEncode(locationsToSave.map((loc) => loc.toJson()).toList()));
                await prefs.setInt('last_headless_api_call', now);
                print('📡 Sent ${batchToSend.length} locations from headless task');
              }
            }
          } else {
            print('📡 Headless location saved, waiting for timer to send (${API_CALL_INTERVAL - (now - lastHeadlessApiCall)}ms remaining)');
          }
        } catch (e) {
          print('❌ Error saving/sending headless location: $e');
        }
      } else if (event.name == 'heartbeat') {
        print('💓 Headless heartbeat received');
        
        // Always force API calls on heartbeat
        // Get stored locations
        final locationsStr = prefs.getString('locations') ?? '[]';
        final List<dynamic> locationsJson = jsonDecode(locationsStr);
        final locations = locationsJson
            .map((json) => LocationData.fromJson(json))
            .toList();
        
        // Get unsent locations
        final unsentLocations = locations
            .where((loc) => !loc.isSynced)
            .toList();
            
        if (unsentLocations.isNotEmpty) {
          final batchToSend = unsentLocations.length > 10 
              ? unsentLocations.sublist(unsentLocations.length - 10) 
              : unsentLocations;
          
          final success = await apiService.sendBatchLocationData(batchToSend);
          
          if (success) {
            // Mark sent locations as synced
            for (final sentLocation in batchToSend) {
              final index = locations.indexWhere((loc) => loc.id == sentLocation.id);
              if (index != -1) {
                locations[index] = LocationData(
                  id: sentLocation.id,
                  latitude: sentLocation.latitude,
                  longitude: sentLocation.longitude,
                  timestamp: sentLocation.timestamp,
                  isSynced: true,
                );
              }
            }
            
            // Save updated sync status
            await prefs.setString('locations', jsonEncode(locations.map((loc) => loc.toJson()).toList()));
            await prefs.setInt('last_headless_api_call', now);
            print('📡 Sent ${batchToSend.length} locations from heartbeat in headless task');
          }
        }
          
        // Get last location timestamp
        String? lastLocationJson = prefs.getString('last_location_headless');
        int lastTimestamp = 0;
        if (lastLocationJson != null) {
          Map<String, dynamic> lastLocation = jsonDecode(lastLocationJson);
          lastTimestamp = lastLocation['timestamp'];
        }
        
        // Only get a new location if it's been at least 8 seconds
        if (now - lastTimestamp >= 8000) {
          try {
            bg.BackgroundGeolocation.getCurrentPosition(
              samples: 1,
              persist: true,
              extras: {'heartbeat': true}
            ).then((bg.Location location) {
              final locationData = LocationData(
                id: now,
                latitude: location.coords.latitude,
                longitude: location.coords.longitude,
                timestamp: DateTime.now(),
              );
              
              // Save this location as the last one
              Map<String, dynamic> currentLocation = {
                'latitude': location.coords.latitude.toString(),
                'longitude': location.coords.longitude.toString(),
                'timestamp': now
              };
              prefs.setString('last_location_headless', jsonEncode(currentLocation));
              
              // Save the new location to storage
              final updatedLocations = [...locations, locationData];
              final locationsToSave = updatedLocations.length > 100 
                  ? updatedLocations.sublist(updatedLocations.length - 100) 
                  : updatedLocations;
                  
              prefs.setString('locations', jsonEncode(locationsToSave.map((loc) => loc.toJson()).toList()));
              print('💓 Heartbeat location saved in headless mode');
              
              // Send the new location immediately
              apiService.sendLocationData(locationData);
            });
          } catch (e) {
            print('❌ Error getting heartbeat location in headless mode: $e');
          }
        } else {
          print('💓 Skipping heartbeat location (too soon after last update)');
        }
      } else if (event.name == 'connectivitychange') {
        // Network connectivity changed - retry failed requests
        final bg.ConnectivityChangeEvent connectivityEvent = event.event;
        if (connectivityEvent.connected) {
          print('🌐 Network connectivity restored in headless mode - retrying requests');
          await apiService.retryFailedRequests();
        }
      }
    } catch (e) {
      print('❌ Error in headless task: $e');
    }
  }
}
