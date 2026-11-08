#import "AxsPlayStarStore.h"

// 收藏状态与「配置文件」分开存放：设置面板仍是配置的唯一写入方，
// 这里只保存播放过程中累积的曲目 -> 收藏 映射。
static NSString * const kAxsPlayStarLikesFile = @"com.axs.playstar.likes.plist";
static const NSUInteger kAxsPlayStarLikesLimit = 4000;

static NSString *axs_playstar_likesPath(void) {
    NSString *prefs = axs_playstar_preferencesPath();
    NSString *dir = [prefs stringByDeletingLastPathComponent];
    return [dir stringByAppendingPathComponent:kAxsPlayStarLikesFile];
}

@implementation AxsPlayStarStore {
    NSMutableDictionary<NSString *, NSNumber *> *_likes;
    dispatch_queue_t _queue;
}

+ (instancetype)axs_playstar_shared {
    static AxsPlayStarStore *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.axs.playstar.likes", DISPATCH_QUEUE_SERIAL);
        NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:axs_playstar_likesPath()];
        _likes = [stored isKindOfClass:[NSDictionary class]] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)axs_playstar_flush {
    NSDictionary *snapshot = [_likes copy];
    dispatch_async(_queue, ^{
        [snapshot writeToFile:axs_playstar_likesPath() atomically:YES];
    });
}

- (BOOL)axs_playstar_isLikedKey:(NSString *)key systemState:(BOOL)systemLiked {
    // 系统（Apple Music）明确给出状态时以系统为准，其余播放器看本地记录。
    if (systemLiked) return YES;
    if (key.length == 0) return NO;
    return [_likes[key] boolValue];
}

- (void)axs_playstar_setLiked:(BOOL)liked forKey:(NSString *)key {
    if (key.length == 0) return;
    if (liked) {
        if (_likes.count >= kAxsPlayStarLikesLimit) [_likes removeAllObjects];
        _likes[key] = @YES;
    } else {
        [_likes removeObjectForKey:key];
    }
    [self axs_playstar_flush];
}

- (void)axs_playstar_forgetKey:(NSString *)key {
    [self axs_playstar_setLiked:NO forKey:key];
}

@end
