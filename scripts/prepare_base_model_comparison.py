"""Compare reference-conditioned Base models without speed or pitch processing."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from vowel_chord_study import read, write, active_mask


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--small', type=Path, required=True)
    p.add_argument('--large', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    reports = [json.loads((folder/'report.json').read_text()) for folder in (a.small, a.large)]
    for report in reports:
        assert report['all_natural_eos'] and report['all_references_unchanged']
        assert report['blocked_network_attempts'] == 0 and not report['audio_sent_to_external_service']
    assert len(reports[0]['trials']) == len(reports[1]['trials']) == 14
    a.output.mkdir(parents=True, exist_ok=False)
    (a.output/'clips').mkdir()
    reels = [[], []]
    examples = []
    rows = []
    sr = 24000
    for i, pair in enumerate(zip(*(r['trials'] for r in reports)), 1):
        before, after = pair
        for field in ('text', 'reference', 'reference_sha256', 'seed'):
            assert before[field] == after[field], field
        signals = []
        gains = []
        sources = []
        for folder, row in zip((a.small, a.large), pair):
            path = folder/row['file']
            rate, x = read(path)
            assert rate == sr and np.isfinite(x).all()
            rms = np.sqrt(np.mean(x[active_mask(x, sr)].astype(float)**2))
            gains.append(10**(-25/20)/rms)
            signals.append(x)
            sources.append(dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), frames=len(x)))
        common = min(1., 10**(-3/20)/max(np.max(abs(x))*g for x, g in zip(signals, gains)))
        for j, (x, g, label) in enumerate(zip(signals, gains, ('0.6b', '1.7b'))):
            gain = float(g*common)
            y = (x*gain).astype(np.float32)
            write(a.output/'clips'/f'{i:02d}-{label}.wav', sr, y)
            reels[j].extend([y, np.zeros(round(.35*sr), dtype=np.float32)])
            if i in (1, 3, 4, 9):
                examples.extend([y, np.zeros(round(.7*sr), dtype=np.float32)])
            sources[j]['gain'] = gain
        rows.append(dict(index=i, category=before['category'], text=before['text'],
                         reference=before['reference'], reference_sha256=before['reference_sha256'], sources=sources))
    outputs = {}
    for name, chunks in [('0.6b-unprocessed-reel', reels[0]), ('1.7b-unprocessed-reel', reels[1]),
                         ('00-0.6b-then-1.7b-examples', examples)]:
        x = np.concatenate(chunks[:-1])
        write(a.output/f'{name}.wav', sr, x)
        _, restored = read(a.output/f'{name}.wav')
        assert np.array_equal(x, restored)
        outputs[name] = dict(seconds=len(x)/sr, sha256=hashlib.sha256((a.output/f'{name}.wav').read_bytes()).hexdigest())
    (a.output/'report.json').write_text(json.dumps(dict(trials=rows, outputs=outputs,
        method='Same reference/text/seed and sampling; constant gain only, no speed/pitch effects',
        quantization='Both models 4bit; capacity and model weights differ',
        example_indices=[1, 3, 4, 9], example_order=['0.6B Base', '1.7B Base'],
        naturalness_and_identity_verified=False), ensure_ascii=False, indent=2))
    (a.output/'transcript.md').write_text('# Base比較\n\n各例は0.6B→1.7B。音量のみ調整。\n\n'+
        '\n\n'.join(f"{r['index']}. {r['category']}\n\n{r['text']}" for r in rows))
    print(json.dumps(outputs, indent=2))


if __name__ == '__main__':
    main()
