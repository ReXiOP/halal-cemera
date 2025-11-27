import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class YoloDetector {
  Interpreter? _interpreter;
  List<String>? _labels;

  static const String modelPath = 'assets/models/yolov8n_float16.tflite';
  static const String labelsPath = 'assets/models/labels.txt';

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);
      // Load labels if available, otherwise default to COCO classes
      _labels = await rootBundle.loadString(labelsPath).then((s) => s.split('\n'));
      debugPrint('YOLO model loaded successfully');
    } catch (e) {
      debugPrint('Error loading YOLO model: $e');
    }
  }

  Future<List<List<double>>> detect(img.Image image, {List<String>? allowedLabels, double confidenceThreshold = 0.4}) async {
    if (_interpreter == null) return [];

    // Preprocess image
    final input = _preprocess(image);
    
    // Output tensor shape depends on model, typically [1, 84, 8400] for YOLOv8n
    // 84 = 4 box coordinates + 80 class probabilities
    final output = List.filled(1 * 84 * 8400, 0.0).reshape([1, 84, 8400]);

    _interpreter!.run(input, output);

    return _postprocess(output[0], allowedLabels, confidenceThreshold);
  }

  List<dynamic> _preprocess(img.Image image) {
    // Image should already be 640x640 from caller
    // Normalize to 0-1
    var input = List.generate(1, (i) => List.generate(640, (y) => List.generate(640, (x) => List.generate(3, (c) => 0.0))));
    
    for (var y = 0; y < 640; y++) {
      for (var x = 0; x < 640; x++) {
        final pixel = image.getPixel(x, y);
        input[0][y][x][0] = pixel.r / 255.0;
        input[0][y][x][1] = pixel.g / 255.0;
        input[0][y][x][2] = pixel.b / 255.0;
      }
    }
    return input;
  }

  List<List<double>> _postprocess(List<dynamic> output, List<String>? allowedLabels, double confidenceThreshold) {
    // Output shape is [84, 8400]
    // 84 rows: 4 box coordinates (cx, cy, w, h) + 80 class scores
    // 8400 columns: number of predictions
    
    List<List<double>> boxes = [];
    const int cols = 8400;

    // Iterate over 8400 predictions (columns)
    for (int i = 0; i < cols; i++) {
      double maxScore = 0;
      int classId = -1;

      // Find the class with the highest score
      // Class scores are in rows 4-83
      for (int c = 0; c < 80; c++) {
        double score = (output[4 + c] as List<dynamic>)[i] as double;
        if (score > maxScore) {
          maxScore = score;
          classId = c;
        }
      }

      // Check if detection is valid
      if (maxScore > confidenceThreshold) {
        // Check if class is allowed
        bool isAllowed = false;
        if (allowedLabels == null || allowedLabels.isEmpty) {
          // Default to person only if no labels provided (backward compatibility)
          isAllowed = classId == 0; 
        } else {
          if (_labels != null && classId < _labels!.length) {
            final detectedLabel = _labels![classId];
            isAllowed = allowedLabels.contains(detectedLabel);
          }
        }

        if (isAllowed) {
          double cx = (output[0] as List<dynamic>)[i] as double;
          double cy = (output[1] as List<dynamic>)[i] as double;
          double w = (output[2] as List<dynamic>)[i] as double;
          double h = (output[3] as List<dynamic>)[i] as double;

          // Convert center coordinates to top-left coordinates [x, y, w, h]
          double x = cx - (w / 2);
          double y = cy - (h / 2);

          debugPrint('Raw Detection: score=$maxScore, class=$classId, cx=$cx, cy=$cy, w=$w, h=$h');
          boxes.add([x, y, w, h, maxScore]);
        }
      }
    }
    
    return _nms(boxes);
  }

  List<List<double>> _nms(List<List<double>> boxes) {
    // Simple NMS implementation
    // Sort by score
    boxes.sort((a, b) => b[4].compareTo(a[4]));
    
    List<List<double>> result = [];
    while (boxes.isNotEmpty) {
      var current = boxes.removeAt(0);
      result.add(current);
      
      boxes.removeWhere((box) => _iou(current, box) > 0.6);
    }
    return result;
  }

  double _iou(List<double> boxA, List<double> boxB) {
    double xA = boxA[0] > boxB[0] ? boxA[0] : boxB[0];
    double yA = boxA[1] > boxB[1] ? boxA[1] : boxB[1];
    double xB = boxA[0] + boxA[2] < boxB[0] + boxB[2] ? boxA[0] + boxA[2] : boxB[0] + boxB[2];
    double yB = boxA[1] + boxA[3] < boxB[1] + boxB[3] ? boxA[1] + boxA[3] : boxB[1] + boxB[3];

    double interArea = (xB - xA > 0 ? xB - xA : 0) * (yB - yA > 0 ? yB - yA : 0);
    double boxAArea = boxA[2] * boxA[3];
    double boxBArea = boxB[2] * boxB[3];

    return interArea / (boxAArea + boxBArea - interArea);
  }
}
