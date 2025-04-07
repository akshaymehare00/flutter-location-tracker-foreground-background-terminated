package com.example.new_location_tracking

import android.app.Application
import android.content.Context
import android.media.AudioManager
import android.app.NotificationManager
import android.os.Build
import io.flutter.app.FlutterApplication

class MainApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()

        // Disable notification sounds at application level
        try {
            // Set notification volume to 0
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.setStreamVolume(AudioManager.STREAM_NOTIFICATION, 0, 0)
            
            // Set notification importance to min
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channels = notificationManager.notificationChannels
                for (channel in channels) {
                    if (channel.importance > NotificationManager.IMPORTANCE_LOW) {
                        // Create a new channel with same ID but lower importance
                        val newChannel = android.app.NotificationChannel(
                            channel.id,
                            channel.name,
                            NotificationManager.IMPORTANCE_LOW
                        )
                        newChannel.description = channel.description
                        newChannel.setSound(null, null)
                        newChannel.enableVibration(false)
                        newChannel.enableLights(false)
                        notificationManager.createNotificationChannel(newChannel)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
} 