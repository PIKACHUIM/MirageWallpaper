#import "RMMeter.h"
#import "RMConfigParser.h"
#import "RMMeasure.h"
#import "RMFontManager.h"
#import "RMLog.h"
#import <CoreImage/CoreImage.h>

#pragma mark - Helpers

static NSColor *RMParseColor(NSString *_Nullable s, NSColor *fallback) {
    if (s.length == 0) return fallback;
    NSArray<NSString *> *parts = [s componentsSeparatedByString:@","];
    if (parts.count >= 3) {
        CGFloat r = [parts[0] doubleValue] / 255.0;
        CGFloat g = [parts[1] doubleValue] / 255.0;
        CGFloat b = [parts[2] doubleValue] / 255.0;
        CGFloat a = parts.count >= 4 ? [parts[3] doubleValue] / 255.0 : 1.0;
        return [NSColor colorWithSRGBRed:r green:g blue:b alpha:a];
    }
    // Hex RRGGBB / RRGGBBAA.
    NSString *hex = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (hex.length == 6 || hex.length == 8) {
        unsigned int v = 0; NSScanner *sc = [NSScanner scannerWithString:hex];
        if ([sc scanHexInt:&v]) {
            if (hex.length == 6) {
                return [NSColor colorWithSRGBRed:((v>>16)&0xFF)/255.0
                                           green:((v>>8)&0xFF)/255.0
                                            blue:(v&0xFF)/255.0 alpha:1.0];
            } else {
                return [NSColor colorWithSRGBRed:((v>>24)&0xFF)/255.0
                                           green:((v>>16)&0xFF)/255.0
                                            blue:((v>>8)&0xFF)/255.0
                                           alpha:(v&0xFF)/255.0];
            }
        }
    }
    return fallback;
}

static NSString *RMNormalizePath(NSString *_Nullable p) {
    if (p.length == 0) return p ?: @"";
    return [p stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
}

// Resolve an image path: absolute paths are used as-is; relative paths
// ("My Computer.png") are looked up first in the skin config directory
// (#CURRENTPATH#) and then in the config @Resources folder (#@#).
static NSString *RMResolveImagePath(NSString *_Nullable raw, RMConfigParser *parser) {
    NSString *p = RMNormalizePath(raw);
    if (p.length == 0) return @"";
    NSFileManager *fm = [NSFileManager defaultManager];
    if (p.isAbsolutePath) return p;
    NSString *cur = parser.currentPath;
    if (cur.length) {
        NSString *cand = [cur stringByAppendingPathComponent:p];
        if ([fm fileExistsAtPath:cand]) return cand;
    }
    NSString *res = parser.resourcesPath;
    if (res.length) {
        NSString *cand = [res stringByAppendingPathComponent:p];
        if ([fm fileExistsAtPath:cand]) return cand;
    }
    // Fall back to config-dir join even if missing, for logging clarity.
    return cur.length ? [cur stringByAppendingPathComponent:p] : p;
}

// Multiply-tint an image (Rainmeter ImageTint semantics: out.rgba = src.rgba *
// tint.rgba / 255). ImageTint=255,255,255,200 keeps the original colours and
// scales alpha to 200/255; a coloured tint recolours a greyscale source. This
// is very different from a solid overlay (SourceAtop), which would replace
// the pixel colours entirely.
static NSImage *RMTintImage(NSImage *src, NSColor *tint) {
    if (src == nil || tint == nil) return src;
    NSSize sz = src.size;
    if (sz.width <= 0 || sz.height <= 0) return src;

    NSColor *srgb = [tint colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: tint;
    CGFloat tr = srgb.redComponent, tg = srgb.greenComponent, tb = srgb.blueComponent, ta = srgb.alphaComponent;

    CIImage *ci = [CIImage imageWithData:[src TIFFRepresentation]];
    if (ci == nil) return src;
    CIFilter *m = [CIFilter filterWithName:@"CIColorMatrix"];
    [m setValue:ci forKey:kCIInputImageKey];
    [m setValue:[CIVector vectorWithX:tr Y:0 Z:0 W:0] forKey:@"inputRVector"];
    [m setValue:[CIVector vectorWithX:0 Y:tg Z:0 W:0] forKey:@"inputGVector"];
    [m setValue:[CIVector vectorWithX:0 Y:0 Z:tb W:0] forKey:@"inputBVector"];
    [m setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:ta] forKey:@"inputAVector"];
    CIImage *out = m.outputImage;
    if (out == nil) return src;
    NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage:out];
    NSImage *result = [[NSImage alloc] initWithSize:sz];
    [result addRepresentation:rep];
    return result;
}

static double RMRelativeValue(RMMeasure *m) {
    if (m == nil) return 0;
    double range = m.maxValue - m.minValue;
    if (range <= 0) return 0;
    double r = (m.value - m.minValue) / range;
    return r < 0 ? 0 : (r > 1 ? 1 : r);
}

#pragma mark - Base

@interface RMMeter ()
@property (nonatomic, strong) NSColor *solidColor;
- (void)readSubclassOptions;
- (void)fillBackgroundIfNeeded;
- (NSString *)measureStringAtIndex:(int)idx;
@end

// Concrete meter classes.
@interface RMMeterImage     : RMMeter @end
@interface RMMeterString    : RMMeter @end
@interface RMMeterBar       : RMMeter @end
@interface RMMeterLine      : RMMeter @end
@interface RMMeterHistogram : RMMeter @end
@interface RMMeterRotator   : RMMeter @end
@interface RMMeterRoundLine : RMMeter @end
@interface RMMeterShape     : RMMeter @end
@interface RMMeterBitmap    : RMMeter @end

@implementation RMMeter

+ (nullable RMMeter *)meterWithType:(NSString *)type
                               name:(NSString *)name
                             parser:(RMConfigParser *)parser {
    NSString *t = type.lowercaseString;
    Class cls;
    if ([t isEqualToString:@"image"])          cls = [RMMeterImage class];
    else if ([t isEqualToString:@"string"])    cls = [RMMeterString class];
    else if ([t isEqualToString:@"bar"])       cls = [RMMeterBar class];
    else if ([t isEqualToString:@"line"])      cls = [RMMeterLine class];
    else if ([t isEqualToString:@"histogram"]) cls = [RMMeterHistogram class];
    else if ([t isEqualToString:@"rotator"])   cls = [RMMeterRotator class];
    else if ([t isEqualToString:@"roundline"]) cls = [RMMeterRoundLine class];
    else if ([t isEqualToString:@"shape"])     cls = [RMMeterShape class];
    else if ([t isEqualToString:@"bitmap"])    cls = [RMMeterBitmap class];
    else return nil;

    RMMeter *m = [[cls alloc] init];
    m.name = name;
    m.parser = parser;
    return m;
}

- (NSRect)frame { return NSMakeRect(self.x, self.y, self.w, self.h); }

- (void)readOptions {
    RMConfigParser *cp = self.parser;

    NSString *xs = [cp readString:self.name key:@"X" default:@"0"];
    NSString *ys = [cp readString:self.name key:@"Y" default:@"0"];
    [self parsePosition:xs isX:YES];
    [self parsePosition:ys isX:NO];

    self.w = [cp readDouble:self.name key:@"W" default:0];
    self.h = [cp readDouble:self.name key:@"H" default:0];
    self.hidden = [cp readBool:self.name key:@"Hidden" default:NO];
    self.antiAlias = [cp readBool:self.name key:@"AntiAlias" default:YES];
    self.group = [cp readString:self.name key:@"Group" default:nil];
    self.solidColor = RMParseColor([cp readString:self.name key:@"SolidColor" default:nil], nil);

    // MeasureName / MeasureName2 ... MeasureNameN
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSString *first = [cp readString:self.name key:@"MeasureName" default:nil];
    if (first.length) [names addObject:first];
    for (int i = 2; i <= 16; i++) {
        NSString *k = [NSString stringWithFormat:@"MeasureName%d", i];
        NSString *v = [cp readString:self.name key:k default:nil];
        if (v.length) [names addObject:v]; else if (i > 2 && first == nil) break;
    }
    self.measureNames = names;

    self.leftMouseUpAction  = [cp readString:self.name key:@"LeftMouseUpAction"  default:nil];
    self.rightMouseUpAction = [cp readString:self.name key:@"RightMouseUpAction" default:nil];

    [self readSubclassOptions];
}

- (void)parsePosition:(NSString *)s isX:(BOOL)isX {
    NSString *v = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL relative = NO, br = NO;
    if (v.length > 0) {
        unichar last = [v characterAtIndex:v.length - 1];
        if (last == 'r') { relative = YES; br = NO;  v = [v substringToIndex:v.length - 1]; }
        else if (last == 'R') { relative = YES; br = YES; v = [v substringToIndex:v.length - 1]; }
    }
    double num = [RMConfigParser evaluateNumber:v default:0];
    if (isX) { self.x = num; self.authoredX = num; self.relativeX = relative; self.relativeXBR = br; self.rawX = s; }
    else     { self.y = num; self.authoredY = num; self.relativeY = relative; self.relativeYBR = br; self.rawY = s; }
}

// Reset live position to the authored value so alignment/relative offsets do
// not accumulate across ticks.
- (void)resetToAuthoredPosition {
    self.x = self.authoredX;
    self.y = self.authoredY;
}

// Resolve relative position given the previous meter (called during layout).
// Rainmeter semantics:
//   x=Nr  → prev.x + N       (TL: relative to previous top-left)
//   x=NR  → prev.x + prev.w + N   (BR: relative to previous bottom-right)
- (void)resolvePositionWithPrevious:(nullable RMMeter *)prev {
    if (prev == nil) return;
    if (self.relativeX) self.x = prev.x + (self.relativeXBR ? prev.w : 0) + self.authoredX;
    if (self.relativeY) self.y = prev.y + (self.relativeYBR ? prev.h : 0) + self.authoredY;
}

- (void)readSubclassOptions { /* override */ }
- (void)prepare { /* override */ }
- (void)draw { /* override */ }

// Build the display text for a bound measure index (1-based).
- (NSString *)measureStringAtIndex:(int)idx {
    int i = idx - 1;
    if (i < 0 || i >= (int)self.measures.count) return @"";
    RMMeasure *m = self.measures[i];
    RMConfigParser *cp = self.parser;
    BOOL autoScale  = [cp readBool:self.name key:@"AutoScale" default:NO];
    BOOL percentual = [cp readBool:self.name key:@"Percentual" default:NO];
    int decimals    = [cp readInt:self.name key:@"NumberOfDecimals" default:-1];
    double scale    = [cp readDouble:self.name key:@"Scale" default:1];
    return [m displayStringAutoScale:autoScale decimals:decimals percentual:percentual scale:scale];
}

- (void)fillBackgroundIfNeeded {
    if (self.solidColor && self.w > 0 && self.h > 0) {
        [self.solidColor setFill];
        NSRectFillUsingOperation(self.frame, NSCompositingOperationSourceOver);
    }
}

@end

#pragma mark - Image

@implementation RMMeterImage {
    NSString *_imagePath;
    NSImage *_image;
    NSString *_loadedPath;
    CGFloat _alpha;
    BOOL _greyscale;
    BOOL _preserveAspect;
    NSColor *_tint;
}
- (void)readSubclassOptions {
    _imagePath = [self.parser readString:self.name key:@"ImageName" default:nil];
    _alpha = [self.parser readDouble:self.name key:@"ImageAlpha" default:255] / 255.0;
    _greyscale = [self.parser readBool:self.name key:@"Greyscale" default:NO];
    _preserveAspect = [self.parser readBool:self.name key:@"PreserveAspectRatio" default:NO];
    _tint = RMParseColor([self.parser readString:self.name key:@"ImageTint" default:nil], nil);
    _loadedPath = nil;   // force reload when options change (e.g. !SetOption)
}
- (void)loadIfNeeded {
    if (_imagePath.length == 0) return;
    NSString *resolved = RMResolveImagePath(_imagePath, self.parser);
    if ([_loadedPath isEqualToString:resolved] && _image) return;
    _loadedPath = resolved;
    _image = [[NSImage alloc] initWithContentsOfFile:resolved];
    if (_image == nil) { RMLogDebug(@"image not found: %@", resolved); return; }
    if (_greyscale) {
        CIImage *ci = [CIImage imageWithData:[_image TIFFRepresentation]];
        CIFilter *f = [CIFilter filterWithName:@"CIPhotoEffectMono"];
        [f setValue:ci forKey:kCIInputImageKey];
        CIImage *out = f.outputImage;
        if (out) {
            NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage:out];
            NSImage *g = [[NSImage alloc] initWithSize:rep.size];
            [g addRepresentation:rep];
            _image = g;
        }
    }
    if (_tint) _image = RMTintImage(_image, _tint);
}
- (void)prepare {
    [self loadIfNeeded];
    if (_image) {
        if (self.w <= 0) self.w = _image.size.width;
        if (self.h <= 0) self.h = _image.size.height;
    }
}
- (void)draw {
    [self fillBackgroundIfNeeded];
    if (_image == nil) return;
    NSRect dst = self.frame;
    if (_preserveAspect && _image.size.width > 0 && _image.size.height > 0) {
        CGFloat s = MIN(dst.size.width / _image.size.width, dst.size.height / _image.size.height);
        CGFloat nw = _image.size.width * s, nh = _image.size.height * s;
        dst = NSMakeRect(dst.origin.x + (dst.size.width - nw) / 2,
                         dst.origin.y + (dst.size.height - nh) / 2, nw, nh);
    }
    [_image drawInRect:dst fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver fraction:_alpha respectFlipped:YES hints:nil];
}
@end

#pragma mark - String

@implementation RMMeterString {
    NSString *_text;
    NSString *_prefix, *_postfix;
    NSString *_align;
    NSString *_case;
    NSString *_effect;
    NSColor *_fontColor;
    NSColor *_effectColor;
    NSString *_face;
    CGFloat _fontSize;
    BOOL _bold, _italic;
    CGFloat _charSpacing;
    NSString *_renderedText;
    NSSize _measured;
    NSPoint _drawOrigin;
}
- (void)readSubclassOptions {
    RMConfigParser *cp = self.parser;
    _text = [cp readString:self.name key:@"Text" default:nil];
    _prefix = [cp readString:self.name key:@"Prefix" default:@""];
    _postfix = [cp readString:self.name key:@"Postfix" default:@""];
    _align = ([cp readString:self.name key:@"StringAlign" default:@"Left"]).lowercaseString;
    _case = ([cp readString:self.name key:@"StringCase" default:@"None"]).lowercaseString;
    _effect = ([cp readString:self.name key:@"StringEffect" default:@"None"]).lowercaseString;
    _fontColor = RMParseColor([cp readString:self.name key:@"FontColor" default:nil],
                              [NSColor whiteColor]);
    _effectColor = RMParseColor([cp readString:self.name key:@"FontEffectColor" default:nil],
                                [NSColor blackColor]);
    _face = [cp readString:self.name key:@"FontFace" default:nil];
    _fontSize = [cp readDouble:self.name key:@"FontSize" default:10];
    NSString *style = ([cp readString:self.name key:@"StringStyle" default:@"Normal"]).lowercaseString;
    _bold = [style containsString:@"bold"];
    _italic = [style containsString:@"italic"];
    // InlineSetting=CharacterSpacing | value | ... (partial support).
    NSString *inl = [cp readString:self.name key:@"InlineSetting" default:nil];
    if ([inl.lowercaseString containsString:@"characterspacing"]) {
        NSArray *parts = [inl componentsSeparatedByString:@"|"];
        if (parts.count >= 2) _charSpacing = [parts[1] doubleValue];
    }
}
- (NSString *)composeText {
    NSString *t = _text ?: (self.measureNames.count ? @"%1" : @"");
    for (int i = (int)self.measures.count; i >= 1; i--) {
        NSString *tok = [NSString stringWithFormat:@"%%%d", i];
        t = [t stringByReplacingOccurrencesOfString:tok withString:[self measureStringAtIndex:i]];
    }
    t = [NSString stringWithFormat:@"%@%@%@", _prefix ?: @"", t, _postfix ?: @""];
    if ([_case isEqualToString:@"upper"]) t = t.uppercaseString;
    else if ([_case isEqualToString:@"lower"]) t = t.lowercaseString;
    else if ([_case isEqualToString:@"proper"]) t = t.capitalizedString;
    return t;
}
- (NSDictionary *)attributes {
    NSFont *font = [[RMFontManager shared] fontWithFace:_face size:_fontSize bold:_bold italic:_italic];
    // NOTE: we do NOT set paragraph-style alignment here. Rainmeter's
    // StringAlign shifts the whole text box relative to the (X,Y) anchor
    // — it is not intra-box justification. drawInRect: with a paragraph
    // alignment plus a wider-than-text box would justify the glyphs inside
    // the box and defeat the anchor shift we compute in `prepare`.
    NSMutableDictionary *attrs = [@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: _fontColor,
    } mutableCopy];
    if (_charSpacing != 0) attrs[NSKernAttributeName] = @(_charSpacing);
    return attrs;
}
- (void)prepare {
    _renderedText = [self composeText];
    NSDictionary *attrs = [self attributes];
    _measured = [_renderedText sizeWithAttributes:attrs];
    if (self.w <= 0) self.w = ceil(_measured.width);
    if (self.h <= 0) self.h = ceil(_measured.height);

    // Compute the aligned draw origin ONCE per tick from the (stable) anchor.
    // self.x/self.y stay at the authored anchor so nothing accumulates.
    NSSize sz = _measured;
    CGFloat drawX = self.x, drawY = self.y;
    if ([_align hasPrefix:@"center"])     drawX = self.x - sz.width / 2.0;
    else if ([_align hasPrefix:@"right"]) drawX = self.x - sz.width;
    if ([_align hasSuffix:@"center"] && ![_align isEqualToString:@"center"])
        drawY = self.y - sz.height / 2.0;
    else if ([_align hasSuffix:@"bottom"])
        drawY = self.y - sz.height;
    _drawOrigin = NSMakePoint(drawX, drawY);
}
- (void)draw {
    [self fillBackgroundIfNeeded];
    if (_renderedText.length == 0) return;
    NSDictionary *attrs = [self attributes];
    NSSize sz = _measured;

    // Box width must match measured text width; using a wider self.w would
    // cause the paragraph aligner (or Cocoa's default line-fill) to shift
    // glyphs inside the box and break our anchor-based positioning.
    NSRect box = NSMakeRect(_drawOrigin.x, _drawOrigin.y, ceil(sz.width) + 1, sz.height);

    if ([_effect isEqualToString:@"shadow"]) {
        NSMutableDictionary *e = [attrs mutableCopy];
        e[NSForegroundColorAttributeName] = _effectColor;
        [_renderedText drawInRect:NSOffsetRect(box, 1, 1) withAttributes:e];
    } else if ([_effect isEqualToString:@"border"]) {
        NSMutableDictionary *e = [attrs mutableCopy];
        e[NSForegroundColorAttributeName] = _effectColor;
        for (int dx = -1; dx <= 1; dx++)
            for (int dy = -1; dy <= 1; dy++)
                if (dx || dy) [_renderedText drawInRect:NSOffsetRect(box, dx, dy) withAttributes:e];
    }
    [_renderedText drawInRect:box withAttributes:attrs];
}
@end

#pragma mark - Bar

@implementation RMMeterBar {
    NSColor *_barColor;
    NSString *_orientation;
    BOOL _flip;
}
- (void)readSubclassOptions {
    _barColor = RMParseColor([self.parser readString:self.name key:@"BarColor" default:nil],
                             [NSColor whiteColor]);
    _orientation = ([self.parser readString:self.name key:@"BarOrientation" default:@"Vertical"]).lowercaseString;
    _flip = [self.parser readBool:self.name key:@"Flip" default:NO];
}
- (void)draw {
    [self fillBackgroundIfNeeded];
    double rel = RMRelativeValue(self.measures.firstObject);
    NSRect f = self.frame;
    [_barColor setFill];
    if ([_orientation hasPrefix:@"horiz"]) {
        CGFloat bw = f.size.width * rel;
        NSRect bar = _flip ? NSMakeRect(f.origin.x + f.size.width - bw, f.origin.y, bw, f.size.height)
                           : NSMakeRect(f.origin.x, f.origin.y, bw, f.size.height);
        NSRectFillUsingOperation(bar, NSCompositingOperationSourceOver);
    } else {
        CGFloat bh = f.size.height * rel;
        // Flipped view: y grows downward. Default bar grows from bottom up.
        NSRect bar = _flip ? NSMakeRect(f.origin.x, f.origin.y, f.size.width, bh)
                           : NSMakeRect(f.origin.x, f.origin.y + f.size.height - bh, f.size.width, bh);
        NSRectFillUsingOperation(bar, NSCompositingOperationSourceOver);
    }
}
@end

#pragma mark - Line

@implementation RMMeterLine {
    NSColor *_lineColor;
    NSMutableArray<NSNumber *> *_history;
    double _scaleV;
}
- (void)readSubclassOptions {
    _lineColor = RMParseColor([self.parser readString:self.name key:@"LineColor" default:nil],
                              [NSColor greenColor]);
    _scaleV = [self.parser readDouble:self.name key:@"LineScale" default:1];
    _history = [NSMutableArray array];
}
- (void)prepare {
    RMMeasure *m = self.measures.firstObject;
    [_history addObject:@(RMRelativeValue(m))];
    NSInteger cap = (NSInteger)MAX(self.w, 1);
    while ((NSInteger)_history.count > cap) [_history removeObjectAtIndex:0];
}
- (void)draw {
    [self fillBackgroundIfNeeded];
    if (_history.count < 2) return;
    NSRect f = self.frame;
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSInteger n = _history.count;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat px = f.origin.x + f.size.width * (CGFloat)i / (CGFloat)MAX(n - 1, 1);
        CGFloat rel = _history[i].doubleValue;
        CGFloat py = f.origin.y + f.size.height - f.size.height * rel;  // flipped
        if (i == 0) [path moveToPoint:NSMakePoint(px, py)];
        else [path lineToPoint:NSMakePoint(px, py)];
    }
    [_lineColor setStroke];
    path.lineWidth = 1.0;
    [path stroke];
}
@end

#pragma mark - Histogram

@implementation RMMeterHistogram {
    NSColor *_primary;
    NSMutableArray<NSNumber *> *_history;
}
- (void)readSubclassOptions {
    _primary = RMParseColor([self.parser readString:self.name key:@"PrimaryColor" default:nil],
                            [NSColor greenColor]);
    _history = [NSMutableArray array];
}
- (void)prepare {
    [_history addObject:@(RMRelativeValue(self.measures.firstObject))];
    NSInteger cap = (NSInteger)MAX(self.w, 1);
    while ((NSInteger)_history.count > cap) [_history removeObjectAtIndex:0];
}
- (void)draw {
    [self fillBackgroundIfNeeded];
    NSRect f = self.frame;
    [_primary setFill];
    NSInteger n = _history.count;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat rel = _history[i].doubleValue;
        CGFloat bh = f.size.height * rel;
        NSRect bar = NSMakeRect(f.origin.x + i, f.origin.y + f.size.height - bh, 1, bh);
        NSRectFillUsingOperation(bar, NSCompositingOperationSourceOver);
    }
}
@end

#pragma mark - Rotator

@implementation RMMeterRotator {
    NSString *_imagePath; NSImage *_image;
    double _startAngle, _rotationAngle;
    CGFloat _offsetX, _offsetY;
}
- (void)readSubclassOptions {
    _imagePath = [self.parser readString:self.name key:@"ImageName" default:nil];
    _startAngle = [self.parser readDouble:self.name key:@"StartAngle" default:0];
    _rotationAngle = [self.parser readDouble:self.name key:@"RotationAngle" default:6.2832];
    _offsetX = [self.parser readDouble:self.name key:@"OffsetX" default:0];
    _offsetY = [self.parser readDouble:self.name key:@"OffsetY" default:0];
    if (_imagePath.length) {
        NSString *resolved = RMResolveImagePath(_imagePath, self.parser);
        _image = [[NSImage alloc] initWithContentsOfFile:resolved];
    }
}
- (void)draw {
    [self fillBackgroundIfNeeded];
    if (_image == nil) return;
    double rel = RMRelativeValue(self.measures.firstObject);
    double angle = _startAngle + _rotationAngle * rel;
    NSRect f = self.frame;
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];
    NSAffineTransform *tr = [NSAffineTransform transform];
    CGFloat cx = f.origin.x + f.size.width / 2.0;
    CGFloat cy = f.origin.y + f.size.height / 2.0;
    [tr translateXBy:cx yBy:cy];
    [tr rotateByRadians:-angle];  // flipped view → negate for clockwise
    [tr concat];
    NSRect dst = NSMakeRect(-_offsetX, -_offsetY, _image.size.width, _image.size.height);
    [_image drawInRect:dst fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    [ctx restoreGraphicsState];
}
@end

#pragma mark - RoundLine

@implementation RMMeterRoundLine {
    NSColor *_lineColor;
    double _lineLength, _lineStart, _startAngle, _rotationAngle;
    BOOL _solid;
}
- (void)readSubclassOptions {
    _lineColor = RMParseColor([self.parser readString:self.name key:@"LineColor" default:nil],
                              [NSColor whiteColor]);
    _lineLength = [self.parser readDouble:self.name key:@"LineLength" default:10];
    _lineStart = [self.parser readDouble:self.name key:@"LineStart" default:0];
    _startAngle = [self.parser readDouble:self.name key:@"StartAngle" default:0];
    _rotationAngle = [self.parser readDouble:self.name key:@"RotationAngle" default:6.2832];
    _solid = [self.parser readBool:self.name key:@"Solid" default:NO];
}
- (void)draw {
    [self fillBackgroundIfNeeded];
    double rel = RMRelativeValue(self.measures.firstObject);
    NSRect f = self.frame;
    CGFloat cx = f.origin.x + f.size.width / 2.0;
    CGFloat cy = f.origin.y + f.size.height / 2.0;
    double angle = _startAngle + _rotationAngle * rel;
    if (_solid) {
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(cx, cy)];
        [p appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy)
                                      radius:_lineLength
                                  startAngle:-_startAngle * 180.0 / M_PI
                                    endAngle:-angle * 180.0 / M_PI
                                   clockwise:YES];
        [p closePath];
        [_lineColor setFill];
        [p fill];
    } else {
        CGFloat ex = cx + cos(angle) * _lineLength;
        CGFloat ey = cy + sin(angle) * _lineLength;
        CGFloat sx = cx + cos(angle) * _lineStart;
        CGFloat sy = cy + sin(angle) * _lineStart;
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(sx, sy)];
        [p lineToPoint:NSMakePoint(ex, ey)];
        [_lineColor setStroke];
        p.lineWidth = 1.0;
        [p stroke];
    }
}
@end

#pragma mark - Shape (rectangle / line subset)

@implementation RMMeterShape {
    NSString *_shape;
}
- (void)readSubclassOptions {
    _shape = [self.parser readString:self.name key:@"Shape" default:nil];
}
- (void)draw {
    [self fillBackgroundIfNeeded];
    // Minimal Shape support: "Rectangle X,Y,W,H | Fill Color R,G,B,A".
    if (_shape.length == 0) return;
    NSString *low = _shape.lowercaseString;
    if ([low hasPrefix:@"rectangle"]) {
        NSArray *pipe = [_shape componentsSeparatedByString:@"|"];
        NSString *head = pipe.firstObject;
        NSArray *nums = [[head stringByReplacingOccurrencesOfString:@"Rectangle"
                                                         withString:@""
                                                            options:NSCaseInsensitiveSearch
                                                              range:NSMakeRange(0, head.length)]
                         componentsSeparatedByString:@","];
        if (nums.count >= 4) {
            NSRect r = NSMakeRect(self.x + [nums[0] doubleValue], self.y + [nums[1] doubleValue],
                                  [nums[2] doubleValue], [nums[3] doubleValue]);
            NSColor *fill = [NSColor colorWithWhite:1 alpha:0.5];
            for (NSString *mod in pipe) {
                NSString *m = [mod stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([m.lowercaseString hasPrefix:@"fill color"]) {
                    fill = RMParseColor([m substringFromIndex:10], fill);
                }
            }
            [fill setFill];
            NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
        }
    }
}
@end

#pragma mark - Bitmap (digit-strip font)

@implementation RMMeterBitmap {
    NSString *_imagePath;
    NSImage *_image;
    NSString *_loadedPath;
    NSColor *_tint;
    int _frameCount;
    int _digits;
    int _separation;
    BOOL _extend;
    BOOL _zeroFrame;
    NSString *_align;
    CGFloat _frameW, _frameH;
    BOOL _vertical;
}
- (void)readSubclassOptions {
    _imagePath = [self.parser readString:self.name key:@"BitmapImage" default:nil];
    _tint = RMParseColor([self.parser readString:self.name key:@"ImageTint" default:nil], nil);
    _frameCount = [self.parser readInt:self.name key:@"BitmapFrames" default:1];
    _digits = [self.parser readInt:self.name key:@"BitmapDigits" default:0];
    _separation = [self.parser readInt:self.name key:@"BitmapSeparation" default:0];
    _extend = [self.parser readBool:self.name key:@"BitmapExtend" default:NO];
    _zeroFrame = [self.parser readBool:self.name key:@"BitmapZeroFrame" default:NO];
    _align = ([self.parser readString:self.name key:@"BitmapAlign" default:@"LEFT"]).lowercaseString;
    _loadedPath = nil;
}
- (void)loadIfNeeded {
    if (_imagePath.length == 0) return;
    NSString *resolved = RMResolveImagePath(_imagePath, self.parser);
    if ([_loadedPath isEqualToString:resolved] && _image) return;
    _loadedPath = resolved;
    _image = [[NSImage alloc] initWithContentsOfFile:resolved];
    if (_image == nil) { RMLogDebug(@"bitmap image not found: %@", resolved); return; }
    if (_tint) _image = RMTintImage(_image, _tint);

    NSSize sz = _image.size;
    _vertical = sz.height > sz.width;
    if (_frameCount < 1) _frameCount = 1;
    if (_vertical) { _frameW = sz.width; _frameH = sz.height / _frameCount; }
    else           { _frameW = sz.width / _frameCount; _frameH = sz.height; }
}
- (void)prepare {
    [self loadIfNeeded];
    if (_image) {
        int digits = MAX(1, _digits);
        if (self.w <= 0) self.w = _extend ? (_frameW * digits + (digits - 1) * _separation) : _frameW;
        if (self.h <= 0) self.h = _frameH;
    }
}
// Draw one frame index `frame` at the given top-left rect origin.
- (void)drawFrame:(int)frame atX:(CGFloat)dx y:(CGFloat)dy {
    NSSize sz = _image.size;
    CGFloat srcX, srcY;
    if (_vertical) {
        srcX = 0;
        // Frame 0 is at the top of the file; NSImage uses a bottom-left origin.
        srcY = sz.height - (frame + 1) * _frameH;
    } else {
        srcX = frame * _frameW;
        srcY = 0;
    }
    NSRect dst = NSMakeRect(dx, dy, _frameW, _frameH);
    NSRect src = NSMakeRect(srcX, srcY, _frameW, _frameH);
    [_image drawInRect:dst fromRect:src operation:NSCompositingOperationSourceOver
              fraction:1.0 respectFlipped:YES hints:nil];
}
- (void)draw {
    [self fillBackgroundIfNeeded];
    if (_image == nil || _frameCount < 1) return;
    RMMeasure *m = self.measures.firstObject;

    if (_extend) {
        long long value = (long long)(m ? m.value : 0);
        if (value < 0) value = 0;
        int numOfNums = 0;
        if (_digits > 0) {
            numOfNums = _digits;
        } else {
            long long tmp = value;
            do { ++numOfNums; tmp = (_frameCount == 1) ? tmp / 2 : tmp / _frameCount; } while (tmp > 0);
        }
        CGFloat step = _frameW + _separation;
        CGFloat offset;
        if ([_align isEqualToString:@"right"])       offset = 0;
        else if ([_align isEqualToString:@"center"]) offset = numOfNums * step / 2.0;
        else                                          offset = numOfNums * step;   // left
        int remaining = numOfNums;
        do {
            offset -= step;
            int frame = (int)(value % _frameCount);
            [self drawFrame:frame atX:self.x + offset y:self.y];
            value = (_frameCount == 1) ? value / 2 : value / _frameCount;
            --remaining;
        } while (remaining > 0);
    } else {
        double rel = RMRelativeValue(m);
        int frame;
        if (_zeroFrame) frame = (m && m.value > 0.0) ? (int)(rel * (_frameCount - 1)) : 0;
        else            frame = (int)(rel * _frameCount);
        if (frame >= _frameCount) frame = _frameCount - 1;
        if (frame < 0) frame = 0;
        [self drawFrame:frame atX:self.x y:self.y];
    }
}
@end
