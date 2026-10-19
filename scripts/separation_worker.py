#!/usr/bin/env python3
"""SonicForge MLX worker: one local job, atomic progress and result files."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import sys

STEMS = ('drums', 'bass', 'other', 'vocals')
PINNED = {'demucs-mlx': '1.6.1', 'mlx': '0.32.4', 'mlx-audio-io': '1.3.24', 'mlx-spectro': '0.9.10'}
WEIGHT_HASH = '339d267a7a6983a11eedbdc00413c602a65e9b9103f695fb5c2b2a481cd9d297'


def atomic_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, allow_nan=False), encoding='utf-8')
    os.replace(temporary, path)


def process(request_path, mode):
    directory = request_path.resolve().parent
    request = json.loads(request_path.read_text())
    if request.get('version') != 1 or not isinstance(request.get('jobID'), str):
        raise ValueError('Unsupported request')
    job = request['jobID']
    def stage(value, message):
        atomic_json(directory/'progress.json', {'version': 1, 'jobID': job, 'stage': value, 'message': message})
    try:
        stage('preparing', '実行環境とモデルを確認中…')
        versions = {p: importlib.metadata.version(p) for p in PINNED}
        if versions != PINNED:
            raise ValueError('実行環境の版が異なります。セットアップ手順で固定版を準備してください。')
        cache = Path(request['cache']).expanduser().resolve()
        os.environ['DEMUCS_MLX_CACHE_DIR'] = str(cache)
        os.environ['DEMUCS_MLX_NO_DOWNLOAD'] = '0' if mode == 'prepare' else '1'
        os.environ['HF_HUB_OFFLINE'] = '0' if mode == 'prepare' else '1'
        import numpy as np
        import mlx.core as mx
        import soundfile as sf
        from demucs_mlx import Separator
        if not mx.metal.is_available():
            raise ValueError('Apple SiliconのMetalを使用できません。')
        cache.mkdir(parents=True, exist_ok=True)
        if mode != 'prepare' and not (cache/'htdemucs.safetensors').is_file():
            raise ValueError('モデル未準備です。「モデルを準備」を実行してください。')
        mx.set_cache_limit(4*1024**3)
        settings = dict(shifts=0, overlap=.25, segment=7.8, batch_size=1, attention_precision='fp32', compile=True)
        separator = Separator(model='htdemucs', **settings)
        weight_hash = hashlib.file_digest(open(cache/'htdemucs.safetensors', 'rb'), 'sha256').hexdigest() if sys.version_info >= (3,11) else hashlib.sha256((cache/'htdemucs.safetensors').read_bytes()).hexdigest()
        if weight_hash != WEIGHT_HASH:
            raise ValueError('モデルのチェックサムが一致しません。モデルを再準備してください。')
        if mode == 'prepare':
            atomic_json(directory/'manifest.json', {'version': 1, 'jobID': job, 'prepared': True,
                        'model': 'htdemucs', 'weightSHA256': weight_hash, 'versions': versions})
            stage('ready', 'モデルの準備ができました')
            return
        source = Path(request['input']).resolve()
        if source.parent != directory or source.stat().st_size > 256*1024**2:
            raise ValueError('入力ファイルの場所または容量が無効です。')
        stage('decoding', '曲を読み込み中…')
        from demucs_mlx.audio import load_audio
        array, rate = load_audio(source, sr=44100)
        mx.eval(array)
        wav = np.asarray(array).astype(np.float32, copy=True)
        del array
        if wav.ndim != 2 or wav.shape[0] not in (1,2) or wav.shape[1] == 0 or wav.shape[1] > 600*44100 or not np.isfinite(wav).all():
            raise ValueError('音源は10分以内のモノラル／ステレオにしてください。')
        if wav.shape[0] == 1:
            wav = np.repeat(wav, 2, axis=0)
        stage('separating', '4つの音に分離中…（初回は準備に時間がかかります）')
        ref = wav.mean(0)
        mean, std = ref.mean(), ref.std(ddof=1) + 1e-8
        _, estimates = separator.separate_tensor(np.ascontiguousarray((wav-mean)/std))
        stems = {name: np.asarray(estimates[name])*std+mean for name in STEMS}
        mx.synchronize()
        stage('validating', '音源を保存・確認中…')
        if any(x.shape != wav.shape or not np.isfinite(x).all() for x in stems.values()):
            raise ValueError('分離結果に無効な音声が含まれています。')
        gain = min(1., .98/max(.98, float(np.max(np.abs(wav))), *(float(np.max(np.abs(x))) for x in stems.values())))
        entries = []
        for name, audio in [('original', wav), *stems.items()]:
            filename = name+'.wav'
            pending = directory/(name+'.partial.wav')
            sf.write(pending, (audio*gain).T, 44100, subtype='FLOAT')
            with sf.SoundFile(pending) as f:
                if f.frames != wav.shape[1] or f.channels != 2 or f.samplerate != 44100:
                    raise ValueError('保存した音源の形式が一致しません。')
                for block in f.blocks(blocksize=16384, dtype='float32'):
                    if not np.isfinite(block).all():
                        raise ValueError('保存した音源を検証できませんでした。')
            os.replace(pending, directory/filename)
            entries.append({'id': name, 'file': filename, 'frames': wav.shape[1], 'sampleRate': 44100, 'channels': 2})
        atomic_json(directory/'manifest.json', {'version': 1, 'jobID': job, 'prepared': False,
                    'model': 'htdemucs', 'device': 'metal', 'weightSHA256': weight_hash,
                    'versions': versions, 'gain': gain, 'audio': entries, 'backend': 'mlx-metal', 'settings': settings,
                    'preprocessing': 'demucs-mlx-load_audio-44100-stereo-outer-normalization-v1',
                    'inputSHA256': hashlib.sha256(source.read_bytes()).hexdigest()})
        stage('ready', '分離が完了しました。試聴する音を選んでください。')
    except Exception:
        # Do not put source paths, native tracebacks or package output in the UI.
        stage('failed', '分離できませんでした。実行環境・モデル・入力形式・空き容量を確認してください。')
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    parser.add_argument('--mode', choices=('prepare','separate'), required=True)
    args = parser.parse_args()
    try:
        process(args.request, args.mode)
    except Exception:
        sys.exit(1)
