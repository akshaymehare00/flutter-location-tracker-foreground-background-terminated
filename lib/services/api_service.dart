import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/location_model.dart';

class ApiService {
  // Replace with your actual API endpoint
  final String apiUrl = 'prefix/add-location-tracking/';
  final String batchApiUrl = 'prefix/add-batch-location/';
  
  final int timeout = 15; // seconds

  // Send a single location data to the API
  Future<bool> sendLocationData(LocationData locationData) async {
    try {
      print('🌍 Sending location to API: ${locationData.latitude}, ${locationData.longitude}');

      // Create the request body
      final body = json.encode({
        'user_id': '111',
        'latitude': locationData.latitude,
        'longitude': locationData.longitude,
        'timestamp': locationData.timestamp.toIso8601String(),
        'id': locationData.id,
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
        _markAsSynced(locationData);
        return true;
      } else {
        print('❌ API request failed with status: ${response.statusCode}');
        _saveFailedRequest(locationData);
        return false;
      }
    } catch (e) {
      print('❌ Error sending location to API: $e');
      _saveFailedRequest(locationData);
      return false;
    }
  }
  
  // Send multiple location data points to the API in a single request
  Future<bool> sendBatchLocationData(List<LocationData> locations) async {
    if (locations.isEmpty) return true;
    
    try {
      print('🌍 Sending batch of ${locations.length} locations to API');

      // Create the batch request body
      final locationsList = locations.map((loc) => {
        'user_id': '111',
        'latitude': loc.latitude,
        'longitude': loc.longitude,
        'timestamp': loc.timestamp.toIso8601String(),
        'id': loc.id,
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
            _markAsSynced(location);
          }
          return true;
        } else {
          // Fallback to individual requests if batch fails
          print('❌ Batch API request failed with status: ${response.statusCode}. Falling back to individual sends');
          return _sendLocationsIndividually(locations);
        }
      } catch (e) {
        print('❌ Error sending batch to API, trying individual locations: $e');
        return _sendLocationsIndividually(locations);
      }
    } catch (e) {
      print('❌ Error preparing batch request: $e');
      for (final location in locations) {
        _saveFailedRequest(location);
      }
      return false;
    }
  }
  
  // Fallback method to send locations individually if batch fails
  Future<bool> _sendLocationsIndividually(List<LocationData> locations) async {
    bool allSuccess = true;
    
    // Only try the most recent locations to avoid too many requests
    final locationsToSend = locations.length > 3 ? locations.sublist(locations.length - 3) : locations;
    
    for (final location in locationsToSend) {
      final success = await sendLocationData(location);
      if (!success) {
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
    } catch (e) {
      print('❌ Error marking location as synced: $e');
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
      
      // Add this request to the list
      failedRequests.add(locationData.toJson());
      
      // Save back to SharedPreferences
      await prefs.setString('failed_location_requests', json.encode(failedRequests));
      print('📝 Saved failed request for later retry');
    } catch (e) {
      print('❌ Error saving failed request: $e');
    }
  }

  // Retry failed requests - call this periodically or when connectivity is restored
  Future<void> retryFailedRequests() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing failed requests
      final String? failedRequestsJson = prefs.getString('failed_location_requests');
      if (failedRequestsJson == null) return;
      
      final List<dynamic> failedRequestsRaw = json.decode(failedRequestsJson);
      final List<LocationData> failedRequests = failedRequestsRaw
          .map((json) => LocationData.fromJson(json))
          .toList();
      
      if (failedRequests.isEmpty) return;
      
      print('🔄 Retrying ${failedRequests.length} failed location requests');
      
      // Try to send batch first
      if (failedRequests.length > 1) {
        final batchSuccess = await sendBatchLocationData(failedRequests);
        if (batchSuccess) {
          // Clear all failed requests if batch was successful
          await prefs.setString('failed_location_requests', '[]');
          print('🔄 Batch retry complete. All ${failedRequests.length} requests succeeded');
          return;
        }
      }
      
      // If batch fails or only one request, try individually
      List<Map<String, dynamic>> remainingFailedRequests = [];
      
      for (final locationData in failedRequests) {
        final success = await sendLocationData(locationData);
        if (!success) {
          remainingFailedRequests.add(locationData.toJson());
        }
      }
      
      // Save any remaining failed requests
      await prefs.setString('failed_location_requests', json.encode(remainingFailedRequests));
      print('🔄 Retry complete. ${failedRequests.length - remainingFailedRequests.length} succeeded, ${remainingFailedRequests.length} failed');
    } catch (e) {
      print('❌ Error retrying failed requests: $e');
    }
  }
} 