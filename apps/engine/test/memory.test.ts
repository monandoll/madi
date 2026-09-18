/**
 * 제작자 기억 저장소 — 기획안 §12 "사용자가 승인하지 않은 내용을 영구적인 편집 성향으로 확정하지 않는다".
 * 완성본에서 온 것은 제안으로 들어오고, 확인해야 쓰이며, 뺀 것은 다시 제안하지 않는다.
 */
import fs from 'node:fs';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { MemoryStore } from '../src/style/memory.js';
import { openTestDb, tempHome } from './helpers.js';

let home: string;
let store: MemoryStore;
let close: () => void;

beforeEach(() => {
  home = tempHome('madi-memory-');
  const { db, sqlite } = openTestDb(home);
  store = new MemoryStore(db);
  close = () => sqlite.close();
});

afterEach(() => {
  close();
  fs.rmSync(home, { recursive: true, force: true });
});

describe('MemoryStore', () => {
  it('완성본에서 온 것은 제안, 직접 쓴 것과 편집 중 남긴 것은 바로 확인됨', () => {
    store.replaceFromReferences([{ text: '도입은 질문으로', kind: 'style', scope: 'all', evidence: ['a'] }]);
    store.add({ text: '견갑골', kind: 'term', scope: 'all', source: 'user' });
    store.add({ text: '이 영상만 인트로 없이', kind: 'style', scope: 'video', videoId: 'v1', source: 'feedback' });
    const all = store.list();
    expect(all.map((m) => [m.source, m.status])).toEqual([
      ['reference', 'proposed'],
      ['user', 'approved'],
      ['feedback', 'approved'],
    ]);
    expect(store.listApproved().map((m) => m.text)).toEqual(['견갑골', '이 영상만 인트로 없이']);
  });

  it('확인하면 쓰이고, 다시 배워도 확인 상태를 이어받는다', () => {
    store.replaceFromReferences([
      { text: 'A', kind: 'style', scope: 'all' },
      { text: 'B', kind: 'keep', scope: 'all' },
    ]);
    const a = store.list().find((m) => m.text === 'A')!;
    expect(store.approve([a.id])).toBe(1);
    expect(store.listApproved().map((m) => m.text)).toEqual(['A']);
    // 다시 배움: A 는 확인 유지, B 는 여전히 제안, C 는 새 제안
    store.replaceFromReferences([
      { text: 'A', kind: 'style', scope: 'all' },
      { text: 'B', kind: 'keep', scope: 'all' },
      { text: 'C', kind: 'avoid', scope: 'all' },
    ]);
    expect(store.list().map((m) => [m.text, m.status])).toEqual([
      ['A', 'approved'],
      ['B', 'proposed'],
      ['C', 'proposed'],
    ]);
    // ids 없이 approve 면 제안 전부
    expect(store.approve()).toBe(2);
    expect(store.list().every((m) => m.status === 'approved')).toBe(true);
  });

  it('뺀 제안은 다시 배워도 다시 제안하지 않는다', () => {
    store.replaceFromReferences([{ text: '싫은 것', kind: 'style', scope: 'all' }]);
    const bad = store.list()[0]!;
    expect(store.remove(bad.id)).toBe(true);
    expect(store.dismissed()).toEqual(['싫은 것']);
    store.replaceFromReferences([
      { text: '싫은 것', kind: 'style', scope: 'all' },
      { text: '괜찮은 것', kind: 'style', scope: 'all' },
    ]);
    expect(store.list().map((m) => m.text)).toEqual(['괜찮은 것']);
    // 직접 쓴 것을 빼도 dismissed 에는 안 들어간다 (다시 쓰면 그만)
    const mine = store.add({ text: '내 것', kind: 'style', scope: 'all', source: 'user' });
    store.remove(mine.id);
    expect(store.dismissed()).toEqual(['싫은 것']);
  });

  it('글을 고치면 확인한 것으로 본다', () => {
    store.replaceFromReferences([{ text: '도입은 질문으로', kind: 'style', scope: 'all' }]);
    const m = store.list()[0]!;
    const next = store.updateText(m.id, '도입은 질문 하나로 연다')!;
    expect(next).toMatchObject({ text: '도입은 질문 하나로 연다', status: 'approved', source: 'reference' });
    expect(store.updateText('없음', 'x')).toBeNull();
  });

  it('직접 쓴 글이 제안과 같으면 그 제안을 확인한 것으로 친다 (중복 없이)', () => {
    store.replaceFromReferences([{ text: '도입은 질문으로', kind: 'style', scope: 'all' }]);
    const got = store.add({ text: '도입은 질문으로', kind: 'style', scope: 'all', source: 'user' });
    expect(store.list()).toHaveLength(1);
    expect(got.status).toBe('approved');
  });

  it('전부 지우기 · 제안만 지우기', () => {
    store.replaceFromReferences([{ text: 'P', kind: 'style', scope: 'all' }]);
    store.add({ text: 'U', kind: 'style', scope: 'all', source: 'user' });
    expect(store.removeAll({ onlyProposed: true })).toBe(1);
    expect(store.list().map((m) => m.text)).toEqual(['U']);
    expect(store.dismissed()).toEqual(['P']);
    store.replaceFromReferences([{ text: 'Q', kind: 'style', scope: 'all' }]);
    expect(store.removeAll()).toBe(2);
    expect(store.list()).toEqual([]);
    expect(store.dismissed()).toEqual(['P', 'Q']);
  });
});
