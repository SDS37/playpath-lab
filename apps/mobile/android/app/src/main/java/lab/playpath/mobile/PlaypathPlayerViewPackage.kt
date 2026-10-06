package lab.playpath.mobile

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.uimanager.ViewManager

class PlaypathPlayerViewPackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return if (name == PlaypathPlayerViewManager.NAME) {
            PlaypathPlayerViewManager()
        } else {
            null
        }
    }

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
        return listOf(PlaypathPlayerViewManager())
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider {
            mapOf(
                PlaypathPlayerViewManager.NAME to ReactModuleInfo(
                    name = PlaypathPlayerViewManager.NAME,
                    className = PlaypathPlayerViewManager::class.java.name,
                    canOverrideExistingModule = false,
                    needsEagerInit = false,
                    isCxxModule = false,
                    isTurboModule = true,
                ),
            )
        }
    }
}
