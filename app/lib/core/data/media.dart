import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'supabase_providers.dart';

/// A file chosen by the student, read into memory so it works the same on
/// Android, iOS and the web.
class PickedFile {
  const PickedFile({required this.bytes, required this.name, required this.mimeType, this.width, this.height});

  final Uint8List bytes;
  final String name;
  final String mimeType;
  final int? width;
  final int? height;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  int get size => bytes.lengthInBytes;

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) return name.substring(dot + 1).toLowerCase();
    return extensionFromMime(mimeType) ?? 'bin';
  }
}

abstract final class MediaPicker {
  static final _picker = ImagePicker();

  static Future<PickedFile?> image({ImageSource source = ImageSource.gallery, double maxSide = 2048}) async {
    final file = await _picker.pickImage(source: source, maxWidth: maxSide, maxHeight: maxSide, imageQuality: 85);
    return file == null ? null : _read(file, measure: true);
  }

  static Future<List<PickedFile>> images({int limit = 4}) async {
    final files = await _picker.pickMultiImage(limit: limit, maxWidth: 2048, maxHeight: 2048, imageQuality: 85);
    final picked = <PickedFile>[];
    for (final file in files.take(limit)) {
      picked.add(await _read(file, measure: true));
    }
    return picked;
  }

  static Future<PickedFile?> video({Duration maxDuration = const Duration(seconds: 90)}) async {
    final file = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: maxDuration);
    return file == null ? null : _read(file);
  }

  static Future<PickedFile?> anyFile() => _file(FileType.any);

  /// A song or other audio file from the device.
  static Future<PickedFile?> audio() => _file(FileType.audio);

  static Future<PickedFile?> _file(FileType type) async {
    final file = await FilePicker.pickFile(type: type);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final mime = lookupMimeType(file.name, headerBytes: bytes.take(32).toList()) ?? 'application/octet-stream';
    return PickedFile(bytes: bytes, name: file.name, mimeType: mime, width: null, height: null);
  }

  static Future<PickedFile> _read(XFile file, {bool measure = false}) async {
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ??
        lookupMimeType(file.name, headerBytes: bytes.take(32).toList()) ??
        'application/octet-stream';
    final size = measure && mime.startsWith('image/') ? await measureImage(bytes) : null;
    final name = file.name.isNotEmpty ? file.name : 'upload.${extensionFromMime(mime) ?? 'bin'}';
    return PickedFile(bytes: bytes, name: name, mimeType: mime, width: size?.$1, height: size?.$2);
  }
}

/// An image's (width, height), or null if it can't be read.
Future<(int, int)?> measureImage(Uint8List bytes) async {
  try {
    // Reads only the header; not available on the web.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (descriptor.width, descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return size;
  } catch (_) {}
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

final storageRepositoryProvider = Provider<StorageRepository>((ref) => StorageRepository(ref.watch(supabaseProvider)));

/// Uploads to Supabase Storage. Public buckets return a URL; chat files stay
/// private and are read through short-lived signed URLs.
class StorageRepository {
  StorageRepository(this._client);

  final SupabaseClient _client;
  final _signed = <String, (String, DateTime)>{};

  static const _uuid = Uuid();

  Future<String> uploadAvatar(PickedFile file) => _uploadPublic('avatars', 'profile', file);

  /// [folder] groups files by use: posts, reels, posters, communities.
  Future<String> uploadMedia(PickedFile file, {required String folder}) => _uploadPublic('media', folder, file);

  Future<String> _uploadPublic(String bucket, String folder, PickedFile file) async {
    final path = '${_client.uid}/$folder/${_uuid.v4()}.${file.extension}';
    await _client.storage.from(bucket).uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mimeType, cacheControl: '31536000'),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Returns the storage path to keep on the message.
  Future<String> uploadChatFile(String conversationId, PickedFile file) async {
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$conversationId/${_client.uid}/${_uuid.v4().substring(0, 8)}-$safeName';
    await _client.storage.from('chat').uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mimeType),
        );
    return path;
  }

  Future<String> chatFileUrl(String path) async {
    final cached = _signed[path];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return cached.$1;
    final url = await _client.storage.from('chat').createSignedUrl(path, 3600);
    _signed[path] = (url, DateTime.now().add(const Duration(minutes: 50)));
    return url;
  }
}
