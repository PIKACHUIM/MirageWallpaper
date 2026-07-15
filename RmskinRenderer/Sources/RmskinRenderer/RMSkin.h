#pragma once

// RMSkin — runtime for a single Rainmeter skin config.
//
// Loads one skin .ini (via RMConfigParser), builds its measures and meters,
// ticks them on the [Rainmeter] Update interval, computes the content size
// (DynamicWindowSize), and draws the composited result. Also dispatches mouse
// actions and !Bangs.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class RMMeasure;
@class RMMeter;
@class RMConfigParser;

NS_ASSUME_NONNULL_BEGIN

@interface RMSkin : NSObject

@property (nonatomic, strong, readonly) RMConfigParser *parser;
@property (nonatomic, strong, readonly) NSArray<RMMeasure *> *measures;
@property (nonatomic, strong, readonly) NSArray<RMMeter *> *meters;

@property (nonatomic, assign, readonly) NSTimeInterval updateInterval; // seconds
@property (nonatomic, assign, readonly) BOOL dynamicWindowSize;
@property (nonatomic, assign, readonly) NSSize contentSize;

@property (nonatomic, copy, nullable) NSString *mouseScrollUpAction;
@property (nonatomic, copy, nullable) NSString *mouseScrollDownAction;

// skinFile:   absolute path of the config's .ini
// resources:  #@# target (root config's @Resources)
// rootConfig: skin root folder (contains @Resources)
// skinsPath:  the Skins/ root
// config:     display config name, e.g. "# - TETRAKTYS\\SYSTEM INFO"
- (nullable instancetype)initWithSkinFile:(NSString *)skinFile
                                resources:(NSString *)resources
                               rootConfig:(NSString *)rootConfig
                                skinsPath:(NSString *)skinsPath
                                   config:(NSString *)config;

// Re-parse the skin from disk and rebuild measures/meters.
- (BOOL)reload;

// Advance one tick: update measures, prepare meters, recompute content size.
- (void)tick;

// Draw into the current AppKit graphics context (flipped, top-left origin),
// within a view of the given bounds.
- (void)drawInBounds:(NSRect)bounds;

// Hit-test a point (skin coordinates, top-left origin) and run its action.
- (void)handleMouseUpAt:(NSPoint)point rightButton:(BOOL)rightButton;
- (void)handleScrollUp:(BOOL)up;

// Execute a bang-action string like "[!SetVariable X 1][!Refresh]".
- (void)executeActions:(NSString *)actions;

// Bang support hooks.
- (void)setOption:(NSString *)key value:(NSString *)value forSection:(NSString *)section;
- (void)requestRedraw;
@property (nonatomic, copy, nullable) void (^onNeedsRedraw)(void);

// Look-ups.
- (nullable RMMeter *)meterNamed:(NSString *)name;
- (nullable RMMeasure *)measureNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
