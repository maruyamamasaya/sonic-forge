"""Local expressive 16-bar vowel arrangement; no application or AI generation."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
import numpy as np
from scipy.signal import fftconvolve
from vowel_chord_study import read, write, active_mask
from create_score_demo import read_score


def phrase_gain(beat):
    # Four 4-bar arcs plus an overall rise and fall, in dB.
    local=np.interp(beat%12,[0,3,7,10,12],[-5,-2,1,-2,-6])
    overall=np.interp(beat,[0,12,26,36,48],[-3,-1,2,0,-7])
    return 10**((local+overall)/20)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--score',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=False);work=a.output/'layers';work.mkdir();sr=24000
    sources={};hashes={}
    for v in ['a','u']:
        path=a.input/(v+'-long.wav');rate,x=read(path);assert rate==sr
        sources[v]=x;hashes[v]=hashlib.sha256(path.read_bytes()).hexdigest()
    # Beat-to-time curve: gentle phrase breathing, with a small final ritardando.
    grid=np.linspace(0,48,4801)
    beat_seconds=(60/72)*(1+.025*np.cos(2*np.pi*grid/12)+.10*np.clip((grid-42)/6,0,1))
    times=np.r_[0,np.cumsum((beat_seconds[1:]+beat_seconds[:-1])*.005)]
    def clock(b):return float(np.interp(b,grid,times))
    cache={}
    def sample(v,pitch,duration):
        duration=round(min(duration,2.35),3);key=(v,pitch,duration)
        if key in cache:return cache[key]
        x=sources[v];ratio=duration/(len(x)/sr);pad=round(.15*sr)
        src=work/f'{len(cache)}-in.wav';dst=work/f'{len(cache)}-out.wav'
        write(src,sr,np.pad(x,(pad,pad)).astype(np.float32))
        subprocess.run(['rubberband','-q','-3','-F','-t',str(ratio),'-p',str(pitch-{'a':68.8,'u':68.1}[v]),str(src),str(dst)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        rate,y=read(dst);assert rate==sr
        start=round(pad*ratio);y=y[start:start+round(duration*sr)].copy()
        ramp=min(round(.035*sr),len(y)//4);y[:ramp]*=np.linspace(0,1,ramp);y[-ramp:]*=np.linspace(1,0,ramp)
        y*=.055/np.sqrt(np.mean(y[active_mask(y,sr)].astype(float)**2))
        cache[key]=y;return y
    raw=read_score(a.score.read_bytes());melody=[];harmony=[];tied_harmony_beats=set()
    for n in raw:
        b=n['beat']
        if n['track']!=1 or not 12<=b<60:continue
        # Bars 9-12: restore tied F#4; suppress MIDI accompaniment retriggers as melody.
        if 24<=b<36:
            if b==24:
                for offset in [0,3,6,9]:melody.append((b-12+offset,66,2.82, .70))
            if b%3==1 and b not in tied_harmony_beats:
                tied_harmony_beats.add(b)
                for pitch in [61 if int((b-25)/3)%2 else 62,66]:harmony.append((b-12,pitch,1.8,.16))
            continue
        chord=b%3==1 and n['duration']>=2
        if chord:
            if n['pitch']>=60:harmony.append((b-12,n['pitch'],min(n['duration'],1.8),.16))
        else:
            pitch=n['pitch']-12
            while pitch<57:pitch+=12
            melody.append((b-12,pitch,min(n['duration'],3),.82*n['velocity']/90))
    size=round((clock(48)+3)*sr);stems={}
    for mode in ['plain','expressive']:
        for role,v,events in [('melody','u',melody),('chorus','a',harmony)]:
            track=np.zeros(size)
            for b,pitch,d,g in events:
                end=min(48,b+d);duration=max(.2,clock(end)-clock(b)-(.09 if b%12>=9 else .025))
                y=sample(v,pitch,duration).astype(float).copy();onset=clock(b)+.15
                if mode=='expressive':
                    pos=np.linspace(0,1,len(y));gain_curve=np.interp(pos,[0,.18,.52,.82,1],[.40,.78,1,.79,.18])
                    absolute=b+pos*(end-b)
                    arc=np.array([phrase_gain(t) for t in absolute])
                    y*=gain_curve*arc
                start=round(onset*sr);track[start:start+len(y)]+=y*g
            stems[(mode,role)]=track
    rng=np.random.default_rng(21);t=np.arange(round(1.5*sr))/sr
    ir=np.convolve(rng.standard_normal(len(t))*np.exp(-np.log(1000)*t/1.05),[.25,.5,.25],mode='same')
    ir/=np.sqrt(np.sum(ir**2));ir=np.pad(ir,(round(.025*sr),0))
    rendered={}
    for (mode,role),track in stems.items():rendered[(mode,role)]=track+(.10 if role=='melody' else .18)*fftconvolve(track,ir)[:size]
    mixes={mode:rendered[(mode,'melody')]+rendered[(mode,'chorus')] for mode in ['plain','expressive']}
    # Match comparison integrated RMS with a single constant, keeping expressive dynamics intact.
    rms=lambda x:np.sqrt(np.mean(x*x))
    plain_gain=rms(mixes['expressive'])/rms(mixes['plain'])
    for role in ['melody','chorus']:rendered[('plain',role)]*=plain_gain
    mixes['plain']*=plain_gain
    gain=min(1.8,10**(-6/20)/max(np.max(abs(x)) for x in mixes.values()))
    for mode in mixes:
        write(a.output/f'gymnopedie-{mode}.wav',sr,(mixes[mode]*gain).astype(np.float32))
        for role in ['melody','chorus']:write(a.output/f'{mode}-{role}.wav',sr,(rendered[(mode,role)]*gain).astype(np.float32))
    # First moving phrase is enough to compare expression without replaying the entire piece.
    end=round((clock(12)+.6)*sr)
    comparison=np.concatenate([mixes['plain'][:end],np.zeros(sr),mixes['expressive'][:end]])*gain
    write(a.output/'00-plain-then-expressive.wav',sr,comparison.astype(np.float32))
    for v in sources:assert hashes[v]==hashlib.sha256((a.input/(v+'-long.wav')).read_bytes()).hexdigest()
    for mode in mixes:
        _,mix=read(a.output/f'gymnopedie-{mode}.wav');_,lead=read(a.output/f'{mode}-melody.wav');_,choir=read(a.output/f'{mode}-chorus.wav')
        assert np.max(abs(mix-lead-choir))<1e-7
    assert abs(20*np.log10(rms(mixes['plain'])/rms(mixes['expressive'])) )<.001
    assert phrase_gain(26)>phrase_gain(0) and phrase_gain(47)<phrase_gain(26)
    report=dict(seconds=size/sr,score_bars=[5,20],melody=melody,chorus=harmony,source_hashes=hashes,source_unchanged=True,
        expression='4-bar crescendo/decrescendo plus overall arc; intra-note swelling; phrase breaths; common rubato and final ritardando',
        tied_note='F#4 in bars9-12 rearticulated at 3-beat breathing points, not a continuous 10-second sample',
        max_note_seconds=2.35,source_pitch_drift_retained=True,new_ai_generation=False,loops=False,
        plain_comparison_gain_db=float(20*np.log10(plain_gain)),output_gain_db=float(20*np.log10(gain)),
        technical_validation='PASS',listening_quality_verified=False)
    (a.output/'report.json').write_text(json.dumps(report,indent=2));print('PASS:',size/sr,'seconds; matched comparison; expressive arcs; source unchanged; stem sum')

if __name__=='__main__':main()
