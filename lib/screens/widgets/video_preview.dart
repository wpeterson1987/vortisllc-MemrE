// lib/widgets/video_preview.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VideoPreview extends StatefulWidget {
  final Uint8List videoBytes;

  const VideoPreview({
    Key? key,
    required this.videoBytes,
  }) : super(key: key);

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      // Create temporary file from bytes
      final tempDir = await getTemporaryDirectory();
      _tempFile = File('${tempDir.path}/temp_video.mp4');
      await _tempFile!.writeAsBytes(widget.videoBytes);

      _videoPlayerController = VideoPlayerController.file(_tempFile!);
      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        aspectRatio: _videoPlayerController.value.aspectRatio,
        autoPlay: false,
        looping: false,
      );

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Error initializing video: $e');
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    // Clean up temporary file
    _tempFile?.delete().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return SizedBox(
      height: 300,
      child: Chewie(
        controller: _chewieController!,
      ),
    );
  }
}
