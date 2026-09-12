package com.apexads.apex_flutter_demo

import android.app.Application
import com.apexads.sdk.ApexAds
import com.apexads.sdk.ApexAdsConfig
import com.apexads.sdk.wallet.WalletAdExtension

class ApexDemoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val config = ApexAdsConfig.Builder("demo-app-token-000")
            .debugLogging(BuildConfig.DEBUG)
            .testMode(BuildConfig.DEBUG)
            .cacheTtlSeconds(120)
            .debugFakeFill(false)
            .build()
        ApexAds.init(this, config)
        WalletAdExtension.install()
    }
}
