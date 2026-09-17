//
//  NotchMediaBridge.m
//  NotchIsland
//
//  Reads system-wide now-playing state from MediaRemote and streams it to the
//  app as newline-delimited JSON on stdout, accepting playback commands as
//  newline-delimited JSON on stdin.
//
//  Why this lives in a dynamic library instead of the app
//  -----------------------------------------------------
//  Since macOS 15.4, mediaremoted only answers MRMediaRemoteGetNowPlayingInfo
//  for callers whose main executable is signed by Apple. An ordinary app gets a
//  callback with an empty dictionary — no error, just nothing. Loading this
//  library into an Apple-signed host process (/usr/bin/perl) satisfies that
//  check, because the check looks at the process, not at what it has loaded.
//
//  The constructor takes over the host process: it never returns, and the host
//  never runs its own program. The process exits when its stdin closes, which
//  is how it notices the app going away.
//

#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

#pragma mark - MediaRemote

static NSString *const kMediaRemotePath =
    @"/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote";

typedef void (*MRGetNowPlayingInfo)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetNowPlayingClient)(dispatch_queue_t, void (^)(id));
typedef void (*MRGetIsPlaying)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRRegisterForNotifications)(dispatch_queue_t);
typedef void (*MRSetWantsNotifications)(BOOL);
typedef Boolean (*MRSendCommand)(int, NSDictionary *);
typedef void (*MRSetElapsedTime)(double);
typedef NSString *(*MRClientGetString)(id);

/// Commands understood by `MRMediaRemoteSendCommand`. Only the transport
/// subset the player actually exposes is listed.
typedef NS_ENUM(int, MRCommand) {
    MRCommandPlay = 0,
    MRCommandPause = 1,
    MRCommandTogglePlayPause = 2,
    MRCommandStop = 3,
    MRCommandNextTrack = 4,
    MRCommandPreviousTrack = 5,
};

static struct {
    void *handle;
    MRGetNowPlayingInfo getInfo;
    MRGetNowPlayingClient getClient;
    MRGetIsPlaying getIsPlaying;
    MRRegisterForNotifications registerForNotifications;
    MRSetWantsNotifications setWantsNotifications;
    MRSendCommand sendCommand;
    MRSetElapsedTime setElapsedTime;
    MRClientGetString clientBundleIdentifier;
    MRClientGetString clientParentBundleIdentifier;
    MRClientGetString clientDisplayName;
} MR;

static BOOL NMBLoadMediaRemote(void) {
    MR.handle = dlopen(kMediaRemotePath.fileSystemRepresentation, RTLD_NOW);
    if (MR.handle == NULL) {
        return NO;
    }

#define NMB_BIND(field, type, symbol) \
    MR.field = (type)dlsym(MR.handle, symbol)

    NMB_BIND(getInfo, MRGetNowPlayingInfo, "MRMediaRemoteGetNowPlayingInfo");
    NMB_BIND(getClient, MRGetNowPlayingClient, "MRMediaRemoteGetNowPlayingClient");
    NMB_BIND(getIsPlaying, MRGetIsPlaying, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    NMB_BIND(registerForNotifications, MRRegisterForNotifications,
             "MRMediaRemoteRegisterForNowPlayingNotifications");
    NMB_BIND(setWantsNotifications, MRSetWantsNotifications,
             "MRMediaRemoteSetWantsNowPlayingNotifications");
    NMB_BIND(sendCommand, MRSendCommand, "MRMediaRemoteSendCommand");
    NMB_BIND(setElapsedTime, MRSetElapsedTime, "MRMediaRemoteSetElapsedTime");
    NMB_BIND(clientBundleIdentifier, MRClientGetString,
             "MRNowPlayingClientGetBundleIdentifier");
    NMB_BIND(clientParentBundleIdentifier, MRClientGetString,
             "MRNowPlayingClientGetParentAppBundleIdentifier");
    NMB_BIND(clientDisplayName, MRClientGetString, "MRNowPlayingClientGetDisplayName");

#undef NMB_BIND

    // Everything else degrades gracefully, but without these three there is
    // nothing worth streaming.
    return MR.getInfo != NULL && MR.getClient != NULL && MR.registerForNotifications != NULL;
}

#pragma mark - Now-playing info keys

static NSString *const kInfoTitle = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString *const kInfoArtist = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString *const kInfoAlbum = @"kMRMediaRemoteNowPlayingInfoAlbum";
static NSString *const kInfoDuration = @"kMRMediaRemoteNowPlayingInfoDuration";
static NSString *const kInfoElapsed = @"kMRMediaRemoteNowPlayingInfoElapsedTime";
static NSString *const kInfoPlaybackRate = @"kMRMediaRemoteNowPlayingInfoPlaybackRate";
static NSString *const kInfoTimestamp = @"kMRMediaRemoteNowPlayingInfoTimestamp";
static NSString *const kInfoMediaType = @"kMRMediaRemoteNowPlayingInfoMediaType";
static NSString *const kInfoIsMusicApp = @"kMRMediaRemoteNowPlayingInfoIsMusicApp";
static NSString *const kInfoUniqueIdentifier = @"kMRMediaRemoteNowPlayingInfoUniqueIdentifier";
static NSString *const kInfoArtworkData = @"kMRMediaRemoteNowPlayingInfoArtworkData";
static NSString *const kInfoArtworkMIMEType = @"kMRMediaRemoteNowPlayingInfoArtworkMIMEType";
static NSString *const kInfoArtworkIdentifier = @"kMRMediaRemoteNowPlayingInfoArtworkIdentifier";

#pragma mark - Output

/// Serialises one JSON object per line on stdout. Called from the main queue
/// only, so no locking is needed around the buffered writes.
static void NMBEmit(NSDictionary *object) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (data == nil) {
        return;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void NMBEmitError(NSString *message) {
    NMBEmit(@{@"type": @"error", @"message": message ?: @"unknown"});
}

#pragma mark - Value coercion

/// MediaRemote hands back a mix of NSNumber, NSString and NSDate. Everything
/// that reaches JSON has to be one of those in a known shape, so each getter
/// below narrows explicitly rather than trusting the dictionary.

static NSString *NMBString(NSDictionary *info, NSString *key) {
    id value = info[key];
    if ([value isKindOfClass:NSString.class]) {
        NSString *string = value;
        return string.length > 0 ? string : nil;
    }
    return nil;
}

static NSNumber *NMBNumber(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

static NSNumber *NMBTimestamp(NSDictionary *info, NSString *key) {
    id value = info[key];
    if ([value isKindOfClass:NSDate.class]) {
        return @([(NSDate *)value timeIntervalSince1970]);
    }
    return nil;
}

/// `kMRMediaRemoteNowPlayingInfoMediaType` arrives as a string on some systems
/// and as a small integer on others. Normalised here so the app only ever sees
/// a string.
static NSString *NMBMediaType(NSDictionary *info) {
    id value = info[kInfoMediaType];
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }
    if ([value isKindOfClass:NSNumber.class]) {
        switch ([value intValue]) {
            case 1: return @"MRMediaRemoteMediaTypeMusic";
            case 2: return @"MRMediaRemoteMediaTypeVideo";
            case 3: return @"MRMediaRemoteMediaTypePodcast";
            default: break;
        }
    }
    return nil;
}

/// Artwork identifiers are numeric for some sources and string for others.
static NSString *NMBArtworkIdentifier(NSDictionary *info) {
    id value = info[kInfoArtworkIdentifier];
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }
    if ([value isKindOfClass:NSNumber.class]) {
        return [(NSNumber *)value stringValue];
    }
    return nil;
}

#pragma mark - Streaming state

/// Signature of the last payload sent, used to suppress duplicate emissions.
/// MediaRemote is chatty: a single track change can produce half a dozen
/// notifications carrying identical content.
static NSString *gLastSignature = nil;

/// Artwork already delivered to the app, so the bytes travel over the pipe once
/// per track rather than once per notification.
static NSString *gLastArtworkKey = nil;

/// Artwork retry bookkeeping. Some sources — Safari and Chrome in particular —
/// publish artwork metadata before the bytes exist: the dictionary carries a
/// MIME type and pixel dimensions but no data. Asking again a moment later
/// usually fills it in, so each track gets a short, bounded retry chain rather
/// than a retry on every notification.
static NSString *gArtworkPendingTrack = nil;
static NSUInteger gArtworkAttempt = 0;
static BOOL gArtworkRetryInFlight = NO;

/// Back-off schedule for those retries. A track that still has no bytes after
/// the last one is treated as having no artwork, and the app falls back to the
/// source application's icon.
static const NSTimeInterval kArtworkRetryDelays[] = {0.4, 1.2, 3.0};
static const NSUInteger kArtworkRetryCount =
    sizeof(kArtworkRetryDelays) / sizeof(kArtworkRetryDelays[0]);

static void NMBPublish(void);

static void NMBScheduleArtworkRetry(void) {
    if (gArtworkRetryInFlight || gArtworkAttempt >= kArtworkRetryCount) {
        return;
    }
    NSTimeInterval delay = kArtworkRetryDelays[gArtworkAttempt];
    gArtworkAttempt += 1;
    gArtworkRetryInFlight = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        gArtworkRetryInFlight = NO;
        NMBPublish();
    });
}

static void NMBEmitArtwork(NSDictionary *info, NSString *trackKey) {
    NSString *track = trackKey ?: @"-";
    if (![track isEqualToString:gArtworkPendingTrack]) {
        gArtworkPendingTrack = track;
        gArtworkAttempt = 0;
    }

    id data = info[kInfoArtworkData];
    if (![data isKindOfClass:NSData.class] || [(NSData *)data length] == 0) {
        // Metadata without bytes means the source is still fetching.
        if (info[kInfoArtworkMIMEType] != nil || info[kInfoArtworkIdentifier] != nil) {
            NMBScheduleArtworkRetry();
        }
        return;
    }

    // Bytes arrived, so no further attempts are needed for this track.
    gArtworkAttempt = kArtworkRetryCount;

    NSString *identifier = NMBArtworkIdentifier(info);
    NSString *key = [NSString stringWithFormat:@"%@|%@|%lu", trackKey ?: @"-",
                                               identifier ?: @"-",
                                               (unsigned long)[(NSData *)data length]];
    if ([key isEqualToString:gLastArtworkKey]) {
        return;
    }
    gLastArtworkKey = key;

    NMBEmit(@{
        @"type": @"artwork",
        @"key": key,
        @"mimeType": NMBString(info, kInfoArtworkMIMEType) ?: @"application/octet-stream",
        @"data": [(NSData *)data base64EncodedStringWithOptions:0],
    });
}

/// Fetches the current state and, if it differs from what the app already has,
/// emits it.
static void NMBPublish(void) {
    MR.getInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
        MR.getClient(dispatch_get_main_queue(), ^(id client) {
            NSMutableDictionary *payload = [NSMutableDictionary dictionary];

            NSString *title = NMBString(info, kInfoTitle);
            NSString *bundleIdentifier = nil;
            NSString *parentBundleIdentifier = nil;
            NSString *appName = nil;

            if (client != nil) {
                if (MR.clientBundleIdentifier != NULL) {
                    bundleIdentifier = MR.clientBundleIdentifier(client);
                }
                if (MR.clientParentBundleIdentifier != NULL) {
                    parentBundleIdentifier = MR.clientParentBundleIdentifier(client);
                }
                if (MR.clientDisplayName != NULL) {
                    appName = MR.clientDisplayName(client);
                }
            }

            // No title and no source means nothing is loaded anywhere. The app
            // treats this as "hide the island".
            if (title == nil && bundleIdentifier == nil && parentBundleIdentifier == nil) {
                if (![gLastSignature isEqualToString:@"idle"]) {
                    gLastSignature = @"idle";
                    gLastArtworkKey = nil;
                    gArtworkPendingTrack = nil;
                    NMBEmit(@{@"type": @"idle"});
                }
                return;
            }

            payload[@"title"] = title ?: @"";
            if (NMBString(info, kInfoArtist)) payload[@"artist"] = NMBString(info, kInfoArtist);
            if (NMBString(info, kInfoAlbum)) payload[@"album"] = NMBString(info, kInfoAlbum);
            if (bundleIdentifier) payload[@"bundleIdentifier"] = bundleIdentifier;
            if (parentBundleIdentifier) payload[@"parentBundleIdentifier"] = parentBundleIdentifier;
            if (appName) payload[@"appName"] = appName;
            if (NMBMediaType(info)) payload[@"mediaType"] = NMBMediaType(info);
            if (NMBNumber(info, kInfoIsMusicApp)) payload[@"isMusicApp"] = NMBNumber(info, kInfoIsMusicApp);
            if (NMBNumber(info, kInfoDuration)) payload[@"duration"] = NMBNumber(info, kInfoDuration);
            if (NMBNumber(info, kInfoElapsed)) payload[@"elapsedTime"] = NMBNumber(info, kInfoElapsed);
            if (NMBNumber(info, kInfoPlaybackRate)) payload[@"playbackRate"] = NMBNumber(info, kInfoPlaybackRate);
            if (NMBTimestamp(info, kInfoTimestamp)) payload[@"timestamp"] = NMBTimestamp(info, kInfoTimestamp);
            if (NMBString(info, kInfoUniqueIdentifier)) {
                payload[@"trackIdentifier"] = NMBString(info, kInfoUniqueIdentifier);
            } else if (NMBNumber(info, kInfoUniqueIdentifier)) {
                payload[@"trackIdentifier"] = [NMBNumber(info, kInfoUniqueIdentifier) stringValue];
            }

            NSString *trackKey = payload[@"trackIdentifier"] ?: title;

            void (^finish)(BOOL) = ^(BOOL isPlaying) {
                payload[@"isPlaying"] = @(isPlaying);

                // The signature deliberately leaves out elapsed time and
                // timestamp: those move constantly, and the app interpolates
                // position locally between real changes.
                NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%d",
                                       payload[@"title"] ?: @"",
                                       payload[@"artist"] ?: @"",
                                       payload[@"album"] ?: @"",
                                       trackKey ?: @"",
                                       payload[@"bundleIdentifier"] ?: @"",
                                       isPlaying];

                // Position still has to be resent when playback is scrubbed
                // while paused, so compare the rounded elapsed time too.
                NSNumber *elapsed = payload[@"elapsedTime"];
                NSString *fullSignature = [NSString stringWithFormat:@"%@|%ld", signature,
                                           (long)llround(elapsed.doubleValue)];

                if (![fullSignature isEqualToString:gLastSignature]) {
                    gLastSignature = fullSignature;
                    NMBEmit(@{@"type": @"state", @"payload": payload});
                }

                NMBEmitArtwork(info, trackKey);
            };

            if (MR.getIsPlaying != NULL) {
                MR.getIsPlaying(dispatch_get_main_queue(), ^(BOOL isPlaying) {
                    finish(isPlaying);
                });
            } else {
                finish(NMBNumber(info, kInfoPlaybackRate).doubleValue > 0.0);
            }
        });
    });
}

#pragma mark - Commands

static void NMBHandleCommand(NSDictionary *command) {
    NSString *name = command[@"cmd"];
    if (![name isKindOfClass:NSString.class]) {
        return;
    }

    if ([name isEqualToString:@"refresh"]) {
        gLastSignature = nil;
        gLastArtworkKey = nil;
        gArtworkPendingTrack = nil;
        gArtworkAttempt = 0;
        NMBPublish();
        return;
    }

    if ([name isEqualToString:@"seek"]) {
        id value = command[@"value"];
        if (MR.setElapsedTime != NULL && [value isKindOfClass:NSNumber.class]) {
            MR.setElapsedTime([value doubleValue]);
            // The source reports its new position asynchronously; nudge it.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                gLastSignature = nil;
                NMBPublish();
            });
        }
        return;
    }

    if (MR.sendCommand == NULL) {
        return;
    }

    MRCommand code;
    if ([name isEqualToString:@"playpause"]) {
        code = MRCommandTogglePlayPause;
    } else if ([name isEqualToString:@"play"]) {
        code = MRCommandPlay;
    } else if ([name isEqualToString:@"pause"]) {
        code = MRCommandPause;
    } else if ([name isEqualToString:@"next"]) {
        code = MRCommandNextTrack;
    } else if ([name isEqualToString:@"previous"]) {
        code = MRCommandPreviousTrack;
    } else if ([name isEqualToString:@"stop"]) {
        code = MRCommandStop;
    } else {
        return;
    }

    MR.sendCommand(code, @{});
}

/// PID of the app that launched this host, captured before anything can
/// reparent us.
static pid_t gParentPID = 0;

/// Watches for the app going away.
///
/// Relying on stdin reaching EOF is not enough: the write end of the pipe stays
/// open in this process, so the read end never reports EOF even after the app
/// is gone and this process has been reparented to launchd. Without an explicit
/// watch, killing the app would leave a perl process running forever.
static void NMBWatchParent(void) {
    gParentPID = getppid();

    // Already orphaned before we got started.
    if (gParentPID <= 1) {
        exit(0);
    }

    dispatch_source_t source =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)gParentPID,
                               DISPATCH_PROC_EXIT, dispatch_get_main_queue());
    if (source != NULL) {
        dispatch_source_set_event_handler(source, ^{
            exit(0);
        });
        dispatch_resume(source);
    }
}

/// Second line of defence, and in practice the one that does the work: the
/// process source above turns out not to fire reliably for this case on current
/// macOS, so orphan detection cannot depend on it. Polling `getppid` once a
/// second is a single cheap syscall and notices within a second of the app
/// going away, however it went.
static void NMBExitIfOrphaned(void) {
    if (gParentPID > 1 && kill(gParentPID, 0) != 0 && errno == ESRCH) {
        exit(0);
    }
    if (getppid() <= 1) {
        exit(0);
    }
}

/// Reads newline-delimited command objects from stdin. An EOF here means the
/// app has gone away — the host process exits rather than lingering.
static void NMBStartCommandReader(void) {
    dispatch_queue_t queue = dispatch_queue_create("com.notchisland.bridge.stdin",
                                                   DISPATCH_QUEUE_SERIAL);
    dispatch_source_t source =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);

    __block NSMutableData *buffer = [NSMutableData data];

    dispatch_source_set_event_handler(source, ^{
        char chunk[4096];
        ssize_t count = read(STDIN_FILENO, chunk, sizeof(chunk));
        if (count <= 0) {
            exit(0);
        }
        [buffer appendBytes:chunk length:(NSUInteger)count];

        while (YES) {
            NSRange newline = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1]
                                          options:0
                                            range:NSMakeRange(0, buffer.length)];
            if (newline.location == NSNotFound) {
                break;
            }
            NSData *line = [buffer subdataWithRange:NSMakeRange(0, newline.location)];
            [buffer replaceBytesInRange:NSMakeRange(0, NSMaxRange(newline)) withBytes:NULL length:0];

            if (line.length == 0) {
                continue;
            }
            id object = [NSJSONSerialization JSONObjectWithData:line options:0 error:NULL];
            if ([object isKindOfClass:NSDictionary.class]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NMBHandleCommand(object);
                });
            }
        }
    });

    dispatch_source_set_cancel_handler(source, ^{
        exit(0);
    });

    dispatch_resume(source);
}

#pragma mark - Entry point

static void NMBObserveNotifications(void) {
    NSArray<NSString *> *names = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification",
        @"kMRNowPlayingPlaybackQueueChangedNotification",
    ];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in names) {
        [center addObserverForName:name
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *notification) {
            NMBPublish();
        }];
    }
}

__attribute__((constructor)) static void NMBMain(void) {
    @autoreleasepool {
        // The app closes the read end of the pipe when it quits; without this,
        // the first write afterwards would kill the process with SIGPIPE before
        // the stdin reader ever noticed.
        signal(SIGPIPE, SIG_IGN);
        setvbuf(stdout, NULL, _IOFBF, 1 << 16);

        if (!NMBLoadMediaRemote()) {
            NMBEmitError(@"MediaRemote is unavailable on this system");
            exit(1);
        }

        MR.registerForNotifications(dispatch_get_main_queue());
        if (MR.setWantsNotifications != NULL) {
            MR.setWantsNotifications(YES);
        }
        NMBWatchParent();
        NMBObserveNotifications();
        NMBStartCommandReader();

        NMBEmit(@{@"type": @"ready", @"parentPID": @(gParentPID), @"pid": @(getpid())});
        NMBPublish();

        // Orphan check. Runs every second so a quit app does not leave this
        // process behind for any noticeable length of time.
        dispatch_source_t orphanCheck =
            dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(orphanCheck, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                                  NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(orphanCheck, ^{
            NMBExitIfOrphaned();
        });
        dispatch_resume(orphanCheck);

        // A slow heartbeat. Notifications cover essentially every change, but a
        // source that dies without notifying would otherwise leave the island
        // showing a stale track forever.
        dispatch_source_t heartbeat =
            dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(heartbeat, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                                  5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(heartbeat, ^{
            NMBPublish();
        });
        dispatch_resume(heartbeat);

        // Takes over the host process for good.
        dispatch_main();
    }
}
