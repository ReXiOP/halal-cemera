import 'package:image/image.dart' as img;
import 'dart:math' as math;

class ImageEnhancer {
  
  /// Applies a full pipeline of enhancements:
  /// 1. Noise Reduction (mild)
  /// 2. HDR / Tone Mapping
  /// 3. Color Grading / Saturation Boost
  /// 4. Sharpening
  img.Image enhance(img.Image image) {
    // Temporarily disabling enhancements to fix "messy/dots" issue.
    // The current algorithms are amplifying sensor noise too much.
    // Returning original image for clean capture.
    
    // 1. Mild Noise Reduction
    // image = img.gaussianBlur(image, radius: 1); 

    // 2. HDR / Tone Mapping
    // image = _applyToneMapping(image);

    // 3. Color Grading
    // image = _applyColorGrading(image);

    return image;
  }

  /// Simulates HDR by lifting shadows and taming highlights.
  /// Uses a simple sigmoid-like curve or gamma correction per channel.
  img.Image _applyToneMapping(img.Image image) {
    // We can use adjustColor to manipulate contrast and brightness
    // But for "HDR" we want to affect shadows/highlights differently.
    // Since pixel-by-pixel manipulation is slow in Dart, we use lookup tables or built-in functions.
    
    // 1. Boost Shadows (Gamma Correction)
    // Gamma < 1.0 brightens dark areas
    image = img.adjustColor(
      image, 
      gamma: 0.95, // Lift shadows slightly (was 0.8)
      contrast: 1.05, // Increase contrast very slightly (was 1.1)
    );

    return image;
  }

  /// Boosts saturation and vibrance to give that "Google Camera" pop.
  img.Image _applyColorGrading(img.Image image) {
    return img.adjustColor(
      image, 
      saturation: 1.08, // 8% boost (was 20%)
      brightness: 1.02, // Very slight brightness bump (was 5%)
    );
  }
}
