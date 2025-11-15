package com.example.app5

import android.content.Context
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager

class CallDetectorManager(private val context: Context) {
    
    var onCallStateChanged: ((Boolean, String) -> Unit)? = null
    
    private lateinit var telephonyManager: TelephonyManager
    private var isInCall = false
    
    fun startMonitoring() {
        telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
    }
    
    fun stopMonitoring() {
        telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE)
    }
    
    private val phoneStateListener = object : PhoneStateListener() {
        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
            when (state) {
                TelephonyManager.CALL_STATE_RINGING -> {
                    println("📞 Cuộc gọi đến")
                }
                TelephonyManager.CALL_STATE_OFFHOOK -> {
                    // Đã nhấc máy
                    if (!isInCall) {
                        isInCall = true
                        onCallStateChanged?.invoke(true, "connected")
                    }
                }
                TelephonyManager.CALL_STATE_IDLE -> {
                    // Kết thúc cuộc gọi
                    if (isInCall) {
                        isInCall = false
                        onCallStateChanged?.invoke(false, "disconnected")
                    }
                }
            }
        }
    }
}