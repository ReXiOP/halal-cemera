import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:typed_data';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import '../ml/yolo_detector.dart';
import '../ml/blur_engine.dart';
import '../core/media_saver.dart';
import '../core/video_processor.dart';
import '../core/image_enhancer.dart';
// import 'gallery_screen.dart'; // Deprecated
import 'settings_screen.dart';
import 'video_coming_soon_screen.dart';
import 'grid_painter.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  int _selectedCameraIndex = 0;
  bool _isRecording = false; // Placeholder for video recording state
  int _selectedMode = 0; // 0: Photo, 1: Video
  
  final YoloDetector _detector = YoloDetector();
  final BlurEngine _blurEngine = BlurEngine();
  final MediaSaver _mediaSaver = MediaSaver();
  final VideoProcessor _videoProcessor = VideoProcessor();
  final NativeDeviceOrientationCommunicator _orientationCommunicator = NativeDeviceOrientationCommunicator();
  final ImageEnhancer _enhancer = ImageEnhancer();
  bool _isProcessing = false;
  File? _lastCapturedMedia;
  List<String> _selectedLabels = ['person'];

  // Camera controls
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 8.0;
  FlashMode _flashMode = FlashMode.off;
  double _currentExposure = 0.0;
  Offset? _focusPoint;
  bool _showFocusIndicator = false;
  bool _showZoomSlider = false;
  final List<double> _zoomPresets = [0.5, 1.0, 2.0, 3.0, 5.0];
  
  // Animations
  late AnimationController _shutterController;
  late AnimationController _scanController;
  double _imageQuality = 95.0;
  double _confidenceThreshold = 0.25;
  
  // Advanced Features
  int _aspectRatioIndex = 1; // 0: 1:1, 1: 3:4, 2: 9:16, 3: Full
  final List<double> _aspectRatios = [1.0, 3/4, 9/16, 20/9]; // 20/9 is approx for full screen, will handle specially
  final List<String> _aspectRatioLabels = ['1:1', '3:4', '9:16', 'FULL'];
  
  bool _showGrid = false;
  int _timerDuration = 0; // 0, 3, 10
  bool _isTimerRunning = false;
  int _timerCountdown = 0;
  bool _isSwitchingCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _shutterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0.9,
      upperBound: 1.0,
    );

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initializeCamera();
    _loadModel();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance(); // Import shared_preferences if not already imported, but it seems it is used in settings_screen, so I might need to add import here if not present.
    // Wait, SharedPreferences is not imported in camera_screen.dart based on previous view.
    // I need to add the import.
    setState(() {
      _selectedLabels = prefs.getStringList('selected_labels') ?? ['person'];
      _imageQuality = (prefs.getDouble('image_quality') ?? 95.0).clamp(50.0, 100.0);
      _confidenceThreshold = (prefs.getDouble('confidence_threshold') ?? 0.25).clamp(0.1, 0.9);
      _aspectRatioIndex = (prefs.getInt('aspect_ratio_index') ?? 1).clamp(0, _aspectRatios.length - 1);
    });
  }

  Future<void> _loadModel() async {
    await _detector.loadModel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _shutterController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    var status = await Permission.camera.request();
    if (status.isDenied) {
      // Handle permission denied
      return;
    }

    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _controller = CameraController(
        _cameras![_selectedCameraIndex],
        ResolutionPreset.max, // Maximum resolution for best quality
        enableAudio: false, // Disable audio for photos to potentially improve camera resource allocation
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      try {
        await _controller!.initialize();
        
        // Get zoom limits
        _minZoom = await _controller!.getMinZoomLevel();
        _maxZoom = await _controller!.getMaxZoomLevel();
        
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      } on CameraException catch (e) {
        debugPrint('Camera error: $e');
      }
    }
  }

  Future<void> _onSwitchCamera() async {
    if (_cameras == null || _cameras!.length < 2 || _isSwitchingCamera) return;
    
    setState(() {
      _isSwitchingCamera = true;
    });

    // Allow UI to update and show blur overlay
    await Future.delayed(const Duration(milliseconds: 100));

    final newIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    
    // 1. Detach controller from UI first to remove CameraPreview
    final oldController = _controller;
    if (mounted) {
      setState(() {
        _controller = null; 
      });
    }
    
    // 2. Wait for frame to render (removing CameraPreview)
    await Future.delayed(const Duration(milliseconds: 50));

    // 3. Dispose old controller safely
    try {
      await oldController?.dispose();
    } catch (e) {
      debugPrint('Error disposing camera: $e');
    }

    // 4. Small delay to allow native cleanup (helps with "dead thread" issues)
    await Future.delayed(const Duration(milliseconds: 200));

    // 5. Initialize new controller
    final newController = CameraController(
      _cameras![newIndex],
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await newController.initialize();
      
      // Get zoom limits
      final minZoom = await newController.getMinZoomLevel();
      final maxZoom = await newController.getMaxZoomLevel();
      
      if (mounted) {
        setState(() {
          _controller = newController;
          _selectedCameraIndex = newIndex;
          _minZoom = minZoom;
          _maxZoom = maxZoom;
          _currentZoom = 1.0; // Reset zoom
          _isCameraInitialized = true;
        });
        
        // Fade out overlay
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          setState(() {
            _isSwitchingCamera = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error switching camera: $e');
      if (mounted) {
        setState(() {
          _isSwitchingCamera = false;
        });
      }
    }
  }

  Future<void> _onCapturePressed() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    if (_selectedMode == 0) {
      // Timer Logic
      if (_timerDuration > 0 && !_isTimerRunning) {
        setState(() {
          _isTimerRunning = true;
          _timerCountdown = _timerDuration;
        });
        
        // Start countdown
        while (_timerCountdown > 0) {
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            setState(() {
              _timerCountdown--;
            });
          }
        }
        
        if (mounted) {
          setState(() {
            _isTimerRunning = false;
          });
        }
      }

      debugPrint('Capture Photo');
      
      // Show instant feedback FIRST
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📸 Processing in background...'),
          duration: Duration(milliseconds: 1500),
          backgroundColor: Colors.black87,
        ),
      );
      
      // Quick visual feedback
      setState(() {
        _isProcessing = true;
      });

      try {
        // Take picture - this is fast
        final XFile file = await _controller!.takePicture();
        
        // Immediately unlock UI
        setState(() {
          _isProcessing = false;
        });
        
        // Turn off flash if it was on (non-blocking)
        if (_flashMode == FlashMode.always || _flashMode == FlashMode.torch) {
          _controller!.setFlashMode(FlashMode.off).then((_) {
            if (mounted) {
              setState(() {
                _flashMode = FlashMode.off;
              });
            }
          });
        }
        
        // Process everything in background (fire and forget)
        final orientation = await _orientationCommunicator.orientation(useSensor: true);
        
        double targetRatio;
        if (_aspectRatioLabels[_aspectRatioIndex] == 'FULL') {
           // Use actual screen ratio for FULL
           targetRatio = MediaQuery.of(context).size.aspectRatio;
        } else {
           double ratio = _aspectRatios[_aspectRatioIndex];
           // If landscape, invert ratio (e.g. 3/4 -> 4/3) to match the view
           if (orientation == NativeDeviceOrientation.landscapeLeft || 
               orientation == NativeDeviceOrientation.landscapeRight) {
             ratio = 1 / ratio;
           }
           targetRatio = ratio;
        }

        _processImageFromFile(file, targetRatio, orientation);
        
      } catch (e) {
        debugPrint('Error capturing photo: $e');
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      }
    } else {
      if (_isRecording) {
        // Stop Recording
        debugPrint('Stop Recording');
        try {
          final XFile file = await _controller!.stopVideoRecording();
          setState(() {
            _isRecording = false;
            _isProcessing = true;
          });

          // Process Video
          final processedPath = await _videoProcessor.processVideo(file.path);
          
          if (processedPath != null) {
            final savedFile = await _mediaSaver.saveVideo(processedPath);
            if (mounted) {
              setState(() {
                _lastCapturedMedia = savedFile;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video processed and saved!')),
              );
            }
          } else {
             if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video processing disabled (Build Issue).')),
              );
            }
          }
        } catch (e) {
          debugPrint('Error stopping video: $e');
        } finally {
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        }
      } else {
        // Start Recording
        debugPrint('Start Recording');
        try {
          await _controller!.startVideoRecording();
          setState(() {
            _isRecording = true;
          });
        } catch (e) {
          debugPrint('Error starting video: $e');
        }
      }
    }
  }

  Future<void> _processImageFromFile(XFile file, double targetRatio, NativeDeviceOrientation orientation) async {
    try {
      // Read file in background
      final bytes = await file.readAsBytes();
      var image = img.decodeImage(bytes);

      if (image != null) {
        // Fix orientation (handle EXIF rotation)
        image = img.bakeOrientation(image);

        // Fix landscape orientation if needed
        // If the device is in landscape but the image is still portrait (width < height),
        // it means the image is rotated 90 degrees relative to the scene.
        // We rotate it manually to ensure the person is upright for detection.
        if (orientation == NativeDeviceOrientation.landscapeLeft && image.width < image.height) {
          image = img.copyRotate(image, angle: -90);
        } else if (orientation == NativeDeviceOrientation.landscapeRight && image.width < image.height) {
          image = img.copyRotate(image, angle: 90);
        }
        
        debugPrint('Image Size: ${image.width}x${image.height}, Target Ratio: $targetRatio');

        // Crop to Aspect Ratio
        final double currentRatio = image.width / image.height;
        
        if ((currentRatio - targetRatio).abs() > 0.01) {
          int newWidth = image.width;
          int newHeight = image.height;
          
          if (currentRatio > targetRatio) {
            // Image is wider than target, crop width
            newWidth = (image.height * targetRatio).toInt();
          } else {
            // Image is taller than target, crop height
            newHeight = (image.width / targetRatio).toInt();
          }
          
          final int offsetX = (image.width - newWidth) ~/ 2;
          final int offsetY = (image.height - newHeight) ~/ 2;
          
          image = img.copyCrop(image, x: offsetX, y: offsetY, width: newWidth, height: newHeight);
          debugPrint('Cropped to $newWidth x $newHeight');
        }

        // Detect (run on resized image for speed)
        final detectionImage = img.copyResize(image, width: 640, height: 640);
        final boxes = await _detector.detect(detectionImage, allowedLabels: _selectedLabels, confidenceThreshold: _confidenceThreshold);
        debugPrint('Detected ${boxes.length} objects');

        debugPrint('Original Image Size: ${image.width}x${image.height}');

        // Blur/erase on original resolution for quality
        var processedImage = await _blurEngine.applyBlur(image, boxes);

        // Apply HDR and Color Enhancement
        processedImage = _enhancer.enhance(processedImage);

        // Save with high quality
        final processedBytes = img.encodeJpg(processedImage, quality: _imageQuality.toInt());
        final savedFile = await _mediaSaver.saveImage(processedBytes);
        
        if (mounted) {
          setState(() {
            _lastCapturedMedia = savedFile;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Photo saved! (${image.width}x${image.height})'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Camera Control Methods
  Future<void> _onTapToFocus(TapDownDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
    final Size size = renderBox.size;

    // Normalize coordinates
    final double x = localPosition.dx / size.width;
    final double y = localPosition.dy / size.height;

    try {
      await _controller!.setFocusPoint(Offset(x, y));
      await _controller!.setExposurePoint(Offset(x, y));

      setState(() {
        _focusPoint = localPosition;
        _showFocusIndicator = true;
      });

      // Hide focus indicator after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showFocusIndicator = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Error setting focus: $e');
    }
  }

  Future<void> _onZoomChanged(double scale) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final double zoom = (_currentZoom * scale).clamp(_minZoom, _maxZoom);
    
    try {
      await _controller!.setZoomLevel(zoom);
      setState(() {
        _currentZoom = zoom;
      });
    } catch (e) {
      debugPrint('Error setting zoom: $e');
    }
  }

  Future<void> _setZoom(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    final clampedZoom = zoom.clamp(_minZoom, _maxZoom);
    
    try {
      await _controller!.setZoomLevel(clampedZoom);
      setState(() {
        _currentZoom = clampedZoom;
      });
    } catch (e) {
      debugPrint('Error setting zoom: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    FlashMode newMode;
    switch (_flashMode) {
      case FlashMode.off:
        newMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        newMode = FlashMode.always;
        break;
      case FlashMode.always:
        newMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        newMode = FlashMode.off;
        break;
    }

    try {
      await _controller!.setFlashMode(newMode);
      setState(() {
        _flashMode = newMode;
      });
    } catch (e) {
      debugPrint('Error setting flash: $e');
    }
  }

  Future<void> _setExposure(double value) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      await _controller!.setExposureOffset(value);
      setState(() {
        _currentExposure = value;
      });
    } catch (e) {
      debugPrint('Error setting exposure: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Allow build even if controller is null during switch (overlay will cover it)
    if (!_isCameraInitialized && !_isSwitchingCamera) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview with Aspect Ratio and Grid
          Center(
            child: AspectRatio(
              aspectRatio: _aspectRatioLabels[_aspectRatioIndex] == 'FULL' 
                  ? MediaQuery.of(context).size.aspectRatio 
                  : (MediaQuery.of(context).orientation == Orientation.landscape 
                      ? 1 / _aspectRatios[_aspectRatioIndex] 
                      : _aspectRatios[_aspectRatioIndex]),
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller?.value.previewSize?.height ?? MediaQuery.of(context).size.height,
                        height: _controller?.value.previewSize?.width ?? MediaQuery.of(context).size.width,
                        child: _controller != null && _controller!.value.isInitialized
                            ? CameraPreview(_controller!)
                            : Container(color: Colors.black),
                      ),
                    ),
                    
                    // Gesture Detector on top of preview
                    GestureDetector(
                      onTapDown: _onTapToFocus,
                      onScaleUpdate: (details) {
                        _onZoomChanged(details.scale);
                      },
                      behavior: HitTestBehavior.translucent, // Ensure touches pass through if needed, but here we want to catch them
                      child: Container(color: Colors.transparent), // Invisible container to catch gestures
                    ),

                    // Grid Overlay
                    if (_showGrid)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: GridPainter(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          
          // Scanning Animation Overlay
          if (_isProcessing)
            AnimatedBuilder(
              animation: _scanController,
              builder: (context, child) {
                return Positioned(
                  top: MediaQuery.of(context).size.height * _scanController.value - 20,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                  ),
                );
              },
            ),

          // Focus Indicator
          if (_showFocusIndicator && _focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 40,
              top: _focusPoint!.dy - 40,
              child: TweenAnimationBuilder(
                tween: Tween<double>(begin: 1.2, end: 1.0),
                duration: const Duration(milliseconds: 300),
                builder: (context, double scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.amber, width: 2),
                        borderRadius: BorderRadius.circular(40),
                      ),
                    ),
                  );
                },
              ),
            ),
          
          if (_isProcessing)
            Container(
              color: Colors.black26, // Lighter overlay
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.amber),
                    const SizedBox(height: 10),
                    Text(
                      'AI Processing...', 
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                  ],
                ),
              ),
            ),

          // Timer Countdown Overlay
          if (_isTimerRunning)
            Center(
              child: Text(
                '$_timerCountdown',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 100,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    const Shadow(
                      color: Colors.black,
                      blurRadius: 10,
                    )
                  ],
                ),
              ),
            ),

          // Transition Overlay (Smooth Switching)
          IgnorePointer(
            ignoring: !_isSwitchingCamera,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isSwitchingCamera ? 1.0 : 0.0,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.amber),
                  ),
                ),
              ),
            ),
          ),

          // Top Bar (Glassmorphism)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.only(top: 50, bottom: 10),
                  color: Colors.black.withOpacity(0.3),
                  child: _buildTopBar(),
                ),
              ),
            ),
          ),

          // iPhone-style Zoom UI
          Positioned(
            bottom: 200,
            left: 0,
            right: 0,
            child: _buildZoomUI(),
          ),

          // Bottom Controls (Glassmorphism)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: _buildBottomControls(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildRotatableIcon(
                icon: Icon(
                  _flashMode == FlashMode.off
                      ? Icons.flash_off
                      : _flashMode == FlashMode.auto
                          ? Icons.flash_auto
                          : _flashMode == FlashMode.always
                              ? Icons.flash_on
                              : Icons.flashlight_on,
                  color: Colors.white,
                ),
                onPressed: _toggleFlash,
              ),
              // Aspect Ratio Toggle
              _buildRotatableIcon(
                icon: Text(
                  _aspectRatioLabels[_aspectRatioIndex],
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: _showAspectRatioSelection,
              ),
              // Grid Toggle
              _buildRotatableIcon(
                icon: Icon(_showGrid ? Icons.grid_on : Icons.grid_off, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _showGrid = !_showGrid;
                  });
                },
              ),
              // Timer Toggle
              _buildRotatableIcon(
                icon: Icon(
                  _timerDuration == 0 
                      ? Icons.timer_off 
                      : _timerDuration == 3 
                          ? Icons.timer_3 
                          : Icons.timer_10, 
                  color: Colors.white
                ),
                onPressed: () {
                  setState(() {
                    if (_timerDuration == 0) _timerDuration = 3;
                    else if (_timerDuration == 3) _timerDuration = 10;
                    else _timerDuration = 0;
                  });
                },
              ),
              _buildRotatableIcon(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  );
                  _loadSettings();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRotatableIcon({required Widget icon, required VoidCallback onPressed}) {
    return RotatedBox(
      quarterTurns: _getQuarterTurns(),
      child: IconButton(
        icon: icon,
        onPressed: onPressed,
      ),
    );
  }

  void _showAspectRatioSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Select Aspect Ratio',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...List.generate(_aspectRatios.length, (index) {
                final isSelected = _aspectRatioIndex == index;
                return ListTile(
                  title: Text(
                    _aspectRatioLabels[index],
                    style: TextStyle(
                      color: isSelected ? Colors.amber : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check, color: Colors.amber) : null,
                  onTap: () async {
                    setState(() {
                      _aspectRatioIndex = index;
                    });
                    Navigator.pop(context);
                    
                    // Save setting
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('aspect_ratio_index', index);
                  },
                );
              }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  int _getQuarterTurns() {
    // Since we are allowing the system to rotate the layout (and thus the aspect ratio),
    // the icons will rotate with the system UI. We don't need manual counter-rotation
    // unless we lock the orientation.
    return 0;
  }

  Future<void> _openGallery() async {
    // 1. Try to open the specific file first using open_file_plus
    if (_lastCapturedMedia != null) {
      try {
        debugPrint('Attempting to open file: ${_lastCapturedMedia!.path}');
        final result = await OpenFile.open(_lastCapturedMedia!.path);
        debugPrint('OpenFile result: ${result.type} - ${result.message}');
        
        if (result.type == ResultType.done) {
          return;
        }
      } catch (e) {
        debugPrint('Error using OpenFile: $e');
      }
    }

    // 2. Fallback: Try to open the Gallery App generally
    if (Platform.isAndroid) {
      try {
        debugPrint('Launching Android Gallery Intent');
        const intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          type: 'image/*',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
      } catch (e) {
        debugPrint('Error opening gallery intent: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open gallery app')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No recent image to view')),
        );
      }
    }
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.only(bottom: 30, top: 20),
      // Decoration removed as it's handled by the parent container for glassmorphism
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode Picker
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              children: [
                _buildModeButton('PHOTO', 0),
                const SizedBox(width: 20),
                _buildModeButton('VIDEO', 1),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Shutter Area
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Gallery Thumbnail
                GestureDetector(
                  onTap: _openGallery,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(12), // Softer corners
                      border: Border.all(color: Colors.white, width: 2),
                      image: _lastCapturedMedia != null
                          ? DecorationImage(
                              image: FileImage(_lastCapturedMedia!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _lastCapturedMedia == null
                        ? const Icon(Icons.photo_library, color: Colors.white)
                        : null,
                  ),
                ),

                // Shutter Button (Animated)
                GestureDetector(
                  onTapDown: (_) => _shutterController.reverse(),
                  onTapUp: (_) {
                    _shutterController.forward();
                    _onCapturePressed();
                  },
                  onTapCancel: () => _shutterController.forward(),
                  child: ScaleTransition(
                    scale: _shutterController,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _selectedMode == 1 && _isRecording
                            ? Colors.red.withOpacity(0.5)
                            : Colors.transparent,
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _selectedMode == 1 && _isRecording ? 30 : 66,
                          height: _selectedMode == 1 && _isRecording ? 30 : 66,
                          decoration: BoxDecoration(
                            color: _selectedMode == 1 ? Colors.red : Colors.white,
                            shape: _selectedMode == 1 && _isRecording
                                ? BoxShape.rectangle
                                : BoxShape.circle,
                            borderRadius: _selectedMode == 1 && _isRecording
                                ? BorderRadius.circular(4)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Switch Camera
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cameraswitch, color: Colors.white, size: 24),
                  ),
                  onPressed: _onSwitchCamera,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(String title, int index) {
    final isSelected = _selectedMode == index;
    return GestureDetector(
      onTap: () {
        if (index == 1) {
          // Video mode - show coming soon
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const VideoComingSoonScreen()),
          );
        } else {
          setState(() {
            _selectedMode = index;
          });
        }
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isSelected ? 1.0 : 0.5,
        child: Text(
          title,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.amber : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            shadows: isSelected
                ? [
                    const Shadow(
                      color: Colors.black,
                      blurRadius: 4,
                    )
                  ]
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildZoomUI() {
    return Center(
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _zoomPresets.map((preset) {
            final isActive = (_currentZoom - preset).abs() < 0.3;
            final isAvailable = preset >= _minZoom && preset <= _maxZoom;
            
            if (!isAvailable) return const SizedBox.shrink();
            
            return GestureDetector(
              onTap: () => _setZoom(preset),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  preset == 1.0 ? '1×' : '${preset.toStringAsFixed(preset < 1 ? 1 : 0)}×',
                  style: TextStyle(
                    color: isActive ? Colors.amber : Colors.white,
                    fontSize: isActive ? 18 : 15,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
