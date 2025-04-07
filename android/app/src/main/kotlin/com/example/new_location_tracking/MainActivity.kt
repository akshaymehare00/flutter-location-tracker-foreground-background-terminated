package com.example.new_location_tracking

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.os.Bundle
import android.util.Log
import android.media.AudioManager
import android.app.NotificationManager
import android.content.Context

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity created")
        
        // Force silent mode for the entire application
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.setStreamVolume(AudioManager.STREAM_NOTIFICATION, 0, 0)
        
        // Set Do Not Disturb mode if possible
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (notificationManager.isNotificationPolicyAccessGranted) {
            notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
        }
        
        // Disable all sounds for background geolocation plugin
        try {
            // Set plugin-specific sound settings to silent
            val locationManager = Class.forName("com.transistorsoft.locationmanager.LocationManager")
            val getInstance = locationManager.getMethod("getInstance", Context::class.java)
            val instance = getInstance.invoke(null, this)
            
            // Use reflection to set sound to false
            val configClass = Class.forName("com.transistorsoft.locationmanager.config.Config")
            val config = configClass.getConstructor().newInstance()
            
            // Set sound to false
            val soundField = configClass.getField("sound")
            soundField.set(config, false)
            
            // Apply the config
            val setConfigMethod = locationManager.getMethod("setConfig", configClass)
            setConfigMethod.invoke(instance, config)
        } catch (e: Exception) {
            // Log error but continue
            println("Error disabling background geolocation sounds: ${e.message}")
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Flutter engine configured")
    }
    
    override fun onResume() {
        super.onResume()
        Log.d(TAG, "MainActivity resumed")
    }
    
    override fun onDestroy() {
        Log.d(TAG, "MainActivity destroyed but location tracking should continue in background")
        super.onDestroy()
    }
}
