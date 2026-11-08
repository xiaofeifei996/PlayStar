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
///
/// 与 MRMediaRemoteSendCommand 的本质区别：这条路径由 MediaPlaybackCore 构造请求，
/// 携带 contentItemID 并走播放器自己注册的 handler，播放器（如汽水音乐）才认。
@interface AxsPlayStarMPC : NSObject

/// 把当前曲目设为 liked / 取消收藏。
/// source 可以是播放器控件视图（MRUNowPlayingTransportControlsView），
/// 也可以是 MRUNowPlayingViewController —— 内部会自己向上溯源。
/// completion 在派发后回调，confirmed 表示播放器回报了与目标一致的状态。
+ (AxsPlayStarVoteOutcome)axs_playstar_setLiked:(BOOL)liked
                                      forSource:(id _Nullable)source
                                     completion:(void (^_Nullable)(BOOL confirmed, NSString *detail))completion;

/// 读播放器自己回报的收藏状态。返回 NO 表示它根本不汇报（例如汽水音乐）。
+ (BOOL)axs_playstar_isLikedFor:(id _Nullable)source;

/// 当前曲目是否具备收藏能力（iOS 17+ 才有 isFavoriteEligible；更早版本看命令 enabled）。
+ (BOOL)axs_playstar_isEligibleFor:(id _Nullable)source;

@end

NS_ASSUME_NONNULL_END
