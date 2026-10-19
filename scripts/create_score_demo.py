#!/usr/bin/env python3
"""Make this fixed Mutopia Satie excerpt with SonicForge's production renderer.
Not a general MIDI import feature. Requires cached Iowa source recordings from pitch evaluation.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import shlex
import struct
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SCORE_URL = 'https://www.mutopiaproject.org/ftp/SatieE/gymnopedie_1/gymnopedie_1.mid'
SCORE_SHA = '09ce7337b4bf42ba12e1aa64b4c7dc7fcfa6455f1070cb12f8880a755df97384'


def read_score(data):
    assert hashlib.sha256(data).hexdigest() == SCORE_SHA, 'Different source MIDI'
    assert data[:4] == b'MThd'
    fmt, tracks, division = struct.unpack('>HHH', data[8:14])
    assert (fmt, tracks, division) == (1, 3, 384)
    pos = 14
    notes = []
    unmatched = 0
    for track in range(tracks):
        assert data[pos:pos+4] == b'MTrk'
        size = int.from_bytes(data[pos+4:pos+8], 'big')
        chunk = data[pos+8:pos+8+size]
        pos += 8+size
        i = tick = status = 0
        pending = defaultdict(list)
        def vlq():
            nonlocal i
            value = 0
            while True:
                byte = chunk[i]
                i += 1
                value = value*128+(byte & 127)
                if byte < 128:
                    return value
        while i < len(chunk):
            tick += vlq()
            if chunk[i] >= 128:
                status = chunk[i]
                i += 1
            if status == 255:
                i += 1
                length = vlq()
                i += length
            elif status in (240, 247):
                length = vlq()
                i += length
            else:
                kind, channel = status & 240, status & 15
                count = 1 if kind in (192, 208) else 2
                event = chunk[i:i+count]
                i += count
                key = (channel, event[0])
                if kind == 144 and event[1] > 0:
                    pending[key].append((tick, event[1]))
                elif kind == 128 or kind == 144:
                    if not pending[key]:
                        unmatched += 1
                        continue
                    start, velocity = pending[key].pop()
                    notes.append(dict(beat=start/division, duration=(tick-start)/division,
                                      pitch=event[0], velocity=velocity, channel=0, track=track))
        assert not any(pending.values())
    assert unmatched == 2 and len(notes) == 282
    return notes


def prepare(out):
    source = ROOT/'build/score-source/gymnopedie_1.mid'
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_bytes(urllib.request.urlopen(SCORE_URL, timeout=60).read())
    notes = read_score(source.read_bytes())
    roles = {'melody': [], 'harmony': [], 'bass': []}
    for original in sorted(notes, key=lambda x: (x['beat'], x['pitch'])):
        if original['beat'] >= 117:
            continue
        n = dict(original)
        track = n.pop('track')
        n['duration'] = min(n['duration'], 117-n['beat'])
        # Fixed voice split checked against LilyPond, not a general voice separator.
        chord = track == 1 and ((n['beat'] % 3 == 1 and n['duration'] >= 2 and n['beat'] < 108) or n['beat'] in (109, 110))
        if chord:
            role = 'harmony'
            n['duration'] = min(n['duration'], 2 if n['beat'] < 108 else 1)
        elif track == 1:
            role = 'melody'
            # LilyPond tie at bars 9-12; exported MIDI retriggers F#4 with accompaniment.
            if n['beat'] == 24 and n['pitch'] == 66:
                n['duration'] = 12
        else:
            role = 'bass' if n['pitch'] < 48 else 'harmony'
        # Softer fixed voicing; preserve the source's relative dynamics.
        n['velocity'] = max(30, min(100, round(n['velocity'] * {'melody': 1.0, 'harmony': .67, 'bass': .72}[role])))
        roles[role].append(n)
    for role, values in roles.items():
        # Distinct channels preserve simultaneously held copies of the same pitch.
        occupied = {}
        for n in values:
            channel = next(c for c in range(16) if occupied.get((c, n['pitch']), 0) <= n['beat']+1e-8)
            n['channel'] = channel
            occupied[(channel, n['pitch'])] = n['beat']+n['duration']
        document = dict(version=1, name='Gymnopedie 1 - '+role, tempo=72, transpose=0,
                        velocityPercent=100, notes=values, pedals=[])
        (out/(role+'.sfperformance')).write_text(json.dumps(document, indent=2)+'\n')
    return {key: len(value) for key, value in roles.items()}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('output', help='New build/ subdirectory; never overwrites an existing directory')
    args = p.parse_args()
    out = Path(args.output).resolve()
    if not out.is_relative_to((ROOT/'build').resolve()) or out.exists():
        raise SystemExit('Choose a new directory inside build/.')
    out.mkdir(parents=True)
    counts = prepare(out)
    source_set = shlex.split((ROOT/'scripts/test.sh').read_text().split('xcrun swiftc', 1)[1].split('build/AudioTests', 1)[0].replace('\\\n', ' '))
    sources = [s for s in source_set if s.startswith('app/') and s.endswith('.swift')]
    binary = out/'ScoreDemoRenderer'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-O', '-module-cache-path', 'build/module-cache',
                    *sources, 'scripts/score_demo.swift', '-o', str(binary)], cwd=ROOT, check=True)
    subprocess.run([str(binary), str(out)], cwd=ROOT, check=True)
    (out/'source.json').write_text(json.dumps(dict(title='Gymnopedie No. 1 - first 39 bars / first ending',
        composer='Erik Satie', typesetter='Evin Robertson / Mutopia Project', score_url=SCORE_URL,
        score_sha256=SCORE_SHA, score_license='Public Domain', tempo=72, quarter_beats=117,
        role_note_counts=counts, adaptations=['First ending only; no repeat', 'F#4 tie bars 9-12 restored from score',
        'Relative dynamics softened; no sustain pedal', 'Three sampler parts, normalized copies; light reverb',
        'Second version: guitar melody, piano harmony, bowed bass']), indent=2)+'\n')
    print('Created:', out)


if __name__ == '__main__':
    main()
