# Playpath mobile

React Native 0.87.1 renders the TypeScript controls and hosts a Fabric view. Android builds that view with Media3 1.11.1 and Clear Key. iOS builds it with `AVPlayer`. JavaScript does not decode samples, and it does not receive a content key.

Commands are `play`, `pause`, and `seek`. Events across the bridge are the playback-event JSON, with `platform` `react-native` and engine `media3` or `avplayer`. The impression URL is not requested. The mid-roll is not wired on this view, so `adPlaying` stays false until a later story.

Android loads `http://127.0.0.1:8080/manifest.mpd` and licenses Clear Key at `http://127.0.0.1:8082/`. iOS loads `http://127.0.0.1:8084/master.m3u8` and does not log `drm`.

From this directory, with Node 24:

```
npm test
npm run check
```

Android, from `android/`:

```
./gradlew :app:compileDebugKotlin :app:testDebugUnitTest --tests lab.playpath.mobile.PlaybackEventsTest
```

That compile and those tests passed. On the emulator the TypeScript controls show Pause and 0:04 / 1:00, and the Media3 view shows the color bars. That session logs `startup` for `http://127.0.0.1:8080/manifest.mpd`, `drm` with `result` `ok`, and `bitrate` with `height` 1080 and `bandwidthBps` 4545011. `platform` is `react-native` and `engine` is `media3`. The iOS picture is still the observation.

## iOS toolchain

`pod` is not on `PATH`. `bundle install` with the system Ruby 2.6.10 stops while compiling the `json` gem: the compiler failed to generate an executable file. The `AVPlayer` sources are in the Xcode project and have not been built. A JavaScript player was not added to finish the story.
