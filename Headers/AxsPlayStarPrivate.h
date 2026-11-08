#pragma once

#import <Foundation/Foundation.h>

// MediaRemote 收藏类命令编号，值固定不随系统变化：
//   早期枚举：RateTrack=20 / LikeTrack=21 / DislikeTrack=22 / BookmarkTrack=23
//   新版私有枚举：kMRLikeTrack=0x6A / kMRBanTrack=0x6B
//                kMRAddTrackToWishList=0x6C / kMRRemoveTrackFromWishList=0x6D
//
// 这些编号现在是喂给 MediaPlaybackCore 的命令工厂的：
//   [playingItem _feedbackCommandWithMediaRemoteCommand:21]   ← iOS 16 唯一入口
//   [playingItem _favoriteCommandWithMediaRemoteCommand:21]   ← iOS 17+
// 拿到的对象再走 changeValue: + performRequest:completion: 派发，
// 由播放器自己注册的 MPRemoteCommandCenter handler 执行。
typedef NS_ENUM(int, AxsPlayStarMRCommand) {
    AxsPlayStarMRCommandLikeLegacy      = 21,
    AxsPlayStarMRCommandBookmarkLegacy  = 23,
    AxsPlayStarMRCommandLikeModern      = 0x6A,
    AxsPlayStarMRCommandAddToWishList   = 0x6C,
    AxsPlayStarMRCommandRemoveWishList  = 0x6D,
};

/// MRUNowPlayingTransportControlsView 的私有访问器（只声明形状，不做实现）。
@protocol AxsPlayStarTransportControls <NSObject>
- (id)leftButton;
- (id)leadingButton;
- (id)routingButton;
- (id)stylingProvider;
@end

/// MRUVisualStylingProvider 的配色访问器。
@protocol AxsPlayStarStylingProvider <NSObject>
- (id)primaryColor;
- (id)secondaryColor;
@end
