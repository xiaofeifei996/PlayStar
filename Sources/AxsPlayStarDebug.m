#import "AxsPlayStarDebug.h"
#import "AxsPlayStarConfig.h"

static NSString * const kAxsPlayStarLogPath = @"/var/mobile/Documents/AxsPlayStar.log";

BOOL axs_playstar_debugEnabled(void) {
    id value = [[AxsPlayStarConfig axs_playstar_shared] axs_playstar_valueForKey:@"debugLog" defaultValue:@(NO)];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

void axs_playstar_log(NSString *format, ...) {
    if (!axs_playstar_debugEnabled()) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];

    static dispatch_queue_t queue;
    static dispatch_once_t queueOnce;
    dispatch_once(&queueOnce, ^{
        queue = dispatch_queue_create("com.axs.playstar.log", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(queue, ^{
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kAxsPlayStarLogPath];
        if (!handle) {
            [[NSFileManager defaultManager] createFileAtPath:kAxsPlayStarLogPath contents:nil attributes:nil];
            handle = [NSFileHandle fileHandleForWritingAtPath:kAxsPlayStarLogPath];
        }
        if (!handle) return;
        @try {
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        } @catch (__unused NSException *exception) {
        }
    });
}
