/**
 * A majority of this code was written by AI.
 * 
 * Script Name: camera_enums.dart
 * Description: 
 *   Defines core enumerations and their associated labels for camera settings,
 *   including exposure, ISO, shutter speed, white balance, and file formats.
 */

enum FlashSetting { off, on, auto, torch }

// Exposure / metering
enum ExposureMode { auto, manual, shutterPriority, aperturePriority, program }

enum MeteringMode { matrix, centerWeighted, spot }

// Focus
enum FocusMode { single, continuous, manual }

// White balance
enum WhiteBalance {
  auto,
  daylight,
  cloudy,
  shade,
  tungsten,
  fluorescent,
  flash,
  custom,
  kelvin,
}

// ISO
enum ISO { iso100, iso200, iso400, iso800, iso1600, iso3200, iso6400, iso12800 }

// Shutter
enum ShutterSpeed {
  s1_4000,
  s1_2000,
  s1_1000,
  s1_500,
  s1_250,
  s1_125,
  s1_60,
  s1_30,
  s1_15,
  s1_8,
  s1_4,
  s1_2,
  s1,
  s2,
  s4,
  s8,
}

// Stabilization
enum Stabilization { off, standard, active }

// Drive
enum DriveMode {
  single,
  continuousHigh,
  continuousLow,
  timer2s,
  timer10s,
  bracketing,
}

// File format
enum FileFormat { jpeg, heif, raw, rawJpeg }

// Photo sizes
enum PhotoResolution { mp12, mp24, mp48 }

// Video
enum VideoResolution { fhd1080, uhd4k, uhd8k }

enum VideoFramerate { fps24, fps30, fps60, fps120 }

// Labels
extension IsoLabel on ISO {
  String get label => switch (this) {
    ISO.iso100 => '100',
    ISO.iso200 => '200',
    ISO.iso400 => '400',
    ISO.iso800 => '800',
    ISO.iso1600 => '1600',
    ISO.iso3200 => '3200',
    ISO.iso6400 => '6400',
    ISO.iso12800 => '12800',
  };
}

extension ShutterLabel on ShutterSpeed {
  String get label => switch (this) {
    ShutterSpeed.s1_4000 => '1/4000',
    ShutterSpeed.s1_2000 => '1/2000',
    ShutterSpeed.s1_1000 => '1/1000',
    ShutterSpeed.s1_500 => '1/500',
    ShutterSpeed.s1_250 => '1/250',
    ShutterSpeed.s1_125 => '1/125',
    ShutterSpeed.s1_60 => '1/60',
    ShutterSpeed.s1_30 => '1/30',
    ShutterSpeed.s1_15 => '1/15',
    ShutterSpeed.s1_8 => '1/8',
    ShutterSpeed.s1_4 => '1/4',
    ShutterSpeed.s1_2 => '1/2',
    ShutterSpeed.s1 => '1"',
    ShutterSpeed.s2 => '2"',
    ShutterSpeed.s4 => '4"',
    ShutterSpeed.s8 => '8"',
  };
}

extension PhotoResLabel on PhotoResolution {
  String get label => switch (this) {
    PhotoResolution.mp12 => '12 MP',
    PhotoResolution.mp24 => '24 MP',
    PhotoResolution.mp48 => '48 MP',
  };
}

extension VideoResLabel on VideoResolution {
  String get label => switch (this) {
    VideoResolution.fhd1080 => '1080p (FHD)',
    VideoResolution.uhd4k => '4K (UHD)',
    VideoResolution.uhd8k => '8K (UHD)',
  };
}

extension FpsLabel on VideoFramerate {
  String get label => switch (this) {
    VideoFramerate.fps24 => '24 fps',
    VideoFramerate.fps30 => '30 fps',
    VideoFramerate.fps60 => '60 fps',
    VideoFramerate.fps120 => '120 fps',
  };
}
