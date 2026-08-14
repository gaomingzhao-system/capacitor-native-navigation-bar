/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

package app.nativenavigationbar.capacitor;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.os.Build;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewTreeObserver;
import androidx.annotation.RequiresApi;

/**
 * Redraws a source view (the WebView) behind the native bars and blurs it with
 * a RenderEffect on Android 12+, producing the `liquidGlass` backdrop. Below
 * API 31 the caller falls back to a translucent surface instead.
 */
final class GlassBackdropView extends View {

    interface PathProvider {
        Path path(int width, int height);
    }

    private static final long SOURCE_CONTENT_REFRESH_INTERVAL_MS = 250L;

    private final Paint fallbackPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final int[] sourceLocation = new int[2];
    private final int[] viewLocation = new int[2];
    private final ViewTreeObserver.OnScrollChangedListener sourceScrollListener = this::markDirty;
    private final ViewTreeObserver.OnPreDrawListener sourcePreDrawListener = () -> {
        markDirtyFromSourcePreDraw();
        return true;
    };
    private final View.OnLayoutChangeListener sourceLayoutListener = (
        view,
        left,
        top,
        right,
        bottom,
        oldLeft,
        oldTop,
        oldRight,
        oldBottom
    ) -> markDirty();
    private View source;
    /*
     * A ViewTreeObserver belongs to the view's *current* window: once the source
     * is detached and re-attached it hands out a different instance, so removing
     * listeners via `source.getViewTreeObserver()` at teardown time can silently
     * no-op and leave this view registered on the stale observer. Keep the exact
     * observer the listeners were registered on and unregister from that one.
     */
    private ViewTreeObserver observedTree;
    private boolean sourceObserversRegistered;
    private PathProvider clipPathProvider;
    private int fallbackColor = Color.TRANSPARENT;
    private boolean dirty;
    private boolean redrawPending;
    private long lastSourcePreDrawRefreshMs;

    GlassBackdropView(Context context) {
        super(context);
        setWillNotDraw(false);
    }

    void configure(View source, float blurRadiusPx, int fallbackColor) {
        this.fallbackColor = fallbackColor;
        attachSource(source);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Api31RenderEffects.setBlur(this, blurRadiusPx);
        }
        markDirty();
    }

    void clearEffect() {
        attachSource(null);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Api31RenderEffects.clear(this);
        }
        markDirty();
    }

    void setClipPathProvider(PathProvider clipPathProvider) {
        this.clipPathProvider = clipPathProvider;
        markDirty();
    }

    private void attachSource(View nextSource) {
        if (source == nextSource) {
            registerSourceObservers();
            return;
        }
        unregisterSourceObservers();
        source = nextSource;
        registerSourceObservers();
        markDirty();
    }

    private void registerSourceObservers() {
        if (source == null || sourceObserversRegistered || !isAttachedToWindow()) {
            return;
        }
        source.addOnLayoutChangeListener(sourceLayoutListener);
        ViewTreeObserver observer = source.getViewTreeObserver();
        if (!observer.isAlive()) {
            source.removeOnLayoutChangeListener(sourceLayoutListener);
            return;
        }
        observer.addOnScrollChangedListener(sourceScrollListener);
        observer.addOnPreDrawListener(sourcePreDrawListener);
        observedTree = observer;
        sourceObserversRegistered = true;
    }

    private void unregisterSourceObservers() {
        if (source != null) {
            source.removeOnLayoutChangeListener(sourceLayoutListener);
        }
        if (observedTree != null && observedTree.isAlive()) {
            observedTree.removeOnScrollChangedListener(sourceScrollListener);
            observedTree.removeOnPreDrawListener(sourcePreDrawListener);
        }
        observedTree = null;
        sourceObserversRegistered = false;
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        registerSourceObservers();
    }

    @Override
    protected void onDetachedFromWindow() {
        unregisterSourceObservers();
        redrawPending = false;
        super.onDetachedFromWindow();
    }

    private void markDirty() {
        dirty = true;
        scheduleRedrawIfVisible();
    }

    private void markDirtyFromSourcePreDraw() {
        dirty = true;
        // SystemClock.uptimeMillis() is monotonic; System.currentTimeMillis() can
        // jump backwards on a clock change and stall the refresh throttle.
        long now = SystemClock.uptimeMillis();
        if (now - lastSourcePreDrawRefreshMs < SOURCE_CONTENT_REFRESH_INTERVAL_MS) {
            return;
        }
        lastSourcePreDrawRefreshMs = now;
        scheduleRedrawIfVisible();
    }

    private void scheduleRedrawIfVisible() {
        if (redrawPending || getVisibility() != View.VISIBLE || !isShown()) {
            return;
        }
        redrawPending = true;
        postInvalidateOnAnimation();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        Path clipPath = clipPathProvider == null ? null : clipPathProvider.path(getWidth(), getHeight());
        if (clipPath == null) {
            drawSource(canvas);
        } else {
            int save = canvas.save();
            canvas.clipPath(clipPath);
            drawSource(canvas);
            canvas.restoreToCount(save);
        }

        dirty = false;
        redrawPending = false;
    }

    private void drawSource(Canvas canvas) {
        View currentSource = source;
        if (currentSource == null || currentSource.getWidth() <= 0 || currentSource.getHeight() <= 0) {
            fallbackPaint.setColor(fallbackColor);
            canvas.drawRect(0, 0, getWidth(), getHeight(), fallbackPaint);
            return;
        }
        currentSource.getLocationOnScreen(sourceLocation);
        getLocationOnScreen(viewLocation);
        canvas.save();
        canvas.translate(sourceLocation[0] - viewLocation[0], sourceLocation[1] - viewLocation[1]);
        currentSource.draw(canvas);
        canvas.restore();
    }

    @Override
    protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        super.onSizeChanged(width, height, oldWidth, oldHeight);
        if (width != oldWidth || height != oldHeight) {
            markDirty();
        }
    }

    @Override
    protected void onVisibilityChanged(View changedView, int visibility) {
        super.onVisibilityChanged(changedView, visibility);
        if (visibility != View.VISIBLE) {
            redrawPending = false;
            return;
        }
        if (dirty) {
            scheduleRedrawIfVisible();
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private static final class Api31RenderEffects {

        static void setBlur(View view, float blurRadiusPx) {
            if (blurRadiusPx <= 0f) {
                view.setRenderEffect(null);
                return;
            }
            view.setRenderEffect(
                android.graphics.RenderEffect.createBlurEffect(
                    blurRadiusPx,
                    blurRadiusPx,
                    android.graphics.Shader.TileMode.CLAMP
                )
            );
        }

        static void clear(View view) {
            view.setRenderEffect(null);
        }
    }
}
