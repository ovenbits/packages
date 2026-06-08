// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Contains player-instance-level APIs.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/video_player_instance_messages.g.dart',
    objcHeaderOut:
        'darwin/video_player_avfoundation/Sources/video_player_avfoundation_objc/include/video_player_avfoundation_objc/VideoPlayerInstanceMessages.g.h',
    objcSourceOut:
        'darwin/video_player_avfoundation/Sources/video_player_avfoundation_objc/VideoPlayerInstanceMessages.g.m',
    objcOptions: ObjcOptions(
      prefix: 'FVP',
      headerIncludePath: './include/video_player_avfoundation_objc/VideoPlayerInstanceMessages.g.h',
    ),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Raw audio track data from AVMediaSelectionOption (for HLS streams).
class MediaSelectionAudioTrackData {
  MediaSelectionAudioTrackData({
    required this.index,
    this.displayName,
    this.languageCode,
    required this.isSelected,
    this.commonMetadataTitle,
  });

  int index;
  String? displayName;
  String? languageCode;
  bool isSelected;
  String? commonMetadataTitle;
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

@HostApi()
abstract class VideoPlayerInstanceApi {
  @ObjCSelector('setLooping:')
  void setLooping(bool looping);
  @ObjCSelector('setVolume:')
  void setVolume(double volume);
  @ObjCSelector('setPlaybackSpeed:')
  void setPlaybackSpeed(double speed);
  void play();
  @ObjCSelector('position')
  int getPosition();
  @async
  @ObjCSelector('seekTo:')
  void seekTo(int position);
  void pause();
  void dispose();
  @ObjCSelector('getAudioTracks')
  List<MediaSelectionAudioTrackData> getAudioTracks();
  @ObjCSelector('selectAudioTrackAtIndex:')
  void selectAudioTrack(int trackIndex);
  @ObjCSelector('startPictureInPicture')
  void startPictureInPicture();
  @ObjCSelector('stopPictureInPicture')
  void stopPictureInPicture();
  @ObjCSelector('setAutoPictureInPicture:')
  void setAutoPictureInPicture(bool enabled);
}
