class LocationData {
  final int id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isSynced;
  final String? errorMessage;
  final int retryCount;

  LocationData({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.isSynced = false,
    this.errorMessage,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'timestamp': timestamp.toIso8601String(),
      'isSynced': isSynced,
      'errorMessage': errorMessage,
      'retryCount': retryCount,
    };
  }

  Map<String, dynamic> toApiJson() {
    return {
      'user_id': 111, // Static user ID as per requirements
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
    };
  }

  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      id: json['id'],
      latitude: double.parse(json['latitude']),
      longitude: double.parse(json['longitude']),
      timestamp: DateTime.parse(json['timestamp']),
      isSynced: json['isSynced'] ?? false,
      errorMessage: json['errorMessage'],
      retryCount: json['retryCount'] ?? 0,
    );
  }

  // Create a copy of this location with updated properties
  LocationData copyWith({
    int? id,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    bool? isSynced,
    String? errorMessage,
    int? retryCount,
  }) {
    return LocationData(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      isSynced: isSynced ?? this.isSynced,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  // Check if this location is the same as another by comparing coordinates
  bool isSameLocation(LocationData other) {
    return (latitude - other.latitude).abs() < 0.0000001 && 
           (longitude - other.longitude).abs() < 0.0000001;
  }

  // Format timestamp to readable format
  String get formattedTimestamp {
    return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  // Get sync status text
  String get syncStatusText {
    if (isSynced) {
      return 'Synced';
    } else if (errorMessage != null) {
      return 'Error: ${errorMessage!}';
    } else if (retryCount > 0) {
      return 'Retrying ($retryCount)';
    } else {
      return 'Pending';
    }
  }
} 