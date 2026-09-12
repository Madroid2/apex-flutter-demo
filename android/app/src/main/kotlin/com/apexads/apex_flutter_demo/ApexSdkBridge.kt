package com.apexads.apex_flutter_demo

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import com.apexads.sdk.appopen.AppOpenAd
import com.apexads.sdk.banner.BannerAd
import com.apexads.sdk.banner.BannerAdListener
import com.apexads.sdk.banner.BannerAdView
import com.apexads.sdk.conversational.ConversationalAd
import com.apexads.sdk.conversational.ConversationalAdListener
import com.apexads.sdk.core.error.AdError
import com.apexads.sdk.core.models.AdFormat
import com.apexads.sdk.core.models.AdSize
import com.apexads.sdk.inappbidding.ApexInAppBidder
import com.apexads.sdk.inappbidding.BidToken
import com.apexads.sdk.inappbidding.InAppBidListener
import com.apexads.sdk.inappbidding.mock.MockMediationPlatform
import com.apexads.sdk.interstitial.InterstitialAd
import com.apexads.sdk.interstitial.InterstitialAdListener
import com.apexads.sdk.nativeads.NativeAd
import com.apexads.sdk.nativeads.NativeAdListener
import com.apexads.sdk.nativeads.NativeAdView
import com.apexads.sdk.video.VideoAd
import com.apexads.sdk.video.VideoAdListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.platform.PlatformViewRegistry

class ApexSdkBridge(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
    registry: PlatformViewRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannel = MethodChannel(messenger, "com.apexads.flutter_demo/sdk")
    private val eventChannel = EventChannel(messenger, "com.apexads.flutter_demo/events")
    private var eventSink: EventChannel.EventSink? = null
    private val bannerSlots = mutableMapOf<String, BannerSlot>()
    private var interstitialAd: InterstitialAd? = null
    private var walletAd: InterstitialAd? = null
    private var videoAd: VideoAd? = null
    private var nativeAd: NativeAd? = null
    private val nativeTrackers = mutableSetOf<NativeTrackerSlot>()
    private var conversationalAd: ConversationalAd? = null
    private var bidToken: BidToken? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        registry.registerViewFactory("apexads/banner", BannerFactory(this))
        registry.registerViewFactory("apexads/native-tracker", NativeTrackerFactory(this))
        initialiseAppOpen()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emit("sdk", "ready", "Apex SDK connected", mapOf("version" to "1.0.0-SNAPSHOT"))
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInfo" -> result.success(
                mapOf(
                    "platform" to "Android",
                    "sdkVersion" to "1.0.0-SNAPSHOT",
                    "server" to "10.0.2.2:8080",
                    "testMode" to true,
                    "appOpenReady" to AppOpenAd.isAdReady(),
                ),
            )
            "loadAd" -> {
                val format = call.argument<String>("format") ?: ""
                loadAd(format)
                result.success(mapOf("accepted" to true, "format" to format))
            }
            "showAd" -> {
                val format = call.argument<String>("format") ?: ""
                showAd(format)
                result.success(true)
            }
            "nativeClick" -> {
                val action = call.argument<Boolean>("action") == true
                result.success(if (action) nativeAd?.performAction(activity) ?: false else nativeAd?.handleClick(activity) ?: false)
            }
            "conversationClick" -> {
                val action = call.argument<Boolean>("action") == true
                result.success(if (action) conversationalAd?.performAction(activity) ?: false else conversationalAd?.handleClick(activity) ?: false)
            }
            "recordConversationRendered" -> {
                conversationalAd?.recordSuggestionRendered()
                result.success(true)
            }
            "fetchBid" -> {
                fetchBid()
                result.success(true)
            }
            "simulateAuction" -> {
                simulateAuction()
                result.success(true)
            }
            "appOpenStatus" -> result.success(mapOf("ready" to AppOpenAd.isAdReady()))
            "setAppOpenEnabled" -> {
                AppOpenAd.setEnabled(call.argument<Boolean>("enabled") != false)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialiseAppOpen() {
        AppOpenAd.initialize(activity.applicationContext, "demo-appopen-placement", object : AppOpenAd.Listener {
            override fun onAppOpenAdLoaded() = emit("appopen", "loaded", "App Open ad preloaded")
            override fun onAppOpenAdFailedToLoad(error: AdError) = fail("appopen", error)
            override fun onAppOpenAdImpression() = emit("appopen", "shown", "Foreground impression recorded")
            override fun onAppOpenAdDismissed() = emit("appopen", "closed", "App Open ad dismissed")
            override fun onAppOpenAdClicked() = emit("appopen", "clicked", "App Open ad clicked")
        })
        AppOpenAd.setFrequencyCapHours(0)
        AppOpenAd.setAdExpiryMinutes(30)
    }

    private fun loadAd(format: String) {
        emit(format, "loading", "Requesting ${formatLabel(format)}")
        when (format) {
            "banner", "mrect" -> bannerSlots[format]?.load()
                ?: emit(format, "waiting", "Ad surface is still attaching")
            "interstitial" -> loadInterstitial(false)
            "wallet" -> loadInterstitial(true)
            "video" -> loadVideo()
            "native" -> loadNative()
            "conversation" -> loadConversation()
            else -> emit(format, "error", "Unknown format")
        }
    }

    private fun showAd(format: String) {
        when (format) {
            "interstitial" -> interstitialAd?.show(activity)
            "wallet" -> walletAd?.show(activity)
            "video" -> videoAd?.show(activity)
            else -> emit(format, "error", "This format does not use a fullscreen Show action")
        }
    }

    private fun loadInterstitial(wallet: Boolean) {
        val format = if (wallet) "wallet" else "interstitial"
        val placement = if (wallet) "demo-wallet-interstitial" else "demo-interstitial-placement"
        val ad = InterstitialAd.Builder(placement)
            .listener(object : InterstitialAdListener {
                override fun onInterstitialLoaded() = emit(format, "loaded", "Ready to show")
                override fun onInterstitialFailed(error: AdError) = fail(format, error)
                override fun onInterstitialShown() = emit(format, "shown", "Fullscreen creative opened")
                override fun onInterstitialClosed() = emit(format, "closed", "Creative closed")
                override fun onInterstitialClicked() = emit(format, "clicked", "Click-through opened")
                override fun onWalletPassSaved() = emit(format, "reward", "Pass saved to Google Wallet")
                override fun onWalletPassCancelled() = emit(format, "closed", "Wallet save cancelled")
                override fun onWalletPassFailed() = emit(format, "error", "Wallet save failed")
            })
            .build()
        if (wallet) walletAd = ad else interstitialAd = ad
        ad.load()
    }

    private fun loadVideo() {
        videoAd = VideoAd.Builder("demo-video-placement")
            .listener(object : VideoAdListener {
                override fun onVideoAdLoaded() = emit("video", "loaded", "VAST video ready")
                override fun onVideoAdFailed(error: AdError) = fail("video", error)
                override fun onVideoAdStarted() = emit("video", "shown", "Playback started")
                override fun onVideoAdCompleted() = emit("video", "completed", "Video completed")
                override fun onVideoAdSkipped() = emit("video", "closed", "Video skipped")
                override fun onVideoAdClicked() = emit("video", "clicked", "Video clicked")
                override fun onRewardEarned() = emit("video", "reward", "Reward earned")
            })
            .build()
            .also { it.load() }
    }

    private fun loadNative() {
        nativeAd?.destroy()
        nativeAd = NativeAd.Builder("demo-native-placement")
            .listener(object : NativeAdListener {
                override fun onNativeAdLoaded(ad: NativeAd) {
                    nativeTrackers.forEach { it.bind(ad) }
                    ad.recordActionRendered()
                    emit(
                        "native",
                        "loaded",
                        "Native assets received",
                        mapOf(
                            "title" to ad.title,
                            "description" to ad.description,
                            "cta" to (ad.actionCtaText ?: ad.ctaText),
                            "advertiser" to ad.advertiserName,
                            "imageUrl" to ad.imageUrl,
                            "iconUrl" to ad.iconUrl,
                            "disclosure" to (ad.disclosureText ?: "Sponsored"),
                            "intentLabel" to ad.intentLabel,
                            "badge" to ad.actionBadgeText,
                            "hasAction" to ad.hasIntentAction(),
                        ),
                    )
                }
                override fun onNativeAdFailed(error: AdError) = fail("native", error)
                override fun onNativeAdClicked() = emit("native", "clicked", "Native creative clicked")
                override fun onNativeAdActionCompleted() = emit("native", "reward", "Native action completed")
                override fun onNativeAdActionCancelled() = emit("native", "closed", "Native action cancelled")
                override fun onNativeAdActionFailed() = emit("native", "error", "Native action failed")
            })
            .build()
            .also { it.load() }
    }

    private fun loadConversation() {
        conversationalAd?.destroy()
        conversationalAd = ConversationalAd.Builder("demo-assistant-inline")
            .listener(object : ConversationalAdListener {
                override fun onSuggestionReady(ad: ConversationalAd) {
                    val item = ad.suggestion ?: return
                    emit(
                        "conversation",
                        "loaded",
                        "Sponsored suggestion ready",
                        mapOf(
                            "title" to item.title,
                            "body" to item.body,
                            "advertiser" to item.advertiserName,
                            "imageUrl" to item.thumbnailUrl,
                            "iconUrl" to item.iconUrl,
                            "disclosure" to item.disclosure,
                            "relevance" to item.relevanceLabel,
                            "cta" to (item.actionCtaText ?: item.fallbackCtaText),
                            "fallbackCta" to item.fallbackCtaText,
                            "badge" to item.badgeText,
                            "hasAction" to item.hasAction,
                        ),
                    )
                }
                override fun onSuggestionFailed(error: AdError) = fail("conversation", error)
                override fun onSuggestionClicked() = emit("conversation", "clicked", "Suggestion clicked")
                override fun onActionCompleted() = emit("conversation", "reward", "Suggestion action completed")
                override fun onActionCancelled() = emit("conversation", "closed", "Suggestion action cancelled")
                override fun onActionFailed() = emit("conversation", "error", "Suggestion action failed")
            })
            .build()
            .also { it.load() }
    }

    private fun fetchBid() {
        emit("bidding", "loading", "Fetching Apex price signal")
        ApexInAppBidder.fetchBidToken(
            "demo-inappbidding-placement",
            AdFormat.INTERSTITIAL,
            object : InAppBidListener {
                override fun onBidReady(token: BidToken) {
                    bidToken = token
                    emit(
                        "bidding",
                        "loaded",
                        "Bid token ready",
                        mapOf("cpm" to token.cpmUsd, "token" to token.token, "placement" to token.placementId),
                    )
                }
                override fun onBidFailed(error: AdError) = fail("bidding", error)
            },
        )
    }

    private fun simulateAuction() {
        val token = bidToken
        if (token == null) {
            emit("bidding", "error", "Fetch a bid token first")
            return
        }
        MockMediationPlatform().apply {
            setApexBidToken(token)
            simulateImpression { winner, cpm ->
                emit("bidding", "auction", "$winner won the auction", mapOf("winner" to winner, "cpm" to cpm))
            }
        }
    }

    fun attachBanner(slot: BannerSlot) {
        bannerSlots[slot.slot] = slot
        emit(slot.slot, "idle", "Ad surface attached")
    }

    fun detachBanner(slot: BannerSlot) {
        if (bannerSlots[slot.slot] === slot) bannerSlots.remove(slot.slot)
    }

    fun attachNativeTracker(slot: NativeTrackerSlot) {
        nativeTrackers += slot
        nativeAd?.takeIf { it.isReady }?.let(slot::bind)
    }

    fun detachNativeTracker(slot: NativeTrackerSlot) {
        nativeTrackers -= slot
    }

    private fun fail(format: String, error: AdError) =
        emit(format, "error", error.message ?: "Unknown Apex SDK error")

    private fun emit(format: String, event: String, message: String, data: Map<String, Any?> = emptyMap()) {
        val payload = mapOf(
            "format" to format,
            "event" to event,
            "message" to message,
            "data" to data,
            "timestamp" to System.currentTimeMillis(),
        )
        activity.runOnUiThread { eventSink?.success(payload) }
    }

    private fun formatLabel(format: String) = when (format) {
        "mrect" -> "300×250 wallet banner"
        "conversation" -> "sponsored suggestion"
        else -> format
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        interstitialAd = null
        walletAd = null
        videoAd = null
        nativeAd?.destroy()
        conversationalAd?.destroy()
        bannerSlots.values.toList().forEach { it.dispose() }
        bannerSlots.clear()
    }

    private class BannerFactory(private val bridge: ApexSdkBridge) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val params = args as? Map<*, *>
            return BannerSlot(context, bridge, params?.get("slot") as? String ?: "banner")
        }
    }

    private class NativeTrackerFactory(private val bridge: ApexSdkBridge) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
            NativeTrackerSlot(context, bridge)
    }

    class NativeTrackerSlot(
        context: Context,
        private val bridge: ApexSdkBridge,
    ) : PlatformView {
        private val host = FrameLayout(context)
        private var tracker: NativeAdView? = null

        init {
            bridge.attachNativeTracker(this)
        }

        fun bind(ad: NativeAd) {
            tracker?.destroy()
            host.removeAllViews()
            tracker = NativeAdView(host.context).also {
                host.addView(it, FrameLayout.LayoutParams(1, 1))
                ad.bindTo(it)
            }
        }

        override fun getView(): View = host

        override fun dispose() {
            tracker?.destroy()
            tracker = null
            host.removeAllViews()
            bridge.detachNativeTracker(this)
        }
    }

    class BannerSlot(
        context: Context,
        private val bridge: ApexSdkBridge,
        val slot: String,
    ) : PlatformView {
        private val view = BannerAdView(context)
        private var ad: BannerAd? = null

        init {
            bridge.attachBanner(this)
        }

        fun load() {
            ad?.destroy()
            val isMrect = slot == "mrect"
            ad = BannerAd.Builder(if (isMrect) "demo-wallet-mrect" else "demo-banner-placement")
                .adSize(if (isMrect) AdSize.MRECT_300x250 else AdSize.BANNER_320x50)
                .listener(object : BannerAdListener {
                    override fun onAdLoaded() {
                        ad?.show(view)
                        bridge.emit(slot, "loaded", if (isMrect) "Wallet MRECT displayed" else "Banner displayed")
                    }
                    override fun onAdFailed(error: AdError) = bridge.fail(slot, error)
                    override fun onAdClicked() = bridge.emit(slot, "clicked", "Banner clicked")
                    override fun onAdImpression() = bridge.emit(slot, "shown", "MRC impression recorded")
                    override fun onWalletPassSaved() = bridge.emit(slot, "reward", "Pass saved to Google Wallet")
                    override fun onWalletPassCancelled() = bridge.emit(slot, "closed", "Wallet save cancelled")
                    override fun onWalletPassFailed() = bridge.emit(slot, "error", "Wallet save failed")
                })
                .build()
                .also { it.load() }
        }

        override fun getView(): View = view

        override fun dispose() {
            ad?.destroy()
            ad = null
            view.destroy()
            bridge.detachBanner(this)
        }
    }
}
