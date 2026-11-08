#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 收藏派发结果。
typedef NS_ENUM(NSInteger, AxsPlayStarVoteOutcome) {
    /// 找不到可用的收藏命令对象（播放器没实现 / 对象图拿不到）。
    AxsPlayStarVoteOutcomeUnavailable = 0,
    /// 命令对象存在但被播放器禁用。
    AxsPlayStarVoteOutcomeDisabled,
    /// 请求已派发。
    AxsPlayStarVoteOutcomeDispatched,
};

/// 直接走 MediaPlaybackCore 的私有对象图触发收藏 —— iOS 26 系统星标用的就是这条路。
///
/// iOS 26 的链路（MediaControls / MediaPlaybackCore 实测）：
///   leadingItemFromResponse:
///     → MPCPlayerResponse.tracklist.playingItem
///       → _favoriteCommandWithMediaRemoteCommand:  (iOS 17+)
///         → isFavoriteEligible / isFavorited
///           → changeValue:
///             → [MPCPlayerCommandRequest performRequest:completion:]
///
/// iOS 16 没有 favorite 那一套，但同一条派发通道早就在，只是入口换成
///   _feedbackCommandWithMediaRemoteCommand:  (likes=21 / dislikes=22 / wishlist=23)
/// 所以这里按「likeCommand → _feedbackCommandWithMediaRemoteCommand:」顺序回退。
@interface AxsPlayStarMPC : NSObject

+ (AxsPlayStarVoteOutcome)axs_playstar_setLiked:(BOOL)liked
                                      forSource:(id _Nullable)source
                                     completion:(void (^_Nullable)(BOOL confirmed, NSString *detail))completion;

+ (BOOL)axs_playstar_isLikedFor:(id _Nullable)source;
+ (BOOL)axs_playstar_isEligibleFor:(id _Nullable)source;

/// 诊断：把从 view 到 playingItem 的整条对象图逐层写进日志。
/// 只在点星标失败时调用，用来定位到底断在哪一层。
+ (void)axs_playstar_dumpObjectGraphFrom:(id _Nullable)source;

@end


NS_ASSUME_NONNULL_END
