#import "AxsPlayStarController.h"
#import "AxsPlayStarButton.h"
#import "AxsPlayStarConfig.h"
#import "AxsPlayStarPreferences.h"
#import "AxsPlayStarRemote.h"
#import "AxsPlayStarStore.h"
#import "AxsPlayStarDebug.h"
#import "AxsPlayStarMPC.h"
#import "AxsPlayStarPrivate.h"
#import <objc/runtime.h>

static const void *kAxsPlayStarButtonKey = &kAxsPlayStarButtonKey;

@interface AxsPlayStarController ()
@property (nonatomic, strong) NSHashTable<UIView *> *hosts;
@property (nonatomic, strong) AxsPlayStarTrack *track;
@property (nonatomic, assign) BOOL requesting;
@property (nonatomic, assign) BOOL requestAgain;
/// 当前曲目是否具备收藏能力。@YES/@NO，nil 表示还没探测出来。
@property (nonatomic, strong) NSNumber *voteEligible;
/// 最近一次点击的宿主视图，用来向上找到 MRUNowPlayingViewController。
@property (nonatomic, weak) UIView *lastHost;
/// 正在派发中，避免连点重复提交。
@property (nonatomic, assign) BOOL dispatching;
/// 上次记录的星标位置，用于抑制重复的布局日志。
@property (nonatomic, assign) CGRect lastLoggedStarFrame;
// 内部方法前置声明，避免 -Werror 下的 no-visible-interface 报错。
- (AxsPlayStarTrack *)axs_playstar_trackFromMPC;
- (UIView *)axs_playstar_anyHost;
- (void)axs_playstar_probeEligibility;
- (void)axs_playstar_showToast:(NSString *)text;
- (void)axs_playstar_changedLiked:(BOOL)liked forTrack:(AxsPlayStarTrack *)track;
- (void)axs_playstar_playHaptic:(BOOL)success;
- (NSString *)axs_playstar_messageForOutcome:(AxsPlayStarVoteOutcome)outcome;
- (void)axs_playstar_finishTapOnTrack:(AxsPlayStarTrack *)track
                                liked:(BOOL)liked
                            confirmed:(BOOL)confirmed
                               detail:(NSString *)detail;
@end

@implementation AxsPlayStarController

+ (instancetype)axs_playstar_shared {
    static AxsPlayStarController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hosts = [NSHashTable weakObjectsHashTable];
        __weak typeof(self) weakSelf = self;
        [AxsPlayStarRemote axs_playstar_shared].changeHandler = ^{
            __strong typeof(weakSelf) self = weakSelf;
            [self axs_playstar_requestTrack];
        };
        [[AxsPlayStarRemote axs_playstar_shared] axs_playstar_startObserving];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(axs_playstar_preferencesDidChange)
                                                     name:AxsPlayStarPreferencesChanged
                                                   object:nil];
        [self axs_playstar_requestTrack];
    }
    return self;
}

- (BOOL)axs_playstar_allowedOnSystem {
    if (![[AxsPlayStarConfig axs_playstar_shared] axs_playstar_isEnabled]) return NO;
    // iOS 26 起播放器自带同一颗星标，默认不重复添加。
    id skip = [[AxsPlayStarConfig axs_playstar_shared] axs_playstar_valueForKey:@"skipNativeStar" defaultValue:@(YES)];
    if ([skip respondsToSelector:@selector(boolValue)] && [skip boolValue]) {
        // iOS 26 起系统自带星标；用运行时版本判断避免依赖新 SDK 的可用性标注。
        NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
        if (version.majorVersion >= 26) return NO;
    }
    return YES;
}

- (BOOL)axs_playstar_hapticsEnabled {
    id value = [[AxsPlayStarConfig axs_playstar_shared] axs_playstar_valueForKey:@"hapticFeedback" defaultValue:@(YES)];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
}

#pragma mark - 曲目状态

- (void)axs_playstar_requestTrack {
    // 注意：不要因为 MediaRemote 符号缺失就提前返回 ——
    // 主路径是 MPC 对象图，和 MediaRemote 完全没有关系。
    if (self.requesting) {
        self.requestAgain = YES;
        return;
    }
    self.requesting = YES;
    __weak typeof(self) weakSelf = self;

    // 优先从 MediaPlaybackCore 的 response 读曲目：
    // MRMediaRemoteGetNowPlayingInfo 在 MediaRemoteUI 进程里返回 NULL（实测），
    // 那条路根本拿不到数据。response 是系统星标自己用的数据源，不涉及权限。
    AxsPlayStarTrack *mcpTrack = [self axs_playstar_trackFromMPC];
    if (mcpTrack) {
        self.track = mcpTrack;
        self.requesting = NO;
        [self axs_playstar_probeEligibility];
        [self axs_playstar_applyState];
        if (self.requestAgain) {
            self.requestAgain = NO;
            [self axs_playstar_requestTrack];
        }
        return;
    }

    // 回退：MediaRemote 查询。只有持有 now-playing client 身份时才有效。
    [[AxsPlayStarRemote axs_playstar_shared] axs_playstar_requestTrack:^(AxsPlayStarTrack *track) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.track = track;
        self.requesting = NO;
        [self axs_playstar_probeEligibility];
        [self axs_playstar_applyState];
        if (self.requestAgain) {
            self.requestAgain = NO;
            [self axs_playstar_requestTrack];
        }
    }];
}

/// 能力探测只走 MPC 对象图：这是唯一的真实判据。
/// 汽水音乐不汇报 IsLiked / SupportsIsLiked，所以 NowPlayingInfo 那条路不可用。
- (void)axs_playstar_probeEligibility {
    if (!self.track) {
        self.voteEligible = nil;
        return;
    }
    UIView *host = [self axs_playstar_anyHost];
    if (!host) {
        self.voteEligible = nil;
        return;
    }
    BOOL eligible = [AxsPlayStarMPC axs_playstar_isEligibleFor:host];
    self.voteEligible = @(eligible);
    axs_playstar_log(@"eligibility key=%@ eligible=%d", self.track.key, eligible);
}


/// 用 MediaPlaybackCore 的 response 拼出曲目。拿不到返回 nil。
- (AxsPlayStarTrack *)axs_playstar_trackFromMPC {
    UIView *host = [self axs_playstar_anyHost];
    if (!host) return nil;

    NSDictionary *info = [AxsPlayStarMPC axs_playstar_nowPlayingFromSource:host];
    NSString *title = info[@"title"];
    if (title.length == 0) return nil;

    AxsPlayStarTrack *track = [AxsPlayStarTrack new];
    track.title = title;
    track.artist = info[@"artist"] ?: @"";
    track.album = info[@"album"] ?: @"";
    track.contentItemID = info[@"contentItemID"] ?: @"";
    // 有 contentItemID 时它就是最准的曲目身份，重播同一首也能对上。
    track.key = track.contentItemID.length > 0
        ? [NSString stringWithFormat:@"ci:%@", track.contentItemID]
        : [NSString stringWithFormat:@"ta:%@|%@", track.title, track.artist];
    if (info[@"liked"]) track.systemLiked = [info[@"liked"] boolValue];
    if (info[@"eligible"]) track.supportsVote = [info[@"eligible"] boolValue];
    return track;
}

- (UIView *)axs_playstar_anyHost {
    for (UIView *candidate in self.hosts.allObjects) {
        if (candidate.window) return candidate;
    }
    for (UIView *candidate in self.hosts.allObjects) return candidate;
    return self.lastHost;
}

- (BOOL)axs_playstar_isLiked {
    AxsPlayStarTrack *track = self.track;
    if (!track) return NO;
    return [[AxsPlayStarStore axs_playstar_shared] axs_playstar_isLikedKey:track.key
                                                               systemState:track.systemLiked];
}

- (void)axs_playstar_applyState {
    BOOL liked = [self axs_playstar_isLiked];
    BOOL hasTrack = (self.track != nil);
    // 未探测出结果时保持可点，避免因为探测时机问题把功能锁死。
    BOOL supported = self.voteEligible ? self.voteEligible.boolValue : YES;
    for (UIView *host in self.hosts.allObjects) {
        AxsPlayStarButton *button = objc_getAssociatedObject(host, kAxsPlayStarButtonKey);
        if (!button) continue;
        [button axs_playstar_applyLiked:liked];
        button.enabled = hasTrack;
        // 不支持时压暗但仍可点，点了会给出明确原因。
        button.alpha = hasTrack ? (supported ? 1.0 : 0.4) : 0.0;
        [button axs_playstar_applyTintColor:[self axs_playstar_tintColorForHost:host]];
    }
}

- (UIColor *)axs_playstar_tintColorForHost:(UIView *)host {
    UIColor *color = nil;
    if ([host respondsToSelector:@selector(stylingProvider)]) {
        id<AxsPlayStarStylingProvider> provider =
            (id<AxsPlayStarStylingProvider>)[(id<AxsPlayStarTransportControls>)host stylingProvider];
        if ([provider respondsToSelector:@selector(primaryColor)]) {
            id candidate = [provider primaryColor];
            if ([candidate isKindOfClass:[UIColor class]]) color = candidate;
        }
    }
    if (!color) color = host.tintColor;
    if (!color) color = UIColor.labelColor;
    return color;
}

#pragma mark - 安装与排版

- (void)axs_playstar_installInControlsView:(UIView *)controlsView {
    if (!controlsView) return;
    if (![self axs_playstar_allowedOnSystem]) {
        [self axs_playstar_removeFromHost:controlsView];
        return;
    }
    [self.hosts addObject:controlsView];
    self.lastHost = controlsView;

    // 星标必须挂在传输控件行自己身上。
    // 之前挂到父视图（MRUNowPlayingView）上，那是个纯容器、不接收触摸，
    // 实测日志里 tap 命中 0 次 —— 这是「点了没反应」的真正原因。
    // 挂在宿主内部后，宿主自己的 hitTest 就会把触摸交给星标。
    AxsPlayStarButton *button = objc_getAssociatedObject(controlsView, kAxsPlayStarButtonKey);
    if (!button) {
        button = [AxsPlayStarButton axs_playstar_button];
        [button addTarget:self action:@selector(axs_playstar_handleTap:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(controlsView, kAxsPlayStarButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [controlsView addSubview:button];
    } else if (button.superview != controlsView) {
        [button removeFromSuperview];
        [controlsView addSubview:button];
    }
    // 宿主要是把交互关掉（部分容器视图会），点击永远进不来。
    controlsView.userInteractionEnabled = YES;
    [controlsView bringSubviewToFront:button];
    [self axs_playstar_layoutInControlsView:controlsView];
    [self axs_playstar_applyState];
    axs_playstar_log(@"install host=%@ bounds=%@",
                     NSStringFromClass(controlsView.class),
                     NSStringFromCGRect(controlsView.bounds));
}

- (UIView *)axs_playstar_buttonForHost:(UIView *)host {
    if (!host) return nil;
    return objc_getAssociatedObject(host, kAxsPlayStarButtonKey);
}

- (void)axs_playstar_removeFromHost:(UIView *)host {
    AxsPlayStarButton *button = objc_getAssociatedObject(host, kAxsPlayStarButtonKey);
    if (button) {
        [button removeFromSuperview];
        objc_setAssociatedObject(host, kAxsPlayStarButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self.hosts removeObject:host];
}

- (void)axs_playstar_removeAll {
    for (UIView *host in self.hosts.allObjects) [self axs_playstar_removeFromHost:host];
}

- (void)axs_playstar_layoutInControlsView:(UIView *)controlsView {
    if (![controlsView isKindOfClass:NSClassFromString(@"MRUNowPlayingTransportControlsView")]) return;
    UIView *host = controlsView;
    AxsPlayStarButton *button = objc_getAssociatedObject(host, kAxsPlayStarButtonKey);
    if (!button) {
        [self axs_playstar_installInControlsView:host];
        return;
    }

    CGRect bounds = host.bounds;
    if (CGRectIsEmpty(bounds)) return;

    id<AxsPlayStarTransportControls> controls = (id<AxsPlayStarTransportControls>)host;
    UIView *left = [controls respondsToSelector:@selector(leftButton)] ? [controls leftButton] : nil;
    UIView *leading = [controls respondsToSelector:@selector(leadingButton)] ? [controls leadingButton] : nil;
    UIView *routing = [controls respondsToSelector:@selector(routingButton)] ? [controls routingButton] : nil;

    if (![left isKindOfClass:[UIView class]]) left = nil;
    if (![leading isKindOfClass:[UIView class]]) leading = nil;
    if (![routing isKindOfClass:[UIView class]]) routing = nil;

    // 系统把「正在投送的设备 / Apple TV 遥控」放在左侧格时让它，避免两个图标打架。
    // updateVisibility 里无内容时 alpha 是 0.0、有内容时 0.5，用 0.25 区分。
    BOOL leadingBusy = leading && !leading.hidden && leading.alpha > 0.25;
    if (leadingBusy) {
        button.hidden = YES;
        return;
    }
    button.hidden = NO;

    // 尺寸跟随系统按钮：优先左侧播放按钮，其次 AirPlay 按钮，最后按控件高度推算。
    CGFloat size = 0;
    if (left && !CGRectIsEmpty(left.frame)) size = left.frame.size.height;
    if (size <= 0 && routing && !CGRectIsEmpty(routing.frame)) size = routing.frame.size.height;
    if (size <= 0 && leading && !CGRectIsEmpty(leading.frame)) size = leading.frame.size.height;
    if (size <= 0) size = MIN(MAX(bounds.size.height * 0.72, 26.0), 44.0);
    size = MIN(MAX(size, 26.0), 44.0);

    // 系统在 layoutSubviews 里始终会排 leadingButton 的 frame（即使没有内容），
    // 那一格正是 iOS 26 放星标的位置，直接借它的中心点。
    CGFloat centerX = 0;
    CGFloat centerY = 0;
    BOOL placed = NO;
    if (leading && !CGRectIsEmpty(leading.frame)) {
        centerX = CGRectGetMidX(leading.frame);
        centerY = CGRectGetMidY(leading.frame);
        placed = YES;
    }
    if (!placed && routing && !CGRectIsEmpty(routing.frame) && CGRectGetMinX(routing.frame) > CGRectGetMidX(bounds)) {
        // 没有 leading 槽位时，与右侧 AirPlay 按钮左右对称。
        CGFloat inset = bounds.size.width - CGRectGetMaxX(routing.frame);
        centerX = inset + size * 0.5;
        placed = YES;
    }
    if (!placed && left && !CGRectIsEmpty(left.frame)) {
        // 兜底：贴在左边界，与系统卡片的内边距对齐。
        centerX = MAX(CGRectGetMinX(left.frame) - size * 0.5 - 8.0, size * 0.5 + 8.0);
        placed = YES;
    }
    if (!placed) centerX = 22.0 + size * 0.5;
    if (centerY <= 0) {
        centerY = (left && !CGRectIsEmpty(left.frame)) ? CGRectGetMidY(left.frame) : CGRectGetMidY(bounds);
    }

    // 星标是宿主的子视图，直接在宿主坐标系里定位。
    // 系统的 leading/routing 槽位落在 bounds 之外（leading.x = -26），
    // 星标摆进去就超出可视区，所以这里把它钳回宿主内部。
    button.bounds = CGRectMake(0, 0, size, size);
    CGFloat half = size * 0.5;
    centerX = MIN(MAX(centerX, half), MAX(bounds.size.width - half, half));
    if (centerY <= 0) centerY = CGRectGetMidY(bounds);
    centerY = MIN(MAX(centerY, half), MAX(bounds.size.height - half, half));
    button.center = CGPointMake(centerX, centerY);
    static BOOL loggedSubviews = NO;
    if (!loggedSubviews) {
        loggedSubviews = YES;
        NSMutableArray *parts = [NSMutableArray array];
        for (UIView *sub in host.subviews) {
            [parts addObject:[NSString stringWithFormat:@"%@%@", NSStringFromClass([sub class]),
                              NSStringFromCGRect(sub.frame)]];
        }
        axs_playstar_log(@"subviews host=%@ bounds=%@ interactive=%d list=%@",
                         NSStringFromClass([host class]), NSStringFromCGRect(host.bounds),
                         host.userInteractionEnabled, [parts componentsJoinedByString:@" | "]);
        axs_playstar_log(@"superview bounds=%@ frame=%@",
                         NSStringFromCGRect(host.superview.bounds), NSStringFromCGRect(host.frame));
    }
    // 布局每次刷新都会走到这里，只在位置真的变化时记一笔，避免日志被刷爆。
    if (!CGRectEqualToRect(self.lastLoggedStarFrame, button.frame)) {
        self.lastLoggedStarFrame = button.frame;
        axs_playstar_log(@"layout host=%@ bounds=%@ leading=%@ routing=%@ star=%@",
                        NSStringFromClass(host.class), NSStringFromCGRect(bounds),
                        NSStringFromCGRect(leading.frame), NSStringFromCGRect(routing.frame),
                        NSStringFromCGRect(button.frame));
    }
    [button axs_playstar_applyTintColor:[self axs_playstar_tintColorForHost:host]];
}

#pragma mark - 交互

- (void)axs_playstar_handleTap:(AxsPlayStarButton *)sender {
    AxsPlayStarTrack *track = self.track;
    axs_playstar_log(@"tap begin track=%@ dispatching=%d", track ? track.title : @"(nil)", self.dispatching);
    if (!track) {
        // 拿不到曲目时不要静默 —— 这正是「看起来没反应」的根因。
        [self axs_playstar_showToast:@"读不到当前播放信息"];
        return;
    }
    if (self.dispatching) return;

    // 按钮挂在宿主的父视图上，所以要用记录下来的宿主做对象图溯源。
    UIView *host = nil;
    for (UIView *candidate in self.hosts.allObjects) {
        if ([self axs_playstar_buttonForHost:candidate] == sender) { host = candidate; break; }
    }
    if (!host) host = self.lastHost;

    BOOL wasLiked = [self axs_playstar_isLiked];
    BOOL target = !wasLiked;
    self.dispatching = YES;

    // 只有这一条路径：MediaPlaybackCore 对象图。
    // 它由播放器自己的命令处理器执行收藏，所以是「真实收藏」而不是改图标。
    __weak typeof(self) weakSelf = self;
    AxsPlayStarVoteOutcome outcome =
        [AxsPlayStarMPC axs_playstar_setLiked:target forSource:host completion:^(BOOL confirmed, NSString *detail) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.dispatching = NO;
            axs_playstar_log(@"tap result key=%@ target=%d confirmed=%d detail=%@",
                             track.key, target, confirmed, detail);
            [self axs_playstar_finishTapOnTrack:track liked:target confirmed:confirmed detail:detail];
        }];

    axs_playstar_log(@"tap key=%@ wasLiked=%d outcome=%ld", track.key, wasLiked, (long)outcome);
    if (outcome != AxsPlayStarVoteOutcomeDispatched) {
        self.dispatching = NO;
        // 命令对象都拿不到时立刻反馈，不用等回调。
        [self axs_playstar_changedLiked:wasLiked forTrack:track];
        [self axs_playstar_playHaptic:NO];
        [self axs_playstar_showToast:[self axs_playstar_messageForOutcome:outcome]];
    }
}

- (NSString *)axs_playstar_messageForOutcome:(AxsPlayStarVoteOutcome)outcome {
    switch (outcome) {
        case AxsPlayStarVoteOutcomeDisabled:
            return @"当前播放器禁用了收藏命令";
        case AxsPlayStarVoteOutcomeUnavailable:
            return @"当前播放器未实现系统收藏命令";
        default:
            return @"";
    }
}

/// 派发完成后落地状态。播放器回报确认就用它的；不回报时按本地记账（汽水就是这种）。
- (void)axs_playstar_finishTapOnTrack:(AxsPlayStarTrack *)track
                                liked:(BOOL)liked
                            confirmed:(BOOL)confirmed
                               detail:(NSString *)detail {
    [self axs_playstar_changedLiked:liked forTrack:track];
    [self axs_playstar_playHaptic:YES];
    // 不回报状态的播放器也要让用户知道结果，但不用红色错误手感。
    if (!confirmed && detail.length > 0) {
        axs_playstar_log(@"tap unconfirmed: %@", detail);
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf axs_playstar_requestTrack];
    });
}

- (void)axs_playstar_changedLiked:(BOOL)liked forTrack:(AxsPlayStarTrack *)track {
    [[AxsPlayStarStore axs_playstar_shared] axs_playstar_setLiked:liked forKey:track.key];
    for (UIView *host in self.hosts.allObjects) {
        AxsPlayStarButton *button = objc_getAssociatedObject(host, kAxsPlayStarButtonKey);
        if (!button) continue;
        [button axs_playstar_applyLiked:liked];
        [button axs_playstar_applyTintColor:[self axs_playstar_tintColorForHost:host]];
    }
}

- (void)axs_playstar_playHaptic:(BOOL)success {
    if (![self axs_playstar_hapticsEnabled]) return;
    UINotificationFeedbackGenerator *generator = [UINotificationFeedbackGenerator new];
    [generator prepare];
    [generator notificationOccurred:success ? UINotificationFeedbackTypeSuccess
                                            : UINotificationFeedbackTypeError];
}

/// 播放器没有可用收藏命令时的提示，避免用户以为已经收藏成功。
- (void)axs_playstar_showToast:(NSString *)text {
    if (text.length == 0) return;
    static NSTimeInterval lastShown;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (now - lastShown < 2.0) return;
    lastShown = now;

    UIWindow *window = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }
    if (!window) return;

    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    [label sizeToFit];
    label.bounds = CGRectInset(label.bounds, -16, -10);
    label.center = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMaxY(window.bounds) - 120);
    label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
    label.layer.cornerRadius = 12;
    label.layer.masksToBounds = YES;
    label.alpha = 0.0;
    label.userInteractionEnabled = NO;
    [window addSubview:label];

    [UIView animateWithDuration:0.18 animations:^{ label.alpha = 1.0; } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.25 delay:1.6 options:0 animations:^{ label.alpha = 0.0; }
                         completion:^(BOOL finished) { [label removeFromSuperview]; }];
    }];
}

- (void)axs_playstar_refreshAll {
    [self axs_playstar_applyState];
    [self axs_playstar_requestTrack];
}

- (void)axs_playstar_preferencesDidChange {
    if (![self axs_playstar_allowedOnSystem]) {
        [self axs_playstar_removeAll];
        return;
    }
    for (UIView *host in self.hosts.allObjects) [self axs_playstar_installInControlsView:host];
    [self axs_playstar_requestTrack];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
