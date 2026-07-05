#import "WebRendererEngine.h"
#import "WallpaperManifest.h"
#import "WRAudioTap.h"
#import "WRURLSchemeHandler.h"

#import <WebKit/WebKit.h>

// WE JS API shim, installed at document-start (≈ CEF OnContextCreated).
// Engine entrypoints (called via evaluateJavaScript):
//   __wr_applyProps(obj)   → wallpaperPropertyListener.applyUserProperties
//   __wr_setPaused(bool)   → wallpaperPropertyListener.setPaused + state
//   __wr_setFps(int)       → requestAnimationFrame throttle
//   __wr_applyMute(bool)   → registered audio streams .muted
//   __wr_pauseStreams()    → registered audio streams .pause()
//   __wr_resumeStreams()   → resume streams the host paused
//   __wr_pushAudio([128])  → wallpaperRegisterAudioListener callbacks
static NSString *const kShimJS = @"\
(function(){\
  if (window.__wr_installed) return;\
  window.__wr_installed = true;\
  /* Chrome-compat: many WE wallpapers were authored against Chromium and \
     feature-sniff for window.chrome. WebKit lacks it; stub it. */\
  try { window.chrome = window.chrome || { runtime: {} }; } catch(e) {}\
  window.wallpaperEngine_paused = false;\
  var __streams = [];\
  window.wallpaperRegisterAudioStream = function(el){\
    if (el && __streams.indexOf(el) < 0) __streams.push(el);\
    return el;\
  };\
  window.wallpaperRemoveAudioStream = function(el){\
    var i = __streams.indexOf(el); if (i >= 0) __streams.splice(i,1);\
  };\
  window.__wr_applyMute = function(m){\
    for (var i=0;i<__streams.length;i++){ try { __streams[i].muted = !!m; } catch(e){} }\
  };\
  window.__wr_pauseStreams = function(){\
    for (var i=0;i<__streams.length;i++){\
      try {\
        var s = __streams[i];\
        if (!s.paused) { s.__wr_wasPlaying = true; s.pause(); }\
        else s.__wr_wasPlaying = false;\
      } catch(e){}\
    }\
  };\
  window.__wr_resumeStreams = function(){\
    for (var i=0;i<__streams.length;i++){\
      try {\
        var s = __streams[i];\
        if (s.__wr_wasPlaying) { s.__wr_wasPlaying = false; var p = s.play(); if (p && p.catch) p.catch(function(){}); }\
      } catch(e){}\
    }\
  };\
  var __listeners = [];\
  window.wallpaperRegisterAudioListener = function(cb){\
    if (typeof cb === 'function') __listeners.push(cb);\
  };\
  window.wallpaperRemoveAudioListener = function(cb){\
    var i = __listeners.indexOf(cb); if (i >= 0) __listeners.splice(i,1);\
  };\
  window.__wr_pushAudio = function(arr){\
    for (var i=0;i<__listeners.length;i++){ try { __listeners[i](arr); } catch(e){} }\
  };\
  /* Capture native rAF before the page can override it; wrap it when fps<60. */\
  window.__wr_nativeRaf = (window.requestAnimationFrame || function(cb){return setTimeout(function(){cb(performance.now());},16);}).bind(window);\
  window.__wr_setFps = function(fps){\
    if (!isFinite(fps) || fps <= 0 || fps >= 60) { window.requestAnimationFrame = window.__wr_nativeRaf; return; }\
    var interval = 1000 / fps, last = 0;\
    window.requestAnimationFrame = function(cb){\
      var now = performance.now();\
      if (interval - (now - last) <= 0) { last = now; return window.__wr_nativeRaf(function(t){ cb(t); }); }\
      return window.__wr_nativeRaf(function(t){\
        if (performance.now() - last >= interval) { last = performance.now(); cb(t); }\
        else { window.requestAnimationFrame(cb); }\
      });\
    };\
  };\
  window.__wr_applyProps = function(props){\
    try {\
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.applyUserProperties === 'function')\
        window.wallpaperPropertyListener.applyUserProperties(props);\
    } catch(e){ console.error('WebRenderer applyUserProperties:', e); }\
  };\
  window.__wr_setPaused = function(p){\
    window.wallpaperEngine_paused = !!p;\
    try {\
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.setPaused === 'function')\
        window.wallpaperPropertyListener.setPaused(!!p);\
    } catch(e){ console.error('WebRenderer setPaused:', e); }\
  };\
  /* Synthetic mouse-event dispatch — used by WRDesktopInputForwarder to feed \
     the page real desktop clicks/moves (the wallpaper window sits below \
     Finder's desktop window and never receives them directly). */\
  window.__wr_dispatchMouse = function(type, x, y){\
    try {\
      var el = document.elementFromPoint(x, y) || document.body;\
      el.dispatchEvent(new MouseEvent(type, {\
        bubbles: true, cancelable: true, view: window, clientX: x, clientY: y\
      }));\
    } catch(e){ console.error('WebRenderer dispatchMouse:', e); }\
  };\
  /* Pipe console.* to native (≈ OWE ClientHandler::OnConsoleMessage). */\
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wrConsole) {\
    var __oc = window.console || {};\
    var __wrap = function(level, orig){\
      return function(){\
        try {\
          var args = Array.prototype.slice.call(arguments);\
          var msg = args.map(function(a){\
            try { return (typeof a === 'object') ? JSON.stringify(a) : String(a); } catch(e){ return String(a); }\
          }).join(' ');\
          window.webkit.messageHandlers.wrConsole.postMessage({type: level, message: msg});\
        } catch(e){}\
        if (typeof orig === 'function') { try { orig.apply(window.console, args); } catch(e){} }\
      };\
    };\
    window.console = {\
      log: __wrap('log', __oc.log), info: __wrap('info', __oc.info),\
      warn: __wrap('warn', __oc.warn), error: __wrap('error', __oc.error),\
      debug: __wrap('debug', __oc.debug)\
    };\
    window.onerror = function(msg, src, line, col){\
      try { window.webkit.messageHandlers.wrConsole.postMessage({type:'error', message:'onerror: '+msg+' ('+src+':'+line+':'+col+')'}); } catch(e){}\
      return false;\
    };\
  }\
})();";

static NSString *const kDefaultUserAgent =
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
     "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

@interface WebRendererEngine () <WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) WRAudioTap *audioTap;
@property (nonatomic, strong) NSTimer *audioTimer;
@property (nonatomic, strong) WRManifest *manifest;
@property (nonatomic, strong) WRURLSchemeHandler *schemeHandler;
@property (nonatomic, assign) BOOL didFinishLoad;
@property (nonatomic, strong) NSMutableArray<NSString *> *pendingJS;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign) BOOL muted;
@end

@implementation WebRendererEngine {
    WREngineConfig _config;
}

+ (WREngineConfig)defaultConfig {
    WREngineConfig c;
    c.enableInspector = YES;
    c.enableAudioSpectrum = YES;
    c.enableAudioPlayback = YES;
    c.initialVolume = 1.0f;
    c.frameRate = 60;
    c.userAgent = nil;
    return c;
}

- (instancetype)initWithFrame:(NSRect)frame config:(WREngineConfig)config {
    self = [super init];
    if (self) {
        _config = config;
        _pendingJS = [NSMutableArray array];
        _volume = config.initialVolume;
        _muted = (config.initialVolume <= 0.0f);
        _audioTap = [[WRAudioTap alloc] init];
        [self setupWebViewWithFrame:frame];
    }
    return self;
}

- (void)setupWebViewWithFrame:(NSRect)frame {
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    WKUserContentController *ucc = [WKUserContentController new];
    WKUserScript *shim = [[WKUserScript alloc] initWithSource:kShimJS
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:YES];
    [ucc addUserScript:shim];
    [ucc addScriptMessageHandler:self name:@"wrConsole"];
    cfg.userContentController = ucc;
    cfg.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    cfg.suppressesIncrementalRendering = NO;
    if (_config.enableAudioPlayback) {
        cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    }

    // Custom scheme = the WKWebView equivalent of CEF's --allow-file-access-from-files.
    _schemeHandler = [WRURLSchemeHandler new];
    [cfg setURLSchemeHandler:_schemeHandler forURLScheme:@"we-wallpaper"];

    _webView = [[WKWebView alloc] initWithFrame:frame configuration:cfg];
    _webView.navigationDelegate = self;
    _webView.customUserAgent = (_config.userAgent.length > 0) ? _config.userAgent : kDefaultUserAgent;
    if (@available(macOS 13.0, *)) {
        _webView.inspectable = _config.enableInspector ? YES : NO;
    }
    _webView.configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
}

#pragma mark - Open wallpaper

- (void)openWallpaper:(WRManifest *)manifest {
    _manifest = manifest;
    _didFinishLoad = NO;
    [_pendingJS removeAllObjects];

    _schemeHandler.baseDirectory = manifest.workshopDir;
    NSString *entry = manifest.entryHTML ?: @"index.html";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"we-wallpaper://wallpaper/%@", entry]];
    fprintf(stderr, "WebRenderer: loading %s\n", entry.UTF8String ?: "index.html");
    [_webView loadRequest:[NSURLRequest requestWithURL:url]];
}

#pragma mark - JS helpers

- (NSString *)jsLiteralForObject:(id)obj {
    if (obj == nil || obj == [NSNull null]) return @"null";
    if ([obj isKindOfClass:[NSString class]]) {
        NSData *d = [NSJSONSerialization dataWithJSONObject:@[obj] options:0 error:nil];
        if (d == nil) return @"null";
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        return [s substringWithRange:NSMakeRange(1, s.length - 2)];
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        if (strcmp([obj objCType], @encode(BOOL)) == 0 ||
            strcmp([obj objCType], @encode(bool)) == 0) {
            return [obj boolValue] ? @"true" : @"false";
        }
        return [obj description];
    }
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null";
}

// Evaluate now if loaded, else queue and replay on didFinishNavigation.
- (void)eval:(NSString *)script {
    if (_didFinishLoad) {
        [_webView evaluateJavaScript:script completionHandler:nil];
    } else {
        [_pendingJS addObject:script];
    }
}

- (void)flushPendingJS {
    NSArray *pending = [_pendingJS copy];
    [_pendingJS removeAllObjects];
    for (NSString *s in pending) {
        [_webView evaluateJavaScript:s completionHandler:nil];
    }
}

#pragma mark - WE API

- (void)applyAllUserProperties {
    NSString *json = _manifest.userPropertiesJSON ?: @"{}";
    [self eval:[NSString stringWithFormat:@"__wr_applyProps(%@);", json]];
}

- (void)applyUserProperty:(NSString *)key value:(id)value {
    NSString *valLit = [self jsLiteralForObject:value];
    [self eval:[NSString stringWithFormat:@"__wr_applyProps({\"%@\":%@});", key, valLit]];
}

- (void)setPaused:(BOOL)paused {
    [self eval:[NSString stringWithFormat:@"__wr_setPaused(%@);", paused ? @"true" : @"false"]];
    [self eval:paused ? @"__wr_pauseStreams();" : @"__wr_resumeStreams();"];
}

- (void)setVolume:(float)volume {
    _volume = volume;
    _muted = (volume <= 0.0f);
    [self applyUserProperty:@"audio" value:@{@"value": @(volume)}];
    [self eval:[NSString stringWithFormat:@"__wr_applyMute(%@);", _muted ? @"true" : @"false"]];
}

- (void)setFrameRate:(int)fps {
    [self eval:[NSString stringWithFormat:@"__wr_setFps(%d);", fps]];
}

#pragma mark - Audio spectrum

- (void)startAudioSpectrum {
    if (!_config.enableAudioSpectrum || _audioTimer != nil) return;
    __weak WebRendererEngine *weakSelf = self;
    [_audioTap startWithCompletion:^(BOOL ok, NSString *msg) {
        __strong WebRendererEngine *s = weakSelf;
        if (!s) return;
        if (!ok) {
            fprintf(stderr, "WebRenderer: audio spectrum disabled (%s)\n",
                    msg ? msg.UTF8String : "unknown");
            return;
        }
        if (getenv("WR_DEBUG")) {
            fprintf(stderr, "WebRenderer: audio spectrum tap running\n");
        }
        s->_audioTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES
            block:^(NSTimer *t) { (void)t; [s tickAudio]; }];
        [[NSRunLoop mainRunLoop] addTimer:s->_audioTimer forMode:NSRunLoopCommonModes];
    }];
}

- (void)stopAudioSpectrum {
    [_audioTimer invalidate];
    _audioTimer = nil;
    [_audioTap stop];
}

- (void)tickAudio {
    float bins[64];
    if (![_audioTap copySpectrum:bins count:64]) return;

    // WE contract: 128 floats — [0..63]=L, [64..127]=R. Mono source duplicated
    // into both halves (matches OWE's WebViewer with wavsen's mono output).
    NSMutableString *arr = [NSMutableString stringWithCapacity:128 * 8];
    [arr appendString:@"__wr_pushAudio(["];
    char buf[32];
    for (int i = 0; i < 64; ++i) {
        if (i) [arr appendString:@","];
        snprintf(buf, sizeof(buf), "%.4f", bins[i]);
        [arr appendFormat:@"%s", buf];
    }
    for (int i = 0; i < 64; ++i) {
        [arr appendString:@","];
        snprintf(buf, sizeof(buf), "%.4f", bins[i]);
        [arr appendFormat:@"%s", buf];
    }
    [arr appendString:@"]);"];
    [_webView evaluateJavaScript:arr completionHandler:nil];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView; (void)navigation;
    _didFinishLoad = YES;
    fprintf(stderr, "WebRenderer: navigation finished; injecting user properties\n");

    // WE order: properties → audio volume → frame rate.
    [self applyAllUserProperties];
    if (_config.initialVolume < 1.0f || _muted) {
        [self setVolume:_volume];
    }
    if (_config.frameRate > 0 && _config.frameRate < 60) {
        [self setFrameRate:_config.frameRate];
    }
    [self flushPendingJS];
}

- (void)webView:(WKWebView *)webView
        decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                        decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    (void)webView;
    NSString *scheme = navigationAction.request.URL.scheme.lowercaseString;
    // Allow our scheme + local/about/data; cancel external page-level nav so a
    // wallpaper can't yank the window off to the web. Sub-resources unaffected.
    if ([scheme isEqualToString:@"we-wallpaper"] || [scheme isEqualToString:@"file"] ||
        [scheme isEqualToString:@"about"] || [scheme isEqualToString:@"data"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    fprintf(stderr, "WebRenderer: blocked external navigation to %s\n",
            navigationAction.request.URL.absoluteString.UTF8String ?: "");
    decisionHandler(WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView; (void)navigation;
    fprintf(stderr, "WebRenderer: navigation failed: %s\n", error.localizedDescription.UTF8String ?: "");
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView; (void)navigation;
    fprintf(stderr, "WebRenderer: provisional load failed: %s\n", error.localizedDescription.UTF8String ?: "");
}

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)ucc;
    if (![message.name isEqualToString:@"wrConsole"]) return;
    NSDictionary *body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
    NSString *type = body[@"type"] ?: @"log";
    NSString *text = body[@"message"] ?: @"";
    fprintf(stderr, "WebRenderer [%s] %s\n", type.UTF8String ?: "log", text.UTF8String ?: "");
}

@end
