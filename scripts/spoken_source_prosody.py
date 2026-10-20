"""Conservative source-informed DSP study on existing short-reference speech, not model training."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.signal import butter, sosfiltfilt, find_peaks
from vowel_chord_study import read, write, active_mask
from vowel_vibrato_study import modulate, known_tone_check


def describe(x, sr):
    hop = round(.02*sr)
    width = round(.04*sr)
    frames = np.lib.stride_tricks.sliding_window_view(x, width)[::hop].astype(float)
    rms = np.sqrt(np.mean(frames**2, axis=1))
    active = rms > max(.0002, rms.max()*.08)
    centered = frames-frames.mean(axis=1, keepdims=True)
    ac = np.fft.irfft(abs(np.fft.rfft(centered, n=2048))**2, n=2048)
    lags = np.arange(round(sr/450), round(sr/90))
    score = ac[:, lags]/np.maximum(ac[:, :1], 1e-12)
    best = score.argmax(axis=1)
    quality = score[np.arange(len(best)), best]
    voiced = active & (quality>.6)
    pitch = 69+12*np.log2(sr/lags[best]/440)
    assert voiced.sum() > 3
    median = np.median(pitch[voiced])
    # Reject large likely octave/subharmonic jumps; no claim of phonetic alignment.
    voiced &= abs(pitch-median)<7
    smooth = gaussian_filter1d(np.interp(np.arange(len(pitch)), np.flatnonzero(voiced), pitch[voiced]), 3)
    env = gaussian_filter1d(rms, 1)
    peaks, _ = find_peaks(env, distance=5, prominence=max(.0002, env.max()*.10))
    high = sosfiltfilt(butter(2, 3500, 'highpass', fs=sr, output='sos'), x)
    airy = np.sqrt(np.mean(high.astype(float)**2)/max(np.mean(x.astype(float)**2), 1e-12))
    db = 20*np.log10(np.maximum(env, 1e-5))
    return dict(peak_rate=len(peaks)/(len(x)/sr), pitch_median=float(median),
                pitch_curve=smooth, envelope_db=db, airy_ratio=float(airy),
                envelope_iqr=float(np.percentile(db[active], 75)-np.percentile(db[active], 25)))


def summary(d):
    return {k:v for k,v in d.items() if k not in ('pitch_curve', 'envelope_db')}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--previous', type=Path, required=True)
    p.add_argument('--references', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    previous = json.loads((a.previous/'report.json').read_text())
    a.output.mkdir(parents=True, exist_ok=False)
    (a.output/'work').mkdir(); (a.output/'clips').mkdir()
    sources = {}; rows = []; old_parts = []; new_parts = []; pairs = []
    for i, row in enumerate(previous['trials'], 1):
        path = a.previous/'clips'/row['file']; ref = a.references/(row['reference']+'.wav')
        assert hashlib.sha256(ref.read_bytes()).hexdigest() == row['reference_sha256']
        sources[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        sources[str(ref)] = hashlib.sha256(ref.read_bytes()).hexdigest()
        sr, x = read(path); rate, source = read(ref); assert sr == rate == 24000
        original = describe(x, sr); target = describe(source, sr)
        # Envelope peak rate is only a rhythm proxy, not measured syllables per second.
        speed = float(np.clip(1+.20*(target['peak_rate']/max(original['peak_rate'], .1)-1), .96, 1.06))
        raw = a.output/'work'/f'{i:02d}-in.wav'; paced = a.output/'work'/f'{i:02d}-paced.wav'
        write(raw, sr, x)
        subprocess.run(['rubberband', '-q', '-3', '-F', '-t', str(1/speed), str(raw), str(paced)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        _, y = read(paced); assert abs(len(y)-round(len(x)/speed))<=2
        u = np.linspace(0, 1, len(y)); gate = np.sin(np.pi*u)**2
        pc = target['pitch_curve']-np.median(target['pitch_curve'])
        correction = np.interp(u, np.linspace(0, 1, len(pc)), pc)*8
        correction = gaussian_filter1d(np.clip(correction, -18, 18)*gate, sr*.09)
        rates = np.exp2(correction/1200); rates -= rates.mean()-1
        cents = 1200*np.log2(rates); y, displacement = modulate(y, sr, cents)
        assert abs(displacement[-1])<1e-6 and np.max(abs(cents))<37
        # Match a small fraction of source dynamics; preserve lexical timing and articulation.
        ec = target['envelope_db']-np.median(target['envelope_db'])
        dynamics = np.clip(np.interp(u, np.linspace(0, 1, len(ec)), ec)*.08, -.8, .8)*gate
        y *= 10**(dynamics/20)
        # Slightly balance existing high-frequency air/consonants; no copied speech or synthetic breath.
        air_db = float(np.clip(20*np.log10(max(target['airy_ratio'], .001)/max(original['airy_ratio'], .001))*.15, -.6, .6))
        high = sosfiltfilt(butter(2, 3500, 'highpass', fs=sr, output='sos'), y)
        y += high*(10**(air_db/20)-1)
        signals = [x, y]; gains = [10**(-25/20)/np.sqrt(np.mean(z[active_mask(z, sr)].astype(float)**2)) for z in signals]
        common = min(1., .7/max(np.max(abs(z))*g for z,g in zip(signals, gains)))
        xx, yy = [(z*float(g*common)).astype(np.float32) for z,g in zip(signals, gains)]
        write(a.output/'clips'/row['file'], sr, yy)
        old_parts.extend([xx, np.zeros(8400, dtype=np.float32)]); new_parts.extend([yy, np.zeros(8400, dtype=np.float32)])
        if i in [1, 2, 3, 5]:
            for z in [xx, yy]: pairs.extend([z, np.zeros(16800, dtype=np.float32)])
        rows.append(dict(index=i, text=row['text'], reference=row['reference'], source=summary(target),
                         before=summary(original), speed_factor=speed, max_pitch_cents=float(np.max(abs(cents))),
                         dynamics_peak_db=float(np.max(abs(dynamics))), air_band_db=air_db,
                         output_frames=len(yy), previous_gain=float(gains[0]*common)))
    outputs = {}
    for name, parts in [('source-informed-demo', new_parts), ('previous-shortref-control', old_parts), ('00-before-then-source-informed', pairs)]:
        z = np.concatenate(parts[:-1]); write(a.output/(name+'.wav'), sr, z)
        _, check = read(a.output/(name+'.wav')); assert np.array_equal(z, check)
        outputs[name] = dict(seconds=len(z)/sr, sha256=hashlib.sha256((a.output/(name+'.wav')).read_bytes()).hexdigest())
    assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in sources.items())
    shutil.copyfile(a.previous/'transcript.md', a.output/'original-transcript.md')
    (a.output/'report.json').write_text(json.dumps(dict(trials=rows, outputs=outputs, inputs=sources,
        source_unchanged=True, known_pitch_test=known_tone_check(24000),
        method='Existing short-reference 1.7B speech; conservative source-statistics DSP, no new generation/training',
        breath_isolation=False, syllabic_rate_measured=False, perceptual_improvement_verified=False), ensure_ascii=False, indent=2))
    print(json.dumps(outputs, indent=2))


if __name__ == '__main__':
    main()
