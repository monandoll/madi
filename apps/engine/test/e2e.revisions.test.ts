import fs from 'node:fs';
import path from 'node:path';
import { afterAll, beforeAll, expect, it } from 'vitest';
import { ActionResponse, OutputDetailResponse, TranscriptResponse, VideoDetailResponse, VideoFramesSummary } from '@madi/shared';
import { startEngine, type Engine } from '../src/engine.js';
import { SAMPLE_SILENT, freePort, tempHome, waitFor } from './helpers.js';

let engine: Engine;
let home: string;
let videoId: string;
const request = async (url: string, body?: unknown, method = 'POST', headers: Record<string,string> = {}) => {
  const res=await fetch(`${engine.url}${url}`,{method,headers:{'content-type':'application/json',...headers},...(body === undefined ? {} : {body:JSON.stringify(body)})});
  expect(res.ok, await (res.ok ? Promise.resolve('') : res.clone().text())).toBe(true);
  return res.json();
};
const detail = async () => VideoDetailResponse.parse(await request(`/api/videos/${videoId}`,undefined,'GET'));
const output = async (id:string) => OutputDetailResponse.parse(await request(`/api/outputs/${id}`,undefined,'GET'));
const act = async (body:unknown) => {
  const action=ActionResponse.parse(await request(`/api/videos/${videoId}/actions`,body));
  await waitFor(()=> ['done','failed'].includes(engine.queue.get(action.job!.id)?.status ?? ''),60000);
  expect(engine.queue.get(action.job!.id)?.status).toBe('done');
  const card=engine.library.messageForJob(action.job!.id)!;
  return output(card.outputId!);
};
const tool=async(name:string,input:unknown)=>{
  const response=await request(`/api/agent/tools/${name}`,{videoId,input},'POST',{'x-madi-agent':engine.agent.token});
  expect(response.ok, response.error).toBe(true);
  return response.result;
};

beforeAll(async()=>{
  home=tempHome('madi-e2e-revisions-');
  const folder=path.join(home,'videos');
  fs.mkdirSync(folder);
  fs.copyFileSync(SAMPLE_SILENT,path.join(folder,'시범.mp4'));
  process.env['MADI_QUIET']='1';
  engine=await startEngine({dataDir:home,dbPath:path.join(home,'test.db'),port:await freePort()});
  await request('/api/settings',{watchFolders:[folder],setupDone:true,ai:{provider:'none'}},'PATCH');
  await waitFor(()=>engine.videos.listVisible().some(v=>v.status==='ready'),60000);
  videoId=engine.videos.listVisible()[0]!.id;
});
afterAll(async()=>{await engine?.stop(); if(home)fs.rmSync(home,{recursive:true,force:true});});

it('edits custom captions on a silent short without resetting framing, overwriting history, or transcribing', async()=>{
  const first=await act({type:'short',range:{start:0.5,end:2.5},subtitles:false});
  const added=TranscriptResponse.parse(await request(`/api/videos/${videoId}/transcript`,{editId:first.edit.id,segments:[{start:0.5,end:1.5,text:'원하는 안내 문구'}]},'PUT'));
  const second=await act({type:'subtitle',editId:first.edit.id,transcriptId:added.transcript.id});
  expect(second.edit).toMatchObject({keep:first.edit.keep,crop:first.edit.crop,revisionOf:first.edit.id});
  expect(second.output.width).toBe(1080);
  expect(second.output.height).toBe(1920);
  expect(Math.abs(second.output.durationSec-first.output.durationSec)).toBeLessThan(0.1);
  expect(second.transcript?.segments[0]?.text).toBe('원하는 안내 문구');
  expect((await detail()).transcript).toBeNull();

  const changed=await tool('set_subtitle_text',{editId:second.edit.id,replaceAll:true,lines:[{start:0.5,end:1.5,text:'수정한 안내 문구'}]});
  expect(changed.editId).not.toBe(second.edit.id);
  // Even a later AI style/edit operation must retain this output-only wording.
  const edited=await tool('apply_edit',{editId:changed.editId,subtitles:true,title:'수정본'});
  const rendered=await tool('render',{editId:edited.editId});
  const third=await output(rendered.outputId);
  expect(third.transcript?.segments[0]?.text).toBe('수정한 안내 문구');
  expect((await output(second.output.id)).transcript?.segments[0]?.text).toBe('원하는 안내 문구');
  expect((await output(first.output.id)).transcript).toBeNull();
  expect((await tool('get_transcript',{editId:second.edit.id})).segments[0].text).toBe('원하는 안내 문구');
  expect(engine.queue.list().some(j=>j.type==='transcribe')).toBe(false);

  const cleared=await tool('set_subtitle_text',{editId:third.edit.id,replaceAll:true,lines:[]});
  const final=await output((await tool('render',{editId:cleared.editId})).outputId);
  expect(final.edit.subtitles).toBe(false);
  expect(final.edit.keep).toEqual(first.edit.keep);
  expect(final.transcript?.segments).toEqual([]);
  expect((await detail()).outputs[0]?.id).toBe(final.output.id);
  expect((await fetch(`${engine.url}${final.output.downloadUrl}`,{method:'HEAD'})).status).toBe(200);
});

it('rejects reversed and out-of-bounds subtitle timestamps at the API',async()=>{
  for(const range of [{start:2,end:1},{start:0,end:100}]) {
    const res=await fetch(`${engine.url}/api/videos/${videoId}/transcript`,{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({segments:[{...range,text:'문구'}]})});
    expect(res.status).toBe(400);
  }
});

it('delivers real video images with source/output times and respects the frames setting', async () => {
  const selected = (await detail()).outputs[0]!;
  const inspect = (input: unknown) => request('/api/agent/tools/inspect_video_frames', { videoId, input }, 'POST', { 'x-madi-agent': engine.agent.token });
  const response = await inspect({ editId: selected.editId, range: { start: 1, end: 2 }, count: 4 });
  expect(response.ok, response.error).toBe(true);
  const summary = VideoFramesSummary.parse(response.result);
  expect(summary.sheets[0]?.frames).toHaveLength(4);
  expect(summary.sheets[0]?.frames[0]?.sourceTime).toBeCloseTo(1.05);
  expect(summary.sheets[0]?.frames[0]?.outputTime).toBeCloseTo(0.55);
  expect(response.images).toHaveLength(1);
  const jpeg = Buffer.from(response.images[0].data, 'base64');
  expect(jpeg.subarray(0, 3)).toEqual(Buffer.from([0xff, 0xd8, 0xff]));
  expect(jpeg.length).toBeGreaterThan(1000);
  expect(fs.readdirSync(engine.cfg.workDir).filter(f => f.startsWith('vision-'))).toEqual([]);
  expect((await inspect({ editId: 'missing' })).ok).toBe(false);
  await request('/api/settings', { ai: { provider: 'none', frames: false } }, 'PATCH');
  const disabled = await inspect({ count: 4 });
  expect(disabled.ok).toBe(false);
  expect(disabled.images).toBeUndefined();
  expect(disabled.error).toContain('꺼져');
  await request('/api/settings', { ai: { provider: 'none', frames: true } }, 'PATCH');
});
