package com.apexads.apex_flutter_demo

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var apexBridge: ApexSdkBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        apexBridge = ApexSdkBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            registry = flutterEngine.platformViewsController.registry,
        )
    }

    override fun onDestroy() {
        apexBridge?.dispose()
        apexBridge = null
        super.onDestroy()
    }
}
