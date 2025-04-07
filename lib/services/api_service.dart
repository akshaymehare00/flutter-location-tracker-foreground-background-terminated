import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/location_model.dart';

class ApiService {
  // Replace with your actual API endpoint
  final String apiUrl = 'https://sflpunch.sgwastech.in/apipunch/location-tracking/add-location-tracking/';
  final String batchApiUrl = 'https://sflpunch.sgwastech.in/apipunch/location-tracking/add-batch-location/';
  
  final int timeout = 15; // seconds
  
  // Prevent multiple simultaneous API calls
  bool _isCallInProgress = false;

  // Send a single location data to the API
  Future<bool> sendLocationData(LocationData locationData) async {
    if (_isCallInProgress) {
      print('🔄 Another API call in progress, queuing this request');
      _saveForBatchProcessing(locationData);
      return false;
    }
    
    _isCallInProgress = true;
    
    try {
      print('🌍 Sending location to API: ${locationData.latitude}, ${locationData.longitude}');

      // Create the request body
      final body = json.encode({
        'user_id': '111',
        'latitude': locationData.latitude.toString(),
        'longitude': locationData.longitude.toString(),
      });

      // Send the request
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(Duration(seconds: timeout));

      // Check if the request was successful
      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ API request successful: ${response.statusCode}');
        await _markAsSynced(locationData);
        _isCallInProgress = false;
        return true;
      } else {
        print('❌ API request failed with status: ${response.statusCode}');
        await _saveFailedRequest(locationData);
        _isCallInProgress = false;
        return false;
      }
    } catch (e) {
      print('❌ Error sending location to API: $e');
      await _saveFailedRequest(locationData);
      _isCallInProgress = false;
      return false;
    }
  }
  
  // Save location for batch processing
  Future<void> _saveForBatchProcessing(LocationData locationData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing batch queue
      final String? batchQueueJson = prefs.getString('batch_queue');
      List<Map<String, dynamic>> batchQueue = [];
      
      if (batchQueueJson != null) {
        batchQueue = List<Map<String, dynamic>>.from(json.decode(batchQueueJson));
      }
      
      // Check if this location ID already exists in the queue
      final existingIndex = batchQueue.indexWhere((item) => item['id'] == locationData.id);
      if (existingIndex != -1) {
        // Update existing location
        batchQueue[existingIndex] = locationData.toJson();
      } else {
        // Add this location to the batch queue
        batchQueue.add(locationData.toJson());
      }
      
      // Save back to SharedPreferences
      await prefs.setString('batch_queue', json.encode(batchQueue));
      print('📝 Saved location for batch processing');
    } catch (e) {
      print('❌ Error saving location for batch processing: $e');
    }
  }
  
  // Send multiple location data points to the API in a single request
  Future<bool> sendBatchLocationData(List<LocationData> locations) async {
    if (locations.isEmpty) return true;
    if (_isCallInProgress) {
      print('🔄 Another API call in progress, queuing this batch request');
      for (final location in locations) {
        await _saveForBatchProcessing(location);
      }
      return false;
    }
    
    _isCallInProgress = true;
    
    try {
      print('🌍 Sending batch of ${locations.length} locations to API');

      // Create the batch request body
      final locationsList = locations.map((loc) => {
        'user_id': '111',
        'latitude': loc.latitude.toString(),
        'longitude': loc.longitude.toString(),
      }).toList();
      
      final body = json.encode({
        'locations': locationsList
      });

      // Send the batch request - if batch endpoint is unavailable, fallback to single endpoint
      try {
        final response = await http.post(
          Uri.parse(batchApiUrl),
          headers: {
            'Content-Type': 'application/json',
          },
          body: body,
        ).timeout(Duration(seconds: timeout * 2)); // Double timeout for batch
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
          print('✅ Batch API request successful: ${response.statusCode}');
          for (final location in locations) {
            await _markAsSynced(location);
          }
          _isCallInProgress = false;
          return true;
        } else {
          // Fallback to individual requests if batch fails
          print('❌ Batch API request failed with status: ${response.statusCode}. Falling back to individual sends');
          final result = await _sendLocationsIndividually(locations);
          _isCallInProgress = false;
          return result;
        }
      } catch (e) {
        print('❌ Error sending batch to API, trying individual locations: $e');
        final result = await _sendLocationsIndividually(locations);
        _isCallInProgress = false;
        return result;
      }
    } catch (e) {
      print('❌ Error preparing batch request: $e');
      for (final location in locations) {
        await _saveFailedRequest(location);
      }
      _isCallInProgress = false;
      return false;
    }
  }
  
  // Fallback method to send locations individually if batch fails
  Future<bool> _sendLocationsIndividually(List<LocationData> locations) async {
    bool allSuccess = true;
    
    // Only try the most recent locations to avoid too many requests
    final locationsToSend = locations.length > 3 ? locations.sublist(locations.length - 3) : locations;
    
    for (final location in locationsToSend) {
      // Don't set _isCallInProgress here since we're already inside a batch operation
      try {
        print('🌍 Sending individual location to API: ${location.latitude}, ${location.longitude}');

        // Create the request body
        final body = json.encode({
          'user_id': '111',
          'latitude': location.latitude.toString(),
          'longitude': location.longitude.toString(),
        });

        // Send the request
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
          },
          body: body,
        ).timeout(Duration(seconds: timeout));

        // Check if the request was successful
        if (response.statusCode >= 200 && response.statusCode < 300) {
          print('✅ Individual API request successful: ${response.statusCode}');
          await _markAsSynced(location);
        } else {
          print('❌ Individual API request failed with status: ${response.statusCode}');
          await _saveFailedRequest(location);
          allSuccess = false;
        }
      } catch (e) {
        print('❌ Error sending individual location to API: $e');
        await _saveFailedRequest(location);
        allSuccess = false;
      }
    }
    
    return allSuccess;
  }

  // Mark location as synced in SharedPreferences
  Future<void> _markAsSynced(LocationData locationData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get the sync status map or create a new one
      final String? syncMapJson = prefs.getString('location_sync_status');
      Map<String, bool> syncMap = {};
      
      if (syncMapJson != null) {
        syncMap = Map<String, bool>.from(json.decode(syncMapJson));
      }
      
      // Mark this location as synced
      syncMap[locationData.id.toString()] = true;
      
      // Save back to SharedPreferences
      await prefs.setString('location_sync_status', json.encode(syncMap));
      
      // Also update the locations list in shared preferences
      final locationsStr = prefs.getString('locations') ?? '[]';
      final List<dynamic> locationsJson = jsonDecode(locationsStr);
      final locations = locationsJson
          .map((json) => LocationData.fromJson(json))
          .toList();
      
      // Find this location in the list
      final index = locations.indexWhere((loc) => loc.id == locationData.id);
      if (index != -1) {
        // Update the sync status
        locations[index] = LocationData(
          id: locationData.id,
          latitude: locationData.latitude,
          longitude: locationData.longitude,
          timestamp: locationData.timestamp,
          isSynced: true,
        );
        
        // Save back to SharedPreferences
        await prefs.setString('locations', jsonEncode(locations.map((loc) => loc.toJson()).toList()));
      }
      
      // Also remove from failed requests if present
      await _removeFromFailedRequests(locationData.id);
      
      // Also remove from batch queue if present
      await _removeFromBatchQueue(locationData.id);
    } catch (e) {
      print('❌ Error marking location as synced: $e');
    }
  }
  
  // Remove a location from the batch queue
  Future<void> _removeFromBatchQueue(int locationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing batch queue
      final String? batchQueueJson = prefs.getString('batch_queue');
      if (batchQueueJson == null) return;
      
      List<Map<String, dynamic>> batchQueue = List<Map<String, dynamic>>.from(json.decode(batchQueueJson));
      
      // Remove this location from the batch queue
      batchQueue.removeWhere((item) => item['id'] == locationId);
      
      // Save back to SharedPreferences
      await prefs.setString('batch_queue', json.encode(batchQueue));
    } catch (e) {
      print('❌ Error removing location from batch queue: $e');
    }
  }

  // Save failed requests to retry later
  Future<void> _saveFailedRequest(LocationData locationData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing failed requests
      final String? failedRequestsJson = prefs.getString('failed_location_requests');
      List<Map<String, dynamic>> failedRequests = [];
      
      if (failedRequestsJson != null) {
        failedRequests = List<Map<String, dynamic>>.from(json.decode(failedRequestsJson));
      }
      
      // Check if this location ID already exists
      final existingIndex = failedRequests.indexWhere((item) => item['id'] == locationData.id);
      if (existingIndex != -1) {
        // Update existing location
        failedRequests[existingIndex] = locationData.toJson();
      } else {
        // Add this request to the list
        failedRequests.add(locationData.toJson());
      }
      
      // Save back to SharedPreferences
      await prefs.setString('failed_location_requests', json.encode(failedRequests));
      print('📝 Saved failed request for later retry');
    } catch (e) {
      print('❌ Error saving failed request: $e');
    }
  }
  
  // Remove a location from failed requests
  Future<void> _removeFromFailedRequests(int locationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing failed requests
      final String? failedRequestsJson = prefs.getString('failed_location_requests');
      if (failedRequestsJson == null) return;
      
      List<Map<String, dynamic>> failedRequests = List<Map<String, dynamic>>.from(json.decode(failedRequestsJson));
      
      // Remove this location from failed requests
      failedRequests.removeWhere((item) => item['id'] == locationId);
      
      // Save back to SharedPreferences
      await prefs.setString('failed_location_requests', json.encode(failedRequests));
    } catch (e) {
      print('❌ Error removing location from failed requests: $e');
    }
  }

  // Retry failed requests - call this periodically or when connectivity is restored
  Future<void> retryFailedRequests() async {
    if (_isCallInProgress) {
      print('🔄 Another API call in progress, skipping retry of failed requests');
      return;
    }
    
    _isCallInProgress = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing failed requests
      final String? failedRequestsJson = prefs.getString('failed_location_requests');
      if (failedRequestsJson == null) {
        _isCallInProgress = false;
        return;
      }
      
      final List<dynamic> failedRequestsRaw = json.decode(failedRequestsJson);
      final List<LocationData> failedRequests = failedRequestsRaw
          .map((json) => LocationData.fromJson(json))
          .toList();
      
      if (failedRequests.isEmpty) {
        _isCallInProgress = false;
        return;
      }
      
      print('🔄 Retrying ${failedRequests.length} failed location requests');
      
      // Try to send batch first
      if (failedRequests.length > 1) {
        final batchSuccess = await sendBatchLocationData(failedRequests);
        if (batchSuccess) {
          // Clear all failed requests if batch was successful
          await prefs.setString('failed_location_requests', '[]');
          print('🔄 Batch retry complete. All ${failedRequests.length} requests succeeded');
          _isCallInProgress = false;
          return;
        }
      }
      
      // If batch fails or only one request, try individually
      List<Map<String, dynamic>> remainingFailedRequests = [];
      
      for (final locationData in failedRequests) {
        // Don't set _isCallInProgress here since we're already inside a retry operation
        try {
          print('🌍 Retrying individual location: ${locationData.latitude}, ${locationData.longitude}');

          // Create the request body
          final body = json.encode({
            'user_id': '111',
            'latitude': locationData.latitude.toString(),
            'longitude': locationData.longitude.toString(),
          });

          // Send the request
          final response = await http.post(
            Uri.parse(apiUrl),
            headers: {
              'Content-Type': 'application/json',
            },
            body: body,
          ).timeout(Duration(seconds: timeout));

          // Check if the request was successful
          if (response.statusCode >= 200 && response.statusCode < 300) {
            print('✅ Retry API request successful: ${response.statusCode}');
            await _markAsSynced(locationData);
          } else {
            print('❌ Retry API request failed with status: ${response.statusCode}');
            remainingFailedRequests.add(locationData.toJson());
          }
        } catch (e) {
          print('❌ Error retrying location: $e');
          remainingFailedRequests.add(locationData.toJson());
        }
      }
      
      // Save any remaining failed requests
      await prefs.setString('failed_location_requests', json.encode(remainingFailedRequests));
      print('🔄 Retry complete. ${failedRequests.length - remainingFailedRequests.length} succeeded, ${remainingFailedRequests.length} failed');
    } catch (e) {
      print('❌ Error retrying failed requests: $e');
    } finally {
      _isCallInProgress = false;
    }
  }
  
  // Process any queued batch requests
  Future<void> processBatchQueue() async {
    if (_isCallInProgress) {
      print('🔄 Another API call in progress, skipping batch queue processing');
      return;
    }
    
    _isCallInProgress = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get batch queue
      final String? batchQueueJson = prefs.getString('batch_queue');
      if (batchQueueJson == null) {
        _isCallInProgress = false;
        return;
      }
      
      final List<dynamic> batchQueueRaw = json.decode(batchQueueJson);
      final List<LocationData> batchQueue = batchQueueRaw
          .map((json) => LocationData.fromJson(json))
          .toList();
      
      if (batchQueue.isEmpty) {
        _isCallInProgress = false;
        return;
      }
      
      print('🔄 Processing ${batchQueue.length} locations from batch queue');
      
      // Send as batch
      final batchSuccess = await sendBatchLocationData(batchQueue);
      if (batchSuccess) {
        // Clear batch queue if successful
        await prefs.setString('batch_queue', '[]');
        print('🔄 Batch queue processing complete. All ${batchQueue.length} requests succeeded');
      } else {
        print('❌ Failed to process batch queue');
      }
    } catch (e) {
      print('❌ Error processing batch queue: $e');
    } finally {
      _isCallInProgress = false;
    }
  }
} 