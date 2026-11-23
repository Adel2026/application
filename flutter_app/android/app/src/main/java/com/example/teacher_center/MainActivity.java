package com.example.teacher_center;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.drawable.Icon;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.ContactsContract;
import android.view.WindowManager;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class MainActivity extends FlutterFragmentActivity {
    private static final String CHANNEL = "com.example.teacher_center/contacts";
    private static final String SHORTCUT_CHANNEL = "com.example.teacher_center/shortcut";
    private static final int REQUEST_CODE_PICK_CONTACT = 2026;
    private MethodChannel.Result pendingResult;

    private android.media.MediaPlayer activeMediaPlayer = null;
    private android.media.Ringtone activeRingtone = null;
    private final android.os.Handler audioStopHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    private Runnable audioStopRunnable = null;

    private synchronized void stopAudioPlayback() {
        if (audioStopRunnable != null) {
            audioStopHandler.removeCallbacks(audioStopRunnable);
            audioStopRunnable = null;
        }
        if (activeMediaPlayer != null) {
            try {
                if (activeMediaPlayer.isPlaying()) {
                    activeMediaPlayer.stop();
                }
                activeMediaPlayer.release();
            } catch (Exception ignored) {}
            activeMediaPlayer = null;
        }
        if (activeRingtone != null) {
            try {
                if (activeRingtone.isPlaying()) {
                    activeRingtone.stop();
                }
            } catch (Exception ignored) {}
            activeRingtone = null;
        }
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("pickContact")) {
                    if (pendingResult != null) {
                        result.error("ALREADY_ACTIVE", "A contact picking operation is already active.", null);
                        return;
                    }
                    pendingResult = result;
                    try {
                        Intent intent = new Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI);
                        startActivityForResult(intent, REQUEST_CODE_PICK_CONTACT);
                    } catch (Exception e) {
                        pendingResult = null;
                        result.error("UNAVAILABLE", "Cannot open contact picker: " + e.getMessage(), null);
                    }
                } else {
                    result.notImplemented();
                }
            });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "com.example.teacher_center/alarm")
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("setAlarm")) {
                    try {
                        Integer hour = call.argument("hour");
                        Integer minutes = call.argument("minutes");
                        String message = call.argument("message");
                        Boolean skipUi = call.argument("skipUi");
                        List<Integer> days = call.argument("days");
                        String ringtoneUri = call.argument("ringtone");

                        Intent intent = new Intent(android.provider.AlarmClock.ACTION_SET_ALARM);
                        if (hour != null) intent.putExtra(android.provider.AlarmClock.EXTRA_HOUR, hour.intValue());
                        if (minutes != null) intent.putExtra(android.provider.AlarmClock.EXTRA_MINUTES, minutes.intValue());
                        if (message != null) intent.putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, message);
                        if (skipUi != null) intent.putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, skipUi.booleanValue());
                        intent.putExtra(android.provider.AlarmClock.EXTRA_VIBRATE, true);

                        if (ringtoneUri != null && !ringtoneUri.isEmpty()) {
                            intent.putExtra(android.provider.AlarmClock.EXTRA_RINGTONE, ringtoneUri);
                        }

                        if (days != null && !days.isEmpty()) {
                            java.util.ArrayList<Integer> daysList = new java.util.ArrayList<>(days);
                            intent.putExtra(android.provider.AlarmClock.EXTRA_DAYS, daysList);
                        }

                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        result.success(true);
                    } catch (Exception e) {
                        result.error("ALARM_ERROR", e.getMessage(), null);
                    }
                } else if (call.method.equals("showAlarms")) {
                    try {
                        Intent intent = new Intent(android.provider.AlarmClock.ACTION_SHOW_ALARMS);
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        result.success(true);
                    } catch (Exception e) {
                        result.error("SHOW_ALARMS_ERROR", e.getMessage(), null);
                    }
                } else if (call.method.equals("dismissAlarm")) {
                    // Handled silently to avoid launching external Clock app UI
                    result.success(true);
                } else if (call.method.equals("testAlarmSound")) {
                    try {
                        stopAudioPlayback();
                        int resId = getResources().getIdentifier("school_bell", "raw", getPackageName());
                        if (resId != 0) {
                            activeMediaPlayer = android.media.MediaPlayer.create(getApplicationContext(), resId);
                            if (activeMediaPlayer != null) {
                                activeMediaPlayer.setAudioStreamType(android.media.AudioManager.STREAM_ALARM);
                                activeMediaPlayer.start();
                                audioStopRunnable = () -> stopAudioPlayback();
                                audioStopHandler.postDelayed(audioStopRunnable, 4500);
                                result.success(true);
                                return;
                            }
                        }
                        android.net.Uri alert = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_ALARM);
                        if (alert == null) {
                            alert = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION);
                        }
                        activeRingtone = android.media.RingtoneManager.getRingtone(getApplicationContext(), alert);
                        if (activeRingtone != null) {
                            activeRingtone.play();
                            audioStopRunnable = () -> stopAudioPlayback();
                            audioStopHandler.postDelayed(audioStopRunnable, 4000);
                        }
                        result.success(true);
                    } catch (Exception e) {
                        result.error("SOUND_ERROR", e.getMessage(), null);
                    }
                } else if (call.method.equals("getDeviceRingtones")) {
                    try {
                        android.media.RingtoneManager manager = new android.media.RingtoneManager(getApplicationContext());
                        manager.setType(android.media.RingtoneManager.TYPE_ALARM | android.media.RingtoneManager.TYPE_RINGTONE | android.media.RingtoneManager.TYPE_NOTIFICATION);
                        android.database.Cursor cursor = manager.getCursor();
                        List<Map<String, String>> list = new java.util.ArrayList<>();
                        if (cursor != null) {
                            while (cursor.moveToNext()) {
                                String title = cursor.getString(android.media.RingtoneManager.TITLE_COLUMN_INDEX);
                                String uri = cursor.getString(android.media.RingtoneManager.URI_COLUMN_INDEX) + "/" + cursor.getString(android.media.RingtoneManager.ID_COLUMN_INDEX);
                                Map<String, String> item = new java.util.HashMap<>();
                                item.put("title", title);
                                item.put("uri", uri);
                                list.add(item);
                            }
                        }
                        result.success(list);
                    } catch (Exception e) {
                        result.error("RINGTONE_ERROR", e.getMessage(), null);
                    }
                } else if (call.method.equals("playAlarmSound")) {
                    try {
                        stopAudioPlayback();
                        String toneId = call.argument("toneId");
                        String uriStr = call.argument("uri");
                        String filePath = call.argument("filePath");
                        Integer durationMs = call.argument("durationMs");
                        int timeout = durationMs != null ? durationMs.intValue() : 5000;

                        // 1. Play by toneId from raw resources (school_bell, alarm_clock, digital_beep, gentle_chime)
                        if (toneId != null && !toneId.isEmpty()) {
                            int resId = getResources().getIdentifier(toneId, "raw", getPackageName());
                            if (resId != 0) {
                                activeMediaPlayer = android.media.MediaPlayer.create(getApplicationContext(), resId);
                                if (activeMediaPlayer != null) {
                                    activeMediaPlayer.setAudioStreamType(android.media.AudioManager.STREAM_ALARM);
                                    activeMediaPlayer.start();
                                    audioStopRunnable = () -> stopAudioPlayback();
                                    audioStopHandler.postDelayed(audioStopRunnable, timeout);
                                    result.success(true);
                                    return;
                                }
                            }
                        }

                        // 2. Play by custom file path
                        if (filePath != null && !filePath.isEmpty()) {
                            java.io.File file = new java.io.File(filePath);
                            if (file.exists()) {
                                activeMediaPlayer = new android.media.MediaPlayer();
                                activeMediaPlayer.setDataSource(filePath);
                                activeMediaPlayer.setAudioStreamType(android.media.AudioManager.STREAM_ALARM);
                                activeMediaPlayer.prepare();
                                activeMediaPlayer.start();
                                audioStopRunnable = () -> stopAudioPlayback();
                                audioStopHandler.postDelayed(audioStopRunnable, timeout);
                                result.success(true);
                                return;
                            }
                        }

                        // 3. Play by ringtone URI or fallback
                        android.net.Uri alertUri = null;
                        if (uriStr != null && !uriStr.isEmpty()) {
                            alertUri = android.net.Uri.parse(uriStr);
                        }
                        if (alertUri == null) {
                            alertUri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_ALARM);
                        }
                        if (alertUri == null) {
                            alertUri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION);
                        }

                        activeRingtone = android.media.RingtoneManager.getRingtone(getApplicationContext(), alertUri);
                        if (activeRingtone != null) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                activeRingtone.setAudioAttributes(new android.media.AudioAttributes.Builder()
                                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .build());
                            }
                            activeRingtone.play();
                            audioStopRunnable = () -> stopAudioPlayback();
                            audioStopHandler.postDelayed(audioStopRunnable, timeout);
                        }
                        result.success(true);
                    } catch (Exception e) {
                        result.error("PLAY_ERROR", e.getMessage(), null);
                    }
                } else if (call.method.equals("stopAlarmSound")) {
                    stopAudioPlayback();
                    result.success(true);
                } else {
                    result.notImplemented();
                }
            });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SHORTCUT_CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("createPinnedShortcut")) {
                    String imagePath = call.argument("imagePath");
                    String appName = call.argument("appName");
                    if (appName == null || appName.isEmpty()) {
                        appName = "سنتر أستاذي";
                    }
                    if (imagePath == null || imagePath.isEmpty()) {
                        result.error("INVALID_PATH", "Image path cannot be empty", null);
                        return;
                    }
                    createPinnedShortcut(imagePath, appName, result);
                } else if (call.method.equals("isPinShortcutSupported")) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ShortcutManager shortcutManager = getSystemService(ShortcutManager.class);
                        result.success(shortcutManager != null && shortcutManager.isRequestPinShortcutSupported());
                    } else {
                        result.success(false);
                    }
                } else if (call.method.equals("pinWidget")) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        android.appwidget.AppWidgetManager appWidgetManager = getSystemService(android.appwidget.AppWidgetManager.class);
                        if (appWidgetManager != null && appWidgetManager.isRequestPinAppWidgetSupported()) {
                            android.content.ComponentName myProvider = new android.content.ComponentName(this, NextSessionWidgetProvider.class);
                            appWidgetManager.requestPinAppWidget(myProvider, null, null);
                            result.success(true);
                            return;
                        }
                    }
                    result.success(false);
                } else {
                    result.notImplemented();
                }
            });

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "com.eduacademy/app_installer")
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("installApk")) {
                    String filePath = call.argument("filePath");
                    if (filePath == null) {
                        result.error("INVALID_PATH", "File path cannot be null", null);
                        return;
                    }
                    java.io.File file = new java.io.File(filePath);
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "File not found at " + filePath, null);
                        return;
                    }
                    try {
                        Uri apkUri = androidx.core.content.FileProvider.getUriForFile(
                            MainActivity.this,
                            getPackageName() + ".fileprovider",
                            file
                        );
                        Intent intent = new Intent(Intent.ACTION_VIEW);
                        intent.setDataAndType(apkUri, "application/vnd.android.package-archive");
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        result.success(true);
                    } catch (Exception e) {
                        result.error("INSTALL_ERROR", e.getMessage(), null);
                    }
                } else {
                    result.notImplemented();
                }
            });
    }

    private void createPinnedShortcut(String imagePath, String appName, MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED", "Shortcut pinning requires Android 8.0 or newer", null);
            return;
        }

        try {
            ShortcutManager shortcutManager = getSystemService(ShortcutManager.class);
            if (shortcutManager == null || !shortcutManager.isRequestPinShortcutSupported()) {
                result.error("NOT_SUPPORTED", "Your launcher does not support pinned shortcuts", null);
                return;
            }

            Bitmap scaledBitmap = getScaledSquareBitmap(imagePath, 256);
            if (scaledBitmap == null) {
                result.error("DECODE_FAILED", "Failed to load image from path: " + imagePath, null);
                return;
            }

            Bitmap finalBitmap = getRoundedCornerBitmap(scaledBitmap, 256 * 0.18f);

            Intent launchIntent = new Intent(this, MainActivity.class);
            launchIntent.setAction(Intent.ACTION_MAIN);
            launchIntent.addCategory(Intent.CATEGORY_LAUNCHER);
            launchIntent.setPackage(getPackageName());
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);

            String shortcutId = "edu_academy_custom_icon";
            ShortcutInfo shortcutInfo = new ShortcutInfo.Builder(this, shortcutId)
                .setShortLabel(appName)
                .setLongLabel(appName)
                .setIcon(Icon.createWithBitmap(finalBitmap))
                .setIntent(launchIntent)
                .build();

            // Update if already pinned
            try {
                List<ShortcutInfo> currentPinned = shortcutManager.getPinnedShortcuts();
                for (ShortcutInfo s : currentPinned) {
                    if (s.getId().equals(shortcutId)) {
                        shortcutManager.updateShortcuts(Collections.singletonList(shortcutInfo));
                        break;
                    }
                }
            } catch (Exception ignored) {}

            boolean requested = shortcutManager.requestPinShortcut(shortcutInfo, null);
            result.success(requested);
        } catch (Exception e) {
            result.error("ERROR", "Failed to create pinned shortcut: " + e.getMessage(), null);
        }
    }

    private Bitmap getScaledSquareBitmap(String path, int size) {
        try {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(path, options);

            int inWidth = options.outWidth;
            int inHeight = options.outHeight;
            if (inWidth <= 0 || inHeight <= 0) return null;

            int sampleSize = 1;
            while ((inWidth / sampleSize) > (size * 2) || (inHeight / sampleSize) > (size * 2)) {
                sampleSize *= 2;
            }

            options.inJustDecodeBounds = false;
            options.inSampleSize = sampleSize;
            Bitmap decoded = BitmapFactory.decodeFile(path, options);
            if (decoded == null) return null;

            int w = decoded.getWidth();
            int h = decoded.getHeight();
            int cropSize = Math.min(w, h);
            int x = (w - cropSize) / 2;
            int y = (h - cropSize) / 2;

            Bitmap cropped = Bitmap.createBitmap(decoded, x, y, cropSize, cropSize);
            if (cropped != decoded) {
                decoded.recycle();
            }

            Bitmap scaled = Bitmap.createScaledBitmap(cropped, size, size, true);
            if (scaled != cropped) {
                cropped.recycle();
            }

            return scaled;
        } catch (Exception e) {
            return null;
        }
    }

    private Bitmap getRoundedCornerBitmap(Bitmap bitmap, float cornerRadius) {
        try {
            Bitmap output = Bitmap.createBitmap(bitmap.getWidth(), bitmap.getHeight(), Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(output);

            final Paint paint = new Paint();
            final Rect rect = new Rect(0, 0, bitmap.getWidth(), bitmap.getHeight());
            final RectF rectF = new RectF(rect);

            paint.setAntiAlias(true);
            canvas.drawARGB(0, 0, 0, 0);
            paint.setColor(0xff424242);
            canvas.drawRoundRect(rectF, cornerRadius, cornerRadius, paint);

            paint.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.SRC_IN));
            canvas.drawBitmap(bitmap, rect, rect, paint);

            return output;
        } catch (Exception e) {
            return bitmap;
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_CODE_PICK_CONTACT) {
            if (pendingResult == null) return;
            MethodChannel.Result res = pendingResult;
            pendingResult = null;

            if (resultCode == Activity.RESULT_OK && data != null) {
                Uri contactUri = data.getData();
                if (contactUri != null) {
                    String[] projection = new String[]{
                        ContactsContract.CommonDataKinds.Phone.NUMBER,
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
                    };
                    Cursor cursor = null;
                    try {
                        cursor = getContentResolver().query(contactUri, projection, null, null, null);
                        if (cursor != null && cursor.moveToFirst()) {
                            int numberIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER);
                            int nameIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME);
                            String number = numberIndex >= 0 ? cursor.getString(numberIndex) : "";
                            String name = nameIndex >= 0 ? cursor.getString(nameIndex) : "";

                            Map<String, String> resultMap = new HashMap<>();
                            resultMap.put("phone", number != null ? number : "");
                            resultMap.put("name", name != null ? name : "");
                            res.success(resultMap);
                            return;
                        }
                    } catch (Exception e) {
                        res.error("QUERY_FAILED", e.getMessage(), null);
                        return;
                    } finally {
                        if (cursor != null) {
                            cursor.close();
                        }
                    }
                }
                res.success(null);
            } else {
                // User cancelled or dismissed picker
                res.success(null);
            }
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setupStatusBar();
    }

    @Override
    protected void onResume() {
        super.onResume();
        setupStatusBar();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            setupStatusBar();
        }
    }

    private void setupStatusBar() {
        // Completely hide the top status bar (battery, clock, wifi)
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);

        WindowInsetsControllerCompat controller =
            WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        if (controller != null) {
            controller.hide(WindowInsetsCompat.Type.statusBars());
            controller.setSystemBarsBehavior(
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            );
        }
    }

    @Override
    protected void onDestroy() {
        stopAudioPlayback();
        super.onDestroy();
    }
}
