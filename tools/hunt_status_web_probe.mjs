// Real Web client + real authority probe. No mocked game data/WS messages.
// See docs/technical/hunt-status-performance.md for invocation and scope.
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
const a=Object.fromEntries(process.argv.slice(2).reduce((p,v,i,s)=>{if(v.startsWith('--'))p.push([v.slice(2),s[i+1]]);return p},[]));
const require=createRequire(`${a.modules}/package.json`);
const {chromium}=require('playwright-core');
const ready=JSON.parse(readFileSync(`${a.probe}.ready`));
const browser=await chromium.launch({headless:true,executablePath:a.chrome,args:['--disable-background-timer-throttling','--disable-renderer-backgrounding','--autoplay-policy=no-user-gesture-required']});
try {
 const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
 const errors=[];page.on('pageerror',e=>{errors.push(String(e));console.log('PAGEERROR',String(e))});page.on('console',m=>{if(m.type()==='error')console.log('CONSOLE',m.text())});
 const cdp=await page.context().newCDPSession(page);
 await cdp.send('Network.enable');await cdp.send('Performance.enable');
 let measuring=false,statuses=0,bytes=0,notifications=0,allMessages=0,allBytes=0;
 const bins={};
 const commands=[];cdp.on("Network.webSocketFrameSent",({response})=>{try{commands.push(JSON.parse(response.payloadData))}catch{}});
 let start=0;
 cdp.on('Network.webSocketFrameReceived',({response})=>{
  if(!measuring)return;
  const body=response.payloadData;allMessages++;allBytes+=Buffer.byteLength(body);
  try {const m=JSON.parse(body);if(m.type==='auto_status') {statuses++;bytes+=Buffer.byteLength(body);const second=Math.floor((performance.now()-start)/1000);bins[second]=(bins[second]||0)+1;}if(m.type==='pet_log_changed')notifications++;} catch {}
 });
 await page.goto(`${a.url}/?server=ws://127.0.0.1:${ready.port}`,{waitUntil:'domcontentloaded'});
 try {await page.waitForFunction(()=>window.stoneAge?.online && window.stoneAge?.map===100,null,{timeout:90000});} catch(e) {await page.screenshot({path:`${a.out}.error.png`});console.log('STATE',await page.evaluate(()=>window.stoneAge));throw e;}
 await page.screenshot({path:`${a.out}.initial.png`});
 // 1280×800 canvas letterboxed in the fixed 390×844 viewport.
 // Actual 最小化 button: observed/verified by the saved initial screenshot.
 await page.mouse.click(269,515);
 await page.waitForFunction(()=>window.stoneAge?.pending===0 && !window.stoneAge?.waiting_screen,null,{timeout:180000});
 await page.waitForTimeout(2000);
 const start_game=await page.evaluate(()=>window.stoneAge);
 const before=Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m=>[m.name,m.value]));
 start=performance.now();measuring=true;
 writeFileSync(a.marker,'start');
 while(!existsSync(a.probe)){await page.waitForTimeout(50);if(performance.now()-start>120000)throw Error('probe timeout');}
 measuring=false;const seconds=(performance.now()-start)/1000;
 const after=Object.fromEntries((await cdp.send('Performance.getMetrics')).metrics.map(m=>[m.name,m.value]));
 await page.screenshot({path:`${a.out}.png`});
 // Post-measurement real UI interactions; never counted as benchmark work.
 const command_offset=commands.length;
 await page.mouse.click(375,515);await page.waitForTimeout(300);
 await page.screenshot({path:`${a.out}.expanded.png`});
 await page.mouse.click(222,515);await page.waitForTimeout(700);
 await page.screenshot({path:`${a.out}.records.png`});
 await page.mouse.click(235,309);await page.waitForTimeout(500);
 await page.screenshot({path:`${a.out}.queue.png`});
 await page.mouse.click(198,309);await page.waitForTimeout(500);
 await page.mouse.click(70,321);await page.waitForTimeout(500);
 await page.screenshot({path:`${a.out}.uncaught.png`});
 const interaction_commands=commands.slice(command_offset);
 const result={viewport:[390,844],browser:browser.version(),seconds,statuses,status_bytes:bytes,status_hz:statuses/seconds,status_bytes_per_second:bytes/seconds,pet_log_notifications:notifications,allMessages,allBytes,per_second:bins,main_thread_task_ms_per_second:(after.TaskDuration-before.TaskDuration)*1000/seconds,script_ms_per_second:(after.ScriptDuration-before.ScriptDuration)*1000/seconds,layout_ms_per_second:(after.LayoutDuration-before.LayoutDuration)*1000/seconds,errors,interaction_commands,start_game,game:await page.evaluate(()=>window.stoneAge),backend:JSON.parse(readFileSync(a.probe))};
 if(!interaction_commands.some(c=>c.type==='hunt_queue') || !interaction_commands.some(c=>c.type==='pet_log' && c.kind==='released' && c.uncaught===true))throw Error('record UI interactions did not reach authority');
 if(result.backend.rolls!==6000)throw Error(`invalid workload: ${result.backend.rolls} rolls`);
 writeFileSync(`${a.out}.json`,JSON.stringify(result,null,2));console.log(JSON.stringify({...result,backend:{...result.backend,queue:undefined,rows:undefined}}));
} finally {await browser.close();}
