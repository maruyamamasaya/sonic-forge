"""Offline vowel-like candidate search and original nursery-style vowel melody.
Uses cached numpy/soundfile only. No model, upload, phoneme recognition or UI edits.
"""
from pathlib import Path
import argparse, hashlib, json, math, subprocess
import numpy as np
import soundfile as sf


def scan(x, sr):
    w, hop = int(sr * .04), int(sr * .01)
    frames = np.lib.stride_tricks.sliding_window_view(x, w)[::hop].copy()
    frames -= frames.mean(axis=1, keepdims=True)
    rms = np.sqrt(np.mean(frames * frames, axis=1))
    fft = np.fft.rfft(frames * np.hanning(w), n=2048)
    ac = np.fft.irfft(abs(fft)**2, n=2048)[:, :w]
    lags = np.arange(int(sr / 500), int(sr / 130))
    scores = ac[:, lags] / ac[:, 0, None].clip(1e-15)
    best = scores.argmax(axis=1)
    quality = scores[np.arange(len(best)), best]
    pitch = 69 + 12 * np.log2(sr / lags[best] / 440)
    spectrum = abs(fft[:, 20:400])
    spectrum /= np.sqrt((spectrum * spectrum).sum(axis=1, keepdims=True)).clip(1e-12)
    similarity = np.r_[1, (spectrum[:-1] * spectrum[1:]).sum(axis=1)]
    mask = (quality > .72) & (rms > .008) & (similarity > .97)
    runs, start = [], None
    for i, valid in enumerate(mask):
        if valid and start is None:
            start = i
        if start is not None and (not valid or i == len(mask) - 1):
            end = i
            duration = (end - start) * hop / sr
            if duration >= .16:
                spread = np.percentile(pitch[start:end], 90) - np.percentile(pitch[start:end], 10)
                if spread < 2:
                    runs.append(dict(start=start * hop / sr, seconds=duration,
                                     midi=float(np.median(pitch[start:end])),
                                     periodicity=float(quality[start:end].mean()), spread=float(spread)))
            start = None
    return sorted(runs, key=lambda r: r['seconds'] * r['periodicity'], reverse=True)


def pitch_marks(x, sr, midi):
    period = sr / (440 * 2**((midi - 69) / 12))
    # Start near a strong positive pulse; follow similar pulses within +/-20%.
    first = int(np.argmax(x[:int(period * 3)]))
    marks = [first]
    while marks[-1] + period * 1.3 < len(x):
        lo = int(marks[-1] + period * .8)
        hi = min(len(x), int(marks[-1] + period * 1.2) + 1)
        next_mark = lo + int(np.argmax(x[lo:hi]))
        marks.append(next_mark)
    return np.array(marks), period


def psola(x, sr, source_midi, target_midi, seconds):
    """Experimental pitch-synchronous OLA, preserving grain duration.
    Not a production formant guarantee; no generative or voice conversion model.
    """
    marks, period = pitch_marks(x, sr, source_midi)
    half = int(round(period))
    marks = marks[(marks >= half) & (marks + half < len(x))]
    if len(marks) < 8:
        raise ValueError('Insufficient pitch marks')
    n = int(round(seconds * sr))
    y, weights = np.zeros(n + 2 * half), np.zeros(n + 2 * half)
    window = np.hanning(2 * half)
    t = float(half)
    while t < n:
        # Reflect through the source rather than repeating one fixed cycle.
        # Keeps slow changes from the candidate; introduces a turning boundary.
        progress = (t / sr) / max(len(x) / sr - .06, .08)
        triangle = 1 - abs(1 - progress % 2)
        index = min(len(marks) - 1, int(triangle * (len(marks) - 1)))
        center = marks[index]
        grain = x[center - half:center + half]
        pos = int(round(t))
        a, b = pos - half, pos + half
        y[a:b] += grain * window
        weights[a:b] += window
        # Very small natural-style drift, not separate choir singers.
        cents = 3 * math.sin(2 * math.pi * 4.7 * t / sr)
        freq = 440 * 2**((target_midi - 69 + cents / 100) / 12)
        t += sr / freq
    y = y[:n] / np.maximum(weights[:n], .25)
    return fade(y, sr, .025, .09)


def fade(x, sr, attack=.008, release=.035):
    x = x.copy()
    a, b = min(len(x), int(sr * attack)), min(len(x), int(sr * release))
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def write(path, x, sr, gain=1):
    x = np.asarray(x) * gain
    if not np.isfinite(x).all() or np.max(abs(x)) >= 1 or np.max(abs(x)) < .0001:
        raise ValueError('Nonfinite, clipping or silent audio: ' + str(path))
    sf.write(path, x, sr, subtype='PCM_24')
    restored, actual_sr = sf.read(path)
    assert actual_sr == sr and restored.shape == x.shape
    assert np.isfinite(restored).all() and np.max(abs(restored)) > .0001
    subprocess.run(['ffmpeg', '-v', 'error', '-n', '-i', str(path), '-c:a', 'libmp3lame',
                    '-b:a', '192k', str(path.with_suffix('.mp3'))], check=True)
    return dict(seconds=len(x) / sr, peak_dbfs=float(20 * np.log10(np.max(abs(x)))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--transpose', type=int, choices=[-12, 0], default=0)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('Choose a new output directory; existing files are protected')
    probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(args.input)]))
    duration = float(probe['format']['duration'])
    if not math.isfinite(duration) or not 0 < duration <= 600:
        raise ValueError('Input limited to ten minutes')
    args.output.mkdir(parents=True)
    before = hashlib.sha256(args.input.read_bytes()).hexdigest()
    subprocess.run(['ffmpeg', '-v', 'error', '-n', '-i', str(args.input), '-ar', '16000', '-ac', '1',
                    '-c:a', 'pcm_f32le', str(args.output / 'analysis.wav')], check=True)
    x, sr = sf.read(args.output / 'analysis.wav')
    if len(x) / sr > 600:
        raise ValueError('Input limited to ten minutes')
    candidates = scan(x, sr)
    # Keep upper-frequency texture for actual listening; only analysis is 16 kHz.
    subprocess.run(['ffmpeg', '-v', 'error', '-n', '-i', str(args.input), '-ar', '44100', '-ac', '1',
                    '-c:a', 'pcm_f32le', str(args.output / 'render-source.wav')], check=True)
    x, sr = sf.read(args.output / 'render-source.wav')
    if not candidates:
        raise ValueError('No stable voiced candidate; do not fabricate a vowel')
    # Keep four temporally distinct candidates, without inventing vowel labels.
    selected = []
    for c in candidates:
        if c['periodicity'] < .9 or not 60 <= c['midi'] <= 76:
            continue
        if all(abs(c['start'] - s['start']) > 1 for s in selected):
            selected.append(c)
        if len(selected) == 4:
            break
    if len(selected) < 2:
        raise ValueError('Need at least two candidates for comparison')
    snippets = [x[int(c['start'] * sr):int((c['start'] + c['seconds']) * sr)] for c in selected]
    # Same gain for source and sustained comparison, not independently normalized.
    common_gain = .5 / max(np.max(abs(s)) for s in snippets)
    source_preview = np.concatenate([np.r_[fade(s, sr), np.zeros(int(sr * .65))] for s in snippets])
    extended = np.concatenate([np.r_[psola(s, sr, c['midi'], c['midi'], 2.0), np.zeros(int(sr * .65))]
                               for s, c in zip(snippets, selected)])
    # Conservative shared limiter-free scaling if OLA has higher peaks.
    common_gain = min(common_gain, .7 / np.max(abs(extended)))
    stats = {'candidates': write(args.output / '01-source-candidates.wav', source_preview, sr, common_gain)}
    stats['extended'] = write(args.output / '02-sustained-candidates.wav', extended, sr, common_gain)
    # Original five-note, 5+5+5+4 mora phrase plan. Vowels only in the supplied
    # voice; no claim that speech clips pronounce these written lyrics.
    phrase_pitches = [[0, 2, 4, 2, 0], [4, 7, 9, 7, 4], [2, 4, 7, 4, 2], [4, 2, 0, 0]]
    phrase_moras = [list('あめあがり'), list('そらきらり'), list('ちいさなめ'), list('おはよう')]
    root = round(selected[0]['midi']) - 4 + args.transpose
    beat = 60 / 108
    song = np.zeros(int(sr * 26))
    events, pos = [], .25
    for line, pitches in enumerate(phrase_pitches):
        for j, offset in enumerate(pitches):
            duration = beat * (2 if j == len(pitches) - 1 else 1)
            sample_index = (line + (j // 2)) % min(2, len(selected))
            c, s = selected[sample_index], snippets[sample_index]
            note = psola(s, sr, c['midi'], root + offset, duration * .96)
            start = int(pos * sr)
            song[start:start + len(note)] += note
            events.append(dict(second=pos, seconds=duration, midi=root + offset,
                               source_candidate=sample_index + 1, planned_mora=phrase_moras[line][j]))
            pos += duration
        pos += beat * .5
    song = song[:int((pos + .3) * sr)]
    song_gain = .65 / np.max(abs(song))
    stats['vowel_song'] = write(args.output / '03-vowel-nursery-dry.wav', song, sr, song_gain)
    # Sparse sustained harmony using a different candidate, no reverb effect.
    harmony = np.zeros_like(song)
    for line in range(4):
        first = events[line * 5] if line < 3 else events[15]
        start = int(first['second'] * sr)
        duration = beat * (5.8 if line < 3 else 4.8)
        for interval in [0, 7]:
            note = psola(snippets[1], sr, selected[1]['midi'], root + interval, duration) * .12
            n = min(len(note), len(harmony) - start)
            harmony[start:start + n] += note[:n]
    choir = song + harmony
    stats['vowel_song_harmony'] = write(args.output / '04-vowel-nursery-chorus.wav', choir, sr, .65 / np.max(abs(choir)))
    report = dict(source_sha256=before, source_unchanged=True, candidates_found=len(candidates), selected=selected,
                  analysis_sample_rate=16000, render_sample_rate=sr,
                  vowel_labels_verified=False, speech_to_lyrics=False, root=root, transpose=args.transpose, tempo=108,
                  lyrics_plan=['あめあがり', 'そらきらり', 'ちいさなめ', 'おはよう'], events=events,
                  gain_sustained=common_gain, gain_song=song_gain, stats=stats)
    assert before == hashlib.sha256(args.input.read_bytes()).hexdigest()
    (args.output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps(dict(selected=selected, stats=stats), indent=2), flush=True)


if __name__ == '__main__':
    main()
