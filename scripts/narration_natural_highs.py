"""Compare pace-only speech with conservative dynamic high-band attenuation, no added breath."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.signal import butter, sosfiltfilt
from vowel_chord_study import read, write


def ratio(x, high, sr):
    energy = gaussian_filter1d(x.astype(float)**2, sr*.02)
    upper = gaussian_filter1d(high.astype(float)**2, sr*.02)
    return np.sqrt(upper/np.maximum(energy, 1e-9)), energy


def soften(x, sr, target):
    high = sosfiltfilt(butter(2, 3800, 'highpass', fs=sr, output='sos'), x)
    measured, energy = ratio(x, high, sr)
    active = energy > max(1e-8, energy.max()*.0025)
    reduction = np.clip(20*np.log10(np.maximum(measured, 1e-6)/target), 0, 2.5)*active
    reduction = gaussian_filter1d(reduction, sr*.02)
    y = x+high*(10**(-reduction/20)-1)
    return y.astype(np.float32), float(reduction.max())


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pace', type=Path, required=True)
    p.add_argument('--references', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args(); report = json.loads((a.pace/'report.json').read_text())
    a.output.mkdir(parents=True, exist_ok=False)
    for label in ['pace-only', 'soft-highs']:
        (a.output/label/'clips').mkdir(parents=True)
    rows = []; inputs = {}
    for i,tr in enumerate(report['trials'], 1):
        source = a.pace/'clips'/tr['file']; ref = a.references/(tr['reference']+'.wav')
        for f in [source,ref]:inputs[str(f)] = hashlib.sha256(f.read_bytes()).hexdigest()
        sr,x = read(source);rate,r = read(ref);assert sr == rate == 24000
        h = sosfiltfilt(butter(2, 3800, 'highpass', fs=sr, output='sos'), r)
        rr, energy = ratio(r,h,sr); active = energy>max(1e-8, energy.max()*.0025)
        target = max(.015, float(np.percentile(rr[active], 80)))
        y, maximum = soften(x,sr,target)
        assert len(x)==len(y) and np.isfinite(y).all() and np.max(abs(y))<1 and maximum<=2.5+1e-9
        write(a.output/'pace-only/clips'/tr['file'],sr,x)
        write(a.output/'soft-highs/clips'/tr['file'],sr,y)
        rows.append(dict(index=i,text=tr['text'],reference=tr['reference'],frames=len(x),
                         high_band_target=target,max_reduction_db=maximum))
    for label in ['pace-only','soft-highs']:
        (a.output/label/'report.json').write_text(json.dumps(dict(trials=rows,method=label),ensure_ascii=False,indent=2))
    assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in inputs.items())
    # The filter must leave a low pure tone nearly unchanged and attenuate an upper tone.
    t = np.arange(24000)/24000
    low = (.1*np.sin(2*np.pi*220*t)).astype(np.float32)
    high = (.1*np.sin(2*np.pi*6000*t)).astype(np.float32)
    low_y,_ = soften(low,24000,.05);high_y,_ = soften(high,24000,.05)
    low_error_db = float(20*np.log10(max(float(np.linalg.norm(low_y-low)/np.linalg.norm(low)), 1e-15)))
    upper_change_db = float(20*np.log10(np.linalg.norm(high_y)/np.linalg.norm(high)))
    assert low_error_db < -50 and -2.6<upper_change_db<-.5
    (a.output/'report.json').write_text(json.dumps(dict(trials=rows,inputs=inputs,
        low_tone_error_db=low_error_db,upper_tone_change_db=upper_change_db,
        method='Remove source-prosody DSP; keep reference-conditioned generation/pace, optionally attenuate 3.8kHz+ by up to 2.5dB',
        isolated_breath=False,perceptual_improvement_verified=False),ensure_ascii=False,indent=2))
    print('PASS low/high known tones, original inputs unchanged, bounded high-band attenuation')


if __name__ == '__main__':main()
