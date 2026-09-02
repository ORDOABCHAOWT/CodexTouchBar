#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

bool CTBPrivateTouchBarAvailable(void);
void CTBSetControlStripPresence(NSString *identifier, bool present);
void CTBSetSystemModalShowsCloseBox(bool showsCloseBox);
bool CTBAddSystemTrayItem(NSTouchBarItem *item);
void CTBRemoveSystemTrayItem(NSTouchBarItem *item);
bool CTBPresentSystemModalTouchBar(NSTouchBar *touchBar, NSString *identifier);
void CTBDismissSystemModalTouchBar(NSTouchBar *touchBar);

NS_ASSUME_NONNULL_END
