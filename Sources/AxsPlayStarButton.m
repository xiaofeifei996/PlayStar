#import "AxsPlayStarButton.h"

@interface AxsPlayStarButton ()
@property (nonatomic, assign) BOOL axs_playstar_liked;
@end

@implementation AxsPlayStarButton

+ (instancetype)axs_playstar_button {
    AxsPlayStarButton *button = [AxsPlayStarButton buttonWithType:UIButtonTypeCustom];
    if (!button) return nil;
    button.backgroundColor = UIColor.clearColor;
    button.isAccessibilityElement = YES;
    button.accessibilityTraits = UIAccessibilityTraitButton;
    button.accessibilityLabel = @"收藏";
    [button axs_playstar_refreshImage];
    return button;
}

- (void)axs_playstar_applyLiked:(BOOL)liked {
    if (_axs_playstar_liked == liked) return;
    _axs_playstar_liked = liked;
    [self axs_playstar_refreshImage];
}

- (void)axs_playstar_refreshImage {
    NSString *symbol = self.axs_playstar_liked ? @"star.fill" : @"star";
    UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightRegular];
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:config];
    if (!image) image = [UIImage systemImageNamed:symbol];
    // 模板渲染：颜色完全交给 tintColor，跟随播放器的 VisualStyling。
    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self setImage:image forState:UIControlStateNormal];

    UIImage *dimmed = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self setImage:dimmed forState:UIControlStateHighlighted];

    self.accessibilityValue = self.axs_playstar_liked ? @"已收藏" : @"未收藏";
    self.accessibilityTraits = UIAccessibilityTraitButton
        | (self.axs_playstar_liked ? UIAccessibilityTraitSelected : 0);
}

- (void)axs_playstar_applyTintColor:(UIColor *)color {
    // 未收藏压暗一档、已收藏全亮，对应 iOS 26 里未激活/已激活的对比。
    UIColor *base = color ?: UIColor.labelColor;
    self.tintColor = self.axs_playstar_liked ? base : [base colorWithAlphaComponent:0.55];
    self.imageView.alpha = 1.0;
}

@end
