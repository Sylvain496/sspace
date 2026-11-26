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
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import androidx.webkit.WebViewAssetLoader;
import android.webkit.WebSettings;
import android.view.Window;
import android.widget.Toast;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;

public class MainActivity extends Activity {
    private static final int REQUEST_MEDIA_PERMISSION = 501;
    private static final int REQUEST_FILE_PICKER = 502;
    private WebView webView;
    private PermissionRequest pendingMediaRequest;
    private String[] pendingMediaResources = new String[0];
    private String[] pendingAndroidPermissions = new String[0];
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
        WebViewAssetLoader assetLoader = new WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
            .build();
        webView.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return assetLoader.shouldInterceptRequest(request.getUrl());
            }
        });
        webView.addJavascriptInterface(new NativeBridge(), "SSPACEAndroid");
        webView.setWebChromeClient(new WebChromeClient() {
            @Override public void onPermissionRequest(PermissionRequest request) {
                runOnUiThread(() -> {
                    Uri origin = request.getOrigin();
                    boolean trustedOrigin = origin != null
                        && "https".equals(origin.getScheme())
                        && "appassets.androidplatform.net".equals(origin.getHost());
                    if (!trustedOrigin) {
                        request.deny();
                        return;
                    }

                    String[] resources = request.getResources();
                    boolean audioRequested = false;
                    boolean videoRequested = false;
                    for (String resource : resources) {
                        if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource)) audioRequested = true;
                        else if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource)) videoRequested = true;
                        else {
                            request.deny();
                            return;
                        }
                    }
                    if (!audioRequested && !videoRequested) {
                        request.deny();
                        return;
                    }

                    java.util.ArrayList<String> required = new java.util.ArrayList<>();
                    if (audioRequested && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
                        required.add(Manifest.permission.RECORD_AUDIO);
                    if (videoRequested && checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
                        required.add(Manifest.permission.CAMERA);

                    if (required.isEmpty()) {
                        request.grant(resources);
                        return;
                    }
                    if (pendingMediaRequest != null) pendingMediaRequest.deny();
                    pendingMediaRequest = request;
                    pendingMediaResources = resources;
                    pendingAndroidPermissions = required.toArray(new String[0]);
                    requestPermissions(pendingAndroidPermissions, REQUEST_MEDIA_PERMISSION);
                });
            }

            @Override public void onPermissionRequestCanceled(PermissionRequest request) {
                if (pendingMediaRequest == request) {
                    pendingMediaRequest = null;
                    pendingMediaResources = new String[0];
                    pendingAndroidPermissions = new String[0];
                }
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
        webView.loadUrl("https://appassets.androidplatform.net/assets/index.html");
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_MEDIA_PERMISSION && pendingMediaRequest != null) {
            boolean granted = grantResults.length == pendingAndroidPermissions.length;
            for (int result : grantResults) {
                if (result != PackageManager.PERMISSION_GRANTED) granted = false;
            }
            PermissionRequest request = pendingMediaRequest;
            pendingMediaRequest = null;
            if (granted) {
                request.grant(pendingMediaResources);
            } else {
                request.deny();
                Toast.makeText(this, "L’accès au microphone ou à la caméra a été refusé.", Toast.LENGTH_SHORT).show();
            }
            pendingMediaResources = new String[0];
            pendingAndroidPermissions = new String[0];
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