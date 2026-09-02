#import "TouchBarPrivateBridge.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

typedef void (*CTBPresenceFunction)(NSString *, BOOL);
typedef void (*CTBCloseBoxFunction)(BOOL);

static void *CTBFrameworkHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY | RTLD_LOCAL);
    });
    return handle;
}

static void *CTBSymbol(const char *name) {
    void *handle = CTBFrameworkHandle();
    return handle == NULL ? NULL : dlsym(handle, name);
}

bool CTBPrivateTouchBarAvailable(void) {
    Class itemClass = NSClassFromString(@"NSTouchBarItem");
    Class barClass = NSClassFromString(@"NSTouchBar");
    SEL addSelector = NSSelectorFromString(@"addSystemTrayItem:");
    SEL presentSelector = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    SEL presentPlacementSelector = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    return CTBSymbol("DFRElementSetControlStripPresenceForIdentifier") != NULL
        && itemClass != Nil
        && [itemClass respondsToSelector:addSelector]
        && barClass != Nil
        && ([barClass respondsToSelector:presentSelector] || [barClass respondsToSelector:presentPlacementSelector]);
}

void CTBSetControlStripPresence(NSString *identifier, bool present) {
    CTBPresenceFunction function = (CTBPresenceFunction)CTBSymbol("DFRElementSetControlStripPresenceForIdentifier");
    if (function != NULL) {
        function(identifier, present ? YES : NO);
    }
}

void CTBSetSystemModalShowsCloseBox(bool showsCloseBox) {
    CTBCloseBoxFunction function = (CTBCloseBoxFunction)CTBSymbol("DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (function != NULL) {
        function(showsCloseBox ? YES : NO);
    }
}

bool CTBAddSystemTrayItem(NSTouchBarItem *item) {
    Class itemClass = NSClassFromString(@"NSTouchBarItem");
    SEL selector = NSSelectorFromString(@"addSystemTrayItem:");
    if (itemClass == Nil || ![itemClass respondsToSelector:selector]) {
        return false;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(itemClass, selector, item);
    return true;
}

void CTBRemoveSystemTrayItem(NSTouchBarItem *item) {
    Class itemClass = NSClassFromString(@"NSTouchBarItem");
    SEL selector = NSSelectorFromString(@"removeSystemTrayItem:");
    if (itemClass != Nil && [itemClass respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(itemClass, selector, item);
    }
}

bool CTBPresentSystemModalTouchBar(NSTouchBar *touchBar, NSString *identifier) {
    Class barClass = NSClassFromString(@"NSTouchBar");
    if (barClass == Nil) {
        return false;
    }

    SEL placementSelector = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    if ([barClass respondsToSelector:placementSelector]) {
        ((void (*)(id, SEL, id, NSInteger, id))objc_msgSend)(barClass, placementSelector, touchBar, 1, identifier);
        return true;
    }

    SEL selector = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    if ([barClass respondsToSelector:selector]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(barClass, selector, touchBar, identifier);
        return true;
    }

    SEL legacySelector = NSSelectorFromString(@"presentSystemModalFunctionBar:systemTrayItemIdentifier:");
    if ([barClass respondsToSelector:legacySelector]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(barClass, legacySelector, touchBar, identifier);
        return true;
    }
    return false;
}

void CTBDismissSystemModalTouchBar(NSTouchBar *touchBar) {
    Class barClass = NSClassFromString(@"NSTouchBar");
    for (NSString *selectorName in @[@"dismissSystemModalTouchBar:", @"dismissSystemModalFunctionBar:"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (barClass != Nil && [barClass respondsToSelector:selector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(barClass, selector, touchBar);
            return;
        }
    }
}
