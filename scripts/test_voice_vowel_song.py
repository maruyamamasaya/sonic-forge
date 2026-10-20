"""Signal checks for the isolated sound study, independent of application tests."""
import numpy as np
from voice_vowel_song import psola, scan

for sr in [16000, 44100]:
    seconds = np.arange(sr) / sr
    source = .3 * np.sin(2 * np.pi * 220 * seconds) + .1 * np.sin(2 * np.pi * 440 * seconds)
    for target in [55, 57, 59]:
        result = psola(source, sr, 57, target, 2)
        assert len(result) == sr * 2 and np.isfinite(result).all()
        middle = result[sr:sr + 4096]
        spectrum = abs(np.fft.rfft(middle * np.hanning(len(middle)), n=32768))
        frequency = np.fft.rfftfreq(32768, 1 / sr)[np.argmax(spectrum)]
        expected = 440 * 2**((target - 69) / 12)
        assert abs(12 * np.log2(frequency / expected)) < .1, (frequency, expected)
        assert np.max(abs(result)) < 1 and np.sqrt(np.mean(result**2)) > .01
    low = psola(source, sr, 57, 45, 2)[sr // 2:sr * 3 // 2]
    correlations = []
    for hz in [110, 220]:
        lag = round(sr / hz)
        correlations.append(np.dot(low[:-lag], low[lag:]) / np.sqrt(np.dot(low[:-lag], low[:-lag]) * np.dot(low[lag:], low[lag:])))
    assert correlations[0] > .98 and correlations[0] > correlations[1] + .1
    if sr == 16000:
        assert scan(np.zeros(sr), sr) == []
        assert scan(np.random.default_rng(1).normal(0, .03, sr * 2), sr) == []
print('PASS: 16/44.1 kHz duration/pitch targets within 10 cents, finite/nonzero, silence/noise rejected')
