"""Read-only use of an installed 1.7B CustomVoice model for lower-register instruction tests.
Uses a preset speaker, not the private reference speaker.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
from local_vowel_model_study import mx,np,load_model,network_attempts
from scipy.io import wavfile
from vowel_chord_study import read,write,active_mask


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();config=json.loads((a.model/'config.json').read_text())
    assert config['tts_model_type']=='custom_voice' and config['tts_model_size']=='1b7'
    config_sha=hashlib.sha256((a.model/'config.json').read_bytes()).hexdigest()
    metadata=a.model/'.cache/huggingface/download/config.json.metadata'
    revision=metadata.read_text().splitlines()[0] if metadata.exists() else 'unrecorded'
    a.output.mkdir(parents=True,exist_ok=False);(a.output/'raw').mkdir()
    mx.set_memory_limit(10*1024**3);mx.set_cache_limit(256*1024**2)
    model=load_model(a.model.resolve(),trust_remote_code=False)
    text='来てくれて、ありがとう。今日は、あなたと話せてよかった。また、会えるといいね。'
    styles=[('01-neutral','通常',None),
      ('02-low-calm','低め・穏やか','Speak in a slightly lower register, calm and conversational, with a warm, clear tone. Keep the delivery natural, not whispered.'),
      ('03-low-quick','低め・少し早口','Use a slightly lower, warm speaking voice. Speak a little quickly and casually, as if talking to a close friend. Keep the words clear.'),
      ('04-low-changing','低め・途中で表情を変える','Use a slightly lower natural speaking register. Begin with warm happiness, become briefly hesitant and a little wistful in the middle, then end gently hopeful. Keep a single consistent speaker.'),
      ('05-low-husky','低め・少しかすれた感じ','Use a slightly lower, gently husky conversational voice, as if a little tired after talking. Stay clear and gentle, not a whisper, not exaggerated.')]
    audio=[];rows=[]
    for name,label,instruction in styles:
        mx.random.seed(7);start=time.monotonic()
        result=list(model.generate_custom_voice(text=text,speaker='Ono_Anna',language='Japanese',instruct=instruction,max_tokens=256,
            temperature=.7,top_k=50,top_p=.95,repetition_penalty=1.1,stream=False,verbose=False))
        assert len(result)==1;result=result[0];x=np.array(result.audio,dtype=np.float32).reshape(-1)
        assert np.isfinite(x).all() and .3<len(x)/result.sample_rate<20.6 and .0001<np.max(abs(x))<1
        sr=result.sample_rate;path=a.output/'raw'/(name+'.wav');wavfile.write(path,sr,x)
        rate,y=read(path);assert rate==sr and np.array_equal(x,y)
        audio.append(x);rows.append(dict(file=name+'.wav',label=label,text=text,instruct=instruction,speaker='Ono_Anna',
            seed=7,seconds=len(x)/sr,tokens=int(result.token_count),limit_reached=int(result.token_count)>=256,
            raw_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),inference_seconds=time.monotonic()-start,
            listening_verified=False))
        (a.output/'progress.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2));print(json.dumps(rows[-1],ensure_ascii=False),flush=True);mx.clear_cache()
    assert not any(r['limit_reached'] for r in rows)
    gains=[10**(-25/20)/np.sqrt(np.mean(x[active_mask(x,sr)].astype(float)**2)) for x in audio]
    common=min(1.,10**(-3/20)/max(np.max(abs(x))*g for x,g in zip(audio,gains)))
    pieces=[]
    for x,g,row in zip(audio,gains,rows):
        y=(x*(g*common)).astype(np.float32);write(a.output/row['file'],sr,y)
        row['listening_gain_db']=float(20*np.log10(g*common));pieces.extend([y,np.zeros(round(.7*sr),dtype=np.float32)])
    combined=np.concatenate(pieces[:-1]);write(a.output/'00-customvoice-low-comparison.wav',sr,combined)
    assert config_sha==hashlib.sha256((a.model/'config.json').read_bytes()).hexdigest()
    (a.output/'report.json').write_text(json.dumps(dict(model='Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit',revision=revision,config_sha256=config_sha,
        speaker='Ono_Anna',private_reference_used=False,preset_is_different_from_base_reference=True,all_natural_eos=True,
        blocked_network_attempts=len(network_attempts),audio_sent_to_external_service=False,seconds=len(combined)/sr,
        method='Same preset/text/seed, direct generation instruct varied; constant listening gain only, no pitch or speed postprocessing',
        trials=rows,lower_register_and_expression_verified=False),ensure_ascii=False,indent=2))
    (a.output/'comparison.md').write_text('# 1.7B CustomVoice低めの指示比較\n\nOno_Anna（元の参照声とは別のプリセット話者）。\n\n順番: 通常 → 低め/穏やか → 低め/少し早口 → 低め/途中で表情を変える → 低め/少しかすれた感じ。\n\n'+text+'\n\n音量のみ調整。指示通りに聞こえるかは試聴待ち。\n')
    print('PASS: 5 preset CustomVoice instruction candidates, no reference upload, listening required',flush=True)

if __name__=='__main__':main()
