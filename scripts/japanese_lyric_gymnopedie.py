"""Local reference-conditioned speech-to-melody study, with approximate vocal-register colouring.
Not a singing model or a simulation of vocal-fold physiology.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
import numpy as np
from scipy.ndimage import gaussian_filter1d,median_filter
from scipy.signal import find_peaks,fftconvolve,butter,sosfiltfilt,stft,istft
from vowel_chord_study import read,write,active_mask
from vowel_vibrato_study import room,modulate
from vowel_expressive_gymnopedie import phrase_gain


def pitch_frames(x,sr):
    hop=round(.01*sr);width=round(.05*sr);lags=np.arange(round(sr/550),round(sr/145))
    positions=np.arange(0,max(1,len(x)-width+1),hop);pitches=[];quality=[];rms=[]
    for start in positions:
        y=x[start:start+width].astype(float);y-=y.mean();power=np.cumsum(np.r_[0,y*y])
        corr=np.correlate(y,y,mode='full')[len(y)-1:]
        denominator=power[len(y)-lags]+power[len(y)]-power[lags]
        nsdf=2*corr[lags]/np.maximum(denominator,1e-12)
        peaks,_=find_peaks(nsdf);best=int(np.argmax(nsdf))
        if len(peaks):
            candidates=peaks[nsdf[peaks]>.88*np.max(nsdf[peaks])]
            if len(candidates):best=int(candidates[0])
        lag=float(lags[best])
        if 0<best<len(nsdf)-1:
            den=nsdf[best-1]-2*nsdf[best]+nsdf[best+1]
            if abs(den)>1e-9:lag+=float(np.clip(.5*(nsdf[best-1]-nsdf[best+1])/den,-.5,.5))
        pitches.append(69+12*np.log2((sr/lag)/440));quality.append(nsdf[best]);rms.append(np.sqrt(np.mean(y*y)))
    times=(positions+width/2)/sr;pitches=np.array(pitches);quality=np.array(quality);rms=np.array(rms)
    voiced=(quality>.62)&(rms>max(.0005,rms.max()*.06))
    if np.count_nonzero(voiced)<5:raise ValueError('Not enough locally voiced speech to track')
    midi=median_filter(np.interp(times,times[voiced],pitches[voiced]),size=7,mode='nearest')
    return times,midi,voiced,rms


def trim(x,sr):
    # Preserve all words in the utterance, only removing outer silence.
    hop=round(.01*sr);env=np.array([np.sqrt(np.mean(x[i:i+hop]**2)) for i in range(0,len(x),hop)])
    active=np.flatnonzero(env>max(.0004,env.max()*.045))
    if not len(active):raise ValueError('Silent line')
    begin=max(0,active[0]*hop-round(.025*sr));end=min(len(x),(active[-1]+1)*hop+round(.045*sr))
    return x[begin:end].copy(),begin,end


def run(args):
    subprocess.run(['rubberband','-q',*args],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)



def mora_timing(x,sr,phrase,clock,events,start,finish,rhythmic=False):
    """Seven approximate mora units, with explicit score anchors and short retained onsets.
    Acoustic boundaries are heuristic, not forced-alignment results.
    """
    _,times,z=stft(x,fs=sr,nperseg=512,noverlap=392)
    magnitude=np.log1p(abs(z)*1000)
    novelty=np.r_[0,np.mean(abs(np.diff(magnitude,axis=1)),axis=0)]
    novelty=gaussian_filter1d(novelty,1)
    novelty/=max(float(np.max(novelty)),1e-8)
    duration=len(x)/sr;boundaries=[0.]
    for i in range(1,7):
        centre=duration*i/7
        candidates=np.flatnonzero((times>max(boundaries[-1]+.065,centre-.085))&(times<min(duration-.065*(7-i),centre+.085)))
        if len(candidates):
            score=novelty[candidates]-.45*((times[candidates]-centre)/.085)**2
            boundary=float(times[candidates[np.argmax(score)]])
        else:boundary=centre
        boundaries.append(boundary)
    boundaries.append(duration)
    score_beats=[[1,2,3,4,5,6,7],[12,13,14,15,16,17,18],
                 [25,26,27,28,29,30,31],[36,36.90,37,39,40,41,42]][phrase]
    if rhythmic:
        score_beats=[[1,1.5,2,2.5,5,5.5,6],[12,12.5,13,13.5,16,16.5,17],
                     [25,25.5,26,26.5,29,29.5,30],[36,36.85,37,39,39.5,40,40.5]][phrase]
    outputs=[float(np.interp(b,np.linspace(0,48,len(clock)),clock))+.15 for b in score_beats]+[finish]
    outputs[0]=start
    points=[(0.,start)]
    onset_lengths=[]
    for i in range(7):
        source_begin,source_end=boundaries[i:i+2]
        target_begin,target_end=outputs[i:i+2]
        # Preserve a compact attack/transition instead of stretching consonants across beats.
        attack=min(.065,.40*(source_end-source_begin),.35*(target_end-target_begin))
        if phrase==3 and i==1:attack=min(attack,.035)  # compact geminate closure
        if source_begin>points[-1][0]:points.append((source_begin,target_begin))
        points.append((source_begin+attack,target_begin+attack))
        points.append((source_end,target_end))
        onset_lengths.append(attack)
    clean=[]
    for source_time,target_time in points:
        if not clean or (source_time>clean[-1][0]+1e-8 and target_time>clean[-1][1]+1e-8):clean.append((source_time,target_time))
    return np.array(clean),dict(source_mora_boundaries_seconds=boundaries,target_mora_beats=score_beats,
        retained_onset_seconds=onset_lengths,target_mora_seconds=outputs[:-1],rhythmic_words=rhythmic,boundaries_verified=False)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--speech',type=Path,required=True);p.add_argument('--previous',type=Path,required=True)
    p.add_argument('--phrases',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--mora-grid',action='store_true',help='Approximate seven-mora score alignment, preserving short attacks')
    p.add_argument('--previous-lyrics',type=Path,help='Earlier lyric rendition for comparison')
    p.add_argument('--rhythmic-words',action='store_true',help='Compact eighth-note word groups and limited vowel holds')
    p.add_argument('--vowel-fill',type=Path,help='Previous wet vowel melody, used quietly between compact word groups')
    a=p.parse_args()
    if a.rhythmic_words:
        a.mora_grid=True
        if not a.vowel_fill:p.error('--rhythmic-words requires --vowel-fill')
    a.output.mkdir(parents=True,exist_ok=False);work=a.output/'render';work.mkdir();sr=24000
    speech_report=json.loads((a.speech/'report.json').read_text())
    assert speech_report['reference_unchanged'] and not speech_report['audio_sent_to_external_service']
    assert speech_report['all_generations_stopped_naturally']
    expected=['静かな夜に。','光が揺れる。','遠くの空へ。','そっとおやすみ。']
    assert [t['text'] for t in speech_report['trials']]==expected
    metadata=json.loads((a.phrases/'report.json').read_text())
    oldpath=(a.previous_lyrics/'gymnopedie-lyrics-register-phrasing.wav') if a.previous_lyrics else (a.previous/'gymnopedie-breath-phrasing.wav');choruspath=a.previous/'unchanged-chorus.wav'
    hashes=dict(previous=hashlib.sha256(oldpath.read_bytes()).hexdigest(),chorus=hashlib.sha256(choruspath.read_bytes()).hexdigest())
    rate,old=read(oldpath);_,chorus=read(choruspath);assert rate==sr
    track=np.zeros(len(old));notes=metadata['phrase_transitions'];reports=[]
    word_gate=np.zeros(len(old));clarity_gate=np.zeros(len(old))
    # Exactly the same common tempo curve as the accepted vowel performance.
    beat_grid=np.linspace(0,48,4801);spb=(60/72)*(1+.025*np.cos(2*np.pi*beat_grid/12)+.10*np.clip((beat_grid-42)/6,0,1))
    clock=np.r_[0,np.cumsum((spb[1:]+spb[:-1])*.005)]
    all_time=np.arange(len(old))/sr
    def target_pitch(time):
        mids=np.array([n['start_seconds'] for n in notes]);vals=np.array([n['pitch'] for n in notes])
        indices=np.clip(np.searchsorted(mids,time,side='right')-1,0,len(vals)-1)
        return vals[indices]
    for phrase,trial in enumerate(speech_report['trials']):
        path=a.speech/trial['file'];before=hashlib.sha256(path.read_bytes()).hexdigest()
        rate,raw=read(path);assert rate==sr
        x,begin,end=trim(raw,sr);times,midi,voiced,energy=pitch_frames(x,sr)
        events=[n for n in notes if int(n['beat']//12)==phrase]
        start=min(n['start_seconds'] for n in events);finish=max(n['end_seconds'] for n in events)
        duration=finish-start
        # Stretch voiced nuclei more than consonants, using an explicit offline time map.
        density=.24+.76*gaussian_filter1d(voiced.astype(float),1.2)
        cumulative=np.cumsum(density);cumulative=(cumulative-cumulative[0])/(cumulative[-1]-cumulative[0])
        desired_time=start+cumulative*duration
        mora_report=None
        if a.mora_grid:
            anchors,mora_report=mora_timing(x,sr,phrase,clock,events,start,finish,rhythmic=a.rhythmic_words)
            desired_time=np.interp(times,anchors[:,0],anchors[:,1])
        requested=target_pitch(desired_time)
        correction=gaussian_filter1d(np.clip(requested-midi,-16,12),1.1)
        pad=round(.15*sr);padded=np.pad(x,(pad,pad)).astype(np.float32)
        src=work/f'{phrase}-speech.wav';pitched=work/f'{phrase}-pitched.wav';pmap=work/f'{phrase}-pitchmap.txt'
        write(src,sr,padded)
        rows=[(0,float(correction[0]))]+[(round(t*sr)+pad,float(c)) for t,c in zip(times,correction)]+[(len(padded)-1,float(correction[-1]))]
        pmap.write_text(''.join(f'{i} {c:.7f}\n' for i,c in rows))
        run(['-3','-F','--pitchmap',str(pmap),'-t','1',str(src),str(pitched)])
        rate,y=read(pitched);assert rate==sr
        # Realtime pitch map may vary output length; keep original placement and record the difference.
        delta=len(y)-len(padded);body=y[pad:pad+len(x)]
        if len(body)<len(x):body=np.pad(body,(0,len(x)-len(body)))
        unpadded=work/f'{phrase}-corrected.wav';write(unpadded,sr,body.astype(np.float32))
        tmap=work/f'{phrase}-timemap.txt';points=[(0,0)]
        map_times,map_outputs=(anchors[:,0],anchors[:,1]-start) if a.mora_grid else (times,desired_time-start)
        for src_time,out_time in zip(map_times,map_outputs):
            source_frame=round(src_time*sr);output_frame=round(out_time*sr)
            if source_frame>points[-1][0] and output_frame>points[-1][1]:points.append((source_frame,output_frame))
        target_count=round(duration*sr)
        points=[v for v in points if v[0]<len(body) and v[1]<target_count];points.append((len(body),target_count))
        tmap.write_text(''.join(f'{i} {j}\n' for i,j in points))
        stretched=work/f'{phrase}-stretched.wav'
        run(['-3','-F','-t',str(target_count/len(body)),'--timemap',str(tmap),str(unpadded),str(stretched)])
        rate,y=read(stretched);assert rate==sr
        y=y[:target_count]
        if len(y)<target_count:y=np.pad(y,(0,target_count-len(y)))
        refinement=None
        if a.mora_grid:
            # Conservative second pass after retiming, to reduce residual pitch errors.
            pt,pm,pv,pe=pitch_frames(y,sr)
            desired_pitch=target_pitch(start+pt)
            residual=desired_pitch-pm
            residual-=12*np.round(residual/12)
            residual=gaussian_filter1d(np.clip(residual,-3,3),4)
            # Limit correction in weak/unvoiced consonants.
            residual*=gaussian_filter1d(pv.astype(float),2)
            refined_map=work/f'{phrase}-refine-map.txt';refine_in=work/f'{phrase}-refine-in.wav';refine_out=work/f'{phrase}-refine-out.wav'
            pad2=round(.15*sr);write(refine_in,sr,np.pad(y,(pad2,pad2)).astype(np.float32))
            refined_map.write_text('0 0\n'+''.join(f'{round(t*sr)+pad2} {c:.7f}\n' for t,c in zip(pt,residual))+f'{len(y)+2*pad2-1} 0\n')
            run(['-3','-F','--pitchmap',str(refined_map),'-t','1',str(refine_in),str(refine_out)])
            rr,ry=read(refine_out);assert rr==sr
            y=ry[pad2:pad2+target_count]
            if len(y)<target_count:y=np.pad(y,(0,target_count-len(y)))
            refinement=dict(max_correction_semitones=float(np.max(abs(residual))),measured_before_median_abs_error=float(np.median(abs((desired_pitch-pm)[pv]))))
        y=y.astype(float);y*=.055/np.sqrt(np.mean(y[active_mask(y,sr)]**2))
        pos=np.linspace(0,1,len(y));beats=np.interp(start+pos*duration-.15,clock,beat_grid)
        envelope=np.array([phrase_gain(b) for b in beats])
        ramp=min(round(.07*sr),len(y)//4);envelope[:ramp]*=np.linspace(0,1,ramp)
        release=round(.33*sr);envelope[-release:]*=np.linspace(1,0,release)**1.3
        articulation=None
        if a.rhythmic_words:
            local_time=start+np.arange(len(y))/sr;local_gate=np.zeros(len(y));unit_events=[]
            positions=mora_report['target_mora_seconds']
            for unit,onset_time in enumerate(positions):
                next_time=positions[unit+1] if unit<6 else finish
                # Only the word endings retain a longer vowel; inner morae move briskly.
                word_end=(unit==3 if phrase<3 else unit==2)
                wanted=.75 if unit==6 else (.52 if word_end else .38)
                if phrase==3 and unit==1:wanted=.055  # keep Japanese geminate closure compact
                hold=min(wanted,max(.05,next_time-onset_time-.018))
                progress=(local_time-onset_time)/hold
                window=np.where((progress>=0)&(progress<=1),1.,0.)
                attack=np.clip((local_time-onset_time)/.008,0,1)
                release=np.clip((onset_time+hold-local_time)/min(.075,hold*.3),0,1)
                window*=np.sin(attack*np.pi/2)**2*np.sin(release*np.pi/2)**2
                local_gate=np.maximum(local_gate,window)
                absolute=np.arange(len(old))/sr-onset_time
                transient=np.where((absolute>=0)&(absolute<.065),np.sin(np.pi*np.clip(absolute/.065,0,1))**2,0.)
                clarity_gate=np.maximum(clarity_gate,transient)
                unit_events.append(dict(mora=unit+1,onset_seconds=onset_time,hold_seconds=hold))
            envelope*=local_gate
            offset=round(start*sr);word_gate[offset:offset+len(y)]=np.maximum(word_gate[offset:offset+len(y)],local_gate)
            articulation=unit_events
        y*=envelope*.65
        onset=round(start*sr);track[onset:onset+len(y)]+=y
        assert before==hashlib.sha256(path.read_bytes()).hexdigest()
        reports.append(dict(text=trial['text'],source_sha256=before,trim_frames=[int(begin),int(end)],source_seconds=len(x)/sr,
            output_seconds=duration,start_seconds=start,source_median_midi=float(np.median(midi)),
            pitch_correction_semitones=[float(correction.min()),float(correction.max())],pitchmap_frame_delta=delta,
            phoneme_alignment='approximate mora score anchors with retained onsets' if a.mora_grid else 'voicing-weighted time map, no forced phoneme alignment',
            mora_timing=mora_report,pitch_refinement=refinement,articulation=articulation,intelligibility_verified=False))
    # Reapply the same shallow vibrato/air-pressure modulation used in the accepted melody.
    gate=np.zeros(len(track))
    for n in notes:
        local=all_time-n['start_seconds'];remaining=n['end_seconds']-all_time
        g=(.5-.5*np.cos(np.pi*np.clip((local-.28)/.38,0,1)))*(.5-.5*np.cos(np.pi*np.clip(remaining/.18,0,1)))
        gate=np.maximum(gate,g)
    rate=4.9+.16*np.sin(2*np.pi*.19*all_time)+.07*np.sin(2*np.pi*.071*all_time+.8)
    phase=2*np.pi*np.cumsum(rate)/sr;depth=10.5+1.5*np.sin(2*np.pi*.23*all_time+.4)
    cents=gate*(depth*np.sin(phase)+1.2*np.sin(2*np.pi*.37*all_time+1.3))
    neutral,_=modulate(track,sr,cents)
    neutral*=10**(gate*(.12*np.sin(phase+.6)+.07*np.sin(2*np.pi*.43*all_time))/20)
    fill_hash=None
    if a.rhythmic_words:
        from vowel_transition_study import dry_from_wet
        fill_hash=hashlib.sha256(a.vowel_fill.read_bytes()).hexdigest()
        fill_sr,fill=read(a.vowel_fill);assert fill_sr==sr and len(fill)==len(neutral)
        fill_dry=dry_from_wet(fill,sr)
        neutral+=.24*(1-word_gate)*fill_dry
    # Approximate register by spectral tilt/body and restrained aspiration; pitch itself stays unchanged.
    f,ft,z=stft(neutral,fs=sr,nperseg=1024,noverlap=896)
    midi=target_pitch(ft);blend=np.clip((midi-64)/3,0,1);blend=blend*blend*(3-2*blend)
    blend=gaussian_filter1d(blend,12)
    chest=1+.14*np.exp(-.5*((f-600)/450)**2)
    light=(1+f/2300)**(-.30)
    colour=chest[:,None]*(1-blend[None,:])+light[:,None]*blend[None,:]
    _,coloured=istft(z*colour,fs=sr,nperseg=1024,noverlap=896)
    coloured=coloured[:len(track)]
    rng=np.random.default_rng(43);noise=sosfiltfilt(butter(3,[1300,7000],btype='bandpass',fs=sr,output='sos'),rng.standard_normal(len(track)))
    noise/=np.sqrt(np.mean(noise**2))
    envelope=gaussian_filter1d(neutral**2,sr*.018)**.5
    register=np.interp(all_time,ft,blend)
    airy=coloured+noise*envelope*register*.035
    if a.rhythmic_words:
        # A small, time-limited presence lift at inferred attacks; not blanket treble boost.
        band=butter(2,[1500,4800],btype='bandpass',fs=sr,output='sos')
        airy+=.28*clarity_gate*sosfiltfilt(band,airy)
        neutral+=.28*clarity_gate*sosfiltfilt(band,neutral)
        assert fill_hash==hashlib.sha256(a.vowel_fill.read_bytes()).hexdigest()
        np.savez_compressed(a.output/'articulation-controls.npz',word_gate=word_gate,clarity_gate=clarity_gate)
    # Preserve the accepted breath cues exactly, as a separate quiet layer.
    controls=np.load(a.previous/'breath-controls.npz');breath=controls['air_dry']
    ir=room(sr)
    versions={};outputs={}
    for name,dry in [('neutral-register',neutral+breath),('register-phrasing',airy+breath)]:
        wet=dry+.1*fftconvolve(dry,ir)[:len(dry)]
        aa=np.mean(wet**2);bb=2*np.mean(wet*chorus);cc=np.mean(chorus.astype(float)**2)-np.mean(old.astype(float)**2)
        gain=(-bb+np.sqrt(bb*bb-4*aa*cc))/(2*aa);wet*=gain;mix=wet+chorus
        assert np.max(abs(mix))<10**(-3/20)
        write(a.output/f'gymnopedie-lyrics-{name}.wav',sr,mix.astype(np.float32))
        write(a.output/f'lyrics-{name}-melody.wav',sr,wet.astype(np.float32))
        assert abs(20*np.log10(np.linalg.norm(mix)/np.linalg.norm(old.astype(float))))<.001
        versions[name]=dict(gain_db=float(20*np.log10(gain)),peak=float(np.max(abs(mix))));outputs[name]=mix
    for name in versions:
        _,m=read(a.output/f'gymnopedie-lyrics-{name}.wav');_,l=read(a.output/f'lyrics-{name}-melody.wav')
        assert np.max(abs(m-l-chorus))<1e-7
    assert hashes['previous']==hashlib.sha256(oldpath.read_bytes()).hexdigest()
    assert hashes['chorus']==hashlib.sha256(choruspath.read_bytes()).hexdigest()
    previous_copy=a.output/('previous-lyrics.wav' if a.previous_lyrics else 'previous-vowels.wav')
    shutil.copyfile(oldpath,previous_copy);shutil.copyfile(choruspath,a.output/'unchanged-chorus.wav')
    end=round(11*sr);pair=np.concatenate([old[:end],np.zeros(sr),outputs['register-phrasing'][:end]])
    write(a.output/('00-previous-then-clear-lyrics.wav' if a.previous_lyrics else '00-vowels-then-japanese-lyrics.wav'),sr,pair.astype(np.float32))
    (a.output/'lyrics.txt').write_text('静かな夜に\n光が揺れる\n遠くの空へ\nそっとおやすみ\n')
    assert oldpath.read_bytes()==previous_copy.read_bytes()
    assert choruspath.read_bytes()==(a.output/'unchanged-chorus.wav').read_bytes()
    report=dict(seconds=len(old)/sr,lyrics=expected,reference_sha256=speech_report['reference_sha256'],reference_mode=speech_report['mode'],
        source_hashes=hashes,trials=reports,versions=versions,chorus_bytes_identical=True,
        mora_grid=a.mora_grid,rhythmic_words=a.rhythmic_words,vowel_fill_sha256=fill_hash,register_transition_midi=[64,67],register_transition_notes=['E4','G4'],
        register_method='DSP approximation: low-mid body on lower notes, lighter spectral tilt and a little aspiration on upper notes; not trained chest/falsetto singing',
        speech_conditioned_on_same_reference=True,singing_model=False,source_f0_and_lyric_alignment_approximate=True,
        shallow_vibrato_retained=True,lyrics_intelligibility_verified=False,speaker_identity_verified=False)
    (a.output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print('PASS: local Japanese lyric study; 43.25 seconds; neutral/register versions; chorus identical; RMS matched')

if __name__=='__main__':main()
