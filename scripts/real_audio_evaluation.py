#!/usr/bin/env python3
"""Reproducible local measurement, not a subjective listening or separation-quality score.
Run with the existing separation venv (numpy, soundfile). All outputs stay under build/.
"""
import argparse
import base64
import io
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def pitch(x, sr):
    y = x.mean(axis=1)[::4]
    y = y - y.mean()
    n = len(y)
    f = np.fft.rfft(y, n=2*n)
    ac = np.fft.irfft(abs(f)**2)[:n]
    lo, hi = int(sr/4/600), min(n-2, int(sr/4/25))
    k = lo + int(np.argmax(ac[lo:hi]))
    d = ac[k-1] - 2*ac[k] + ac[k+1]
    frac = 0.5*(ac[k-1]-ac[k+1])/d if abs(d) > 1e-12 else 0
    hz = sr/4/(k+frac)
    return {'hz': float(hz), 'periodicity': float(ac[k]/max(ac[0], 1e-15)),
            'midi_estimate': float(69+12*np.log2(hz/440))}


def metrics(x, sr):
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x*x)))
    return {'seconds': len(x)/sr, 'sample_rate': sr, 'peak_dbfs': float(20*np.log10(max(peak, 1e-12))),
            'rms_dbfs': float(20*np.log10(max(rms, 1e-12))), 'nonfinite': int(np.count_nonzero(~np.isfinite(x))),
            'over_fullscale': int(np.count_nonzero(abs(x)>1)), 'max_adjacent_step': float(np.max(abs(np.diff(x, axis=0))))}


def make_auditions(out, split, candidates):
    """Listening copies only: -20 dBFS RMS target, -3 dBFS peak cap per segment."""
    indexes = {}
    for c in candidates:
        stem = c['stem']; segments = []; timeline = []; cursor = 0.0
        for name, path in [('original_context', split/'original.wav'), ('stem_context', split/(stem+'.wav'))] + [
                (name, out/(stem+'_'+name+'.wav')) for name in ['pitch_m12','pitch_root','pitch_p12','chord','phrase','loop_hard','loop_crossfade']]:
            if name.endswith('_context'):
                a = max(0,c['startFrame']-11025)
                x,sr=sf.read(path,start=a,stop=a+88200,always_2d=True)
            else:
                x,sr=sf.read(path,always_2d=True)
            gain=min(10**(-20/20)/max(float(np.sqrt(np.mean(x*x))),1e-12),10**(-3/20)/max(float(np.max(abs(x))),1e-12))
            x=x*gain
            if sr != 48000:
                t=np.arange(round(len(x)*48000/sr))*sr/48000
                x=np.stack([np.interp(t,np.arange(len(x)),x[:,ch]) for ch in range(2)],axis=1)
            timeline.append({'label':name,'start_seconds':cursor,'duration_seconds':len(x)/48000,'gain_db':float(20*np.log10(gain))})
            segments.extend([x,np.zeros((24000,2))]);cursor+=len(x)/48000+.5
        sf.write(out/(stem+'_audition.wav'),np.concatenate(segments),48000,subtype='FLOAT')
        indexes[stem]=timeline
    (out/'audition-index.json').write_text(json.dumps(indexes,indent=2,allow_nan=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--separated', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT/'build/real-audio-evaluation')
    args = parser.parse_args()
    source, split, out = args.input.resolve(), args.separated.resolve(), args.output.resolve()
    if not out.is_relative_to(ROOT/'build') or out.exists():
        raise ValueError('Use a new output directory below build/; existing results are never replaced')
    manifest = json.loads((split/'manifest.json').read_text())
    assert digest(source) == manifest['inputSHA256'], 'Separation does not match source'
    entries = {e['id']: e for e in manifest['audio']}
    hashes = {}
    for name in ['original','bass','drums','other','vocals']:
        entry = entries[name]
        assert entry['file'] == name+'.wav'
        path = split/entry['file']
        info = sf.info(path)
        assert info.frames == entry['frames'] and info.samplerate == 44100 and info.channels == 2
        hashes[name] = digest(path)
    out.mkdir(parents=True)
    # Stable periodic segments from a coarse 0.25s scan of this specific recording.
    # Root is manual: the previous bass diagnostic mapping 48 is now corrected to D-sharp2 (39).
    candidates = [{'stem':'bass','startFrame':63*44100,'endFrame':int(63.3*44100),'root':39},
                  {'stem':'other','startFrame':int(115.25*44100),'endFrame':int(115.55*44100),'root':51}]
    drums, sr = sf.read(split/'drums.wav', start=20*44100, stop=40*44100, always_2d=True)
    block = 441
    envelope = np.sqrt(np.mean(drums[:len(drums)//block*block].reshape(-1,block,2)**2,axis=(1,2)))
    onset = max(0, int(np.argmax(np.diff(envelope)))*block - 220) + 20*44100
    candidates.append({'stem':'drums','startFrame':onset,'endFrame':onset+int(.22*44100),'root':60})
    (out/'candidates.json').write_text(json.dumps(candidates, indent=2))
    report = {'source_sha256':manifest['inputSHA256'],'model':manifest['model'], 'weight_sha256':manifest['weightSHA256'],
              'versions':manifest['versions'],'shared_separation_gain':manifest['gain'],'stem_sha256':hashes,
              'separation':'reused full-song worker output, source hash verified; no new inference',
              'subjective_listening':'not performed; agent has no listening capability', 'candidates':[]}
    for c in candidates:
        a,b = c['startFrame'],c['endFrame']; stem=c['stem']
        item = dict(c)
        item['start_seconds'],item['end_seconds']=a/44100,b/44100
        for name in ['original',stem]:
            x,sr = sf.read(split/(name+'.wav'),start=a,stop=b,always_2d=True)
            assert np.isfinite(x).all()
            sf.write(out/(stem+'_'+('original' if name=='original' else 'extracted')+'.wav'), x,sr,subtype='FLOAT')
            item[name] = metrics(x,sr)
            rms=np.sqrt(np.mean(x*x)); gain=min(10**(-18/20)/max(rms,1e-12),10**(-1/20)/max(np.max(abs(x)),1e-12))
            sf.write(out/(stem+'_'+name+'_levelmatched.wav'),x*gain,sr,subtype='FLOAT')
            item[name]['comparison_gain_db']=float(20*np.log10(gain))
            if name==stem: item['pitch_estimate']=pitch(x,sr)
        report['candidates'].append(item)
    # Use exactly the app source set already maintained by test.sh, replacing its test entry point.
    command=shlex.split((ROOT/'scripts/test.sh').read_text().split('xcrun swiftc',1)[1].split('build/AudioTests',1)[0].replace('\\\n',' '))
    sources=[s for s in command if s.startswith('app/') and s.endswith('.swift')]
    binary=out/'RealAudioEvaluation'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-module-cache-path','build/module-cache',*sources,
                    'scripts/real_audio_evaluation.swift','-o',str(binary)],cwd=ROOT,check=True)
    subprocess.run([str(binary),str(out),str(split),str(source)],cwd=ROOT,check=True)
    report['archive_checks']={}
    for c in candidates:
        stem=c['stem']
        archive=json.loads((out/(stem+'.sfinstrument')).read_text())
        saved,sr=sf.read(io.BytesIO(base64.b64decode(archive['sampleWAV'])),always_2d=True)
        extracted,rate=sf.read(out/(stem+'_extracted.wav'),always_2d=True)
        assert archive['version']==5 and sr==rate and np.array_equal(saved,extracted)
        song=json.loads((out/(stem+'_phrase.sfensemble')).read_text())
        assert song['version']==12
        report['archive_checks'][stem]={'instrument_version':5,'ensemble_version':12,'embedded_pcm_exact':True}
    report['renders']={}
    for path in sorted(out.glob('*.wav')):
        x,sr=sf.read(path,always_2d=True)
        m=metrics(x,sr)
        if '_loop_' in path.name:
            steady=x[int(.35*sr):int(.9*sr)]
            m['steady_max_adjacent_step']=float(np.max(abs(np.diff(steady,axis=0))))
        assert m['nonfinite']==0 and m['over_fullscale']==0 and m['peak_dbfs'] > -120, path
        if '_pitch_' in path.name and not path.name.startswith('drums'):
            m['pitch_estimate']=pitch(x[int(.1*sr):int(.25*sr)],sr)
            m['early_pitch_estimate']=pitch(x[int(.03*sr):int(.12*sr)],sr)
        report['renders'][path.name]=m
    make_auditions(out, split, candidates)
    # Source and cached full-length stems must remain byte-identical.
    assert digest(source)==report['source_sha256']
    assert all(digest(split/(n+'.wav'))==h for n,h in hashes.items())
    report['source_and_stems_unchanged']=True
    (out/'measurements.json').write_text(json.dumps(report,indent=2,allow_nan=False))
    print('PASS: measurements and audio comparisons saved to',out)


if __name__ == '__main__':
    main()
