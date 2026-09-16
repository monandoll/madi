import { useQuery } from '@tanstack/react-query';
import { OutputView } from '../components/OutputView.js';
import { TopBar } from '../components/TopBar.js';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { formatDuration } from '../lib/format.js';
import { go } from '../lib/route.js';
import { useIsPc, useUi } from '../store.js';
import { VideoDetail } from './VideoDetail.js';

/**
 * #/outputs/:id
 * - 모바일: design/v2 결과물 화면 (전체). "이 문장 고쳐줘" 는 영상 채팅으로 넘어가 입력창에 채워진다.
 * - PC: 그 영상의 채팅 + 오른쪽 결과물 패널.
 */
export function OutputDetail({ id }: { id: string }) {
  const pc = useIsPc();
  const q = useQuery({ queryKey: queryKeys.output(id), queryFn: () => api.output(id) });
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health, refetchInterval: 15_000 });
  const setPrefill = useUi((s) => s.setPrefill);

  if (pc) {
    if (q.isPending) return <Frame title="">{null}</Frame>;
    if (q.isError || !q.data) return <Frame title="">{copy.output.notFound}</Frame>;
    return <VideoDetail id={q.data.output.videoId} panelOutputId={id} />;
  }

  if (q.isPending) return <Frame title="">{null}</Frame>;
  if (q.isError || !q.data) return <Frame title="">{copy.output.notFound}</Frame>;
  const { output } = q.data;
  const vertical = output.width < output.height;
  const aiOn = health.data?.ai.connected ?? false;
  const ask = (text: string) => {
    setPrefill(output.videoId, text);
    go({ screen: 'video', id: output.videoId });
  };
  return (
    <div className="flex h-full min-h-0 flex-col bg-surface" data-testid="output-detail">
      <TopBar title={output.title} meta={`${formatDuration(output.durationSec)} · ${vertical ? '9:16' : '16:9'}`} showBack backFallback={{ screen: 'video', id: output.videoId }} />
      <OutputView data={q.data} wide onAsk={aiOn ? ask : undefined} />
    </div>
  );
}

function Frame({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex h-full flex-col bg-surface">
      <TopBar title={title} showBack />
      <main className="flex flex-1 items-center justify-center p-4 text-13 text-text-3">{children}</main>
    </div>
  );
}
