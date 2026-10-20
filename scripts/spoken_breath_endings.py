"""Source-informed phrase spacing and gentle terminal release; no isolated breath splicing."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from vowel_chord_study import read, write, active_mask


def runs(mask):
    edges = np.diff(np.r_[False, mask, False].astype(int))
    return list(zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)))


def source_release(x, sr):
    hop = round(.01*sr)
    env = np.array([np.sqrt(np.mean(x[i:i+hop].astype(float)**2)) for i in range(0, len(x), hop)])
    active = env > max(.0003, env.max()*.10)
    gaps = [(b-a)*.01 for a,b in runs(~active) if a>0 and b<len(env) and .12<=(b-a)*.01<=.8]
    ratios = []
    for a,b in runs(active):
        if b-a>=16 and b+8<len(env) and not active[b:b+8].any():
            ratios.append(float(np.mean(env[b-4:b])/max(np.mean(env[b-12:b-4]), 1e-8)))
    # Weak release even when candidate endings cannot be reliably estimated.
    release = float(np.clip(np.median(ratios) if ratios else .95, .82, .97))
    return dict(gap_seconds=float(np.clip(np.median(gaps) if gaps else .35, .24, .48)),
                ending_gain=release, valid_gap_candidates=len(gaps), valid_decay_candidates=len(ratios),
                isolated_breath=False, semantic_boundaries_verified=False)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--references', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    report = json.loads((a.input/'report.json').read_text())
    a.output.mkdir(parents=True, exist_ok=False); (a.output/'clips').mkdir()
    old = []; new = []; pairs = []; rows = []; input_hashes = {}; position = 0
    text = '# 新しい会話・息と語尾の試作\n\n'
    for tr in report['trials']:
        i = tr['index']; f = a.input/'clips'/f'{i:02d}-spoken.wav'
        ref = a.references/(tr['reference']+'.wav')
        for path in [f, ref]: input_hashes[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        sr,x = read(f); rate,source = read(ref); assert rate == sr == 24000
        settings = source_release(source, sr)
        mask = active_mask(x, sr); last = int(np.flatnonzero(mask)[-1])+1
        duration = round(.16*sr); first = max(0, last-duration)
        gain = np.ones(len(x)); u = np.linspace(0, 1, last-first)
        gain[first:last] = 1-(1-settings['ending_gain'])*(.5-.5*np.cos(np.pi*u))
        # Keep existing trailing air; relax the attenuation back to unity over 100 ms.
        stop = min(len(x), last+round(.1*sr))
        if stop>last:
            gain[last:stop] = np.linspace(settings['ending_gain'], 1, stop-last)
        y = (x*gain).astype(np.float32)
        assert np.array_equal(y[:first], x[:first]) and len(x)==len(y)
        assert np.max(abs(y))<=np.max(abs(x))+1e-7 and gain.min()>=.82
        write(a.output/'clips'/f.name, sr, y)
        gap = np.zeros(round(settings['gap_seconds']*sr), dtype=np.float32)
        old.extend([x,gap]);new.extend([y,gap])
        if i in [2,5,6,14]:
            for z in [x,y]: pairs.extend([z,np.zeros(16800,dtype=np.float32)])
        text += f"- {position:.2f}秒: {tr['text']}\n";position += (len(y)+len(gap))/sr
        rows.append(dict(index=i,text=tr['text'],reference=tr['reference'],settings=settings,
                         release_first_frame=first,last_active_frame=last,release_stop_frame=stop,
                         frames=len(y),max_gain_change_db=float(-20*np.log10(gain.min()))))
    outputs = {}
    for name,chunks in [('expressive-breath-ending-demo',new),('same-new-lines-control',old),('00-new-lines-before-after',pairs)]:
        x = np.concatenate(chunks[:-1]);write(a.output/(name+'.wav'), sr, x)
        _,check = read(a.output/(name+'.wav'));assert np.array_equal(x,check)
        outputs[name] = dict(seconds=len(x)/sr,sha256=hashlib.sha256((a.output/(name+'.wav')).read_bytes()).hexdigest())
    assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in input_hashes.items())
    (a.output/'transcript.md').write_text(text)
    (a.output/'report.json').write_text(json.dumps(dict(trials=rows,outputs=outputs,inputs=input_hashes,
        input_unchanged=True,method='New short-reference-conditioned speech with textual sighs, source-informed phrase gaps and gentle last-160ms attenuation',
        actual_breath_isolation=False,perceptual_quality_verified=False),ensure_ascii=False,indent=2))
    print(json.dumps(outputs,indent=2))


if __name__ == '__main__':
    main()
