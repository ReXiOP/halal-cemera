import 'dart:io';
import 'package:flutter/material.dart';
import '../core/media_saver.dart';
import 'image_viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final MediaSaver _mediaSaver = MediaSaver();
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    final files = await _mediaSaver.getGalleryFiles();
    setState(() {
      _files = files;
      _isLoading = false;
    });
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Delete All?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete all ${_files.length} images? This cannot be undone.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (var file in _files) {
        try {
          await File(file.path).delete();
        } catch (e) {
          debugPrint('Error deleting ${file.path}: $e');
        }
      }
      _loadFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All images deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Gallery (${_files.length})',
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_files.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : _files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 80, color: Colors.grey[700]),
                      const SizedBox(height: 16),
                      Text(
                        'No photos yet',
                        style: TextStyle(color: Colors.grey[600], fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Capture photos to see them here',
                        style: TextStyle(color: Colors.grey[700], fontSize: 14),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadFiles,
                  color: Colors.amber,
                  backgroundColor: Colors.grey[900],
                  child: GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      return GestureDetector(
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ImageViewerScreen(
                                images: _files,
                                initialIndex: index,
                              ),
                            ),
                          );
                          if (result == true) {
                            _loadFiles(); // Refresh if image was deleted
                          }
                        },
                        child: Hero(
                          tag: file.path,
                          child: Image.file(
                            File(file.path),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              color: Colors.grey[800],
                              child: const Icon(Icons.broken_image,
                                  color: Colors.grey),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
