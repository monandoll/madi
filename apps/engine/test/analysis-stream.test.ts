import { expect, it } from 'vitest';
import { parseMotion, parseScenes, parseSilences } from '@madi/ffmpeg-presets';
import { run, runAnalysis, SpawnError } from '../src/workers/spawn.js';

it('retains a full 25-minute analysis across stream chunks and diagnostic noise', async () => {
  const script = `
    let data='';
    for(let i=1;i<=6000;i++) {
      data+='frame:'+i+' pts_time:'+i/4+'\\nlavfi.signalstats.YDIF=4.5\\n';
      if(i===1) data+='silence_start: 0\\nsilence_end: 2\\n';
    }
    data+='[Parsed_showinfo] pts_time: 1499\\n'+'diagnostic noise '.repeat(6000)+'\\n';
    data+='silence_start: 1498\\nsilence_end: 1500';
    let i=0;
    function send(){if(i>=data.length)return;process.stderr.write(data.slice(i,i+719));i+=719;setImmediate(send);}
    send();`;
  const result=await runAnalysis(process.execPath,['-e',script]);
  const motion=parseMotion(result.stderr);
  expect(motion).toHaveLength(6000);
  expect(motion[0]?.t).toBe(0.25);
  expect(motion.at(-1)?.t).toBe(1500);
  expect(parseScenes(result.stderr)).toEqual([1499]);
  expect(parseSilences(result.stderr,1500)).toEqual([{start:0,end:2},{start:1498,end:1500}]);
  expect(result.stderr).not.toContain('diagnostic noise');
});

it('keeps ordinary process errors bounded and reports the actual failure', async () => {
  const script=`process.stderr.write('noise'.repeat(40000)+' final failure',()=>{process.exitCode=7;});`;
  try { await run(process.execPath,['-e',script]); throw new Error('expected failure'); }
  catch(error) { expect(error).toBeInstanceOf(SpawnError); const e=error as SpawnError; expect(e.code).toBe(7); expect(e.stderr.length).toBeLessThanOrEqual(64000); expect(e.message).toContain('final failure'); }
});
