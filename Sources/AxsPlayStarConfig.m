#import "AxsPlayStarConfig.h"
#import "AxsPlayStarPreferences.h"

@interface AxsPlayStarConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void axs_playstar_preferencesDidChange(CFNotificationCenterRef center, void *observer,
                                          CFStringRef name, const void *object, CFDictionaryRef info) {
    AxsPlayStarConfig *config = (__bridge AxsPlayStarConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config axs_playstar_reload];
    });
}

@implementation AxsPlayStarConfig

+ (instancetype)axs_playstar_shared {
    static AxsPlayStarConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.axs.playstar.preferences", DISPATCH_QUEUE_SERIAL);
        [self axs_playstar_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, axs_playstar_preferencesDidChange,
            (__bridge CFStringRef)AxsPlayStarPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self axs_playstar_reload]; });
    }
    return self;
}

- (void)axs_playstar_reload {
    self.snapshot = axs_playstar_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AxsPlayStarPreferencesChanged object:self];
    });
}

- (id)axs_playstar_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)axs_playstar_isEnabled {
    id value = [self axs_playstar_valueForKey:@"enabled" defaultValue:@(YES)];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
