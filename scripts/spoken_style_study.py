"""Reference/punctuation style experiment with the local Base model.
No emotion-instruction support is assumed; labels remain listener hypotheses.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
from local_vowel_model_study import mx,np,load_model,load_audio,network_attempts
from scipy.io import wavfile


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model',type=Path,required=True);p.add_argument('--references',type=Path,required=True)
    p.add_argument('--baseline-reference',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    metadata=json.loads((a.references/'report.json').read_text())
    assert metadata['source_unchanged']
    neutral='来てくれて、ありがとう。今日は、あなたと話せてよかった。また、会えるといいね。'
    versions=dict(bright='来てくれて、ありがとう！今日は、あなたと話せてよかった！また、会えるといいね。',
        subdued='来てくれて、ありがとう…。今日は、あなたと話せてよかった…。また、会えるといいね…。',calm=neutral)
    core=lambda text:re.sub(r'[、。！!？?…\s]','',text)
    assert all(core(text)==core(neutral) for text in versions.values())
    mx.set_memory_limit(8*1024**3);mx.set_cache_limit(256*1024**2)
    model=load_model(a.model.resolve(),trust_remote_code=False)
    references=[dict(file=str(a.baseline_reference.resolve()),style='baseline',variant=0)]
    references+= [dict(entry,file=str((a.references/entry['file']).resolve())) for entry in metadata['references']]
    rows=[]
    for entry in references:
        refpath=Path(entry['file']);digest=hashlib.sha256(refpath.read_bytes()).hexdigest()
        reference=load_audio(str(refpath),sample_rate=model.sample_rate)
        ref_embedding=np.array(model.extract_speaker_embedding(reference)).flatten()
        modes=['same-text'] if entry['style']=='baseline' else ['same-text','punctuation']
        for mode in modes:
            text=neutral if mode=='same-text' else versions[entry['style']]
            mx.random.seed(7);start=time.monotonic()
            result=list(model.generate(text=text,ref_audio=reference,ref_text=None,lang_code='japanese',max_tokens=192,
                temperature=.7,top_k=50,top_p=.95,repetition_penalty=1.1,verbose=False,stream=False))
            assert len(result)==1;result=result[0];x=np.array(result.audio,dtype=np.float32).reshape(-1)
            assert np.isfinite(x).all() and .2<len(x)/result.sample_rate<15.5 and .0001<float(np.max(abs(x)))<1
            name=f"{entry['style']}-{entry['variant']}-{mode}.wav";path=a.output/name;wavfile.write(path,result.sample_rate,x)
            sr,restored=wavfile.read(path);assert sr==result.sample_rate and np.array_equal(restored,x)
            embedding=np.array(model.extract_speaker_embedding(mx.array(x))).flatten()
            cosine=float(np.dot(embedding,ref_embedding)/(np.linalg.norm(embedding)*np.linalg.norm(ref_embedding)))
            row=dict(file=name,reference_file=refpath.name,reference_sha256=digest,reference_unchanged=True,style_candidate=entry['style'],variant=entry['variant'],
                mode=mode,text=text,word_sequence_identical=core(text)==core(neutral),seconds=len(x)/sr,sample_rate=sr,
                seed=7,tokens=int(result.token_count),limit_reached=int(result.token_count)>=192,reference_embedding_cosine=cosine,
                postprocessing='none',inference_seconds=time.monotonic()-start,emotion_and_identity_verified=False)
            rows.append(row);(a.output/'progress.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
            print(json.dumps(row,ensure_ascii=False),flush=True)
            mx.clear_cache()
        assert digest==hashlib.sha256(refpath.read_bytes()).hexdigest()
    (a.output/'report.json').write_text(json.dumps(dict(text=neutral,trials=rows,all_references_unchanged=True,
        all_natural_eos=not any(r['limit_reached'] for r in rows),blocked_network_attempts=len(network_attempts),audio_sent_to_external_service=False,
        mode='Base speaker embedding only, no instruct, no reference transcript; reference and punctuation ablation',
        emotions_are_candidates=True),ensure_ascii=False,indent=2))
    print('PASS: local candidate generations; emotion/identity awaiting listening',flush=True)

if __name__=='__main__':main()
