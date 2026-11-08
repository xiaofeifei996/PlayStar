#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// 轻量日志：只有在设置里打开「调试日志」时才写文件，
// 路径固定为 /var/mobile/Documents/AxsPlayStar.log，方便用 Filza 或 SSH 取回。
void axs_playstar_log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
BOOL axs_playstar_debugEnabled(void);

#ifdef __cplusplus
}
#endif
