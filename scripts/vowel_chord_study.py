"""Offline three-note chord study from approved local AI vowel samples.
Uses installed Rubber Band R3 with formant preservation; no new AI or app edits.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import numpy as np
from scipy.io import wavfile


def read(path):
    sr, x = wavfile.read(path)
    if np.issubdtype(x.dtype, np.integer):
        x = x.astype(np.float32) / float(2**(np.iinfo(x.dtype).bits - 1))
    else:
        x = x.astype(np.float32)
    if x.ndim != 1 or not x.size or not np.isfinite(x).all():
        raise ValueError('Expected finite mono audio')
    return sr, x


def active_mask(x, sr):
    hop = round(sr * .01)
    rms = np.array([np.sqrt(np.mean(x[i:i+hop]**2)) for i in range(0, len(x), hop)])
    active = rms > max(.0002, float(rms.max()) * .04)
    mask = np.repeat(active, hop)[:len(x)]
    if not mask.any():
        raise ValueError('Silent input')
    return mask


def shift(x, sr, semitones, directory, prefix):
    pad = round(sr * .15)
    padded = np.pad(x, (pad, pad)).astype(np.float32)
    source, destination = directory/(prefix+'-padded.wav'), directory/(prefix+'-shifted.wav')
    wavfile.write(source, sr, padded)
    subprocess.run(['rubberband', '-q', '-3', '-F', '-t', '1', '-p', str(semitones), str(source), str(destination)], check=True)
    actual_sr, y = read(destination)
    if actual_sr != sr or len(y) != len(padded):
        raise ValueError('Offline pitch shift did not retain exact duration')
    return y[pad:pad+len(x)].copy()


def write(path, sr, x):
    x = np.asarray(x, dtype=np.float32)
    if not np.isfinite(x).all() or not .0001 < np.max(abs(x)) < 1:
        raise ValueError('Nonfinite, silent or clipping output')
    wavfile.write(path, sr, x)
    actual_sr, y = read(path)
    assert actual_sr == sr and np.array_equal(x, y)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    if args.output.exists():
        raise SystemExit('Use a fresh output directory')
    if not shutil.which('rubberband'):
        raise SystemExit('Installed rubberband CLI required')
    args.output.mkdir(parents=True)
    work = args.output/'layers';work.mkdir()
    version = subprocess.check_output(['rubberband','--version'], text=True, stderr=subprocess.STDOUT).strip()
    # Known-pitch check verifies local CLI pitch/duration behavior before voice work.
    sr = 24000
    sine = (.2*np.sin(2*np.pi*220*np.arange(sr)/sr)).astype(np.float32)
    checks=[]
    for steps in [-4,3]:
        y = shift(sine, sr, steps, work, 'check-'+str(steps))
        segment = y[round(.2*sr):round(.8*sr)]
        magnitude = abs(np.fft.rfft(segment*np.hanning(len(segment)), n=131072))
        frequency = np.fft.rfftfreq(131072, 1/sr)[np.argmax(magnitude)]
        expected = 220*2**(steps/12)
        cents = 1200*np.log2(frequency/expected)
        if abs(cents)>10:
            raise ValueError('Known pitch test failed')
        checks.append(dict(semitones=steps, frequency=float(frequency), expected=expected, cents=float(cents)))
    reports, sequence = [], []
    for vowel in ['a','u']:
        source = args.input/(vowel+'-long.wav')
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        sr, solo = read(source)
        if sr!=24000 or not .2<len(solo)/sr<2:
            raise ValueError('Unexpected approved vowel format')
        active = active_mask(solo, sr)
        solo_rms = float(np.sqrt(np.mean(solo[active].astype(np.float64)**2)))
        voices, layers = [], []
        for steps in [-4,0,3]:
            voice = solo.copy() if steps==0 else shift(solo,sr,steps,work,vowel+'-'+str(steps))
            rms = float(np.sqrt(np.mean(voice[active].astype(np.float64)**2)))
            if rms<.0001:
                raise ValueError('Silent pitch layer')
            gain = solo_rms/rms
            voice = voice*gain
            write(work/(vowel+'-voice-'+str(steps)+'.wav'),sr,voice)
            voices.append(voice)
            layers.append(dict(semitones=steps, gain_db=20*np.log10(gain), unprocessed=steps==0))
        chord = (np.sum(voices,axis=0)/3).astype(np.float32)
        chord_rms = float(np.sqrt(np.mean(chord[active].astype(np.float64)**2)))
        gain = solo_rms/chord_rms
        chord = (chord*gain).astype(np.float32)
        if np.max(abs(chord))>=10**(-3/20):
            raise ValueError('Insufficient chord headroom')
        solo_out=args.output/(vowel+'-single.wav');shutil.copyfile(source,solo_out)
        assert source.read_bytes()==solo_out.read_bytes()
        write(args.output/(vowel+'-major-chord.wav'),sr,chord)
        gap=np.zeros(round(sr*.7),dtype=np.float32)
        pair=np.concatenate([solo,gap,chord])
        write(args.output/(vowel+'-single-then-chord.wav'),sr,pair)
        sequence.extend([solo,gap,chord,gap])
        assert before==hashlib.sha256(source.read_bytes()).hexdigest()
        reports.append(dict(vowel=vowel,source_sha256=before,source_unchanged=True,solo_bytes_identical=True,
            seconds=len(solo)/sr,sample_rate=sr,intervals=[-4,0,3],layers=layers,
            final_mix_gain_db=20*np.log10(gain),solo_active_rms_dbfs=20*np.log10(solo_rms),
            chord_active_rms_dbfs=20*np.log10(float(np.sqrt(np.mean(chord[active].astype(np.float64)**2)))),
            peak_dbfs=20*np.log10(float(np.max(abs(chord)))),phoneme_and_timbre_verified_by_listener=False))
    combined=np.concatenate(sequence[:-1]);write(args.output/'00-single-chord-a-u.wav',24000,combined)
    (args.output/'report.json').write_text(json.dumps(dict(tool='Rubber Band '+version,
        formant_preservation=True,offline_r3=True,pitch_check=checks,
        method='Major triad: original unchanged middle voice, -4 and +3 semitone additions; exact source duration; RMS match; mono; no loop, reverb, delay, EQ or new AI generation',
        order=['single a','chord a','single u','chord u'],gap_seconds=.7,sequence_seconds=len(combined)/24000,trials=reports),indent=2))
    print(json.dumps(reports,indent=2))


if __name__=='__main__':
    main()
