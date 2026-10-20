"""Select first sound from each local vowel generation and level-match auditions.
No new synthesis, time/pitch editing, fading, looping, or application changes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.io import wavfile


def first_sound(x, sr):
    hop = max(1, round(sr * .01))
    energy = np.array([np.sqrt(np.mean(x[i:i + hop]**2)) for i in range(0, len(x), hop)])
    threshold = max(.0002, float(energy.max()) * .04)
    active = np.flatnonzero(energy > threshold)
    if not len(active):
        raise ValueError('No non-silent first sound')
    first, last = int(active[0]), int(active[0])
    for i in active[1:]:
        if i - last > 10:  # Do not include a later separate sound after >=100ms silence.
            break
        last = int(i)
    start, end = max(0, first * hop - round(sr * .03)), min(len(x), (last + 1) * hop + round(sr * .1))
    segment = x[start:end].copy()
    voiced = np.concatenate([x[i * hop:min(len(x), (i + 1) * hop)] for i in active if first <= i <= last])
    rms = float(np.sqrt(np.mean(voiced.astype(np.float64)**2)))
    return segment, start, end, rms


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--approved-u', type=Path, required=True)
    args = p.parse_args()
    if args.output.exists():
        raise SystemExit('Use a fresh output directory')
    report = json.loads((args.input / 'report.json').read_text())
    if [t['text'] for t in report['trials']] != ['あ。', 'い。', 'う。', 'え。', 'お。']:
        raise ValueError('Expected five ordered vowel prompts')
    if not report['reference_unchanged'] or report['reference_seconds'] != 3:
        raise ValueError('Expected unchanged three-second reference')
    approved_sr, approved = wavfile.read(args.approved_u)
    u_sr, u = wavfile.read(args.input / '03-u.wav')
    assert approved_sr == u_sr and np.array_equal(approved, u)
    args.output.mkdir(parents=True)
    entries = []
    for trial in report['trials']:
        source = args.input / trial['file']
        sr, x = wavfile.read(source)
        if sr != 24000 or x.ndim != 1 or not np.isfinite(x).all():
            raise ValueError('Unexpected generation format')
        clip, start, end, rms = first_sound(x, sr)
        if not .12 <= len(clip) / sr <= 2:
            raise ValueError('First sound not short enough for this comparison')
        gain = 10**(-24 / 20) / rms
        entries.append((trial, source, sr, clip, start, end, rms, gain))
    # Shared attenuation only if any matched preview would exceed -3 dBFS.
    max_peak = max(float(np.max(abs(e[3]))) * e[7] for e in entries)
    shared = min(1, 10**(-3 / 20) / max_peak)
    sequence, summaries, position = [], [], 0
    for trial, source, sr, clip, start, end, rms, gain in entries:
        gain *= shared
        y = (clip * gain).astype(np.float32)
        assert np.isfinite(y).all() and 0 < np.max(abs(y)) < 1
        output = args.output / trial['file']
        wavfile.write(output, sr, y)
        actual_sr, back = wavfile.read(output)
        assert actual_sr == sr and np.array_equal(y, back)
        silence = np.zeros(round(sr * .65), dtype=np.float32)
        sequence.extend([y, silence])
        summaries.append(dict(file=output.name, text=trial['text'], source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
            raw_limit_reached=trial['limit_reached'], source_seconds=trial['seconds'],
            start_sample=start, end_sample=end, seconds=len(y) / sr, sequence_start_seconds=position / sr,
            gain_db=20 * np.log10(gain), active_rms_dbfs=20 * np.log10(rms * gain),
            peak_dbfs=20 * np.log10(float(np.max(abs(y))))))
        position += len(y) + len(silence)
    combined = np.concatenate(sequence[:-1])  # No trailing gap after the last vowel.
    wavfile.write(args.output / '00-aiueo-comparison.wav', 24000, combined)
    rate, restored = wavfile.read(args.output / '00-aiueo-comparison.wav')
    assert rate == 24000 and np.array_equal(combined, restored)
    summary = dict(reference_sha256=report['reference_sha256'], reference_seconds=3,
        approved_u_raw_pcm_identical=True, target_active_rms_dbfs=-24, shared_attenuation_db=20*np.log10(shared),
        processing='First sound only; trim surrounding silence/later sounds; linear gain; concatenate with 0.65s silence. No pitch/time/loop/EQ/reverb processing.',
        sequence_seconds=len(combined)/24000, vowels=summaries)
    (args.output / 'report.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
