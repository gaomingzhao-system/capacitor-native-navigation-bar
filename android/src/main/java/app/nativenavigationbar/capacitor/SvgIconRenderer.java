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
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.xml.parsers.SAXParserFactory;
import org.xml.sax.Attributes;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;
import org.xml.sax.helpers.DefaultHandler;
import org.xmlpull.v1.XmlPullParser;
import org.xmlpull.v1.XmlPullParserFactory;

/**
 * Minimal SVG rasterizer for icon descriptors. Supports the shape subset the
 * public API documents: path, line, polyline, polygon, circle and rect.
 */
final class SvgIconRenderer {

    static final Pattern NUMBER_PATTERN = Pattern.compile("[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?");
    static final int MAX_SVG_CHARACTERS = 256_000;
    static final int MAX_ICON_SIZE_DP = 256;
    private static final int MAX_XML_ELEMENTS = 2_048;
    private static final int MAX_XML_DEPTH = 64;
    private static final int MAX_BITMAP_PIXELS = 4_194_304;

    private SvgIconRenderer() {}

    static Drawable render(Resources resources, String svg, int iconWidthDp, int iconHeightDp) {
        if (!isSafeSvg(svg)) {
            return null;
        }
        int safeWidthDp = Math.max(1, Math.min(MAX_ICON_SIZE_DP, iconWidthDp));
        int safeHeightDp = Math.max(1, Math.min(MAX_ICON_SIZE_DP, iconHeightDp));
        float density = NativeUnitConverter.normalizedDensity(resources.getDisplayMetrics().density);
        int widthPx = Math.max(1, Math.round(safeWidthDp * density));
        int heightPx = Math.max(1, Math.round(safeHeightDp * density));
        long pixels = (long) widthPx * heightPx;
        if (pixels > MAX_BITMAP_PIXELS) {
            float scale = (float) Math.sqrt(MAX_BITMAP_PIXELS / (double) pixels);
            widthPx = Math.max(1, Math.round(widthPx * scale));
            heightPx = Math.max(1, Math.round(heightPx * scale));
        }

        Bitmap bitmap;
        try {
            bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888);
        } catch (OutOfMemoryError | IllegalArgumentException ignored) {
            return null;
        }
        Canvas canvas = new Canvas(bitmap);
        RectF viewBox = viewBox(svg, safeWidthDp, safeHeightDp);
        canvas.scale(widthPx / Math.max(viewBox.width(), 1f), heightPx / Math.max(viewBox.height(), 1f));
        canvas.translate(-viewBox.left, -viewBox.top);

        try {
            XmlPullParser parser = XmlPullParserFactory.newInstance().newPullParser();
            parser.setFeature("http://xmlpull.org/v1/doc/features.html#process-docdecl", false);
            parser.setInput(new StringReader(svg));
            ArrayDeque<SvgStyle> styles = new ArrayDeque<>();
            styles.push(new SvgStyle());
            int elementCount = 0;
            int event = parser.getEventType();
            while (event != XmlPullParser.END_DOCUMENT) {
                if (event == XmlPullParser.START_TAG) {
                    elementCount++;
                    if (elementCount > MAX_XML_ELEMENTS || styles.size() >= MAX_XML_DEPTH) {
                        bitmap.recycle();
                        return null;
                    }
                    SvgStyle style = styles.peek().copy();
                    style.apply(parser);
                    styles.push(style);
                    drawElement(canvas, parser, style);
                } else if (event == XmlPullParser.END_TAG && styles.size() > 1) {
                    styles.pop();
                }
                event = parser.next();
            }
        } catch (Exception | OutOfMemoryError ignored) {
            bitmap.recycle();
            return null;
        }

        BitmapDrawable drawable = new BitmapDrawable(resources, bitmap);
        drawable.setBounds(0, 0, widthPx, heightPx);
        return drawable;
    }

    static boolean isSafeSvg(String svg) {
        if (svg == null || svg.isEmpty() || svg.length() > MAX_SVG_CHARACTERS) {
            return false;
        }
        String lower = svg.toLowerCase(Locale.ROOT);
        if (lower.contains("<!doctype") || lower.contains("<!entity")) {
            return false;
        }
        try {
            SAXParserFactory factory = SAXParserFactory.newInstance();
            factory.setNamespaceAware(true);
            SvgValidationHandler handler = new SvgValidationHandler();
            org.xml.sax.XMLReader reader = factory.newSAXParser().getXMLReader();
            reader.setEntityResolver((publicId, systemId) -> {
                throw new SAXException("External SVG entities are not allowed");
            });
            reader.setContentHandler(handler);
            reader.parse(new InputSource(new StringReader(svg)));
            return handler.sawSvgRoot && handler.depth == 0;
        } catch (Exception | OutOfMemoryError ignored) {
            return false;
        }
    }

    private static final class SvgValidationHandler extends DefaultHandler {

        int depth;
        int elementCount;
        boolean sawSvgRoot;

        @Override
        public void startElement(String uri, String localName, String qualifiedName, Attributes attributes) throws SAXException {
            depth++;
            elementCount++;
            String name = localName == null || localName.isEmpty() ? qualifiedName : localName;
            if (depth == 1) {
                sawSvgRoot = "svg".equalsIgnoreCase(name);
            }
            if (!sawSvgRoot || depth > MAX_XML_DEPTH || elementCount > MAX_XML_ELEMENTS) {
                throw new SAXException("SVG structure exceeds renderer limits");
            }
        }

        @Override
        public void endElement(String uri, String localName, String qualifiedName) throws SAXException {
            depth--;
            if (depth < 0) {
                throw new SAXException("Unbalanced SVG markup");
            }
        }
    }

    private static void drawElement(Canvas canvas, XmlPullParser parser, SvgStyle style) {
        String name = parser.getName().toLowerCase(Locale.ROOT);
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
        paint.setAlpha(style.alpha);
        if (style.fill) {
            paint.setColor(style.fillColor);
            paint.setStyle(Paint.Style.FILL);
            canvas.drawPath(path, paint);
        }
        if (style.stroke) {
            paint.setColor(style.strokeColor);
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

    static RectF viewBox(String svg, int fallbackWidthDp, int fallbackHeightDp) {
        List<Float> viewBoxValues = numbers(attribute(svg, "viewBox"));
        if (viewBoxValues.size() >= 4 && viewBoxValues.get(2) > 0f && viewBoxValues.get(3) > 0f) {
            float left = viewBoxValues.get(0);
            float top = viewBoxValues.get(1);
            float right = left + viewBoxValues.get(2);
            float bottom = top + viewBoxValues.get(3);
            if (Float.isFinite(right) && Float.isFinite(bottom)) {
                return new RectF(left, top, right, bottom);
            }
        }
        float width = value(attribute(svg, "width"));
        float height = value(attribute(svg, "height"));
        if (width <= 0 || height <= 0) {
            width = fallbackWidthDp;
            height = fallbackHeightDp;
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
            try {
                float parsed = Float.parseFloat(matcher.group());
                if (Float.isFinite(parsed)) {
                    numbers.add(parsed);
                }
            } catch (NumberFormatException ignored) {
                // Ignore values outside Float's representable range.
            }
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
        if (!matcher.find()) {
            return null;
        }
        try {
            float parsed = Float.parseFloat(matcher.group());
            return Float.isFinite(parsed) ? parsed : null;
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    /** Inherited presentation attributes for the shapes above. */
    static final class SvgStyle {

        boolean fill = true;
        boolean stroke = false;
        int fillColor = Color.BLACK;
        int strokeColor = Color.BLACK;
        float strokeWidth = 2f;
        Paint.Cap lineCap = Paint.Cap.BUTT;
        Paint.Join lineJoin = Paint.Join.MITER;
        int alpha = 255;

        SvgStyle copy() {
            SvgStyle copy = new SvgStyle();
            copy.fill = fill;
            copy.stroke = stroke;
            copy.fillColor = fillColor;
            copy.strokeColor = strokeColor;
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
                fillColor = svgColor(fillValue, fillColor);
            }
            String strokeValue = attr(parser, "stroke");
            if (strokeValue != null) {
                stroke = !"none".equalsIgnoreCase(strokeValue);
                strokeColor = svgColor(strokeValue, strokeColor);
            }
            Float width = length(attr(parser, "stroke-width"));
            if (width != null) {
                strokeWidth = Math.max(0f, Math.min(1024f, width));
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

        private int svgColor(String value, int fallback) {
            if (value == null || value.isEmpty() || "currentColor".equalsIgnoreCase(value) || "none".equalsIgnoreCase(value)) {
                return fallback;
            }
            try {
                return Color.parseColor(value);
            } catch (IllegalArgumentException ignored) {
                return fallback;
            }
        }
    }
}
