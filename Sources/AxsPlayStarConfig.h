#pragma once

#import <Foundation/Foundation.h>

@interface AxsPlayStarConfig : NSObject
+ (instancetype)axs_playstar_shared;
- (BOOL)axs_playstar_isEnabled;
- (id)axs_playstar_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)axs_playstar_reload;
@end
