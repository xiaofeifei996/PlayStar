#import "AxsPlayStarRemote.h"
#import "AxsPlayStarPrivate.h"
#import "AxsPlayStarDebug.h"
#import <dlfcn.h>

// MediaRemote 常量名按字面量使用，避免链接到可能不存在的符号。
static NSString * const kAxsPlayStarInfoTitle         = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString * const kAxsPlayStarInfoArtist        = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString * const kAxsPlayStarInfoAlbum         = @"kMRMediaRemoteNowPlayingInfoAlbum";
static NSString * const kAxsPlayStarInfoUniqueID      = @"kMRMediaRemoteNowPlayingInfoUniqueIdentifier";
static NSString * const kAxsPlayStarInfoIsLiked       = @"kMRMediaRemoteNowPlayingInfoIsLiked";
static NSString * const kAxsPlayStarInfoSupportsLiked = @"kMRMediaRemoteNowPlayingInfoSupportsIsLiked";
static NSString * const kAxsPlayStarInfoIsMusicApp    = @"kMRMediaRemoteNowPlayingInfoIsMusicApp";
static NSString * const kAxsPlayStarInfoContentItem   = @"kMRMediaRemoteNowPlayingInfoContentItemIdentifier";
static NSString * const kAxsPlayStarDidChangeNote     = @"kMRMediaRemoteNowPlayingInfoDidChangeNotification";

@implementation AxsPlayStarTrack
@end

typedef void (*AxsPlayStarGetInfoFn)(dispatch_queue_t queue, void (^completion)(CFDictionaryRef info));

static AxsPlayStarGetInfoFn axs_playstar_infoSym;

@interface AxsPlayStarRemote ()
@property (nonatomic, assign) void *handle;
@property (nonatomic, copy, readwrite, nullable) NSString *axs_playstar_playerBundleID;
@end

static void axs_playstar_nowPlayingChanged(CFNotificationCenterRef center, void *observer,
                                           CFStringRef name, const void *object,
                                           CFDictionaryRef userInfo) {
    AxsPlayStarRemote *remote = (__bridge AxsPlayStarRemote *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (remote.changeHandler) remote.changeHandler();
    });
}

@implementation AxsPlayStarRemote

+ (instancetype)axs_playstar_shared {
    static AxsPlayStarRemote *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) [self axs_playstar_loadSymbols];
    return self;
}

- (void)axs_playstar_loadSymbols {
    axs_playstar_infoSym = (AxsPlayStarGetInfoFn)dlsym(RTLD_DEFAULT, "MRMediaRemoteGetNowPlayingInfo");
    if (axs_playstar_infoSym) return;
    self.handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (!self.handle) return;
    axs_playstar_infoSym = (AxsPlayStarGetInfoFn)dlsym(self.handle, "MRMediaRemoteGetNowPlayingInfo");
}

- (BOOL)axs_playstar_available {
    BOOL ok = axs_playstar_infoSym != NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        axs_playstar_log(@"mediaremote info=%d", axs_playstar_infoSym != NULL);
    });
    return ok;
}

- (void)axs_playstar_startObserving {
    static BOOL registered = NO;
    if (registered) return;
    registered = YES;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self, axs_playstar_nowPlayingChanged,
        (__bridge CFStringRef)kAxsPlayStarDidChangeNote, NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)axs_playstar_requestTrack:(void (^)(AxsPlayStarTrack *_Nullable))completion {
    if (!completion) return;
    if (!axs_playstar_infoSym) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    __weak typeof(self) weakSelf = self;
    axs_playstar_infoSym(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(CFDictionaryRef info) {
        NSDictionary *dictionary = [(__bridge NSDictionary *)info copy];
        AxsPlayStarTrack *track = [weakSelf axs_playstar_trackFromInfo:dictionary];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(track); });
    });
}

- (AxsPlayStarTrack *)axs_playstar_trackFromInfo:(NSDictionary *)info {
    // 诊断：先把系统到底给了什么写进日志。空字典是最常见的失败形态。
    if (![info isKindOfClass:[NSDictionary class]]) {
        axs_playstar_log(@"info: not a dictionary (%@)", NSStringFromClass([info class]));
        return nil;
    }
    axs_playstar_log(@"info: count=%lu keys=%@", (unsigned long)info.count,
                     [[info allKeys] componentsJoinedByString:@","]);
    if (info.count == 0) return nil;

    NSString *title = info[kAxsPlayStarInfoTitle];
    if (![title isKindOfClass:[NSString class]] || title.length == 0) {
        axs_playstar_log(@"info: no title (title=%@ artist=%@)", info[kAxsPlayStarInfoTitle],
                         info[kAxsPlayStarInfoArtist]);
        return nil;
    }

    AxsPlayStarTrack *track = [AxsPlayStarTrack new];
    track.title = title;
    track.artist = [info[kAxsPlayStarInfoArtist] isKindOfClass:[NSString class]] ? info[kAxsPlayStarInfoArtist] : @"";
    track.album = [info[kAxsPlayStarInfoAlbum] isKindOfClass:[NSString class]] ? info[kAxsPlayStarInfoAlbum] : @"";

    id uniqueID = info[kAxsPlayStarInfoUniqueID];
    NSString *identifier = [uniqueID respondsToSelector:@selector(stringValue)]
        ? [uniqueID stringValue]
        : ([uniqueID isKindOfClass:[NSString class]] ? uniqueID : @"");
    track.key = identifier.length > 0
        ? [NSString stringWithFormat:@"id:%@", identifier]
        : [NSString stringWithFormat:@"ta:%@|%@|%@", track.title, track.artist, track.album];

    id liked = info[kAxsPlayStarInfoIsLiked];
    track.systemLiked = [liked respondsToSelector:@selector(boolValue)] ? [liked boolValue] : NO;
    id supports = info[kAxsPlayStarInfoSupportsLiked];
    track.supportsVote = [supports respondsToSelector:@selector(boolValue)] ? [supports boolValue] : NO;

    id musicApp = info[kAxsPlayStarInfoIsMusicApp];
    track.bundleID = [musicApp respondsToSelector:@selector(boolValue)] && [musicApp boolValue]
        ? @"com.apple.Music" : @"";

    id contentItem = info[kAxsPlayStarInfoContentItem];
    track.contentItemID = [contentItem isKindOfClass:[NSString class]] ? contentItem : @"";

    axs_playstar_log(@"track title=%@ liked=%d supports=%d contentItem=%@",
                     track.title, track.systemLiked, track.supportsVote, track.contentItemID);
    return track;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
    if (_handle) dlclose(_handle);
}

@end
