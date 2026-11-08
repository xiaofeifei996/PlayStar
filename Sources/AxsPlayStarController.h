#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 统一管理锁屏 / 控制中心里所有播放器控件视图上的星标按钮。
@interface AxsPlayStarController : NSObject
+ (instancetype)axs_playstar_shared;
/// 在传输按钮行里安装并排版星标按钮（幂等，可反复调用）。
- (void)axs_playstar_installInControlsView:(UIView *)controlsView;
/// 只更新位置，不新增子视图；供 layoutSubviews 阶段安全调用。
- (void)axs_playstar_layoutInControlsView:(UIView *)controlsView;
/// 取某个宿主视图上的星标按钮（可能为 nil）。
- (nullable UIView *)axs_playstar_buttonForHost:(UIView *)host;
/// 系统播放状态变化后刷新所有已安装按钮。
- (void)axs_playstar_refreshAll;
@end

NS_ASSUME_NONNULL_END
