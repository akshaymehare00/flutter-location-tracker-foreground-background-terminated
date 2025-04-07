import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'services/location_service.dart';
import 'providers/location_provider.dart';
import 'screens/home_screen.dart';

// Register headless task handler
@pragma('vm:entry-point')
void headlessTaskCallback(bg.HeadlessEvent headlessEvent) async {
  print('⚙️ [Headless Task] - ${headlessEvent.name}');
  await LocationService.headlessTask(headlessEvent);
}

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register the headless task
  bg.BackgroundGeolocation.registerHeadlessTask(headlessTaskCallback);
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final LocationProvider _locationProvider = LocationProvider();

  @override
  void initState() {
    super.initState();
    _initializeLocationService();
  }

  Future<void> _initializeLocationService() async {
    try {
      print('📱 Initializing location service');
      // Initialize the location service
      await LocationService.instance.initialize();
    } catch (e) {
      print('❌ Error initializing location service: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _locationProvider,
      child: MaterialApp(
        title: 'Location Tracking',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
  
  @override
  void dispose() {
    LocationService.instance.dispose();
    super.dispose();
  }
}
