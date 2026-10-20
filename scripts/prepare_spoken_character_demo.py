"""Prepare a conversational variation reel, keeping full utterances and modest effects.
Text/reference performance is separate from explicit whole-utterance DSP listed in the report.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from scipy.interpolate import CubicSpline
from scipy.ndimage import gaussian_filter1d
from scipy.signal import butter,sosfiltfilt
from vowel_chord_study import read,write,active_mask
from vowel_vibrato_study import modulate


def clock_label(t):return f'{int(t)//60:02d}:{int(t)%60:02d}'


def change_pace(x,sr,mode,work,index):
    if mode=='normal':return x.copy(),dict(mode=mode,speed_range=[1.,1.],ratio=1.)
    source=work/f'{index:02d}-source.wav';destination=work/f'{index:02d}-pace.wav';mapping=work/f'{index:02d}-timemap.txt'
    write(source,sr,x)
    grid=np.linspace(0,len(x)/sr,101);u=grid/grid[-1];ease=u*u*(3-2*u)
    if mode=='quick':speed=np.full(len(grid),1.16)
    elif mode=='accelerate':speed=1+.20*ease
    elif mode=='settle':speed=1.14-.16*ease
    else:raise ValueError('Unknown pace mode')
    mapped=np.r_[0,np.cumsum(np.diff(grid)*(.5/speed[:-1]+.5/speed[1:]))]
    src=np.round(grid*sr).astype(int);dst=np.round(mapped*sr).astype(int)
    assert np.all(np.diff(src)>0) and np.all(np.diff(dst)>0)
    mapping.write_text(''.join(f'{s} {d}\n' for s,d in zip(src,dst)))
    subprocess.run(['rubberband','-q','-3','-F','-t',str(dst[-1]/len(x)),'--timemap',str(mapping),str(source),str(destination)],
        check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    rate,y=read(destination);assert rate==sr and abs(len(y)-dst[-1])<=1
    return y,dict(mode=mode,speed_range=[float(speed.min()),float(speed.max())],ratio=len(y)/len(x))


def colour_variation(x,sr,wander,air,index):
    y=x.astype(float).copy();report={}
    if wander:
        rng=np.random.default_rng(100+index);duration=len(y)/sr
        knots=np.linspace(0,duration,max(5,round(duration/.7)))
        values=rng.normal(0,.6,len(knots));values[0]=values[-1]=0
        curve=CubicSpline(knots,values,bc_type='natural')(np.arange(len(y))/sr)
        curve*=np.sin(np.linspace(0,np.pi,len(y)))**2
        curve*=wander/max(np.max(abs(curve)),1e-8)
        rates=2**(curve/12);rates-=rates.mean()-1
        cents=1200*np.log2(rates);y,displacement=modulate(y,sr,cents)
        assert abs(displacement[-1])<1e-7
        report.update(pitch_wander_peak_cents=float(np.max(abs(cents))),max_time_displacement_ms=float(np.max(abs(displacement))/sr*1000))
    if air:
        rng=np.random.default_rng(200+index)
        noise=sosfiltfilt(butter(3,[900,6500],btype='bandpass',fs=sr,output='sos'),rng.standard_normal(len(y)))
        noise/=np.sqrt(np.mean(noise**2))
        envelope=np.sqrt(gaussian_filter1d(y*y,sr*.018))
        # A very light breathiness proxy; no clipping, throat simulation or growl synthesis.
        y+=noise*envelope*air
        report['synthetic_air_relative_amplitude']=air
    return y.astype(np.float32),report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--max-reel-seconds',type=float,default=155,help='Upper validation bound; never stretches or truncates audio')
    a=p.parse_args();generation=json.loads((a.input/'report.json').read_text())
    assert 100<a.max_reel_seconds<=300
    assert generation['all_natural_eos'] and generation['all_references_unchanged']
    assert not generation['audio_sent_to_external_service'] and generation['blocked_network_attempts']==0
    a.output.mkdir(parents=True,exist_ok=False);work=a.output/'work';work.mkdir();(a.output/'clips').mkdir()
    trials=generation['trials'];raw=[];processed=[];meta=[];gains=[]
    for i,tr in enumerate(trials,1):
        source=a.input/tr['file'];digest=hashlib.sha256(source.read_bytes()).hexdigest();sr,x=read(source);assert sr==24000
        y,pace=change_pace(x,sr,tr['pace'],work,i)
        y,variation=colour_variation(y,sr,tr['pitch_wander_semitones'],tr['air_mix'],i)
        source_rms=np.sqrt(np.mean(x[active_mask(x,sr)].astype(float)**2))
        result_rms=np.sqrt(np.mean(y[active_mask(y,sr)].astype(float)**2))
        level=1. if tr['reference'].startswith('bright') else (-1.5 if tr['reference'].startswith('subdued') else 0.)
        target=10**((-25+level)/20);gains.append((target/source_rms,target/result_rms))
        raw.append(x);processed.append(y)
        meta.append(dict(category=tr['category'],text=tr['text'],reference=tr['reference'],reference_sha256=tr['reference_sha256'],
            file=tr['file'],source_sha256=digest,source_frames=len(x),result_frames=len(y),pace=pace,variation=variation,
            waveform_cuts=False,performed_style_verified=False))
    peak=max(max(np.max(abs(x))*g[0],np.max(abs(y))*g[1]) for x,y,g in zip(raw,processed,gains))
    common=min(1.,10**(-3/20)/peak);gap=np.zeros(round(.35*sr),dtype=np.float32)
    final=[];original=[];position=0
    for i,(x,y,g,m) in enumerate(zip(raw,processed,gains,meta)):
        xx=(x*(g[0]*common)).astype(np.float32);yy=(y*(g[1]*common)).astype(np.float32)
        write(a.output/'clips'/m['file'],sr,yy)
        final.append(yy);original.append(xx);m['start_seconds']=position/sr;position+=len(yy);m['end_seconds']=position/sr
        m['gain_db']=float(20*np.log10(g[1]*common))
        if i<len(meta)-1:final.append(gap);original.append(gap);position+=len(gap)
        assert m['source_sha256']==hashlib.sha256((a.input/m['file']).read_bytes()).hexdigest()
    reel=np.concatenate(final);control=np.concatenate(original)
    write(a.output/'spoken-character-demo.wav',sr,reel);write(a.output/'generation-only-control.wav',sr,control)
    assert 100<len(reel)/sr<a.max_reel_seconds,'Do not stretch or truncate the whole reel to force its duration'
    transcript='# 会話の癖・話し方のバリエーション\n\nカテゴリーは演技の狙いであり、感情制御の成功を保証するラベルではない。元の生成音声と速度/微小揺れ/薄い息成分の加工を区別する。\n\n'
    for m in meta:
        transcript+=f"- {clock_label(m['start_seconds'])}〜{clock_label(m['end_seconds'])} **{m['category']}**：{m['text']}\n"
    (a.output/'transcript.md').write_text(transcript)
    _,check=read(a.output/'spoken-character-demo.wav');assert np.array_equal(reel,check)
    for m in meta:
        _,clip=read(a.output/'clips'/m['file']);assert np.array_equal(reel[round(m['start_seconds']*sr):round(m['end_seconds']*sr)],clip)
    result=dict(seconds=len(reel)/sr,control_seconds=len(control)/sr,utterances=len(meta),gap_seconds=.35,common_gain_db=float(20*np.log10(common)),
        sources_unchanged=True,all_natural_eos=True,method='Whole generated utterances; contextual text disfluencies/reference variation; modest offline tempo shaping on 4 lines, small pitch wandering on 2, thin synthetic air on 2. No word cuts or forced pitch correction.',
        acting_emotion_and_hoarseness_verified=False,trials=meta)
    (a.output/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));shutil.copyfile(a.input/'report.json',a.output/'generation-report.json')
    print(f'PASS: {len(meta)} complete utterances; {len(reel)/sr:.2f}s character reel; {len(control)/sr:.2f}s generation-only control')

if __name__=='__main__':main()
