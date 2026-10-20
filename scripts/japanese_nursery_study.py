"""Separate lyric-layout study using the installed macOS Kyoko voice.
Not the supplied speaker. No voice cloning, cloud service or model downloads.
"""
import argparse, hashlib, json, subprocess
from pathlib import Path
import numpy as np
import soundfile as sf
from voice_vowel_song import psola, fade, write


def voiced_region(x, sr):
    w, hop = 640, 160
    if len(x) < w:
        raise ValueError('Short TTS mora')
    frames = np.lib.stride_tricks.sliding_window_view(x, w)[::hop].copy()
    frames -= frames.mean(axis=1, keepdims=True)
    ac = np.fft.irfft(abs(np.fft.rfft(frames * np.hanning(w), n=2048))**2, n=2048)
    lags = np.arange(32, 124)
    score = ac[:, lags] / ac[:, 0, None].clip(1e-15)
    best = score.argmax(axis=1)
    rms = np.sqrt((frames * frames).mean(axis=1))
    quality = score[np.arange(len(best)), best]
    valid = (quality > .65) & (rms > max(.001, rms.max() * .3))
    # Favor the latter voiced region to use the vowel rather than a consonant.
    ids = np.flatnonzero(valid)
    if not len(ids):
        raise ValueError('No voiced vowel in TTS output')
    center = int(ids[int(len(ids) * .6)])
    midi = float(np.median(69 + 12 * np.log2(sr / lags[best[ids]] / 440)))
    middle = center * hop + w // 2
    lo, hi = max(0, middle - 1200), min(len(x), middle + 1200)
    return x[lo:hi], midi


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    out = args.output
    if out.exists():
        raise SystemExit('Choose a new output directory')
    out.mkdir(parents=True)
    # Kana-to-note layout; final おはよう extends /o/ rather than switching to /u/.
    lines = [['ア', 'メ', 'ア', 'ガ', 'リ'], ['ソ', 'ラ', 'キ', 'ラ', 'リ'],
             ['チ', 'イ', 'サ', 'ナ', 'メ'], ['オ', 'ハ', 'ヨ', 'オ']]
    pitches = [[60, 62, 64, 62, 60], [64, 67, 69, 67, 64],
               [62, 64, 67, 64, 62], [64, 62, 60, 60]]
    units, source_report = {}, {}
    for index, kana in enumerate(dict.fromkeys(k for line in lines for k in line)):
        aiff = out / f'mora-{index:02d}.aiff'
        wav = out / f'mora-{index:02d}.wav'
        subprocess.run(['say', '-v', 'Kyoko', '-r', '160', '-o', str(aiff), kana], check=True)
        subprocess.run(['ffmpeg', '-v', 'error', '-n', '-i', str(aiff), '-ar', '16000', '-ac', '1',
                        '-c:a', 'pcm_f32le', str(wav)], check=True)
        x, sr = sf.read(wav)
        if not len(x):
            raise ValueError('Empty TTS output; macOS voice service unavailable in this environment')
        nonzero = np.flatnonzero(abs(x) > max(.001, np.max(abs(x)) * .03))
        if not len(nonzero):
            raise ValueError('Silent TTS mora')
        x = x[max(0, nonzero[0] - 80):min(len(x), nonzero[-1] + 160)]
        vowel, midi = voiced_region(x, sr)
        units[kana] = (x, vowel, midi)
        source_report[kana] = dict(file=wav.name, sha256=hashlib.sha256(wav.read_bytes()).hexdigest(), midi=midi)
    sr, beat, pos = 16000, 60 / 108, .25
    song = np.zeros(sr * 26)
    events = []
    spoken = []
    for line_index, (line, notes) in enumerate(zip(lines, pitches)):
        for index, (kana, midi) in enumerate(zip(line, notes)):
            original, vowel, source_midi = units[kana]
            seconds = beat * (2 if index == len(line) - 1 else 1)
            # Retain the first consonant/onset, sustain the voiced nucleus.
            attack_count = min(int(sr * .07), len(original) // 3)
            onset = fade(original[:attack_count], sr, .003, .012)
            body = psola(vowel, sr, source_midi, midi, seconds * .96 - len(onset) / sr)
            note = np.r_[onset, body]
            note *= .5 / max(np.max(abs(note)), 1e-6)
            start = int(pos * sr)
            song[start:start + len(note)] += note
            events.append(dict(second=pos, seconds=seconds, kana=kana, midi=midi, line=line_index + 1))
            spoken.append(np.r_[original, np.zeros(int(sr * .12))])
            pos += seconds
        pos += beat * .5
    song = song[:int((pos + .3) * sr)]
    stats = write(out / '05-japanese-lyrics-dry.wav', song, sr, .65 / np.max(abs(song)))
    # Reference is the same local TTS, unpitched/unextended.
    reference = np.concatenate(spoken)
    write(out / '06-tts-mora-reference.wav', reference, sr, .5 / np.max(abs(reference)))
    (out / 'report.json').write_text(json.dumps(dict(voice='macOS Kyoko; not supplied speaker',
        lyrics=['あめあがり', 'そらきらり', 'ちいさなめ', 'おはよう'], original_melody=True,
        tempo=108, units=source_report, events=events, stats=stats,
        intelligibility_verified_by_listener=False), ensure_ascii=False, indent=2))
    print('PASS: local Kyoko lyric study', stats, flush=True)


if __name__ == '__main__':
    main()
