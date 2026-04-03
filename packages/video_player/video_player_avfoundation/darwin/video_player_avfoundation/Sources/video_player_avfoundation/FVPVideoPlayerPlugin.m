// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "./include/video_player_avfoundation/FVPVideoPlayerPlugin.h"
#import "./include/video_player_avfoundation/FVPVideoPlayerPlugin_Test.h"

@import AVFoundation;
@import AVKit;

#import <objc/runtime.h>

#import "./include/video_player_avfoundation/FVPAVFactory.h"
#import "./include/video_player_avfoundation/FVPAssetProvider.h"
#import "./include/video_player_avfoundation/FVPDisplayLink.h"
#import "./include/video_player_avfoundation/FVPEventBridge.h"
#import "./include/video_player_avfoundation/FVPFrameUpdater.h"
#import "./include/video_player_avfoundation/FVPNativeVideoViewFactory.h"
#import "./include/video_player_avfoundation/FVPTextureBasedVideoPlayer.h"
#import "./include/video_player_avfoundation/FVPVideoPlayer.h"
// Relative path is needed for messages.g.h. See
// https://github.com/flutter/packages/pull/6675/#discussion_r1591210702
#import "./include/video_player_avfoundation/messages.g.h"

#pragma mark - HLS manifest override support

/// AVAssetResourceLoaderDelegate that serves a UTF-8 HLS playlist body for the
/// initial manifest request. All segment/sub-playlist URLs inside the body must
/// be absolute HTTP so the player fetches them over the network normally.
@interface FVPHlsManifestOverrideDelegate : NSObject <AVAssetResourceLoaderDelegate>
@property(nonatomic, copy) NSString *playlistBody;
- (instancetype)initWithPlaylistBody:(NSString *)body;
@end

@implementation FVPHlsManifestOverrideDelegate
- (instancetype)initWithPlaylistBody:(NSString *)body {
  self = [super init];
  if (self) {
    _playlistBody = [body copy];
  }
  return self;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader
    shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
  (void)resourceLoader;
  NSData *data = [self.playlistBody dataUsingEncoding:NSUTF8StringEncoding];
  if (!data) {
    [loadingRequest finishLoadingWithError:[NSError errorWithDomain:@"FVPHlsManifestOverride"
                                                              code:1
                                                          userInfo:nil]];
    return YES;
  }

  AVAssetResourceLoadingContentInformationRequest *info = loadingRequest.contentInformationRequest;
  if (info != nil) {
    info.contentType = @"public.m3u-playlist";
    info.contentLength = (long long)data.length;
    info.byteRangeAccessSupported = NO;
  }

  AVAssetResourceLoadingDataRequest *dataRequest = loadingRequest.dataRequest;
  if (dataRequest != nil) {
    long long offset = dataRequest.currentOffset;
    if (offset < 0 || (NSUInteger)offset >= data.length) {
      [loadingRequest finishLoading];
      return YES;
    }
    NSUInteger start = (NSUInteger)offset;
    NSUInteger available = data.length - start;
    long long reqLen = dataRequest.requestedLength;
    NSUInteger length = (reqLen <= 0) ? available : (NSUInteger)MIN((unsigned long long)reqLen,
                                                                    (unsigned long long)available);
    [dataRequest respondWithData:[data subdataWithRange:NSMakeRange(start, length)]];
  }

  [loadingRequest finishLoading];
  return YES;
}
@end

/// Minimal FVPAVAsset wrapper for a raw AVAsset (used by the HLS override path
/// where the AVURLAsset has a custom resource loader and cannot go through the
/// factory's URLAssetWithURL:options:).
@interface FVPHlsOverrideAsset : NSObject <FVPAVAsset>
@property(nonatomic, readwrite) AVAsset *asset;
@end

@implementation FVPHlsOverrideAsset
- (instancetype)initWithAsset:(AVAsset *)asset {
  self = [super init];
  if (self) {
    _asset = asset;
  }
  return self;
}

- (CMTime)duration {
  return self.asset.duration;
}

- (AVKeyValueStatus)statusOfValueForKey:(NSString *)key
                                  error:(NSError *_Nullable *_Nullable)outError {
  return [self.asset statusOfValueForKey:key error:outError];
}

- (void)loadValuesAsynchronouslyForKeys:(NSArray<NSString *> *)keys
                      completionHandler:(nullable void (^NS_SWIFT_SENDABLE)(void))handler {
  [self.asset loadValuesAsynchronouslyForKeys:keys completionHandler:handler];
}

- (NSArray<AVAssetTrack *> *)tracksWithMediaType:(AVMediaType)mediaType {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [self.asset tracksWithMediaType:mediaType];
#pragma clang diagnostic pop
}

- (void)loadTracksWithMediaType:(AVMediaType)mediaType
              completionHandler:(void (^NS_SWIFT_SENDABLE)(NSArray<AVAssetTrack *> *_Nullable,
                                                           NSError *_Nullable))completionHandler
    API_AVAILABLE(macos(12.0), ios(15.0)) {
  [self.asset loadTracksWithMediaType:mediaType completionHandler:completionHandler];
}
@end

/// Minimal FVPAVPlayerItem wrapper for a raw AVPlayerItem.
@interface FVPHlsOverridePlayerItem : NSObject <FVPAVPlayerItem>
@property(nonatomic, readwrite) AVPlayerItem *playerItem;
@end

@implementation FVPHlsOverridePlayerItem
- (instancetype)initWithPlayerItem:(AVPlayerItem *)playerItem {
  self = [super init];
  if (self) {
    _playerItem = playerItem;
  }
  return self;
}

- (NSObject<FVPAVAsset> *)asset {
  return [[FVPHlsOverrideAsset alloc] initWithAsset:self.playerItem.asset];
}

- (AVVideoComposition *)videoComposition {
  return self.playerItem.videoComposition;
}

- (void)setVideoComposition:(AVVideoComposition *)videoComposition {
  self.playerItem.videoComposition = videoComposition;
}
@end

#pragma mark -

/// Non-test implementation of the diplay link factory.
@interface FVPDefaultDisplayLinkFactory : NSObject <FVPDisplayLinkFactory>
@end

@implementation FVPDefaultDisplayLinkFactory
- (NSObject<FVPDisplayLink> *)displayLinkWithViewProvider:(NSObject<FVPViewProvider> *)viewProvider
                                                 callback:(void (^)(void))callback {
#if TARGET_OS_IOS
  return [[FVPCADisplayLink alloc] initWithViewProvider:viewProvider callback:callback];
#else
  if (@available(macOS 14.0, *)) {
    return [[FVPCADisplayLink alloc] initWithViewProvider:viewProvider callback:callback];
  }
  return [[FVPCoreVideoDisplayLink alloc] initWithViewProvider:viewProvider callback:callback];
#endif
}

@end

#pragma mark -

/// Non-test implementation of FVPAssetProvider, wrapping a Flutter plugin
/// registrar.
@interface FVPDefaultAssetProvider : NSObject <FVPAssetProvider>
@property(weak, nonatomic) NSObject<FlutterPluginRegistrar> *registrar;

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar;
@end

@implementation FVPDefaultAssetProvider

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  self = [super init];
  if (self) {
    _registrar = registrar;
  }
  return self;
}

- (NSString *)lookupKeyForAsset:(NSString *)asset {
  return [self.registrar lookupKeyForAsset:asset];
}

- (NSString *)lookupKeyForAsset:(NSString *)asset fromPackage:(NSString *)package {
  return [self.registrar lookupKeyForAsset:asset fromPackage:package];
}

@end

#pragma mark -

@interface FVPVideoPlayerPlugin ()
@property(nonatomic, strong) NSObject<FlutterBinaryMessenger> *binaryMessenger;
@property(nonatomic, strong) NSObject<FlutterTextureRegistry> *textureRegistry;
@property(nonatomic, strong) id<FVPDisplayLinkFactory> displayLinkFactory;
@property(nonatomic, strong) id<FVPAVFactory> avFactory;
@property(nonatomic, strong) NSObject<FVPViewProvider> *viewProvider;
@property(nonatomic, strong) NSObject<FVPAssetProvider> *assetProvider;
@property(nonatomic, assign) int64_t nextPlayerIdentifier;
@end

@implementation FVPVideoPlayerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FVPVideoPlayerPlugin *instance = [[FVPVideoPlayerPlugin alloc] initWithRegistrar:registrar];
  // Publish the instance so that it receives detachFromEngineForRegistrar:.
  [registrar publish:instance];
  FVPNativeVideoViewFactory *factory = [[FVPNativeVideoViewFactory alloc]
               initWithMessenger:registrar.messenger
      playerByIdentifierProvider:^FVPVideoPlayer *(NSNumber *playerIdentifier) {
        return instance->_playersByIdentifier[playerIdentifier];
      }];
  [registrar registerViewFactory:factory withId:@"plugins.flutter.dev/video_player_ios"];
  SetUpFVPAVFoundationVideoPlayerApi(registrar.messenger, instance);
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  return [self initWithAVFactory:[[FVPDefaultAVFactory alloc] init]
              displayLinkFactory:[[FVPDefaultDisplayLinkFactory alloc] init]
                 binaryMessenger:registrar.messenger
                 textureRegistry:registrar.textures
                    viewProvider:[[FVPDefaultViewProvider alloc] initWithRegistrar:registrar]
                   assetProvider:[[FVPDefaultAssetProvider alloc] initWithRegistrar:registrar]];
}

- (instancetype)initWithAVFactory:(id<FVPAVFactory>)avFactory
               displayLinkFactory:(id<FVPDisplayLinkFactory>)displayLinkFactory
                  binaryMessenger:(NSObject<FlutterBinaryMessenger> *)binaryMessenger
                  textureRegistry:(NSObject<FlutterTextureRegistry> *)textureRegistry
                     viewProvider:(NSObject<FVPViewProvider> *)viewProvider
                    assetProvider:(NSObject<FVPAssetProvider> *)assetProvider {
  self = [super init];
  NSAssert(self, @"super init cannot be nil");
  _binaryMessenger = binaryMessenger;
  _textureRegistry = textureRegistry;
  _assetProvider = assetProvider;
  _viewProvider = viewProvider;
  _displayLinkFactory = displayLinkFactory ?: [[FVPDefaultDisplayLinkFactory alloc] init];
  _avFactory = avFactory ?: [[FVPDefaultAVFactory alloc] init];
  _playersByIdentifier = [NSMutableDictionary dictionaryWithCapacity:1];
  _nextPlayerIdentifier = 1;
  return self;
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterError *error;
  for (FVPVideoPlayer *player in self.playersByIdentifier.allValues) {
    // Remove the channel and texture cleanup, and the event listener, to ensure that the player
    // doesn't message the engine that is no longer connected.
    player.onDisposed = nil;
    player.eventListener = nil;
    [player disposeWithError:&error];
  }
  [self.playersByIdentifier removeAllObjects];
  SetUpFVPAVFoundationVideoPlayerApi(registrar.messenger, nil);
}

- (int64_t)configurePlayer:(FVPVideoPlayer *)player
    withExtraDisposeHandler:(nullable void (^)(void))extraDisposeHandler
         backgroundPlayback:(nullable FVPBackgroundPlaybackMessage *)backgroundPlayback
      allowExternalPlayback:(BOOL)allowExternalPlayback {
  int64_t playerIdentifier = self.nextPlayerIdentifier++;
  self.playersByIdentifier[@(playerIdentifier)] = player;

  // Configure external playback (AirPlay)
  player.player.allowsExternalPlayback = allowExternalPlayback;

  // Configure background playback if requested
  if (backgroundPlayback != nil) {
    [player configureBackgroundPlayback:backgroundPlayback];
  }

  NSObject<FlutterBinaryMessenger> *messenger = self.binaryMessenger;
  NSString *channelSuffix = [NSString stringWithFormat:@"%lld", playerIdentifier];
  // Set up the player-specific API handler, and its onDispose unregistration.
  SetUpFVPVideoPlayerInstanceApiWithSuffix(messenger, player, channelSuffix);
  __weak typeof(self) weakSelf = self;
  player.onDisposed = ^() {
    SetUpFVPVideoPlayerInstanceApiWithSuffix(messenger, nil, channelSuffix);
    if (extraDisposeHandler) {
      extraDisposeHandler();
    }
    [weakSelf.playersByIdentifier removeObjectForKey:@(playerIdentifier)];
  };
  // Set up the event channel.
  FVPEventBridge *eventBridge = [[FVPEventBridge alloc]
      initWithMessenger:messenger
            channelName:[NSString stringWithFormat:@"flutter.dev/videoPlayer/videoEvents%@",
                                                   channelSuffix]];
  player.eventListener = eventBridge;

  return playerIdentifier;
}

// This function, although slightly modified, is also in camera_avfoundation.
// Both need to do the same thing and run on the same thread (for example main thread).
// Do not overwrite PlayAndRecord with Playback which causes inability to record
// audio, do not overwrite all options.
// Only change category if it is considered an upgrade which means it can only enable
// ability to play in silent mode or ability to record audio but never disables it,
// that could affect other plugins which depend on this global state. Only change
// category or options if there is change to prevent unnecessary lags and silence.
#if TARGET_OS_IOS
static void upgradeAudioSessionCategory(NSObject<FVPAVAudioSession> *session,
                                        AVAudioSessionCategory requestedCategory,
                                        AVAudioSessionCategoryOptions options,
                                        AVAudioSessionCategoryOptions clearOptions) {
  NSSet *playCategories = [NSSet
      setWithObjects:AVAudioSessionCategoryPlayback, AVAudioSessionCategoryPlayAndRecord, nil];
  NSSet *recordCategories =
      [NSSet setWithObjects:AVAudioSessionCategoryRecord, AVAudioSessionCategoryPlayAndRecord, nil];
  NSSet *requiredCategories = [NSSet setWithObjects:requestedCategory, session.category, nil];
  BOOL requiresPlay = [requiredCategories intersectsSet:playCategories];
  BOOL requiresRecord = [requiredCategories intersectsSet:recordCategories];
  if (requiresPlay && requiresRecord) {
    requestedCategory = AVAudioSessionCategoryPlayAndRecord;
  } else if (requiresPlay) {
    requestedCategory = AVAudioSessionCategoryPlayback;
  } else if (requiresRecord) {
    requestedCategory = AVAudioSessionCategoryRecord;
  }
  options = (session.categoryOptions & ~clearOptions) | options;
  if ([requestedCategory isEqualToString:session.category] && options == session.categoryOptions) {
    return;
  }
  [session setCategory:requestedCategory withOptions:options error:nil];
}
#endif

- (void)initialize:(FlutterError *__autoreleasing *)error {
#if TARGET_OS_IOS
  // Allow audio playback when the Ring/Silent switch is set to silent
  upgradeAudioSessionCategory(self.avFactory.sharedAudioSession, AVAudioSessionCategoryPlayback,
                              /* options */ 0,
                              /* clearOptions */ 0);
#endif

  FlutterError *disposeError;
  // Disposing a player removes it from the dictionary, so iterate over a copy.
  NSArray<FVPVideoPlayer *> *players = [self.playersByIdentifier.allValues copy];
  for (FVPVideoPlayer *player in players) {
    [player disposeWithError:&disposeError];
  }
  [self.playersByIdentifier removeAllObjects];
}

- (nullable NSNumber *)createPlatformViewPlayerWithOptions:(nonnull FVPCreationOptions *)options
                                                     error:(FlutterError **)error {
  @try {
    NSObject<FVPAVPlayerItem> *item = [self playerItemWithCreationOptions:options];

    // FVPVideoPlayer contains all required logic for platform views.
    FVPVideoPlayer *player = [[FVPVideoPlayer alloc] initWithPlayerItem:item
                                                              avFactory:self.avFactory
                                                           viewProvider:self.viewProvider];

    return @([self configurePlayer:player
           withExtraDisposeHandler:nil
                backgroundPlayback:options.backgroundPlayback
             allowExternalPlayback:options.allowExternalPlayback]);
  } @catch (NSException *exception) {
    *error = [FlutterError errorWithCode:@"video_player" message:exception.reason details:nil];
    return nil;
  }
}

- (nullable FVPTexturePlayerIds *)createTexturePlayerWithOptions:
                                      (nonnull FVPCreationOptions *)options
                                                           error:(FlutterError **)error {
  @try {
    NSObject<FVPAVPlayerItem> *item = [self playerItemWithCreationOptions:options];
    FVPFrameUpdater *frameUpdater = [[FVPFrameUpdater alloc] initWithRegistry:self.textureRegistry];
    NSObject<FVPDisplayLink> *displayLink =
        [self.displayLinkFactory displayLinkWithViewProvider:self.viewProvider
                                                    callback:^() {
                                                      [frameUpdater displayLinkFired];
                                                    }];

    FVPTextureBasedVideoPlayer *player =
        [[FVPTextureBasedVideoPlayer alloc] initWithPlayerItem:item
                                                  frameUpdater:frameUpdater
                                                   displayLink:displayLink
                                                     avFactory:self.avFactory
                                                  viewProvider:self.viewProvider];

    int64_t textureIdentifier = [self.textureRegistry registerTexture:player];
    [player setTextureIdentifier:textureIdentifier];
    __weak typeof(self) weakSelf = self;
    int64_t playerIdentifier = [self configurePlayer:player
                             withExtraDisposeHandler:^() {
                               [weakSelf.textureRegistry unregisterTexture:textureIdentifier];
                             }
                                  backgroundPlayback:options.backgroundPlayback
                               allowExternalPlayback:options.allowExternalPlayback];
    return [FVPTexturePlayerIds makeWithPlayerId:playerIdentifier textureId:textureIdentifier];
  } @catch (NSException *exception) {
    *error = [FlutterError errorWithCode:@"video_player" message:exception.reason details:nil];
    return nil;
  }
}

- (void)setMixWithOthers:(BOOL)mixWithOthers
                   error:(FlutterError *_Nullable __autoreleasing *)error {
#if TARGET_OS_OSX
  // AVAudioSession doesn't exist on macOS, and audio always mixes, so just no-op.
#else
  NSObject<FVPAVAudioSession> *session = self.avFactory.sharedAudioSession;
  if (mixWithOthers) {
    upgradeAudioSessionCategory(session, session.category,
                                /* options */ AVAudioSessionCategoryOptionMixWithOthers,
                                /* clearOptions */ 0);
  } else {
    upgradeAudioSessionCategory(session, session.category, /* options */ 0,
                                /* clearOptions */ AVAudioSessionCategoryOptionMixWithOthers);
  }
#endif
}

- (nullable NSString *)fileURLForAssetWithName:(NSString *)asset
                                       package:(nullable NSString *)package
                                         error:(FlutterError *_Nullable *_Nonnull)error {
  NSString *resource = package == nil
                           ? [self.assetProvider lookupKeyForAsset:asset]
                           : [self.assetProvider lookupKeyForAsset:asset fromPackage:package];

  NSString *path = [[NSBundle mainBundle] pathForResource:resource ofType:nil];
#if TARGET_OS_OSX
  // See https://github.com/flutter/flutter/issues/135302
  // TODO(stuartmorgan): Remove this if the asset APIs are adjusted to work better for macOS.
  if (!path) {
    path = [NSURL URLWithString:resource relativeToURL:NSBundle.mainBundle.bundleURL].path;
  }
#endif

  if (!path) {
    return nil;
  }
  return [NSURL fileURLWithPath:path].absoluteString;
}

- (nullable NSNumber *)isPictureInPictureSupported:(FlutterError *_Nullable *_Nonnull)error {
  return @([AVPictureInPictureController isPictureInPictureSupported]);
}

/// Returns the AVPlayerItem corresponding to the given player creation options.
- (nonnull NSObject<FVPAVPlayerItem> *)playerItemWithCreationOptions:
    (nonnull FVPCreationOptions *)options {
  NSString *hlsOverride = options.hlsManifestOverride;
  if (hlsOverride != nil && hlsOverride.length > 0) {
    return [self playerItemWithHlsManifestOverride:hlsOverride originalUri:options.uri];
  }

  NSDictionary<NSString *, NSString *> *headers = options.httpHeaders;
  NSDictionary<NSString *, id> *itemOptions =
      headers.count == 0 ? nil : @{@"AVURLAssetHTTPHeaderFieldsKey" : headers};
  NSObject<FVPAVAsset> *asset = [self.avFactory URLAssetWithURL:[NSURL URLWithString:options.uri]
                                                        options:itemOptions];
  return [self.avFactory playerItemWithAsset:asset];
}

/// Creates an AVPlayerItem that loads [hlsManifestOverride] as the HLS master
/// playlist via AVAssetResourceLoaderDelegate while fetching all segments and
/// sub-playlists from the network normally (they use absolute HTTP URLs inside
/// the override body).
- (nonnull NSObject<FVPAVPlayerItem> *)playerItemWithHlsManifestOverride:
                                           (nonnull NSString *)hlsOverride
                                                             originalUri:
                                                                 (nonnull NSString *)originalUri {
  // Use a custom URL scheme so AVAssetResourceLoader intercepts the initial
  // manifest request. Subsequent segment requests use absolute HTTP URLs from
  // the synthetic playlist body, so they bypass the resource loader entirely.
  NSString *customUri =
      [NSString stringWithFormat:@"x-mx-hls://%@", [[NSUUID UUID] UUIDString]];
  NSURL *customURL = [NSURL URLWithString:customUri];
  AVURLAsset *rawAsset = [AVURLAsset URLAssetWithURL:customURL options:nil];

  FVPHlsManifestOverrideDelegate *delegate =
      [[FVPHlsManifestOverrideDelegate alloc] initWithPlaylistBody:hlsOverride];
  // The delegate must be retained for the lifetime of the asset. Associated
  // objects prevent premature deallocation.
  static char kDelegateAssocKey;
  objc_setAssociatedObject(rawAsset, &kDelegateAssocKey, delegate,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [rawAsset.resourceLoader setDelegate:delegate
                                 queue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];

  AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:rawAsset];
  return [[FVPHlsOverridePlayerItem alloc] initWithPlayerItem:item];
}

@end
