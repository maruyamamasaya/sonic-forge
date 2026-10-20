"""Level-match reference/punctuation style candidates without modifying delivery."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import re
import numpy as np
from vowel_chord_study import read,write,active_mask


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--references',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    report=json.loads((a.input/'report.json').read_text())
    assert report['all_references_unchanged'] and report['all_natural_eos']
    assert report['blocked_network_attempts']==0 and not report['audio_sent_to_external_service']
    a.output.mkdir(parents=True,exist_ok=False);(a.output/'clips').mkdir()
    rows=report['trials'];assert len(rows)==13
    core=lambda text:re.sub(r'[、。！!？?…\s]','',text)
    assert all(core(r['text'])==core(report['text']) for r in rows)
    audio={};raw={};gains={};hashes={}
    for row in rows:
        path=a.input/row['file'];sr,x=read(path);assert sr==24000 and not row['limit_reached']
        hashes[row['file']]=hashlib.sha256(path.read_bytes()).hexdigest();raw[row['file']]=x
        rms=np.sqrt(np.mean(x[active_mask(x,sr)].astype(float)**2));gains[row['file']]=10**(-25/20)/rms
    peak=max(float(np.max(abs(raw[k])))*gains[k] for k in raw);common=min(1.,10**(-3/20)/peak)
    for key,x in raw.items():
        y=(x*(gains[key]*common)).astype(np.float32);audio[key]=y;write(a.output/'clips'/key,24000,y)
    sr=24000;gap=np.zeros(round(.7*sr),dtype=np.float32);sequences={}
    def sequence(name,keys):
        pieces=[]
        for key in keys:pieces.extend([audio[key],gap])
        combined=np.concatenate(pieces[:-1]);write(a.output/name,sr,combined)
        _,check=read(a.output/name);assert np.array_equal(check,combined)
        sequences[name]=dict(order=keys,seconds=len(combined)/sr)
    sequence('01-three-expression-candidates.wav',[f'{s}-1-punctuation.wav' for s in ['bright','subdued','calm']])
    sequence('02-alternate-reference-candidates.wav',[f'{s}-2-punctuation.wav' for s in ['bright','subdued','calm']])
    sequence('03-reference-only-same-text.wav',[f'{s}-1-same-text.wav' for s in ['bright','subdued','calm']])
    shutil.copyfile(a.output/'clips/baseline-0-same-text.wav',a.output/'00-baseline.wav')
    shutil.copyfile(a.references/'00-reference-candidates.wav',a.output/'04-source-reference-candidates.wav')
    # Calm punctuation is unchanged: the two modes form a deterministic control.
    for variant in [1,2]:assert np.array_equal(raw[f'calm-{variant}-same-text.wav'],raw[f'calm-{variant}-punctuation.wav'])
    for row in rows:
        path=a.input/row['file'];assert hashes[row['file']]==hashlib.sha256(path.read_bytes()).hexdigest()
        _,restored=read(a.output/'clips'/row['file']);assert np.array_equal(restored,(raw[row['file']]*(gains[row['file']]*common)).astype(np.float32))
    transcript='# 同じセリフの調子比較\n\n'+report['text']+'\n\n'
    transcript+='3候補の順番は、明るめ（うれしい候補）→声を落とした感じ（悲しい候補）→穏やか（落ち着いた候補）。感情の成立/同一声質は未評価。\n\n'
    transcript+='01は参照候補1と句読点、02は別の参照候補2と句読点。03は句読点も完全同一で参照だけ変更。04は元音源からの参照6件。\n'
    (a.output/'comparison.md').write_text(transcript)
    result=dict(text=report['text'],source_hashes=hashes,sources_unchanged=True,all_natural_eos=True,sequences=sequences,
        original_word_sequence_unchanged=True,common_gain_db=float(20*np.log10(common)),
        method='Independent same-seed Base generations with reference and punctuation variants; constant RMS gain only. No pitch/time/EQ/reverb/emotion DSP.',
        calm_same_text_control_identical=True,emotions_and_speaker_identity_verified=False)
    (a.output/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));shutil.copyfile(a.input/'report.json',a.output/'generation-report.json')
    print('PASS: 13 unretimed utterances; three candidate styles x two references; same-text control; emotions unverified')

if __name__=='__main__':main()
