"""Subtle delayed vibrato on an approved local legato melody; chorus unchanged."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from scipy.fft import rfft, irfft, next_fast_len
from scipy.ndimage import map_coordinates
from scipy.signal import fftconvolve
from vowel_chord_study import read, write


def room(sr):
    rng=np.random.default_rng(21);t=np.arange(round(1.5*sr))/sr
    ir=np.convolve(rng.standard_normal(len(t))*np.exp(-np.log(1000)*t/1.05),[.25,.5,.25],mode='same')
    ir/=np.sqrt(np.sum(ir**2));return np.pad(ir,(round(.025*sr),0))


def modulate(x,sr,cents):
    # Integrate instantaneous rate, retaining output length. Tiny resampling also moves formants slightly.
    displacement=np.cumsum(np.exp2(cents/1200)-1)
    coordinates=np.arange(len(x))+displacement
    return map_coordinates(x,[coordinates],order=3,mode='constant',cval=0,prefilter=True),displacement


def known_tone_check(sr):
    t=np.arange(2*sr)/sr;cents=12*np.sin(2*np.pi*5*t)
    signal=.2*np.sin(2*np.pi*220*t);out,disp=modulate(signal,sr,cents)
    assert len(out)==len(signal) and np.isfinite(out).all()
    # Positive zero crossings measure the actual time-varying pitch, independently of interpolation rate.
    indices=np.flatnonzero((out[:-1]<=0)&(out[1:]>0))
    crossings=indices-out[indices]/(out[indices+1]-out[indices])
    freq=sr/np.diff(crossings);mid=(crossings[:-1]+crossings[1:])/(2*sr)
    measured=1200*np.log2(freq/220);expected=12*np.sin(2*np.pi*5*mid)
    keep=(mid>.1)&(mid<1.9)
    error=float(np.sqrt(np.mean((measured[keep]-expected[keep])**2)))
    assert error<1
    return dict(rms_error_cents=error,measured_peak_cents=float(np.max(abs(measured[keep]))))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--previous',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    inputs={name:a.previous/name for name in ['gymnopedie-legato.wav','legato-melody.wav','unchanged-chorus.wav','report.json']}
    hashes={name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in inputs.items()}
    sr,old=read(inputs['gymnopedie-legato.wav']);_,lead=read(inputs['legato-melody.wav']);_,chorus=read(inputs['unchanged-chorus.wav'])
    assert sr==24000 and len(old)==len(lead)==len(chorus)
    previous=json.loads(inputs['report.json'].read_text());ir=room(sr)
    # Remove the known linear room before modulation, then restore it. Do not wobble the room tail.
    nfft=next_fast_len(2*(len(lead)+len(ir)))
    dry=irfft(rfft(lead.astype(float),nfft)/(1+.10*rfft(ir,nfft)),nfft)[:len(lead)]
    reconstructed=dry+.10*fftconvolve(dry,ir)[:len(dry)]
    reconstruction_error=float(np.max(abs(reconstructed-lead)));assert reconstruction_error<1e-7
    t=np.arange(len(dry))/sr;gate=np.zeros(len(dry))
    for event in previous['transitions']:
        local=t-event['start_seconds'];remaining=event['end_seconds']-t
        onset=np.clip((local-.28)/.38,0,1);offset=np.clip(remaining/.18,0,1)
        g=(.5-.5*np.cos(np.pi*onset))*(.5-.5*np.cos(np.pi*offset))
        gate=np.maximum(gate,g)
    rate=4.9+.16*np.sin(2*np.pi*.19*t)+.07*np.sin(2*np.pi*.071*t+.8)
    phase=2*np.pi*np.cumsum(rate)/sr
    depth=10.5+1.5*np.sin(2*np.pi*.23*t+.4)
    cents=gate*(depth*np.sin(phase)+1.2*np.sin(2*np.pi*.37*t+1.3))
    amplitude_db=gate*(.12*np.sin(phase+.6)+.07*np.sin(2*np.pi*.43*t))
    changed,displacement=modulate(dry,sr,cents)
    changed*=10**(amplitude_db/20)
    wet=changed+.10*fftconvolve(changed,ir)[:len(changed)]
    aa=np.mean(wet**2);bb=2*np.mean(wet*chorus);cc=np.mean(chorus.astype(float)**2)-np.mean(old.astype(float)**2)
    gain=(-bb+np.sqrt(bb*bb-4*aa*cc))/(2*aa)
    wet*=gain;mix=wet+chorus
    assert np.max(abs(mix))<10**(-3/20)
    write(a.output/'gymnopedie-vibrato.wav',sr,mix.astype(np.float32));write(a.output/'vibrato-melody.wav',sr,wet.astype(np.float32))
    write(a.output/'pitch-modulation-cents.wav',sr,(cents/100).astype(np.float32))
    shutil.copyfile(inputs['gymnopedie-legato.wav'],a.output/'previous-version.wav')
    shutil.copyfile(inputs['unchanged-chorus.wav'],a.output/'unchanged-chorus.wav')
    cut=round(10.6*sr);pair=np.concatenate([old[:cut],np.zeros(sr,dtype=np.float32),mix[:cut].astype(np.float32)])
    write(a.output/'00-previous-then-vibrato.wav',sr,pair)
    _,actual=read(a.output/'gymnopedie-vibrato.wav');_,l=read(a.output/'vibrato-melody.wav')
    assert np.max(abs(actual-l-chorus))<1e-7
    difference=20*np.log10(np.linalg.norm(actual.astype(float))/np.linalg.norm(old.astype(float)))
    assert abs(difference)<.001
    assert np.max(abs(cents))<14 and np.max(abs(amplitude_db))<.20
    assert np.all(cents[gate==0]==0)
    for name,path in inputs.items():assert hashes[name]==hashlib.sha256(path.read_bytes()).hexdigest()
    for src,dest in [('gymnopedie-legato.wav','previous-version.wav'),('unchanged-chorus.wav','unchanged-chorus.wav')]:assert inputs[src].read_bytes()==(a.output/dest).read_bytes()
    result=dict(seconds=len(old)/sr,source_hashes=hashes,source_unchanged=True,chorus_bytes_identical=True,previous_bytes_identical=True,
        vibrato_rate_hz=[float(rate.min()),float(rate.max())],pitch_peak_cents=float(np.max(abs(cents))),amplitude_peak_db=float(np.max(abs(amplitude_db))),
        onset_delay_seconds=.28,onset_ramp_seconds=.38,rms_difference_db=float(difference),melody_gain_db=float(20*np.log10(gain)),
        room_reconstruction_max_error=reconstruction_error,known_tone_check=known_tone_check(sr),
        max_time_displacement_ms=float(np.max(abs(displacement))/sr*1000),
        method='tiny cubic-interpolated rate modulation of dry melody, original linear room restored; no special formant compensation for sub-14-cent modulation',
        new_ai_generation=False,listening_quality_verified=False)
    (a.output/'report.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))

if __name__=='__main__':main()
