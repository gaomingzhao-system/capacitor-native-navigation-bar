/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Derived from @capgo/capacitor-native-navigation
 * (https://github.com/Cap-go/capacitor-native-navigation), Copyright (c) Capgo.
 * See NOTICE for details. */

package app.nativenavigationbar.capacitor;

import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import androidx.core.graphics.PathParser;
import java.io.StringReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.xmlpull.v1.XmlPullParser;
import org.xmlpull.v1.XmlPullParserFactory;

/**
 * Minimal SVG rasterizer for icon descriptors. Supports the shape subset the
 * public API documents: path, line, polyline, polygon, circle and rect.
 */
final class SvgIconRenderer {

    static final Pattern NUMBER_PATTERN = Pattern.compile("[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?");

    private SvgIconRenderer() {}

    static Drawable render(Resources resources, String svg, int iconSizeDp) {
        int sizePx = Math.max(1, Math.round(iconSizeDp * resources.getDisplayMetrics().density));
        Bitmap bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        RectF viewBox = viewBox(svg, iconSizeDp);
        canvas.scale(sizePx / Math.max(viewBox.width(), 1f), sizePx / Math.max(viewBox.height(), 1f));
        canvas.translate(-viewBox.left, -viewBox.top);

        try {
            XmlPullParser parser = XmlPullParserFactory.newInstance().newPullParser();
            parser.setInput(new StringReader(svg));
            ArrayDeque<SvgStyle> styles = new ArrayDeque<>();
            styles.push(new SvgStyle());
            int event = parser.getEventType();
            while (event != XmlPullParser.END_DOCUMENT) {
                if (event == XmlPullParser.START_TAG) {
                    SvgStyle style = styles.peek().copy();
                    style.apply(parser);
                    styles.push(style);
                    drawElement(canvas, parser, style);
                } else if (event == XmlPullParser.END_TAG && styles.size() > 1) {
                    styles.pop();
                }
                event = parser.next();
            }
        } catch (Exception ignored) {
            // Malformed markup renders as far as it parsed, matching the iOS renderer.
        }

        BitmapDrawable drawable = new BitmapDrawable(resources, bitmap);
        drawable.setBounds(0, 0, sizePx, sizePx);
        return drawable;
    }

    private static void drawElement(Canvas canvas, XmlPullParser parser, SvgStyle style) {
        String name = parser.getName().toLowerCase();
        if ("path".equals(name)) {
            Path path = path(attr(parser, "d"));
            if (path != null) {
                drawPath(canvas, path, style);
            }
        } else if ("line".equals(name)) {
            Path path = new Path();
            path.moveTo(value(attr(parser, "x1")), value(attr(parser, "y1")));
            path.lineTo(value(attr(parser, "x2")), value(attr(parser, "y2")));
            drawPath(canvas, path, style);
        } else if ("polyline".equals(name) || "polygon".equals(name)) {
            Path path = pointsPath(attr(parser, "points"), "polygon".equals(name));
            if (path != null) {
                drawPath(canvas, path, style);
            }
        } else if ("circle".equals(name)) {
            float cx = value(attr(parser, "cx"));
            float cy = value(attr(parser, "cy"));
            float radius = value(attr(parser, "r"));
            Path path = new Path();
            path.addOval(new RectF(cx - radius, cy - radius, cx + radius, cy + radius), Path.Direction.CW);
            drawPath(canvas, path, style);
        } else if ("rect".equals(name)) {
            float x = value(attr(parser, "x"));
            float y = value(attr(parser, "y"));
            float width = value(attr(parser, "width"));
            float height = value(attr(parser, "height"));
            float radius = Math.max(value(attr(parser, "rx")), value(attr(parser, "ry")));
            Path path = new Path();
            RectF rect = new RectF(x, y, x + width, y + height);
            if (radius > 0) {
                path.addRoundRect(rect, radius, radius, Path.Direction.CW);
            } else {
                path.addRect(rect, Path.Direction.CW);
            }
            drawPath(canvas, path, style);
        }
    }

    private static void drawPath(Canvas canvas, Path path, SvgStyle style) {
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.BLACK);
        paint.setAlpha(style.alpha);
        if (style.fill) {
            paint.setStyle(Paint.Style.FILL);
            canvas.drawPath(path, paint);
        }
        if (style.stroke) {
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(style.strokeWidth);
            paint.setStrokeCap(style.lineCap);
            paint.setStrokeJoin(style.lineJoin);
            canvas.drawPath(path, paint);
        }
    }

    private static Path path(String data) {
        if (data == null || data.isEmpty()) {
            return null;
        }
        try {
            return PathParser.createPathFromPathData(data);
        } catch (RuntimeException ignored) {
            return null;
        }
    }

    private static Path pointsPath(String value, boolean closed) {
        List<Float> numbers = numbers(value);
        if (numbers.size() < 2) {
            return null;
        }
        Path path = new Path();
        path.moveTo(numbers.get(0), numbers.get(1));
        for (int index = 2; index + 1 < numbers.size(); index += 2) {
            path.lineTo(numbers.get(index), numbers.get(index + 1));
        }
        if (closed) {
            path.close();
        }
        return path;
    }

    static RectF viewBox(String svg, int iconSizeDp) {
        List<Float> viewBoxValues = numbers(attribute(svg, "viewBox"));
        if (viewBoxValues.size() >= 4) {
            return new RectF(
                viewBoxValues.get(0),
                viewBoxValues.get(1),
                viewBoxValues.get(0) + viewBoxValues.get(2),
                viewBoxValues.get(1) + viewBoxValues.get(3)
            );
        }
        float width = value(attribute(svg, "width"));
        float height = value(attribute(svg, "height"));
        if (width <= 0 || height <= 0) {
            width = iconSizeDp;
            height = iconSizeDp;
        }
        return new RectF(0, 0, width, height);
    }

    private static String attribute(String svg, String name) {
        if (svg == null) {
            return null;
        }
        Pattern pattern = Pattern.compile(name + "\\s*=\\s*[\"']([^\"']+)[\"']", Pattern.CASE_INSENSITIVE);
        Matcher matcher = pattern.matcher(svg);
        return matcher.find() ? matcher.group(1) : null;
    }

    private static float value(String value) {
        Float parsed = length(value);
        return parsed == null ? 0f : parsed;
    }

    static List<Float> numbers(String value) {
        List<Float> numbers = new ArrayList<>();
        if (value == null) {
            return numbers;
        }
        Matcher matcher = NUMBER_PATTERN.matcher(value);
        while (matcher.find()) {
            numbers.add(Float.parseFloat(matcher.group()));
        }
        return numbers;
    }

    static String attr(XmlPullParser parser, String name) {
        return parser.getAttributeValue(null, name);
    }

    static Float length(String value) {
        if (value == null || value.trim().isEmpty()) {
            return null;
        }
        Matcher matcher = NUMBER_PATTERN.matcher(value.trim());
        return matcher.find() ? Float.parseFloat(matcher.group()) : null;
    }

    /** Inherited presentation attributes for the shapes above. */
    static final class SvgStyle {

        boolean fill = true;
        boolean stroke = false;
        float strokeWidth = 2f;
        Paint.Cap lineCap = Paint.Cap.BUTT;
        Paint.Join lineJoin = Paint.Join.MITER;
        int alpha = 255;

        SvgStyle copy() {
            SvgStyle copy = new SvgStyle();
            copy.fill = fill;
            copy.stroke = stroke;
            copy.strokeWidth = strokeWidth;
            copy.lineCap = lineCap;
            copy.lineJoin = lineJoin;
            copy.alpha = alpha;
            return copy;
        }

        void apply(XmlPullParser parser) {
            String fillValue = attr(parser, "fill");
            if (fillValue != null) {
                fill = !"none".equalsIgnoreCase(fillValue);
            }
            String strokeValue = attr(parser, "stroke");
            if (strokeValue != null) {
                stroke = !"none".equalsIgnoreCase(strokeValue);
            }
            Float width = length(attr(parser, "stroke-width"));
            if (width != null) {
                strokeWidth = width;
            }
            Float opacity = length(attr(parser, "opacity"));
            if (opacity != null) {
                alpha = Math.max(0, Math.min(255, Math.round(opacity * 255)));
            }
            String cap = attr(parser, "stroke-linecap");
            if ("round".equalsIgnoreCase(cap)) {
                lineCap = Paint.Cap.ROUND;
            } else if ("square".equalsIgnoreCase(cap)) {
                lineCap = Paint.Cap.SQUARE;
            } else if (cap != null) {
                lineCap = Paint.Cap.BUTT;
            }
            String join = attr(parser, "stroke-linejoin");
            if ("round".equalsIgnoreCase(join)) {
                lineJoin = Paint.Join.ROUND;
            } else if ("bevel".equalsIgnoreCase(join)) {
                lineJoin = Paint.Join.BEVEL;
            } else if (join != null) {
                lineJoin = Paint.Join.MITER;
            }
        }
    }
}
