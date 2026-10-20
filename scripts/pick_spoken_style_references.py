"""Pick acoustically contrasting reference candidates from the supplied private recording.
Acoustic labels are provisional, not emotion recognition.
"""
import argparse
import hashlib
import json
import subprocess
import unicodedata
from pathlib import Path
import numpy as np
from scipy.signal import resample_poly
from vowel_chord_study import read,write,active_mask


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();root=Path(__file__).resolve().parents[1]
    metadata=json.loads((root/'build/midi-materials/voice/source.json').read_text())
    source=next(f for f in (root/'sample_music').iterdir() if f.is_file() and unicodedata.normalize('NFC',f.name)==unicodedata.normalize('NFC',metadata['source']))
    digest=hashlib.sha256(source.read_bytes()).hexdigest();assert digest==metadata['sha256']
    a.output.mkdir(parents=True,exist_ok=False)
    decoded=a.output/'source-decoded.wav'
    subprocess.run(['ffmpeg','-v','error','-n','-i',str(source),'-ar','24000','-ac','1','-c:a','pcm_f32le',str(decoded)],check=True)
    sr,x=read(decoded);y=resample_poly(x,1,2);analysis_sr=12000
    width,hop=480,240
    frames=np.lib.stride_tricks.sliding_window_view(y,width)[::hop]
    times=(np.arange(len(frames))*hop+width/2)/analysis_sr
    rms=np.sqrt(np.mean(frames.astype(float)**2,axis=1));f0=[];quality=[]
    lags=np.arange(round(analysis_sr/550),round(analysis_sr/150))
    for first in range(0,len(frames),512):
        batch=frames[first:first+512].astype(float);batch-=batch.mean(axis=1,keepdims=True)
        ac=np.fft.irfft(abs(np.fft.rfft(batch,n=1024))**2,n=1024)
        scores=ac[:,lags]/np.maximum(ac[:,0,None],1e-12);best=scores.argmax(axis=1)
        f0.extend(analysis_sr/lags[best]);quality.extend(scores[np.arange(len(best)),best])
    f0=np.array(f0);quality=np.array(quality)
    active=(rms>max(.001,np.percentile(rms,80)*.09))&(quality>.55)
    candidates=[]
    for start in np.arange(.2,len(x)/sr-3.2,.5):
        mask=(times>=start)&(times<start+3.2);voiced=mask&active
        if voiced.sum()<40 or voiced.sum()/mask.sum()<.40:continue
        midi=69+12*np.log2(f0[voiced]/440)
        candidates.append(dict(start_seconds=float(start),seconds=3.2,pitch_median=float(np.median(midi)),
            pitch_iqr=float(np.percentile(midi,75)-np.percentile(midi,25)),
            rms_dbfs=float(20*np.log10(np.sqrt(np.mean(rms[mask]**2)))),
            rms_variation=float(np.std(rms[mask])/max(np.mean(rms[mask]),1e-8)),voiced_fraction=float(voiced.sum()/mask.sum())))
    assert len(candidates)>12
    keys=['pitch_median','pitch_iqr','rms_dbfs','rms_variation'];features=np.array([[c[k] for k in keys] for c in candidates]);z=(features-np.median(features,axis=0))/np.maximum(np.std(features,axis=0),.01)
    scores=dict(bright=z[:,0]+.8*z[:,1]+.25*z[:,2],subdued=-.65*z[:,0]-.8*z[:,2],calm=-z[:,1]-.65*z[:,3]-.2*abs(z[:,0]))
    chosen=[];used=[8.7]
    for variant in range(2):
        for style in ['bright','subdued','calm']:
            for index in np.argsort(scores[style])[::-1]:
                candidate=candidates[int(index)]
                if all(abs(candidate['start_seconds']-position)>12 for position in used):break
            else:raise ValueError('Not enough independent reference windows')
            used.append(candidate['start_seconds']);entry=dict(candidate,style=style,variant=variant+1,label_verified_by_listener=False)
            name=f'{style}-{variant+1}.wav';start=round(entry['start_seconds']*sr);clip=x[start:start+round(entry['seconds']*sr)]
            write(a.output/name,sr,clip);entry['file']=name;entry['sha256']=hashlib.sha256((a.output/name).read_bytes()).hexdigest();chosen.append(entry)
    # Level-matched listening copies are separate from untouched model reference clips.
    clips=[]
    for c in chosen:
        _,clip=read(a.output/c['file']);gain=10**(-25/20)/np.sqrt(np.mean(clip[active_mask(clip,sr)].astype(float)**2))
        gain=min(gain,.7/np.max(abs(clip)));clips.extend([(clip*gain).astype(np.float32),np.zeros(round(.5*sr),dtype=np.float32)])
    write(a.output/'00-reference-candidates.wav',sr,np.concatenate(clips[:-1]))
    assert digest==hashlib.sha256(source.read_bytes()).hexdigest()
    (a.output/'report.json').write_text(json.dumps(dict(source_sha256=digest,source_unchanged=True,candidate_count=len(candidates),
        labels='Acoustic bright/subdued/calm candidates, not verified happiness/sadness/calm emotions',references=chosen),indent=2))
    print('PASS: six contrasting reference candidates, source unchanged; emotion labels unverified')

if __name__=='__main__':main()
