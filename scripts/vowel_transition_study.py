"""Smooth A/U coarticulation with one vibrato carrier and interpolated spectral envelopes."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from scipy.fft import rfft,irfft,next_fast_len
from scipy.ndimage import gaussian_filter
from scipy.signal import stft,istft,fftconvolve
from vowel_chord_study import read,write
from vowel_vibrato_study import room


def dry_from_wet(x,sr):
    ir=room(sr);n=next_fast_len(2*(len(x)+len(ir)))
    y=irfft(rfft(x.astype(float),n)/(1+.1*rfft(ir,n)),n)[:len(x)]
    assert np.max(abs(y+.1*fftconvolve(y,ir)[:len(y)]-x))<1e-7
    return y


def transform(x,sr):return stft(x,fs=sr,nperseg=1024,noverlap=896,boundary='zeros',padded=True)

def restore(z,sr,length):
    _,x=istft(z,fs=sr,nperseg=1024,noverlap=896,boundary=True)
    return x[:length]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--previous',type=Path,required=True);p.add_argument('--u-carrier',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    paths=dict(old=a.previous/'gymnopedie-phrase-vowels.wav',lead=a.previous/'phrase-melody.wav',
        chorus=a.previous/'unchanged-chorus.wav',metadata=a.previous/'report.json',carrier=a.u_carrier/'vibrato-melody.wav')
    hashes={k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in paths.items()}
    sr,old=read(paths['old']);_,lead=read(paths['lead']);_,chorus=read(paths['chorus']);_,u=read(paths['carrier'])
    assert sr==24000 and len(old)==len(lead)==len(chorus)==len(u)
    metadata=json.loads(paths['metadata'].read_text());carrier=dry_from_wet(u,sr);target=dry_from_wet(lead,sr)
    f,t,z=transform(carrier,sr);_,_,original=transform(target,sr)
    identity=restore(z,sr,len(carrier));identity_error=float(np.max(abs(identity-carrier)));assert identity_error<1e-7
    # Smooth envelopes instead of mixing independently pitched waveforms. Retain one carrier's phase/vibrato.
    floor=1e-7
    carrier_env=gaussian_filter(np.abs(z),sigma=(7,2),mode='nearest')+floor
    target_env=gaussian_filter(np.abs(original),sigma=(7,2),mode='nearest')+floor
    log_ratio=np.clip(np.log(target_env/carrier_env),-np.log(3),np.log(3))
    weight=np.zeros(len(t));switches=[]
    for phrase in range(1,4):
        events=[e for e in metadata['phrase_transitions'] if int(e['beat']//12)==phrase]
        first=min(events,key=lambda e:e['start_seconds'])
        start=first['start_seconds']+.08;end=start+.70
        phase=np.clip((t-start)/(end-start),0,1);smooth=phase*phase*(3-2*phase)
        weight=weight+(1 if phrase%2 else -1)*smooth
        switches.append(dict(phrase=phrase+1,from_vowel='u' if phrase%2 else 'a',to_vowel='a' if phrase%2 else 'u',start_seconds=start,end_seconds=end))
    weight=np.clip(weight,0,1)
    # Extend A's envelope gently into switching windows, avoiding a sudden timbral jump at note attack.
    hard_a=np.zeros(len(t),dtype=bool)
    for e in metadata['phrase_transitions']:
        if e['vowel']=='a':hard_a|=(t>=e['start_seconds'])&(t<=e['end_seconds'])
    energy=np.sqrt(np.sum(abs(original)**2,axis=0));valid=hard_a&(energy>max(energy.max()*.025,1e-5))
    assert np.count_nonzero(valid)>10
    a_ratio=np.empty_like(log_ratio)
    for k in range(len(f)):a_ratio[k]=np.interp(t,t[valid],log_ratio[k,valid])
    a_ratio=gaussian_filter(a_ratio,sigma=(0,3),mode='nearest')
    modified=z*np.exp(a_ratio*weight[None,:])
    # Keep the existing large-scale performance envelope without per-frame jumps.
    desired=np.sqrt(np.sum(abs(original)**2,axis=0));actual=np.sqrt(np.sum(abs(modified)**2,axis=0))
    level=gaussian_filter(np.clip(desired/(actual+1e-8),.55,1.8),sigma=5)
    modified*=level[None,:]
    dry=restore(modified,sr,len(carrier));ir=room(sr);wet=dry+.1*fftconvolve(dry,ir)[:len(dry)]
    aa=np.mean(wet**2);bb=2*np.mean(wet*chorus);cc=np.mean(chorus.astype(float)**2)-np.mean(old.astype(float)**2)
    gain=(-bb+np.sqrt(bb*bb-4*aa*cc))/(2*aa);wet*=gain;mix=wet+chorus
    assert np.max(abs(mix))<10**(-3/20)
    write(a.output/'gymnopedie-smooth-vowels.wav',sr,mix.astype(np.float32));write(a.output/'smooth-melody.wav',sr,wet.astype(np.float32))
    shutil.copyfile(paths['old'],a.output/'previous-version.wav');shutil.copyfile(paths['chorus'],a.output/'unchanged-chorus.wav')
    begin,finish=round(8.3*sr),round(23*sr)
    pair=np.concatenate([old[begin:finish],np.zeros(sr,dtype=np.float32),mix[begin:finish].astype(np.float32)])
    write(a.output/'00-previous-then-smooth.wav',sr,pair)
    np.savez_compressed(a.output/'vowel-controls.npz',frame_seconds=t,a_weight=weight)
    _,out=read(a.output/'gymnopedie-smooth-vowels.wav');_,outlead=read(a.output/'smooth-melody.wav')
    assert np.max(abs(out-outlead-chorus))<1e-7
    difference=20*np.log10(np.linalg.norm(out.astype(float))/np.linalg.norm(old.astype(float)));assert abs(difference)<.001
    assert np.max(abs(np.diff(weight)))<.02
    for k,path in paths.items():assert hashes[k]==hashlib.sha256(path.read_bytes()).hexdigest()
    assert paths['old'].read_bytes()==(a.output/'previous-version.wav').read_bytes()
    assert paths['chorus'].read_bytes()==(a.output/'unchanged-chorus.wav').read_bytes()
    report=dict(seconds=len(old)/sr,source_hashes=hashes,sources_unchanged=True,chorus_bytes_identical=True,previous_bytes_identical=True,
        switches=switches,method='single U-phase carrier with gradual A spectral-envelope transfer, 700ms smoothstep coarticulation, original room restored',
        spectrum_ratio_limit_db=float(20*np.log10(3)),stft_identity_error=identity_error,rms_difference_db=float(difference),melody_gain_db=float(20*np.log10(gain)),
        original_vibrato_carrier=True,new_ai_generation=False,listening_quality_verified=False)
    (a.output/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

if __name__=='__main__':main()
