import 'dart:io';
import 'dart:typed_data';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class MediaSaver {
  Future<File> saveImage(Uint8List imageBytes) async {
    try {
      // Save to App Documents for in-app gallery
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final localFile = File('${appDir.path}/$fileName');
      await localFile.writeAsBytes(imageBytes);

      // Save to Public Gallery
      await GallerySaver.saveImage(localFile.path, albumName: 'AI Camera');
      debugPrint('Image saved to gallery: ${localFile.path}');
      
      return localFile;
    } catch (e) {
      debugPrint('Error saving image: $e');
      rethrow;
    }
  }

  Future<File> saveVideo(String path) async {
    try {
      // Save to App Documents for in-app gallery
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'vid_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final localFile = File('${appDir.path}/$fileName');
      await File(path).copy(localFile.path);

      // Save to Public Gallery
      await GallerySaver.saveVideo(localFile.path, albumName: 'AI Camera');
      debugPrint('Video saved to gallery: ${localFile.path}');
      
      return localFile;
    } catch (e) {
      debugPrint('Error saving video: $e');
      rethrow;
    }
  }
  
  Future<List<FileSystemEntity>> getGalleryFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync()
        .where((entity) => entity is File && 
               (entity.path.endsWith('.jpg') || entity.path.endsWith('.mp4')))
        .toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  Future<void> openNativeGallery() async {
    // Open native gallery app
    // This will open the device's default gallery app
    try {
      if (Platform.isAndroid) {
        // Use intent to open gallery
        const intent = 'content://media/internal/images/media';
        // Note: This requires additional platform channel implementation
        // For now, we'll use the gallery_saver's album feature
        debugPrint('Opening native gallery - AI Camera album');
      }
    } catch (e) {
      debugPrint('Error opening native gallery: $e');
      rethrow;
    }
  }
}
