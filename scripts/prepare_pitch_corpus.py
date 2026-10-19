#!/usr/bin/env python3
"""Rebuild the bundled corpus with macOS /usr/bin/python3 (aifc, stdlib only).
Download is explicit; source and fixture SHA-256 are checked against the committed manifest.
"""
import aifc
import argparse
import array
import hashlib
import json
from pathlib import Path
import sys
import urllib.request
import wave

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / 'app/Resources/PitchCorpus'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_clip(path, start, duration):
    with aifc.open(str(path), 'rb') as f:
        rate, channels, width = f.getframerate(), f.getnchannels(), f.getsampwidth()
        assert f.getcomptype() == b'NONE' and width in (2, 3)
        first, count = round(start * rate), round(duration * rate)
        assert first >= 0 and first + count <= f.getnframes()
        f.setpos(first)
        raw = f.readframes(count)
    if width == 2:
        values = array.array('h', raw)
        if sys.byteorder == 'little':
            values.byteswap()
        values = [v / 32768 for v in values]
    else:
        values = [int.from_bytes(raw[i:i+width], 'big', signed=True) / 8388608 for i in range(0, len(raw), width)]
    mono = [sum(values[i:i+channels])/channels for i in range(0, len(values), channels)]
    return rate, mono


def wav_bytes(rate, values):
    import io
    pcm = array.array('h', [max(-32768, min(32767, round(v*32768))) for v in values])
    if sys.byteorder != 'little':
        pcm.byteswap()
    output = io.BytesIO()
    with wave.open(output, 'wb') as f:
        f.setparams((1, 2, rate, len(values), 'NONE', 'not compressed'))
        f.writeframes(pcm.tobytes())
    return output.getvalue()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--download', action='store_true')
    args = p.parse_args()
    manifest = json.loads((CORPUS/'manifest.json').read_text())
    cache = ROOT/'build/pitch-corpus-source'
    cache.mkdir(parents=True, exist_ok=True)
    for source in manifest['sources']:
        path = cache/(source['id']+'.aif')
        if not path.exists():
            if not args.download:
                raise SystemExit('Missing cached source: '+source['id']+'; pass --download to fetch it.')
            data = urllib.request.urlopen(source['url'], timeout=120).read()
            if sha(data) != source['sha256']:
                raise SystemExit('Downloaded source checksum mismatch: '+source['id'])
            path.write_bytes(data)
        if sha(path.read_bytes()) != source['sha256']:
            raise SystemExit('Cached source checksum mismatch: '+source['id'])
    rendered = {}
    for entry in manifest['entries']:
        if entry['kind'] != 'chord':
            rate, values = read_clip(cache/(entry['source_id']+'.aif'), entry['start_seconds'], entry['duration_seconds'])
        else:
            components = [rendered[part] for part in entry['components']]
            rate = components[0][0]
            assert all(x[0] == rate for x in components)
            values = [sum(x[1][i] for x in components)/len(components) for i in range(min(len(x[1]) for x in components))]
        rendered[entry['id']] = (rate, values)
        data = wav_bytes(rate, values)
        if sha(data) != entry['sha256']:
            raise SystemExit('Fixture checksum mismatch: '+entry['id'])
        dest = CORPUS/entry['file']
        if dest.exists() and dest.read_bytes() != data:
            raise SystemExit('Refusing to replace different fixture: '+entry['id'])
        dest.write_bytes(data)
    print('PASS: rebuilt/verified', len(rendered), 'recorded fixtures')


if __name__ == '__main__':
    main()
