"""Generate whole conversational utterances with textual disfluencies and source-reference variants.
Base model style labels are intentions, not guaranteed acting controls.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
from local_vowel_model_study import mx,np,load_model,load_audio,network_attempts
from scipy.io import wavfile


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model',type=Path,required=True);p.add_argument('--references',type=Path,required=True)
    p.add_argument('--baseline-reference',type=Path,required=True);p.add_argument('--prompts',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--low-register-anchor',type=Path,help='Optional liked utterance: retry higher-pitched candidates once, without pitch shifting')
    a=p.parse_args()
    entries=json.loads(a.prompts.read_text());assert 1<=len(entries)<=32
    refs={'baseline':a.baseline_reference}
    for label in ['bright','subdued','calm']:
        for i in [1,2]:refs[f'{label}-{i}']=a.references/f'{label}-{i}.wav'
    for entry in entries:
        assert entry['reference'] in refs and 1<=len(entry['text'])<=140
        assert entry['pace'] in ['normal','quick','accelerate','settle']
    a.output.mkdir(parents=True,exist_ok=False)
    mx.set_memory_limit(8*1024**3);mx.set_cache_limit(256*1024**2)
    model=load_model(a.model.resolve(),trust_remote_code=False);rows=[]
    anchor=None
    if a.low_register_anchor:
        from spoken_source_prosody import describe
        from vowel_chord_study import read
        anchor_sr,anchor_audio=read(a.low_register_anchor)
        anchor_description=describe(anchor_audio,anchor_sr)
        anchor=dict(median=anchor_description['pitch_median'],p90=float(np.percentile(anchor_description['pitch_curve'],90)),
                    sha256=hashlib.sha256(a.low_register_anchor.read_bytes()).hexdigest())
    hashes={key:hashlib.sha256(path.read_bytes()).hexdigest() for key,path in refs.items()}
    for i,entry in enumerate(entries,1):
        reference=load_audio(str(refs[entry['reference']].resolve()),sample_rate=model.sample_rate)
        started=time.monotonic();candidates=[]
        for seed in ([7,19] if anchor else [7]):
            mx.random.seed(seed)
            outputs=list(model.generate(text=entry['text'],ref_audio=reference,ref_text=None,lang_code='japanese',max_tokens=256,
                temperature=.7,top_k=50,top_p=.95,repetition_penalty=1.1,verbose=False,stream=False))
            assert len(outputs)==1;candidate=outputs[0];audio=np.array(candidate.audio,dtype=np.float32).reshape(-1)
            info=dict(seed=seed,tokens=int(candidate.token_count))
            if anchor:
                d=describe(audio,candidate.sample_rate)
                info.update(median=d['pitch_median'],p90=float(np.percentile(d['pitch_curve'],90)))
                info['score']=max(0.,info['median']-anchor['median']-1)**2+max(0.,info['p90']-anchor['p90']-1)**2+.1*abs(info['median']-anchor['median'])
            candidates.append((candidate,audio,info))
            if not anchor or (info['tokens']<256 and info['median']<=anchor['median']+2 and info['p90']<=anchor['p90']+2):break
            mx.clear_cache()
        eligible=([c for c in candidates if c[2]['tokens']<256 and np.isfinite(c[1]).all() and .0001<np.max(abs(c[1]))<1]
                  if anchor else candidates)
        assert eligible,'No complete finite candidate'
        result,x,selected=min(eligible,key=lambda c:c[2].get('score',0.))
        assert np.isfinite(x).all() and .3<len(x)/result.sample_rate<20.6 and .0001<np.max(abs(x))<1
        name=f'{i:02d}-spoken.wav';wavfile.write(a.output/name,result.sample_rate,x)
        sr,y=wavfile.read(a.output/name);assert sr==result.sample_rate and np.array_equal(x,y)
        row=dict(entry,file=name,reference_sha256=hashes[entry['reference']],seconds=len(x)/sr,sample_rate=sr,
            tokens=int(result.token_count),limit_reached=int(result.token_count)>=256,seed=selected['seed'],
            inference_seconds=time.monotonic()-started,postprocessing='none',performance_verified=False)
        if anchor:row.update(register_candidates=[c[2] for c in candidates],selected_register=selected)
        rows.append(row);(a.output/'progress.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
        print(json.dumps(row,ensure_ascii=False),flush=True);mx.clear_cache()
    assert all(hashes[k]==hashlib.sha256(path.read_bytes()).hexdigest() for k,path in refs.items())
    if anchor:assert anchor['sha256']==hashlib.sha256(a.low_register_anchor.read_bytes()).hexdigest()
    (a.output/'report.json').write_text(json.dumps(dict(trials=rows,all_references_unchanged=True,
        all_natural_eos=not any(r['limit_reached'] for r in rows),blocked_network_attempts=len(network_attempts),
        audio_sent_to_external_service=False,prompts_sha256=hashlib.sha256(a.prompts.read_bytes()).hexdigest(),
        low_register_anchor=anchor,
        method='Whole utterance Base generation, speaker embedding conditioning; disfluencies/emotional changes conveyed by text, no instruct support'),ensure_ascii=False,indent=2))
    print('PASS technical generation only; naturalness/acting require listening',flush=True)

if __name__=='__main__':main()
