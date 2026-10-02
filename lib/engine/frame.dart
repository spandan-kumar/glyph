import 'dart:typed_data';

/// A width×height RGB image in row-major order, origin top-left.
class Frame {
  Frame(this.width, this.height) : rgb = Uint8List(width * height * 3);

  final int width;
  final int height;
  final Uint8List rgb;

  int get pixelCount => width * height;

  void set(int x, int y, int color) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final i = (y * width + x) * 3;
    rgb[i] = (color >> 16) & 0xFF;
    rgb[i + 1] = (color >> 8) & 0xFF;
    rgb[i + 2] = color & 0xFF;
  }

  int get(int x, int y) {
    final i = (y * width + x) * 3;
    return (rgb[i] << 16) | (rgb[i + 1] << 8) | rgb[i + 2];
  }

  void fill(int color) {
    for (var i = 0; i < pixelCount; i++) {
      rgb[i * 3] = (color >> 16) & 0xFF;
      rgb[i * 3 + 1] = (color >> 8) & 0xFF;
      rgb[i * 3 + 2] = color & 0xFF;
    }
  }

  /// Multiplies every channel by [factor] (0..1); used for trails.
  void fade(double factor) {
    for (var i = 0; i < rgb.length; i++) {
      rgb[i] = (rgb[i] * factor).toInt();
    }
  }

  Frame copy() => Frame(width, height)..rgb.setAll(0, rgb);
}

int rgb(int r, int g, int b) =>
    ((r.clamp(0, 255)) << 16) | ((g.clamp(0, 255)) << 8) | b.clamp(0, 255);

int scaleColor(int c, double f) => rgb(
      (((c >> 16) & 0xFF) * f).toInt(),
      (((c >> 8) & 0xFF) * f).toInt(),
      ((c & 0xFF) * f).toInt(),
    );

int addColors(int a, int b) => rgb(
      ((a >> 16) & 0xFF) + ((b >> 16) & 0xFF),
      ((a >> 8) & 0xFF) + ((b >> 8) & 0xFF),
      (a & 0xFF) + (b & 0xFF),
    );
