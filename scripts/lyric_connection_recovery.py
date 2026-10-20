"""Diagnostic, speech-led lyric recovery: retain complete utterances and natural durations.
Not a successful sung-lyric rendition. No mora cuts, time stretch or pitch correction.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.signal import stft,istft,fftconvolve,butter,sosfiltfilt
from vowel_chord_study import read,write,active_mask
from vowel_transition_study import dry_from_wet
from vowel_vibrato_study import room,modulate
from vowel_expressive_gymnopedie import phrase_gain


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--speech',type=Path,required=True);p.add_argument('--previous',type=Path,required=True)
    p.add_argument('--phrases',type=Path,required=True);p.add_argument('--vowel-fill',type=Path,required=True)
    p.add_argument('--breath',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False);sr=24000
    oldpath=a.previous/'gymnopedie-lyrics-register-phrasing.wav';choruspath=a.previous/'unchanged-chorus.wav'
    hashes=dict(old=hashlib.sha256(oldpath.read_bytes()).hexdigest(),chorus=hashlib.sha256(choruspath.read_bytes()).hexdigest(),fill=hashlib.sha256(a.vowel_fill.read_bytes()).hexdigest())
    rate,old=read(oldpath);_,chorus=read(choruspath);assert rate==sr
    _,vowel=read(a.vowel_fill);assert len(vowel)==len(old)
    metadata=json.loads((a.phrases/'report.json').read_text());speech=json.loads((a.speech/'report.json').read_text())
    assert speech['reference_unchanged'] and not speech['audio_sent_to_external_service']
    track=np.zeros(len(old));voice_gate=np.zeros(len(old));vibrato_gate=np.zeros(len(old));trials=[];units=[]
    for i,trial in enumerate(speech['trials']):
        path=a.speech/trial['file'];digest=hashlib.sha256(path.read_bytes()).hexdigest()
        rate,x=read(path);assert rate==sr
        # Whole utterance: no internal boundaries, clipping, retiming or intonation replacement.
        gain=.055/np.sqrt(np.mean(x[active_mask(x,sr)].astype(float)**2))
        y=x.astype(float)*gain
        events=[n for n in metadata['phrase_transitions'] if int(n['beat']//12)==i]
        first=min(n['start_seconds'] for n in events)
        strength=phrase_gain(i*12+3)*.82
        onset=round(first*sr);track[onset:onset+len(y)]+=y*strength
        envelope=gaussian_filter1d(x.astype(float)**2,sr*.018)**.5
        gate=np.clip(envelope/max(float(envelope.max())*.14,1e-6),0,1)
        voice_gate[onset:onset+len(y)]=gate
        local=np.arange(len(y))/sr
        vibrato_gate[onset:onset+len(y)]=gate*np.clip((local-.28)/.38,0,1)
        units.append((x,y*strength))
        assert digest==hashlib.sha256(path.read_bytes()).hexdigest()
        trials.append(dict(text=trial['text'],source_sha256=digest,seconds=len(x)/sr,
            output_frames=len(y),input_frames=len(x),start_seconds=first,source_intonation_retained=True))
    t=np.arange(len(track))/sr;gate=vibrato_gate
    # Only gentle existing vibrato; original speech intonation is deliberately retained.
    rate=4.9+.16*np.sin(2*np.pi*.19*t)+.07*np.sin(2*np.pi*.071*t+.8)
    phase=2*np.pi*np.cumsum(rate)/sr;depth=10.5+1.5*np.sin(2*np.pi*.23*t+.4)
    cents=gate*(depth*np.sin(phase)+1.2*np.sin(2*np.pi*.37*t+1.3))
    spoken,displacement=modulate(track,sr,cents)
    spoken*=10**(gate*(.12*np.sin(phase+.6)+.07*np.sin(2*np.pi*.43*t))/20)
    # Keep the established register colouring, without changing pronunciation timing.
    f,ft,z=stft(spoken,fs=sr,nperseg=1024,noverlap=896)
    starts=np.array([n['start_seconds'] for n in metadata['phrase_transitions']]);pitches=np.array([n['pitch'] for n in metadata['phrase_transitions']])
    index=np.clip(np.searchsorted(starts,ft,side='right')-1,0,len(starts)-1)
    blend=np.clip((pitches[index]-64)/3,0,1);blend=gaussian_filter1d(blend*blend*(3-2*blend),12)
    chest=1+.14*np.exp(-.5*((f-600)/450)**2);light=(1+f/2300)**(-.30)
    _,coloured=istft(z*(chest[:,None]*(1-blend[None,:])+light[:,None]*blend[None,:]),fs=sr,nperseg=1024,noverlap=896)
    coloured=coloured[:len(track)]
    rng=np.random.default_rng(43);noise=sosfiltfilt(butter(3,[1300,7000],btype='bandpass',fs=sr,output='sos'),rng.standard_normal(len(track)))
    noise/=np.sqrt(np.mean(noise**2))
    coloured+=noise*np.sqrt(gaussian_filter1d(spoken**2,sr*.018))*np.interp(t,ft,blend)*.035
    # Complementary vowel melody carries the actual score between the short spoken lines.
    fill=dry_from_wet(vowel,sr)*.24*(1-voice_gate)
    breath=np.load(a.breath/'breath-controls.npz')['air_dry']
    ir=room(sr);spoken_wet=coloured+.1*fftconvolve(coloured,ir)[:len(track)]
    other=fill+breath;other+=.1*fftconvolve(other,ir)[:len(track)]
    lead=spoken_wet+other
    aa=np.mean(lead**2);bb=2*np.mean(lead*chorus);cc=np.mean(chorus.astype(float)**2)-np.mean(old.astype(float)**2)
    gain=(-bb+np.sqrt(bb*bb-4*aa*cc))/(2*aa)
    lead*=gain;mix=lead+chorus
    if np.max(abs(mix))>=10**(-3/20):raise ValueError('Insufficient headroom at matched RMS')
    write(a.output/'gymnopedie-connected-speech-study.wav',sr,mix.astype(np.float32))
    write(a.output/'connected-speech-melody.wav',sr,lead.astype(np.float32))
    write(a.output/'processed-spoken-lines.wav',sr,(spoken_wet*gain).astype(np.float32))
    shutil.copyfile(oldpath,a.output/'previous-lyrics.wav');shutil.copyfile(choruspath,a.output/'unchanged-chorus.wav')
    # Diagnostic first: untouched model output, lightly processed solo, then music.
    shutil.copyfile(a.speech/speech['trials'][0]['file'],a.output/'01-original-spoken-line.wav')
    begin=round(trials[0]['start_seconds']*sr);end=begin+len(units[0][0])
    write(a.output/'02-lightly-processed-line.wav',sr,(spoken_wet[begin:end]*gain).astype(np.float32))
    cut=11*sr;pair=np.concatenate([old[:cut],np.zeros(sr),mix[:cut]])
    write(a.output/'00-previous-then-connected-speech.wav',sr,pair.astype(np.float32))
    _,out=read(a.output/'gymnopedie-connected-speech-study.wav');_,l=read(a.output/'connected-speech-melody.wav')
    assert np.max(abs(out-l-chorus))<1e-7
    rms_db=20*np.log10(np.linalg.norm(out.astype(float))/np.linalg.norm(old.astype(float)));assert abs(rms_db)<.001
    assert oldpath.read_bytes()==(a.output/'previous-lyrics.wav').read_bytes()
    assert choruspath.read_bytes()==(a.output/'unchanged-chorus.wav').read_bytes()
    assert (a.speech/speech['trials'][0]['file']).read_bytes()==(a.output/'01-original-spoken-line.wav').read_bytes()
    assert all(tr['input_frames']==tr['output_frames'] for tr in trials)
    assert hashes['old']==hashlib.sha256(oldpath.read_bytes()).hexdigest() and hashes['chorus']==hashlib.sha256(choruspath.read_bytes()).hexdigest()
    assert hashes['fill']==hashlib.sha256(a.vowel_fill.read_bytes()).hexdigest()
    report=dict(seconds=len(old)/sr,trials=trials,source_hashes=hashes,chorus_bytes_identical=True,previous_bytes_identical=True,
        raw_first_line_bytes_identical=True,no_internal_utterance_cuts=True,time_stretch=False,pitch_correction=False,
        melody_is_sung=False,description='Diagnostic spoken lyrics over accepted vowel melody/chorus; not natural sung lyrics',
        register_colouring_retained=True,vibrato_peak_cents=float(np.max(abs(cents))),rms_difference_db=float(rms_db),
        gain_db=float(20*np.log10(gain)),max_time_displacement_ms=float(np.max(abs(displacement))/sr*1000),
        previous_user_quality='user reports disordered/unintelligible; not accepted as successful singing',
        speech_intelligibility_verified=False,new_ai_generation=False)
    (a.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print('PASS: speech-led diagnostic only; unchanged utterance durations; chorus identical; RMS matched')

if __name__=='__main__':main()
