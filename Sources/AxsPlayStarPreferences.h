#pragma once

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "AxsPlayStarPaths.h"

static NSString * const AxsPlayStarPreferencesDomain = @"com.axs.playstar";
static NSString * const AxsPlayStarPreferencesChanged = @"com.axs.playstar.preferences-changed";

// 读取顺序：cfprefsd（沙盒安全，两条进程都能访问）→ 隐根/真实路径文件 → 空字典。
static inline NSDictionary *axs_playstar_readPreferences(void) {
    CFStringRef domain = (__bridge CFStringRef)AxsPlayStarPreferencesDomain;
    CFDictionaryRef merged = CFPreferencesCopyMultiple(NULL, domain,
                                                       kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (merged) {
        NSDictionary *values = (__bridge_transfer NSDictionary *)merged;
        if (values.count > 0) return values;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray *candidates = [NSMutableArray arrayWithObject:axs_playstar_preferencesPath()];
    [candidates addObjectsFromArray:axs_playstar_legacyPreferencesPaths()];
    for (NSString *path in candidates) {
        if (![manager fileExistsAtPath:path]) continue;
        NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([values isKindOfClass:[NSDictionary class]] && values.count > 0) return values;
    }
    return @{};
}

// 只有设置面板调用；Tweak 自身永不写配置。
static inline BOOL axs_playstar_writePreference(NSString *key, id value, NSError **error) {
    if (key.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:AxsPlayStarPreferencesDomain code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"无效的设置项"}];
        }
        return NO;
    }
    NSMutableDictionary *values = [axs_playstar_readPreferences() mutableCopy];
    if (!values) values = [NSMutableDictionary dictionary];
    if (value) values[key] = value;
    else [values removeObjectForKey:key];

    CFStringRef domain = (__bridge CFStringRef)AxsPlayStarPreferencesDomain;
    CFPreferencesSetMultiple((__bridge CFDictionaryRef)values, NULL, domain,
                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    Boolean synced = CFPreferencesAppSynchronize(domain);
    if (!synced) {
        if (error) {
            *error = [NSError errorWithDomain:AxsPlayStarPreferencesDomain code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"设置未能写入系统偏好"}];
        }
        return NO;
    }

    // 隐根环境下额外镜像一份，避免 var 清理把设置扫掉；失败不影响主流程。
    NSString *path = axs_playstar_preferencesPath();
    if (path.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [values writeToFile:path atomically:YES];
    }

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)AxsPlayStarPreferencesChanged, NULL, NULL, true);
    return YES;
}
