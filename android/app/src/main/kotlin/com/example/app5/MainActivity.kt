package com.example.app5

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
    private lateinit var unlockMonitor: UnlockMonitor
    private lateinit var eventChannel: EventChannel
    
    private val permissions = arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION,
        Manifest.permission.READ_PHONE_STATE
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Kiểm tra và yêu cầu permissions
        if (!hasPermissions()) {
            ActivityCompat.requestPermissions(this, permissions, 100)
        }
        
        unlockMonitor = UnlockMonitor(this)
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.app/monitor_events")
        eventChannel.setStreamHandler(unlockMonitor)
    }
    
    private fun hasPermissions(): Boolean {
        return permissions.all { permission ->
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        unlockMonitor.stopMonitoring()
    }
}