#import "WRDesktopInputForwarder.h"

#import <CoreGraphics/CoreGraphics.h>

// Full mouse gesture forwarding: monitors LeftMouseDown, LeftMouseDragged,
// LeftMouseUp, and MouseMoved. On the desktop we synthesize mousedown ->
// mousemove (with buttons:1) -> mouseup + click so web wallpapers that rely
// on drag gestures (e.g. gallery) work correctly.

@implementation WRDesktopInputForwarder {
    WKWebView *_webView;
    NSScreen  *_screen;
    id _mouseDownMonitor;
    id _mouseDragMonitor;
    id _mouseUpMonitor;
    id _mouseMoveMonitor;
    NSPoint _lastMovePos;
    BOOL _dragging;        // between mousedown and mouseup on the desktop
    NSPoint _downPoint;    // where the gesture started
}

- (instancetype)initWithWebView:(WKWebView *)webView screen:(NSScreen *)screen {
    self = [super init];
    if (self) {
        _webView = webView;
        _screen = screen;
        _lastMovePos = NSMakePoint(-1, -1);
        _dragging = NO;
    }
    return self;
}

- (void)start {
    if (_mouseDownMonitor) return;

    _mouseDownMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
        NSEventMaskLeftMouseDown handler:^(NSEvent *e) { [self handleMouseDown:e]; }];
    _mouseDragMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
        NSEventMaskLeftMouseDragged handler:^(NSEvent *e) { [self handleMouseDragged:e]; }];
    _mouseUpMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
        NSEventMaskLeftMouseUp handler:^(NSEvent *e) { [self handleMouseUp:e]; }];
    _mouseMoveMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
        NSEventMaskMouseMoved handler:^(NSEvent *e) { [self handleMouseMove:e]; }];

    if (getenv("WR_DEBUG")) {
        fprintf(stderr, "WebRenderer: input forwarder started (global monitors), screen=%.0fx%.0f\n",
                _screen.frame.size.width, _screen.frame.size.height);
    }
}

- (void)stop {
    if (_mouseDownMonitor) { [NSEvent removeMonitor:_mouseDownMonitor]; _mouseDownMonitor = nil; }
    if (_mouseDragMonitor) { [NSEvent removeMonitor:_mouseDragMonitor]; _mouseDragMonitor = nil; }
    if (_mouseUpMonitor)   { [NSEvent removeMonitor:_mouseUpMonitor];   _mouseUpMonitor = nil; }
    if (_mouseMoveMonitor) { [NSEvent removeMonitor:_mouseMoveMonitor]; _mouseMoveMonitor = nil; }
    _dragging = NO;
}

#pragma mark - Desktop hit detection

- (BOOL)pointIsOnDesktop:(NSPoint)p {
    CFArrayRef arr = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (arr == NULL) return NO;
    NSArray *windows = CFBridgingRelease(arr);
    CGFloat screenH = NSHeight(_screen.frame);
    CGPoint cgPt = CGPointMake((CGFloat)p.x, screenH - (CGFloat)p.y);
    for (NSDictionary *w in windows) {
        CGRect bounds = CGRectZero;
        NSDictionary *b = w[(__bridge NSString *)kCGWindowBounds];
        if (b) CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)b, &bounds);
        if (!CGRectContainsPoint(bounds, cgPt)) continue;
        NSInteger layer = [w[(__bridge NSString *)kCGWindowLayer] integerValue];
        if (layer > 0) continue;
        return layer < 0;
    }
    return NO;
}

#pragma mark - Dispatch

- (void)dispatchMouseType:(NSString *)type atPoint:(NSPoint)p buttons:(int)buttons {
    NSRect sf = _screen.frame;
    if (NSWidth(sf) <= 0 || NSHeight(sf) <= 0) return;
    double nx = (p.x - sf.origin.x) / NSWidth(sf);
    double ny = 1.0 - (p.y - sf.origin.y) / NSHeight(sf);
    if (nx < 0) nx = 0; if (nx > 1) nx = 1;
    if (ny < 0) ny = 0; if (ny > 1) ny = 1;
    NSString *js = [NSString stringWithFormat:
        @"(function(){var W=window.innerWidth||1,H=window.innerHeight||1;"
        "window.__wr_dispatchMouse('%@', %f*W, %f*H, %d);})();", type, nx, ny, buttons];
    [_webView evaluateJavaScript:js completionHandler:nil];
}

#pragma mark - Event handlers

- (void)handleMouseDown:(NSEvent *)e {
    (void)e;
    NSPoint p = NSEvent.mouseLocation;
    if (!NSPointInRect(p, _screen.frame)) return;
    BOOL desktop = [self pointIsOnDesktop:p];
    if (getenv("WR_DEBUG")) {
        fprintf(stderr, "WebRenderer mousedown: (%.0f,%.0f) desktop=%d\n",
                p.x, p.y, desktop ? 1 : 0);
    }
    if (!desktop) return;
    _dragging = YES;
    _downPoint = p;
    [self dispatchMouseType:@"mousedown" atPoint:p buttons:1];
}

- (void)handleMouseDragged:(NSEvent *)e {
    (void)e;
    if (!_dragging) return;
    NSPoint p = NSEvent.mouseLocation;
    if (!NSPointInRect(p, _screen.frame)) return;
    [self dispatchMouseType:@"mousemove" atPoint:p buttons:1];
}

- (void)handleMouseUp:(NSEvent *)e {
    (void)e;
    if (!_dragging) return;
    _dragging = NO;
    NSPoint p = NSEvent.mouseLocation;
    if (!NSPointInRect(p, _screen.frame)) return;
    [self dispatchMouseType:@"mouseup" atPoint:p buttons:0];
    // Also fire click if the release is close to the press point (< 5px drift).
    double dx = p.x - _downPoint.x;
    double dy = p.y - _downPoint.y;
    if (dx * dx + dy * dy < 25.0) {
        [self dispatchMouseType:@"click" atPoint:p buttons:0];
    }
}

- (void)handleMouseMove:(NSEvent *)e {
    (void)e;
    if (_dragging) return; // dragged events handle this case
    NSPoint p = NSEvent.mouseLocation;
    if (NSEqualPoints(p, _lastMovePos)) return;
    _lastMovePos = p;
    if (NSPointInRect(p, _screen.frame) && [self pointIsOnDesktop:p]) {
        [self dispatchMouseType:@"mousemove" atPoint:p buttons:0];
    }
}

@end
