package com.example.app5

import android.content.Context
import android.net.TrafficStats
import android.os.Handler
import android.os.Looper

class NetworkMonitor(private val context: Context) {
    
    var onNetworkActivityDetected: ((Boolean, String) -> Unit)? = null
    
    private val handler = Handler(Looper.getMainLooper())
    private var lastBytesReceived: Long = 0
    private var consecutiveActiveCount = 0
    
    fun startMonitoring() {
        lastBytesReceived = TrafficStats.getTotalRxBytes()
        handler.postDelayed(networkCheckRunnable, 3000)
    }
    
    fun stopMonitoring() {
        handler.removeCallbacks(networkCheckRunnable)
    }
    
    private val networkCheckRunnable = object : Runnable {
        override fun run() {
            checkNetworkActivity()
            handler.postDelayed(this, 3000)
        }
    }
    
    private fun checkNetworkActivity() {
        val currentBytes = TrafficStats.getTotalRxBytes()
        val bytesDiff = currentBytes - lastBytesReceived
        
        val isActive = bytesDiff > 50000 // 50KB threshold
        
        if (isActive) {
            consecutiveActiveCount++
        } else {
            consecutiveActiveCount = maxOf(0, consecutiveActiveCount - 1)
        }
        
        val confirmedActive = consecutiveActiveCount >= 2
        val activityType = determineActivityType(bytesDiff)
        
        onNetworkActivityDetected?.invoke(confirmedActive, activityType)
        lastBytesReceived = currentBytes
    }
    
    private fun determineActivityType(bytesDiff: Long): String {
        return when {
            bytesDiff > 150000 -> "Tải dữ liệu lớn"
            bytesDiff > 80000 -> "Web có ảnh"
            bytesDiff > 50000 -> "Lướt web"
            else -> "Mạng nhẹ"
        }
    }
}