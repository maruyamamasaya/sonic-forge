"""Join the approved expressive melody with voiced-core overlaps; retain its chorus."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from scipy.signal import fftconvolve
from vowel_chord_study import read, write, active_mask
from vowel_expressive_gymnopedie import phrase_gain


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--previous',type=Path,required=True);p.add_argument('--input',type=Path,required=True)
    p.add_argument('--phrase-vowels', choices=['u,a,u,a'], help='Alternate vowels at 12-beat phrase boundaries')
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=False);work=a.output/'layers';work.mkdir();sr=24000
    report=json.loads((a.previous/'report.json').read_text())
    previous_path=a.previous/'gymnopedie-expressive.wav';previous_hash=hashlib.sha256(previous_path.read_bytes()).hexdigest()
    rate,old=read(previous_path);assert rate==sr
    _,chorus=read(a.previous/'expressive-chorus.wav')
    source=a.input/'u-long.wav';source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
    assert source_hash==report['source_hashes']['u']
    _,original=read(source)
    # Use the steady voiced middle, avoiding repeated breathy onsets at every pitch change.
    core=original[round(.20*sr):round(.80*sr)].copy()
    alternate=None;alternate_hash=None
    if a.phrase_vowels:
        alternate_path=a.input/'a-long.wav'
        alternate_hash=hashlib.sha256(alternate_path.read_bytes()).hexdigest()
        assert alternate_hash==report['source_hashes']['a']
        rate,alternate=read(alternate_path);assert rate==sr
    grid=np.linspace(0,48,4801);seconds=(60/72)*(1+.025*np.cos(2*np.pi*grid/12)+.10*np.clip((grid-42)/6,0,1))
    times=np.r_[0,np.cumsum((seconds[1:]+seconds[:-1])*.005)]
    clock=lambda b:float(np.interp(b,grid,times))
    events=sorted(report['melody']);joins=[]
    for i,(b,pitch,d,g) in enumerate(events[:-1]):
        nb,npitch,_,_=events[i+1]
        # Breath at phrase boundaries, repeated held-note breaths and actual rests.
        joins.append(abs(b+d-nb)<.03 and nb%12!=0 and pitch!=npitch and clock(nb)-clock(b)<2.25)
    joins.append(False)
    track=np.zeros(len(old));transitions=[]
    for i,(b,pitch,d,g) in enumerate(events):
        incoming=i>0 and joins[i-1];outgoing=joins[i]
        start=clock(b)+.15-(.06 if incoming else 0)
        end=(clock(events[i+1][0])+.21) if outgoing else clock(min(48,b+d))+.15-.16
        duration=min(2.4,max(.25,end-start))
        # Unconnected phrase entries retain the original vocal onset; joined notes use voiced core.
        vowel='a' if alternate is not None and int(b//12)%2 else 'u'
        # Keep the approved A articulation rather than inventing a new vowel by filtering U.
        x=(alternate[round(.20*sr):round(.67*sr)] if incoming else alternate) if vowel=='a' else (core if incoming else original)
        base=68.8 if vowel=='a' else (68.12 if incoming else 68.1)
        ratio=duration/(len(x)/sr);pad=round(.15*sr)
        src=work/f'{i}-in.wav';dst=work/f'{i}-out.wav'
        write(src,sr,np.pad(x,(pad,pad)).astype(np.float32))
        subprocess.run(['rubberband','-q','-3','-F','-t',str(ratio),'-p',str(pitch-base),str(src),str(dst)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        rate,y=read(dst);assert rate==sr
        off=round(pad*ratio);y=y[off:off+round(duration*sr)].astype(float).copy()
        y*=.055/np.sqrt(np.mean(y[active_mask(y,sr)]**2))
        pos=np.linspace(0,1,len(y))
        # No per-note collapse within a phrase: continuous expression with small internal movement.
        env=np.interp(pos,[0,.25,.65,1],[.84,.98,1,.90])
        attack=min(round((.12 if incoming else .10)*sr),len(y)//3)
        release=min(round((.12 if outgoing else .23)*sr),len(y)//3)
        env[:attack]*=np.sin(np.linspace(0,np.pi/2,attack))**2
        env[-release:]*=np.cos(np.linspace(0,np.pi/2,release))**2
        absolute=b+pos*min(d,duration/(60/72))
        y*=env*np.array([phrase_gain(t) for t in absolute])*g*10**(report['output_gain_db']/20)
        onset=round(start*sr);track[onset:onset+len(y)]+=y
        transitions.append(dict(beat=b,pitch=pitch,vowel=vowel,incoming_legato=incoming,outgoing_legato=outgoing,start_seconds=start,end_seconds=start+len(y)/sr))
    rng=np.random.default_rng(21);t=np.arange(round(1.5*sr))/sr
    ir=np.convolve(rng.standard_normal(len(t))*np.exp(-np.log(1000)*t/1.05),[.25,.5,.25],mode='same')
    ir/=np.sqrt(np.sum(ir**2));ir=np.pad(ir,(round(.025*sr),0))
    lead=track+.10*fftconvolve(track,ir)[:len(track)]
    # Keep chorus PCM unchanged and solve a single melody gain for matched whole-piece RMS.
    aa=np.mean(lead**2);bb=2*np.mean(lead*chorus);cc=np.mean(chorus.astype(float)**2)-np.mean(old.astype(float)**2)
    gain=(-bb+np.sqrt(bb*bb-4*aa*cc))/(2*aa)
    lead*=gain;mix=lead+chorus
    assert np.max(abs(mix))<10**(-3/20)
    write(a.output/'gymnopedie-legato.wav',sr,mix.astype(np.float32));write(a.output/'legato-melody.wav',sr,lead.astype(np.float32))
    shutil.copyfile(a.previous/'expressive-chorus.wav',a.output/'unchanged-chorus.wav')
    shutil.copyfile(previous_path,a.output/'previous-version.wav')
    assert (a.output/'previous-version.wav').read_bytes()==previous_path.read_bytes()
    assert (a.output/'unchanged-chorus.wav').read_bytes()==(a.previous/'expressive-chorus.wav').read_bytes()
    cut=round(10.6*sr);pair=np.concatenate([old[:cut],np.zeros(sr,dtype=np.float32),mix[:cut].astype(np.float32)])
    write(a.output/'00-previous-then-legato.wav',sr,pair)
    _,actual=read(a.output/'gymnopedie-legato.wav');_,l=read(a.output/'legato-melody.wav')
    assert np.max(abs(actual-l-chorus))<1e-7
    rms_db=20*np.log10(np.linalg.norm(actual.astype(float))/np.linalg.norm(old.astype(float)))
    assert abs(rms_db)<.001
    for i,join in enumerate(joins[:-1]):
        if join:assert abs(transitions[i]['end_seconds']-transitions[i+1]['start_seconds']-.12)<2/sr
    assert previous_hash==hashlib.sha256(previous_path.read_bytes()).hexdigest()
    assert source_hash==hashlib.sha256(source.read_bytes()).hexdigest()
    if alternate is not None:assert alternate_hash==hashlib.sha256(alternate_path.read_bytes()).hexdigest()
    result=dict(phrase_vowels=a.phrase_vowels or 'u,u,u,u',alternate_source_sha256=alternate_hash,seconds=len(old)/sr,previous_sha256=previous_hash,source_sha256=source_hash,
        source_unchanged=True,previous_bytes_identical=True,chorus_bytes_identical=True,
        rms_difference_db=float(rms_db),melody_gain_db=float(20*np.log10(gain)),
        overlap_seconds=.12,joined_transitions=sum(joins),transitions=transitions,
        method='voiced-core continuations, 120ms complementary overlaps, phrase-boundary releases and pauses; no fabricated breath noise or pitch slides',
        reverb_unchanged=True,new_ai_generation=False,loops=False,listening_quality_verified=False)
    (a.output/'report.json').write_text(json.dumps(result,indent=2));print('PASS',result['seconds'],'seconds;',sum(joins),'joined transitions; chorus unchanged; RMS matched')

if __name__=='__main__':main()
