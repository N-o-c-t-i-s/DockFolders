// Dock Folders — Dock helper.
//
// A small root launchd daemon, installed only when someone turns on "Open apps only in their
// folders" on a Mac with System Integrity Protection partly off. It watches for the Dock (it
// restarts now and then) and loads Dock Folders' payload into each new one, for users who have
// the option on. Root is needed because only root may open another process (task_for_pid), and
// even root only with SIP's debugging restrictions off.
//
// If the Dock keeps quitting soon after the payload goes in (a macOS update changed something),
// the helper stops for that user and leaves a note Dock Folders shows in Settings.
//
//   DockFoldersHelper --daemon         run as the launchd job
//   DockFoldersHelper --inject <pid>   load the payload into one Dock now (for testing)

#import <Foundation/Foundation.h>
#import <libproc.h>
#import <pwd.h>
#import <os/log.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import "loader.h"

static os_log_t DFLog;

static const char *DFDockPath = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock";
static const char *DFPayloadPath = "/Library/Application Support/Dock Folders/DockFoldersHook.dylib";

/// The Dock Folders support folder in the home of `uid`.
static NSString *DFSupportDir(uid_t uid) {
    struct passwd *pw = getpwuid(uid);
    if (!pw || !pw->pw_dir) return nil;
    return [[NSString stringWithUTF8String:pw->pw_dir] stringByAppendingPathComponent:@"Library/Application Support/Dock Folders"];
}

/// Whether this user has the option on (and the helper hasn't paused itself for them).
static BOOL DFWantedFor(uid_t uid) {
    NSString *dir = DFSupportDir(uid);
    if (!dir) return NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:[dir stringByAppendingPathComponent:@"HookPaused"]]) return NO;
    NSDictionary *list = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"HiddenInDock.plist"]];
    return [list[@"enabled"] boolValue];
}

static void DFPause(uid_t uid, NSString *reason) {
    NSString *dir = DFSupportDir(uid);
    if (!dir) return;
    NSString *file = [dir stringByAppendingPathComponent:@"HookPaused"];
    [reason writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chown(file.fileSystemRepresentation, uid, (gid_t)-1);
    os_log_error(DFLog, "paused for uid %d: %{public}@", uid, reason);
}

typedef struct { pid_t pid; uid_t uid; time_t started; } DFDock;

static NSArray<NSValue *> *DFDocks(void) {
    NSMutableArray *docks = [NSMutableArray array];
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return docks;
    pid_t *pids = calloc((size_t)count + 64, sizeof(pid_t));
    count = proc_listallpids(pids, (int)(((size_t)count + 64) * sizeof(pid_t)));
    char path[PROC_PIDPATHINFO_MAXSIZE];
    for (int i = 0; i < count; i++) {
        if (pids[i] <= 0 || proc_pidpath(pids[i], path, sizeof(path)) <= 0) continue;
        if (strcmp(path, DFDockPath) != 0) continue;
        struct proc_bsdinfo info;
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != (int)sizeof(info)) continue;
        DFDock dock = { pids[i], info.pbi_uid, (time_t)info.pbi_start_tvsec };
        [docks addObject:[NSValue valueWithBytes:&dock objCType:@encode(DFDock)]];
    }
    free(pids);
    return docks;
}

static int DFRunDaemon(void) {
    os_log(DFLog, "helper started");
    NSMutableDictionary<NSNumber *, NSDate *> *injected = [NSMutableDictionary dictionary];   // pid → when
    NSMutableDictionary<NSNumber *, NSNumber *> *owners = [NSMutableDictionary dictionary];    // pid → uid
    NSMutableDictionary<NSNumber *, NSMutableArray<NSDate *> *> *quickExits = [NSMutableDictionary dictionary]; // uid → times

    for (;;) {
        @autoreleasepool {
            NSArray *docks = DFDocks();
            NSMutableSet *alive = [NSMutableSet set];
            for (NSValue *value in docks) {
                DFDock dock;
                [value getValue:&dock];
                [alive addObject:@(dock.pid)];
            }

            // A Dock that went away soon after being loaded: count it (Dock Folders itself restarts
            // the Dock sometimes, so it takes a few in a row to pause).
            for (NSNumber *pid in injected.allKeys) {
                if ([alive containsObject:pid]) continue;
                NSDate *when = injected[pid];
                NSNumber *uid = owners[pid];
                [injected removeObjectForKey:pid];
                [owners removeObjectForKey:pid];
                if (!uid || [[NSDate date] timeIntervalSinceDate:when] > 20) continue;
                NSMutableArray *exits = quickExits[uid] ?: [NSMutableArray array];
                [exits addObject:[NSDate date]];
                [exits filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDate *d, id _) {
                    return [[NSDate date] timeIntervalSinceDate:d] < 180;
                }]];
                quickExits[uid] = exits;
                if (exits.count >= 3) {
                    DFPause(uid.unsignedIntValue, @"The Dock quit several times right after Dock Folders loaded into it.");
                    [exits removeAllObjects];
                }
            }

            for (NSValue *value in docks) {
                DFDock dock;
                [value getValue:&dock];
                if (injected[@(dock.pid)]) continue;
                // Let a new Dock finish starting up.
                if (time(NULL) - dock.started < 2) continue;
                if (!DFWantedFor(dock.uid)) continue;
                char error[256] = "";
                if (df_inject(dock.pid, DFPayloadPath, error, sizeof(error)) == 0) {
                    os_log(DFLog, "loaded into Dock %d", dock.pid);
                } else {
                    os_log_error(DFLog, "couldn't load into Dock %d: %{public}s", dock.pid, error);
                }
                // Once per Dock either way: a failure would only fail again.
                injected[@(dock.pid)] = [NSDate date];
                owners[@(dock.pid)] = @(dock.uid);
            }
        }
        sleep(1);
    }
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        DFLog = os_log_create("com.mylesdean.DockFolders", "Helper");
        if (argc >= 2 && strcmp(argv[1], "--daemon") == 0) return DFRunDaemon();
        if (argc >= 3 && strcmp(argv[1], "--inject") == 0) {
            char error[256] = "";
            int result = df_inject((pid_t)atoi(argv[2]), DFPayloadPath, error, sizeof(error));
            if (result != 0) fprintf(stderr, "%s\n", error);
            return result;
        }
        if (argc >= 2 && strcmp(argv[1], "--version") == 0) { printf("1\n"); return 0; }
        fprintf(stderr, "usage: %s --daemon | --inject <pid> | --version\n", argv[0]);
        return 2;
    }
}
