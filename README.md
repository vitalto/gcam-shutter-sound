# GCam Custom Shutter Sound

An Xposed/LSPosed module that replaces the **Google Camera** shutter sound with
your own audio clip.

[![Release](https://img.shields.io/github/v/release/vitalto/gcam-shutter-sound?label=download)](https://github.com/vitalto/gcam-shutter-sound/releases/latest)
[![Build](https://github.com/vitalto/gcam-shutter-sound/actions/workflows/build.yml/badge.svg)](https://github.com/vitalto/gcam-shutter-sound/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Google Camera plays its shutter through `SoundPool`, loading the bundled
resource `R.raw.camera_shutter`. This module hooks `SoundPool.load(...)` inside
the GCam process: when GCam loads that resource, the module loads your clip
instead and returns its sample id, so GCam's own `play()` emits your sound.

## Requirements

- Rooted Android with **LSPosed** or a compatible framework (e.g. Vector).
- Google Camera (`com.google.android.GoogleCamera`).
- Tested on Pixel 9 (Android 15).

## Install

1. Download the APK from [Releases](https://github.com/vitalto/gcam-shutter-sound/releases/latest)
   (or build it, see below) and install it.
2. In your Xposed manager, **enable the module** and set its **scope** to
   Google Camera.
3. Force-stop and reopen Google Camera, then take a photo.

### Enable from the command line (LSPosed/Vector CLI)

```sh
vector-cli modules enable com.roottools.shuttersound
vector-cli scope set com.roottools.shuttersound com.google.android.GoogleCamera/0
```

## Use your own sound

Replace `app/src/main/assets/custom_shutter.ogg` with your clip (keep the file
name) and rebuild. `SoundPool` detects the format from content, so `.ogg`,
`.mp3` or `.wav` all work under that name — `.ogg` is recommended for a short,
latency-free click.

## Build

### Gradle (Android Studio / CI)

```sh
./gradlew :app:assembleRelease
# -> app/build/outputs/apk/release/app-release-unsigned.apk  (sign it)
```

### Offline, no Gradle

Needs only the Android SDK command-line tools and a JDK:

```sh
export ANDROID_SDK=/path/to/Android/Sdk
bash tools/build.sh
# -> build/GCamCustomShutter.apk  (signed with a throwaway key)
```

## License

MIT — see [LICENSE](LICENSE).
