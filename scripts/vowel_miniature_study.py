"""Two delicate local vowel miniatures, without application integration."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
import numpy as np
from scipy.signal import fftconvolve
from vowel_chord_study import read, write, active_mask
from create_score_demo import read_score


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True)
    p.add_argument('--score',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    work=a.output/'layers';work.mkdir();sr=24000
    sources={};hashes={}
    # U has a more stable pitch centre; A retains its breathy rising onset in the quiet accompaniment.
    for v in ['a','u']:
        f=a.input/(v+'-long.wav');rate,x=read(f);assert rate==sr
        sources[v]=x;hashes[v]=hashlib.sha256(f.read_bytes()).hexdigest()
    cache={}
    def voice(v,pitch,duration):
        key=(v,pitch,round(duration,3))
        if key in cache:return cache[key]
        x=sources[v];base={'a':68.8,'u':68.1}[v]
        # Limit extension: long score notes breathe out rather than use mechanical sustain loops.
        duration=min(duration,1.65)
        ratio=max(.35,duration/(len(x)/sr))
        pad=round(.12*sr);padded=np.pad(x,(pad,pad)).astype(np.float32)
        stem=f'{v}-{pitch}-{len(cache)}';src=work/(stem+'-in.wav');dst=work/(stem+'-out.wav')
        write(src,sr,padded)
        subprocess.run(['rubberband','-q','-3','-F','-t',str(ratio),'-p',str(pitch-base),str(src),str(dst)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        rate,y=read(dst);assert rate==sr
        start=round(pad*ratio);y=y[start:start+round(duration*sr)].copy()
        # Smooth boundaries only; retain original internal articulation and pitch drift.
        ramp=min(round(.025*sr),len(y)//4)
        y[:ramp]*=np.linspace(0,1,ramp);y[-ramp:]*=np.linspace(1,0,ramp)
        rms=np.sqrt(np.mean(y[active_mask(y,sr)].astype(float)**2));y*=.055/rms
        cache[key]=y;return y
    # Familiar public-domain nursery tune, four bars, light two-note accompaniment.
    pitches=[60,60,67,67,69,69,67,65,65,64,64,62,62,60]
    lengths=[1,1,1,1,1,1,2,1,1,1,1,1,1,2]
    melody=[];beat=0
    for n,d in zip(pitches,lengths):melody.append((beat,n+5,d,.95));beat+=d
    nursery_harmony=[]
    for bar,notes in enumerate([(60,64),(60,65),(59,62),(60,64)]):
        for off in [0,2]:
            for n in notes:nursery_harmony.append((bar*4+off,n+5,1.1,.20))
    score=read_score(a.score.read_bytes())
    gm=[];gh=[]
    for n in score:
        if not 12<=n['beat']<24 or n['track']!=1:continue
        chord=n['beat']%3==1 and n['duration']>=2
        if chord:
            # Omit lowest chord member to keep just two delicate inner voices.
            if n['pitch']>=60:gh.append((n['beat']-12,n['pitch'],min(n['duration'],1.4),.18))
        else:gm.append((n['beat']-12,n['pitch']-12,n['duration'],.8*n['velocity']/90))
    # Deterministic short room, same restrained character as prior comparison.
    rng=np.random.default_rng(21);t=np.arange(round(1.2*sr))/sr
    ir=rng.standard_normal(len(t))*np.exp(-np.log(1000)*t/.9)
    ir=np.convolve(ir,[.25,.5,.25],mode='same');ir/=np.sqrt(np.sum(ir**2));ir=np.pad(ir,(round(.022*sr),0))
    reports=[]
    for name,bpm,beats,lead_events,choir_events in [('nursery',96,16,melody,nursery_harmony),('gymnopedie',72,12,gm,gh)]:
        seconds=beats*60/bpm+2;size=round(seconds*sr)
        lead=np.zeros(size);choir=np.zeros(size)
        for target,v,events in [(lead,'u',lead_events),(choir,'a',choir_events)]:
            for beat,pitch,d,gain in events:
                y=voice(v,pitch,d*60/bpm*.9)*gain;start=round((.12+beat*60/bpm)*sr)
                target[start:start+len(y)]+=y
        # Shared reverb preserves interaction; choir has a little more room than lead.
        lead_w=lead+.10*fftconvolve(lead,ir)[:size]
        choir_w=choir+.17*fftconvolve(choir,ir)[:size]
        mix=lead_w+choir_w
        gain=min(1.,10**(-6/20)/np.max(abs(mix)))
        for suffix,x in [('mix',mix),('melody',lead_w),('chorus',choir_w)]:write(a.output/f'{name}-{suffix}.wav',sr,(x*gain).astype(np.float32))
        _,actual=read(a.output/f'{name}-mix.wav');assert np.max(abs(actual-(lead_w+choir_w)*gain))<1e-7
        reports.append(dict(name=name,bpm=bpm,seconds=seconds,melody_notes=len(lead_events),chorus_notes=len(choir_events),peak=float(np.max(abs(actual))),events=dict(melody=lead_events,chorus=choir_events)))
    for v in sources:assert hashes[v]==hashlib.sha256((a.input/(v+'-long.wav')).read_bytes()).hexdigest()
    (a.output/'report.json').write_text(json.dumps(dict(trials=reports,source_hashes=hashes,source_unchanged=True,
        melody_vowel='u',chorus_vowel='a',formant_preservation=True,max_note_seconds=1.65,
        nursery='Twinkle Twinkle / Ah vous dirai-je maman, first four bars',
        gymnopedie='Mutopia fixed MIDI, bars 5-8; melody octave down, bass omitted, two upper accompaniment tones',
        pitch_centres_approximate=True,original_pitch_drift_retained=True,loops=False,new_ai_generation=False,
        listening_quality_verified=False),indent=2))
    print('PASS: generated two miniatures and separate melody/chorus stems; source hashes unchanged')

if __name__=='__main__':main()
