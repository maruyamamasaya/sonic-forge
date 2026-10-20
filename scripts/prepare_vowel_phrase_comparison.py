"""Compare the approved U melody against a phrase-alternating A/U rendition."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from vowel_chord_study import read,write


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--previous',type=Path,required=True);p.add_argument('--rendered',type=Path,required=True)
    p.add_argument('--phrases',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    oldpath=a.previous/'gymnopedie-vibrato.wav';newpath=a.rendered/'gymnopedie-vibrato.wav'
    sr,old=read(oldpath);rate,new=read(newpath);assert rate==sr==24000 and len(old)==len(new)
    oldhash=hashlib.sha256(oldpath.read_bytes()).hexdigest();newhash=hashlib.sha256(newpath.read_bytes()).hexdigest()
    choruspath=a.previous/'unchanged-chorus.wav'
    assert choruspath.read_bytes()==(a.rendered/'unchanged-chorus.wav').read_bytes()
    _,chorus=read(choruspath);_,lead=read(a.rendered/'vibrato-melody.wav')
    lead=lead.astype(float);aa=np.mean(lead**2);bb=2*np.mean(lead*chorus)
    cc=np.mean(chorus.astype(float)**2)-np.mean(old.astype(float)**2)
    gain=(-bb+np.sqrt(bb*bb-4*aa*cc))/(2*aa);lead*=gain;mix=lead+chorus
    write(a.output/'gymnopedie-phrase-vowels.wav',sr,mix.astype(np.float32))
    write(a.output/'phrase-melody.wav',sr,lead.astype(np.float32))
    shutil.copyfile(oldpath,a.output/'previous-version.wav');shutil.copyfile(choruspath,a.output/'unchanged-chorus.wav')
    # Include both the U->A and A->U phrase boundaries in the comparison.
    first,last=round(8.3*sr),round(23*sr)
    pair=np.concatenate([old[first:last],np.zeros(sr,dtype=np.float32),mix[first:last].astype(np.float32)])
    write(a.output/'00-previous-then-phrase-vowels.wav',sr,pair)
    phrases=json.loads((a.phrases/'report.json').read_text())
    expected=['u','a','u','a']
    assert phrases['phrase_vowels']==','.join(expected)
    for event in phrases['transitions']:assert event['vowel']==expected[int(event['beat']//12)]
    _,actual=read(a.output/'gymnopedie-phrase-vowels.wav');_,actual_lead=read(a.output/'phrase-melody.wav')
    assert np.max(abs(actual-actual_lead-chorus))<1e-7
    rms_difference=20*np.log10(np.linalg.norm(actual.astype(float))/np.linalg.norm(old.astype(float)))
    assert abs(rms_difference)<.001
    assert np.max(abs(actual))<10**(-3/20)
    assert oldpath.read_bytes()==(a.output/'previous-version.wav').read_bytes()
    assert choruspath.read_bytes()==(a.output/'unchanged-chorus.wav').read_bytes()
    assert oldhash==hashlib.sha256(oldpath.read_bytes()).hexdigest() and newhash==hashlib.sha256(newpath.read_bytes()).hexdigest()
    report=dict(seconds=len(old)/sr,phrase_vowels=expected,beats_per_phrase=12,source_hashes=dict(previous=oldhash,rendered=newhash),
        sources_unchanged=True,chorus_bytes_identical=True,previous_bytes_identical=True,
        comparison_source_seconds=[8.3,23],rms_difference_db=float(rms_difference),melody_gain_db=float(20*np.log10(gain)),
        phrase_transitions=phrases['transitions'],original_A_pitch_drift_retained=True,
        method='approved A/U samples assigned per phrase; original expressive arcs, legato timing and shallow vibrato reused',
        new_ai_generation=False,listening_quality_verified=False)
    (a.output/'report.json').write_text(json.dumps(report,indent=2))
    print('PASS: 43.25-second U/A/U/A melody, chorus identical, RMS matched, previous comparison preserved')

if __name__=='__main__':main()
