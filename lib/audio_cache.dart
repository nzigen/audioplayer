import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'audioplayers.dart';
import 'package:http/http.dart' as http;

/// This class represents a cache for Local Assets to be played.
///
/// Flutter can only play audios on device folders, so this first copies files to a temporary folder and the plays then.
/// You can pre-cache your audio, or clear the cache, as desired.
class AudioCache {
  /// A reference to the loaded files.
  Map<String, File> loadedFiles = {};

  /// This is the path inside your assets folder where your files lie.
  ///
  /// For example, Flame uses the prefix 'assets/audio/' (must include the slash!).
  /// Your files will be found at <prefix><fileName>
  String prefix;

  /// This is an instance of AudioPlayer that, if present, will always be used.
  ///
  /// If not set, the AudioCache will create and return a instance of AudioPlayer every call, allowing for simultaneous calls.
  /// If this is set, every call will overwrite previous calls.
  AudioPlayer fixedPlayer;

  AudioCache({this.prefix = "", this.fixedPlayer = null});

  /// Clear the cache of the file [fileName].
  ///
  /// Does nothing if there was already no cache.
  void clear(String fileName) {
    loadedFiles.remove(fileName);
  }

  /// Clear the whole cache.
  void clearCache() {
    loadedFiles.clear();
  }

  /// Disable [AudioPlayer] logs (enable only if debuggin, otherwise they can be quite overwhelming).
  void disableLog() {
    AudioPlayer.logEnabled = false;
  }

  Future<Uint8List> _fetchAsset(String fileName) async {
    return (await rootBundle.load('$prefix$fileName')).buffer.asUint8List();
  }

  Future<Uint8List> _fetchNetwork(String url) async {
    final response = await http.get(url);
    return response.bodyBytes;
  }

  Future<File> fetchToMemory(String fileName) async {
    final Uri uri = Uri.parse(fileName);
    String fullPath;
    
    final temporaryPath = (await getTemporaryDirectory()).path;
    final isNetwork = uri.scheme == 'http' || uri.scheme == 'https';
    if (isNetwork) {
      fullPath = '$temporaryPath/${uri.host}${uri.path}';
    } else {
      fullPath = '$temporaryPath/$fileName';
    }
    final file = File(fullPath);
    if (await file.exists()) {
      return file;
    }
    final splitted = fullPath.split('/');
    final replaced = splitted.sublist(0, splitted.length - 1).join('/');
    await Directory(replaced).create(recursive: true);
    if (isNetwork) {
      return await file.writeAsBytes(await _fetchNetwork(fileName));
    }
    return await file.writeAsBytes(await _fetchAsset(fileName));
  }

  /// Load all the [fileNames] provided to the cache.
  ///
  /// Also retruns a list of [Future]s for those files.
  Future<List<File>> loadAll(List<String> fileNames) async {
    return Future.wait(fileNames.map(load));
  }

  /// Load a single [fileName] to the cache.
  ///
  /// Also retruns a [Future] to access that file.
  Future<File> load(String fileName) async {
    if (!loadedFiles.containsKey(fileName)) {
      loadedFiles[fileName] = await fetchToMemory(fileName);
    }
    return loadedFiles[fileName];
  }

  AudioPlayer _player() {
    return fixedPlayer ?? AudioPlayer();
  }

  /// Plays the given [fileName].
  ///
  /// If the file is already cached, it plays imediatelly. Otherwise, first waits for the file to load (might take a few milliseconds).
  /// It creates a instance of [AudioPlayer], so it does not affect other audios playing (unless you specify a [fixedPlayer], in which case it always use the same).
  /// The instance is returned, to allow later access (either way).
  Future<AudioPlayer> play(String fileName, {double volume = 1.0}) async {
    File file = await load(fileName);
    AudioPlayer player = _player();
    await player.play(file.path, isLocal: true, volume: volume);
    return player;
  }

  /// Like [play], but loops the audio (starts over once finished).
  ///
  /// The instance of [AudioPlayer] created is returned, so you can use it to stop the playback as desired.
  Future<AudioPlayer> loop(String fileName, {double volume = 1.0}) async {
    File file = await load(fileName);
    AudioPlayer player = _player();
    player.setReleaseMode(ReleaseMode.LOOP);
    player.play(file.path, isLocal: true, volume: volume);
    return player;
  }
}
