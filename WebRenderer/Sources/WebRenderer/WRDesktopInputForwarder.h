#pragma once

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

// WRDesktopInputForwarder — feeds real desktop mouse events to a wallpaper
// that sits BELOW Finder's desktop window.
//
// Problem: on macOS a borderless wallpaper window placed just under the
// desktop-icon layer is also below Finder's full-screen desktop window, which
// absorbs every desktop click (icons + empty desktop). The wallpaper renders
// fine but never sees the mouse, so click-interactive web wallpapers
// (e.g. 菠萝菠萝's click-to-trigger-animation) are dead.
//
// Fix: keep the wallpaper window below Finder (icons stay fully clickable) and
// observe the mouse GLOBALLY instead. On each desktop click we:
//   1. confirm the click landed on the desktop (no app/Dock/menubar window
//      is on top at that point);
//   2. confirm it did NOT land on a desktop icon (icon rects queried from
//      Finder via AppleScript, cached + refreshed);
//   3. otherwise synthesize a MouseEvent on the page at the matching point
//      via __wr_dispatchMouse. Icon clicks and app-window clicks are left
//      untouched so Finder / the app handles them normally.
//
// Mouse-moved events over the desktop are forwarded too (for parallax-style
// wallpapers). Drag is intentionally NOT forwarded — left-drag on empty
// desktop stays Finder's rubber-band selection.
@interface WRDesktopInputForwarder : NSObject

- (instancetype)initWithWebView:(WKWebView *)webView screen:(NSScreen *)screen NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
