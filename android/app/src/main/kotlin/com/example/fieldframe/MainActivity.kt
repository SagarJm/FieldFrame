package com.example.fieldframe

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        if (intent.action == Intent.ACTION_VIEW) {
            val data = intent.dataString
            if (data != null) {
                // Forward to Flutter
                val launchIntent = Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_SEND
                    putExtra("deep_link_url", data)
                    type = "text/plain"
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                startActivity(launchIntent)
            }
        }
    }
}