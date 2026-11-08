#pragma once

#import <Foundation/Foundation.h>

// RootHide 的 var 清理会扫真实 /var/mobile/Library/Preferences；
// 有隐根时优先写进当前隐根的 Preferences，没有隐根时就是普通路径。
static inline NSString *axs_playstar_jailbreakRoot(void) {
    NSString *groupDir = @"/var/mobile/Containers/Shared/AppGroup";
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *names = [manager contentsOfDirectoryAtPath:groupDir error:NULL];
    NSString *best = nil;
    NSDate *bestDate = nil;
    for (NSString *name in names) {
        if (![name hasPrefix:@".jbroot-"]) continue;
        NSString *root = [groupDir stringByAppendingPathComponent:name];
        // 用新版 rootless 的路径做隐根判定，旧布局再兜底检查一次。
        BOOL found = NO;
        for (NSString *relative in @[@"Library/MobileSubstrate/DynamicLibraries/AxsPlayStar.dylib",
                                     @"usr/lib/TweakInject/AxsPlayStar.dylib"]) {
            if ([manager fileExistsAtPath:[root stringByAppendingPathComponent:relative]]) { found = YES; break; }
        }
        if (!found) continue;
        NSDictionary *attributes = [manager attributesOfItemAtPath:root error:NULL];
        NSDate *date = attributes[NSFileModificationDate];
        if (!best || (date && [date compare:bestDate] == NSOrderedDescending)) {
            best = root;
            bestDate = date;
        }
    }
    return best;
}

static inline NSString *axs_playstar_primaryPreferencesPath(void) {
    NSString *root = axs_playstar_jailbreakRoot();
    NSString *relative = @"/var/mobile/Library/Preferences/com.axs.playstar.plist";
    if (root.length > 0) return [root stringByAppendingString:relative];
    return relative;
}

// 切换越狱环境或隐根 UUID 变化后，读旧副本兜底，避免设置丢失。
static inline NSArray<NSString *> *axs_playstar_legacyPreferencesPaths(void) {
    NSMutableArray *paths = [NSMutableArray array];
    NSString *real = @"/var/mobile/Library/Preferences/com.axs.playstar.plist";
    NSString *current = axs_playstar_primaryPreferencesPath();
    if (![current isEqualToString:real]) [paths addObject:real];

    NSString *groupDir = @"/var/mobile/Containers/Shared/AppGroup";
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:groupDir error:NULL];
    for (NSString *name in names) {
        if (![name hasPrefix:@".jbroot-"]) continue;
        NSString *candidate = [[groupDir stringByAppendingPathComponent:name]
            stringByAppendingString:@"/var/mobile/Library/Preferences/com.axs.playstar.plist"];
        if ([candidate isEqualToString:current]) continue;
        [paths addObject:candidate];
    }
    return paths;
}

static inline NSString *axs_playstar_preferencesPath(void) {
    return axs_playstar_primaryPreferencesPath();
}

// 本项目没有需要按越狱根解析的资源，保留模板接口。
static inline NSString *axs_playstar_resourcePath(NSString *rootfsPath) {
    NSString *root = axs_playstar_jailbreakRoot();
    if (root.length > 0 && [rootfsPath hasPrefix:@"/"]) return [root stringByAppendingString:rootfsPath];
    return rootfsPath;
}
