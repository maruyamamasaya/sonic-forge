"""Offline Qwen3-TTS reference-conditioned vowel trial; not waveform editing.
Run inside an isolated MLX Audio environment with a predownloaded local model.
Never starts a server, fetches models, uploads audio, or edits application data.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import time

os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', HF_HUB_DISABLE_TELEMETRY='1')
network_attempts = []


def deny_network(*args, **kwargs):
    network_attempts.append('blocked')
    raise RuntimeError('Network disabled during local voice inference')


socket.socket.connect = deny_network
socket.socket.connect_ex = deny_network
socket.create_connection = deny_network

import mlx.core as mx
import numpy as np
from scipy.io import wavfile
from mlx_audio.tts.utils import load_model
from mlx_audio.utils import load_audio


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model', type=Path, required=True)
    p.add_argument('--reference', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--max-tokens', type=int, choices=[48,96,192], default=48)
    p.add_argument('--short-prompts', action='store_true')
    p.add_argument('--five-vowels', action='store_true')
    p.add_argument('--lyric-study', action='store_true', help='Four short original Japanese lyric lines')
    p.add_argument('--prompts-file',type=Path,help='JSON list of short text/category objects for spoken generation')
    args = p.parse_args()
    if args.prompts_file and (args.lyric_study or args.five_vowels or args.short_prompts):
        p.error('--prompts-file cannot be combined with built-in prompt modes')
    custom_prompts=None
    if args.prompts_file:
        custom_prompts=json.loads(args.prompts_file.read_text())
        if not isinstance(custom_prompts,list) or not 1<=len(custom_prompts)<=32:
            p.error('Expected 1 to 32 short text objects')
        for entry in custom_prompts:
            if not isinstance(entry,dict) or not isinstance(entry.get('text'),str) or not 1<=len(entry['text'].strip())<=140:
                p.error('Each prompt must contain 1 to 140 characters of text')
    if args.lyric_study and (args.five_vowels or args.short_prompts):
        p.error('--lyric-study cannot be combined with vowel prompt modes')
    if not args.model.is_dir() or not (args.model / 'config.json').is_file():
        raise SystemExit('A predownloaded local model is required')
    if args.output.exists():
        raise SystemExit('Use a fresh output directory')
    before = hashlib.sha256(args.reference.read_bytes()).hexdigest()
    args.output.mkdir(parents=True)
    mx.set_memory_limit(8 * 1024**3)
    mx.set_cache_limit(256 * 1024**2)
    print('Loading local model', flush=True)
    model = load_model(args.model.resolve(), trust_remote_code=False)
    print('Model ready', flush=True)
    reference = load_audio(str(args.reference.resolve()), sample_rate=model.sample_rate)
    if not .2 <= reference.size / model.sample_rate <= 10:
        raise ValueError('Reference must be 0.2 to 10 seconds')
    ref_embedding = np.array(model.extract_speaker_embedding(reference)).flatten()
    trials = []
    prompts = [('01-generated-aa', 'あ。' if args.short_prompts else 'あー。'), ('02-generated-uu', 'う。' if args.short_prompts else 'うー。')]
    if args.five_vowels:
        prompts = [(f'{i:02d}-{name}', text + '。') for i, (name, text) in enumerate([('a','あ'),('i','い'),('u','う'),('e','え'),('o','お')], 1)]
    if args.lyric_study:
        prompts = [(f'{i:02d}-lyrics', text) for i,text in enumerate(['静かな夜に。','光が揺れる。','遠くの空へ。','そっとおやすみ。'],1)]
    if custom_prompts is not None:
        prompts=[(f'{i:02d}-spoken',entry['text']) for i,entry in enumerate(custom_prompts,1)]
    for name, text in prompts:
        mx.random.seed(7)
        started = time.monotonic()
        # ref_text intentionally absent: do not invent a transcript for a vowel
        # candidate. The inspected Base implementation uses speaker-embedding
        # conditioning in this mode rather than transcript+codec ICL cloning.
        results = list(model.generate(text=text, ref_audio=reference, ref_text=None,
            lang_code='japanese', max_tokens=args.max_tokens, temperature=.7, top_k=50, top_p=.95,
            repetition_penalty=1.1, verbose=True, stream=False))
        if len(results) != 1:
            raise ValueError('Unexpected generation segment count')
        result = results[0]
        audio = np.array(result.audio, dtype=np.float32).reshape(-1)
        if not len(audio) or not np.isfinite(audio).all() or not .1 < len(audio) / result.sample_rate < max(9,args.max_tokens*.08+.1):
            raise ValueError('Invalid generated audio')
        peak = float(np.max(abs(audio)))
        if not .0001 < peak < 1:
            raise ValueError('Silent or clipping generation')
        wav = args.output / (name + '.wav')
        wavfile.write(wav, result.sample_rate, audio)
        actual_sr, restored = wavfile.read(wav)
        assert actual_sr == result.sample_rate and np.array_equal(audio, restored)
        embedding = np.array(model.extract_speaker_embedding(mx.array(audio))).flatten()
        cosine = float(np.dot(ref_embedding, embedding) / (np.linalg.norm(ref_embedding) * np.linalg.norm(embedding)))
        trial = dict(file=wav.name, text=text, seed=7, seconds=len(audio) / result.sample_rate,
            sample_rate=result.sample_rate, tokens=int(result.token_count), limit_reached=int(result.token_count) >= args.max_tokens,
            peak_dbfs=20 * np.log10(peak), rms_dbfs=10 * np.log10(float(np.mean(audio**2))),
            reference_embedding_cosine=cosine, inference_seconds=time.monotonic() - started,
            postprocessing='none', phoneme_and_identity_verified_by_listener=False)
        if custom_prompts is not None:
            trial['category']=custom_prompts[len(trials)].get('category','spoken')
        trials.append(trial)
        (args.output / 'progress.json').write_text(json.dumps(trials, ensure_ascii=False, indent=2))
        print(json.dumps(trial, ensure_ascii=False), flush=True)
        mx.clear_cache()
    assert before == hashlib.sha256(args.reference.read_bytes()).hexdigest()
    (args.output / 'report.json').write_text(json.dumps(dict(
        reference_sha256=before, reference_seconds=reference.size / model.sample_rate,
        reference_unchanged=True, all_generations_stopped_naturally=not any(t['limit_reached'] for t in trials), mode='Base speaker-embedding conditioning; no reference transcript',
        audio_sent_to_external_service=False, blocked_network_attempts=len(network_attempts),
        interpretation='Generated synthetic speech or vowels conditioned on reference; not direct phoneme editing or verified speaker identity',
        prompts_file_sha256=hashlib.sha256(args.prompts_file.read_bytes()).hexdigest() if args.prompts_file else None,
        trials=trials), ensure_ascii=False, indent=2))
    print('PASS technical checks only: offline, WAV reload, finite/nonzero/nonclipping, unchanged reference. Natural EOS: ' + str(not any(t['limit_reached'] for t in trials)), flush=True)


if __name__ == '__main__':
    main()
