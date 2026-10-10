/// Bounds preparation on the phone, independently of device storage.
const maxBakeFrames = 12000;
const maxBakePixels = 8 * 1024 * 1024;

class BakeLimitException implements Exception {
  const BakeLimitException();

  String get message => 'This animation is too large to prepare on your phone. '
      'Show it live instead, or reduce its size.';

  @override
  String toString() => message;
}

void checkBakeSize(int width, int height, int frames) {
  if (width <= 0 || height <= 0 || frames <= 0) {
    throw ArgumentError('Animation dimensions and frame count must be positive');
  }
  // Encoding also allocates corrected frames, colour indices and sort buffers.
  if (frames > maxBakeFrames || width * height * frames > maxBakePixels) {
    throw const BakeLimitException();
  }
}
