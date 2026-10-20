"""Compare approved short vowels with new, reference-conditioned longer vowels.
No new inference; crop first utterance and level match only. Raw outputs retained.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import numpy as np
from scipy.io import wavfile
from prepare_five_vowel_comparison import first_sound


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--long-input', type=Path, required=True)
    p.add_argument('--short-input', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    if args.output.exists():
        raise SystemExit('Use a fresh output directory')
    raw_report = json.loads((args.long_input / 'report.json').read_text())
    short_report = json.loads((args.short_input / 'report.json').read_text())
    if raw_report['reference_sha256'] != short_report['reference_sha256'] or raw_report['reference_seconds'] != 3:
        raise ValueError('Expected exactly the same three-second reference')
    if not raw_report['reference_unchanged'] or raw_report['blocked_network_attempts']:
        raise ValueError('Reference/network invariant failed')
    args.output.mkdir(parents=True)
    sequences, entries = [], []
    for label, short_file, long_file in [('a', '01-a.wav', '01-generated-aa.wav'), ('u', '03-u.wav', '02-generated-uu.wav')]:
        sr, short = wavfile.read(args.short_input / short_file)
        long_sr, raw = wavfile.read(args.long_input / long_file)
        if sr != long_sr or sr != 24000:
            raise ValueError('Unexpected sample rate')
        long, start, end, rms = first_sound(raw, sr)
        if not len(short) * 1.4 <= len(long) <= sr * 2:
            raise ValueError('New sound must be measurably longer and <=2 seconds')
        gain = 10**(-24/20) / rms
        long = (long * gain).astype(np.float32)
        if not np.isfinite(long).all() or not .0001 < np.max(abs(long)) < 1:
            raise ValueError('Invalid long sound')
        short_out = args.output / (label + '-short.wav')
        shutil.copyfile(args.short_input / short_file, short_out)
        assert short_out.read_bytes() == (args.short_input / short_file).read_bytes()
        long_out = args.output / (label + '-long.wav')
        wavfile.write(long_out, sr, long)
        restored_sr, restored = wavfile.read(long_out)
        assert restored_sr == sr and np.array_equal(long, restored)
        gap = np.zeros(round(sr * .65), dtype=np.float32)
        pair = np.concatenate([short, gap, long])
        wavfile.write(args.output / (label + '-short-then-long.wav'), sr, pair)
        sequences.extend([short, gap, long, gap])
        trial = next(t for t in raw_report['trials'] if t['file'] == long_file)
        entries.append(dict(vowel=label, short_seconds=len(short)/sr, long_seconds=len(long)/sr,
            short_file=short_out.name, long_file=long_out.name, start_sample=start, end_sample=end,
            raw_generation_file=long_file, raw_generation_sha256=hashlib.sha256((args.long_input/long_file).read_bytes()).hexdigest(),
            raw_limit_reached=trial['limit_reached'], gain_db=20*np.log10(gain), active_rms_dbfs=-24,
            peak_dbfs=20*np.log10(float(np.max(abs(long)))), short_bytes_unchanged=True))
    combined = np.concatenate(sequences[:-1])
    wavfile.write(args.output / '00-short-long-a-u.wav', 24000, combined)
    rate, back = wavfile.read(args.output / '00-short-long-a-u.wav')
    assert rate == 24000 and np.array_equal(back, combined)
    report = dict(reference_sha256=raw_report['reference_sha256'], reference_seconds=3,
        method='New AI-generated long-vowel instruction; first utterance crop, RMS gain only; no looping, time stretch, pitch shift, EQ or reverb',
        order=['short a', 'long a', 'short u', 'long u'], gap_seconds=.65,
        sequence_seconds=len(combined)/24000, trials=entries, quality_verified_by_listener=False)
    (args.output/'report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
