#import "WRDesktopInputForwarder.h"

#import <CoreGraphics/CoreGraphics.h>

// Click detection: a global event monitor (NSEvent.addGlobalMonitorForEvents)
// fires once per real left-click delivered to other apps. We forward the click
// to the wallpaper ONLY when it lands on the desktop (no app/Dock/menubar
// window on top at that point) — so clicks in real app windows stay with the
// app. Icon clicks are intentionally NOT special-cased (per design): clicking
// a desktop icon triggers both Finder (open/select) and the wallpaper, which
// is the simple, predictable behaviour. Mouse-move over the desktop is
// forwarded too.

@implementation WRDesktopInputForwarder {
    WKWebView *_webView;
    NSScreen  *_screen;
    id _mouseDownMonitor;
    id _mouseMoveMonitor;
    NSPoint _lastMovePos;
}

- (instancetype)initWithWebView:(WKWebView *)webView screen:(NSScreen *)screen {
    self = [super init];
    if (self) {
        _webView = webView;
        _screen = screen;
        _lastMovePos = NSMakePoint(-1, -1);
    }
    return self;
}

- (void)start {
    if (_mouseDownMonitor) return;
    _mouseDownMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
        NSEventMaskLeftMouseDown handler:^(NSEvent *e) { [self handleMouseDown:e]; }];
    _mouseMoveMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
        NSEventMaskMouseMoved handler:^(NSEvent *e) { [self handleMouseMove:e]; }];
    if (getenv("WR_DEBUG")) {
        fprintf(stderr, "WebRenderer: input forwarder started (global monitors), screen=%.0fx%.0f\n",
                _screen.frame.size.width, _screen.frame.size.height);
    }
}

- (void)stop {
    if (_mouseDownMonitor) { [NSEvent removeMonitor:_mouseDownMonitor]; _mouseDownMonitor = nil; }
    if (_mouseMoveMonitor) { [NSEvent removeMonitor:_mouseMoveMonitor]; _mouseMoveMonitor = nil; }
}

#pragma mark - Desktop hit detection

// Is `p` on the desktop? We skip system UI overlay windows (Dock, menubar,
// popups — all at layer > 0) which can be full-screen but click-transparent
// outside their actual region; the Dock's layer-20 window in particular
// covers the whole screen and would otherwise shadow every click. The first
// containing window at layer ≤ 0 is the real target: layer < 0 = desktop
// (Finder's desktop window), layer == 0 = an app window.
- (BOOL)pointIsOnDesktop:(NSPoint)p {
    CFArrayRef arr = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (arr == NULL) return NO;
    NSArray *windows = CFBridgingRelease(arr);
    CGFloat screenH = NSHeight(_screen.frame);
    CGPoint cgPt = CGPointMake((CGFloat)p.x, screenH - (CGFloat)p.y);  // Cocoa→CG (y flip)
    for (NSDictionary *w in windows) {
        CGRect bounds = CGRectZero;
        NSDictionary *b = w[(__bridge NSString *)kCGWindowBounds];
        if (b) CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)b, &bounds);
        if (!CGRectContainsPoint(bounds, cgPt)) continue;
        NSInteger layer = [w[(__bridge NSString *)kCGWindowLayer] integerValue];
        if (layer > 0) continue;   // system overlay (Dock/menubar) — click-transparent, skip
        return layer < 0;          // first real containing window
    }
    return NO;
}

#pragma mark - Dispatch

- (void)dispatchMouseType:(NSString *)type atPoint:(NSPoint)p {
    NSRect sf = _screen.frame;
    if (NSWidth(sf) <= 0 || NSHeight(sf) <= 0) return;
    double nx = (p.x - sf.origin.x) / NSWidth(sf);
    double ny = 1.0 - (p.y - sf.origin.y) / NSHeight(sf);
    if (nx < 0) nx = 0; if (nx > 1) nx = 1;
    if (ny < 0) ny = 0; if (ny > 1) ny = 1;
    NSString *js = [NSString stringWithFormat:
        @"(function(){var W=window.innerWidth||1,H=window.innerHeight||1;"
        "window.__wr_dispatchMouse('%@', %f*W, %f*H);})();", type, nx, ny];
    [_webView evaluateJavaScript:js completionHandler:nil];
}

- (void)handleMouseDown:(NSEvent *)e {
    (void)e;
    NSPoint p = NSEvent.mouseLocation;
    if (!NSPointInRect(p, _screen.frame)) return;
    BOOL desktop = [self pointIsOnDesktop:p];
    if (getenv("WR_DEBUG")) {
        fprintf(stderr, "WebRenderer click: (%.0f,%.0f) desktop=%d → %s\n",
                p.x, p.y, desktop ? 1 : 0, desktop ? "forwarded" : "ignored");
    }
    if (!desktop) return;   // app window / Dock / menubar → owner handles
    [self dispatchMouseType:@"click" atPoint:p];
}

- (void)handleMouseMove:(NSEvent *)e {
    (void)e;
    NSPoint p = NSEvent.mouseLocation;
    if (NSEqualPoints(p, _lastMovePos)) return;
    _lastMovePos = p;
    if (NSPointInRect(p, _screen.frame) && [self pointIsOnDesktop:p]) {
        [self dispatchMouseType:@"mousemove" atPoint:p];
    }
}

@end
