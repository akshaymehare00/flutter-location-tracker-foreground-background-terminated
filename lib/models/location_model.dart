class LocationData {
  final int id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isSynced;

  LocationData({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.isSynced = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'timestamp': timestamp.toIso8601String(),
      'isSynced': isSynced,
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
    );
  }
} 