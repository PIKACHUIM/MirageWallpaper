// WebViewer — standalone debug window for a Wallpaper Engine web wallpaper.
// Counterpart to OWE's viewer/WebViewer.cpp (GLFW + CEF + Vulkan presenter).
// Here: NSWindow + WKWebView (the engine's webView is the content view).
//
// Usage:
//   WebViewer <wallpaper-dir> [--width W] [--height H] [--fps N]
//             [--volume 0..1] [--no-spectrum] [--diag] [--remote-debugging-port N]

#import <AppKit/AppKit.h>

#import "WallpaperManifest.h"
#import "WebRendererEngine.h"

struct ViewerArgs {
    const char *workshop = nullptr;
    int   width  = 1280;
    int   height = 720;
    int   fps    = 60;
    float volume = 1.0f;
    BOOL  spectrum = YES;
    BOOL  inspector = YES;
    BOOL  diag = NO;
};

static void PrintUsage(const char *argv0) {
    fprintf(stderr,
        "Usage: %s <wallpaper-dir> [options]\n\n"
        "Options:\n"
        "  --width N              window width  (default 1280)\n"
        "  --height N             window height (default 720)\n"
        "  --fps N                target frame rate (default 60)\n"
        "  --volume 0..1          master volume (default 1.0)\n"
        "  --no-spectrum          disable audio-spectrum capture\n"
        "  --diag                 after load, print page state (ready/listener/spine)\n"
        "  --remote-debugging-port N  enable Safari Web Inspector (kept for\n"
        "                          OWE CLI compat; the port itself is unused)\n"
        "  -h, --help             show this help\n",
        argv0);
}

static BOOL ParseArgs(int argc, char **argv, ViewerArgs &out) {
    for (int i = 1; i < argc; ++i) {
        const char *arg = argv[i];
        auto take = [&](int &i, const char *opt) -> const char * {
            if (i + 1 >= argc) { fprintf(stderr, "%s requires a value\n", opt); return nullptr; }
            return argv[++i];
        };
        if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
            PrintUsage(argv[0]); return false;
        } else if (strcmp(arg, "--width") == 0) {
            const char *v = take(i, arg); if (!v) return false; out.width = atoi(v);
        } else if (strcmp(arg, "--height") == 0) {
            const char *v = take(i, arg); if (!v) return false; out.height = atoi(v);
        } else if (strcmp(arg, "--fps") == 0) {
            const char *v = take(i, arg); if (!v) return false; out.fps = atoi(v);
        } else if (strcmp(arg, "--volume") == 0) {
            const char *v = take(i, arg); if (!v) return false; out.volume = strtof(v, nullptr);
        } else if (strcmp(arg, "--no-spectrum") == 0) {
            out.spectrum = NO;
        } else if (strcmp(arg, "--diag") == 0) {
            out.diag = YES;
        } else if (strcmp(arg, "--remote-debugging-port") == 0) {
            const char *v = take(i, arg); if (!v) return false; // value ignored
            out.inspector = YES;
        } else if (arg[0] == '-') {
            fprintf(stderr, "unknown option: %s\n", arg); return false;
        } else {
            if (out.workshop == nullptr) out.workshop = arg;
            else { fprintf(stderr, "unexpected positional argument: %s\n", arg); return false; }
        }
    }
    if (out.workshop == nullptr) { PrintUsage(argv[0]); return false; }
    if (out.width  < 64) out.width  = 64;
    if (out.height < 64) out.height = 64;
    if (out.fps < 0) out.fps = 0;
    if (out.volume < 0.0f) out.volume = 0.0f;
    if (out.volume > 1.0f) out.volume = 1.0f;
    return true;
}

@interface WebViewerAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WebRendererEngine *engine;
@end
@implementation WebViewerAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender; return YES;
}
@end

// Minimal menu so Cmd+Q / Reload work. `reloadTarget` gets the Reload action.
static void InstallMainMenu(NSString *appName, NSResponder *reloadTarget) {
    NSMenu *bar = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:appName action:NULL keyEquivalent:@""];
    [bar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:appName];
    [appMenu addItemWithTitle:[NSString stringWithFormat:@"About %@", appName]
                       action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:@"Hide %@", appName]
                       action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[NSString stringWithFormat:@"Quit %@", appName]
                       action:@selector(terminate:) keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];

    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:NULL keyEquivalent:@""];
    [bar addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *reload = [[NSMenuItem alloc] initWithTitle:@"Reload"
                                                    action:@selector(reload) keyEquivalent:@"r"];
    [reload setTarget:reloadTarget];
    [viewMenu addItem:reload];
    [viewItem setSubmenu:viewMenu];

    [NSApp setMainMenu:bar];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        ViewerArgs args;
        if (!ParseArgs(argc, argv, args)) return 1;

        NSError *manifestErr = nil;
        WRManifest *manifest = [WRManifest loadFromDirectory:@(args.workshop) error:&manifestErr];
        if (manifest == nil) {
            fprintf(stderr, "WebViewer: %s\n",
                    manifestErr.localizedDescription.UTF8String ?: "failed to load project.json");
            return 2;
        }

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        WebViewerAppDelegate *delegate = [WebViewerAppDelegate new];
        [app setDelegate:delegate];
        [app finishLaunching];

        WREngineConfig cfg = [WebRendererEngine defaultConfig];
        cfg.enableInspector = args.inspector;
        cfg.enableAudioSpectrum = args.spectrum;
        cfg.initialVolume = args.volume;
        cfg.frameRate = args.fps;

        NSRect frame = NSMakeRect(0, 0, args.width, args.height);
        WebRendererEngine *engine = [[WebRendererEngine alloc] initWithFrame:frame config:cfg];
        delegate.engine = engine;
        InstallMainMenu(manifest.title.length ? manifest.title : @"WebViewer", engine.webView);

        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:style
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.title = manifest.title.length ? manifest.title : @"WebViewer";
        window.backgroundColor = NSColor.blackColor;
        window.contentView = engine.webView;
        engine.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [window center];
        [window makeKeyAndOrderFront:nil];
        delegate.window = window;

        [engine openWallpaper:manifest];
        [engine startAudioSpectrum];

        if (args.diag) {
            WKWebView *dw = engine.webView;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                NSString *js = @"(function(){"
                    "console.log('WebRenderer diag ping');"
                    "var pc = document.querySelector('#player-container');"
                    "var xhrOk='n/a',xhrStatus=0,xhrLen=0;"
                    "try{var x=new XMLHttpRequest();x.open('GET','image/c511_01_00.atlas',false);x.send();"
                    "xhrStatus=x.status;xhrOk=(x.status===200||x.status===206);xhrLen=(x.responseText||'').length;"
                    "}catch(e){xhrOk='throw:'+e;}"
                    "var rp=window.reproductor,am=rp&&rp.assetManager;"
                    "var errs=am?am.getErrors():null,errCount=(errs&&errs.length)||0;"
                    "return JSON.stringify({"
                    "ready:document.readyState,"
                    "listener:!!(window.wallpaperPropertyListener&&window.wallpaperPropertyListener.applyUserProperties),"
                    "setPaused:!!(window.wallpaperPropertyListener&&window.wallpaperPropertyListener.setPaused),"
                    "spine41:(typeof spine41!=='undefined'),"
                    "playerCanvas:!!(pc&&pc.querySelector('canvas')),"
                    "atlasXhrOk:xhrOk,atlasXhrStatus:xhrStatus,atlasLen:xhrLen,"
                    "hasReproductor:!!rp,spineLoadComplete:am?!!am.isLoadingComplete():'no-am',"
                    "spineErrors:errCount,errorDom:!!document.querySelector('.spine-player-error'),"
                    "bgmRegistered:(window.__wr_installed===true),paused:window.wallpaperEngine_paused"
                    "});})();";
                [dw evaluateJavaScript:js completionHandler:^(id result, NSError *err) {
                    if (err) fprintf(stderr, "WebRenderer DIAG err: %s\n", err.localizedDescription.UTF8String ?: "?");
                    else fprintf(stderr, "WebRenderer DIAG: %s\n",
                                 [result isKindOfClass:[NSString class]] ? [result UTF8String] : "(no result)");
                }];
            });
        }

        [app activateIgnoringOtherApps:YES];
        [app run];

        [engine stopAudioSpectrum];
    }
    return 0;
}
