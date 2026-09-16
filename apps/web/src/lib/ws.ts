import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { type VideosResponse, WsEvent } from '@madi/shared';
import { queryKeys } from './api.js';

/**
 * 엔진 WS 에 붙어서 갤러리 캐시를 실시간으로 맞춘다.
 * 끊기면 지수 백오프로 다시 붙는다.
 */
export function useEngineEvents(): void {
  const qc = useQueryClient();
  useEffect(() => {
    let ws: WebSocket | null = null;
    let closed = false;
    let retry = 500;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const connect = () => {
      const proto = location.protocol === 'https:' ? 'wss' : 'ws';
      ws = new WebSocket(`${proto}://${location.host}/ws`);
      ws.onopen = () => {
        retry = 500;
        void qc.invalidateQueries({ queryKey: queryKeys.videos });
      };
      ws.onmessage = (m) => {
        const parsed = WsEvent.safeParse(JSON.parse(String(m.data)));
        if (!parsed.success) return;
        const ev = parsed.data;
        if (ev.type === 'video.added' || ev.type === 'video.updated' || ev.type === 'video.removed') {
          void qc.invalidateQueries({ queryKey: queryKeys.videos });
        } else if (ev.type === 'message.added' || ev.type === 'message.updated') {
          void qc.invalidateQueries({ queryKey: queryKeys.video(ev.message.videoId) });
        } else if (ev.type === 'output.added') {
          void qc.invalidateQueries({ queryKey: queryKeys.video(ev.output.videoId) });
          void qc.invalidateQueries({ queryKey: queryKeys.outputs });
          void qc.invalidateQueries({ queryKey: queryKeys.videos });
        } else if (ev.type === 'style.updated' || ev.type === 'reference.updated') {
          void qc.invalidateQueries({ queryKey: queryKeys.style });
        } else if (ev.type === 'job.updated' && ev.job.videoId) {
          // 상세 화면의 진행 카드: 잡 진행률만 캐시에 얹는다 (재요청 없이)
          qc.setQueryData<import('@madi/shared').VideoDetailResponse>(queryKeys.video(ev.job.videoId), (prev) =>
            prev
              ? {
                  ...prev,
                  jobs: [...prev.jobs.filter((j) => j.id !== ev.job.id), ...(ev.job.status === 'queued' || ev.job.status === 'running' ? [ev.job] : [])],
                }
              : prev,
          );
          const { job } = ev;
          qc.setQueryData<VideosResponse>(queryKeys.videos, (prev) =>
            prev
              ? {
                  videos: prev.videos.map((v) =>
                    v.id === job.videoId
                      ? {
                          ...v,
                          activeJob:
                            job.status === 'running' || job.status === 'queued'
                              ? { type: job.type, progress: job.progress }
                              : v.activeJob?.type === job.type
                                ? null
                                : v.activeJob,
                        }
                      : v,
                  ),
                }
              : prev,
          );
        }
      };
      ws.onclose = () => {
        if (closed) return;
        timer = setTimeout(connect, retry);
        retry = Math.min(retry * 2, 10_000);
      };
      ws.onerror = () => ws?.close();
    };
    connect();
    return () => {
      closed = true;
      clearTimeout(timer);
      ws?.close();
    };
  }, [qc]);
}
