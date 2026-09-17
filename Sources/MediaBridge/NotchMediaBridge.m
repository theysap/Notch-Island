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
static NSString *const kInfoArtworkURL = @"kMRMediaRemoteNowPlayingInfoArtworkURL";
static NSString *const kInfoContentType = @"kMRMediaRemoteNowPlayingInfoContentType";

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

/// Signature of the last status sent, so an unchanged status is not resent.
static NSString *gLastSignature = nil;

/// Artwork already delivered, so the same cover is not sent twice.
static NSString *gLastArtworkKey = nil;

/// Last playing state reported, from whichever source reported it.
static BOOL gLastKnownIsPlaying = NO;

/// Artwork identifiers are not always identifiers. Apple Music puts an https
/// URL in this field and no image bytes anywhere, so a URL is forwarded to the
/// app to fetch. Browser sources use a numeric identifier and, sometimes,
/// bytes.
static NSString *NMBArtworkURLString(NSDictionary *info) {
    NSString *candidate =
        NMBString(info, kInfoArtworkURL) ?: NMBString(info, kInfoArtworkIdentifier);
    if (candidate == nil) {
        return nil;
    }
    if ([candidate hasPrefix:@"https://"] || [candidate hasPrefix:@"http://"]) {
        return candidate;
    }
    return nil;
}

static void NMBEmitArtwork(NSDictionary *info, NSString *trackKey) {
    NSString *track = trackKey ?: @"-";

    // Bytes, when the source supplies them.
    id data = info[kInfoArtworkData];
    if ([data isKindOfClass:NSData.class] && [(NSData *)data length] > 0) {
        NSString *key = [NSString stringWithFormat:@"%@|bytes|%lu", track,
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
        return;
    }

    // Otherwise a URL, which the app fetches and caches.
    NSString *url = NMBArtworkURLString(info);
    if (url != nil) {
        NSString *key = [NSString stringWithFormat:@"%@|url|%@", track, url];
        if ([key isEqualToString:gLastArtworkKey]) {
            return;
        }
        gLastArtworkKey = key;

        NMBEmit(@{@"type": @"artworkURL", @"key": key, @"url": url});
    }
}

/// Reads the identity of whatever is playing off a client object.
static void NMBClientIdentity(id client, NSString **bundleIdentifier,
                              NSString **parentBundleIdentifier, NSString **appName) {
    *bundleIdentifier = nil;
    *parentBundleIdentifier = nil;
    *appName = nil;

    if (client == nil) {
        return;
    }
    if (MR.clientBundleIdentifier != NULL) {
        *bundleIdentifier = MR.clientBundleIdentifier(client);
    }
    if (MR.clientParentBundleIdentifier != NULL) {
        *parentBundleIdentifier = MR.clientParentBundleIdentifier(client);
    }
    if (MR.clientDisplayName != NULL) {
        *appName = MR.clientDisplayName(client);
    }
}

/// Builds the payload for a track, or nil when the dictionary holds nothing
/// worth showing.
///
/// A source with no title, artist or duration is a player sitting open with
/// nothing loaded. The island shows nothing at all in that case: an island
/// containing only an application icon tells nobody anything.
static NSDictionary *NMBBuildPayload(NSDictionary *info, id client, BOOL isPlaying) {
    NSString *bundleIdentifier = nil;
    NSString *parentBundleIdentifier = nil;
    NSString *appName = nil;
    NMBClientIdentity(client, &bundleIdentifier, &parentBundleIdentifier, &appName);

    NSString *title = NMBString(info, kInfoTitle);
    BOOL hasSubstance = title != nil || NMBString(info, kInfoArtist) != nil
                        || NMBNumber(info, kInfoDuration) != nil;
    if (!hasSubstance) {
        return nil;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"title"] = title ?: @"";
    if (NMBString(info, kInfoArtist)) payload[@"artist"] = NMBString(info, kInfoArtist);
    if (NMBString(info, kInfoAlbum)) payload[@"album"] = NMBString(info, kInfoAlbum);
    if (bundleIdentifier) payload[@"bundleIdentifier"] = bundleIdentifier;
    if (parentBundleIdentifier) payload[@"parentBundleIdentifier"] = parentBundleIdentifier;
    if (appName) payload[@"appName"] = appName;
    if (NMBMediaType(info)) payload[@"mediaType"] = NMBMediaType(info);
    if (NMBString(info, kInfoContentType)) {
        payload[@"contentType"] = NMBString(info, kInfoContentType);
    }
    if (NMBNumber(info, kInfoIsMusicApp)) payload[@"isMusicApp"] = NMBNumber(info, kInfoIsMusicApp);
    if (NMBNumber(info, kInfoDuration)) payload[@"duration"] = NMBNumber(info, kInfoDuration);
    if (NMBNumber(info, kInfoElapsed)) payload[@"elapsedTime"] = NMBNumber(info, kInfoElapsed);
    if (NMBNumber(info, kInfoPlaybackRate)) {
        payload[@"playbackRate"] = NMBNumber(info, kInfoPlaybackRate);
    }
    if (NMBTimestamp(info, kInfoTimestamp)) {
        payload[@"timestamp"] = NMBTimestamp(info, kInfoTimestamp);
    }
    if (NMBString(info, kInfoUniqueIdentifier)) {
        payload[@"trackIdentifier"] = NMBString(info, kInfoUniqueIdentifier);
    } else if (NMBNumber(info, kInfoUniqueIdentifier)) {
        payload[@"trackIdentifier"] = [NMBNumber(info, kInfoUniqueIdentifier) stringValue];
    }
    // The playback rate in the dictionary is the most trustworthy account of
    // whether this is actually playing: it came from the source along with
    // everything else here, at the same instant. The value passed in is a
    // fallback for sources that omit it.
    // The cast matters: in C a comparison yields `int`, so boxing it without
    // one produces a number rather than a boolean, and the JSON carries 1
    // instead of true.
    NSNumber *rate = NMBNumber(info, kInfoPlaybackRate);
    payload[@"isPlaying"] = rate != nil ? @((BOOL)(rate.doubleValue > 0)) : @(isPlaying);

    return payload;
}

#pragma mark - One-shot mode

/// Fetches the now-playing dictionary once, prints it, and exits.
///
/// This exists because `MRMediaRemoteGetNowPlayingInfo` hands its dictionary to
/// a given process **once**. A long-lived process asking repeatedly gets
/// nothing: measured at 13 asks and 0 replies across two track changes, while
/// fresh processes answered correctly every time at the same moments. So each
/// refresh gets a brand new process, and this is what it runs.
///
/// Nothing is registered for notifications here — this process exists for a few
/// hundred milliseconds and only asks its one question.
static void NMBFetchOnce(void) {
    __block BOOL finished = NO;
    __block NSDictionary *info = nil;
    __block id client = nil;
    __block BOOL haveInfo = NO;
    __block BOOL haveClient = NO;

    void (^complete)(void) = ^{
        if (finished) {
            return;
        }
        finished = YES;

        NSDictionary *payload = NMBBuildPayload(info, client, gLastKnownIsPlaying);
        if (payload != nil) {
            NMBEmit(@{@"type": @"state", @"payload": payload});
            NMBEmitArtwork(info, payload[@"trackIdentifier"] ?: payload[@"title"]);
        } else if (client == nil) {
            // Nothing is registered anywhere.
            NMBEmit(@{@"type": @"idle"});
        } else if (haveInfo && info.count > 0) {
            // The daemon answered, and the source genuinely has nothing loaded.
            NMBEmit(@{@"type": @"idle"});
        } else {
            // No answer at all. That is the normal outcome when the dictionary
            // has not changed since the daemon last handed it over, and says
            // nothing about whether something is playing — so it must not be
            // reported as idle. The app keeps whatever it already had.
            NMBEmit(@{@"type": @"nodata"});
        }
        exit(0);
    };

    void (^checkComplete)(void) = ^{
        if (haveInfo && haveClient) {
            complete();
        }
    };

    MR.getInfo(dispatch_get_main_queue(), ^(NSDictionary *fetched) {
        info = fetched;
        haveInfo = YES;
        checkComplete();
    });

    MR.getClient(dispatch_get_main_queue(), ^(id fetched) {
        client = fetched;
        haveClient = YES;
        checkComplete();
    });

    if (MR.getIsPlaying != NULL) {
        MR.getIsPlaying(dispatch_get_main_queue(), ^(BOOL playing) {
            gLastKnownIsPlaying = playing;
        });
    }

    // The dictionary is only handed over when it has changed since the daemon
    // last delivered it, so an unanswered query is normal rather than a
    // failure. Report whatever did arrive and quit.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       complete();
                   });
}

#pragma mark - Streaming mode

/// Reports who is playing and whether they are playing.
///
/// This carries no track metadata: the streaming process cannot obtain any
/// after its first attempt. The app treats a change here as its cue to run a
/// one-shot fetch.
static void NMBEmitStatus(id client, BOOL isPlaying) {
    NSString *bundleIdentifier = nil;
    NSString *parentBundleIdentifier = nil;
    NSString *appName = nil;
    NMBClientIdentity(client, &bundleIdentifier, &parentBundleIdentifier, &appName);

    if (client == nil) {
        if (![gLastSignature isEqualToString:@"idle"]) {
            gLastSignature = @"idle";
            NMBEmit(@{@"type": @"idle"});
        }
        return;
    }

    NSString *signature = [NSString stringWithFormat:@"%@|%@|%d",
                                                     bundleIdentifier ?: @"",
                                                     parentBundleIdentifier ?: @"", isPlaying];
    if ([signature isEqualToString:gLastSignature]) {
        return;
    }
    gLastSignature = signature;

    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    status[@"type"] = @"status";
    status[@"isPlaying"] = @(isPlaying);
    if (bundleIdentifier) status[@"bundleIdentifier"] = bundleIdentifier;
    if (parentBundleIdentifier) status[@"parentBundleIdentifier"] = parentBundleIdentifier;
    if (appName) status[@"appName"] = appName;

    NMBEmit(status);
}

/// Asks who is playing. Unlike the dictionary, this answers every time, which
/// is what makes it usable as the test for whether anything is playing at all.
static void NMBRefreshStatus(void) {
    MR.getClient(dispatch_get_main_queue(), ^(id client) {
        NMBEmitStatus(client, gLastKnownIsPlaying);
    });
}

/// Forces the next status to be sent even if nothing has changed.
static void NMBInvalidateStatus(void) {
    gLastSignature = nil;
}

/// When the last `changed` event was sent.
static NSTimeInterval gLastChangeEmit = 0;

/// Tells the app something moved, so it should re-read the dictionary.
///
/// This is separate from the status because a *track* change alters neither the
/// client nor the playing state — status alone would report nothing new, and
/// the app would never refetch. Notifications arrive in bursts of three to six
/// for a single event, so they are coalesced.
static void NMBEmitChanged(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - gLastChangeEmit < 0.25) {
        return;
    }
    gLastChangeEmit = now;
    NMBEmit(@{@"type": @"changed"});
}

#pragma mark - Commands

static void NMBHandleCommand(NSDictionary *command) {
    NSString *name = command[@"cmd"];
    if (![name isKindOfClass:NSString.class]) {
        return;
    }

    // Acknowledged so a command that goes nowhere can be told apart from one
    // that never arrived.
    NMBEmit(@{@"type": @"ack", @"cmd": name});

    if ([name isEqualToString:@"refresh"]) {
        NMBInvalidateStatus();
        NMBRefreshStatus();
        return;
    }

    if ([name isEqualToString:@"seek"]) {
        id value = command[@"value"];
        if (MR.setElapsedTime != NULL && [value isKindOfClass:NSNumber.class]) {
            MR.setElapsedTime([value doubleValue]);
            // The source reports its new position asynchronously; nudge it.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                               NMBInvalidateStatus();
                               NMBRefreshStatus();
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
/// Held for the life of the process. A dispatch source released by ARC when
/// the function that made it returns stops delivering events, which is what
/// silently broke every transport command.
static dispatch_source_t gCommandSource = nil;

static void NMBStartCommandReader(void) {
    dispatch_queue_t queue = dispatch_queue_create("com.notchisland.bridge.stdin",
                                                   DISPATCH_QUEUE_SERIAL);
    dispatch_source_t source =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
    gCommandSource = source;

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

/// Safety net for anything the notifications miss. The client query is cheap
/// and answers every time; the dictionary request below is a standing one and
/// costs nothing to leave outstanding.
static const NSTimeInterval kPollInterval = 2.0;

static NSString *const kUserInfoIsPlaying =
    @"kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey";

/// Handles a MediaRemote notification.
///
/// These arrive on Core Foundation's *local* notification centre, not through
/// `NSNotificationCenter`, and most of their names begin with an underscore —
/// which is why an earlier version that watched `NSNotificationCenter` for
/// names beginning `kMR` saw nothing at all and concluded, wrongly, that
/// MediaRemote sends no notifications.
///
/// Playback state arrives in the notification itself, so a pause shows up
/// immediately rather than waiting for the next poll.
static void NMBNotificationCallback(CFNotificationCenterRef centre, void *observer,
                                    CFStringRef name, const void *object,
                                    CFDictionaryRef userInfo) {
    NSString *notification = (__bridge NSString *)name;
    if (![notification hasPrefix:@"kMR"] && ![notification hasPrefix:@"_kMR"]) {
        return;
    }

    NSDictionary *info = (__bridge NSDictionary *)userInfo;
    id playing = info[kUserInfoIsPlaying];
    if ([playing isKindOfClass:NSNumber.class]) {
        gLastKnownIsPlaying = [playing boolValue];
    }

    // Any MediaRemote notification means something moved. The app answers by
    // running a one-shot fetch, which is the only way to get fresh metadata.
    NMBRefreshStatus();
    NMBEmitChanged();
}

static void NMBObserveNotifications(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL,
                                    NMBNotificationCallback, NULL, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
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

        // One-shot mode: fetch, print, exit. Never returns from dispatch_main.
        if (getenv("NOTCH_BRIDGE_ONCE") != NULL) {
            NMBFetchOnce();
            dispatch_main();
        }

        MR.registerForNotifications(dispatch_get_main_queue());
        if (MR.setWantsNotifications != NULL) {
            MR.setWantsNotifications(YES);
        }
        NMBObserveNotifications();

        NMBWatchParent();
        NMBStartCommandReader();

        // One reading of the playing state for this process. Like the
        // dictionary, this query answers once — but once is enough to start
        // from, and the notifications report every change after that.
        if (MR.getIsPlaying != NULL) {
            MR.getIsPlaying(dispatch_get_main_queue(), ^(BOOL playing) {
                gLastKnownIsPlaying = playing;
                NMBInvalidateStatus();
                NMBRefreshStatus();
            });
        }

        NMBEmit(@{@"type": @"ready", @"parentPID": @(gParentPID), @"pid": @(getpid())});
        NMBRefreshStatus();

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

        // Safety net for anything the notifications miss.
        dispatch_source_t poll =
            dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(poll,
                                  dispatch_time(DISPATCH_TIME_NOW,
                                                (int64_t)(kPollInterval * NSEC_PER_SEC)),
                                  (uint64_t)(kPollInterval * NSEC_PER_SEC), NSEC_PER_SEC / 4);
        dispatch_source_set_event_handler(poll, ^{
            NMBRefreshStatus();
        });
        dispatch_resume(poll);

        // Takes over the host process for good.
        dispatch_main();
    }
}
