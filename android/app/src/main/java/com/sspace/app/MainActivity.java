package com.sspace.app;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebSettings;
import android.view.Window;
import android.view.inputmethod.InputMethodManager;
import android.content.Context;
import android.content.res.Configuration;
import android.widget.Toast;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;

public class MainActivity extends Activity {
    private WebView webView;

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
        webView.setWebChromeClient(new WebChromeClient());
        setContentView(webView);

        if (state != null && webView.restoreState(state) != null) return;
        loadBundledApp();
    }

    private void loadBundledApp() {
        try (InputStream input = getAssets().open("index.html");
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            String html = output.toString("UTF-8");
            // Give the bundled page a secure HTTPS origin instead of file://.
            // This avoids opaque-origin restrictions on Supabase authentication/API calls.
            webView.loadDataWithBaseURL(
                "https://appassets.androidplatform.net/assets/index.html",
                html, "text/html", "UTF-8", null
            );
        } catch (Exception error) {
            Toast.makeText(this, "Impossible de charger SSPACE.", Toast.LENGTH_LONG).show();
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
