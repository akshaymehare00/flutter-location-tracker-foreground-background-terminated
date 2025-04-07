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
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Flutter engine configured")
    }
    
    override fun onResume() {
        super.onResume()
        Log.d(TAG, "MainActivity resumed")
        
        // Ensure notifications remain silent when app is resumed
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.setStreamVolume(AudioManager.STREAM_NOTIFICATION, 0, 0)
    }
    
    override fun onDestroy() {
        Log.d(TAG, "MainActivity destroyed but location tracking should continue in background")
        super.onDestroy()
    }
}
