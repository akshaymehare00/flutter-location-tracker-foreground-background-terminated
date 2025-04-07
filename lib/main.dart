import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'screens/home_screen.dart';
import 'providers/location_provider.dart';
import 'services/location_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // CRITICAL: Silence all sounds before configuring anything
  await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);
  
  // Quick config to disable sounds immediately
  await bg.BackgroundGeolocation.setConfig(bg.Config(
    debug: false, // CRITICAL - debug mode causes sounds
    logLevel: bg.Config.LOG_LEVEL_OFF,
    soundId: bg.BackgroundGeolocation.SOUND_SILENCE,
    stopOnTerminate: false,
    startOnBoot: true,
    enableHeadless: true
  ));
  
  // Play silence sound again to ensure no sound plays
  await bg.BackgroundGeolocation.playSound(bg.BackgroundGeolocation.SOUND_SILENCE);
  
  // Register headless task handler for background/terminated mode
  bg.BackgroundGeolocation.registerHeadlessTask(LocationService.headlessTask);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => LocationProvider(),
      child: MaterialApp(
        title: 'Location Tracker',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
