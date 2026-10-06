package lab.playpath.mobile

import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.viewmanagers.PlaypathPlayerViewManagerDelegate
import com.facebook.react.viewmanagers.PlaypathPlayerViewManagerInterface

@ReactModule(name = PlaypathPlayerViewManager.NAME)
class PlaypathPlayerViewManager :
    SimpleViewManager<PlaypathPlayerView>(),
    PlaypathPlayerViewManagerInterface<PlaypathPlayerView> {
    private val delegate = PlaypathPlayerViewManagerDelegate(this)

    override fun getDelegate(): ViewManagerDelegate<PlaypathPlayerView> = delegate

    override fun getName(): String = NAME

    override fun createViewInstance(reactContext: ThemedReactContext): PlaypathPlayerView {
        return PlaypathPlayerView(reactContext)
    }

    override fun setManifestUrl(view: PlaypathPlayerView, value: String?) {
        view.setManifestUrl(value)
    }

    override fun play(view: PlaypathPlayerView) {
        view.play()
    }

    override fun pause(view: PlaypathPlayerView) {
        view.pause()
    }

    override fun seek(view: PlaypathPlayerView, positionMs: Int) {
        view.seekToMs(positionMs)
    }

    override fun onDropViewInstance(view: PlaypathPlayerView) {
        view.releasePlayer()
        super.onDropViewInstance(view)
    }

    override fun getExportedCustomBubblingEventTypeConstants(): Map<String, Any> {
        return mapOf(
            "onPlaybackEvent" to mapOf(
                "phasedRegistrationNames" to mapOf(
                    "bubbled" to "onPlaybackEvent",
                    "captured" to "onPlaybackEventCapture",
                ),
            ),
            "onSnapshot" to mapOf(
                "phasedRegistrationNames" to mapOf(
                    "bubbled" to "onSnapshot",
                    "captured" to "onSnapshotCapture",
                ),
            ),
        )
    }

    companion object {
        const val NAME = "PlaypathPlayerView"
    }
}
