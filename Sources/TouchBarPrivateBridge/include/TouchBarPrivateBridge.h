#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

bool CTBPrivateTouchBarAvailable(void);
void CTBSetControlStripPresence(NSString *identifier, bool present);
void CTBSetSystemModalShowsCloseBox(bool showsCloseBox);
bool CTBAddSystemTrayItem(NSTouchBarItem *item);
void CTBRemoveSystemTrayItem(NSTouchBarItem *item);
bool CTBPresentSystemModalTouchBar(NSTouchBar *touchBar, NSString *identifier);
void CTBDismissSystemModalTouchBar(NSTouchBar *touchBar);

/// Sends a command to the current system media player without synthesizing keyboard events.
bool CTBMediaRemoteAvailable(void);
bool CTBSendMediaCommand(NSInteger command);

/// Returns recent Codex activity metadata only: id, display title source, workspace basename, time.
NSArray<NSDictionary<NSString *, id> *> *CTBReadRecentCodexActivity(NSTimeInterval recentSeconds);

NS_ASSUME_NONNULL_END
