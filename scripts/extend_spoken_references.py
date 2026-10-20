"""Retain original PCM around approved source-reference candidates for a longer-reference trial."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from vowel_chord_study import read, write, active_mask


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--references', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    metadata = json.loads((a.references/'report.json').read_text())
    source = a.references/'source-decoded.wav'
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    sr, x = read(source)
    a.output.mkdir(parents=True, exist_ok=False)
    rows = []
    previews = []
    for ref in metadata['references']:
        # Keep bright candidates unchanged, unused by the low-register prompts.
        seconds = 3.2 if ref['style'] == 'bright' else 6.4
        start = max(0., min(ref['start_seconds']-(seconds-3.2)/2, len(x)/sr-seconds))
        first = round(start*sr)
        clip = x[first:first+round(seconds*sr)]
        if ref['style'] != 'bright':
            _, old = read(a.references/ref['file'])
            offset = round(ref['start_seconds']*sr)-first
            assert np.array_equal(clip[offset:offset+len(old)], old)
        write(a.output/ref['file'], sr, clip)
        _, check = read(a.output/ref['file'])
        assert np.array_equal(clip, check)
        gain = float(min(10**(-25/20)/np.sqrt(np.mean(clip[active_mask(clip, sr)].astype(float)**2)), .7/np.max(abs(clip))))
        if ref['style'] != 'bright':
            previews.extend([(clip*gain).astype(np.float32), np.zeros(round(.5*sr), dtype=np.float32)])
        rows.append(dict(file=ref['file'], start_seconds=start, seconds=seconds,
                         original_candidate_sha256=ref['sha256'],
                         sha256=hashlib.sha256((a.output/ref['file']).read_bytes()).hexdigest()))
    write(a.output/'00-longer-low-calm-references.wav', sr, np.concatenate(previews[:-1]))
    assert digest == hashlib.sha256(source.read_bytes()).hexdigest()
    (a.output/'report.json').write_text(json.dumps(dict(references=rows, source_decoded_sha256=digest,
        source_unchanged=True, original_source_sha256=metadata['source_sha256'],
        method='Extend low/calm reference windows symmetrically; unchanged source PCM; no transcript invented',
        closeness_improvement_verified=False), indent=2))


if __name__ == '__main__':
    main()
