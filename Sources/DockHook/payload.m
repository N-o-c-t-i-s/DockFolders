// Dock Folders — Dock payload.
//
// Loaded into the Dock by Dock Folders' helper, only on Macs where System Integrity Protection is
// partly off (Settings → General → Open apps only in their folders). It keeps apps that live in a
// Dock Folders folder from getting their own running tile, so an open app shows only inside its
// folder. The apps themselves are untouched: they keep their menu bar, ⌘-Tab and Force Quit.
//
// What it changes, all through the Dock's own Objective-C methods (macOS 26):
//  • -[DockBar insertTile:atIndex:forReason:] / -[DockBar addTile:forReason:]: a running-app tile
//    (DOCKProcessTile) for a folder app is never put in the bar.
//  • -[DockBar addProcessForASN:separatorIndex:updateDirect:atLaunch:isLocked:]: folder apps are
//    skipped when the Dock lists running apps (returning the separator position unchanged, as
//    the Dock does for apps that get no tile).
//  • Apps already showing a tile when they go into a folder are handed to the Dock's own
//    "app went into the background" path (-[DockBar _handleDeathNotification:data:asn:]), the
//    one it uses when an app stops being a regular app.
//  • An app taken out of every folder while open gets its tile back via addProcessForASN.
// Anything it can't find (a different macOS), it leaves alone.
//
// The list of folder apps comes from ~/Library/Application Support/Dock Folders/HiddenInDock.plist,
// re-read whenever Dock Folders posts com.mylesdean.DockFolders.HiddenAppsChanged.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <os/lock.h>
#import <os/log.h>

#define DF_PAYLOAD_VERSION @"1"

static os_log_t DFLog;
static os_unfair_lock DFLock = OS_UNFAIR_LOCK_INIT;
static NSSet<NSString *> *DFHiddenIDs;
static NSSet<NSString *> *DFHiddenPaths;
static NSSet<NSString *> *DFPreviouslyHiddenPaths;
static __weak id DFDockBar;

static IMP DFOrigInsertTile, DFOrigAddTile, DFOrigAddProcess, DFOrigConvert, DFOrigTiles;

// LaunchServices (private, exported by CoreServices; already loaded in the Dock).
typedef CFTypeRef (*DFLSCopyItemFn)(int session, CFTypeRef asn, CFStringRef key);
typedef CFDictionaryRef (*DFLSCopyInfoFn)(int session, CFTypeRef asn, CFArrayRef keys);
typedef CFArrayRef (*DFLSRunningAppsFn)(int session);
static DFLSCopyItemFn DFLSCopyItem;
static DFLSCopyInfoFn DFLSCopyInfo;
static DFLSRunningAppsFn DFLSRunningApps;
static CFStringRef DFLSBundlePathKey;
static const int DFLSDefaultSession = -2;

#pragma mark - The list of folder apps

static NSString *DFNormalize(NSString *path) {
    if (path.length == 0) return nil;
    NSString *p = path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    while (p.length > 1 && [p hasSuffix:@"/"]) p = [p substringToIndex:p.length - 1];
    return p;
}

static NSString *DFListPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dock Folders/HiddenInDock.plist"];
}

static void DFLoadList(void) {
    NSDictionary *list = [NSDictionary dictionaryWithContentsOfFile:DFListPath()];
    BOOL enabled = [list[@"enabled"] boolValue];
    NSMutableSet *ids = [NSMutableSet set], *paths = [NSMutableSet set];
    if (enabled) {
        for (id value in ([list[@"bundleIDs"] isKindOfClass:NSArray.class] ? list[@"bundleIDs"] : @[]))
            if ([value isKindOfClass:NSString.class]) [ids addObject:value];
        for (id value in ([list[@"paths"] isKindOfClass:NSArray.class] ? list[@"paths"] : @[]))
            if ([value isKindOfClass:NSString.class] && DFNormalize(value)) [paths addObject:DFNormalize(value)];
    }
    os_unfair_lock_lock(&DFLock);
    DFPreviouslyHiddenPaths = DFHiddenPaths ?: [NSSet set];
    DFHiddenIDs = ids;
    DFHiddenPaths = paths;
    os_unfair_lock_unlock(&DFLock);
}

/// A folder app: matched by its location (so another copy of the same app still shows), or by
/// bundle identifier when the location isn't known.
static BOOL DFHides(NSString *bundleID, NSString *path) {
    NSString *p = DFNormalize(path);
    os_unfair_lock_lock(&DFLock);
    BOOL hide = p ? [DFHiddenPaths containsObject:p] : (bundleID && [DFHiddenIDs containsObject:bundleID]);
    os_unfair_lock_unlock(&DFLock);
    return hide;
}

#pragma mark - Tiles and apps

static BOOL DFIsProcessTile(id tile) {
    static Class processTile;
    if (!processTile) processTile = objc_getClass("DOCKProcessTile");
    return tile && processTile && [tile isKindOfClass:processTile];
}

static NSString *DFTileBundleID(id tile) {
    if (![tile respondsToSelector:@selector(bundleIdentifier)]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(tile, @selector(bundleIdentifier));
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSString *DFTilePath(id tile) {
    if (![tile respondsToSelector:@selector(fileURL)]) return nil;
    id url = ((id (*)(id, SEL))objc_msgSend)(tile, @selector(fileURL));
    return [url isKindOfClass:NSURL.class] ? [url path] : nil;
}

static BOOL DFTileHidden(id tile) {
    if (!DFIsProcessTile(tile)) return NO;
    @try {
        return DFHides(DFTileBundleID(tile), DFTilePath(tile));
    } @catch (NSException *e) {
        return NO;
    }
}

static NSString *DFASNString(id asn, CFStringRef key) {
    if (!DFLSCopyItem || !asn || !key) return nil;
    id value = CFBridgingRelease(DFLSCopyItem(DFLSDefaultSession, (__bridge CFTypeRef)asn, key));
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL DFASNHidden(id asn) {
    @try {
        return DFHides(DFASNString(asn, kCFBundleIdentifierKey), DFASNString(asn, DFLSBundlePathKey));
    } @catch (NSException *e) {
        return NO;
    }
}

static NSArray *DFTiles(id bar) {
    if (![bar respondsToSelector:@selector(tiles)]) return nil;
    id tiles = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(tiles));
    return [tiles isKindOfClass:NSArray.class] ? tiles : nil;
}

/// Running apps at `path` (their LaunchServices identities, for the Dock's own handlers). The
/// Dock doesn't load AppKit, so this asks LaunchServices directly.
static NSArray *DFASNsForPath(NSString *path) {
    NSString *target = DFNormalize(path);
    if (!DFLSRunningApps || !target) return @[];
    NSMutableArray *asns = [NSMutableArray array];
    NSArray *running = CFBridgingRelease(DFLSRunningApps(DFLSDefaultSession));
    for (id asn in running) {
        if ([DFNormalize(DFASNString(asn, DFLSBundlePathKey)) isEqualToString:target]) [asns addObject:asn];
    }
    return asns;
}

#pragma mark - Hooks

static void DFInsertTile(id self, SEL _cmd, id tile, long long index, id reason) {
    DFDockBar = self;
    if (DFTileHidden(tile)) return;
    ((void (*)(id, SEL, id, long long, id))DFOrigInsertTile)(self, _cmd, tile, index, reason);
}

static void DFAddTile(id self, SEL _cmd, id tile, id reason) {
    DFDockBar = self;
    if (DFTileHidden(tile)) return;
    ((void (*)(id, SEL, id, id))DFOrigAddTile)(self, _cmd, tile, reason);
}

static unsigned long DFAddProcess(id self, SEL _cmd, id asn, unsigned long separatorIndex,
                                  BOOL updateDirect, BOOL atLaunch, BOOL isLocked) {
    DFDockBar = self;
    if (DFASNHidden(asn)) return separatorIndex;
    return ((unsigned long (*)(id, SEL, id, unsigned long, BOOL, BOOL, BOOL))DFOrigAddProcess)(
        self, _cmd, asn, separatorIndex, updateDirect, atLaunch, isLocked);
}

static void DFSync(void);

// A kept app taken out of the Dock while open becomes a running tile in place.
static void DFConvert(id self, SEL _cmd, id tile, BOOL openIconCache) {
    ((void (*)(id, SEL, id, BOOL))DFOrigConvert)(self, _cmd, tile, openIconCache);
    DFDockBar = self;
    dispatch_async(dispatch_get_main_queue(), ^{ DFSync(); });
}

static id DFTilesGetter(id self, SEL _cmd) {
    DFDockBar = self;
    return ((id (*)(id, SEL))DFOrigTiles)(self, _cmd);
}

static IMP DFSwizzle(Class cls, SEL sel, IMP replacement, const char *expectedTypes) {
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        os_log_error(DFLog, "missing -[%{public}s %{public}s]", class_getName(cls), sel_getName(sel));
        return NULL;
    }
    // Only methods with the shape these replacements were written for (the Dock may change).
    const char *types = method_getTypeEncoding(method);
    if (expectedTypes && types) {
        NSString *have = [NSString stringWithUTF8String:types];
        NSString *want = [NSString stringWithUTF8String:expectedTypes];
        NSString *(^strip)(NSString *) = ^(NSString *s) {
            NSMutableString *out = [NSMutableString string];
            for (NSUInteger i = 0; i < s.length; i++) {
                unichar c = [s characterAtIndex:i];
                if (c >= '0' && c <= '9') continue;
                if (c == 'B') c = 'c';   // BOOL is 'B' on arm64, 'c' on x86_64
                [out appendFormat:@"%C", c];
            }
            return out;
        };
        if (![strip(have) isEqualToString:strip(want)]) {
            os_log_error(DFLog, "unexpected types for %{public}s: %{public}s", sel_getName(sel), types);
            return NULL;
        }
    }
    return method_setImplementation(method, replacement);
}

#pragma mark - Keeping the Dock in step with the list

/// Hands folder apps that still have a running tile to the Dock's "went into the background"
/// path, and gives apps that left every folder their tile back.
static void DFSync(void) {
    id bar = DFDockBar;
    if (!bar) return;
    @try {
        NSArray *tiles = DFTiles(bar);
        NSMutableSet *withTiles = [NSMutableSet set];
        SEL death = NSSelectorFromString(@"_handleDeathNotification:data:asn:");
        for (id tile in tiles) {
            NSString *path = DFNormalize(DFTilePath(tile));
            if (path) [withTiles addObject:path];
            if (!DFTileHidden(tile) || ![bar respondsToSelector:death] || !DFLSCopyInfo) continue;
            for (id asn in DFASNsForPath(path)) {
                NSDictionary *info = CFBridgingRelease(DFLSCopyInfo(DFLSDefaultSession, (__bridge CFTypeRef)asn, NULL));
                ((void (*)(id, SEL, int, id, id))objc_msgSend)(bar, death, 0, info, asn);
                os_log(DFLog, "took %{public}@ out of the Dock (it lives in a folder)", path.lastPathComponent);
            }
        }

        // Back from a folder while open: let the Dock add it the way it adds running apps.
        os_unfair_lock_lock(&DFLock);
        NSMutableSet *revealed = [DFPreviouslyHiddenPaths mutableCopy] ?: [NSMutableSet set];
        [revealed minusSet:DFHiddenPaths ?: [NSSet set]];
        DFPreviouslyHiddenPaths = DFHiddenPaths;
        os_unfair_lock_unlock(&DFLock);
        [revealed minusSet:withTiles];
        if (revealed.count == 0 || !DFOrigAddProcess) return;
        SEL separatorSel = @selector(separatorTile);
        id separator = [bar respondsToSelector:separatorSel] ? ((id (*)(id, SEL))objc_msgSend)(bar, separatorSel) : nil;
        for (NSString *path in revealed) {
            for (id asn in DFASNsForPath(path)) {
                NSUInteger index = separator ? [DFTiles(bar) indexOfObjectIdenticalTo:separator] : NSNotFound;
                if (index == NSNotFound) return;
                ((unsigned long (*)(id, SEL, id, unsigned long, BOOL, BOOL, BOOL))DFOrigAddProcess)(
                    bar, @selector(addProcessForASN:separatorIndex:updateDirect:atLaunch:isLocked:), asn, index, YES, NO, NO);
                os_log(DFLog, "gave %{public}@ its tile back", path.lastPathComponent);
            }
        }
    } @catch (NSException *e) {
        os_log_error(DFLog, "sync failed: %{public}@", e.reason);
    }
}

/// The Dock's bar object, once something has touched it (it's used constantly; at load time we
/// may need to wait a moment).
static void DFSyncWhenReady(int attempts) {
    if (DFDockBar || attempts <= 0) { DFSync(); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        DFSyncWhenReady(attempts - 1);
    });
}

static void DFReport(BOOL hooked) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dock Folders"];
    NSDictionary *status = @{ @"pid": @(getpid()), @"loaded": [NSDate date], @"version": DF_PAYLOAD_VERSION, @"hooked": @(hooked) };
    [status writeToFile:[dir stringByAppendingPathComponent:@"HookStatus.plist"] atomically:YES];
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.mylesdean.DockFolders.HookLoaded"
                                                                   object:nil userInfo:nil deliverImmediately:YES];
}

__attribute__((constructor))
static void DFLoad(void) {
    DFLog = os_log_create("com.mylesdean.DockFolders", "DockHook");
    // Load once per Dock (the helper never injects twice, but be safe).
    static BOOL loaded;
    if (loaded) return;
    loaded = YES;

    DFLSCopyItem = (DFLSCopyItemFn)dlsym(RTLD_DEFAULT, "_LSCopyApplicationInformationItem");
    DFLSCopyInfo = (DFLSCopyInfoFn)dlsym(RTLD_DEFAULT, "_LSCopyApplicationInformation");
    DFLSRunningApps = (DFLSRunningAppsFn)dlsym(RTLD_DEFAULT, "_LSCopyRunningApplicationArray");
    CFStringRef *pathKey = (CFStringRef *)dlsym(RTLD_DEFAULT, "_kLSBundlePathKey");
    DFLSBundlePathKey = pathKey ? *pathKey : CFSTR("LSBundlePath");

    dispatch_async(dispatch_get_main_queue(), ^{
        Class bar = objc_getClass("DockBar");
        if (!bar || !objc_getClass("DOCKProcessTile")) {
            os_log_error(DFLog, "this Dock isn't one Dock Folders knows; leaving it alone");
            DFReport(NO);
            return;
        }
        DFLoadList();
        DFOrigInsertTile = DFSwizzle(bar, @selector(insertTile:atIndex:forReason:), (IMP)DFInsertTile, "v@:@q@");
        DFOrigAddTile = DFSwizzle(bar, @selector(addTile:forReason:), (IMP)DFAddTile, "v@:@@");
        DFOrigAddProcess = DFSwizzle(bar, @selector(addProcessForASN:separatorIndex:updateDirect:atLaunch:isLocked:),
                                     (IMP)DFAddProcess, "Q@:@Qccc");
        DFOrigConvert = DFSwizzle(bar, @selector(convertFileTileToProcessTile:openIconCache:), (IMP)DFConvert, "v@:@c");
        DFOrigTiles = DFSwizzle(bar, @selector(tiles), (IMP)DFTilesGetter, "@@:");
        BOOL hooked = DFOrigInsertTile && DFOrigAddTile && DFOrigAddProcess;
        os_log(DFLog, "loaded into the Dock (hooks %{public}s)", hooked ? "in place" : "incomplete");

        [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"com.mylesdean.DockFolders.HiddenAppsChanged"
                                                                     object:nil queue:NSOperationQueue.mainQueue
                                                                 usingBlock:^(NSNotification *note) {
            DFLoadList();
            DFSync();
        }];
        DFSyncWhenReady(30);
        DFReport(hooked);
    });
}
