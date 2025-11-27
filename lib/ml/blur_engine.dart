import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

class BlurEngine {
  Future<img.Image> applyBlur(img.Image originalImage, List<List<double>> boxes) async {
    img.Image processed = img.Image.from(originalImage);

    // Load settings
    final prefs = await SharedPreferences.getInstance();
    final blurIntensity = prefs.getDouble('blur_intensity') ?? 30.0;
    final useMagicEraser = prefs.getBool('use_magic_eraser') ?? false;

    debugPrint('Blur settings: intensity=$blurIntensity, magicEraser=$useMagicEraser');

    for (var box in boxes) {
      // box: [x, y, w, h, score] where coordinates are normalized (0.0-1.0)
      
      // Scale normalized coordinates to actual image dimensions
      double x = box[0] * originalImage.width;
      double y = box[1] * originalImage.height;
      double w = box[2] * originalImage.width;
      double h = box[3] * originalImage.height;

      // Convert to integers and clamp to image bounds
      int xInt = x.toInt().clamp(0, originalImage.width - 1);
      int yInt = y.toInt().clamp(0, originalImage.height - 1);
      int wInt = w.toInt().clamp(1, originalImage.width - xInt);
      int hInt = h.toInt().clamp(1, originalImage.height - yInt);

      debugPrint('Processing Region: x=$xInt, y=$yInt, w=$wInt, h=$hInt');

      if (wInt <= 0 || hInt <= 0) continue;

      if (useMagicEraser) {
        // Modern AI-style magic eraser with content-aware fill
        _applyModernMagicEraser(processed, xInt, yInt, wInt, hInt);
      } else {
        // Multi-pass blur for stronger effect
        _applyStrongBlur(processed, xInt, yInt, wInt, hInt, blurIntensity.toInt());
      }
    }

    return processed;
  }

  void _applyStrongBlur(img.Image image, int x, int y, int w, int h, int intensity) {
    // Extract region
    img.Image crop = img.copyCrop(image, x: x, y: y, width: w, height: h);
    
    // Apply multiple passes of blur for stronger effect
    img.Image blurred = crop;
    int passes = (intensity / 15).ceil().clamp(1, 5);
    
    for (int i = 0; i < passes; i++) {
      blurred = img.gaussianBlur(blurred, radius: math.min(intensity, 25));
    }
    
    // Composite back
    img.compositeImage(image, blurred, dstX: x, dstY: y);
  }

  void _applyModernMagicEraser(img.Image image, int x, int y, int w, int h) {
    // 1. Collect valid background samples from the immediate border
    const int margin = 5;
    List<img.Pixel> borderPixels = [];
    
    int rSum = 0, gSum = 0, bSum = 0;
    int count = 0;

    for (int dy = -margin; dy <= h + margin; dy++) {
      for (int dx = -margin; dx <= w + margin; dx++) {
        // Check if we are in the border region (not inside the box)
        bool isBorder = (dx < 0 || dx >= w || dy < 0 || dy >= h);
        
        if (isBorder) {
          int px = (x + dx).clamp(0, image.width - 1);
          int py = (y + dy).clamp(0, image.height - 1);
          
          var pixel = image.getPixel(px, py);
          borderPixels.add(pixel);
          
          rSum += pixel.r.toInt();
          gSum += pixel.g.toInt();
          bSum += pixel.b.toInt();
          count++;
        }
      }
    }

    if (count == 0) return;

    // Calculate average background color
    int avgR = rSum ~/ count;
    int avgG = gSum ~/ count;
    int avgB = bSum ~/ count;

    // 2. Fill the region with a gradient/blended approach
    // We fill from outside in, or just use a smart noise fill based on average
    
    for (int j = 0; j < h; j++) {
      for (int i = 0; i < w; i++) {
        int px = x + i;
        int py = y + j;
        
        if (px >= image.width || py >= image.height) continue;

        // Simple Inpainting:
        // Mix the average color with some noise derived from the border pixels
        // to simulate texture.
        
        // Pick a random pixel from border to simulate texture
        int randIndex = ((px * i + py * j + i * j) % borderPixels.length).abs();
        var texturePixel = borderPixels[randIndex];
        
        // Blend average with texture (60% texture, 40% average)
        int r = (texturePixel.r.toInt() * 0.6 + avgR * 0.4).toInt();
        int g = (texturePixel.g.toInt() * 0.6 + avgG * 0.4).toInt();
        int b = (texturePixel.b.toInt() * 0.6 + avgB * 0.4).toInt();
        
        // Add slight noise for realism
        int noise = (math.Random().nextInt(10) - 5);
        r = (r + noise).clamp(0, 255);
        g = (g + noise).clamp(0, 255);
        b = (b + noise).clamp(0, 255);

        image.setPixelRgb(px, py, r, g, b);
      }
    }

    // 3. Apply a strong blur ONLY to the filled region to smooth it out
    // We crop, blur, and paste back.
    try {
      img.Image region = img.copyCrop(image, x: x, y: y, width: w, height: h);
      // Gaussian blur to remove hard noise patterns
      region = img.gaussianBlur(region, radius: 5);
      img.compositeImage(image, region, dstX: x, dstY: y);
      
      // 4. Blend edges (blur the boundary)
      // This is expensive but looks better. We blur a slightly larger region.
      int blendMargin = 5;
      int bx = (x - blendMargin).clamp(0, image.width - 1);
      int by = (y - blendMargin).clamp(0, image.height - 1);
      int bw = (w + blendMargin * 2).clamp(1, image.width - bx);
      int bh = (h + blendMargin * 2).clamp(1, image.height - by);
      
      img.Image edgeRegion = img.copyCrop(image, x: bx, y: by, width: bw, height: bh);
      edgeRegion = img.gaussianBlur(edgeRegion, radius: 3);
      
      // We only want to apply this blur to the EDGES, but applying to the whole
      // expanded region is a decent approximation for "blending" into background.
      // For performance, we might skip this or keep it simple.
      // Let's stick to the inner blur for now to save processing time on mobile.
    } catch (e) {
      debugPrint('Error blending magic eraser: $e');
    }
  }
}
