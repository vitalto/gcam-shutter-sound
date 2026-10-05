package io.github.vitalto.gcamshutter;

import android.content.Context;
import android.media.SoundPool;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.IXposedHookZygoteInit;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * Google Camera plays its shutter sound through SoundPool. We hook
 * SoundPool.load(Context, resId, prio); when GCam loads R.raw.camera_shutter we
 * load our own clip instead and return that sampleId, so GCam's own play() call
 * plays our sound.
 */
public class ShutterSoundHook implements IXposedHookLoadPackage, IXposedHookZygoteInit {

    private static final String TAG = "GCamShutter";
    private static final String TARGET = "com.google.android.GoogleCamera";
    private static final String ASSET = "assets/custom_shutter.ogg";
    private static final String SHUTTER_SUFFIX = "/camera_shutter";

    private static volatile String modulePath;
    private static volatile String cachedSoundPath;

    @Override
    public void initZygote(IXposedHookZygoteInit.StartupParam startupParam) {
        modulePath = startupParam.modulePath;
    }

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpp) {
        if (!TARGET.equals(lpp.packageName)) return;
        XposedBridge.log(TAG + ": attached to " + lpp.packageName);

        XposedHelpers.findAndHookMethod("android.media.SoundPool", lpp.classLoader, "load",
                Context.class, int.class, int.class, new XC_MethodHook() {
            @Override
            protected void beforeHookedMethod(MethodHookParam param) {
                try {
                    Context context = (Context) param.args[0];
                    int resId = ((Integer) param.args[1]).intValue();
                    int priority = ((Integer) param.args[2]).intValue();

                    String resName = null;
                    try { resName = context.getResources().getResourceName(resId); } catch (Throwable ignore) {}
                    if (resName == null || !resName.endsWith(SHUTTER_SUFFIX)) return;

                    String soundPath = extractSound(context);
                    if (soundPath == null) return;

                    SoundPool soundPool = (SoundPool) param.thisObject;
                    int sampleId = soundPool.load(soundPath, priority);
                    param.setResult(Integer.valueOf(sampleId));
                    XposedBridge.log(TAG + ": replaced " + resName + " -> " + soundPath + " (sampleId=" + sampleId + ")");
                } catch (Throwable t) {
                    XposedBridge.log(TAG + ": hook error " + t);
                }
            }
        });
    }

    /** Copies the bundled clip out of our module APK into GCam's cache (GCam can read its own cache). */
    private static synchronized String extractSound(Context context) {
        try {
            if (cachedSoundPath != null) return cachedSoundPath;
            if (modulePath == null) {
                XposedBridge.log(TAG + ": modulePath is null, cannot extract sound");
                return null;
            }
            File out = new File(context.getCacheDir(), "custom_shutter.ogg");
            if (!out.exists() || out.length() == 0) {
                ZipFile zip = new ZipFile(modulePath);
                try {
                    ZipEntry entry = zip.getEntry(ASSET);
                    InputStream in = zip.getInputStream(entry);
                    FileOutputStream fos = new FileOutputStream(out);
                    byte[] buf = new byte[8192];
                    int n;
                    while ((n = in.read(buf)) > 0) fos.write(buf, 0, n);
                    fos.close();
                    in.close();
                } finally {
                    zip.close();
                }
            }
            out.setReadable(true, false);
            cachedSoundPath = out.getAbsolutePath();
            XposedBridge.log(TAG + ": sound ready at " + cachedSoundPath + " (" + out.length() + " bytes)");
            return cachedSoundPath;
        } catch (Throwable t) {
            XposedBridge.log(TAG + ": extract error " + t);
            return null;
        }
    }
}
