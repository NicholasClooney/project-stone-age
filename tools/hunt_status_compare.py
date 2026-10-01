"""Compare true Backend rolls and actual Web client traffic/CPU in alternating runs."""
import subprocess, os, time, json, pathlib
# Caller serves each exported Web build on private localhost ports.
# Only Popen-created test servers are terminated; never the live game.
import argparse, platform, shutil
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline',required=True,type=pathlib.Path)
parser.add_argument('--modules',required=True)
parser.add_argument('--chrome',required=True)
parser.add_argument('--out',required=True,type=pathlib.Path)
parser.add_argument('--before-url',required=True)
parser.add_argument('--after-url',required=True)
parser.add_argument('--runs',type=int,default=3)
a=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
modules=a.modules;chrome=a.chrome
a.out.mkdir(parents=True,exist_ok=True)
shutil.copyfile(root/'client/tools/hunt_status_probe.gd',a.baseline/'client/tools/hunt_status_probe.gd')
metadata={'machine':platform.platform(),'processor':platform.processor(),'cores':os.cpu_count(),'load_start':os.getloadavg(),'runs':[]}
(a.out/'machine.json').write_text(json.dumps(metadata,indent=2))
for label,run in [(label,run) for run in range(1,a.runs+1) for label in ('before','after')]:
    repo=root if label=='after' else a.baseline
    name=str(a.out/f'hunt-web-{label}-{run}')
    probe=name+'.backend.json';marker=name+'.start'
    for path in [probe,probe+'.ready',marker]:pathlib.Path(path).unlink(missing_ok=True)
    env=dict(os.environ,STONE_AGE_TEST_USER_DIR=f'Godot/app_userdata/Stone Age tests/hunt-probe-{label}-{run}')
    log=open(name+'.backend.log','w')
    server=subprocess.Popen([str(repo/'.tools/Godot.app/Contents/MacOS/Godot'),'--headless','--path','client','--audio-driver','Dummy','--log-file',name+'.godot.log','--script','res://tools/hunt_status_probe.gd','--','--marker='+marker,'--out='+probe],cwd=repo,env=env,stdout=log,stderr=subprocess.STDOUT)
    try:
        deadline=time.monotonic()+30
        while not pathlib.Path(probe+'.ready').exists():
            if server.poll() is not None or time.monotonic()>deadline:raise RuntimeError('probe startup failed')
            time.sleep(.05)
        with open(name+'.browser.log','w') as browser_log:
            subprocess.run(['node','tools/hunt_status_web_probe.mjs','--modules',modules,'--chrome',chrome,'--url',a.after_url if label=='after' else a.before_url,'--probe',probe,'--marker',marker,'--out',name],cwd=root,stdout=browser_log,stderr=subprocess.STDOUT,check=True,timeout=300)
        row=json.loads(pathlib.Path(name+'.json').read_text())
        metadata['runs'].append({'label':label,'run':run,'load':os.getloadavg(),'results':name+'.json'})
        (a.out/'machine.json').write_text(json.dumps(metadata,indent=2))
        print(label,run,{k:row[k] for k in ['statuses','status_bytes','main_thread_task_ms_per_second']},flush=True)
    finally:
        # Only this Popen child; no real save, temporary test authority.
        server.terminate();server.wait(timeout=15);log.close()
