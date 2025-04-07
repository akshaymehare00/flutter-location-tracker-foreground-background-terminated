# Flutter Background Location Tracking

![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-2.19+-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

A robust, production-ready Flutter application for tracking location in foreground, background, and even when the app is terminated. This implementation features reliable 10-second API interval updates, persistent background execution, and visual sync status indicators.

## 📱 Features

- **Continuous Location Tracking**: Works in foreground, background, and terminated states
- **Precise 10-Second API Updates**: Sends location data at exact 10-second intervals
- **Offline Mode**: Stores locations when offline and synchronizes when connection is restored
- **Sync Status Indicators**: Visual feedback showing which locations are synced or pending
- **Batch API Processing**: Efficiently sends multiple locations in a single request
- **Battery Optimized**: Implements strategies to minimize battery consumption
- **Enhanced UI**: Modern interface with pull-to-refresh and status indicators
- **Headless Execution**: Keeps tracking when the app is terminated
- **Native Android Implementation**: Uses Java receivers for enhanced reliability

## 📸 Screenshots

<table>
  <tr>
    <td align="center">Home Screen</td>
    <td align="center">Location History</td>
    <td align="center">Sync Status</td>
  </tr>
  <tr>
    <td><img src="screenshots/home_screen.png" width="220"></td>
    <td><img src="screenshots/location_history.png" width="220"></td>
    <td><img src="screenshots/sync_status.png" width="220"></td>
  </tr>
</table>

## 🔧 Installation

1. Clone the repository:

```bash
git clone https://github.com/akshaymehare00/flutter-location-tracker-foreground-background-terminated.git
cd flutter-location-tracker-foreground-background-terminated
flutter pub get
```

2. Or add as a dependency in your `pubspec.yaml`:

```yaml
dependencies:
  flutter_background_location:
    git:
      url: https://github.com/akshaymehare00/flutter-location-tracker-foreground-background-terminated.git
```

## 📋 Requirements

- Flutter 3.0+
- Dart 2.19.3+
- Android: minSdkVersion 21 (Android 5.0)
- iOS: iOS 12.0+

## 🚀 Usage

### Initialize the service

In your `main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:provider/provider.dart';
import 'package:new_location_tracking/services/location_service.dart';
import 'package:new_location_tracking/providers/location_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register headless task
  bg.BackgroundGeolocation.registerHeadlessTask(LocationService.headlessTask);
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationProvider()),
      ],
      child: MyApp(),
    ),
  );
}
```

### Start location tracking

```dart
// Using the LocationProvider
final provider = Provider.of<LocationProvider>(context, listen: false);
provider.startTracking();

// Or directly using LocationService
await LocationService.instance.startTracking();
```

### Stop location tracking

```dart
final provider = Provider.of<LocationProvider>(context, listen: false);
provider.stopTracking();
```

### Refreshing data manually

```dart
await provider.refreshData();
```

## 🏗️ Architecture

This application follows a clean architecture approach with:

1. **Services Layer**: Core functionality for location tracking and API communication
   - `location_service.dart`: Manages location tracking and background execution
   - `api_service.dart`: Handles API communication with retry mechanisms

2. **Provider Layer**: State management for UI components
   - `location_provider.dart`: Provides location data and tracking status to UI

3. **UI Layer**: User interface components
   - `home_screen.dart`: Main screen with location history and controls
   - `location_card.dart`: Visual representation of location with sync status

4. **Model Layer**: Data models
   - `location_model.dart`: Represents location data with sync status

## 🔄 API Communication

The application implements a dual API strategy:

1. **Individual API**: `https://sflpunch.sgwastech.in/apipunch/location-tracking/add-location-tracking/`
   - Used for single location updates
   - Fallback when batch fails

2. **Batch API**: `https://sflpunch.sgwastech.in/apipunch/location-tracking/add-batch-location/`
   - More efficient for multiple locations
   - Reduces network usage and battery consumption

### API Payload Format

Individual:
```json
{
  "user_id": 111,
  "latitude": "20.9240645",
  "longitude": "77.7610111"
}
```

Batch:
```json
{
  "locations": [
    {
      "user_id": 111,
      "latitude": "20.9240645",
      "longitude": "77.7610111"
    },
    {
      "user_id": 111,
      "latitude": "20.9240647",
      "longitude": "77.7610115"
    }
  ]
}
```

## 📱 Android Setup

Add the following to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.INTERNET" />

<!-- Services for background geolocation -->
<service android:name="com.transistorsoft.locationmanager.service.TrackingService" android:foregroundServiceType="location" />
<service android:name="com.transistorsoft.locationmanager.service.LocationRequestService" android:foregroundServiceType="location" />

<!-- Custom receiver for enhanced reliability -->
<meta-data android:name="com.transistorsoft.locationmanager.adapter.BackgroundGeolocation" android:value="com.example.new_location_tracking.receivers.LocationReceiver" />
```

## 📱 iOS Setup

Add the following to your `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app requires location permissions to track your position.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app requires background location permissions to track your position even when the app is closed.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>This app requires background location permissions to track your position even when the app is closed.</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
    <string>processing</string>
</array>
```

## 🔧 Customization

### API URL Configuration

Update the API endpoints in `lib/services/api_service.dart`:

```dart
final String apiUrl = 'https://your-api-endpoint.com/location/add';
final String batchApiUrl = 'https://your-api-endpoint.com/location/add-batch';
```

### Tracking Intervals

Modify the location update and API call intervals in `lib/services/location_service.dart`:

```dart
// API call interval (milliseconds)
static const int API_CALL_INTERVAL = 10000; // 10 seconds

// Location tracking config
await bg.BackgroundGeolocation.ready(bg.Config(
  locationUpdateInterval: 10000, // 10 seconds
  // Other options...
));
```

## 🧪 Testing

To verify the implementation:

1. Install the app on a device
2. Start location tracking
3. Close the app (force close if needed)
4. Move around to different locations
5. Reopen the app and verify that locations were tracked and sent to the API
6. Check the server logs to confirm receipt of location data every 10 seconds

## 🔧 Troubleshooting

### Common Issues

1. **Location tracking stops in background**
   - Ensure `stopOnTerminate: false` is set
   - Verify that the headless task is registered
   - Check Android permission for background location

2. **API sending fails**
   - Verify network connectivity
   - Check API endpoint URLs
   - Ensure proper payload formatting

3. **Battery drain issues**
   - Adjust `locationUpdateInterval` to a higher value
   - Set `pausesLocationUpdatesAutomatically: true` for less frequent updates when stationary

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 Pushing to GitHub

To push this code to GitHub, follow these steps:

```bash
# Initialize git repository (if not already done)
git init

# Add all files
git add .

# Commit changes
git commit -m "Initial commit: Flutter background location tracking implementation"

# Add remote repository
git remote add origin https://github.com/akshaymehare00/flutter-location-tracker-foreground-background-terminated.git

# Push to main branch
git push -u origin main
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

**Akshay Mehare**
- GitHub: [@akshaymehare00](https://github.com/akshaymehare00)

## 🙏 Acknowledgments

- [flutter_background_geolocation](https://github.com/transistorsoft/flutter_background_geolocation) for the powerful background geolocation plugin
- Flutter community for continuous support and inspiration
