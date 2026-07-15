#import "RMBangs.h"
#import "RMSkin.h"
#import "RMConfigParser.h"
#import "RMMathParser.h"
#import "RMMeter.h"
#import "RMLog.h"

@implementation RMBangs

// Split "[!A x][!B y z]" into individual "!A x" / "!B y z" strings.
+ (NSArray<NSString *> *)splitGroups:(NSString *)actions {
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    NSUInteger i = 0, n = actions.length;
    while (i < n) {
        unichar c = [actions characterAtIndex:i];
        if (c == '[') {
            NSInteger depth = 0; NSUInteger k = i;
            for (; k < n; k++) {
                unichar ck = [actions characterAtIndex:k];
                if (ck == '[') depth++;
                else if (ck == ']') { depth--; if (depth == 0) break; }
            }
            if (k < n) {
                NSString *inner = [actions substringWithRange:NSMakeRange(i + 1, k - i - 1)];
                [groups addObject:inner];
                i = k + 1;
                continue;
            }
        }
        i++;
    }
    if (groups.count == 0 && actions.length) [groups addObject:actions];
    return groups;
}

// Tokenize a bang group into ["!SetVariable", "Scale", "1"], honouring quotes.
+ (NSArray<NSString *> *)tokenize:(NSString *)group {
    NSMutableArray<NSString *> *toks = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    BOOL inQuote = NO, has = NO; unichar q = '"';
    NSUInteger i = 0, n = group.length;
    while (i < n) {
        unichar c = [group characterAtIndex:i];
        if (inQuote) {
            if (c == q) inQuote = NO;
            else { [cur appendFormat:@"%C", c]; has = YES; }
        } else if (c == '"' || c == '\'') {
            inQuote = YES; has = YES; q = c;
        } else if (c == ' ' || c == '\t') {
            if (has) { [toks addObject:cur.copy]; [cur setString:@""]; has = NO; }
        } else {
            [cur appendFormat:@"%C", c]; has = YES;
        }
        i++;
    }
    if (has) [toks addObject:cur.copy];
    return toks;
}

+ (void)execute:(NSString *)actions onSkin:(RMSkin *)skin {
    if (actions.length == 0 || skin == nil) return;
    for (NSString *group in [self splitGroups:actions]) {
        NSArray<NSString *> *toks = [self tokenize:group];
        if (toks.count == 0) continue;
        NSString *bang = toks[0];
        if (![bang hasPrefix:@"!"]) continue;
        NSString *rawName = [bang substringFromIndex:1].lowercaseString;
        // "!RainmeterShowMeter" is an old alias for "!ShowMeter" etc.
        NSString *name = rawName;
        if ([name hasPrefix:@"rainmeter"]) name = [name substringFromIndex:9];
        [self run:name args:toks onSkin:skin];
    }
}

+ (void)run:(NSString *)name args:(NSArray<NSString *> *)toks onSkin:(RMSkin *)skin {
    RMConfigParser *cp = skin.parser;
    auto argAt = ^NSString *(NSUInteger i) { return i < toks.count ? toks[i] : @""; };

    if ([name isEqualToString:@"setvariable"]) {
        NSString *var = argAt(1);
        NSString *val = [cp expand:argAt(2)];
        double num;
        if ([RMMathParser parse:val result:&num]) {
            // Store a clean numeric string when the value evaluates.
            val = (num == floor(num)) ? [NSString stringWithFormat:@"%ld", (long)num]
                                      : [NSString stringWithFormat:@"%g", num];
        }
        [cp setVariable:var value:val];
        [skin requestRedraw];
    } else if ([name isEqualToString:@"writekeyvalue"]) {
        // [!WriteKeyValue Section Key Value [File]] — apply live (persist skipped).
        NSString *section = argAt(1), *key = argAt(2), *val = [cp expand:argAt(3)];
        double num;
        if ([RMMathParser parse:val result:&num]) {
            val = (num == floor(num)) ? [NSString stringWithFormat:@"%ld", (long)num]
                                      : [NSString stringWithFormat:@"%g", num];
        }
        if ([section.uppercaseString isEqualToString:@"VARIABLES"]) {
            [cp setVariable:key value:val];
        } else {
            [skin setOption:key value:val forSection:section];
        }
        [skin requestRedraw];
    } else if ([name isEqualToString:@"refresh"] || [name isEqualToString:@"refreshapp"]) {
        [skin reload];
        [skin tick];
        [skin requestRedraw];
    } else if ([name isEqualToString:@"redraw"]) {
        [skin requestRedraw];
    } else if ([name isEqualToString:@"update"]) {
        [skin tick];
        [skin requestRedraw];
    } else if ([name isEqualToString:@"hidemeter"] || [name isEqualToString:@"hide"]) {
        RMMeter *m = [skin meterNamed:argAt(1)];
        m.hidden = YES; [skin requestRedraw];
    } else if ([name isEqualToString:@"showmeter"] || [name isEqualToString:@"show"]) {
        RMMeter *m = [skin meterNamed:argAt(1)];
        m.hidden = NO; [skin requestRedraw];
    } else if ([name isEqualToString:@"togglemeter"] || [name isEqualToString:@"toggle"]) {
        RMMeter *m = [skin meterNamed:argAt(1)];
        m.hidden = !m.hidden; [skin requestRedraw];
    } else if ([name isEqualToString:@"setoption"]) {
        [skin setOption:argAt(2) value:[cp expand:argAt(3)] forSection:argAt(1)];
        [skin requestRedraw];
    } else if ([name isEqualToString:@"execute"]) {
        // !Execute groups nested bang groups: re-enter with the remaining args joined.
        NSMutableString *inner = [NSMutableString string];
        for (NSUInteger i = 1; i < toks.count; i++) {
            [inner appendString:toks[i]];
            if (i + 1 < toks.count) [inner appendString:@" "];
        }
        [self execute:inner onSkin:skin];
    } else {
        RMLogDebug(@"unhandled bang: %@", name);
    }
}

@end
