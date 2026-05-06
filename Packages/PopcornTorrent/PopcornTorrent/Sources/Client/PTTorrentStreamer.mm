

#import "PTTorrentStreamer.h"
#import <Foundation/Foundation.h>
#import <string>
#import <sys/stat.h>
#import <libtorrent/bencode.hpp>
#import "../Security/CocoaSecurity.h"
#import "../Resources/NSString+Localization.h"
#import "PTTorrentStreamer+Protected.h"
#import <GCDWebServer.h>
#import "PTTorrentsSession.h"
#import "PTTorrentsSession+Protected.h"
#import "PTSize.h"

#define PIECE_DEADLINE_MILLIS 100

// Smallest contiguous run of pieces VLC needs to start decoding after a
// seek. Initial pre-buffer is governed by the user's Buffering Strategy
// (Fast / Balanced / Smooth → 3-8 pieces), but a *seek* doesn't need
// the same headroom: VLC already has its decoder warm, the local HTTP
// connection is reused, and the rest of the run-in streams in via
// `prioritizeNextPieces:` after the initial response goes out. Lower
// floor here = noticeably snappier seek-to-first-frame.
#define SEEK_MIN_PIECES 2

NSNotificationName const PTTorrentStatusDidChangeNotification = @"com.popcorntimetv.popcorntorrent.status.change";


using namespace libtorrent;

// Class-level override for MIN_PIECES. `0` means auto-compute (default).
// Set from Swift via `+setMinPiecesOverride:` based on
// `Session.bufferingStrategy` (Fast / Balanced / Smooth).
static NSInteger sMinPiecesOverride = 0;

// User-chosen streaming cache root, set via `Session.applyStorageOverrides()`
// after resolving a security-scoped bookmark in the sandboxed macOS build.
// `nil` means use the default (`NSTemporaryDirectory()/Downloads`).
static NSString *sDownloadDirectoryOverride = nil;

@implementation PTTorrentStreamer

+ (void)setMinPiecesOverride:(NSInteger)value {
    sMinPiecesOverride = value;
}

+ (NSInteger)minPiecesOverride {
    return sMinPiecesOverride;
}

+ (void)setDownloadDirectoryOverride:(NSString *)path {
    sDownloadDirectoryOverride = [path copy];
}

+ (NSString *)downloadDirectoryOverride {
    return sDownloadDirectoryOverride;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        selectedFileIndex = -1;
        self.session = [PTTorrentsSession sharedSession];
        [self setupSession];
    }
    return self;
}

- (PTSize *)fileSize {
    return [PTSize sizeWithLongLong:_requiredSpace];
}

- (PTSize *)totalDownloaded {
    return [PTSize sizeWithLongLong:_totalDownloaded];
}


+ (NSString *)downloadDirectory {
    NSString *downloadDirectory = sDownloadDirectoryOverride
        ?: [NSTemporaryDirectory() stringByAppendingPathComponent:@"Downloads"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:downloadDirectory]) {
        NSError *error;
        [[NSFileManager defaultManager] createDirectoryAtPath:downloadDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        if (error) return nil;
    }

    return downloadDirectory;
}

- (void)setupSession {
    _torrentHandle = libtorrent::torrent_handle();
    firstPiece = libtorrent::piece_index_t(-1);
    endPiece = libtorrent::piece_index_t(0);
    lastFilePiece = libtorrent::piece_index_t(0);
    _initialBufferingComplete = NO;

    _requestedRangeInfo = [[NSMutableDictionary alloc] init];

    _status = torrent_status();
    if(self.mediaServer == nil)self.mediaServer = [[GCDWebServer alloc] init];

}

- (void)startStreamingFromMultiTorrentFileOrMagnetLink:(NSString *)filePathOrMagnetLink
                                  progress:(PTTorrentStreamerProgress)progress
                               readyToPlay:(PTTorrentStreamerReadyToPlay)readyToPlay
                                   failure:(PTTorrentStreamerFailure)failure
                                    selectFileToStream:(PTTorrentStreamerSelection)callback{
    self.selectionBlock = callback;
    [self startStreamingFromFileOrMagnetLink:filePathOrMagnetLink
                               directoryName:nil
                                    progress:progress
                                 readyToPlay:readyToPlay
                                     failure:failure];
    
}

- (void)startStreamingFromFileOrMagnetLink:(NSString *)filePathOrMagnetLink
                             directoryName:(NSString * _Nullable)directoryName
                                  progress:(PTTorrentStreamerProgress)progress
                               readyToPlay:(PTTorrentStreamerReadyToPlay)readyToPlay
                                   failure:(PTTorrentStreamerFailure)failure {
    
    
    [self startStreamingFromFileOrMagnetLink:filePathOrMagnetLink
                               directoryName:directoryName
                                    progress:progress
                                 readyToPlay:readyToPlay
                                     failure:failure
                                  fastResume:true];
}

- (void)startStreamingFromFileOrMagnetLink:(NSString *)filePathOrMagnetLink
                             directoryName:(NSString * _Nullable)directoryName
                                  progress:(PTTorrentStreamerProgress)progress
                               readyToPlay:(PTTorrentStreamerReadyToPlay)readyToPlay
                                   failure:(PTTorrentStreamerFailure)failure
                                fastResume:(Boolean)fastResume {

    self.progressBlock = progress;
    self.readyToPlayBlock = readyToPlay;
    self.failureBlock = failure;
    
    error_code ec;
    add_torrent_params tp;
    
    NSString *MD5String = nil;
    
    if ([filePathOrMagnetLink hasPrefix:@"magnet"]) {
        NSString *magnetLink = [[filePathOrMagnetLink stringByRemovingPercentEncoding] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];

        tp = parse_magnet_uri(std::string([magnetLink UTF8String]));//std::string([magnetLink UTF8String]);
        
        MD5String = [CocoaSecurity md5:magnetLink].hexLower;
    } else {
        NSString *filePath = filePathOrMagnetLink;
        NSError *error;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            NSData *fileData = [NSData dataWithContentsOfFile:filePath];
            MD5String = [CocoaSecurity md5WithData:fileData].hexLower;
            std::shared_ptr<torrent_info> ti1 = std::make_shared<torrent_info>([filePathOrMagnetLink UTF8String], ec);
            tp.ti = ti1;
            if (ec) {
                error = [[NSError alloc] initWithDomain:@"com.popcorntimetv.popcorntorrent.error" code:-1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithCString:ec.message().c_str() encoding:NSUTF8StringEncoding]}];
            }
            int index = [self selectedFileIndexInTorrentWithTorrentInfo:tp.ti];
            // PATCH(MEM.Zone): start playback after a much smaller pre-buffer
            // (was 3% of file or up to 20 pieces ~= 80 MB). Popcorn-Desktop's
            // WebTorrent streamer kicks off the moment metadata arrives;
            // libtorrent's HTTP byte-range server can do the same once the
            // first few pieces are present.
            //
            // The user-selectable Buffering Strategy (Settings →
            // Fast / Balanced / Smooth) sets `+setMinPiecesOverride:`
            // before play. If set, that wins; otherwise fall back to
            // the proven 4–6 auto-clamp.
            if (sMinPiecesOverride > 0) {
                MIN_PIECES = (int)sMinPiecesOverride;
            } else {
                MIN_PIECES = ((tp.ti->files().file_size(libtorrent::file_index_t(index)) * 0.005) / tp.ti->piece_length());
                MIN_PIECES = std::max(MIN_PIECES, 4);
                MIN_PIECES = std::min(MIN_PIECES, 6);
            }
        } else {
            error = [[NSError alloc] initWithDomain:@"com.popcorntimetv.popcorntorrent.error" code:-2 userInfo:@{NSLocalizedDescriptionKey: [NSString localizedStringWithFormat:@"File doesn't exist at path: %@".localizedString, filePath]}];
        }
        
        if (error) {
            if (failure) failure(error);
            return [self cancelStreamingAndDeleteData:NO];
        }
    }
    
    //construct the folder path for downloads
    NSString *pathComponent = directoryName != nil ? directoryName : [MD5String substringToIndex:16];
    
    NSString *basePath = [[self class] downloadDirectory];
    
    if (!basePath) {
        NSError *error = [NSError errorWithDomain:@"com.popcorntimetv.popcorntorrent.error" code:-412 userInfo:@{NSLocalizedDescriptionKey: @"Could not create download directory".localizedString}];
        if (failure) failure(error);
        return [self cancelStreamingAndDeleteData:NO];
    }
    
    Boolean didTryFastResume = false;
    
    _savePath = [basePath stringByAppendingPathComponent:pathComponent];
    //create folder for torrents
    if (![[NSFileManager defaultManager] fileExistsAtPath:_savePath]) {
        NSError *error;
        [[NSFileManager defaultManager] createDirectoryAtPath:self.savePath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        //if we cannot create folder clear all data and exit
        if (error) {
            if (failure) failure(error);
            return [self cancelStreamingAndDeleteData:NO];
        }
    } else if ([filePathOrMagnetLink hasPrefix:@"magnet"] && fastResume){
        //if folder exists already and we are loading a magnet search for resume file
        [self.session tryToResumeTorrentParams:&tp atPath:_savePath];
        didTryFastResume = true;
    }
    
    tp.save_path = std::string([self.savePath UTF8String]);
    // tp.storage_mode = storage_mode_allocate;
    
    NSError *error;
    _torrentHandle = [self.session addTorrent:self params:tp error:&error];
    
    // torrent exists, give it a new session, so there is no interference
    if (error && error.code == -2) {
        error = nil;
        self.session = [[PTTorrentsSession alloc] init];
        self.deleteOnlyDownloadedFile = YES;
        PTTorrentStreamer *existing = [[PTTorrentsSession sharedSession] torrentStreamerForTorrentHandle:_torrentHandle];
        existing.deleteOnlyDownloadedFile = YES;
        _torrentHandle = [self.session addTorrent:self params:tp error:&error];
    }
    
    if (error) {
        if (didTryFastResume) {
            // retry streaming without fast resume, aka start from scratch
            [[NSFileManager defaultManager] removeItemAtPath:self.savePath error:nil];
            [self cancelStreamingAndDeleteData:YES];
            [self startStreamingFromFileOrMagnetLink:filePathOrMagnetLink
                                       directoryName:directoryName
                                            progress:progress
                                         readyToPlay:readyToPlay
                                             failure:failure];
        } else {
            
            if (failure) failure(error);
            [self cancelStreamingAndDeleteData:NO];
        }
        return;
    }
    
    if (![filePathOrMagnetLink hasPrefix:@"magnet"] || _torrentHandle.status().has_metadata) {
        [self metadataReceivedAlert:_torrentHandle];
    }
}

- (void)handleTorrentError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.failureBlock) self.failureBlock(error);
        [self cancelStreamingAndDeleteData:NO];
    });
}

#pragma mark - Fast Forward


- (BOOL)fastForwardTorrentForRange:(NSRange)range
{
    auto torrent =  _torrentHandle;
    auto ti = torrent.torrent_file();

    //find the torrent piece corresponding to the requested piece of the movie
    auto index = file_index_t([self selectedFileIndexInTorrent:torrent]);
    int64_t fileSize = ti->files().file_size(index);
    int length = range.length > INT_MAX ? INT_MAX : int(range.length);
    peer_request request = ti->map_file(index, range.location, length);

    //set first and last pieces — wait for MIN_PIECES (the user's
    //Buffering Strategy choice) from the start of VLC's requested
    //range so VLC has enough contiguous bytes to start decoding.
    //An earlier optimisation lowered this to a 2-piece floor for
    //"snappier seek-to-first-frame", but on slow swarms VLC sometimes
    //hit the response, read 2 piece's worth, then ran into the sparse
    //hole and stalled with the spinner up. Reverting to MIN_PIECES is
    //slower-to-start but consistently makes progress.
    auto seekRunIn = MIN_PIECES;
    auto startPiece = request.piece;
    auto finalPiece = startPiece;
    for (int i = 0; i < seekRunIn - 1; i++) {
        finalPiece++;
        if (finalPiece > lastFilePiece) {
            finalPiece = lastFilePiece;
            break;
        }
    }

    //if we already have the requested part of the movie return immediately
    for(auto j = startPiece; j <= finalPiece; j++){
        if (!torrent.have_piece(j)) {
            break;
        } else if (j==finalPiece) {
            // Pieces ready — also keep `firstPiece`/`endPiece` updated
            // so `pieceFinishedAlert` fires the queued-completion path
            // for any in-flight request matching this range.
            firstPiece = startPiece;
            endPiece = finalPiece;
            NSLog(@"fast forwarding to new start piece: %d", (int)startPiece);
            return YES;
        }
    }

    // Range is missing pieces. Don't thrash the priority window: if the
    // request falls INSIDE the current sliding prefetch window
    // (`required_pieces`), libtorrent is already targeting these pieces
    // — just queue the request and let the existing prefetch finish.
    // Without this guard, every byte-range from VLC (header reads at
    // offset 0, moov atom reads at end, then resume seek) clears
    // libtorrent's priorities and re-sets MIN_PIECES, so the seek
    // target never converges. Symptom: "3% on disk, 3.5 MB/s, nothing
    // playing" because libtorrent keeps starting fresh prefetch cycles
    // for whichever offset VLC last asked for.
    BOOL alreadyTargetingThisRange = NO;
    mtx.lock();
    if (!required_pieces.empty()) {
        auto windowStart = required_pieces.front();
        auto windowEnd = required_pieces.back();
        if (startPiece >= windowStart && startPiece <= windowEnd) {
            alreadyTargetingThisRange = YES;
        }
    }
    mtx.unlock();

    if (alreadyTargetingThisRange) {
        NSLog(@"new start piece %d already in prefetch window — leaving priorities alone", (int)startPiece);
        firstPiece = startPiece;
        endPiece = finalPiece;
        return NO;
    }

    //set global variables — true seek, take over the priority window
    firstPiece = startPiece;
    endPiece = finalPiece;
    NSLog(@"fast forwarding to new start piece: %d", (int)startPiece);

    NSLog(@"new start piece missing, downloading...");
    // `prioritizeNextPieces` does the demote-and-clear of the prior
    // window atomically under the mutex — calling it directly is
    // equivalent to the old "lock + clear + call" sequence and avoids
    // a momentary empty `required_pieces` window that other threads
    // could observe.
    [self prioritizeNextPieces:torrent];

    return NO;

}


- (void)cancelStreamingAndDeleteData:(BOOL)deleteData {
    [self.session removeTorrent:self];
    
    required_pieces.clear();
    required_pieces.shrink_to_fit();
    
    [self.requestedRangeInfo removeAllObjects];
    _status = torrent_status();
    
    self.progressBlock = nil;
    self.readyToPlayBlock = nil;
    self.failureBlock = nil;
    
    if (self.mediaServer.isRunning) [self.mediaServer stop];
    [self.mediaServer removeAllHandlers];
    
    firstPiece = libtorrent::piece_index_t(-1);
    endPiece = libtorrent::piece_index_t(0);
    _initialBufferingComplete = NO;

    self.streaming = NO;
    _torrentStatus = (PTTorrentStatus){0, 0, 0, 0, 0, 0};
    _isFinished = false;
    
    if (deleteData) {
        if (self.deleteOnlyDownloadedFile) {
            NSString *filePath = [self.savePath stringByAppendingPathComponent:_fileName];
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        } else {
            // delete whole directory
            [[NSFileManager defaultManager] removeItemAtPath:self.savePath error:nil];
        }
        _savePath = nil;
        _fileName = nil;
        _requiredSpace = 0;
        _totalDownloaded = 0;
        [self setupSession];
    }
}

- (void)prioritizeNextPieces:(torrent_handle)th {
    piece_index_t next_required_piece = piece_index_t(0);

    if (firstPiece != piece_index_t(-1)) {
        next_required_piece = firstPiece;
    } else if (required_pieces.size() > 0) {
        auto next_piece = std::min(MIN_PIECES, int(required_pieces.size()));
        next_required_piece = required_pieces[next_piece - 1];
        next_required_piece++;
    }

    firstPiece = libtorrent::piece_index_t(-1);

    mtx.lock();

    // Selective demote: only knock the *previously top-prioritised*
    // pieces back down to low_priority — leave every other piece
    // alone. The earlier code blasted ALL piece priorities to
    // low_priority and cleared every deadline on each call, which
    // killed in-flight prefetch from prior seeks (peers stop sending
    // a piece the moment its priority drops + deadline clears, so
    // pieces that were 80 % done from a previous seek-back never
    // finish on a slow swarm). Already-downloaded pieces' priority
    // is moot; in-progress demoted pieces continue at low_priority
    // and finish naturally when bandwidth allows. Downstream effect:
    // the movie genuinely accumulates on disk over the playback
    // session, so seek-back to a watched region is instant instead
    // of triggering a fresh fetch.
    for (auto p : required_pieces) {
        if (!th.have_piece(p)) {
            th.piece_priority(p, low_priority);
            th.reset_piece_deadline(p);
        }
    }
    required_pieces.clear();

    for (int i = 0; i < MIN_PIECES; i++) {
        if (next_required_piece <= lastFilePiece) {
            th.piece_priority(next_required_piece, top_priority);
            th.set_piece_deadline(next_required_piece, PIECE_DEADLINE_MILLIS);
            required_pieces.push_back(next_required_piece);
            next_required_piece++;
        }
    }

    mtx.unlock();
}

- (void)processTorrent:(torrent_handle)th {
    _status = th.status();
    if ([self isStreaming]) return;
    
    if (self.readyToPlayBlock) {
        self.streaming = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startWebServerAndPlay];
        });
    }
}

/// Construct a `GCDWebServerFileResponse` for `request` against
/// `fileURL`. Falls back to a 416 error response if the file response
/// can't be built (e.g. the file is shorter than the requested
/// byte-range end). Caller must guarantee the file exists on disk
/// and contains bytes covering the requested range — the underlying
/// `GCDWebServerFileResponse initWithFile:byteRange:` calls
/// `abort()` (not nil) when the file is missing or too short, so
/// we never want to invoke this from a code path where pieces
/// might still be downloading.
- (GCDWebServerResponse *)makeFileResponseForRequest:(GCDWebServerRequest *)request fileURL:(NSURL *)fileURL {
    // Pre-flight lstat: GCDWebServerFileResponse's
    // `initWithFile:byteRange:` calls `abort()` (via GWS_DNOT_REACHED)
    // in DEBUG builds when lstat fails or the path isn't a regular
    // file. Two known windows produce that:
    //   1. Early-server-start race — `fastForwardTorrentForRange:`
    //      returns YES based on piece readiness, but libtorrent hasn't
    //      yet materialised the file on disk (it allocates lazily on
    //      first piece write).
    //   2. Sandboxed macOS — a user-chosen save path can lose its
    //      security-scoped access between checks.
    // Either way, returning a 503 lets VLC back off and retry instead
    // of crashing the whole process.
    NSString *path = fileURL.relativePath;
    struct ::stat info;
    int statResult = ::lstat([path fileSystemRepresentation], &info);
    if (statResult != 0 || !S_ISREG(info.st_mode)) {
        // Log what tripped the guard so we can tell missing-file races
        // apart from non-regular-file mishaps when debugging seek
        // crashes. Range printed because seek requests are the typical
        // trigger.
        NSLog(@"[PTTorrentStreamer] guard hit: lstat=%d errno=%d mode=0%o path=%@ range=[%lu,%lu]",
              statResult, errno, info.st_mode,
              path,
              (unsigned long)request.byteRange.location,
              (unsigned long)request.byteRange.length);
        return [GCDWebServerErrorResponse responseWithStatusCode:503];
    }

    GCDWebServerFileResponse *response;
    if (request.hasByteRange) {
        response = [[GCDWebServerFileResponse alloc] initWithFile:path byteRange:request.byteRange];
    } else {
        response = [[GCDWebServerFileResponse alloc] initWithFile:path];
    }
    if (response == nil) {
        GCDWebServerErrorResponse *errResponse = [GCDWebServerErrorResponse responseWithStatusCode:416];
        [errResponse setValue:[NSString stringWithFormat:@"*/%lu", (unsigned long)request.byteRange.location] forAdditionalHeader:@"Content-Range"];
        return errResponse;
    }
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Expose-Headers"];
    return response;
}

- (void)startWebServerAndPlay {
    __block NSURL *fileURL = [NSURL fileURLWithPath:[self.savePath stringByAppendingPathComponent:_fileName]];
    __weak __typeof__(self) weakSelf = self;
    NSLog(@"file to be streamed is %@",[self.savePath stringByAppendingPathComponent:_fileName]);
    [self.mediaServer addDefaultHandlerForMethod:@"GET" requestClass:[GCDWebServerRequest class] asyncProcessBlock:^(GCDWebServerRequest *request, GCDWebServerCompletionBlock completionBlock) {
        // Finished torrents — file is fully on disk, just serve it.
        if (weakSelf.isFinished) {
            GCDWebServerResponse *response = [weakSelf makeFileResponseForRequest:request fileURL:fileURL];
            completionBlock(response);
            return;
        }

        // The previous version constructed the
        // `GCDWebServerFileResponse` up-front and queued it when
        // pieces weren't ready. That worked while the server only
        // started after `allRequiredPiecesDownloaded` (file
        // guaranteed to exist). With the early-server-start
        // optimisation, the file may not exist on disk yet —
        // libtorrent creates it lazily on first piece write — and
        // `GCDWebServerFileResponse initWithFile:byteRange:` calls
        // `abort()` (rather than returning nil) when the file is
        // missing. So we now queue the *raw request* and construct
        // the response in `pieceFinishedAlert` once the file +
        // required pieces are ready.
        if ([weakSelf fastForwardTorrentForRange:request.byteRange]) {
            NSLog(@"[PTTorrentStreamer] serving request range=[%lu,%lu] (pieces ready)",
                  (unsigned long)request.byteRange.location,
                  (unsigned long)request.byteRange.length);
            GCDWebServerResponse *response = [weakSelf makeFileResponseForRequest:request fileURL:fileURL];
            completionBlock(response);
        } else {
            NSLog(@"[PTTorrentStreamer] queued request range=[%lu,%lu] — waiting for pieces",
                  (unsigned long)request.byteRange.location,
                  (unsigned long)request.byteRange.length);
            [weakSelf.requestedRangeInfo setObject:request forKey:@"request"];
            [weakSelf.requestedRangeInfo setObject:completionBlock forKey:@"completionBlock"];
        }
    }];
    
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    NSInteger port = 50321;
    [options setObject:[NSNumber numberWithInteger:port] forKey:GCDWebServerOption_Port];
    NSError *error;

    while (![self.mediaServer startWithOptions:options error:&error]) {
        port++;
        [options setObject:[NSNumber numberWithInteger:port] forKey:GCDWebServerOption_Port];

        /// failed to start webserver
        if (port > 50341) {
            if (_failureBlock) _failureBlock(error);
            [self cancelStreamingAndDeleteData:NO];
            return;
        }
    }
    
    __block NSURL *serverURL = nil; // ios now requires permission to access local network// self.mediaServer.serverURL;
    
    if (serverURL == nil) // `nil` when device is on cellular network.
    {
        serverURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://0.0.0.0:%i/", (int)self.mediaServer.port]];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakSelf.readyToPlayBlock) weakSelf.readyToPlayBlock(serverURL, fileURL);
    });
}


- (int)selectedFileIndexInTorrent:(torrent_handle)th {
    std::shared_ptr<const torrent_info> ti = th.torrent_file();
    return [self selectedFileIndexInTorrentWithTorrentInfo:ti];
}

- (int)selectedFileIndexInTorrentWithTorrentInfo:(std::shared_ptr<const torrent_info>)ti {
    if (selectedFileIndex != -1) {
        return selectedFileIndex;
    }

    auto files = ti->files();
    NSMutableArray* file_names = [[NSMutableArray alloc] init];
    NSMutableArray* file_sizes = [[NSMutableArray alloc] init];
    for (int i=0; i<ti->num_files(); i++) {
        [file_names addObject:[NSString stringWithFormat:@"%s", files.file_name(file_index_t(i)).to_string().c_str()]];
        [file_sizes addObject:[NSNumber numberWithLong: files.file_size(file_index_t(i))]];
    }

    selectedFileIndex = self.selectionBlock([file_names copy], [file_sizes copy]);
    return selectedFileIndex;
}

#pragma mark - Alerts

- (void)metadataReceivedAlert:(torrent_handle)th {
    _requiredSpace = th.status().total_wanted;
    NSURL* savePathURL = [NSURL fileURLWithPath:self.savePath];
    NSDictionary *results = [savePathURL resourceValuesForKeys:@[NSURLVolumeAvailableCapacityKey] error:nil];
    NSNumber *availableSpace = results[NSURLVolumeAvailableCapacityKey];//get available space on device
    
    int selectedIndex = [self selectedFileIndexInTorrent:th];
    file_index_t file_index = file_index_t(selectedIndex);
    
    auto file_priorities = th.get_file_priorities();
    std::fill(file_priorities.begin(), file_priorities.end(), dont_download);
    file_priorities[selectedIndex] = top_priority;
    th.prioritize_files(file_priorities);
    
    auto ti = th.torrent_file();
    int64_t file_size = ti->files().file_size(file_index);
    std::string path = ti->files().file_path(file_index);
    _fileName = [NSString stringWithCString:path.c_str() encoding:NSUTF8StringEncoding];
    NSString *filePath = [self.savePath stringByAppendingPathComponent:_fileName];
    int64_t requiredSize = file_size;

    // check if file already downloaded to ignore used space, so it will not be downloaded again from scratch
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        long long fileSize = [[fileAttributes objectForKey:NSFileSize] longLongValue];
        requiredSize -= fileSize;
    }

    // Streaming-aware headroom check. Reserving the *whole* file size
    // up-front made "insufficient space" fire on plenty-of-space
    // systems streaming a 15 GB 4K release with only 12 GB free —
    // even though the user typically watches once, downloads a few
    // GB worth of the file, then quits. Cap the upfront requirement
    // at `kStreamingHeadroom` so the pre-check rejects only genuinely
    // disk-starved volumes; if the disk does fill mid-stream
    // libtorrent halts cleanly.
    static const int64_t kStreamingHeadroom = 2LL * 1024 * 1024 * 1024;  // 2 GB
    int64_t headroomNeeded = std::min(requiredSize, kStreamingHeadroom);

    if (headroomNeeded > availableSpace.longLongValue) {
        PTSize *headroomSize = [PTSize sizeWithLongLong: headroomNeeded];
        NSString *description = [NSString localizedStringWithFormat:@"There is not enough space to download the torrent. Please clear at least %@ and try again.".localizedString, headroomSize.stringValue];
        NSError *error = [[NSError alloc] initWithDomain:@"com.popcorntimetv.popcorntorrent.error" code:-4 userInfo:@{NSLocalizedDescriptionKey: description}];
        [self handleTorrentError:error];
        return;
    }

    [self updateAndMonitorTorrentProgress];
    
    // file already downloaded
    if (_isFinished) {
        [self torrentFinishedAlert:th];
        return;
    }
    
    // PATCH(MEM.Zone): start playback after a much smaller pre-buffer
    // (was 3% of file or up to 20 pieces ~= 80 MB). See the matching
    // patch above for the rationale + the override hook.
    if (sMinPiecesOverride > 0) {
        MIN_PIECES = (int)sMinPiecesOverride;
    } else {
        MIN_PIECES = (ti->files().file_size(file_index) * 0.005) / ti->piece_length();
        MIN_PIECES = std::max(MIN_PIECES, 4);
        MIN_PIECES = std::min(MIN_PIECES, 6);
    }
    NSLog(@"min pieces: %d", MIN_PIECES);
    piece_index_t first_piece = ti->map_file(file_index, 0, 0).piece;
    NSLog(@"first piece: %d", (int)first_piece);
    for (int i = 0; i < MIN_PIECES; i++) {
        required_pieces.push_back(first_piece);
        first_piece++;
    }
    
    // download last pieces
    piece_index_t last_piece = ti->map_file(file_index, file_size - 1, 0).piece;
    NSLog(@"last piece: %d", (int)last_piece);
    lastFilePiece = last_piece;
    int maxEndPieces = MIN_PIECES <= 6 ? 1 : 2;
    for (int i = 0; i < maxEndPieces; i++) {
        required_pieces.push_back(last_piece);
        last_piece--;
    }

    // don't download intermediate pieces when streaming starts
    piece_index_t piece = first_piece;
    do {
        th.piece_priority(piece, low_priority);
        piece++;
    } while (piece <= last_piece);
    
    th.clear_piece_deadlines();
    for (piece_index_t piece : required_pieces) {
        th.piece_priority(piece, top_priority);
        th.set_piece_deadline(piece, PIECE_DEADLINE_MILLIS);
    }

    // Start GCDWebServer + fire `readyToPlayBlock` IMMEDIATELY
    // now that metadata + piece priorities are set. VLC connects in
    // parallel with libtorrent's piece download. The range handler
    // queues VLC's first byte-range request as a raw `request` (not
    // a constructed response) and `pieceFinishedAlert` builds the
    // response when pieces arrive — the queue switched from "store
    // response" to "store request" specifically to make this safe
    // against `GCDWebServerFileResponse initWithFile:byteRange:`
    // aborting when the file doesn't yet exist on disk.
    [self processTorrent:th];
}

- (void)updateAndMonitorTorrentProgress {
    if (!_progressBlock || !_torrentHandle.is_valid() || _status.is_finished) {
        return;
    }

    _status = _torrentHandle.status();
    _torrentStatus = {
        _torrentStatus.bufferingProgress,
        _status.progress,
        _status.download_rate,
        _status.upload_rate,
        _status.num_seeds,
        _status.num_peers
    };
    _totalDownloaded = _status.total_wanted_done;
    _isFinished = _status.is_finished;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (_progressBlock) _progressBlock(_torrentStatus);
        [[NSNotificationCenter defaultCenter] postNotificationName:PTTorrentStatusDidChangeNotification object:self];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self updateAndMonitorTorrentProgress];
    });
}

- (void)pieceFinishedAlert:(torrent_handle)th forPieceIndex:(piece_index_t)index {
    NSLog(@"downloaded piece: %d", (int)index);
    _status = th.status();
    
    int requiredPiecesDownloaded = 0;
    BOOL allRequiredPiecesDownloaded = YES;
    
    auto copyRequired(required_pieces);
    
    for (piece_index_t piece: copyRequired) {
        if (th.have_piece(piece) == false) {
            allRequiredPiecesDownloaded = NO;
        }else{
            requiredPiecesDownloaded++;
        }
    }
    
    int requiredPieces = (int)copyRequired.size();

    // bufferingProgress is the public "ready to play" signal. The
    // internal `required_pieces` is a sliding window — `prioritize
    // NextPieces` clears it and refills it with the *next* head batch
    // every time a window completes. Reporting the raw windowed ratio
    // makes the UI bar lurch 100 % → 25 % → 100 % as windows slide.
    // Latch a flag the first time the initial window finishes; from
    // there on, hold the public value at 1.0 — the windowed maths
    // stay internal for `allRequiredPiecesDownloaded` book-keeping.
    float bufferingProgress;
    if (_initialBufferingComplete) {
        bufferingProgress = 1.0f;
    } else {
        bufferingProgress = 1.0f - (requiredPieces - requiredPiecesDownloaded) / (float)requiredPieces;
        if (allRequiredPiecesDownloaded) {
            _initialBufferingComplete = YES;
            bufferingProgress = 1.0f;
        }
    }

    _torrentStatus = {
        bufferingProgress,
        _status.progress,
        _status.download_rate,
        _status.upload_rate,
        _status.num_seeds,
        _status.num_peers
    };
    
    _totalDownloaded = _status.total_wanted_done;
    _isFinished = _status.is_finished;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_progressBlock) _progressBlock(_torrentStatus);
        [[NSNotificationCenter defaultCenter] postNotificationName:PTTorrentStatusDidChangeNotification object:self];
    });
    
    
    
    if (allRequiredPiecesDownloaded) {
        if (th.have_piece(endPiece) && self.requestedRangeInfo.count > 0) {
            GCDWebServerRequest *queuedRequest = [self.requestedRangeInfo objectForKey:@"request"];
            GCDWebServerCompletionBlock completionBlock = [self.requestedRangeInfo objectForKey:@"completionBlock"];
            [self.requestedRangeInfo removeAllObjects];
            // File definitely exists by now (libtorrent has written
            // pieces to it). Construct the response now and fulfil
            // the queued request.
            if (queuedRequest && completionBlock) {
                NSLog(@"[PTTorrentStreamer] fulfilling queued request range=[%lu,%lu]",
                      (unsigned long)queuedRequest.byteRange.location,
                      (unsigned long)queuedRequest.byteRange.length);
                NSURL *fileURL = [NSURL fileURLWithPath:[self.savePath stringByAppendingPathComponent:_fileName]];
                GCDWebServerResponse *response = [self makeFileResponseForRequest:queuedRequest fileURL:fileURL];
                completionBlock(response);
            }
        }
        if (MIN_PIECES == 0) {
            [self metadataReceivedAlert:th];
        }
        [self prioritizeNextPieces:th];
        [self processTorrent:th];
    }
}

- (void)torrentFinishedAlert:(torrent_handle)th {
    [self processTorrent:th];
    
    _torrentStatus = {
        1, 1,
        _status.download_rate,
        _status.upload_rate,
        _status.num_seeds,
        _status.num_peers
    };
    
    _totalDownloaded = _status.total_wanted_done;
    _isFinished = _status.is_finished;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_progressBlock) _progressBlock(_torrentStatus);
        [[NSNotificationCenter defaultCenter] postNotificationName:PTTorrentStatusDidChangeNotification object:self];
    });
    
    [self.session removeTorrent:self];
    // Remove the torrent when its finished
    // th.pause(torrent_handle::graceful_pause);
}

@end

