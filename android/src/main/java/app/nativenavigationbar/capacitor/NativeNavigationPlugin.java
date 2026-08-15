/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

package app.nativenavigationbar.capacitor;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Outline;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.ViewParent;
import android.view.Window;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.appcompat.content.res.AppCompatResources;
import androidx.appcompat.widget.Toolbar;
import com.getcapacitor.Bridge;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import org.json.JSONArray;
import org.json.JSONObject;

@CapacitorPlugin(name = "NativeNavigation")
public class NativeNavigationPlugin extends Plugin {

    private static final int DEFAULT_NAVBAR_DP = 56;
    private static final int DEFAULT_TABBAR_DP = 64;
    private static final int DEFAULT_TRANSITION_MS = 350;
    private static final int MAX_TRANSITION_MS = 60_000;
    private static final int TRANSITION_WATCHDOG_GRACE_MS = 4_000;
    private static final int MAX_SNAPSHOT_PIXELS = 8_388_608;
    private static final int MAX_LAYOUT_DP = 2_048;
    private static final double MAX_TRANSITION_COORDINATE_DP = 1_000_000d;
    private static final int MENU_ITEM_BASE = 10_000;
    private static final int DEFAULT_TABBAR_BACKGROUND_COLOR = Color.WHITE;
    private static final int DEFAULT_TINT_COLOR = Color.rgb(0, 122, 255);
    private static final int DEFAULT_INACTIVE_TINT_COLOR = Color.rgb(120, 126, 137);
    private static final int DETACHED_TRAILING_GAP_DP = 10;
    private static final int MAX_INLINE_IMAGE_CHARACTERS = SvgIconRenderer.MAX_SVG_CHARACTERS * 2;
    private static final String[] CSS_INSET_VARIABLES = {
        "--cap-native-navigation-top",
        "--cap-native-navigation-right",
        "--cap-native-navigation-bottom",
        "--cap-native-navigation-left",
        "--cap-native-navbar-height",
        "--cap-native-tabbar-height",
    };
    private static final AtomicLong TRANSITION_SEQUENCE = new AtomicLong();

    private final NativeNavigation implementation = new NativeNavigation();
    private FrameLayout navbarContainer;
    private FrameLayout tabbarContainer;
    private View tabbarBackdrop;
    private Toolbar toolbar;
    private NativeTabbarLayout tabbar;
    private GlassBackdropView navbarGlassBackdrop;
    private View navbarGlassSurface;
    private GlassBackdropView tabbarGlassBackdrop;
    private View tabbarGlassSurface;
    private final JSObject configState = new JSObject()
        .put("enabled", true)
        .put("contentInsetMode", "css")
        .put("platformStyle", "auto");
    private final JSObject navbarState = new JSObject();
    private final JSObject tabbarState = new JSObject();
    private boolean navbarStateInitialized;
    private boolean tabbarStateInitialized;
    private boolean enabled = true;
    private boolean navbarVisible = false;
    private boolean tabbarVisible = false;
    private String contentInsetMode = "css";
    private GlassOptions defaultGlassOptions = GlassOptions.defaults();
    private GlassOptions navbarGlassOptions = GlassOptions.defaults();
    private GlassOptions tabbarGlassOptions = GlassOptions.defaults();
    private int defaultTransitionMs = DEFAULT_TRANSITION_MS;
    private int tintColor = Color.rgb(0, 122, 255);
    private int inactiveTintColor = Color.rgb(120, 126, 137);
    private int navbarBackgroundColor = Color.argb(225, 255, 255, 255);
    private int tabbarBackgroundColor = Color.argb(235, 255, 255, 255);
    private int badgeBackgroundColor = Color.rgb(255, 59, 48);
    private int badgeTextColor = Color.WHITE;
    private boolean disableIndicator = false;
    private int indicatorColor = Color.argb(34, 0, 122, 255);
    private int rippleColor = Color.argb(40, 0, 122, 255);
    private TabbarStyle tabbarStyle = TabbarStyle.defaults(Color.rgb(0, 122, 255));
    private final Map<Integer, String> menuActionIds = new HashMap<>();
    private final Map<Integer, String> menuActionTitles = new HashMap<>();
    private final Map<Integer, String> menuActionPlacements = new HashMap<>();
    private final Map<Integer, Boolean> menuActionTemplates = new HashMap<>();
    private final List<NativeTabItem> tabItems = new ArrayList<>();
    private int selectedTabIndex = 0;

    /*
     * Safety net for a `beginTransition` that never gets a matching
     * `finishTransition` (an app bug, an exception thrown between the two
     * calls, or the process getting backgrounded mid-transition). Without this
     * the WebView is left at alpha 0.01f — effectively invisible — until
     * something else happens to reset it. Cancelled as soon as the transition
     * finishes normally, and also fired immediately from `handleOnPause`.
     */
    private final Handler transitionWatchdogHandler = new Handler(Looper.getMainLooper());
    private TransitionSession activeTransition;

    private int lastRootWidth = -1;
    private int lastRootHeight = -1;
    private View observedRoot;
    private View insetsObserverView;
    private Insets lastSystemInsets = Insets.NONE;
    private boolean hasReceivedWindowInsets;
    private boolean insetsUpdatePending;

    private static final class TransitionSession {

        final String id;
        String direction;
        int durationMs;
        RectF zoomSourceFrame;
        float zoomCornerRadiusPx;
        ImageView snapshot;
        Bitmap bitmap;
        Drawable rootBackground;
        boolean rootBackgroundCaptured;
        Runnable watchdog;
        Runnable delayedCompletion;
        PluginCall finishCall;
        boolean completed;

        TransitionSession(String id, String direction, int durationMs) {
            this.id = id;
            this.direction = direction;
            this.durationMs = durationMs;
        }
    }

    /*
     * Capacitor's BridgeActivity absorbs orientation and screen-size configuration
     * changes instead of being recreated, so nothing re-runs the chrome layout
     * after a rotation and the tabbar keeps the pixel width it was given in the
     * previous orientation. Watching the content root's bounds fixes rotation,
     * multi-window resizes and display cutout changes with one hook that exists
     * in every supported Capacitor version.
     */
    private final View.OnLayoutChangeListener rootLayoutListener = (
        view,
        left,
        top,
        right,
        bottom,
        oldLeft,
        oldTop,
        oldRight,
        oldBottom
    ) -> {
        int width = right - left;
        int height = bottom - top;
        if (width == lastRootWidth && height == lastRootHeight) {
            return;
        }
        lastRootWidth = width;
        lastRootHeight = height;
        // setLayoutParams() inside layoutChrome() would re-enter this listener, so
        // defer to the next frame and gate on an actual size change.
        view.post(this::handleRootSizeChanged);
    };

    @Override
    public void load() {
        Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> {
            enableEdgeToEdge();
            observeContentRoot();
        });
    }

    @Override
    protected void handleOnDestroy() {
        runOnUiThread(this::teardownChrome);
        super.handleOnDestroy();
    }

    @Override
    protected void handleOnPause() {
        // If the app is backgrounded mid-transition, nothing the user is
        // watching matters anymore, so force-complete it immediately rather
        // than leaving the WebView at alpha 0.01f for whenever the activity
        // happens to resume.
        TransitionSession session = activeTransition;
        if (session != null) {
            runOnUiThread(() -> recoverStuckTransition(session));
        }
        super.handleOnPause();
    }

    @PluginMethod
    public void configure(PluginCall call) {
        runOnUiThread(() -> {
            Double requestedDuration = call.getDouble("animationDuration");
            if (requestedDuration != null && !isValidTransitionDuration(requestedDuration)) {
                call.reject("animationDuration must be finite and between 0 and " + MAX_TRANSITION_MS + " milliseconds");
                return;
            }
            mergeState(configState, call.getData(), "colors", "glass");
            enabled = configState.optBoolean("enabled", true);
            contentInsetMode = "none".equals(configState.optString("contentInsetMode", "css")) ? "none" : "css";
            defaultGlassOptions = GlassOptions.from(configState.optJSONObject("glass"), GlassOptions.defaults());
            if (configState.has("animationDuration")) {
                defaultTransitionMs = validatedTransitionDuration(configState.optDouble("animationDuration", DEFAULT_TRANSITION_MS));
            }
            navbarGlassOptions = GlassOptions.from(navbarState.optJSONObject("glass"), defaultGlassOptions);
            tabbarGlassOptions = GlassOptions.from(tabbarState.optJSONObject("glass"), defaultGlassOptions);
            if (!enabled) {
                hideChromeForDisabledState();
            } else if (!applyNavbarState() || !applyTabbarState()) {
                call.reject("Activity unavailable");
                return;
            }
            updateInsetsAndNotify();
            call.resolve(insetsResult());
        });
    }

    @PluginMethod
    public void setNavbar(PluginCall call) {
        runOnUiThread(() -> {
            mergeState(navbarState, call.getData(), "colors", "glass");
            navbarStateInitialized = true;
            if (!enabled) {
                hideNavbarViews();
                updateInsetsAndNotify();
                call.resolve(insetsResult());
                return;
            }
            if (!applyNavbarState()) {
                call.reject("Activity unavailable");
                return;
            }
            updateInsetsAndNotify();
            call.resolve(insetsResult());
        });
    }

    @PluginMethod
    public void setTabbar(PluginCall call) {
        runOnUiThread(() -> {
            mergeState(tabbarState, call.getData(), "colors", "glass", "style");
            tabbarStateInitialized = true;
            if (!enabled) {
                hideTabbarViews();
                updateInsetsAndNotify();
                call.resolve(insetsResult());
                return;
            }
            if (!applyTabbarState()) {
                call.reject("Activity unavailable");
                return;
            }
            updateInsetsAndNotify();
            call.resolve(insetsResult());
        });
    }

    private boolean applyNavbarState() {
        if (!navbarStateInitialized) {
            hideNavbarViews();
            return true;
        }
        navbarVisible = NativeVisibilityState.isVisible(navbarStateInitialized, enabled, navbarState.opt("hidden"));
        if (!navbarVisible) {
            hideNavbarViews();
            return true;
        }

        Toolbar nativeToolbar = ensureToolbar();
        if (nativeToolbar == null) {
            navbarVisible = false;
            return false;
        }
        nativeToolbar.setTitle(navbarState.optString("title", ""));
        nativeToolbar.setSubtitle(nullableString(navbarState, "subtitle"));
        nativeToolbar.getMenu().clear();
        menuActionIds.clear();
        menuActionTitles.clear();
        menuActionPlacements.clear();
        menuActionTemplates.clear();

        JSONObject backButton = navbarState.optJSONObject("backButton");
        if (backButton != null && backButton.optBoolean("visible", false)) {
            nativeToolbar.setNavigationIcon(androidx.appcompat.R.drawable.abc_ic_ab_back_material);
            nativeToolbar.setNavigationContentDescription(backButton.optString("title", "Back"));
            nativeToolbar.setNavigationOnClickListener(v -> emitEvent("navbarBack", new JSObject().put("source", "navbar")));
        } else {
            nativeToolbar.setNavigationIcon(null);
            nativeToolbar.setNavigationOnClickListener(null);
            addToolbarItems(nativeToolbar, arrayOrEmpty(navbarState, "leftItems"), "left");
        }
        addToolbarItems(nativeToolbar, arrayOrEmpty(navbarState, "rightItems"), "right");

        JSObject colors = mergedObject(configState.optJSONObject("colors"), navbarState.optJSONObject("colors"));
        navbarGlassOptions = GlassOptions.from(navbarState.optJSONObject("glass"), defaultGlassOptions);
        applyToolbarColors(nativeToolbar, colors);
        navbarContainer.setVisibility(View.VISIBLE);
        return true;
    }

    private boolean applyTabbarState() {
        if (!tabbarStateInitialized) {
            hideTabbarViews();
            return true;
        }
        tabbarVisible = NativeVisibilityState.isVisible(tabbarStateInitialized, enabled, tabbarState.opt("hidden"));
        if (!tabbarVisible) {
            hideTabbarViews();
            return true;
        }

        NativeTabbarLayout nativeTabbar = ensureTabbar();
        if (nativeTabbar == null) {
            tabbarVisible = false;
            return false;
        }
        nativeTabbar.removeAllViews();
        tabItems.clear();
        selectedTabIndex = -1;

        boolean labels = tabbarState.optBoolean("labels", true);
        boolean icons = tabbarState.optBoolean("icons", true);
        String labelVisibilityMode = tabbarState.optString("labelVisibilityMode", labels ? "labeled" : "unlabeled");
        JSONArray tabs = arrayOrEmpty(tabbarState, "tabs");
        String selectedId = nullableString(tabbarState, "selectedId");
        JSObject colors = mergedObject(configState.optJSONObject("colors"), tabbarState.optJSONObject("colors"));
        tabbarGlassOptions = GlassOptions.from(tabbarState.optJSONObject("glass"), defaultGlassOptions);
        applyTabbarColors(tabbarState, colors);
        tabbarStyle = makeTabbarStyle(objectOrEmpty(tabbarState, "style"));
        badgeBackgroundColor = colorOption(
            tabbarState,
            colors,
            "badgeBackgroundColor",
            "badgeBackground",
            Color.rgb(255, 59, 48)
        );
        badgeTextColor = colorOption(tabbarState, colors, "badgeTextColor", "badgeText", Color.WHITE);
        disableIndicator = tabbarState.optBoolean("disableIndicator", false);
        indicatorColor = colorOption(tabbarState, colors, "indicatorColor", "indicator", withAlpha(tintColor, 34));
        rippleColor = colorOption(tabbarState, colors, "rippleColor", "ripple", withAlpha(tintColor, 40));

        int lastDetachedSourceIndex = lastVisibleDetachedSourceIndex(tabs, selectedId);
        for (int sourceIndex = 0; sourceIndex < tabs.length(); sourceIndex++) {
            JSONObject rawTab = tabs.optJSONObject(sourceIndex);
            if (rawTab == null) {
                continue;
            }
            String id = rawTab.optString("id", "tab-" + sourceIndex);
            boolean isHidden = rawTab.optBoolean("hidden", false);
            if (isHidden && !id.equals(selectedId)) {
                continue;
            }

            JSONObject iconDescriptor = rawTab.optJSONObject("icon");
            JSONObject selectedIconDescriptor = rawTab.optJSONObject("selectedIcon");
            Drawable icon = icons ? iconFrom(iconDescriptor) : null;
            Drawable selectedIcon = icons ? iconFrom(selectedIconDescriptor) : null;
            String badge = rawTab.has("badge") && !rawTab.isNull("badge") ? String.valueOf(rawTab.opt("badge")) : null;
            boolean detachedTrailing = !tabbarStyle.isCurve() && sourceIndex == lastDetachedSourceIndex;
            tabItems.add(
                new NativeTabItem(
                    id,
                    rawTab.optString("title", ""),
                    icon,
                    selectedIcon,
                    iconTemplate(iconDescriptor),
                    iconTemplate(selectedIconDescriptor),
                    iconWidthDp(iconDescriptor),
                    iconHeightDp(iconDescriptor),
                    iconWidthDp(selectedIconDescriptor),
                    iconHeightDp(selectedIconDescriptor),
                    badge,
                    rawTab.optBoolean("enabled", true),
                    detachedTrailing,
                    sourceIndex
                )
            );
        }
        NativeItemOrder.moveLastMatchingToEnd(tabItems, item -> item.detachedTrailing);

        for (int index = 0; index < tabItems.size(); index++) {
            if (tabItems.get(index).id.equals(selectedId)) {
                selectedTabIndex = index;
                break;
            }
        }
        if (tabItems.isEmpty()) {
            hideTabbarViews();
            return true;
        }
        if (selectedTabIndex < 0 || selectedTabIndex >= tabItems.size()) {
            selectedTabIndex = firstEnabledTabIndex();
        }

        renderTabbarItems(labelVisibilityMode, icons);
        if (tabbarContainer != null) {
            tabbarContainer.setVisibility(View.VISIBLE);
        }
        if (tabbarBackdrop != null) {
            tabbarBackdrop.setVisibility(View.VISIBLE);
        }
        nativeTabbar.setVisibility(View.VISIBLE);
        return true;
    }

    private void hideChromeForDisabledState() {
        hideNavbarViews();
        hideTabbarViews();
    }

    private void hideNavbarViews() {
        navbarVisible = false;
        if (navbarContainer != null) {
            navbarContainer.setVisibility(View.GONE);
        }
    }

    private void hideTabbarViews() {
        tabbarVisible = false;
        if (tabbar != null) {
            tabbar.setVisibility(View.GONE);
        }
        if (tabbarContainer != null) {
            tabbarContainer.setVisibility(View.GONE);
        }
        if (tabbarBackdrop != null) {
            tabbarBackdrop.setVisibility(View.GONE);
        }
    }

    private int firstEnabledTabIndex() {
        for (int index = 0; index < tabItems.size(); index++) {
            if (tabItems.get(index).enabled) {
                return index;
            }
        }
        return 0;
    }

    private int lastVisibleDetachedSourceIndex(JSONArray tabs, String selectedId) {
        for (int index = tabs.length() - 1; index >= 0; index--) {
            JSONObject tab = tabs.optJSONObject(index);
            if (tab == null) {
                continue;
            }
            String id = tab.optString("id", "tab-" + index);
            if (tab.optBoolean("hidden", false) && !id.equals(selectedId)) {
                continue;
            }
            String role = tab.optString("role", "normal");
            if ("search".equalsIgnoreCase(role) || "prominent".equalsIgnoreCase(role)) {
                return index;
            }
        }
        return -1;
    }

    private void mergeState(JSObject state, JSObject patch, String... nestedKeys) {
        if (patch == null) {
            return;
        }
        Iterator<String> keys = patch.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object value = patch.opt(key);
            if (isNestedKey(key, nestedKeys) && value instanceof JSONObject) {
                state.put(key, mergedObject(state.optJSONObject(key), (JSONObject) value));
            } else if (value == JSONObject.NULL) {
                if (!isNestedKey(key, nestedKeys)) {
                    state.put(key, JSONObject.NULL);
                }
            } else if (value != null) {
                state.put(key, value);
            }
        }
    }

    private boolean isNestedKey(String key, String... nestedKeys) {
        for (String nestedKey : nestedKeys) {
            if (nestedKey.equals(key)) {
                return true;
            }
        }
        return false;
    }

    private JSObject mergedObject(JSONObject base, JSONObject patch) {
        JSObject result = new JSObject();
        copyObjectProperties(base, result);
        copyObjectProperties(patch, result);
        return result;
    }

    private void copyObjectProperties(JSONObject source, JSObject destination) {
        if (source == null) {
            return;
        }
        Iterator<String> keys = source.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object value = source.opt(key);
            if (value != null) {
                destination.put(key, value);
            }
        }
    }

    private JSObject objectOrEmpty(JSONObject source, String key) {
        return mergedObject(source == null ? null : source.optJSONObject(key), null);
    }

    private JSONArray arrayOrEmpty(JSONObject source, String key) {
        JSONArray value = source == null ? null : source.optJSONArray(key);
        return value == null ? new JSArray() : value;
    }

    private String nullableString(JSONObject source, String key) {
        if (source == null || !source.has(key) || source.isNull(key)) {
            return null;
        }
        return source.optString(key, null);
    }

    @PluginMethod
    public void beginTransition(PluginCall call) {
        runOnUiThread(() -> {
            Bridge bridge = getBridge();
            View webView = bridge == null ? null : bridge.getWebView();
            FrameLayout root = contentRoot();
            if (webView == null || root == null || webView.getWidth() <= 0 || webView.getHeight() <= 0) {
                call.reject("WebView unavailable");
                return;
            }
            Double duration = call.getDouble("duration");
            if (duration != null && !isValidTransitionDuration(duration)) {
                call.reject("duration must be finite and between 0 and " + MAX_TRANSITION_MS + " milliseconds");
                return;
            }

            cancelActiveTransitionForReplacement();
            resetWebViewTransitionProperties(webView);

            String transitionId = call.getString("id", nextTransitionId());
            String direction = call.getString("direction", "forward");
            int durationMs = duration == null ? defaultTransitionMs : validatedTransitionDuration(duration);
            TransitionSession session = new TransitionSession(transitionId, direction, durationMs);
            activeTransition = session;

            RectF zoomSourceRectDp = "zoom".equals(direction) ? transitionRect(call.getObject("sourceRect", null)) : null;
            session.zoomSourceFrame = zoomSourceRectDp == null ? null : rootFrameFromDp(zoomSourceRectDp, webView, root);
            session.zoomCornerRadiusPx = cornerRadiusPx(call.getDouble("cornerRadius"));
            int transitionSurface = transitionSurfaceColor(webView);
            prepareTransitionRootBackground(session, root, transitionSurface);

            try {
                Rect crop = zoomSourceRectDp == null ? null : bitmapCropRectFromDp(zoomSourceRectDp, webView);
                session.bitmap = captureWebViewBitmap(webView, crop);
                session.snapshot = new ImageView(getContext());
                session.snapshot.setImageBitmap(session.bitmap);
                session.snapshot.setBackgroundColor(transitionSurface);
                session.snapshot.setScaleType(ImageView.ScaleType.FIT_XY);
            } catch (OutOfMemoryError | RuntimeException error) {
                cleanupTransition(session, false, null);
                call.reject("Unable to capture the WebView transition snapshot");
                return;
            }

            try {
                RectF snapshotFrame = session.zoomSourceFrame == null ? webViewFrameInRoot(webView, root) : session.zoomSourceFrame;
                FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    Math.max(1, Math.round(snapshotFrame.width())),
                    Math.max(1, Math.round(snapshotFrame.height()))
                );
                params.leftMargin = Math.round(snapshotFrame.left);
                params.topMargin = Math.round(snapshotFrame.top);
                if (session.zoomCornerRadiusPx > 0) {
                    session.snapshot.setClipToOutline(true);
                    session.snapshot.setOutlineProvider(roundRectOutlineProvider(session.zoomCornerRadiusPx));
                }
                root.addView(session.snapshot, params);
                webView.setAlpha(0.01f);
            } catch (OutOfMemoryError | RuntimeException error) {
                cleanupTransition(session, false, null);
                call.reject("Unable to prepare the WebView transition snapshot");
                return;
            }
            bringChromeToFront();
            armTransitionWatchdog(session, durationMs);

            JSObject event = transitionEvent(session.id, session.direction, session.durationMs);
            emitEvent("transitionStart", event);
            call.resolve(event);
        });
    }

    @PluginMethod
    public void finishTransition(PluginCall call) {
        runOnUiThread(() -> {
            Bridge bridge = getBridge();
            View webView = bridge == null ? null : bridge.getWebView();
            if (webView == null) {
                call.reject("WebView unavailable");
                return;
            }
            String explicitId = call.getString("id", null);
            TransitionSession session = activeTransition;
            if (session == null || session.completed) {
                call.reject("No active transition");
                return;
            }
            if (explicitId != null && !explicitId.equals(session.id)) {
                call.reject("Transition id does not match the active transition");
                return;
            }
            if (session.finishCall != null) {
                call.reject("Transition is already finishing");
                return;
            }
            Double duration = call.getDouble("duration");
            if (duration != null && !isValidTransitionDuration(duration)) {
                call.reject("duration must be finite and between 0 and " + MAX_TRANSITION_MS + " milliseconds");
                return;
            }
            String direction = call.getString("direction", session.direction);
            int durationMs = duration == null ? session.durationMs : validatedTransitionDuration(duration);
            session.direction = direction;
            session.durationMs = durationMs;
            session.finishCall = call;
            armTransitionWatchdog(session, durationMs);

            float width = webView.getWidth();
            if ("zoom".equals(direction)) {
                FrameLayout root = contentRoot();
                RectF sourceRectDp = transitionRect(call.getObject("sourceRect", null));
                RectF targetRectDp = transitionRect(call.getObject("targetRect", null));
                finishZoomTransition(
                    webView,
                    session,
                    root == null || sourceRectDp == null ? null : rootFrameFromDp(sourceRectDp, webView, root),
                    root == null || targetRectDp == null ? null : rootFrameFromDp(targetRectDp, webView, root),
                    call.getDouble("cornerRadius") == null ? session.zoomCornerRadiusPx : cornerRadiusPx(call.getDouble("cornerRadius"))
                );
                return;
            }
            float startTranslation;
            float snapshotEndTranslation;
            if ("back".equals(direction)) {
                startTranslation = -width * 0.3f;
                snapshotEndTranslation = width;
            } else if (isStationaryTransition(direction)) {
                startTranslation = 0;
                snapshotEndTranslation = 0;
            } else {
                startTranslation = width;
                snapshotEndTranslation = -width * 0.3f;
            }

            boolean stationaryTransition = isStationaryTransition(direction);
            webView.animate().cancel();
            webView.setTranslationX(startTranslation);
            webView.setAlpha(stationaryTransition ? 1f : 0.01f);
            ImageView snapshot = session.snapshot;
            TransitionSession finishingSession = session;
            JSObject event = transitionEvent(session.id, direction, durationMs);
            Runnable finish = () -> completeTransition(finishingSession, event);

            if (durationMs == 0) {
                finish.run();
                return;
            }

            webView.animate().translationX(0).alpha(1f).setDuration(durationMs).start();
            if (snapshot != null) {
                snapshot.animate().cancel();
                snapshot
                    .animate()
                    .translationX(snapshotEndTranslation)
                    .alpha(stationaryTransition ? 0f : 0.75f)
                    .setDuration(durationMs)
                    .withEndAction(finish)
                    .start();
            } else {
                finishingSession.delayedCompletion = finish;
                transitionWatchdogHandler.postDelayed(finish, durationMs);
            }
        });
    }

    @PluginMethod
    public void getPluginVersion(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("version", implementation.getPluginVersion());
        call.resolve(ret);
    }

    private void armTransitionWatchdog(TransitionSession session, int durationMs) {
        cancelTransitionCallbacks(session);
        long delayMs = Math.max(0, durationMs) + (long) TRANSITION_WATCHDOG_GRACE_MS;
        session.watchdog = () -> recoverStuckTransition(session);
        transitionWatchdogHandler.postDelayed(session.watchdog, delayMs);
    }

    private void cancelTransitionCallbacks(TransitionSession session) {
        if (session == null) {
            return;
        }
        if (session.watchdog != null) {
            transitionWatchdogHandler.removeCallbacks(session.watchdog);
            session.watchdog = null;
        }
        if (session.delayedCompletion != null) {
            transitionWatchdogHandler.removeCallbacks(session.delayedCompletion);
            session.delayedCompletion = null;
        }
    }

    private void recoverStuckTransition(TransitionSession session) {
        if (session == null || session != activeTransition || session.completed) {
            return;
        }
        completeTransition(session, transitionEvent(session.id, session.direction, 0));
    }

    private void finishZoomTransition(
        View webView,
        TransitionSession session,
        RectF sourceFrame,
        RectF targetFrame,
        float cornerRadiusPx
    ) {
        RectF startFrame = sourceFrame == null ? session.zoomSourceFrame : sourceFrame;
        FrameLayout root = contentRoot();
        if (startFrame == null) {
            startFrame = root == null
                ? new RectF(0, 0, webView.getWidth(), webView.getHeight())
                : webViewFrameInRoot(webView, root);
        }
        int durationMs = session.durationMs;
        ImageView snapshot = session.snapshot;
        JSObject event = transitionEvent(session.id, "zoom", durationMs);
        Runnable finish = () -> completeTransition(session, event);

        if (durationMs == 0) {
            finish.run();
            return;
        }

        if (targetFrame != null && snapshot != null) {
            webView.animate().cancel();
            snapshot.animate().cancel();
            webView.setAlpha(0.01f);
            snapshot.setX(startFrame.left);
            snapshot.setY(startFrame.top);
            snapshot.setPivotX(0f);
            snapshot.setPivotY(0f);
            float scaleX = targetFrame.width() / Math.max(startFrame.width(), 1f);
            float scaleY = targetFrame.height() / Math.max(startFrame.height(), 1f);
            webView.animate().alpha(1f).setDuration(durationMs).start();
            snapshot
                .animate()
                .x(targetFrame.left)
                .y(targetFrame.top)
                .scaleX(scaleX)
                .scaleY(scaleY)
                .alpha(0f)
                .setDuration(durationMs)
                .withEndAction(finish)
                .start();
            return;
        }

        float fullWidth = Math.max(webView.getWidth(), 1f);
        float fullHeight = Math.max(webView.getHeight(), 1f);
        RectF webViewFrame = root == null
            ? new RectF(0, 0, fullWidth, fullHeight)
            : webViewFrameInRoot(webView, root);
        float fullCenterX = webViewFrame.centerX();
        float fullCenterY = webViewFrame.centerY();
        webView.animate().cancel();
        webView.setPivotX(fullWidth / 2f);
        webView.setPivotY(fullHeight / 2f);
        webView.setTranslationX(startFrame.centerX() - fullCenterX);
        webView.setTranslationY(startFrame.centerY() - fullCenterY);
        webView.setScaleX(Math.max(startFrame.width() / fullWidth, 0.01f));
        webView.setScaleY(Math.max(startFrame.height() / fullHeight, 0.01f));
        webView.setAlpha(1f);
        if (cornerRadiusPx > 0) {
            webView.setClipToOutline(true);
            webView.setOutlineProvider(roundRectOutlineProvider(cornerRadiusPx));
        }

        if (snapshot != null) {
            snapshot.animate().cancel();
            snapshot.setX(startFrame.left);
            snapshot.setY(startFrame.top);
            snapshot.setPivotX(0f);
            snapshot.setPivotY(0f);
            snapshot
                .animate()
                .x(webViewFrame.left)
                .y(webViewFrame.top)
                .scaleX(fullWidth / Math.max(startFrame.width(), 1f))
                .scaleY(fullHeight / Math.max(startFrame.height(), 1f))
                .alpha(0f)
                .setDuration(durationMs)
                .start();
        }

        webView
            .animate()
            .translationX(0)
            .translationY(0)
            .scaleX(1f)
            .scaleY(1f)
            .alpha(1f)
            .setDuration(durationMs)
            .withEndAction(() -> {
                webView.setClipToOutline(false);
                webView.setOutlineProvider(ViewOutlineProvider.BACKGROUND);
                finish.run();
            })
            .start();
    }

    private void completeTransition(TransitionSession session, JSObject event) {
        if (session == null || session != activeTransition || session.completed) {
            return;
        }
        PluginCall finishCall = session.finishCall;
        cleanupTransition(session, true, event);
        if (finishCall != null) {
            finishCall.resolve(event);
        }
    }

    private void cancelActiveTransitionForReplacement() {
        TransitionSession session = activeTransition;
        if (session != null && !session.completed) {
            JSObject event = transitionEvent(session.id, session.direction, 0);
            PluginCall finishCall = session.finishCall;
            cleanupTransition(session, true, event);
            if (finishCall != null) {
                finishCall.resolve(event);
            }
        }
    }

    private void cleanupTransition(TransitionSession session, boolean notifyEnd, JSObject event) {
        if (session == null || session.completed) {
            return;
        }
        session.completed = true;
        cancelTransitionCallbacks(session);
        Bridge bridge = getBridge();
        View webView = bridge == null ? null : bridge.getWebView();
        if (webView != null) {
            resetWebViewTransitionProperties(webView);
        }
        removeTransitionSnapshot(session);
        restoreTransitionRootBackground(session);
        if (activeTransition == session) {
            activeTransition = null;
        }
        if (notifyEnd && event != null) {
            emitEvent("transitionEnd", event);
        }
    }

    private void removeTransitionSnapshot(TransitionSession session) {
        if (session == null) {
            return;
        }
        ImageView snapshot = session.snapshot;
        if (snapshot != null) {
            snapshot.animate().cancel();
            removeFromParent(snapshot);
            snapshot.setImageDrawable(null);
            session.snapshot = null;
        }
        if (session.bitmap != null && !session.bitmap.isRecycled()) {
            session.bitmap.recycle();
        }
        session.bitmap = null;
    }

    private void resetWebViewTransitionProperties(View webView) {
        webView.animate().cancel();
        webView.setTranslationX(0);
        webView.setTranslationY(0);
        webView.setScaleX(1f);
        webView.setScaleY(1f);
        webView.setAlpha(1f);
        webView.setClipToOutline(false);
        webView.setOutlineProvider(ViewOutlineProvider.BACKGROUND);
    }

    private Bitmap captureWebViewBitmap(View webView, Rect crop) {
        Rect capture = crop == null ? new Rect(0, 0, webView.getWidth(), webView.getHeight()) : crop;
        int captureWidth = Math.max(1, capture.width());
        int captureHeight = Math.max(1, capture.height());
        long pixels = (long) captureWidth * captureHeight;
        float scale = pixels > MAX_SNAPSHOT_PIXELS ? (float) Math.sqrt(MAX_SNAPSHOT_PIXELS / (double) pixels) : 1f;
        int bitmapWidth = Math.max(1, Math.round(captureWidth * scale));
        int bitmapHeight = Math.max(1, Math.round(captureHeight * scale));
        Bitmap bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888);
        try {
            Canvas canvas = new Canvas(bitmap);
            canvas.scale(scale, scale);
            canvas.translate(-capture.left, -capture.top);
            webView.draw(canvas);
            return bitmap;
        } catch (RuntimeException | OutOfMemoryError error) {
            bitmap.recycle();
            throw error;
        }
    }

    private boolean isValidTransitionDuration(double duration) {
        return Double.isFinite(duration) && duration >= 0 && duration <= MAX_TRANSITION_MS;
    }

    private int validatedTransitionDuration(double duration) {
        return (int) Math.round(Math.max(0, Math.min(MAX_TRANSITION_MS, duration)));
    }

    private String nextTransitionId() {
        return "transition-" + System.currentTimeMillis() + "-" + TRANSITION_SEQUENCE.incrementAndGet();
    }

    private boolean hasDetachedTrailingItem() {
        return tabItems.stream().anyMatch((item) -> item.detachedTrailing);
    }

    private void addToolbarItems(Toolbar nativeToolbar, JSONArray rawItems, String placement) {
        for (int index = 0; index < rawItems.length(); index++) {
            JSONObject rawItem = rawItems.optJSONObject(index);
            if (rawItem == null) {
                continue;
            }
            int itemId = MENU_ITEM_BASE + menuActionIds.size();
            String id = rawItem.optString("id", "item-" + itemId);
            String title = rawItem.optString("title", "");
            MenuItem item = nativeToolbar.getMenu().add(Menu.NONE, itemId, index, title);
            item.setEnabled(rawItem.optBoolean("enabled", true));
            Drawable icon = iconFrom(rawItem.optJSONObject("icon"));
            if (icon != null) {
                item.setIcon(icon);
            }
            item.setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS);
            menuActionIds.put(itemId, id);
            menuActionTitles.put(itemId, title);
            menuActionPlacements.put(itemId, placement);
            menuActionTemplates.put(itemId, iconTemplate(rawItem.optJSONObject("icon")));
        }
    }

    private RectF transitionRect(JSONObject object) {
        if (object == null) {
            return null;
        }
        double width = object.optDouble("width", 0);
        double height = object.optDouble("height", 0);
        double x = object.optDouble("x", 0);
        double y = object.optDouble("y", 0);
        double right = x + width;
        double bottom = y + height;
        if (
            !Double.isFinite(x) ||
            !Double.isFinite(y) ||
            !Double.isFinite(width) ||
            !Double.isFinite(height) ||
            !Double.isFinite(right) ||
            !Double.isFinite(bottom) ||
            Math.abs(x) > MAX_TRANSITION_COORDINATE_DP ||
            Math.abs(y) > MAX_TRANSITION_COORDINATE_DP ||
            width <= 0 ||
            width > MAX_TRANSITION_COORDINATE_DP ||
            height <= 0 ||
            height > MAX_TRANSITION_COORDINATE_DP
        ) {
            return null;
        }
        return new RectF((float) x, (float) y, (float) right, (float) bottom);
    }

    private RectF rootFrameFromDp(RectF viewportRectDp, View webView, FrameLayout root) {
        float density = displayDensity();
        RectF webViewFrame = webViewFrameInRoot(webView, root);
        return new RectF(
            webViewFrame.left + NativeUnitConverter.dpToPhysicalPx(viewportRectDp.left, density),
            webViewFrame.top + NativeUnitConverter.dpToPhysicalPx(viewportRectDp.top, density),
            webViewFrame.left + NativeUnitConverter.dpToPhysicalPx(viewportRectDp.right, density),
            webViewFrame.top + NativeUnitConverter.dpToPhysicalPx(viewportRectDp.bottom, density)
        );
    }

    private RectF webViewFrameInRoot(View webView, FrameLayout root) {
        int[] webViewLocation = new int[2];
        int[] rootLocation = new int[2];
        webView.getLocationOnScreen(webViewLocation);
        root.getLocationOnScreen(rootLocation);
        int left = NativeUnitConverter.relativeScreenPosition(webViewLocation[0], rootLocation[0]);
        int top = NativeUnitConverter.relativeScreenPosition(webViewLocation[1], rootLocation[1]);
        return new RectF(left, top, left + webView.getWidth(), top + webView.getHeight());
    }

    private Rect bitmapCropRectFromDp(RectF viewportRectDp, View webView) {
        float density = displayDensity();
        int left = Math.max(0, Math.min(webView.getWidth() - 1, Math.round(NativeUnitConverter.dpToPhysicalPx(viewportRectDp.left, density))));
        int top = Math.max(0, Math.min(webView.getHeight() - 1, Math.round(NativeUnitConverter.dpToPhysicalPx(viewportRectDp.top, density))));
        int right = Math.max(left + 1, Math.min(webView.getWidth(), Math.round(NativeUnitConverter.dpToPhysicalPx(viewportRectDp.right, density))));
        int bottom = Math.max(top + 1, Math.min(webView.getHeight(), Math.round(NativeUnitConverter.dpToPhysicalPx(viewportRectDp.bottom, density))));
        return new Rect(left, top, right, bottom);
    }

    private float cornerRadiusPx(Double cornerRadiusDp) {
        if (cornerRadiusDp == null || !Double.isFinite(cornerRadiusDp) || cornerRadiusDp <= 0d) {
            return 0f;
        }
        return NativeUnitConverter.dpToPhysicalPx(Math.min(cornerRadiusDp, SvgIconRenderer.MAX_ICON_SIZE_DP), displayDensity());
    }

    private ViewOutlineProvider roundRectOutlineProvider(float radius) {
        return new ViewOutlineProvider() {
            @Override
            public void getOutline(View view, Outline outline) {
                outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
            }
        };
    }

    private Toolbar ensureToolbar() {
        if (toolbar != null) {
            return toolbar;
        }
        Activity activity = getActivity();
        if (activity == null) {
            return null;
        }
        FrameLayout root = contentRoot();
        navbarContainer = new FrameLayout(getContext());
        navbarContainer.setElevation(dp(8));
        toolbar = new Toolbar(getContext());
        toolbar.setPopupTheme(androidx.appcompat.R.style.ThemeOverlay_AppCompat_Light);
        navbarGlassBackdrop = new GlassBackdropView(getContext());
        navbarGlassSurface = new View(getContext());
        navbarGlassBackdrop.setVisibility(View.GONE);
        navbarGlassSurface.setVisibility(View.GONE);

        toolbar.setOnMenuItemClickListener(item -> {
            int itemId = item.getItemId();
            JSObject event = new JSObject();
            event.put("id", menuActionIds.get(itemId));
            event.put("title", menuActionTitles.get(itemId));
            event.put("placement", menuActionPlacements.get(itemId));
            emitEvent("navbarItemTap", event);
            return true;
        });

        navbarContainer.addView(navbarGlassBackdrop);
        navbarContainer.addView(navbarGlassSurface);
        navbarContainer.addView(toolbar);
        if (root != null) {
            root.addView(navbarContainer);
        } else {
            activity.addContentView(
                navbarContainer,
                new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(DEFAULT_NAVBAR_DP))
            );
        }
        return toolbar;
    }

    private NativeTabbarLayout ensureTabbar() {
        if (tabbar != null) {
            return tabbar;
        }
        Activity activity = getActivity();
        if (activity == null) {
            return null;
        }
        FrameLayout root = contentRoot();
        tabbarBackdrop = new View(getContext());
        tabbarBackdrop.setBackgroundColor(resolvedTabbarSurfaceColor());
        tabbarContainer = new FrameLayout(getContext());
        tabbarContainer.setClipChildren(false);
        tabbarContainer.setClipToPadding(false);
        tabbarContainer.setElevation(dp(12));

        tabbarGlassBackdrop = new GlassBackdropView(getContext());
        tabbarGlassSurface = new View(getContext());
        tabbarGlassBackdrop.setVisibility(View.GONE);
        tabbarGlassSurface.setVisibility(View.GONE);

        tabbar = new NativeTabbarLayout(getContext());
        tabbar.setClipChildren(false);
        tabbar.setClipToPadding(false);
        tabbar.setBackgroundColor(Color.TRANSPARENT);
        tabbarContainer.addView(tabbarGlassBackdrop);
        tabbarContainer.addView(tabbarGlassSurface);
        tabbarContainer.addView(
            tabbar,
            new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        );
        if (root != null) {
            root.addView(tabbarBackdrop);
            root.addView(tabbarContainer);
        } else {
            activity.addContentView(
                tabbarBackdrop,
                new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, Gravity.BOTTOM)
            );
            activity.addContentView(
                tabbarContainer,
                new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(DEFAULT_TABBAR_DP))
            );
        }
        return tabbar;
    }

    private void renderTabbarItems(String labelVisibilityMode, boolean icons) {
        if (tabbar == null) {
            return;
        }
        tabbar.removeAllViews();
        int centerIndex = centerTabIndex();
        applyTabbarBackground(centerIndex);
        for (int index = 0; index < tabItems.size(); index++) {
            final int itemIndex = index;
            NativeTabItem item = tabItems.get(index);
            boolean selected = itemIndex == selectedTabIndex;
            boolean detachedTrailing = item.detachedTrailing && !tabbarStyle.isCurve();
            boolean showLabel = detachedTrailing
                ? !icons && shouldShowTabLabel(labelVisibilityMode, selected)
                : shouldShowTabLabel(labelVisibilityMode, selected);
            FrameLayout button = makeTabButton(item, selected, showLabel, icons, itemIndex == centerIndex);
            if (detachedTrailing) {
                button.setTag(NativeTabbarLayout.TAG_DETACHED_TRAILING);
            }
            button.setSelected(selected);
            button.setEnabled(item.enabled);
            button.setAlpha(item.enabled ? 1f : 0.38f);
            button.setOnClickListener(view -> {
                if (!item.enabled) {
                    return;
                }
                selectedTabIndex = itemIndex;
                tabbarState.put("selectedId", item.id);
                renderTabbarItems(labelVisibilityMode, icons);
                JSObject event = new JSObject();
                event.put("id", item.id);
                event.put("index", item.sourceIndex);
                event.put("title", item.title);
                emitEvent("tabSelect", event);
            });
            tabbar.addView(button, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        }
    }

    private boolean shouldShowTabLabel(String mode, boolean selected) {
        if ("unlabeled".equals(mode)) {
            return false;
        }
        if ("selected".equals(mode)) {
            return selected;
        }
        return true;
    }

    private FrameLayout makeTabButton(NativeTabItem item, boolean selected, boolean showLabel, boolean icons, boolean center) {
        FrameLayout button = new FrameLayout(getContext());
        button.setClipChildren(false);
        button.setClipToPadding(false);
        button.setForeground(tabRippleBackground());
        if (center) {
            GradientDrawable centerBackground = new GradientDrawable();
            centerBackground.setShape(GradientDrawable.OVAL);
            centerBackground.setColor(tabbarStyle.centerButtonColor);
            View centerFill = new View(getContext());
            centerFill.setBackground(centerBackground);
            int centerFillDiameter = dp(Math.max(tabbarStyle.centerButtonDiameter - 14, 44));
            button.addView(centerFill, new FrameLayout.LayoutParams(centerFillDiameter, centerFillDiameter, Gravity.CENTER));
        }

        if (!center && selected && !disableIndicator) {
            GradientDrawable selectedBackground = new GradientDrawable();
            selectedBackground.setShape(GradientDrawable.OVAL);
            selectedBackground.setColor(indicatorColor);
            View selectedCircle = new View(getContext());
            selectedCircle.setBackground(selectedBackground);
            button.addView(selectedCircle, new FrameLayout.LayoutParams(dp(58), dp(58), Gravity.CENTER));
        }

        LinearLayout content = new LinearLayout(getContext());
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER);
        content.setPadding(dp(4), dp(4), dp(4), dp(4));
        button.addView(content, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        Drawable currentIcon = selected && item.selectedIcon != null ? item.selectedIcon : item.icon;
        boolean usesSelectedIcon = selected && item.selectedIcon != null;
        boolean template = usesSelectedIcon ? item.selectedIconTemplate : item.iconTemplate;
        int iconWidthDp = usesSelectedIcon ? item.selectedIconWidthDp : item.iconWidthDp;
        int iconHeightDp = usesSelectedIcon ? item.selectedIconHeightDp : item.iconHeightDp;
        boolean labelVisible = center ? showLabel && (currentIcon == null || !icons) : showLabel;
        int itemColor = center ? tabbarStyle.centerButtonIconColor : (selected ? tintColor : inactiveTintColor);
        if (icons && currentIcon != null) {
            Drawable icon = currentIcon.mutate();
            if (template) {
                icon.setTint(itemColor);
            }
            ImageView image = new ImageView(getContext());
            image.setImageDrawable(icon);
            if (template) {
                image.setColorFilter(itemColor);
            } else {
                image.clearColorFilter();
            }
            int imageWidth = dp(Math.max(1, Math.min(SvgIconRenderer.MAX_ICON_SIZE_DP, iconWidthDp)));
            int imageHeight = dp(Math.max(1, Math.min(SvgIconRenderer.MAX_ICON_SIZE_DP, iconHeightDp)));
            LinearLayout.LayoutParams imageParams = new LinearLayout.LayoutParams(imageWidth, imageHeight);
            imageParams.bottomMargin = labelVisible ? dp(2) : 0;
            content.addView(image, imageParams);
        }

        if (labelVisible) {
            TextView label = new TextView(getContext());
            label.setText(item.title);
            label.setTextColor(itemColor);
            label.setTextSize(12);
            label.setTypeface(Typeface.DEFAULT, selected ? Typeface.BOLD : Typeface.NORMAL);
            label.setGravity(Gravity.CENTER);
            label.setSingleLine(true);
            content.addView(label, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(18)));
        }

        if (item.badge != null && !item.badge.isEmpty() && !"0".equals(item.badge)) {
            TextView badge = new TextView(getContext());
            badge.setText(item.badge);
            badge.setTextColor(badgeTextColor);
            badge.setTextSize(11);
            badge.setTypeface(Typeface.DEFAULT_BOLD);
            badge.setGravity(Gravity.CENTER);
            GradientDrawable badgeBackground = new GradientDrawable();
            badgeBackground.setColor(badgeBackgroundColor);
            badgeBackground.setCornerRadius(dp(9));
            badge.setBackground(badgeBackground);
            int badgeWidth = Math.max(dp(18), item.badge.length() * dp(7) + dp(10));
            FrameLayout.LayoutParams badgeParams = new FrameLayout.LayoutParams(badgeWidth, dp(18), Gravity.TOP | Gravity.CENTER_HORIZONTAL);
            badgeParams.topMargin = center ? 0 : dp(4);
            badge.setTranslationX(center ? dp(18) : dp(16));
            button.addView(badge, badgeParams);
        }

        button.setContentDescription(item.title == null || item.title.isEmpty() ? item.id : item.title);
        return button;
    }

    private Drawable iconFrom(JSONObject descriptor) {
        if (descriptor == null) {
            return null;
        }
        String svg = svgFrom(descriptor);
        if (svg != null && !svg.isEmpty()) {
            return SvgIconRenderer.render(getContext().getResources(), svg, iconWidthDp(descriptor), iconHeightDp(descriptor));
        }
        JSONObject android = descriptor.optJSONObject("android");
        String resource = android == null ? null : android.optString("resource", null);
        if (resource == null || resource.isEmpty()) {
            resource = android == null ? null : android.optString("image", null);
        }
        if (resource == null || resource.isEmpty()) {
            resource = descriptor.optString("src", null);
        }
        String inlineSvg = inlineSvgFrom(resource);
        if (inlineSvg != null) {
            return SvgIconRenderer.render(getContext().getResources(), inlineSvg, iconWidthDp(descriptor), iconHeightDp(descriptor));
        }
        if (resource == null || resource.isEmpty()) {
            return null;
        }
        Resources resources = getContext().getResources();
        int id = resources.getIdentifier(resource, "drawable", getContext().getPackageName());
        if (id == 0) {
            id = resources.getIdentifier(resource, "mipmap", getContext().getPackageName());
        }
        if (id == 0) {
            id = resources.getIdentifier(resource, "drawable", "android");
        }
        return id == 0 ? null : AppCompatResources.getDrawable(getContext(), id);
    }

    private String svgFrom(JSONObject descriptor) {
        JSONObject android = descriptor.optJSONObject("android");
        if (android != null) {
            String svg = android.optString("svg", null);
            if (svg != null && !svg.isEmpty()) {
                return svg;
            }
        }
        String svg = descriptor.optString("svg", null);
        if (svg != null && !svg.isEmpty()) {
            return svg;
        }
        return inlineSvgFrom(descriptor.optString("src", null));
    }

    private String inlineSvgFrom(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.length() > MAX_INLINE_IMAGE_CHARACTERS) {
            return null;
        }
        if (trimmed.startsWith("<svg")) {
            return SvgIconRenderer.isSafeSvg(trimmed) ? trimmed : null;
        }
        String lower = trimmed.toLowerCase(Locale.ROOT);
        if (!lower.startsWith("data:image/svg+xml")) {
            return null;
        }
        int comma = trimmed.indexOf(',');
        if (comma < 0) {
            return null;
        }
        String meta = trimmed.substring(0, comma);
        String payload = trimmed.substring(comma + 1);
        try {
            if (meta.contains(";base64")) {
                byte[] decoded = android.util.Base64.decode(payload, android.util.Base64.DEFAULT);
                if (decoded.length > SvgIconRenderer.MAX_SVG_CHARACTERS) {
                    return null;
                }
                String svg = new String(decoded, StandardCharsets.UTF_8);
                return SvgIconRenderer.isSafeSvg(svg) ? svg : null;
            }
            // The Charset overload was added in API 33. Keep the Android 11
            // baseline by using the API 1 charset-name overload instead.
            String svg = URLDecoder.decode(payload, StandardCharsets.UTF_8.name());
            return SvgIconRenderer.isSafeSvg(svg) ? svg : null;
        } catch (Exception ignored) {
            return null;
        }
    }

    private int iconWidthDp(JSONObject descriptor) {
        return iconDimensionDp(descriptor, "width", 24);
    }

    private int iconHeightDp(JSONObject descriptor) {
        return iconDimensionDp(descriptor, "height", iconWidthDp(descriptor));
    }

    private int iconDimensionDp(JSONObject descriptor, String key, int fallback) {
        if (descriptor == null) {
            return fallback;
        }
        double value = descriptor.optDouble(key, fallback);
        if (!Double.isFinite(value) || value <= 0d) {
            return fallback;
        }
        return (int) Math.max(1, Math.min(SvgIconRenderer.MAX_ICON_SIZE_DP, Math.round(value)));
    }

    private boolean iconTemplate(JSONObject descriptor) {
        return descriptor == null || descriptor.optBoolean("template", true);
    }

    private void applyToolbarColors(Toolbar nativeToolbar, JSObject colors) {
        boolean dynamic = Boolean.TRUE.equals(colors.getBool("dynamic"));
        int tintFallback = dynamic ? dynamicColor("system_accent1_600", DEFAULT_TINT_COLOR) : DEFAULT_TINT_COLOR;
        int backgroundFallback = dynamic
            ? withAlpha(dynamicColor(isNightMode() ? "system_neutral1_900" : "system_neutral1_50", Color.WHITE), 235)
            : Color.argb(225, 255, 255, 255);
        int foregroundFallback = dynamic
            ? dynamicColor(isNightMode() ? "system_neutral1_50" : "system_neutral1_900", Color.rgb(20, 24, 32))
            : Color.rgb(20, 24, 32);
        int tint = parseColor(colors.getString("tint", null), tintFallback);
        int background = parseColor(colors.getString("background", null), backgroundFallback);
        navbarBackgroundColor = background;
        int foreground = parseColor(colors.getString("foreground", null), foregroundFallback);
        nativeToolbar.setTitleTextColor(foreground);
        nativeToolbar.setSubtitleTextColor(withAlpha(foreground, 190));
        Drawable navigationIcon = nativeToolbar.getNavigationIcon();
        if (navigationIcon != null) {
            Drawable tintedIcon = navigationIcon.mutate();
            tintedIcon.setTint(tint);
            nativeToolbar.setNavigationIcon(tintedIcon);
        }
        nativeToolbar.setBackgroundColor(Color.TRANSPARENT);
        applyChromeBackground(navbarContainer, navbarGlassBackdrop, navbarGlassSurface, background, navbarGlassOptions, 0f);
        for (int index = 0; index < nativeToolbar.getMenu().size(); index++) {
            MenuItem menuItem = nativeToolbar.getMenu().getItem(index);
            Drawable icon = menuItem.getIcon();
            if (icon != null && !Boolean.FALSE.equals(menuActionTemplates.get(menuItem.getItemId()))) {
                // Drawable.mutate() returns a *copy* whenever the drawable shares a
                // ConstantState (everything AppCompatResources hands out does), so
                // upstream's `icon.mutate().setTint(tint)` tinted a throwaway and the
                // menu icons stayed untinted. The tinted drawable has to be set back.
                Drawable tintedIcon = icon.mutate();
                tintedIcon.setTint(tint);
                menuItem.setIcon(tintedIcon);
            }
        }
    }

    private TabbarStyle makeTabbarStyle(JSObject rawStyle) {
        String requestedShape = rawStyle.getString("shape", TabbarStyle.SHAPE_FLOATING);
        boolean curve = TabbarStyle.SHAPE_CURVE.equalsIgnoreCase(requestedShape);
        int centerButtonDiameter = Math.max(styleDimension(rawStyle, "centerButtonDiameter", 56), 44);
        int height = Math.max(styleDimension(rawStyle, "height", curve ? 76 : DEFAULT_TABBAR_DP), 44);
        int centerButtonLift = Math.max(styleDimension(rawStyle, "centerButtonLift", centerButtonDiameter / 2), 0);
        int bottomGap = Math.max(styleDimension(rawStyle, "bottomGap", curve ? 0 : 10), 0);
        int horizontalMargin = Math.max(styleDimension(rawStyle, "horizontalMargin", curve ? 0 : 24), 0);
        int maxWidth = Math.max(styleDimension(rawStyle, "maxWidth", curve ? 0 : 430), 0);
        int cornerRadius = Math.max(styleDimension(rawStyle, "cornerRadius", curve ? 0 : height / 2), 0);
        int centerButtonColor = parseColor(rawStyle.getString("centerButtonColor", null), tintColor);
        int centerButtonIconColor = parseColor(rawStyle.getString("centerButtonIconColor", null), Color.WHITE);
        return new TabbarStyle(
            curve ? TabbarStyle.SHAPE_CURVE : TabbarStyle.SHAPE_FLOATING,
            height,
            horizontalMargin,
            maxWidth,
            bottomGap,
            cornerRadius,
            rawStyle.getString("centerItemId", null),
            centerButtonDiameter,
            centerButtonLift,
            centerButtonColor,
            centerButtonIconColor
        );
    }

    private int styleDimension(JSObject rawStyle, String key, int fallback) {
        if (rawStyle == null || !rawStyle.has(key)) {
            return fallback;
        }
        double value = rawStyle.optDouble(key, fallback);
        if (!Double.isFinite(value)) {
            return fallback;
        }
        return (int) Math.round(Math.max(0d, Math.min(MAX_LAYOUT_DP, value)));
    }

    private int centerTabIndex() {
        if (!tabbarStyle.isCurve() || tabItems.isEmpty()) {
            return -1;
        }
        if (tabbarStyle.centerItemId != null) {
            for (int index = 0; index < tabItems.size(); index++) {
                if (tabbarStyle.centerItemId.equals(tabItems.get(index).id)) {
                    return index;
                }
            }
        }
        return tabItems.size() / 2;
    }

    private void applyTabbarColors(JSONObject options, JSObject colors) {
        boolean dynamic = Boolean.TRUE.equals(colors.getBool("dynamic"));
        int tintFallback = dynamic ? dynamicColor("system_accent1_600", DEFAULT_TINT_COLOR) : DEFAULT_TINT_COLOR;
        int inactiveFallback = dynamic
            ? dynamicColor("system_neutral2_600", DEFAULT_INACTIVE_TINT_COLOR)
            : DEFAULT_INACTIVE_TINT_COLOR;
        int backgroundFallback = dynamic
            ? dynamicColor(isNightMode() ? "system_neutral1_900" : "system_neutral1_50", DEFAULT_TABBAR_BACKGROUND_COLOR)
            : DEFAULT_TABBAR_BACKGROUND_COLOR;
        tintColor = parseColor(colors.getString("tint", null), tintFallback);
        inactiveTintColor = parseColor(colors.getString("inactiveTint", null), inactiveFallback);
        tabbarBackgroundColor = parseColor(colors.getString("background", null), backgroundFallback);
        applyTabbarBackground();
    }

    private void applyTabbarBackground() {
        applyTabbarBackground(centerTabIndex());
    }

    private void applyTabbarBackground(int centerIndex) {
        if (tabbar == null) {
            return;
        }
        int drawColor = resolvedTabbarSurfaceColor();
        if (tabbarBackdrop != null) {
            tabbarBackdrop.setBackgroundColor(drawColor);
        }

        GlassOptions resolvedGlassOptions = tabbarGlassOptions == null ? GlassOptions.defaults() : tabbarGlassOptions;
        if (resolvedGlassOptions.isLiquidGlass()) {
            if (tabbarContainer != null) {
                tabbarContainer.setBackgroundColor(Color.TRANSPARENT);
            }
            hideGlassBackground(null, tabbarGlassSurface);
            if (tabbarGlassBackdrop != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Bridge bridge = getBridge();
                View webView = bridge == null ? null : bridge.getWebView();
                tabbarGlassBackdrop.setClipPathProvider((width, height) -> tabbar.backgroundPath(width, height));
                tabbarGlassBackdrop.configure(webView, dp((double) resolvedGlassOptions.blurRadiusDp), drawColor);
                tabbarGlassBackdrop.setVisibility(View.VISIBLE);
            } else if (tabbarGlassBackdrop != null) {
                tabbarGlassBackdrop.setClipPathProvider((width, height) -> tabbar.backgroundPath(width, height));
                tabbarGlassBackdrop.clearEffect();
                tabbarGlassBackdrop.setVisibility(View.GONE);
            }
        } else {
            hideGlassBackground(tabbarGlassBackdrop, tabbarGlassSurface);
            if (tabbarGlassBackdrop != null) {
                tabbarGlassBackdrop.setClipPathProvider(null);
            }
            if (tabbarContainer != null) {
                tabbarContainer.setBackgroundColor(Color.TRANSPARENT);
            }
        }

        tabbar.setTabbarStyle(tabbarStyle, drawColor, centerIndex);
    }

    private int resolvedTabbarSurfaceColor() {
        GlassOptions resolvedGlassOptions = tabbarGlassOptions == null ? GlassOptions.defaults() : tabbarGlassOptions;
        return resolvedGlassOptions.isLiquidGlass() ? glassSurfaceColor(tabbarBackgroundColor, resolvedGlassOptions) : tabbarBackgroundColor;
    }

    private void reapplyVisibleChromeBackgrounds() {
        if (navbarContainer != null && navbarContainer.getVisibility() == View.VISIBLE) {
            applyChromeBackground(navbarContainer, navbarGlassBackdrop, navbarGlassSurface, navbarBackgroundColor, navbarGlassOptions, 0f);
        }
        if (tabbarContainer != null && tabbarContainer.getVisibility() == View.VISIBLE) {
            applyTabbarBackground();
        }
    }

    private void applyChromeBackground(
        ViewGroup container,
        GlassBackdropView backdrop,
        View surface,
        int background,
        GlassOptions glassOptions,
        float cornerRadius
    ) {
        if (container == null) {
            return;
        }
        GlassOptions resolvedGlassOptions = glassOptions == null ? GlassOptions.defaults() : glassOptions;
        if (!resolvedGlassOptions.isLiquidGlass()) {
            hideGlassBackground(backdrop, surface);
            container.setBackground(chromeBackgroundDrawable(background, cornerRadius));
            return;
        }

        container.setBackgroundColor(Color.TRANSPARENT);
        int surfaceColor = glassSurfaceColor(background, resolvedGlassOptions);
        if (surface != null) {
            surface.setBackground(chromeBackgroundDrawable(surfaceColor, cornerRadius));
            surface.setVisibility(View.VISIBLE);
        }
        if (backdrop != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Bridge bridge = getBridge();
            View webView = bridge == null ? null : bridge.getWebView();
            backdrop.setClipPathProvider(null);
            backdrop.configure(webView, dp((double) resolvedGlassOptions.blurRadiusDp), surfaceColor);
            backdrop.setVisibility(View.VISIBLE);
        } else if (backdrop != null) {
            backdrop.clearEffect();
            backdrop.setVisibility(View.GONE);
        }
    }

    private void hideGlassBackground(GlassBackdropView backdrop, View surface) {
        if (backdrop != null) {
            backdrop.clearEffect();
            backdrop.setVisibility(View.GONE);
        }
        if (surface != null) {
            surface.setBackground(null);
            surface.setVisibility(View.GONE);
        }
    }

    private Drawable chromeBackgroundDrawable(int color, float cornerRadius) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        if (cornerRadius > 0f) {
            drawable.setCornerRadius(cornerRadius);
        }
        return drawable;
    }

    private int glassSurfaceColor(int background, GlassOptions glassOptions) {
        return withAlpha(background, Math.round(Color.alpha(background) * (float) glassOptions.surfaceAlpha));
    }

    private int parseColor(String value, int fallback) {
        if (value == null || value.isEmpty()) {
            return fallback;
        }
        if ("android:dynamicPrimary".equals(value) || "system:primary".equals(value)) {
            return dynamicColor("system_accent1_600", fallback);
        }
        if ("android:dynamicSurface".equals(value) || "system:surface".equals(value)) {
            return dynamicColor(isNightMode() ? "system_neutral1_900" : "system_neutral1_50", fallback);
        }
        try {
            return Color.parseColor(value);
        } catch (IllegalArgumentException ignored) {
            return fallback;
        }
    }

    private Integer parseColorOrNull(String value) {
        if (value == null || value.isEmpty()) {
            return null;
        }
        if ("android:dynamicPrimary".equals(value) || "system:primary".equals(value)) {
            return dynamicColor("system_accent1_600", tintColor);
        }
        if ("android:dynamicSurface".equals(value) || "system:surface".equals(value)) {
            return dynamicColor(isNightMode() ? "system_neutral1_900" : "system_neutral1_50", Color.WHITE);
        }
        try {
            return Color.parseColor(value);
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private Integer colorOption(JSONObject options, JSONObject colors, String directKey, String colorKey, Integer fallback) {
        Integer direct = parseColorOrNull(options == null ? null : options.optString(directKey, null));
        if (direct != null) {
            return direct;
        }
        Integer nested = parseColorOrNull(colors == null ? null : colors.optString(colorKey, null));
        return nested == null ? fallback : nested;
    }

    private int dynamicColor(String name, int fallback) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return fallback;
        }
        int id = Resources.getSystem().getIdentifier(name, "color", "android");
        if (id == 0) {
            return fallback;
        }
        return getContext().getColor(id);
    }

    private int withAlpha(int color, int alpha) {
        return Color.argb(Math.max(0, Math.min(255, alpha)), Color.red(color), Color.green(color), Color.blue(color));
    }

    private Drawable tabRippleBackground() {
        GradientDrawable mask = new GradientDrawable();
        mask.setShape(GradientDrawable.OVAL);
        mask.setColor(Color.WHITE);
        return new RippleDrawable(ColorStateList.valueOf(rippleColor), null, mask);
    }

    private boolean isNightMode() {
        int mode = getContext().getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
        return mode == Configuration.UI_MODE_NIGHT_YES;
    }

    private void fillContainer(View view) {
        if (view != null) {
            view.setLayoutParams(new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        }
    }

    private void layoutChrome() {
        FrameLayout root = contentRoot();
        if (root == null) {
            return;
        }
        Insets systemInsets = currentSystemInsets();
        int status = systemInsets.top;
        int bottom = systemInsets.bottom;
        int navbarHeight = navbarVisible ? status + dp(DEFAULT_NAVBAR_DP) : 0;
        int tabbarHeight = dp(tabbarStyle.totalHeight());
        int tabbarBottomMargin = tabbarVisible ? bottom + dp(tabbarStyle.bottomGap) : bottom;

        if (navbarContainer != null) {
            FrameLayout.LayoutParams containerParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                navbarHeight,
                Gravity.TOP
            );
            navbarContainer.setLayoutParams(containerParams);
            FrameLayout.LayoutParams toolbarParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(DEFAULT_NAVBAR_DP),
                Gravity.TOP
            );
            toolbarParams.topMargin = status;
            toolbarParams.leftMargin = systemInsets.left;
            toolbarParams.rightMargin = systemInsets.right;
            toolbar.setLayoutParams(toolbarParams);
            fillContainer(navbarGlassBackdrop);
            fillContainer(navbarGlassSurface);
        }

        if (tabbarBackdrop != null) {
            int backdropHeight = tabbarVisible ? bottom + dp(tabbarStyle.bottomGap) : 0;
            FrameLayout.LayoutParams backdropParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                backdropHeight,
                Gravity.BOTTOM
            );
            tabbarBackdrop.setLayoutParams(backdropParams);
            tabbarBackdrop.setBackgroundColor(resolvedTabbarSurfaceColor());
            tabbarBackdrop.setVisibility(tabbarVisible && backdropHeight > 0 ? View.VISIBLE : View.GONE);
        }
        if (tabbarContainer != null) {
            int rootWidth = root.getWidth() > 0 ? root.getWidth() : Resources.getSystem().getDisplayMetrics().widthPixels;
            int horizontalMargin = dp(tabbarStyle.horizontalMargin);
            int safeLeft = Math.max(0, systemInsets.left);
            int safeRight = Math.max(0, systemInsets.right);
            int availableWidth = Math.max(0, rootWidth - safeLeft - safeRight - horizontalMargin * 2);
            int maxWidth = tabbarStyle.maxWidth > 0 ? dp(tabbarStyle.maxWidth) : availableWidth;
            boolean hasDetachedTrailing = !tabbarStyle.isCurve() && hasDetachedTrailingItem();
            int trailingExtra = hasDetachedTrailing ? dp(tabbarStyle.height) + dp(DETACHED_TRAILING_GAP_DP) : 0;
            int tabbarWidth = Math.min(availableWidth, maxWidth + trailingExtra);
            FrameLayout.LayoutParams tabbarContainerParams = new FrameLayout.LayoutParams(
                tabbarWidth,
                tabbarHeight,
                Gravity.BOTTOM | Gravity.LEFT
            );
            tabbarContainerParams.bottomMargin = tabbarBottomMargin;
            tabbarContainerParams.leftMargin = safeLeft + horizontalMargin + Math.max(0, (availableWidth - tabbarWidth) / 2);
            tabbarContainer.setLayoutParams(tabbarContainerParams);
            fillContainer(tabbarGlassBackdrop);
            fillContainer(tabbarGlassSurface);
        }

        if (tabbar != null) {
            FrameLayout.LayoutParams tabbarParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            );
            tabbar.setLayoutParams(tabbarParams);
            tabbar.setPadding(0, 0, 0, 0);
            applyTabbarBackground();
        }

        bringChromeToFront();
    }

    private void bringChromeToFront() {
        if (navbarContainer != null) {
            navbarContainer.bringToFront();
        }
        if (tabbarBackdrop != null) {
            tabbarBackdrop.bringToFront();
        }
        if (tabbar != null) {
            tabbar.bringToFront();
        }
        if (tabbarContainer != null) {
            tabbarContainer.bringToFront();
        }
    }

    private void updateInsetsAndNotify() {
        layoutChrome();
        JSObject insets = currentInsets();
        syncCssInsets(insets);
        JSObject event = new JSObject();
        event.put("insets", insets);
        emitEvent("safeAreaChanged", event);
    }

    private void syncCssInsets(JSObject insets) {
        Bridge bridge = getBridge();
        View webView = bridge == null ? null : bridge.getWebView();
        if (!(webView instanceof android.webkit.WebView)) {
            return;
        }
        StringBuilder script = new StringBuilder("(() => {const root=document.documentElement;");
        if ("none".equals(contentInsetMode)) {
            for (String variable : CSS_INSET_VARIABLES) {
                script.append("root.style.removeProperty(").append(JSONObject.quote(variable)).append(");");
            }
        } else {
            String[] keys = { "top", "right", "bottom", "left", "navbarHeight", "tabbarHeight" };
            for (int index = 0; index < CSS_INSET_VARIABLES.length; index++) {
                script
                    .append("root.style.setProperty(")
                    .append(JSONObject.quote(CSS_INSET_VARIABLES[index]))
                    .append(",")
                    .append(JSONObject.quote(insets.optInt(keys[index], 0) + "px"))
                    .append(");");
            }
        }
        script.append("})();");
        ((android.webkit.WebView) webView).evaluateJavascript(script.toString(), null);
    }

    private void emitEvent(String eventName, JSObject event) {
        JSObject detail = event == null ? new JSObject() : event;
        notifyListeners(eventName, detail);
        Bridge bridge = getBridge();
        View webView = bridge == null ? null : bridge.getWebView();
        if (!(webView instanceof android.webkit.WebView)) {
            return;
        }
        String script =
            "window.dispatchEvent(new CustomEvent(" +
            JSONObject.quote("capNativeNavigation:" + eventName) +
            ",{detail:" +
            detail.toString() +
            "}));";
        ((android.webkit.WebView) webView).evaluateJavascript(script, null);
    }

    private JSObject currentInsets() {
        /*
         * Insets describe how much of the *WebView viewport* the native bars cover.
         * A Capacitor 7 app can set `android.adjustMarginsForEdgeToEdge` to
         * "auto"/"force", and CapacitorWebView.edgeToEdgeHandler() then margins the
         * WebView by the system bar insets. Measuring the chrome against the
         * WebView's real position keeps a single code path correct whether or not
         * that margining is active; when the WebView is not offset — the default —
         * these expressions reduce to the plain bar heights.
         */
        Insets systemInsets = currentSystemInsets();
        Rect webViewGaps = webViewGapsInRoot();
        int topPx = navbarVisible ? Math.max(0, systemInsets.top + dp(DEFAULT_NAVBAR_DP) - webViewGaps.top) : 0;
        int bottomPx = tabbarVisible
            ? Math.max(0, systemInsets.bottom + dp(tabbarStyle.totalHeight()) + dp(tabbarStyle.bottomGap) - webViewGaps.bottom)
            : 0;
        int leftPx = Math.max(0, systemInsets.left - webViewGaps.left);
        int rightPx = Math.max(0, systemInsets.right - webViewGaps.right);
        float density = displayDensity();
        int top = NativeUnitConverter.physicalPxToCssPx(topPx, density);
        int right = NativeUnitConverter.physicalPxToCssPx(rightPx, density);
        int bottom = NativeUnitConverter.physicalPxToCssPx(bottomPx, density);
        int left = NativeUnitConverter.physicalPxToCssPx(leftPx, density);
        JSObject insets = new JSObject();
        insets.put("top", top);
        insets.put("right", right);
        insets.put("bottom", bottom);
        insets.put("left", left);
        insets.put("navbarHeight", top);
        insets.put("tabbarHeight", bottom);
        return insets;
    }

    /** Insets the host already applies between the WebView and content root. */
    private Rect webViewGapsInRoot() {
        FrameLayout root = contentRoot();
        Bridge bridge = getBridge();
        View webView = bridge == null ? null : bridge.getWebView();
        if (root == null || webView == null || webView.getWidth() <= 0 || webView.getHeight() <= 0) {
            return new Rect();
        }
        RectF webViewFrame = webViewFrameInRoot(webView, root);
        return new Rect(
            Math.max(0, Math.round(webViewFrame.left)),
            Math.max(0, Math.round(webViewFrame.top)),
            Math.max(0, root.getWidth() - Math.round(webViewFrame.right)),
            Math.max(0, root.getHeight() - Math.round(webViewFrame.bottom))
        );
    }

    private JSObject insetsResult() {
        JSObject result = new JSObject();
        result.put("insets", currentInsets());
        return result;
    }

    private JSObject transitionEvent(String id, String direction, int duration) {
        JSObject event = new JSObject();
        event.put("id", id);
        event.put("direction", direction);
        event.put("duration", duration);
        return event;
    }

    private boolean isStationaryTransition(String direction) {
        return "tab".equals(direction) || "root".equals(direction) || "none".equals(direction);
    }

    private void prepareTransitionRootBackground(TransitionSession session, FrameLayout root, int surfaceColor) {
        session.rootBackground = root.getBackground();
        session.rootBackgroundCaptured = true;
        if (needsTransitionSurface(session.rootBackground)) {
            root.setBackgroundColor(surfaceColor);
        }
    }

    private void restoreTransitionRootBackground(TransitionSession session) {
        if (session == null || !session.rootBackgroundCaptured) {
            return;
        }
        FrameLayout root = contentRoot();
        if (root != null) {
            root.setBackground(session.rootBackground);
        }
        session.rootBackground = null;
        session.rootBackgroundCaptured = false;
    }

    private boolean needsTransitionSurface(Drawable background) {
        if (background == null) {
            return true;
        }
        if (background instanceof ColorDrawable) {
            return Color.alpha(((ColorDrawable) background).getColor()) < 255;
        }
        return false;
    }

    private int transitionSurfaceColor(View webView) {
        Drawable background = webView.getBackground();
        if (background instanceof ColorDrawable) {
            int color = ((ColorDrawable) background).getColor();
            if (Color.alpha(color) > 0) {
                return withAlpha(color, 255);
            }
        }
        int fallback = isNightMode() ? Color.rgb(18, 18, 18) : Color.WHITE;
        return dynamicColor(isNightMode() ? "system_neutral1_900" : "system_neutral1_50", fallback);
    }

    private FrameLayout contentRoot() {
        Activity activity = getActivity();
        return activity == null ? null : activity.findViewById(android.R.id.content);
    }

    private void observeContentRoot() {
        FrameLayout root = contentRoot();
        if (root == null || root == observedRoot) {
            return;
        }
        if (observedRoot != null) {
            observedRoot.removeOnLayoutChangeListener(rootLayoutListener);
        }
        removeFromParent(insetsObserverView);
        observedRoot = root;
        lastRootWidth = root.getWidth();
        lastRootHeight = root.getHeight();
        root.addOnLayoutChangeListener(rootLayoutListener);
        insetsObserverView = new View(getContext());
        insetsObserverView.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        insetsObserverView.setOnApplyWindowInsetsListener((view, windowInsets) -> {
            Insets updated = windowInsets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            boolean changed = !hasReceivedWindowInsets || !sameInsets(lastSystemInsets, updated);
            hasReceivedWindowInsets = true;
            lastSystemInsets = updated;
            if (changed) {
                scheduleInsetsUpdate(view);
            }
            return windowInsets;
        });
        root.addView(insetsObserverView, new FrameLayout.LayoutParams(0, 0));
        insetsObserverView.requestApplyInsets();
    }

    private void handleRootSizeChanged() {
        updateInsetsAndNotify();
    }

    private void scheduleInsetsUpdate(View view) {
        if (insetsUpdatePending) {
            return;
        }
        insetsUpdatePending = true;
        view.post(() -> {
            insetsUpdatePending = false;
            if (view == insetsObserverView) {
                updateInsetsAndNotify();
            }
        });
    }

    private boolean sameInsets(Insets first, Insets second) {
        return first.left == second.left && first.top == second.top && first.right == second.right && first.bottom == second.bottom;
    }

    private void teardownChrome() {
        // Also short-circuits any relayout already posted from the root listener.
        navbarVisible = false;
        tabbarVisible = false;
        TransitionSession session = activeTransition;
        if (session != null) {
            cleanupTransition(session, false, null);
        }
        if (observedRoot != null) {
            observedRoot.removeOnLayoutChangeListener(rootLayoutListener);
            observedRoot = null;
        }
        if (insetsObserverView != null) {
            insetsObserverView.setOnApplyWindowInsetsListener(null);
            removeFromParent(insetsObserverView);
            insetsObserverView = null;
        }
        hasReceivedWindowInsets = false;
        lastSystemInsets = Insets.NONE;
        insetsUpdatePending = false;
        if (navbarGlassBackdrop != null) {
            navbarGlassBackdrop.clearEffect();
        }
        if (tabbarGlassBackdrop != null) {
            tabbarGlassBackdrop.clearEffect();
            tabbarGlassBackdrop.setClipPathProvider(null);
        }
        removeFromParent(navbarContainer);
        removeFromParent(tabbarContainer);
        removeFromParent(tabbarBackdrop);
        navbarContainer = null;
        tabbarContainer = null;
        tabbarBackdrop = null;
        toolbar = null;
        tabbar = null;
        navbarGlassBackdrop = null;
        navbarGlassSurface = null;
        tabbarGlassBackdrop = null;
        tabbarGlassSurface = null;
        tabItems.clear();
        menuActionIds.clear();
        menuActionTitles.clear();
        menuActionPlacements.clear();
        menuActionTemplates.clear();
    }

    private void removeFromParent(View view) {
        if (view == null) {
            return;
        }
        ViewParent parent = view.getParent();
        if (parent instanceof ViewGroup) {
            ((ViewGroup) parent).removeView(view);
        }
    }

    private void enableEdgeToEdge() {
        Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        Window window = activity.getWindow();
        window.setDecorFitsSystemWindows(false);
    }

    private Insets currentSystemInsets() {
        if (hasReceivedWindowInsets) {
            return lastSystemInsets;
        }
        WindowInsets insets = rootWindowInsets();
        if (insets != null) {
            return insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
        }
        return Insets.of(0, systemDimension("status_bar_height"), 0, systemDimension("navigation_bar_height"));
    }

    private WindowInsets rootWindowInsets() {
        // Upstream dereferenced getActivity() here without a null check, which
        // crashes when a queued call runs after the activity is gone.
        Activity activity = getActivity();
        if (activity == null) {
            return null;
        }
        Window window = activity.getWindow();
        return window == null ? null : window.getDecorView().getRootWindowInsets();
    }

    private int systemDimension(String name) {
        int id = getContext().getResources().getIdentifier(name, "dimen", "android");
        return id == 0 ? 0 : getContext().getResources().getDimensionPixelSize(id);
    }

    private int dp(int value) {
        return Math.round(NativeUnitConverter.dpToPhysicalPx(value, displayDensity()));
    }

    private float dp(double value) {
        return NativeUnitConverter.dpToPhysicalPx(value, displayDensity());
    }

    private float displayDensity() {
        return NativeUnitConverter.normalizedDensity(getContext().getResources().getDisplayMetrics().density);
    }

    private void runOnUiThread(Runnable runnable) {
        Activity activity = getActivity();
        if (activity == null) {
            runnable.run();
            return;
        }
        activity.runOnUiThread(runnable);
    }
}
