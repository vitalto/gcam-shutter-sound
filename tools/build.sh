#!/usr/bin/env bash
#
# Offline builder — no Gradle, no network. Produces a signed, installable APK
# using only the Android SDK command-line tools (aapt2, d8, zipalign, apksigner)
# plus a JDK. Xposed API classes are provided by compile-only stubs in tools/stub
# and are NOT packaged into the APK (the Xposed framework provides them at runtime).
#
# Env overrides:
#   ANDROID_SDK    path to the SDK (default: $ANDROID_HOME or $ANDROID_SDK_ROOT)
#   BUILD_TOOLS    build-tools version dir name (default: autodetected, newest)
#   PLATFORM       android platform dir name    (default: autodetected, newest)
#   KEYSTORE       signing keystore (default: tools/debug.keystore, created if absent)
#
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/build"
mkdir -p "$OUT"

SDK="${ANDROID_SDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}}"
[ -n "$SDK" ] || { echo "Set ANDROID_SDK (or ANDROID_HOME) to your Android SDK path." >&2; exit 1; }

pick_newest() { ls -1 "$1" 2>/dev/null | sort -V | tail -1; }
BT_DIR="${BUILD_TOOLS:-$(pick_newest "$SDK/build-tools")}"
PLAT_DIR="${PLATFORM:-$(pick_newest "$SDK/platforms")}"
BT="$SDK/build-tools/$BT_DIR"
AJ="$SDK/platforms/$PLAT_DIR/android.jar"
[ -f "$AJ" ] || { echo "android.jar not found at $AJ" >&2; exit 1; }

# tool names differ on Windows (.exe/.bat) vs *nix
ext() { for e in "$1" "$1.exe" "$1.bat"; do [ -f "$BT/$e" ] && { echo "$BT/$e"; return; }; done; echo "$BT/$1"; }
AAPT2="$(ext aapt2)"; D8="$(ext d8)"; ZIPALIGN="$(ext zipalign)"; APKSIGNER="$(ext apksigner)"
JAVAC="${JAVAC:-javac}"

# On MSYS/Cygwin (Windows) the SDK .bat/.exe wrappers need native paths; cygpath
# converts them. On Linux/macOS cygpath is absent and paths pass through as-is.
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
# classpath separator: ';' for a Windows JDK (MSYS/Cygwin), ':' elsewhere
sep() { if command -v cygpath >/dev/null 2>&1; then echo ';'; else echo ':'; fi; }

KEYSTORE="${KEYSTORE:-$ROOT/tools/debug.keystore}"
if [ ! -f "$KEYSTORE" ]; then
  echo "Creating throwaway signing key at $KEYSTORE"
  keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android \
    -alias key -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=gcam-shutter" >/dev/null 2>&1
fi

echo ">> compiling Java"
rm -rf "$OUT/classes" "$OUT/stubclasses" "$OUT/dex"
mkdir -p "$OUT/classes" "$OUT/stubclasses" "$OUT/dex"
# Xposed API stubs compile to their own dir so they stay out of the packaged dex.
"$JAVAC" -source 17 -target 17 -cp "$(wp "$AJ")" -d "$(wp "$OUT/stubclasses")" \
  $(find tools/stub -name '*.java') 2>&1 | grep -v "system modules" || true
"$JAVAC" -source 17 -target 17 -cp "$(wp "$AJ")$(sep)$(wp "$OUT/stubclasses")" -d "$(wp "$OUT/classes")" \
  $(find app/src/main/java -name '*.java') 2>&1 | grep -v "system modules" || true

echo ">> dexing (module classes only)"
"${JAR:-jar}" cf "$OUT/module.jar" -C "$OUT/classes" .
"$D8" --min-api 24 --lib "$(wp "$AJ")" --classpath "$(wp "$OUT/stubclasses")" \
  --output "$(wp "$OUT/dex")" "$(wp "$OUT/module.jar")"

echo ">> linking resources + manifest + assets"
"$AAPT2" compile --dir "$(wp app/src/main/res)" -o "$(wp "$OUT/res.zip")"
"$AAPT2" link -o "$(wp "$OUT/base.apk")" -I "$(wp "$AJ")" --min-sdk-version 24 --target-sdk-version 35 \
  --manifest "$(wp app/src/main/AndroidManifest.xml)" -A "$(wp app/src/main/assets)" "$(wp "$OUT/res.zip")"

echo ">> injecting classes.dex"
cp "$OUT/dex/classes.dex" "$OUT/classes.dex"
( cd "$OUT" && "${JAR:-jar}" uf base.apk classes.dex )

echo ">> aligning + signing"
"$ZIPALIGN" -f 4 "$(wp "$OUT/base.apk")" "$(wp "$OUT/aligned.apk")"
"$APKSIGNER" sign --ks "$(wp "$KEYSTORE")" --ks-pass pass:android --key-pass pass:android \
  --out "$(wp "$OUT/GCamCustomShutter.apk")" "$(wp "$OUT/aligned.apk")"

rm -f "$OUT/aligned.apk" "$OUT/base.apk" "$OUT/classes.dex" "$OUT/res.zip"
echo ">> done: $OUT/GCamCustomShutter.apk"
