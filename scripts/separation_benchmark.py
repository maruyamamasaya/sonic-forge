#!/usr/bin/env python3
"""Local, sequential HTDemucs backend benchmark. Dependencies live in a dedicated venv."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import resource
import threading
import time


def run(args):
    import numpy as np
    import soundfile as sf
    import psutil
    wall_start = time.perf_counter()
    if args.repeats < 1:
        raise ValueError("repeats must be at least 1")
    backend = args.backend
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    samples, rate = sf.read(args.input, dtype='float32', always_2d=True)
    if rate != 44100 or samples.shape[1] != 2:
        raise ValueError('Prepare a common stereo 44.1 kHz WAV before benchmarking.')
    wav = np.ascontiguousarray(samples.T)
    del samples
    report = {'backend': backend, 'sample_rate': rate, 'frames': wav.shape[1],
              'duration_s': wav.shape[1] / rate, 'input_sha256': hashlib.sha256(Path(args.input).read_bytes()).hexdigest(),
              'settings': {'model': 'htdemucs', 'shifts': 0, 'overlap': .25,
                           'split': True, 'segment': 7.8, 'precision': 'float32', 'batch_size': 1},
              'runs': []}
    proc = psutil.Process()
    peak = {'rss_bytes': 0, 'metal_active_bytes': 0, 'metal_driver_bytes': 0}
    stopping = threading.Event()
    gpu_memory = lambda: (0, 0)
    def sample_memory():
        while not stopping.is_set():
            peak['rss_bytes'] = max(peak['rss_bytes'], proc.memory_info().rss)
            a, d = gpu_memory()
            peak['metal_active_bytes'] = max(peak['metal_active_bytes'], a)
            peak['metal_driver_bytes'] = max(peak['metal_driver_bytes'], d)
            stopping.wait(.05)
    monitor = threading.Thread(target=sample_memory, daemon=True)
    monitor.start()
    try:
        started = time.perf_counter()
        if backend == 'torch':
            import torch
            from demucs.pretrained import get_model
            from demucs.apply import apply_model
            if not torch.backends.mps.is_available():
                raise RuntimeError('MPS unavailable; no silent CPU fallback')
            model = get_model('htdemucs').to('mps').eval()
            gpu_memory = lambda: (torch.mps.current_allocated_memory(), torch.mps.driver_allocated_memory())
            sync = torch.mps.synchronize
            def infer(x):
                # Common outer preprocessing; inference includes input/output transfers.
                ref = x.mean(0)
                mean, std = ref.mean(), ref.std(ddof=1) + 1e-8
                tensor = torch.from_numpy(np.ascontiguousarray((x - mean) / std))
                with torch.inference_mode():
                    y = apply_model(model, tensor[None], device='mps', shifts=0,
                                    overlap=.25, split=True, segment=7.8, progress=False,
                                    num_workers=0)[0]
                result = y.cpu().numpy() * std + mean
                sync()
                return result
            sources = model.sources
            report['versions'] = {p: importlib.metadata.version(p) for p in ('demucs', 'torch', 'numpy')}
        else:
            import mlx.core as mx
            from demucs_mlx import Separator
            if not mx.metal.is_available():
                raise RuntimeError('Metal unavailable')
            mx.set_cache_limit(4 * 1024**3)
            separator = Separator(model='htdemucs', shifts=0, overlap=.25,
                                  segment=7.8, batch_size=1, attention_precision='fp32', compile=True)
            gpu_memory = lambda: (mx.get_active_memory(), mx.get_cache_memory() + mx.get_active_memory())
            sync = mx.synchronize
            def infer(x):
                ref = x.mean(0)
                mean, std = ref.mean(), ref.std(ddof=1) + 1e-8
                _, stems = separator.separate_tensor(np.ascontiguousarray((x - mean) / std))
                result = np.stack([stems[s] for s in separator.model.sources]) * std + mean
                sync()
                return result
            sources = separator.model.sources
            report['versions'] = {p: importlib.metadata.version(p) for p in ('demucs-mlx', 'mlx', 'numpy')}
        sync()
        report['load_s'] = time.perf_counter() - started
        print(json.dumps({'stage': 'loaded', 'backend': backend, 'seconds': report['load_s']}), flush=True)
        for index in range(args.repeats):
            sync()
            began = time.perf_counter()
            stems = infer(wav)
            elapsed = time.perf_counter() - began
            if stems.shape != (4, 2, wav.shape[1]) or not np.isfinite(stems).all():
                raise ValueError('Invalid stems')
            report['runs'].append({'kind': 'cold' if index == 0 else 'warm', 'inference_s': elapsed,
                                   'audio_seconds_per_wall_second': report['duration_s'] / elapsed})
            print(json.dumps({'stage': 'inferred', 'backend': backend, 'run': index, 'seconds': elapsed}), flush=True)
            began = time.perf_counter()
            # Keep the first output for quality comparison; no independent stem normalization.
            if index == 0:
                for name, audio in zip(sources, stems):
                    sf.write(output / (name + '.wav'), audio.T, rate, subtype='FLOAT')
            report['runs'][-1]['write_s'] = time.perf_counter() - began
            del stems
        if backend == 'mlx':
            report['mlx_peak_active_bytes'] = mx.get_peak_memory()
        report['sources'] = list(sources)
        report['total_s'] = time.perf_counter() - wall_start
    finally:
        stopping.set()
        monitor.join()
    report['memory'] = peak
    report['memory']['process_peak_rss_bytes'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    (output / 'metrics.json').write_text(json.dumps(report, indent=2) + '\n')


def compare(args):
    import numpy as np
    import soundfile as sf
    rows = {}
    for stem in ('drums', 'bass', 'other', 'vocals'):
        a, sr = sf.read(Path(args.torch) / (stem + '.wav'), dtype='float64', always_2d=True)
        b, br = sf.read(Path(args.mlx) / (stem + '.wav'), dtype='float64', always_2d=True)
        if a.shape != b.shape or sr != br or not np.isfinite(a).all() or not np.isfinite(b).all():
            raise ValueError('Incompatible output')
        error = a - b
        energy = float(np.sum(a*a))
        correlation = float(np.corrcoef(a.ravel(), b.ravel())[0,1]) if a.std() > 0 and b.std() > 0 else None
        rows[stem] = {'snr_db_against_torch': float(10*np.log10(energy/max(np.sum(error*error),1e-30))) if energy > 0 else None,
                      'max_abs_error': float(np.max(np.abs(error))),
                      'rms_torch': float(np.sqrt(np.mean(a*a))), 'rms_mlx': float(np.sqrt(np.mean(b*b))),
                      'correlation': correlation,
                      'frames': len(a), 'sample_rate': sr}
    Path(args.output).write_text(json.dumps(rows, indent=2)+'\n')
    print(json.dumps(rows, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('run')
    p.add_argument('--backend', choices=('torch', 'mlx'), required=True)
    p.add_argument('--input', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--repeats', type=int, default=3)
    p = sub.add_parser('compare')
    p.add_argument('--torch', required=True)
    p.add_argument('--mlx', required=True)
    p.add_argument('--output', required=True)
    args = parser.parse_args()
    if args.command == 'run':
        run(args)
    else:
        compare(args)
