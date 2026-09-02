#import "TouchBarPrivateBridge.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sqlite3.h>

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

typedef Boolean (*CTBMediaCommandFunction)(NSInteger, id _Nullable);

static void *CTBMediaRemoteHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL);
    });
    return handle;
}

static CTBMediaCommandFunction CTBMediaCommandSymbol(void) {
    void *handle = CTBMediaRemoteHandle();
    return handle == NULL ? NULL : (CTBMediaCommandFunction)dlsym(handle, "MRMediaRemoteSendCommand");
}

bool CTBMediaRemoteAvailable(void) {
    if (CTBMediaCommandSymbol() != NULL) {
        return true;
    }
    Class controllerClass = NSClassFromString(@"MRNowPlayingController");
    SEL routeSelector = NSSelectorFromString(@"localRouteController");
    SEL commandSelector = NSSelectorFromString(@"sendCommand:options:completion:");
    if (controllerClass == Nil || ![controllerClass respondsToSelector:routeSelector]) {
        return false;
    }
    id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, routeSelector);
    return controller != nil && [controller respondsToSelector:commandSelector];
}

bool CTBSendMediaCommand(NSInteger command) {
    if (command < 0 || command > 5) {
        return false;
    }
    CTBMediaCommandFunction function = CTBMediaCommandSymbol();
    if (function != NULL) {
        return function(command, nil);
    }

    Class controllerClass = NSClassFromString(@"MRNowPlayingController");
    SEL routeSelector = NSSelectorFromString(@"localRouteController");
    SEL commandSelector = NSSelectorFromString(@"sendCommand:options:completion:");
    if (controllerClass == Nil || ![controllerClass respondsToSelector:routeSelector]) {
        return false;
    }
    id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, routeSelector);
    if (controller == nil || ![controller respondsToSelector:commandSelector]) {
        return false;
    }
    ((void (*)(id, SEL, NSInteger, id, id))objc_msgSend)(controller, commandSelector, command, @{}, nil);
    return true;
}

static NSString *CTBTextColumn(sqlite3_stmt *statement, int column) {
    const unsigned char *text = sqlite3_column_text(statement, column);
    return text == NULL ? @"" : [NSString stringWithUTF8String:(const char *)text];
}

NSArray<NSDictionary<NSString *, id> *> *CTBReadRecentCodexActivity(NSTimeInterval recentSeconds) {
    NSString *codexDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@".codex"];
    NSString *logsPath = [codexDirectory stringByAppendingPathComponent:@"logs_2.sqlite"];
    NSString *statePath = [codexDirectory stringByAppendingPathComponent:@"state_5.sqlite"];
    sqlite3 *logs = NULL;
    sqlite3 *state = NULL;
    NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];

    int flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX;
    if (sqlite3_open_v2(logsPath.fileSystemRepresentation, &logs, flags, NULL) != SQLITE_OK ||
        sqlite3_open_v2(statePath.fileSystemRepresentation, &state, flags, NULL) != SQLITE_OK) {
        if (logs != NULL) sqlite3_close(logs);
        if (state != NULL) sqlite3_close(state);
        return rows;
    }
    sqlite3_busy_timeout(logs, 150);
    sqlite3_busy_timeout(state, 150);

    const char *activitySQL =
        "SELECT thread_id, MAX(ts) FROM logs "
        "WHERE thread_id IS NOT NULL AND ts >= CAST(strftime('%s','now') AS INTEGER) - ? "
        "AND target IN ('codex_core::stream_events_utils','codex_core::session::turn',"
        "'codex_core::session::world_state','codex_core::tools::parallel','codex_goal_extension::runtime') "
        "GROUP BY thread_id ORDER BY MAX(ts) DESC LIMIT 12";
    const char *threadSQL =
        "SELECT COALESCE(NULLIF(name,''), NULLIF(preview,''), NULLIF(title,''), ''), cwd, source "
        "FROM threads WHERE id = ? LIMIT 1";
    sqlite3_stmt *activityStatement = NULL;
    sqlite3_stmt *threadStatement = NULL;

    if (sqlite3_prepare_v2(logs, activitySQL, -1, &activityStatement, NULL) == SQLITE_OK &&
        sqlite3_prepare_v2(state, threadSQL, -1, &threadStatement, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(activityStatement, 1, (sqlite3_int64)MAX(10, MIN(600, recentSeconds)));
        while (sqlite3_step(activityStatement) == SQLITE_ROW) {
            NSString *threadID = CTBTextColumn(activityStatement, 0);
            sqlite3_int64 updatedAt = sqlite3_column_int64(activityStatement, 1);
            if (threadID.length == 0) continue;

            sqlite3_reset(threadStatement);
            sqlite3_clear_bindings(threadStatement);
            sqlite3_bind_text(threadStatement, 1, threadID.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(threadStatement) != SQLITE_ROW) continue;

            NSString *source = CTBTextColumn(threadStatement, 2);
            if ([source rangeOfString:@"subagent" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                continue;
            }
            NSString *rawTitle = CTBTextColumn(threadStatement, 0);
            NSString *cwd = CTBTextColumn(threadStatement, 1);
            NSString *workspace = cwd.lastPathComponent.length > 0 ? cwd.lastPathComponent : @"Codex";
            [rows addObject:@{
                @"id": threadID,
                @"rawTitle": rawTitle,
                @"workspace": workspace,
                @"updatedAt": @(updatedAt),
            }];
        }
    }

    if (activityStatement != NULL) sqlite3_finalize(activityStatement);
    if (threadStatement != NULL) sqlite3_finalize(threadStatement);
    sqlite3_close(logs);
    sqlite3_close(state);
    return rows;
}
