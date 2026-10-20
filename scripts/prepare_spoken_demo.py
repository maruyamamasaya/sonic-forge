"""Assemble complete local spoken utterances with static gain and short gaps only."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from vowel_chord_study import read,write,active_mask


def stamp(seconds):
    return f'{int(seconds)//60:02d}:{int(seconds)%60:02d}'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();report=json.loads((a.input/'report.json').read_text())
    assert report['reference_unchanged'] and report['all_generations_stopped_naturally']
    assert not report['audio_sent_to_external_service'] and report['blocked_network_attempts']==0
    assert len(report['trials'])==16
    assert not a.output.exists();a.output.mkdir(parents=True);(a.output/'clips').mkdir()
    sources=[];gains=[];hashes=[]
    for entry in report['trials']:
        path=a.input/entry['file'];hashes.append(hashlib.sha256(path.read_bytes()).hexdigest())
        sr,x=read(path);assert sr==24000 and not entry['limit_reached']
        assert abs(len(x)/sr-entry['seconds'])<1/sr
        mask=active_mask(x,sr);rms=np.sqrt(np.mean(x[mask].astype(float)**2))
        gain=10**(-25/20)/rms;sources.append(x);gains.append(gain)
    max_peak=max(float(np.max(abs(x)))*gain for x,gain in zip(sources,gains))
    common=min(1.,10**(-3/20)/max_peak);gap_count=round(.35*sr)
    pieces=[];rows=[];position=0
    for i,(entry,x,gain,digest) in enumerate(zip(report['trials'],sources,gains,hashes)):
        actual_gain=gain*common;y=(x*actual_gain).astype(np.float32)
        clip=a.output/'clips'/entry['file'];write(clip,sr,y)
        _,check=read(clip);assert np.array_equal(check,(x*actual_gain).astype(np.float32))
        start=position/sr;pieces.append(y);position+=len(y);end=position/sr
        rows.append(dict(file=str(clip.relative_to(a.output)),category=entry['category'],text=entry['text'],start_seconds=start,end_seconds=end,
            source_sha256=digest,source_frames=len(x),output_frames=len(y),gain_db=float(20*np.log10(actual_gain))))
        if i<len(sources)-1:pieces.append(np.zeros(gap_count,dtype=np.float32));position+=gap_count
    combined=np.concatenate(pieces);write(a.output/'spoken-demo.wav',sr,combined)
    assert 100<=len(combined)/sr<=150,'Measure actual duration; do not force timing by stretching speech'
    _,restored=read(a.output/'spoken-demo.wav');assert np.array_equal(restored,combined)
    for row,x in zip(rows,sources):
        source=a.input/Path(row['file']).name
        assert row['source_sha256']==hashlib.sha256(source.read_bytes()).hexdigest()
        begin=round(row['start_seconds']*sr);end=round(row['end_seconds']*sr)
        assert end-begin==len(x)
    transcript='# セリフ・話し声サンプル\n\n同じ3秒参照のローカル生成音声。歌唱加工なし。各行の元の速度・イントネーションを保持し、音量と行間だけを調整。\n\n'
    for row in rows:transcript+=f"- {stamp(row['start_seconds'])}〜{stamp(row['end_seconds'])}　{row['category']}：{row['text']}\n"
    (a.output/'transcript.md').write_text(transcript)
    shutil.copyfile(a.input/'report.json',a.output/'generation-report.json')
    result=dict(seconds=len(combined)/sr,sample_rate=sr,sentences=len(rows),gap_seconds=.35,common_gain_db=float(20*np.log10(common)),
        reference_sha256=report['reference_sha256'],source_unchanged=True,all_natural_eos=True,
        method='Complete utterances, static active-RMS gain per utterance and 350ms gaps. No trimming, pitch/time correction, EQ, reverb, music or singing processing.',
        technical_validation='PASS',pronunciation_and_identity_verified=False,trials=rows)
    (a.output/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(f'PASS: {len(rows)} complete utterances; {len(combined)/sr:.2f} seconds; original timing preserved')

if __name__=='__main__':main()
