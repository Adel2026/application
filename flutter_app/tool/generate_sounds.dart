import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  final rawDir = Directory('android/app/src/main/res/raw');
  final assetsDir = Directory('assets/audio');
  if (!rawDir.existsSync()) rawDir.createSync(recursive: true);
  if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);

  print('Generating audio tones...');

  // 1. School Bell: Authentic double-ding brass chime repeating 3 times
  final schoolBell = generateSchoolBell(sampleRate: 44100, durationSec: 3.5);
  saveWav(File('${rawDir.path}/school_bell.wav'), schoolBell, 44100);
  saveWav(File('${assetsDir.path}/school_bell.wav'), schoolBell, 44100);

  // 2. Alarm Clock: Energetic digital alarm clock beep pattern
  final alarmClock = generateAlarmClock(sampleRate: 44100, durationSec: 3.2);
  saveWav(File('${rawDir.path}/alarm_clock.wav'), alarmClock, 44100);
  saveWav(File('${assetsDir.path}/alarm_clock.wav'), alarmClock, 44100);

  // 3. Digital Beep: Pleasant modern melodic chime (C-E-G-C)
  final digitalBeep = generateDigitalBeep(sampleRate: 44100, durationSec: 2.5);
  saveWav(File('${rawDir.path}/digital_beep.wav'), digitalBeep, 44100);
  saveWav(File('${assetsDir.path}/digital_beep.wav'), digitalBeep, 44100);

  // 4. Gentle Chime: Warm acoustic bell with smooth decay
  final gentleChime = generateGentleChime(sampleRate: 44100, durationSec: 3.0);
  saveWav(File('${rawDir.path}/gentle_chime.wav'), gentleChime, 44100);
  saveWav(File('${assetsDir.path}/gentle_chime.wav'), gentleChime, 44100);

  print('Audio tones generated successfully!');
}

Float64List generateSchoolBell({required int sampleRate, required double durationSec}) {
  final totalSamples = (sampleRate * durationSec).toInt();
  final buffer = Float64List(totalSamples);

  // Strike pattern: Ding at 0.0s, Dong at 0.5s, Ding at 1.2s, Dong at 1.7s, Ding at 2.4s
  final strikes = [
    (0.0, 880.0, 0.9),   // A5
    (0.45, 659.25, 0.95), // E5
    (1.1, 880.0, 0.9),
    (1.55, 659.25, 0.95),
    (2.2, 880.0, 0.9),
    (2.65, 523.25, 1.0), // C5
  ];

  for (final (startSec, freq, gain) in strikes) {
    final startIdx = (startSec * sampleRate).toInt();
    final strikeDuration = 0.7; // seconds decay
    final strikeSamples = (strikeDuration * sampleRate).toInt();

    for (int i = 0; i < strikeSamples && (startIdx + i) < totalSamples; i++) {
      final t = i / sampleRate;
      final decay = exp(-4.2 * t);
      // Harmonic bell overtone mixture: Fundamental + 2.76x + 5.4x + strike transient
      final sample = sin(2 * pi * freq * t) * 0.6 +
          sin(2 * pi * freq * 2.76 * t) * 0.25 * exp(-6.0 * t) +
          sin(2 * pi * freq * 5.40 * t) * 0.15 * exp(-9.0 * t);
      buffer[startIdx + i] += sample * decay * gain;
    }
  }

  // Normalize
  normalize(buffer);
  return buffer;
}

Float64List generateAlarmClock({required int sampleRate, required double durationSec}) {
  final totalSamples = (sampleRate * durationSec).toInt();
  final buffer = Float64List(totalSamples);

  // Standard alarm: 3 bursts of beeps, repeated
  // Each burst has 3 beeps of 80ms on, 50ms off at 1046 Hz (High C)
  final burstTimes = [0.0, 0.6, 1.3, 1.9, 2.6];
  for (final burstStart in burstTimes) {
    for (int b = 0; b < 3; b++) {
      final beepStartSec = burstStart + (b * 0.12);
      final startIdx = (beepStartSec * sampleRate).toInt();
      final beepSamples = (0.07 * sampleRate).toInt();

      for (int i = 0; i < beepSamples && (startIdx + i) < totalSamples; i++) {
        final t = i / sampleRate;
        final env = sin(pi * (i / beepSamples)); // smooth attack and release
        final sample = (sin(2 * pi * 1046.5 * t) * 0.8 + sin(2 * pi * 2093.0 * t) * 0.2);
        buffer[startIdx + i] += sample * env * 0.85;
      }
    }
  }

  normalize(buffer);
  return buffer;
}

Float64List generateDigitalBeep({required int sampleRate, required double durationSec}) {
  final totalSamples = (sampleRate * durationSec).toInt();
  final buffer = Float64List(totalSamples);

  // Arpeggio: C5 (523Hz), E5 (659Hz), G5 (784Hz), C6 (1046Hz) repeated twice
  final cycles = [0.0, 1.2];
  final notes = [523.25, 659.25, 783.99, 1046.50];

  for (final cycleStart in cycles) {
    for (int n = 0; n < notes.length; n++) {
      final noteStartSec = cycleStart + (n * 0.14);
      final startIdx = (noteStartSec * sampleRate).toInt();
      final noteSamples = (0.35 * sampleRate).toInt();

      for (int i = 0; i < noteSamples && (startIdx + i) < totalSamples; i++) {
        final t = i / sampleRate;
        final decay = exp(-5.0 * t);
        final sample = sin(2 * pi * notes[n] * t) * 0.7 +
            sin(2 * pi * notes[n] * 2.0 * t) * 0.2 +
            sin(2 * pi * notes[n] * 3.0 * t) * 0.1;
        buffer[startIdx + i] += sample * decay * 0.85;
      }
    }
  }

  normalize(buffer);
  return buffer;
}

Float64List generateGentleChime({required int sampleRate, required double durationSec}) {
  final totalSamples = (sampleRate * durationSec).toInt();
  final buffer = Float64List(totalSamples);

  // Warm marimba/kalimba notes: F#5 (739Hz), A5 (880Hz), C#6 (1108Hz)
  final chords = [
    (0.0, [587.33, 880.0, 1174.66]), // D major
    (1.2, [659.25, 987.77, 1318.51]), // E minor
  ];

  for (final (startSec, freqs) in chords) {
    final startIdx = (startSec * sampleRate).toInt();
    final noteSamples = (1.1 * sampleRate).toInt();

    for (int i = 0; i < noteSamples && (startIdx + i) < totalSamples; i++) {
      final t = i / sampleRate;
      final decay = exp(-3.2 * t);
      double sample = 0;
      for (final f in freqs) {
        sample += sin(2 * pi * f * t) * (1.0 / freqs.length);
      }
      buffer[startIdx + i] += sample * decay * 0.9;
    }
  }

  normalize(buffer);
  return buffer;
}

void normalize(Float64List buffer) {
  double maxVal = 0;
  for (final v in buffer) {
    if (v.abs() > maxVal) maxVal = v.abs();
  }
  if (maxVal > 0) {
    final scale = 0.95 / maxVal;
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] *= scale;
    }
  }
}

void saveWav(File file, Float64List samples, int sampleRate) {
  final numSamples = samples.length;
  final subchunk2Size = numSamples * 2; // 16-bit = 2 bytes per sample
  final chunkSize = 36 + subchunk2Size;

  final bytes = ByteData(44 + subchunk2Size);

  // RIFF header
  bytes.setUint8(0, 0x52); // 'R'
  bytes.setUint8(1, 0x49); // 'I'
  bytes.setUint8(2, 0x46); // 'F'
  bytes.setUint8(3, 0x46); // 'F'
  bytes.setUint32(4, chunkSize, Endian.little);
  bytes.setUint8(8, 0x57);  // 'W'
  bytes.setUint8(9, 0x41);  // 'A'
  bytes.setUint8(10, 0x56); // 'V'
  bytes.setUint8(11, 0x45); // 'E'

  // fmt chunk
  bytes.setUint8(12, 0x66); // 'f'
  bytes.setUint8(13, 0x6D); // 'm'
  bytes.setUint8(14, 0x74); // 't'
  bytes.setUint8(15, 0x20); // ' '
  bytes.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
  bytes.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
  bytes.setUint16(22, 1, Endian.little);  // NumChannels (1 = Mono)
  bytes.setUint32(24, sampleRate, Endian.little); // SampleRate
  bytes.setUint32(28, sampleRate * 2, Endian.little); // ByteRate (SampleRate * NumChannels * BitsPerSample/8)
  bytes.setUint16(32, 2, Endian.little);  // BlockAlign (NumChannels * BitsPerSample/8)
  bytes.setUint16(34, 16, Endian.little); // BitsPerSample

  // data chunk
  bytes.setUint8(36, 0x64); // 'd'
  bytes.setUint8(37, 0x61); // 'a'
  bytes.setUint8(38, 0x74); // 't'
  bytes.setUint8(39, 0x61); // 'a'
  bytes.setUint32(40, subchunk2Size, Endian.little);

  // PCM data
  int offset = 44;
  for (int i = 0; i < numSamples; i++) {
    final s = (samples[i] * 32767).clamp(-32768, 32767).toInt();
    bytes.setInt16(offset, s, Endian.little);
    offset += 2;
  }

  file.writeAsBytesSync(bytes.buffer.asUint8List());
}
