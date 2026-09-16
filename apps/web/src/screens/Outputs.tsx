import { useQuery } from '@tanstack/react-query';
import { OutputList } from '../components/ChatFeed.js';
import { TopBar } from '../components/TopBar.js';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { Empty } from './Gallery.js';

/** 결과물 목록 (모바일 탭 · PC 레일). 누르면 결과물 화면(모바일) / 영상 채팅 + 옆 패널(PC). */
export function OutputsScreen() {
  const outputs = useQuery({ queryKey: queryKeys.outputs, queryFn: api.outputs });
  const list = outputs.data?.outputs ?? [];
  return (
    <div className="flex h-full min-h-0 flex-col bg-surface">
      <TopBar title={copy.tabs.outputs} meta={copy.header.sectionMeta['outputs']} />
      <main className="min-h-0 flex-1 overflow-y-auto px-3.5 pt-3 pb-5 pc:px-6 pc:pt-5 pc:pb-10">
        {outputs.isPending ? <Empty>{copy.empty.loading}</Empty> : list.length === 0 ? <Empty>{copy.empty.noOutputs}</Empty> : <OutputList outputs={list} />}
      </main>
    </div>
  );
}
