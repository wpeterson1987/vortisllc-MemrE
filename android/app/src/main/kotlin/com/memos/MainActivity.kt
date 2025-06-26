package com.vortisllc.memre

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException

class MainActivity: FlutterActivity() {
    private val SMS_CHANNEL = "com.vortisllc.memre/sms"
    private val SHARE_CHANNEL = "com.vortisllc.memre/share"
    private var sharedData: Map<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // SMS Channel (your existing code)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSMS" -> {
                        val phone = call.argument<String>("phone")
                        val message = call.argument<String>("message")
                        val success = sendSMS(phone, message)
                        result.success(success)
                    }
                    "canSendSMS" -> {
                        val canSend = canSendSMS()
                        result.success(canSend)
                    }
                    else -> result.notImplemented()
                }
            }

        // Share Channel (new)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedData" -> {
                        Log.d("MainActivity", "getSharedData called")
                        if (sharedData != null) {
                            Log.d("MainActivity", "Returning shared data: $sharedData")
                            result.success(sharedData)
                            sharedData = null // Clear after sending
                        } else {
                            Log.d("MainActivity", "No shared data available")
                            result.success(null)
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        Log.d("MainActivity", "Handling intent: ${intent.action}")

        when (intent.action) {
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("text/") == true) {
                    handleTextShare(intent)
                } else {
                    handleFileShare(intent)
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                handleMultipleFileShare(intent)
            }
        }
    }

    private fun handleTextShare(intent: Intent) {
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
        Log.d("MainActivity", "Received shared text: $sharedText")
        
        if (sharedText != null) {
            sharedData = mapOf(
                "type" to "text",
                "content" to sharedText
            )
            Log.d("MainActivity", "Stored text share data")
        }
    }

    private fun handleFileShare(intent: Intent) {
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        Log.d("MainActivity", "Received shared file URI: $uri")
        
        if (uri != null) {
            try {
                val inputStream = contentResolver.openInputStream(uri)
                if (inputStream != null) {
                    val byteArrayOutputStream = ByteArrayOutputStream()
                    val buffer = ByteArray(1024)
                    var length: Int
                    
                    while (inputStream.read(buffer).also { length = it } != -1) {
                        byteArrayOutputStream.write(buffer, 0, length)
                    }
                    
                    val fileBytes = byteArrayOutputStream.toByteArray()
                    val fileName = getFileName(uri)
                    val mimeType = contentResolver.getType(uri)
                    
                    Log.d("MainActivity", "File loaded: $fileName, size: ${fileBytes.size}, type: $mimeType")
                    
                    val fileType = when {
                        mimeType?.startsWith("image/") == true -> "image"
                        mimeType?.startsWith("video/") == true -> "video"
                        else -> "file"
                    }
                    
                    sharedData = mapOf(
                        "type" to fileType,
                        "content" to fileBytes.toList(), // Convert to List<Int> for Flutter
                        "filePath" to uri.toString(),
                        "fileName" to fileName,
                        "mimeType" to (mimeType ?: "application/octet-stream")
                    )
                    
                    Log.d("MainActivity", "Stored file share data")
                    
                    inputStream.close()
                    byteArrayOutputStream.close()
                }
            } catch (e: IOException) {
                Log.e("MainActivity", "Error reading shared file", e)
            }
        }
    }

    private fun handleMultipleFileShare(intent: Intent) {
        val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        Log.d("MainActivity", "Received ${uris?.size} shared files")
        
        // For now, just handle the first file
        if (!uris.isNullOrEmpty()) {
            val singleIntent = Intent().apply {
                action = Intent.ACTION_SEND
                type = intent.type
                putExtra(Intent.EXTRA_STREAM, uris[0])
            }
            handleFileShare(singleIntent)
        }
    }

    private fun getFileName(uri: Uri): String {
        var result = "shared_file"
        val cursor = contentResolver.query(uri, null, null, null, null)
        
        cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) {
                    result = it.getString(nameIndex) ?: result
                }
            }
        }
        
        return result
    }

    // Your existing SMS methods
    private fun sendSMS(phone: String?, message: String?): Boolean {
        return try {
            println("Attempting to send SMS to: $phone")
            println("Message: $message")
            
            // Try the same approaches as in canSendSMS(), starting with the one that works
            val intents = listOf(
                // Method 3 (the one that works in canSendSMS)
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra("address", phone)
                    putExtra("sms_body", message)
                    putExtra(Intent.EXTRA_TEXT, message)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                },
                // Method 1
                Intent(Intent.ACTION_SENDTO).apply {
                    data = Uri.parse("smsto:$phone")
                    putExtra("sms_body", message)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                },
                // Method 2
                Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse("sms:$phone")
                    putExtra("sms_body", message)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                },
                // Alternative approach
                Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse("sms:$phone?body=${Uri.encode(message)}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            )
            
            for ((index, intent) in intents.withIndex()) {
                println("Trying SMS method ${index + 1}...")
                try {
                    if (intent.resolveActivity(packageManager) != null) {
                        println("SMS method ${index + 1} found compatible app, launching...")
                        startActivity(intent)
                        Thread.sleep(500)
                        return true
                    } else {
                        println("SMS method ${index + 1}: No compatible app")
                    }
                } catch (e: Exception) {
                    println("SMS method ${index + 1} failed: ${e.message}")
                }
            }
            
            println("All SMS methods failed")
            return false
            
        } catch (e: Exception) {
            println("SMS error: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    private fun canSendSMS(): Boolean {
        return try {
            println("Checking SMS capability...")
            
            // Check the same methods as in sendSMS
            val smsIntents = listOf(
                Intent(Intent.ACTION_SEND).apply { type = "text/plain" },
                Intent(Intent.ACTION_SENDTO).apply { data = Uri.parse("smsto:") },
                Intent(Intent.ACTION_VIEW).apply { data = Uri.parse("sms:") }
            )
            
            for ((index, intent) in smsIntents.withIndex()) {
                println("Checking SMS method ${index + 1}...")
                if (intent.resolveActivity(packageManager) != null) {
                    println("SMS method ${index + 1}: Available")
                    return true
                } else {
                    println("SMS method ${index + 1}: Not available")
                }
            }
            
            println("SMS capability check: Not available")
            return false
            
        } catch (e: Exception) {
            println("Error checking SMS capability: ${e.message}")
            return true
        }
    }
}