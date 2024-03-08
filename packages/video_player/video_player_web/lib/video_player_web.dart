// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_util';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'src/video_player.dart';

/// The web implementation of [VideoPlayerPlatform].
///
/// This class implements the `package:video_player` functionality for the web.
class VideoPlayerPlugin extends VideoPlayerPlatform {
  /// Registers this class as the default instance of [VideoPlayerPlatform].
  static void registerWith(Registrar registrar) {
    VideoPlayerPlatform.instance = VideoPlayerPlugin();
  }

  // Map of textureId -> VideoPlayer instances
  final Map<int, VideoPlayer> _videoPlayers = <int, VideoPlayer>{};

  // Simulate the native "textureId".
  int _textureCounter = 1;

  @override
  Future<void> init() async {
    return _disposeAllPlayers();
  }

  @override
  Future<void> dispose(int textureId) async {
    _player(textureId).dispose();

    _videoPlayers.remove(textureId);
    return;
  }

  void _disposeAllPlayers() {
    for (final VideoPlayer videoPlayer in _videoPlayers.values) {
      videoPlayer.dispose();
    }
    _videoPlayers.clear();
  }

  @override
  Future<int> create(DataSource dataSource) async {
    final int textureId = _textureCounter++;

    late String uri;
    switch (dataSource.sourceType) {
      case DataSourceType.network:
        // Do NOT modify the incoming uri, it can be a Blob, and Safari doesn't
        // like blobs that have changed.
        uri = dataSource.uri ?? '';
      case DataSourceType.asset:
        String assetUrl = dataSource.asset!;
        if (dataSource.package != null && dataSource.package!.isNotEmpty) {
          assetUrl = 'packages/${dataSource.package}/$assetUrl';
        }
        assetUrl = ui_web.assetManager.getAssetUrl(assetUrl);
        uri = assetUrl;
      case DataSourceType.file:
        return Future<int>.error(UnimplementedError(
            'web implementation of video_player cannot play local files'));
      case DataSourceType.contentUri:
        return Future<int>.error(UnimplementedError(
            'web implementation of video_player cannot play content uri'));
    }

    final web.HTMLVideoElement videoElement = web.HTMLVideoElement()
      ..id = 'videoElement-$textureId'
      ..style.border = 'none'
      ..style.height = '100%'
      ..style.width = '100%';

    // if we are rendering as textures, we need the video element appear to be visible or chrome won't allow us to create an image bitmap
    if (renderVideoAsTexture) {
      videoElement.crossOrigin = 'anonymous';
      videoElement.style.opacity = '0';
      videoElement.style.pointerEvents = 'none';
    } else {
      // TODO(hterkelsen): Use initialization parameters once they are available
      ui_web.platformViewRegistry.registerViewFactory(
          'videoPlayer-$textureId', (int viewId) => videoElement);
    }

    final VideoPlayer player = VideoPlayer(videoElement: videoElement)
      ..initialize(
        src: uri,
      );

    _videoPlayers[textureId] = player;

    return textureId;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {
    return _player(textureId).setLooping(looping);
  }

  @override
  Future<void> play(int textureId) async {
    return _player(textureId).play();
  }

  @override
  Future<void> pause(int textureId) async {
    return _player(textureId).pause();
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    return _player(textureId).setVolume(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    return _player(textureId).setPlaybackSpeed(speed);
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    return _player(textureId).seekTo(position);
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    return _player(textureId).getPosition();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _player(textureId).events;
  }

  @override
  Future<void> setWebOptions(int textureId, VideoPlayerWebOptions options) {
    return _player(textureId).setOptions(options);
  }

  // Retrieves a [VideoPlayer] by its internal `id`.
  // It must have been created earlier from the [create] method.
  VideoPlayer _player(int id) {
    return _videoPlayers[id]!;
  }

  @override
  Widget buildView(int textureId) {
    if (renderVideoAsTexture) {
      return _WebVideoPlayerRenderer(
          element: _videoPlayers[textureId]!.videoElement);
    } else {
      return HtmlElementView(viewType: 'videoPlayer-$textureId');
    }
  }

  /// Whether to render the video directly into the canvas. If true (default),
  /// the video will be drawn into the canvas. If false, the video will be
  /// rendered using a <video> element inside a platform view.
  static bool renderVideoAsTexture = true;

  /// Sets the audio mode to mix with other sources (ignored)
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) => Future<void>.value();
}

class _WebVideoPlayerRenderer extends StatefulWidget {
  const _WebVideoPlayerRenderer({required this.element});

  final web.HTMLVideoElement element;

  @override
  State createState() => _WebVideoPlayerRendererState();
}

class _WebVideoPlayerRendererState extends State<_WebVideoPlayerRenderer> {
  @override
  void initState() {
    super.initState();

    getFrame(widget.element);
    web.document.body!.appendChild(widget.element);
  }

  int? callbackID;

  void getFrame(web.HTMLVideoElement element) {
    callbackID = element.requestVideoFrameCallback(frameCallback.toJS);
  }

  void cancelFrame(web.HTMLVideoElement element) {
    if (callbackID != null) {
      element.cancelVideoFrameCallback(callbackID!);
    }
  }

  void frameCallback(JSAny now, JSAny metadata) {
    capture();
  }

  Future<void> capture() async {
    final tmp =
        await promiseToFuture(web.window.createImageBitmap(widget.element));
    final ui.Image img = await ui_web.createImageFromImageBitmap(tmp);

    if (mounted) {
      setState(() {
        image = img;
      });
      getFrame(widget.element);
    }
  }

  @override
  void dispose() {
    cancelFrame(widget.element);
    super.dispose();
    if (web.document.body!.contains(widget.element)) {
      web.document.body!.removeChild(widget.element);
    }
  }

  @override
  void didUpdateWidget(_WebVideoPlayerRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.element != widget.element) {
      if (web.document.body!.contains(oldWidget.element)) {
        web.document.body!.removeChild(oldWidget.element);
      }
      web.document.body!.appendChild(widget.element);
      cancelFrame(oldWidget.element);
      getFrame(widget.element);
    }
  }

  ui.Image? image;

  @override
  Widget build(BuildContext context) {
    if (image != null) {
      return RawImage(image: image);
    } else {
      return const ColoredBox(color: Colors.black);
    }
  }
}

typedef _VideoFrameRequestCallback = JSFunction;

extension _createImageBitmap on web.Window {
  external JSPromise createImageBitmap(JSAny source);
}

extension _HTMLVideoElementRequestAnimationFrame on web.HTMLVideoElement {
  external int requestVideoFrameCallback(_VideoFrameRequestCallback callback);
  external void cancelVideoFrameCallback(int callbackID);
}
