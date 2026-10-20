"""Quiet synthetic breath cues and phrase releases on the approved smooth-vowel study."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from scipy.signal import butter,sosfiltfilt,fftconvolve
from vowel_chord_study import read,write
from vowel_transition_study import dry_from_wet
from vowel_vibrato_study import room


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--previous',type=Path,required=True);p.add_argument('--phrases',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    paths=dict(old=a.previous/'gymnopedie-smooth-vowels.wav',lead=a.previous/'smooth-melody.wav',chorus=a.previous/'unchanged-chorus.wav',phrases=a.phrases/'report.json')
    hashes={k:hashlib.sha256(path.read_bytes()).hexdigest() for k,path in paths.items()}
    sr,old=read(paths['old']);_,lead=read(paths['lead']);_,chorus=read(paths['chorus'])
    assert sr==24000 and len(old)==len(lead)==len(chorus)
    dry=dry_from_wet(lead,sr);count=len(dry);time=np.arange(count)/sr
    # A restrained unvoiced cue, not a recording of the original speaker inhaling.
    rng=np.random.default_rng(31)
    noise=sosfiltfilt(butter(3,[850,6200],btype='bandpass',fs=sr,output='sos'),rng.standard_normal(count))
    noise/=np.sqrt(np.mean(noise**2))
    breath=np.zeros(count);voiced_gain=np.ones(count);events=[]
    metadata=json.loads(paths['phrases'].read_text())
    for phrase in range(4):
        notes=[e for e in metadata['phrase_transitions'] if int(e['beat']//12)==phrase]
        first=min(e['start_seconds'] for e in notes);last=max(e['end_seconds'] for e in notes)
        # Soft, short inhalation just before the entrance, with complete silence between cues.
        begin=max(0,first-.23);end=first-.045
        mask=(time>=begin)&(time<=end);position=(time[mask]-begin)/(end-begin)
        inhale=np.sin(np.pi*position)**1.7
        strength=[.0010,.00115,.00125,.0010][phrase]
        breath[mask]+=noise[mask]*inhale*strength
        # Let phonation give way to a little air, rather than simply closing the note gate.
        start=last-.34;finish=last+.12
        if phrase<3:
            next_head=min(e['start_seconds'] for e in metadata['phrase_transitions'] if int(e['beat']//12)==phrase+1)
            finish=min(finish,next_head-.27)  # Separate exhalation from the next inhalation cue.
        mask=(time>=start)&(time<=last);position=np.clip((time[mask]-start)/.34,0,1)
        voiced_gain[mask]*=1-.55*(position*position*(3-2*position))
        mask=(time>=start)&(time<=finish);position=(time[mask]-start)/(finish-start)
        exhale=(np.sin(np.pi*position)**1.4)*(1-.5*position)
        breath[mask]+=noise[mask]*exhale*.00085
        events.append(dict(phrase=phrase+1,inhale=[begin,end],release=[start,finish],voiced_end_gain=.45))
    softened=dry*voiced_gain
    ir=room(sr)
    phonation=softened+.1*fftconvolve(softened,ir)[:count]
    air=breath+.1*fftconvolve(breath,ir)[:count]
    candidate=phonation+air
    aa=np.mean(candidate**2);bb=2*np.mean(candidate*chorus);cc=np.mean(chorus.astype(float)**2)-np.mean(old.astype(float)**2)
    gain=(-bb+np.sqrt(bb*bb-4*aa*cc))/(2*aa)
    newlead=candidate*gain;mix=newlead+chorus
    assert np.max(abs(mix))<10**(-3/20)
    for name,x in [('gymnopedie-breath-phrasing.wav',mix),('breath-melody.wav',newlead),('synthetic-air-only.wav',air*gain)]:write(a.output/name,sr,x.astype(np.float32))
    shutil.copyfile(paths['old'],a.output/'previous-version.wav');shutil.copyfile(paths['chorus'],a.output/'unchanged-chorus.wav')
    begin,finish=round(8.3*sr),round(23*sr)
    pair=np.concatenate([old[begin:finish],np.zeros(sr,dtype=np.float32),mix[begin:finish].astype(np.float32)])
    write(a.output/'00-previous-then-breath-phrasing.wav',sr,pair)
    _,out=read(a.output/'gymnopedie-breath-phrasing.wav');_,outlead=read(a.output/'breath-melody.wav')
    assert np.max(abs(out-outlead-chorus))<1e-7
    rms_diff=20*np.log10(np.linalg.norm(out.astype(float))/np.linalg.norm(old.astype(float)));assert abs(rms_diff)<.001
    for k,path in paths.items():assert hashes[k]==hashlib.sha256(path.read_bytes()).hexdigest()
    assert paths['old'].read_bytes()==(a.output/'previous-version.wav').read_bytes()
    assert paths['chorus'].read_bytes()==(a.output/'unchanged-chorus.wav').read_bytes()
    cue_mask=np.zeros(count,dtype=bool)
    for e in events:
        for start,end in [e['inhale'],e['release']]:cue_mask|=(time>=start)&(time<=end)
    assert np.all(breath[~cue_mask]==0)
    for current,following in zip(events,events[1:]):assert current['release'][1]<following['inhale'][0]
    assert np.min(voiced_gain)>=.45-1e-10 and np.max(voiced_gain)==1
    controls=a.output/'breath-controls.npz';np.savez_compressed(controls,voiced_gain=voiced_gain,air_dry=breath)
    report=dict(seconds=count/sr,source_hashes=hashes,sources_unchanged=True,chorus_bytes_identical=True,previous_bytes_identical=True,
        events=events,noise_seed=31,synthetic_noise_band_hz=[850,6200],air_rms_dbfs=float(20*np.log10(np.sqrt(np.mean(air**2)))),
        air_to_voiced_rms_db=float(20*np.log10(np.linalg.norm(air)/np.linalg.norm(phonation))),rms_difference_db=float(rms_diff),melody_gain_db=float(20*np.log10(gain)),
        method='quiet shaped synthetic unvoiced cues before phrases; softened last 340ms and brief airy release; same vibrato, vowel transitions, tempo and room',
        lyrics=False,new_ai_generation=False,listening_quality_verified=False)
    (a.output/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

if __name__=='__main__':main()
