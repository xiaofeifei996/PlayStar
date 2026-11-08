#import "AxsPlayStarMPC.h"
#import "AxsPlayStarPrivate.h"
#import "AxsPlayStarDebug.h"
#import <objc/message.h>
#import <objc/runtime.h>

// 私有类不在 SDK 里，全程 objc_msgSend：写静态类型编译不过。

static id axs_send_id(id object, NSString *name) {
    if (!object || name.length == 0) return nil;
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return nil;
    typedef id (*Fn)(id, SEL);
    return ((Fn)objc_msgSend)(object, selector);
}

static BOOL axs_send_bool(id object, NSString *name, BOOL *found) {
    if (found) *found = NO;
    if (!object || name.length == 0) return NO;
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return NO;
    typedef BOOL (*Fn)(id, SEL);
    BOOL value = ((Fn)objc_msgSend)(object, selector);
    if (found) *found = YES;
    return value;
}

/// 属性名和 getter 名不一致时依次尝试（enabled -> isEnabled）。
static BOOL axs_send_bool_any(id object, NSArray<NSString *> *names, BOOL *found) {
    for (NSString *name in names) {
        BOOL hit = NO;
        BOOL value = axs_send_bool(object, name, &hit);
        if (hit) {
            if (found) *found = YES;
            return value;
        }
    }
    if (found) *found = NO;
    return NO;
}

@implementation AxsPlayStarMPC

#pragma mark - 对象图溯源

/// 沿响应链找 MRUNowPlayingViewController。按钮挂在宿主的父视图上，
/// 所以起点是控件视图本身，不是按钮。
+ (id)axs_playstar_viewControllerForSource:(id)source {
    if (!source) return nil;
    Class viewControllerClass = NSClassFromString(@"MRUNowPlayingViewController");
    if (!viewControllerClass) return nil;

    if ([source isKindOfClass:viewControllerClass]) return source;
    // 不是视图说明调用方已经把控制器传进来了，直接沿用。
    if (![source isKindOfClass:[UIView class]]) return source;

    id responder = source;
    while (responder) {
        if ([responder isKindOfClass:viewControllerClass]) return responder;
        id nested = axs_send_id(responder, @"nowPlayingViewController");
        if (nested && [nested isKindOfClass:viewControllerClass]) return nested;
        if (![responder respondsToSelector:@selector(nextResponder)]) break;
        typedef id (*NextFn)(id, SEL);
        id next = ((NextFn)objc_msgSend)(responder, @selector(nextResponder));
        if (next == responder) break;
        responder = next;
    }
    return nil;
}

/// 找到持有 MPCPlayerResponse 的控制器。三个候选来源按可靠性依次尝试。
+ (id)axs_playstar_controllerForSource:(id)source {
    id viewController = [self axs_playstar_viewControllerForSource:source];
    if (viewController) {
        id controller = axs_send_id(viewController, @"controller");
        if (controller) return controller;
        return viewController;
    }
    // source 可能是 MRUNowPlayingViewController.controller 本身。
    return source;
}

+ (id)axs_playstar_responseForSource:(id)source {
    id controller = [self axs_playstar_controllerForSource:source];
    if (!controller) {
        axs_playstar_log(@"mpc: no controller (source=%@)", NSStringFromClass([source class]));
        return nil;
    }

    Class responseClass = NSClassFromString(@"MPCPlayerResponse");
    NSMutableArray *candidates = [NSMutableArray array];
    id direct = axs_send_id(controller, @"response");
    if (direct) [candidates addObject:direct];

    id dataSource = axs_send_id(controller, @"metadataDataSource");
    id dataSourceResponse = axs_send_id(dataSource, @"response");
    if (dataSourceResponse) [candidates addObject:dataSourceResponse];

    id endpoint = axs_send_id(controller, @"endpointController");
    id endpointResponse = axs_send_id(endpoint, @"response");
    if (endpointResponse) [candidates addObject:endpointResponse];

    for (id candidate in candidates) {
        if (!responseClass || [candidate isKindOfClass:responseClass]) return candidate;
    }
    if (candidates.count > 0) {
        axs_playstar_log(@"mpc: no MPCPlayerResponse, got %@",
                         NSStringFromClass([[candidates firstObject] class]));
    }
    return nil;
}

+ (id)axs_playstar_playingItemForSource:(id)source {
    id response = [self axs_playstar_responseForSource:source];
    if (!response) return nil;
    id tracklist = axs_send_id(response, @"tracklist");
    id item = axs_send_id(tracklist, @"playingItem");
    if (!item) {
        axs_playstar_log(@"mpc: no playingItem (tracklist=%@)",
                         NSStringFromClass([tracklist class]));
    }
    return item;
}

#pragma mark - 收藏命令对象

/// 取收藏命令。iOS 17+ 是 likeCommand / favoriteCommand；
/// iOS 16 只有 _feedbackCommandWithMediaRemoteCommand:，命令号 21 = like。
+ (id)axs_playstar_likeCommandForItem:(id)item {
    if (!item) return nil;

    id command = axs_send_id(item, @"likeCommand");
    if (command) return command;

    // iOS 16 回退：直接用反馈命令工厂，21 = kMRMediaRemoteCommandLike。
    SEL factory = NSSelectorFromString(@"_feedbackCommandWithMediaRemoteCommand:");
    if ([item respondsToSelector:factory]) {
        typedef id (*Fn)(id, SEL, unsigned int);
        command = ((Fn)objc_msgSend)(item, factory, (unsigned int)AxsPlayStarMRCommandLikeLegacy);
        if (command) {
            axs_playstar_log(@"mpc: like command via _feedbackCommandWithMediaRemoteCommand:21");
            return command;
        }
    }

    // 再兜一层：新版工厂（iOS 17+ 的 favorite 入口）。
    SEL favoriteFactory = NSSelectorFromString(@"_favoriteCommandWithMediaRemoteCommand:");
    if ([item respondsToSelector:favoriteFactory]) {
        typedef id (*Fn)(id, SEL, unsigned int);
        command = ((Fn)objc_msgSend)(item, favoriteFactory, (unsigned int)AxsPlayStarMRCommandLikeLegacy);
        if (command) {
            axs_playstar_log(@"mpc: like command via _favoriteCommandWithMediaRemoteCommand:21");
            return command;
        }
    }

    axs_playstar_log(@"mpc: playingItem has no like command (%@)",
                     NSStringFromClass([item class]));
    return nil;
}

+ (BOOL)axs_playstar_isLikedFor:(id)source {
    id item = [self axs_playstar_playingItemForSource:source];
    id command = axs_send_id(item, @"likeCommand");
    if (!command) command = [self axs_playstar_likeCommandForItem:item];
    if (!command) return NO;
    BOOL found = NO;
    BOOL liked = axs_send_bool(command, @"value", &found);
    return found ? liked : NO;
}

+ (BOOL)axs_playstar_isEligibleFor:(id)source {
    id item = [self axs_playstar_playingItemForSource:source];
    if (!item) return NO;

    BOOL found = NO;
    BOOL eligible = axs_send_bool(item, @"isFavoriteEligible", &found);
    if (found) return eligible;

    id command = [self axs_playstar_likeCommandForItem:item];
    if (!command) return NO;
    BOOL enabled = axs_send_bool_any(command, @[@"isEnabled", @"enabled"], &found);
    // 拿不到 enabled 时不阻拦，交给派发阶段判定。
    return found ? enabled : YES;
}

#pragma mark - 派发

+ (AxsPlayStarVoteOutcome)axs_playstar_setLiked:(BOOL)liked
                                      forSource:(id)source
                                     completion:(void (^)(BOOL, NSString *))completion {
    void (^finish)(BOOL, NSString *) = ^(BOOL confirmed, NSString *detail) {
        if (completion) completion(confirmed, detail ?: @"");
    };

    id item = [self axs_playstar_playingItemForSource:source];
    if (!item) {
        // 断点在这一层最常见：找不到控制器 / response / playingItem。
        [self axs_playstar_dumpObjectGraphFrom:source];
        finish(NO, @"找不到当前播放项");
        return AxsPlayStarVoteOutcomeUnavailable;
    }

    id command = [self axs_playstar_likeCommandForItem:item];
    if (!command) {
        finish(NO, @"播放器未提供收藏命令");
        return AxsPlayStarVoteOutcomeUnavailable;
    }

    BOOL found = NO;
    // MPRemoteCommand 的 enabled 属性 getter 是 isEnabled，两个都试。
    BOOL enabled = axs_send_bool_any(command, @[@"isEnabled", @"enabled"], &found);
    if (found && !enabled) {
        axs_playstar_log(@"mpc: like command disabled by player");
        finish(NO, @"播放器已禁用收藏命令");
        return AxsPlayStarVoteOutcomeDisabled;
    }

    // changeValue: 的参数是新值。系统星标用 value ^ 1，这里直接用目标值更准确。
    SEL changeSelector = NSSelectorFromString(@"changeValue:");
    if (![command respondsToSelector:changeSelector]) {
        finish(NO, @"命令不支持 changeValue:");
        return AxsPlayStarVoteOutcomeUnavailable;
    }
    typedef id (*ChangeFn)(id, SEL, unsigned int);
    id request = ((ChangeFn)objc_msgSend)(command, changeSelector, liked ? 1u : 0u);
    if (!request) {
        finish(NO, @"changeValue: 返回空请求");
        return AxsPlayStarVoteOutcomeUnavailable;
    }

    Class requestClass = NSClassFromString(@"MPCPlayerCommandRequest");
    SEL performSelector = NSSelectorFromString(@"performRequest:completion:");
    if (!requestClass || ![requestClass respondsToSelector:performSelector]) {
        finish(NO, @"缺少 performRequest:completion:");
        return AxsPlayStarVoteOutcomeUnavailable;
    }

    // completion 的 status 是 MPRemoteCommandHandlerStatus：
    // 0 = success，其余为失败原因。这里只有当播放器回报状态时才确认。
    __block BOOL confirmed = NO;
    id statusBlock = ^(id status) {
        NSInteger code = 0;
        BOOL hasCode = NO;
        if ([status respondsToSelector:@selector(integerValue)]) {
            code = [status integerValue];
            hasCode = YES;
        } else if ([status isKindOfClass:[NSError class]]) {
            hasCode = YES;
            code = ((NSError *)status).code;
        }
        confirmed = hasCode && code == 0;
        axs_playstar_log(@"mpc: perform status=%@ code=%ld confirmed=%d",
                         status, (long)code, confirmed);
    };
    typedef void (*PerformFn)(id, SEL, id, id);
    ((PerformFn)objc_msgSend)((id)requestClass, performSelector, request, statusBlock);

    axs_playstar_log(@"mpc: dispatched liked=%d command=%@ request=%@",
                     liked, NSStringFromClass([command class]),
                     NSStringFromClass([request class]));

    // 回执是同步/短异步的，留一点时间再读一遍真实状态。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL stateKnown = NO;
        id refreshed = [self axs_playstar_playingItemForSource:source];
        id refreshedCommand = axs_send_id(refreshed, @"likeCommand");
        if (refreshedCommand) {
            BOOL foundValue = NO;
            BOOL value = axs_send_bool(refreshedCommand, @"value", &foundValue);
            if (foundValue) {
                stateKnown = YES;
                confirmed = (value == liked);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            finish(confirmed, stateKnown ? @"播放器回报了状态" : @"已派发，播放器不回报状态");
        });
    });

    return AxsPlayStarVoteOutcomeDispatched;
}

#pragma mark - 诊断

/// 逐层打印对象图，定位到底断在哪一环。
+ (void)axs_playstar_dumpObjectGraphFrom:(id)source {
    axs_playstar_log(@"=== dump start source=%@", NSStringFromClass([source class]));

    id viewController = [self axs_playstar_viewControllerForSource:source];
    axs_playstar_log(@"dump: viewController=%@", viewController ? NSStringFromClass([viewController class]) : @"nil");
    if (!viewController) {
        // 响应链走不通时，把整条 nextResponder 链打出来看看到底挂在谁身上。
        id responder = source;
        NSMutableArray *chain = [NSMutableArray array];
        NSUInteger guard = 0;
        while (responder && guard++ < 40) {
            [chain addObject:NSStringFromClass([responder class])];
            if (![responder respondsToSelector:@selector(nextResponder)]) break;
            typedef id (*NextFn)(id, SEL);
            id next = ((NextFn)objc_msgSend)(responder, @selector(nextResponder));
            if (next == responder) break;
            responder = next;
        }
        axs_playstar_log(@"dump: responder chain=%@", [chain componentsJoinedByString:@" -> "]);
    }

    id controller = [self axs_playstar_controllerForSource:source];
    axs_playstar_log(@"dump: controller=%@", controller ? NSStringFromClass([controller class]) : @"nil");

    id response = [self axs_playstar_responseForSource:source];
    axs_playstar_log(@"dump: response=%@", response ? NSStringFromClass([response class]) : @"nil");

    if (controller) {
        NSArray *names = @[@"response", @"tracklist", @"metadataDataSource", @"endpointController",
                           @"nowPlayingController", @"playerPath"];
        for (NSString *name in names) {
            id value = axs_send_id(controller, name);
            axs_playstar_log(@"dump: controller.%@ = %@", name,
                             value ? NSStringFromClass([value class]) : @"nil");
        }
        // 把控制器上所有能返回对象的无参 getter 扫一遍，找真正的数据源。
        NSUInteger guard = 0;
        Class cls = [controller class];
        while (cls && guard++ < 6) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList(cls, &count);
            NSMutableArray *hits = [NSMutableArray array];
            for (unsigned int i = 0; i < count; i++) {
                SEL selector = method_getName(methods[i]);
                const char *types = method_getTypeEncoding(methods[i]);
                if (method_getNumberOfArguments(methods[i]) != 2) continue;
                if (!types || types[0] != '@') continue;
                NSString *name = NSStringFromSelector(selector);
                if ([name hasPrefix:@"_"] || [name containsString:@"delegate"]) continue;
                if (![controller respondsToSelector:selector]) continue;
                id value = axs_send_id(controller, name);
                if (value) [hits addObject:[NSString stringWithFormat:@"%@:%@", name, NSStringFromClass([value class])]];
            }
            free(methods);
            if (hits.count > 0) {
                axs_playstar_log(@"dump: %@ getters=%@", NSStringFromClass(cls),
                                 [hits componentsJoinedByString:@" | "]);
            }
            cls = class_getSuperclass(cls);
        }
    }

    if (response) {
        id tracklist = axs_send_id(response, @"tracklist");
        axs_playstar_log(@"dump: tracklist=%@", tracklist ? NSStringFromClass([tracklist class]) : @"nil");
        id item = axs_send_id(tracklist, @"playingItem");
        axs_playstar_log(@"dump: playingItem=%@", item ? NSStringFromClass([item class]) : @"nil");
        if (item) {
            NSArray *names = @[@"likeCommand", @"dislikeCommand", @"bookmarkCommand",
                               @"isFavoriteEligible", @"isFavorited", @"contentItemIdentifier"];
            for (NSString *name in names) {
                if (![item respondsToSelector:NSSelectorFromString(name)]) {
                    axs_playstar_log(@"dump: item.%@ = (no selector)", name);
                    continue;
                }
                id value = axs_send_id(item, name);
                axs_playstar_log(@"dump: item.%@ = %@", name,
                                 value ? [NSString stringWithFormat:@"%@ %@", NSStringFromClass([value class]), value] : @"nil");
            }
        }
    }
    axs_playstar_log(@"=== dump end");
}

@end
