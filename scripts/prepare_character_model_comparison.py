"""Compare identical dialogue/scene processing across model and reference conditions."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from vowel_chord_study import read, write, active_mask


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--small', type=Path, required=True)
    p.add_argument('--large-control', type=Path, required=True)
    p.add_argument('--large-longref', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    folders = [a.small, a.large_control, a.large_longref]
    reports = [json.loads((f/'report.json').read_text()) for f in folders]
    assert all(len(r['trials']) == 14 for r in reports)
    assert all(x['reference_sha256'] == y['reference_sha256']
               for x, y in zip(reports[0]['trials'], reports[1]['trials']))
    a.output.mkdir(parents=True, exist_ok=False)
    rows = []
    examples = []
    sr = 24000
    for index in [1, 2, 3, 5]:
        entries = [r['trials'][index-1] for r in reports]
        for entry in entries[1:]:
            for field in ['text', 'reference']:
                assert entry[field] == entries[0][field]
            assert entry['pace']['mode'] == entries[0]['pace']['mode']
            assert entry['pace']['speed_range'] == entries[0]['pace']['speed_range']
        clips = []
        gains = []
        for folder, entry in zip(folders, entries):
            rate, x = read(folder/'clips'/entry['file'])
            assert rate == sr
            clips.append(x)
            gains.append(10**(-25/20)/np.sqrt(np.mean(x[active_mask(x, sr)].astype(float)**2)))
        common = min(1., .7/max(np.max(abs(x))*g for x, g in zip(clips, gains)))
        for label, x, g in zip(['0.6B short reference', '1.7B short reference', '1.7B longer reference'], clips, gains):
            gain = float(g*common)
            y = (x*gain).astype(np.float32)
            examples.extend([y, np.zeros(round(.7*sr), dtype=np.float32)])
            rows.append(dict(index=index, label=label, text=entries[0]['text'], gain=gain,
                             input_pcm_sha256=hashlib.sha256(x.tobytes()).hexdigest()))
    result = np.concatenate(examples[:-1])
    write(a.output/'00-three-way-examples.wav', sr, result)
    _, check = read(a.output/'00-three-way-examples.wav')
    assert np.array_equal(check, result)
    (a.output/'report.json').write_text(json.dumps(dict(examples=rows, seconds=len(result)/sr,
        model_control_reference_hashes_match=all(x['reference_sha256'] == y['reference_sha256']
            for x, y in zip(reports[0]['trials'], reports[1]['trials'])),
        naturalness_and_source_similarity_verified=False), ensure_ascii=False, indent=2))
    print(f'PASS: three conditions, four scenes, {len(result)/sr:.2f}s')


if __name__ == '__main__':
    main()
