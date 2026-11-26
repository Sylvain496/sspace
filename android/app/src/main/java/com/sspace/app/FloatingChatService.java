package com.sspace.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.IBinder;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebSettings;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import androidx.webkit.WebViewAssetLoader;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import org.json.JSONObject;

public class FloatingChatService extends Service {
    public static final String EXTRA_OTHER_ID = "other_user_id";
    public static final String EXTRA_DISPLAY_NAME = "display_name";
    private static final String CHANNEL_ID = "sspace_floating_chat";
    private static final int NOTIFICATION_ID = 7314;
    private WindowManager windowManager;
    private View bubble;
    private View panel;
    private WebView chatWebView;
    private WindowManager.LayoutParams bubbleParams;
    private WindowManager.LayoutParams panelParams;
    private String otherId = "";
    private String displayName = "Discussion SSPACE";
    private boolean expanded = false;
    private float downX, downY;
    private int startX, startY;

    @Override public void onCreate() {
        super.onCreate();
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        createNotificationChannel();
        Notification notification = buildNotification();
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
        createBubble();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null) {
            String incomingId = intent.getStringExtra(EXTRA_OTHER_ID);
            String incomingName = intent.getStringExtra(EXTRA_DISPLAY_NAME);
            if (incomingId != null && !incomingId.trim().isEmpty()) otherId = incomingId;
            if (incomingName != null && !incomingName.trim().isEmpty()) displayName = incomingName;
            if (chatWebView != null && !otherId.isEmpty()) openConversationInWebView();
        }
        return START_STICKY;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "Bulle de discussion SSPACE", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Maintient la conversation flottante disponible pendant l’utilisation d’autres applications.");
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) manager.createNotificationChannel(channel);
        }
    }

    private Notification buildNotification() {
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
            ? new Notification.Builder(this, CHANNEL_ID) : new Notification.Builder(this);
        return builder.setSmallIcon(android.R.drawable.sym_action_chat)
            .setContentTitle("SSPACE — discussion flottante active")
            .setContentText("La bulle reste disponible au-dessus de tes applications.")
            .setOngoing(true).build();
    }

    private int overlayType() {
        return Build.VERSION.SDK_INT >= 26 ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE;
    }

    private GradientDrawable shape(int color, int radius, int strokeColor) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(radius);
        d.setStroke(2, strokeColor);
        return d;
    }

    private TextView text(String value, int size, int color) {
        TextView t = new TextView(this);
        t.setText(value);
        t.setTextSize(size);
        t.setTextColor(color);
        t.setGravity(Gravity.CENTER);
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return t;
    }

    private void createBubble() {
        if (bubble != null) return;
        TextView b = text("S", 21, Color.WHITE);
        b.setBackground(shape(Color.rgb(89, 91, 235), 100, Color.rgb(190, 170, 255)));
        b.setElevation(16);
        bubble = b;
        bubbleParams = new WindowManager.LayoutParams(dp(58), dp(58), overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT);
        bubbleParams.gravity = Gravity.TOP | Gravity.START;
        bubbleParams.x = dp(12);
        bubbleParams.y = dp(220);
        b.setOnTouchListener((v, event) -> {
            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    downX = event.getRawX(); downY = event.getRawY();
                    startX = bubbleParams.x; startY = bubbleParams.y;
                    return true;
                case MotionEvent.ACTION_MOVE:
                    float dx = event.getRawX() - downX, dy = event.getRawY() - downY;
                    bubbleParams.x = startX + (int) dx;
                    bubbleParams.y = startY + (int) dy;
                    clampBubble();
                    if (bubble.getParent() != null) windowManager.updateViewLayout(bubble, bubbleParams);
                    return true;
                case MotionEvent.ACTION_UP:
                    float moved = Math.abs(event.getRawX()-downX)+Math.abs(event.getRawY()-downY);
                    if (event.getRawY() > getResources().getDisplayMetrics().heightPixels - dp(105)) {
                        stopSelf();
                    } else if (moved < dp(12)) {
                        expandPanel();
                    } else {
                        snapBubbleToEdge();
                    }
                    return true;
            }
            return true;
        });
        windowManager.addView(bubble, bubbleParams);
    }

    private void clampBubble() {
        int w = getResources().getDisplayMetrics().widthPixels;
        int h = getResources().getDisplayMetrics().heightPixels;
        bubbleParams.x = Math.max(0, Math.min(bubbleParams.x, w - dp(58)));
        bubbleParams.y = Math.max(dp(24), Math.min(bubbleParams.y, h - dp(90)));
    }

    private void snapBubbleToEdge() {
        int w = getResources().getDisplayMetrics().widthPixels;
        bubbleParams.x = bubbleParams.x + dp(29) < w / 2 ? dp(5) : w - dp(63);
        if (bubble != null && bubble.getParent() != null) windowManager.updateViewLayout(bubble, bubbleParams);
    }

    private void expandPanel() {
        if (expanded) { minimizePanel(); return; }
        expanded = true;
        if (bubble != null && bubble.getParent() != null) windowManager.removeView(bubble);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackground(shape(Color.rgb(13, 17, 35), dp(18), Color.rgb(88, 102, 160)));
        root.setClipToOutline(true);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(4), dp(7), dp(4));
        header.setBackgroundColor(Color.rgb(35, 42, 82));
        TextView title = text("SSPACE  •  " + displayName, 13, Color.WHITE);
        title.setGravity(Gravity.CENTER_VERTICAL);
        title.setSingleLine(true);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        header.addView(title, new LinearLayout.LayoutParams(0, dp(42), 1));
        Button minimize = new Button(this);
        minimize.setText("—");
        minimize.setTextColor(Color.WHITE);
        minimize.setBackgroundColor(Color.TRANSPARENT);
        header.addView(minimize, new LinearLayout.LayoutParams(dp(44), dp(42)));
        Button close = new Button(this);
        close.setText("✕");
        close.setTextColor(Color.WHITE);
        close.setBackgroundColor(Color.TRANSPARENT);
        header.addView(close, new LinearLayout.LayoutParams(dp(44), dp(42)));
        root.addView(header);
        chatWebView = new WebView(this);
        WebSettings settings = chatWebView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadsImagesAutomatically(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        chatWebView.setBackgroundColor(Color.rgb(13, 17, 35));
        chatWebView.addJavascriptInterface(new OverlayBridge(), "SSPACEOverlay");
        chatWebView.setWebChromeClient(new WebChromeClient());
        WebViewAssetLoader assetLoader = new WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
            .build();
        chatWebView.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return assetLoader.shouldInterceptRequest(request.getUrl());
            }
            @Override public void onPageFinished(WebView view, String url) {
                openConversationInWebView();
            }
        });
        root.addView(chatWebView, new LinearLayout.LayoutParams(-1, 0, 1));
        panel = root;
        panelParams = new WindowManager.LayoutParams(
            Math.min(getResources().getDisplayMetrics().widthPixels - dp(20), dp(390)),
            Math.min(getResources().getDisplayMetrics().heightPixels - dp(90), dp(560)),
            overlayType(),
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT);
        panelParams.gravity = Gravity.CENTER;
        windowManager.addView(panel, panelParams);
        minimize.setOnClickListener(v -> minimizePanel());
        close.setOnClickListener(v -> stopSelf());
        header.setOnTouchListener((v, event) -> {
            if (event.getAction() == MotionEvent.ACTION_DOWN) { downX=event.getRawX(); downY=event.getRawY(); startX=panelParams.x; startY=panelParams.y; return true; }
            if (event.getAction() == MotionEvent.ACTION_MOVE) { panelParams.x=startX+(int)(event.getRawX()-downX); panelParams.y=startY+(int)(event.getRawY()-downY); windowManager.updateViewLayout(panel,panelParams); return true; }
            return event.getAction()==MotionEvent.ACTION_UP;
        });
        loadBundledApp();
    }

    private void loadBundledApp() {
        chatWebView.loadUrl("https://appassets.androidplatform.net/assets/index.html");
    }

    private void openConversationInWebView() {
        if (chatWebView == null || otherId.isEmpty()) return;
        String id = JSONObject.quote(otherId);
        chatWebView.evaluateJavascript("(function(){if(window.SSPACE_NATIVE_OPEN_CHAT){window.SSPACE_NATIVE_OPEN_CHAT("+id+");}else{setTimeout(arguments.callee,350);}})()", null);
    }

    private void minimizePanel() {
        if (panel != null) { windowManager.removeView(panel); panel = null; }
        if (chatWebView != null) { chatWebView.destroy(); chatWebView = null; }
        expanded = false;
        createBubble();
    }

    private int dp(int value) { return (int)(value * getResources().getDisplayMetrics().density + 0.5f); }

    public class OverlayBridge {
        @JavascriptInterface public void closeOverlay() { stopSelf(); }
        @JavascriptInterface public void minimizeOverlay() { new android.os.Handler(getMainLooper()).post(() -> minimizePanel()); }
    }

    @Override public void onDestroy() {
        try { if (panel != null) windowManager.removeView(panel); } catch (Exception ignored) {}
        try { if (bubble != null) windowManager.removeView(bubble); } catch (Exception ignored) {}
        if (chatWebView != null) { chatWebView.destroy(); chatWebView = null; }
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}