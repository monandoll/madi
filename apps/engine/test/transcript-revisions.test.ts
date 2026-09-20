import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_SUBTITLE_STYLE, editDiff, type Video } from '@madi/shared';
import { Library } from '../src/library.js';
import { VideoStore } from '../src/videos.js';
import { runAction, type ActionDeps } from '../src/actions.js';
import { openDb } from '../src/db/index.js';
import { AgentRunner, type RunnerDeps } from '../src/agent/runner.js';
import { MIGRATIONS, openTestDb, tempHome } from './helpers.js';

describe('immutable subtitle revisions', () => {
  let home: string;
  let conn: ReturnType<typeof openTestDb>;
  let lib: Library;
  let video: Video;
  beforeEach(() => {
    home = tempHome('madi-revisions-');
    conn = openTestDb(home);
    lib = new Library(conn.db);
    video = { ...new VideoStore(conn.db).register({path:path.join(home,'source.mp4'),fileName:'source.mp4',sizeBytes:1,recordedAt:1}).video, status:'ready', durationSec:120, hasAudio:false };
  });
  afterEach(() => { conn.sqlite.close(); fs.rmSync(home,{recursive:true,force:true}); });
  const text = (value: string) => ({language:'ko',model:'manual',segments:[{id:'line',start:10,end:13,text:value,words:[]}]});
  const originalEdit = (transcriptId: string) => lib.createEdit({videoId:video.id,title:'숏폼',keep:{start:10,end:40},parts:[{start:25,end:40},{start:10,end:25}],cuts:[{start:15,end:16,reason:'manual'}],crop:'vertical',cropFocus:1,subtitles:true,transcriptId,subtitleStyle:{...DEFAULT_SUBTITLE_STYLE,bottom:0.7},subtitleAuto:false,emphasis:[{term:'어깨',start:10,end:13}],speed:[]});

  it('keeps source versions immutable and output-only wording out of source analysis', () => {
    const a=lib.setTranscript(video.id,text('원본 음성'));
    const edit=originalEdit(a.id);
    const b=lib.setTranscript(video.id,text('교정한 음성'));
    const custom=lib.setTranscript(video.id,text('원하는 안내 문구'),{source:false});
    expect(new Set([a.id,b.id,custom.id]).size).toBe(3);
    expect(lib.transcriptForEdit(edit)?.segments[0]?.text).toBe('원본 음성');
    expect(lib.transcriptOf(video.id)?.id).toBe(b.id);
    expect(lib.transcript(custom.id)?.segments[0]?.text).toBe('원하는 안내 문구');
    expect(lib.transcriptForEdit({...edit,transcriptId:'missing'})).toBeNull();
  });

  it('manual revision preserves all other edit decisions and never requires speech recognition', () => {
    const a=lib.setTranscript(video.id,text('어깨를 펴세요'));
    const edit=originalEdit(a.id);
    const b=lib.setTranscript(video.id,text('어깨 힘 빼기'),{source:false});
    const queued: any[]=[];
    const deps={library:lib,events:{record(){}},queue:{enqueue(payload: unknown){queued.push(payload);return{id:'render',payload};}}} as unknown as ActionDeps;
    runAction(deps,video,{type:'subtitle',editId:edit.id,transcriptId:b.id});
    expect(queued).toHaveLength(1);
    expect(queued[0].type).toBe('render');
    const revised=lib.edit(queued[0].editId)!;
    expect(revised).toEqual({...edit,id:revised.id,createdAt:revised.createdAt,revisionOf:edit.id,transcriptId:b.id});
    expect(lib.edit(edit.id)).toEqual(edit);
    expect(editDiff(edit,revised)).toMatchObject({changed:true,subtitleText:true});
    const empty=lib.setTranscript(video.id,{...text(''),segments:[]},{source:false});
    runAction(deps,video,{type:'subtitle',editId:revised.id,transcriptId:empty.id});
    expect(lib.edit(queued[1].editId)).toMatchObject({subtitles:false,keep:edit.keep,parts:edit.parts,crop:'vertical'});
  });

  it('rejects another video’s edit or subtitle version before queuing work', () => {
    const other=new VideoStore(conn.db).register({path:path.join(home,'other.mp4'),fileName:'other.mp4',sizeBytes:1,recordedAt:1}).video;
    const otherText=lib.setTranscript(other.id,text('다른 영상'));
    const own=originalEdit(lib.setTranscript(video.id,text('내 영상')).id);
    const deps={library:lib,events:{record(){}},queue:{enqueue(){throw new Error('must not enqueue');}}} as unknown as ActionDeps;
    expect(()=>runAction(deps,video,{type:'subtitle',editId:own.id,transcriptId:otherText.id})).toThrow('not_found');
    expect(()=>runAction(deps,{...other,status:'ready'}, {type:'subtitle',editId:own.id})).toThrow('not_found');
  });

  it('identifies the selected version even when outputs have identical titles', () => {
    const runner = new AgentRunner({ library: lib } as RunnerDeps);
    const old = originalEdit(lib.setTranscript(video.id,text('과거 문구')).id);
    const next = lib.reviseEdit(old, { transcriptId: lib.setTranscript(video.id,text('새 문구')).id });
    for (const edit of [old, next]) lib.addOutput({videoId:video.id,editId:edit.id,title:'숏폼',kind:'short',path:'unused.mp4',durationSec:30,width:1080,height:1920,sizeBytes:1});
    const prompt = runner.buildPrompt(video, '이 문장을 고쳐줘', 'unused', old.id);
    expect(prompt).toContain(`이번 요청에서 사용자가 선택한 결과물: editId=${old.id}`);
  });
});

it('upgrades an existing single-transcript database without losing edit references', () => {
  const home=tempHome('madi-migration-');
  const oldDir=path.join(home,'migrations');
  fs.mkdirSync(path.join(oldDir,'meta'),{recursive:true});
  const journal=JSON.parse(fs.readFileSync(path.join(MIGRATIONS,'meta/_journal.json'),'utf8'));
  journal.entries=journal.entries.filter((entry:{idx:number})=>entry.idx<12);
  fs.writeFileSync(path.join(oldDir,'meta/_journal.json'),JSON.stringify(journal));
  for(const entry of journal.entries) fs.copyFileSync(path.join(MIGRATIONS,`${entry.tag}.sql`),path.join(oldDir,`${entry.tag}.sql`));
  const dbPath=path.join(home,'old.db');
  const old=openDb(dbPath,oldDir);
  old.sqlite.exec(`INSERT INTO videos (id,path,file_name,title,size_bytes,recorded_at,created_at,updated_at) VALUES ('v','v.mp4','v.mp4','v',1,1,1,1);
    INSERT INTO transcripts VALUES ('t','v','ko','base','[]',1);
    INSERT INTO edits (id,video_id,title,cuts,subtitles,transcript_id,subtitle_style,speed,created_at) VALUES ('e','v','old','[]',1,'t','${JSON.stringify(DEFAULT_SUBTITLE_STYLE)}','[]',1);
    INSERT INTO edits (id,video_id,title,cuts,subtitles,subtitle_style,speed,created_at) VALUES ('fallback','v','old fallback','[]',1,'${JSON.stringify(DEFAULT_SUBTITLE_STYLE)}','[]',1);`);
  old.sqlite.close();
  const next=openDb(dbPath,MIGRATIONS);
  try {
    const lib=new Library(next.db);
    expect(lib.transcriptForEdit(lib.edit('e')!)?.id).toBe('t');
    expect(lib.transcriptForEdit(lib.edit('fallback')!)?.id).toBe('t');
    const revised=lib.setTranscript('v',{language:'ko',model:'manual',segments:[]});
    expect(revised.id).not.toBe('t');
    expect(lib.transcript('t')).not.toBeNull();
    expect(lib.transcriptOf('v')?.id).toBe(revised.id);
  } finally {next.sqlite.close();fs.rmSync(home,{recursive:true,force:true});}
});
