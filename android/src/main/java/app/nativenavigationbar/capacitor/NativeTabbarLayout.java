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
import android.graphics.RectF;
import android.view.View;
import android.widget.FrameLayout;

/**
 * Draws the floating capsule / curved bar background and lays the tab buttons
 * out around the optional center action or detached trailing action.
 */
final class NativeTabbarLayout extends FrameLayout {

    static final String TAG_DETACHED_TRAILING = "detachedTrailing";
    private static final int DETACHED_TRAILING_GAP_DP = 10;
    private static final int DEFAULT_TABBAR_BACKGROUND_COLOR = Color.WHITE;

    private final Paint backgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private TabbarStyle style = TabbarStyle.defaults(Color.rgb(0, 122, 255));
    private int backgroundColor = DEFAULT_TABBAR_BACKGROUND_COLOR;
    private int centerIndex = -1;

    NativeTabbarLayout(Context context) {
        super(context);
        setWillNotDraw(false);
    }

    void setTabbarStyle(TabbarStyle style, int backgroundColor, int centerIndex) {
        this.style = style;
        this.backgroundColor = backgroundColor;
        this.centerIndex = centerIndex;
        requestLayout();
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        backgroundPaint.setColor(backgroundColor);
        canvas.drawPath(backgroundPath(getWidth(), getHeight()), backgroundPaint);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int width = MeasureSpec.getSize(widthMeasureSpec);
        int height = MeasureSpec.getSize(heightMeasureSpec);
        if (hasCenterButton()) {
            int barHeight = dp(style.height);
            int barTop = dp(style.barTop());
            int centerGap = Math.min(dp(style.centerButtonDiameter + 4), Math.round(width * 0.34f));
            int leftWidth = Math.max(0, Math.round(width / 2f - centerGap / 2f));
            int rightX = Math.min(width, Math.round(width / 2f + centerGap / 2f));
            measureRange(0, centerIndex, leftWidth, barHeight);
            measureChildExact(getChildAt(centerIndex), dp(style.centerButtonDiameter), dp(style.centerButtonDiameter));
            measureRange(centerIndex + 1, getChildCount(), width - rightX, barHeight);
            setMeasuredDimension(width, Math.max(height, barTop + barHeight));
            return;
        }

        int trailingIndex = detachedTrailingIndex();
        if (trailingIndex >= 0) {
            int trailingDiameter = dp(style.height);
            int capsuleWidth = Math.max(0, width - trailingDiameter - dp(DETACHED_TRAILING_GAP_DP));
            measureRange(0, trailingIndex, capsuleWidth, height);
            measureChildExact(getChildAt(trailingIndex), trailingDiameter, trailingDiameter);
            measureRange(trailingIndex + 1, getChildCount(), 0, height);
            setMeasuredDimension(width, height);
            return;
        }

        int count = Math.max(getChildCount(), 1);
        int childWidth = width / count;
        for (int index = 0; index < getChildCount(); index++) {
            measureChildExact(getChildAt(index), childWidth, height);
        }
        setMeasuredDimension(width, height);
    }

    @Override
    protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        int width = right - left;
        int height = bottom - top;
        if (hasCenterButton()) {
            int barTop = dp(style.barTop());
            int barHeight = dp(style.height);
            int buttonDiameter = dp(style.centerButtonDiameter);
            int centerGap = Math.min(dp(style.centerButtonDiameter + 4), Math.round(width * 0.34f));
            int leftWidth = Math.max(0, Math.round(width / 2f - centerGap / 2f));
            int rightX = Math.min(width, Math.round(width / 2f + centerGap / 2f));
            View center = getChildAt(centerIndex);
            int centerTop = Math.max(0, barTop - dp(style.centerButtonLift));
            center.layout((width - buttonDiameter) / 2, centerTop, (width + buttonDiameter) / 2, centerTop + buttonDiameter);
            layoutRange(0, centerIndex, 0, barTop, leftWidth, barHeight);
            layoutRange(centerIndex + 1, getChildCount(), rightX, barTop, width - rightX, barHeight);
            return;
        }

        int trailingIndex = detachedTrailingIndex();
        if (trailingIndex >= 0) {
            int trailingDiameter = dp(style.height);
            int capsuleWidth = Math.max(0, width - trailingDiameter - dp(DETACHED_TRAILING_GAP_DP));
            View trailing = getChildAt(trailingIndex);
            int trailingTop = Math.max(0, (height - trailingDiameter) / 2);
            trailing.layout(width - trailingDiameter, trailingTop, width, trailingTop + trailingDiameter);
            layoutRange(0, trailingIndex, 0, 0, capsuleWidth, height);
            return;
        }

        layoutRange(0, getChildCount(), 0, 0, width, height);
    }

    private boolean hasCenterButton() {
        return style.isCurve() && centerIndex >= 0 && centerIndex < getChildCount();
    }

    private int detachedTrailingIndex() {
        if (style.isCurve()) {
            return -1;
        }
        for (int index = 0; index < getChildCount(); index++) {
            if (TAG_DETACHED_TRAILING.equals(getChildAt(index).getTag())) {
                return index;
            }
        }
        return -1;
    }

    private int capsuleWidth(int width) {
        int trailingIndex = detachedTrailingIndex();
        if (trailingIndex < 0) {
            return width;
        }
        return Math.max(0, width - dp(style.height) - dp(DETACHED_TRAILING_GAP_DP));
    }

    private void measureRange(int start, int end, int width, int height) {
        int count = Math.max(0, end - start);
        if (count == 0) {
            return;
        }
        int childWidth = Math.max(0, width / count);
        for (int index = start; index < end; index++) {
            measureChildExact(getChildAt(index), childWidth, height);
        }
    }

    private void layoutRange(int start, int end, int left, int top, int width, int height) {
        int count = Math.max(0, end - start);
        if (count == 0) {
            return;
        }
        int childWidth = Math.max(0, width / count);
        for (int index = start; index < end; index++) {
            int childLeft = left + (index - start) * childWidth;
            getChildAt(index).layout(childLeft, top, childLeft + childWidth, top + height);
        }
    }

    private void measureChildExact(View child, int width, int height) {
        child.measure(
            MeasureSpec.makeMeasureSpec(Math.max(0, width), MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(Math.max(0, height), MeasureSpec.EXACTLY)
        );
    }

    Path backgroundPath(int width, int height) {
        Path path = new Path();
        if (!style.isCurve()) {
            float radius = dp(style.cornerRadius);
            int capsuleWidth = capsuleWidth(width);
            path.addRoundRect(new RectF(0, 0, capsuleWidth, height), radius, radius, Path.Direction.CW);
            int trailingIndex = detachedTrailingIndex();
            if (trailingIndex >= 0) {
                float diameter = dp(style.height);
                float left = width - diameter;
                float top = (height - diameter) / 2f;
                path.addRoundRect(
                    new RectF(left, top, left + diameter, top + diameter),
                    diameter / 2f,
                    diameter / 2f,
                    Path.Direction.CW
                );
            }
            return path;
        }
        float barTop = dp(style.barTop());
        float barHeight = dp(style.height);
        float cornerRadius = Math.min(dp(style.cornerRadius), barHeight / 2f);
        float centerX = width / 2f;
        float centerRadius = dp(style.centerButtonDiameter) / 2f;
        float centerTop = Math.max(0f, barTop - dp(style.centerButtonLift));
        float centerY = centerTop + centerRadius;
        float dyToBarTop = barTop - centerY;
        float shoulderWidth = (float) Math.sqrt(Math.max(0f, centerRadius * centerRadius - dyToBarTop * dyToBarTop));
        float leftShoulder = Math.max(cornerRadius, centerX - shoulderWidth);
        RectF barRect = new RectF(0, barTop, width, barTop + barHeight);
        RectF centerRect = new RectF(centerX - centerRadius, centerY - centerRadius, centerX + centerRadius, centerY + centerRadius);
        float startAngle = (float) Math.toDegrees(Math.atan2(dyToBarTop, -shoulderWidth));
        float endAngle = (float) Math.toDegrees(Math.atan2(dyToBarTop, shoulderWidth));
        float sweepAngle = endAngle - startAngle;
        if (sweepAngle <= 0f) {
            sweepAngle += 360f;
        }

        path.moveTo(barRect.left + cornerRadius, barRect.top);
        path.lineTo(leftShoulder, barRect.top);
        if (shoulderWidth > 0f) {
            path.arcTo(centerRect, startAngle, sweepAngle, false);
        }
        path.lineTo(barRect.right - cornerRadius, barRect.top);
        path.quadTo(barRect.right, barRect.top, barRect.right, barRect.top + cornerRadius);
        path.lineTo(barRect.right, barRect.bottom - cornerRadius);
        path.quadTo(barRect.right, barRect.bottom, barRect.right - cornerRadius, barRect.bottom);
        path.lineTo(barRect.left + cornerRadius, barRect.bottom);
        path.quadTo(barRect.left, barRect.bottom, barRect.left, barRect.bottom - cornerRadius);
        path.lineTo(barRect.left, barRect.top + cornerRadius);
        path.quadTo(barRect.left, barRect.top, barRect.left + cornerRadius, barRect.top);
        path.close();
        return path;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

}
