package com.sspace.app;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.provider.Settings;
import android.webkit.JavascriptInterface;
import android.os.Bundle;
import android.os.Build;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;
import android.view.Window;
import android.widget.Toast;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;

public class MainActivity extends Activity {
    private static final int REQUEST_AUDIO_PERMISSION = 501;
    private static final int REQUEST_FILE_PICKER = 502;
    private WebView webView;
    private PermissionRequest pendingAudioRequest;
    private ValueCallback<Uri[]> filePathCallback;
    private String pendingOverlayUserId = "";
    private String pendingOverlayDisplayName = "";
    private static final int REQUEST_OVERLAY_PERMISSION = 503;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        webView = new WebView(this);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadsImagesAutomatically(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        webView.setWebViewClient(new WebViewClient());
        webView.addJavascriptInterface(new NativeBridge(), "SSPACEAndroid");
        webView.setWebChromeClient(new WebChromeClient() {
            @Override public void onPermissionRequest(PermissionRequest request) {
                runOnUiThread(() -> {
                    boolean audioRequested = false;
                    for (String resource : request.getResources()) {
                        if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource)) audioRequested = true;
                    }
                    Uri origin = request.getOrigin();
                    boolean trustedOrigin = origin != null
                        && "https".equals(origin.getScheme())
                        && "appassets.androidplatform.net".equals(origin.getHost());
                    if (!audioRequested || !trustedOrigin) {
                        request.deny();
                        return;
                    }
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        request.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
                    } else {
                        pendingAudioRequest = request;
                        requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, REQUEST_AUDIO_PERMISSION);
                    }
                });
            }

            @Override public void onPermissionRequestCanceled(PermissionRequest request) {
                if (pendingAudioRequest == request) pendingAudioRequest = null;
            }

            @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (filePathCallback != null) filePathCallback.onReceiveValue(null);
                filePathCallback = callback;
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("*/*");
                intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{
                    "image/jpeg", "image/png", "image/webp", "image/gif",
                    "audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav",
                    "audio/ogg", "audio/webm", "audio/mp4", "audio/aac",
                    "video/mp4", "video/webm"
                });
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                try {
                    startActivityForResult(intent, REQUEST_FILE_PICKER);
                } catch (Exception error) {
                    filePathCallback = null;
                    callback.onReceiveValue(null);
                    Toast.makeText(MainActivity.this, "Impossible d’ouvrir les fichiers.", Toast.LENGTH_SHORT).show();
                    return false;
                }
                return true;
            }
        });
        setContentView(webView);

        if (state != null && webView.restoreState(state) != null) return;
        loadBundledApp();
    }

    private class NativeBridge {
        @JavascriptInterface public void showFloatingChat(String userId, String displayName) {
            runOnUiThread(() -> startFloatingChat(userId, displayName));
        }
        @JavascriptInterface public boolean canDrawOverlays() {
            return Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(MainActivity.this);
        }
    }

    private void startFloatingChat(String userId, String displayName) {
        if (userId == null || userId.trim().isEmpty()) {
            Toast.makeText(this, "Ouvre d’abord une conversation.", Toast.LENGTH_SHORT).show();
            return;
        }
        pendingOverlayUserId = userId;
        pendingOverlayDisplayName = displayName == null ? "Discussion" : displayName;
        if (Build.VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "Autorise SSPACE à s’afficher par-dessus les autres applications, puis reviens ici.", Toast.LENGTH_LONG).show();
            Intent settingsIntent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + getPackageName()));
            startActivityForResult(settingsIntent, REQUEST_OVERLAY_PERMISSION);
            return;
        }
        launchFloatingService();
    }

    private void launchFloatingService() {
        if (pendingOverlayUserId.isEmpty()) return;
        Intent service = new Intent(this, FloatingChatService.class);
        service.putExtra(FloatingChatService.EXTRA_OTHER_ID, pendingOverlayUserId);
        service.putExtra(FloatingChatService.EXTRA_DISPLAY_NAME, pendingOverlayDisplayName);
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(service); else startService(service);
        Toast.makeText(this, "Bulle SSPACE activée. Tu peux maintenant changer d’application.", Toast.LENGTH_SHORT).show();
        pendingOverlayUserId = "";
        pendingOverlayDisplayName = "";
    }

    @Override protected void onResume() {
        super.onResume();
        if (!pendingOverlayUserId.isEmpty() && (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this))) launchFloatingService();
    }

    private void loadBundledApp() {
        try (InputStream input = getAssets().open("index.html");
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            String html = output.toString("UTF-8");
            webView.loadDataWithBaseURL(
                "https://appassets.androidplatform.net/assets/index.html",
                html, "text/html", "UTF-8", null
            );
        } catch (Exception error) {
            Toast.makeText(this, "Impossible de charger SSPACE.", Toast.LENGTH_LONG).show();
        }
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_AUDIO_PERMISSION && pendingAudioRequest != null) {
            PermissionRequest request = pendingAudioRequest;
            pendingAudioRequest = null;
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                request.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
            } else {
                request.deny();
                Toast.makeText(this, "L’accès au microphone a été refusé.", Toast.LENGTH_SHORT).show();
            }
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_OVERLAY_PERMISSION) {
            if (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this)) launchFloatingService();
            else Toast.makeText(this, "L’autorisation est nécessaire pour afficher la bulle hors de SSPACE.", Toast.LENGTH_LONG).show();
            return;
        }
        if (requestCode == REQUEST_FILE_PICKER && filePathCallback != null) {
            Uri[] results = null;
            if (resultCode == RESULT_OK && data != null && data.getData() != null) {
                results = new Uri[]{data.getData()};
            }
            filePathCallback.onReceiveValue(results);
            filePathCallback = null;
        }
    }

    @Override protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        if (webView != null) webView.saveState(out);
    }

    @Override public void onBackPressed() {
        if (webView != null && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }
}