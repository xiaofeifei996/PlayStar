#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import "AxsPlayStarController.h"
#import "AxsPlayStarRemote.h"
#import "AxsPlayStarDebug.h"

// 星标按钮的 frame 完整落在 MRUNowPlayingTransportControlsView 的 bounds 之外：
// 系统把这一排的可排区域左右各放宽一格（leading=-26 / routing=164.67，bounds 宽 164.67），
// 自己的 AirPlay 按钮就是靠这点画出边界的。UIKit 的命中测试不认可 bounds 外的子视图，
// 所以必须同时放宽宿主和它的父视图，触摸才能落到星标上。
%group AxsPlayStarControls

%hook MRUNowPlayingTransportControlsView

- (void)layoutSubviews {
    %orig;
    [[AxsPlayStarController axs_playstar_shared] axs_playstar_layoutInControlsView:(UIView *)self];
}

- (void)setTransportControls:(id)controls {
    %orig;
    [[AxsPlayStarController axs_playstar_shared] axs_playstar_installInControlsView:(UIView *)self];
}

- (void)setStylingProvider:(id)provider {
    %orig;
    [[AxsPlayStarController axs_playstar_shared] axs_playstar_installInControlsView:(UIView *)self];
}

- (void)setLayout:(long long)layout {
    %orig;
    [[AxsPlayStarController axs_playstar_shared] axs_playstar_installInControlsView:(UIView *)self];
}

- (void)didMoveToWindow {
    %orig;
    [[AxsPlayStarController axs_playstar_shared] axs_playstar_installInControlsView:(UIView *)self];
}

%end

%end

static void axs_playstar_installHooks(void) {
    static BOOL installed = NO;
    if (installed) return;
    if (!objc_getClass("MRUNowPlayingTransportControlsView")) return;
    installed = YES;
    %init(AxsPlayStarControls);
    [[AxsPlayStarRemote axs_playstar_shared] axs_playstar_startObserving];
}

static void axs_playstar_imageAdded(const struct mach_header *header, intptr_t slide) {
    axs_playstar_installHooks();
}

%ctor {
    dlopen("/System/Library/PrivateFrameworks/MediaControls.framework/MediaControls", RTLD_LAZY);
    axs_playstar_installHooks();
    if (!objc_getClass("MRUNowPlayingTransportControlsView")) {
        _dyld_register_func_for_add_image(axs_playstar_imageAdded);
    }
}
