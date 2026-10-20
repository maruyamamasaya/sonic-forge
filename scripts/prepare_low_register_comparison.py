"""Compare identical dialogue against lower-reference variants, with matched listening levels."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from vowel_chord_study import read,write,active_mask


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--previous',type=Path,required=True);p.add_argument('--current',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    old=json.loads((a.previous/'report.json').read_text());new=json.loads((a.current/'report.json').read_text())
    assert len(old['trials'])==len(new['trials'])==14
    for before,after in zip(old['trials'],new['trials']):
        assert before['text']==after['text'] and before['category']==after['category']
        assert before['pace']['mode']==after['pace']['mode']
    a.output.mkdir(parents=True,exist_ok=False)
    pieces=[];rows=[];sr=24000
    # Opening and correction line: one formerly baseline, one formerly bright reference.
    for index in [0,3]:
        pair=[]
        for folder,label,report in [(a.previous,'previous',old),(a.current,'lower-reference',new)]:
            entry=report['trials'][index];path=folder/'clips'/entry['file'];rate,x=read(path);assert rate==sr
            rms=np.sqrt(np.mean(x[active_mask(x,sr)].astype(float)**2));gain=10**(-25/20)/rms
            pair.append((x,gain));rows.append(dict(index=index+1,label=label,text=entry['text'],reference=entry['reference'],
                source_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        common=min(1.,10**(-3/20)/max(np.max(abs(x))*gain for x,gain in pair))
        for x,gain in pair:pieces.extend([(x*(gain*common)).astype(np.float32),np.zeros(round(.7*sr),dtype=np.float32)])
    combined=np.concatenate(pieces[:-1]);write(a.output/'00-previous-then-lower-examples.wav',sr,combined)
    _,check=read(a.output/'00-previous-then-lower-examples.wav');assert np.array_equal(check,combined)
    shutil.copyfile(a.current/'spoken-character-demo.wav',a.output/'low-register-demo.wav')
    shutil.copyfile(a.current/'generation-only-control.wav',a.output/'generation-only-control.wav')
    shutil.copyfile(a.current/'transcript.md',a.output/'transcript.md')
    references=[r['reference'] for r in new['trials']]
    assert sum(r.startswith('subdued') for r in references)==10 and sum(r.startswith('calm') for r in references)==4
    result=dict(seconds=new['seconds'],same_14_texts=True,reference_counts=dict(subdued=10,calm=4),example_order=rows,
        method='Different source-reference conditioning with identical texts and scene processing; no global pitch lowering',
        example_seconds=len(combined)/sr,low_register_perception_verified=False)
    (a.output/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
    shutil.copyfile(a.current/'report.json',a.output/'processing-report.json');shutil.copyfile(a.current/'generation-report.json',a.output/'generation-report.json')
    print(f'PASS: {new["seconds"]:.2f}s lower-reference reel; same 14 texts; example pairs matched for level')

if __name__=='__main__':main()
