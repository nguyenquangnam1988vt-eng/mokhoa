package com.example.app5

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject
import kotlin.math.*

class UnlockMonitor(private val context: Context) : EventChannel.StreamHandler, 
                                                    SensorEventListener, 
                                                    LocationListener {
    
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var sensorManager: SensorManager
    private lateinit var locationManager: LocationManager
    private lateinit var callDetector: CallDetectorManager
    private lateinit var networkMonitor: NetworkMonitor
    
    // Biến trạng thái
    private var currentSpeed: Double = 0.0
    private var isDriving = false
    private var isNetworkActive = false
    private var isActiveBrowsing = false
    private var isInCall = false
    
    // Tilt monitoring
    private val zAccelerationHistory = mutableListOf<Double>()
    private val zStabilityBufferSize = 50
    private var zStability: Double = 0.0
    
    // Ngưỡng
    private val drivingSpeedThreshold = 10.0 // km/h
    private val viewingPhoneThreshold = 80.0
    private val intermediateThreshold = 90.0
    
    private val handler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
        startMonitoring()
        sendEventToFlutter("MONITOR_STATUS", "Android monitoring started")
    }

    override fun onCancel(arguments: Any?) {
        stopMonitoring()
        eventSink = null
    }

    fun startMonitoring() {
        setupSensors()
        setupLocationMonitoring()
        setupCallDetection()
        setupNetworkMonitoring()
    }

    fun stopMonitoring() {
        try {
            sensorManager.unregisterListener(this)
            locationManager.removeUpdates(this)
            callDetector.stopMonitoring()
            networkMonitor.stopMonitoring()
        } catch (e: Exception) {
            // Ignore errors during cleanup
        }
    }

    private fun setupSensors() {
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_NORMAL)
    }

    private fun setupLocationMonitoring() {
        locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        
        try {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000L, // 1 second
                2f,    // 2 meters
                this
            )
        } catch (e: SecurityException) {
            sendEventToFlutter("ERROR", "Location permission denied: ${e.message}")
        } catch (e: Exception) {
            sendEventToFlutter("ERROR", "Location error: ${e.message}")
        }
    }

    private fun setupCallDetection() {
        callDetector = CallDetectorManager(context)
        callDetector.onCallStateChanged = { isInCall, callType ->
            this.isInCall = isInCall
            val eventData = mapOf(
                "type" to "CALL_EVENT",
                "message" to if (isInCall) "Đang trong cuộc gọi điện thoại" else "Đã kết thúc cuộc gọi",
                "isInCall" to isInCall,
                "callState" to callType,
                "timestamp" to System.currentTimeMillis()
            )
            sendEventToFlutter(eventData)
            
            // Kiểm tra cảnh báo nếu đang lái xe
            if (isInCall && isDriving) {
                sendDangerAlert("CALL", "Đang lái xe và NGHE ĐIỆN THOẠI!")
            }
        }
        callDetector.startMonitoring()
    }

    private fun setupNetworkMonitoring() {
        networkMonitor = NetworkMonitor(context)
        networkMonitor.onNetworkActivityDetected = { isActive, activityType ->
            this.isNetworkActive = isActive
            this.isActiveBrowsing = isActive
            
            val eventData = mapOf(
                "type" to "REAL_NETWORK_ANALYSIS",
                "message" to if (isActive) "Đang có hoạt động web ($activityType)" else "Không có hoạt động web",
                "isActiveBrowsing" to isActive,
                "activityType" to activityType,
                "timestamp" to System.currentTimeMillis()
            )
            sendEventToFlutter(eventData)
            
            // Kiểm tra cảnh báo nếu đang lái xe
            if (isActive && isDriving) {
                sendDangerAlert("WEB", "Đang lái xe và LƯỚT WEB!")
            }
        }
        networkMonitor.startMonitoring()
    }

    // SensorEventListener implementation
    override fun onSensorChanged(event: SensorEvent?) {
        event?.let {
            if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
                val zAcceleration = event.values[2].toDouble()
                updateZStability(zAcceleration)
                handleTiltDetection(zAcceleration)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // LocationListener implementation
    override fun onLocationChanged(location: Location) {
        val speed = location.speed.toDouble() * 3.6 // Convert to km/h
        currentSpeed = speed
        val wasDriving = isDriving
        isDriving = speed >= drivingSpeedThreshold
        
        val locationData = mapOf(
            "type" to "LOCATION_UPDATE",
            "speed" to currentSpeed,
            "isDriving" to isDriving,
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "timestamp" to System.currentTimeMillis()
        )
        sendEventToFlutter(locationData)
    }

    override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
    override fun onProviderEnabled(provider: String) {}
    override fun onProviderDisabled(provider: String) {}

    private fun updateZStability(zValue: Double) {
        zAccelerationHistory.add(zValue)
        if (zAccelerationHistory.size > zStabilityBufferSize) {
            zAccelerationHistory.removeAt(0)
        }
        
        if (zAccelerationHistory.size >= 2) {
            val mean = zAccelerationHistory.average()
            val variance = zAccelerationHistory.map { (it - mean).pow(2) }.average()
            zStability = sqrt(variance)
        }
    }

    private fun convertTiltToPercent(zValue: Double): Double {
        val tiltAbsolute = abs(zValue)
        val tiltPercent = (tiltAbsolute / 1.0) * 100.0
        return tiltPercent.coerceIn(0.0, 100.0)
    }

    private fun getTiltStatus(tiltPercent: Double): String {
        return when {
            tiltPercent <= viewingPhoneThreshold -> "📱 ĐANG XEM"
            tiltPercent < intermediateThreshold -> "⚡ TRUNG GIAN"
            else -> "🔼 KHÔNG XEM"
        }
    }

    private fun handleTiltDetection(zValue: Double) {
        val tiltPercent = convertTiltToPercent(zValue)
        val tiltStatus = getTiltStatus(tiltPercent)
        
        val tiltData = mapOf(
            "type" to "TILT_EVENT",
            "message" to "Thiết bị: $tiltStatus",
            "tiltValue" to zValue,
            "tiltPercent" to tiltPercent,
            "speed" to currentSpeed,
            "isNetworkActive" to isNetworkActive,
            "isActiveBrowsing" to isActiveBrowsing,
            "isInCall" to isInCall,
            "zStability" to zStability,
            "timestamp" to System.currentTimeMillis()
        )
        sendEventToFlutter(tiltData)
    }

    private fun sendDangerAlert(dangerType: String, message: String) {
        val dangerData = mapOf(
            "type" to "DANGER_EVENT",
            "message" to "CẢNH BÁO NGUY HIỂM: $message",
            "speed" to currentSpeed,
            "isInCall" to isInCall,
            "isActiveBrowsing" to isActiveBrowsing,
            "timestamp" to System.currentTimeMillis()
        )
        sendEventToFlutter(dangerData)
    }

    private fun sendEventToFlutter(type: String, message: String) {
        val eventData = mapOf(
            "type" to type,
            "message" to message,
            "timestamp" to System.currentTimeMillis()
        )
        sendEventToFlutter(eventData)
    }

    private fun sendEventToFlutter(data: Map<String, Any>) {
        handler.post {
            try {
                val jsonString = JSONObject(data).toString()
                eventSink?.success(jsonString)
            } catch (e: Exception) {
                // Handle error
            }
        }
    }
}