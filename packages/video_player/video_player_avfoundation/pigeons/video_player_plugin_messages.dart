// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Contains plugin-class-level APIs.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/video_player_plugin_messages.g.dart',
    swiftOut:
        'darwin/video_player_avfoundation/Sources/video_player_avfoundation/VideoPlayerPluginMessages.g.swift',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Information passed to the platform view creation.
class PlatformVideoViewCreationParams {
  const PlatformVideoViewCreationParams({required this.playerId});

  final int playerId;
}

/// Metadata for the system media notification when playing in background.
class NotificationMetadataMessage {
  NotificationMetadataMessage({
    required this.id,
    this.title,
    this.album,
    this.artist,
    this.durationMs,
    this.artUri,
  });

  String id;
  String? title;
  String? album;
  String? artist;
  int? durationMs;
  String? artUri;
}

/// Message for configuring background playback with media notification.
class BackgroundPlaybackMessage {
  BackgroundPlaybackMessage({required this.enableBackground, this.notificationMetadata});

  bool enableBackground;
  NotificationMetadataMessage? notificationMetadata;
}

class CreationOptions {
  CreationOptions({
    required this.uri,
    required this.httpHeaders,
    required this.allowExternalPlayback,
    this.backgroundPlayback,
  });

  String uri;
  Map<String, String> httpHeaders;

  /// Whether to allow video playback on external displays (e.g., AirPlay).
  bool allowExternalPlayback;

  /// Background playback configuration (optional).
  BackgroundPlaybackMessage? backgroundPlayback;
}

class TexturePlayerIds {
  TexturePlayerIds({required this.playerId, required this.textureId});

  final int playerId;
  final int textureId;
}

@HostApi()
abstract class AVFoundationVideoPlayerApi {
  void initialize();
  // Creates a new player using a platform view for rendering and returns its
  // ID.
  @SwiftFunction('createPlatformViewPlayer(options:)')
  int createForPlatformView(CreationOptions params);
  // Creates a new player using a texture for rendering and returns its IDs.
  @SwiftFunction('createTexturePlayer(options:)')
  TexturePlayerIds createForTextureView(CreationOptions creationOptions);
  @SwiftFunction('setMixWithOthers(_:)')
  void setMixWithOthers(bool mixWithOthers);
  @SwiftFunction('fileURLForAsset(name:package:)')
  String? getAssetUrl(String asset, String? package);
  @SwiftFunction('isPictureInPictureSupported()')
  bool isPictureInPictureSupported();
}
