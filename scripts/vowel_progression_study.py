"""Local I-vi-IV-V vowel study; reuse approved voices, no AI generation."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.signal import fftconvolve
from vowel_chord_study import read, write, shift, active_mask


def rms(x):
    return float(np.sqrt(np.mean(np.asarray(x, dtype=np.float64)**2)))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    work = args.output/'layers'; work.mkdir()
    sr = 24000
    # Closely voiced I-vi-IV-V, relative to the unchanged middle source voice.
    voicings = [(-4, 0, 3), (-4, 0, 5), (-4, 1, 5), (-2, 2, 5)]
    # Deterministic diffuse room impulse: 22 ms predelay, RT60 0.9 s.
    rng = np.random.default_rng(21)
    t = np.arange(round(sr*1.2))/sr
    ir = rng.standard_normal(len(t))*np.exp(-np.log(1000)*t/.9)
    ir = np.convolve(ir, [.25, .5, .25], mode='same')
    ir /= np.sqrt(np.sum(ir**2))
    ir = np.pad(ir, (round(.022*sr), 0))
    write(work/'room-impulse.wav', sr, ir.astype(np.float32))
    reports = []
    pairs = []
    for vowel in ['a', 'u']:
        source = args.input/(vowel+'-long.wav')
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        rate, x = read(source)
        assert rate == sr and len(x) < round(1.1*sr)
        mask = active_mask(x, sr)
        target = rms(x[mask])
        layers = {}
        for semitones in sorted(set(sum((list(v) for v in voicings), []))):
            y = x.copy() if semitones == 0 else shift(x, sr, semitones, work, f'{vowel}-{semitones}')
            layers[semitones] = y * (target/rms(y[mask]))
        dry = np.zeros(round(6*sr), dtype=np.float32)
        for i, voicing in enumerate(voicings):
            chord = np.mean([layers[s] for s in voicing], axis=0)
            chord *= target/rms(chord[mask])
            start = round(i*1.1*sr)
            dry[start:start+len(chord)] += chord
        reverberation = fftconvolve(dry, ir)[:len(dry)]
        wet = (dry + .12*reverberation).astype(np.float32)
        # Same total duration and integrated RMS, including the room tail.
        wet_gain = rms(dry)/rms(wet)
        wet = (wet*wet_gain).astype(np.float32)
        assert abs(20*np.log10(rms(wet)/rms(dry))) < .001
        assert np.max(abs(wet[-round(.2*sr):])) < 1e-5
        for name, data in [('dry', dry), ('reverb', wet)]:
            assert np.max(abs(data)) < 10**(-3/20)
            write(args.output/f'{vowel}-{name}.wav', sr, data)
        pair = np.concatenate([dry, np.zeros(round(.8*sr), dtype=np.float32), wet])
        write(args.output/f'{vowel}-dry-then-reverb.wav', sr, pair)
        pairs.append(pair)
        assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
        reports.append(dict(vowel=vowel, source_sha256=digest, source_unchanged=True,
            seconds=len(dry)/sr, dry_rms_dbfs=20*np.log10(rms(dry)),
            wet_rms_dbfs=20*np.log10(rms(wet)), wet_gain_db=20*np.log10(wet_gain),
            dry_peak=float(np.max(abs(dry))), wet_peak=float(np.max(abs(wet)))))
    combined = np.concatenate([pairs[0], np.zeros(sr, dtype=np.float32), pairs[1]])
    write(args.output/'00-a-u-dry-reverb.wav', sr, combined)
    report = dict(progression=['I','vi','IV','V'], relative_semitones=voicings,
        onset_spacing_seconds=1.1, formant_preservation=True, time_stretch=False,
        loops=False, absolute_tuning=False, new_ai_generation=False,
        reverb=dict(rt60_seconds=.9, predelay_seconds=.022, wet_amplitude=.12, seed=21),
        order=['a dry','a reverb','u dry','u reverb'], trials=reports,
        listening_quality_verified=False)
    (args.output/'report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
