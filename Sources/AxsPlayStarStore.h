#pragma once

#import <Foundation/Foundation.h>
#import "AxsPlayStarPreferences.h"
#import "AxsPlayStarRemote.h"

NS_ASSUME_NONNULL_BEGIN

/// 把曲目指纹与「本地已收藏」状态一起落盘，键名 liked.<指纹 hash>。
@interface AxsPlayStarStore : NSObject
+ (instancetype)axs_playstar_shared;
- (BOOL)axs_playstar_isLikedKey:(NSString *)key systemState:(BOOL)systemLiked;
- (void)axs_playstar_setLiked:(BOOL)liked forKey:(NSString *)key;
- (void)axs_playstar_forgetKey:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
