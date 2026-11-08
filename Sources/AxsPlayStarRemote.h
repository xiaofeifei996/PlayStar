#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 当前曲目的精简描述，用于「曲目 -> 已收藏」的本地去重键。
@interface AxsPlayStarTrack : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *bundleID;
/// 当前内容项标识。收藏命令必须携带它，否则播放器不知道要操作哪一首。
@property (nonatomic, copy) NSString *contentItemID;
/// 播放器申报的收藏能力位。多数国产播放器不汇报，此时无意义。
@property (nonatomic, assign) BOOL supportsVote;
/// 播放器申报的收藏状态。多数国产播放器不汇报。
@property (nonatomic, assign) BOOL systemLiked;
@end

/// 只负责「读」：现在播的是什么、播放器申报了什么。
/// 收藏动作不在这里 —— 那条路径已收敛到 AxsPlayStarMPC 的 MediaPlaybackCore 对象图，
/// 不再使用 MRMediaRemoteSendCommand（广播式命令进不了播放器自己注册的 handler）。
@interface AxsPlayStarRemote : NSObject

+ (instancetype)axs_playstar_shared;

@property (nonatomic, readonly) BOOL axs_playstar_available;
@property (nonatomic, copy, nullable) void (^changeHandler)(void);

- (void)axs_playstar_startObserving;
- (void)axs_playstar_requestTrack:(void (^)(AxsPlayStarTrack *_Nullable track))completion;

/// 当前播放器的 bundle id（仅诊断用；MediaRemote 通常不给第三方 App 这项）。
@property (nonatomic, copy, readonly, nullable) NSString *axs_playstar_playerBundleID;

@end

NS_ASSUME_NONNULL_END
