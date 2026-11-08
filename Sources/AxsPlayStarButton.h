#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 星标按钮：未收藏用描边 star，已收藏用实心 star.fill，跟随宿主控件的配色。
@interface AxsPlayStarButton : UIButton
@property (nonatomic, readonly) BOOL axs_playstar_liked;
/// 工厂方法，内部完成 SF Symbol 与可访问性配置。
+ (instancetype)axs_playstar_button;
- (void)axs_playstar_applyLiked:(BOOL)liked;
- (void)axs_playstar_applyTintColor:(nullable UIColor *)color;
@end

NS_ASSUME_NONNULL_END
