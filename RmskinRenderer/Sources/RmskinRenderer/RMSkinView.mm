#import "RMSkinView.h"
#import "RMSkin.h"
#import "RMLog.h"

@implementation RMSkinView {
    NSTimer *_timer;
    NSPoint _dragStartInWindow;
    NSPoint _windowStartOrigin;
    BOOL    _dragged;
    NSSize  _lastContentSize;
    BOOL    _hasPerformedInitialLayout;
}

- (instancetype)initWithSkin:(RMSkin *)skin {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 100, 100)])) {
        _skin = skin;
        _draggable = YES;
        __weak RMSkinView *weakSelf = self;
        skin.onNeedsRedraw = ^{ weakSelf.needsDisplay = YES; };
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }

- (void)start {
    [self.skin tick];
    [self resizeToContent];
    self.needsDisplay = YES;

    NSTimeInterval interval = self.skin.updateInterval > 0 ? self.skin.updateInterval : 1.0;
    _timer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *t) {
        [self.skin tick];
        [self resizeToContent];
        self.needsDisplay = YES;
    }];
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
}

- (void)resizeToContent {
    NSSize cs = self.skin.contentSize;
    // Skip only if the size literally hasn't changed AND we've already
    // performed the initial layout. On the first pass, always position
    // the window, even when cs == {0,0}, so percentage/anchor placements
    // take effect and the window lands at its designated spot.
    if (NSEqualSizes(cs, _lastContentSize) && _hasPerformedInitialLayout) return;
    _lastContentSize = cs;
    _hasPerformedInitialLayout = YES;

    NSWindow *win = self.window;
    if (win) {
        NSRect frame = win.frame;
        NSRect newFrame;

        if (self.hasDesiredPosition && !NSIsEmptyRect(self.targetScreenFrame)) {
            // Interpret desiredScreenTopLeft as: the widget's anchor point
            // (anchorFracX * w, anchorFracY * h, measured from widget's top-
            // left) should be placed exactly here on the screen. Coordinates
            // are AppKit (bottom-left origin); .y is the "top edge" line the
            // widget's top-left will sit at when anchor is (0,0).
            CGFloat topLeftScreenX = self.desiredScreenTopLeft.x - self.anchorFracX * cs.width;
            CGFloat topLeftScreenY = self.desiredScreenTopLeft.y + self.anchorFracY * cs.height;
            // AppKit window origin is the bottom-left corner.
            CGFloat originX = topLeftScreenX;
            CGFloat originY = topLeftScreenY - cs.height;
            newFrame = NSMakeRect(originX, originY, cs.width, cs.height);

            // Force fully-on-screen. Widget shall never sit off-screen; if
            // the requested position pushes it out, clamp into the target
            // screen with a small edge margin.
            NSRect sf = self.targetScreenFrame;
            CGFloat margin = 20;
            CGFloat minX = NSMinX(sf) + margin;
            CGFloat maxX = NSMaxX(sf) - cs.width - margin;
            CGFloat minY = NSMinY(sf) + margin;
            CGFloat maxY = NSMaxY(sf) - cs.height - margin;
            if (maxX < minX) maxX = minX;
            if (maxY < minY) maxY = minY;
            newFrame.origin.x = MIN(MAX(newFrame.origin.x, minX), maxX);
            newFrame.origin.y = MIN(MAX(newFrame.origin.y, minY), maxY);
        } else {
            // No layout position: keep the top edge fixed while the height
            // changes, so the widget grows downwards from its current spot.
            CGFloat top = NSMaxY(frame);
            newFrame = NSMakeRect(frame.origin.x, top - cs.height, cs.width, cs.height);
        }

        [win setFrame:newFrame display:YES];
    }
    self.frame = NSMakeRect(0, 0, cs.width, cs.height);
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);
    [self.skin drawInBounds:self.bounds];
}

#pragma mark - Mouse

- (void)mouseDown:(NSEvent *)event {
    _dragged = NO;
    _dragStartInWindow = [event locationInWindow];
    _windowStartOrigin = self.window.frame.origin;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_draggable) return;
    NSPoint now = [event locationInWindow];
    // locationInWindow is relative to the (moving) window; use screen delta.
    NSPoint screenNow = [self.window convertPointToScreen:now];
    NSPoint screenStart = [self.window convertPointToScreen:_dragStartInWindow];
    CGFloat dx = screenNow.x - screenStart.x;
    CGFloat dy = screenNow.y - screenStart.y;
    if (fabs(dx) > 2 || fabs(dy) > 2) _dragged = YES;
    NSRect f = self.window.frame;
    f.origin = NSMakePoint(_windowStartOrigin.x + dx, _windowStartOrigin.y + dy);
    [self.window setFrameOrigin:f.origin];
}

- (void)mouseUp:(NSEvent *)event {
    if (_dragged) return;
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    [self.skin handleMouseUpAt:p rightButton:NO];
}

- (void)rightMouseUp:(NSEvent *)event {
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    [self.skin handleMouseUpAt:p rightButton:YES];
}

- (void)scrollWheel:(NSEvent *)event {
    if (event.deltaY > 0) [self.skin handleScrollUp:YES];
    else if (event.deltaY < 0) [self.skin handleScrollUp:NO];
}

@end
