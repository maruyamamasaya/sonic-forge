from pathlib import Path
import subprocess,json,hashlib,shutil
import argparse, math
parser=argparse.ArgumentParser(description='Bounded local analysis: two 12-second song excerpts and one voice excerpt; no uploads or downloads.')
parser.add_argument('--song-a',type=Path,required=True)
parser.add_argument('--song-b',type=Path,required=True)
parser.add_argument('--voice',type=Path,required=True)
parser.add_argument('--song-start',type=float,default=40)
parser.add_argument('--voice-start',type=float,default=8)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1];out=root/'build/midi-materials'
if not all(math.isfinite(v) and v >= 0 for v in (args.song_start,args.voice_start)): raise SystemExit('Start positions must be finite and non-negative')
ffmpeg=shutil.which('ffmpeg'); ffprobe=shutil.which('ffprobe')
if not ffmpeg or not ffprobe: raise SystemExit('ffmpeg and ffprobe are required on PATH')
out.mkdir(parents=True,exist_ok=True)
if any((out/name).exists() for name in ('song-a','song-b','voice')): raise SystemExit('Existing analysis is protected; preserve it and choose a fresh workspace.')
files=[args.song_a.resolve(),args.song_b.resolve(),args.voice.resolve()]
inventory=[]
for i,f in enumerate(files):
 info=json.loads(subprocess.check_output([ffprobe,'-v','quiet','-show_format','-of','json',str(f)]))
 inventory.append({'id':i,'name':f.name,'duration':float(info['format']['duration']),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
(out/'inventory.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2))
for label,f,start in [('song-a',args.song_a,args.song_start),('song-b',args.song_b,args.song_start),('voice',args.voice,args.voice_start)]:
 f=f.resolve()
 d=out/label
 if d.exists(): raise SystemExit('Existing analysis directory is protected: '+str(d))
 d.mkdir()
 wav=d/'input.wav'
 if not wav.exists():subprocess.run([ffmpeg,'-v','error','-n','-ss',str(start),'-t','12','-i',str(f),'-ar','44100','-ac','2','-c:a','pcm_f32le',str(wav)],check=True)
 (d/'source.json').write_text(json.dumps({'source':f.name,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'start_seconds':start,'seconds':12},ensure_ascii=False,indent=2))
 if label!='voice' and not (d/'manifest.json').exists():
  req={'version':1,'jobID':label,'cache':str(root/'build/separation-bench/cache/mlx'),'input':str(wav)}
  (d/'request.json').write_text(json.dumps(req))
  print('Separating',label,flush=True)
  subprocess.run([str(root/'build/separation-bench/venv/bin/python'),'scripts/separation_worker.py','--request',str(d/'request.json'),'--mode','separate'],check=True,stdout=open(d/'worker.log','w'),stderr=subprocess.STDOUT)
 print('Ready',label,flush=True)
print('Inventoried',len(inventory),'files; separated only 24 seconds locally')
