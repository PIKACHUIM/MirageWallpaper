#import "RMSkin.h"
#import "RMConfigParser.h"
#import "RMMeasure.h"
#import "RMMeter.h"
#import "RMBangs.h"
#import "RMFontManager.h"
#import "RMLog.h"

@implementation RMSkin {
    NSString *_skinFile;
    NSString *_resources;
    NSString *_rootConfig;
    NSString *_skinsPath;
    NSString *_config;

    NSMutableArray<RMMeasure *> *_measures;
    NSMutableArray<RMMeter *>   *_meters;
    NSMutableDictionary<NSString *, RMMeasure *> *_measureByName; // UPPER
    NSMutableDictionary<NSString *, RMMeter *>   *_meterByName;   // UPPER

    NSColor  *_bgColor;
    NSImage  *_bgImage;
    int       _backgroundMode;
}

- (nullable instancetype)initWithSkinFile:(NSString *)skinFile
                                resources:(NSString *)resources
                               rootConfig:(NSString *)rootConfig
                                skinsPath:(NSString *)skinsPath
                                   config:(NSString *)config {
    if ((self = [super init])) {
        _skinFile = skinFile;
        _resources = resources;
        _rootConfig = rootConfig;
        _skinsPath = skinsPath;
        _config = config;
        [[RMFontManager shared] registerFontsInDirectory:
            [resources stringByAppendingPathComponent:@"Fonts"]];
        [[RMFontManager shared] registerFontsInDirectory:resources];
        if (![self reload]) return nil;
    }
    return self;
}

#pragma mark - Build

- (BOOL)reload {
    _parser = [RMConfigParser new];
    _parser.resourcesPath = [_resources hasSuffix:@"/"] ? _resources
                                                        : [_resources stringByAppendingString:@"/"];
    _parser.rootConfigPath = _rootConfig;
    _parser.skinsPath = _skinsPath;
    _parser.currentPath = [_skinFile stringByDeletingLastPathComponent];
    _parser.currentConfig = _config;

    __weak RMSkin *weakSelf = self;
    _parser.sectionVariableResolver = ^NSString *(NSString *token) {
        return [weakSelf resolveSectionVariable:token];
    };
    _parser.measureValueResolver = ^BOOL(NSString *name, double *out) {
        return [weakSelf resolveMeasureValue:name into:out];
    };

    if (![_parser loadSkinFile:_skinFile]) {
        RMLogError(@"failed to load skin: %@", _skinFile);
        return NO;
    }

    _measures = [NSMutableArray array];
    _meters = [NSMutableArray array];
    _measureByName = [NSMutableDictionary dictionary];
    _meterByName = [NSMutableDictionary dictionary];

    [self readRainmeterSection];

    for (RMIniSection *section in _parser.ini.sections) {
        NSString *nameUpper = section.name.uppercaseString;
        if ([nameUpper isEqualToString:@"RAINMETER"] ||
            [nameUpper isEqualToString:@"METADATA"] ||
            [nameUpper isEqualToString:@"VARIABLES"]) continue;

        NSString *measureType = [section valueForKey:@"Measure"];
        NSString *meterType   = [section valueForKey:@"Meter"];

        if (measureType.length) {
            RMMeasure *m = [RMMeasure measureWithType:measureType name:section.name parser:_parser];
            if (m) {
                [m readOptions];
                __weak RMSkin *weakSelf = self;
                m.executeAction = ^(NSString *bang) { [weakSelf executeActions:bang]; };
                [_measures addObject:m];
                _measureByName[nameUpper] = m;
            }
        } else if (meterType.length) {
            RMMeter *mt = [RMMeter meterWithType:meterType name:section.name parser:_parser];
            if (mt) {
                [mt readOptions];
                [_meters addObject:mt];
                _meterByName[nameUpper] = mt;
            }
        }
    }

    // Resolve meter → measure bindings.
    for (RMMeter *mt in _meters) {
        NSMutableArray<RMMeasure *> *bound = [NSMutableArray array];
        for (NSString *mn in mt.measureNames) {
            RMMeasure *ms = _measureByName[mn.uppercaseString];
            if (ms) [bound addObject:ms];
        }
        mt.measures = bound;
    }
    return YES;
}

- (void)readRainmeterSection {
    RMConfigParser *cp = _parser;
    int ms = [cp readInt:@"Rainmeter" key:@"Update" default:1000];
    _updateInterval = MAX(ms, 16) / 1000.0;
    _dynamicWindowSize = [cp readBool:@"Rainmeter" key:@"DynamicWindowSize" default:NO];
    _backgroundMode = [cp readInt:@"Rainmeter" key:@"BackgroundMode" default:0];

    NSString *solid = [cp readString:@"Rainmeter" key:@"SolidColor" default:nil];
    _bgColor = nil;
    if (solid.length) {
        NSArray *p = [solid componentsSeparatedByString:@","];
        if (p.count >= 3) {
            CGFloat a = p.count >= 4 ? [p[3] doubleValue] / 255.0 : 1.0;
            _bgColor = [NSColor colorWithSRGBRed:[p[0] doubleValue]/255.0
                                           green:[p[1] doubleValue]/255.0
                                            blue:[p[2] doubleValue]/255.0 alpha:a];
        }
    }
    NSString *bg = [cp readString:@"Rainmeter" key:@"Background" default:nil];
    _bgImage = bg.length ? [[NSImage alloc] initWithContentsOfFile:bg] : nil;

    self.mouseScrollUpAction   = [cp readString:@"Rainmeter" key:@"MouseScrollUpAction"   default:nil];
    self.mouseScrollDownAction = [cp readString:@"Rainmeter" key:@"MouseScrollDownAction" default:nil];
}

#pragma mark - Section variables

- (nullable NSString *)resolveSectionVariable:(NSString *)token {
    NSRange colon = [token rangeOfString:@":"];
    NSString *base = colon.location == NSNotFound ? token : [token substringToIndex:colon.location];
    NSString *sel  = colon.location == NSNotFound ? nil : [token substringFromIndex:colon.location + 1];

    RMMeasure *m = _measureByName[base.uppercaseString];
    if (m) {
        if (sel.length == 0) return [m displayStringAutoScale:NO decimals:-1 percentual:NO scale:1];
        if ([sel isEqualToString:@"%"]) return [m displayStringAutoScale:NO decimals:0 percentual:YES scale:1];
        if ([sel caseInsensitiveCompare:@"MaxValue"] == NSOrderedSame) return [NSString stringWithFormat:@"%g", m.maxValue];
        if ([sel caseInsensitiveCompare:@"MinValue"] == NSOrderedSame) return [NSString stringWithFormat:@"%g", m.minValue];
        if ([sel hasPrefix:@"/"]) { double d = [[sel substringFromIndex:1] doubleValue]; return d != 0 ? [NSString stringWithFormat:@"%g", m.value/d] : @"0"; }
        int dec = [sel intValue];
        return [m displayStringAutoScale:NO decimals:dec percentual:NO scale:1];
    }

    RMMeter *mt = _meterByName[base.uppercaseString];
    if (mt) {
        NSString *s = sel.uppercaseString;
        if ([s isEqualToString:@"X"])  return [NSString stringWithFormat:@"%g", mt.x];
        if ([s isEqualToString:@"Y"])  return [NSString stringWithFormat:@"%g", mt.y];
        if ([s isEqualToString:@"W"])  return [NSString stringWithFormat:@"%g", mt.w];
        if ([s isEqualToString:@"H"])  return [NSString stringWithFormat:@"%g", mt.h];
        if ([s isEqualToString:@"XW"]) return [NSString stringWithFormat:@"%g", mt.x + mt.w];
        if ([s isEqualToString:@"YH"]) return [NSString stringWithFormat:@"%g", mt.y + mt.h];
    }
    return nil;
}

// Resolve a bare measure name used inside a Calc formula to its numeric value.
- (BOOL)resolveMeasureValue:(NSString *)name into:(double *)out {
    RMMeasure *m = _measureByName[name.uppercaseString];
    if (m == nil) return NO;
    if (out) *out = [m numericValue];
    return YES;
}

#pragma mark - Tick / size

- (void)tick {
    for (RMMeasure *m in _measures) [m update];

    RMMeter *prev = nil;
    CGFloat maxX = 0, maxY = 0;
    for (RMMeter *mt in _meters) {
        [mt resetToAuthoredPosition];
        [mt resolvePositionWithPrevious:prev];
        [mt prepare];
        if (!mt.hidden) {
            maxX = MAX(maxX, mt.x + mt.w);
            maxY = MAX(maxY, mt.y + mt.h);
        }
        prev = mt;
    }
    _contentSize = NSMakeSize(ceil(maxX), ceil(maxY));
    if (_contentSize.width < 1) _contentSize.width = 1;
    if (_contentSize.height < 1) _contentSize.height = 1;
}

#pragma mark - Draw

- (void)drawInBounds:(NSRect)bounds {
    if (_bgImage) {
        [_bgImage drawInRect:NSMakeRect(0, 0, _bgImage.size.width, _bgImage.size.height)
                    fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                    fraction:1.0 respectFlipped:YES hints:nil];
    } else if (_bgColor && (_backgroundMode == 1 || _backgroundMode == 0)) {
        if (_bgColor.alphaComponent > 0.004) {
            [_bgColor setFill];
            NSRectFillUsingOperation(NSMakeRect(0, 0, _contentSize.width, _contentSize.height),
                                     NSCompositingOperationSourceOver);
        }
    }
    for (RMMeter *mt in _meters) {
        if (mt.hidden) continue;
        @try { [mt draw]; }
        @catch (NSException *ex) { RMLogWarn(@"meter draw failed %@: %@", mt.name, ex); }
    }
}

#pragma mark - Mouse

- (void)handleMouseUpAt:(NSPoint)point rightButton:(BOOL)rightButton {
    for (RMMeter *mt in _meters.reverseObjectEnumerator) {
        if (mt.hidden) continue;
        if (NSPointInRect(point, mt.frame)) {
            NSString *action = rightButton ? mt.rightMouseUpAction : mt.leftMouseUpAction;
            if (action.length) { [self executeActions:action]; return; }
        }
    }
}

- (void)handleScrollUp:(BOOL)up {
    NSString *a = up ? self.mouseScrollUpAction : self.mouseScrollDownAction;
    if (a.length) [self executeActions:a];
}

#pragma mark - Bangs

- (void)executeActions:(NSString *)actions {
    [RMBangs execute:actions onSkin:self];
}

- (void)setOption:(NSString *)key value:(NSString *)value forSection:(NSString *)section {
    RMIniSection *s = [_parser.ini ensureSectionNamed:section];
    [s setValue:value forKey:key overwrite:YES];
    RMMeter *mt = _meterByName[section.uppercaseString];
    if (mt) { [mt readOptions]; [self rebindMeter:mt]; return; }
    RMMeasure *ms = _measureByName[section.uppercaseString];
    if (ms) { [ms readOptions]; }
}

- (void)rebindMeter:(RMMeter *)mt {
    NSMutableArray<RMMeasure *> *bound = [NSMutableArray array];
    for (NSString *mn in mt.measureNames) {
        RMMeasure *ms = _measureByName[mn.uppercaseString];
        if (ms) [bound addObject:ms];
    }
    mt.measures = bound;
}

- (void)requestRedraw { if (self.onNeedsRedraw) self.onNeedsRedraw(); }

#pragma mark - Lookups / accessors

- (NSArray<RMMeasure *> *)measures { return _measures; }
- (NSArray<RMMeter *> *)meters { return _meters; }
- (nullable RMMeter *)meterNamed:(NSString *)name { return _meterByName[name.uppercaseString]; }
- (nullable RMMeasure *)measureNamed:(NSString *)name { return _measureByName[name.uppercaseString]; }

@end
