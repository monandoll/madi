import { useEffect, useState } from 'react';
import { create } from 'zustand';

interface UiState {
  /** 결과물 화면의 "이 문장 고쳐줘" 같은 말을 채팅 입력창에 미리 채운다 */
  prefill: { videoId: string; text: string; at: number; editId?: string | undefined } | null;
  setPrefill(videoId: string, text: string, editId?: string): void;
  clearPrefill(): void;
  /** 결과물 화면의 "자막 고치기"(AI 없이) → 영상 상세가 자막 편집을 연다 */
  subtitleEditor: { videoId: string; outputId: string; at: number } | null;
  openSubtitleEditor(videoId: string, outputId: string): void;
  clearSubtitleEditor(): void;
}

export const useUi = create<UiState>((set) => ({
  prefill: null,
  setPrefill: (videoId, text, editId) => set({ prefill: { videoId, text, editId, at: Date.now() } }),
  clearPrefill: () => set({ prefill: null }),
  subtitleEditor: null,
  openSubtitleEditor: (videoId, outputId) => set({ subtitleEditor: { videoId, outputId, at: Date.now() } }),
  clearSubtitleEditor: () => set({ subtitleEditor: null }),
}));

const PC = '(min-width: 900px)';

/** PC(사이드바) 레이아웃인지. design/v2/Desktop.dc.html 은 1280, Mobile.dc.html 은 375 기준. */
export function useIsPc(): boolean {
  const [pc, setPc] = useState(() => (typeof window !== 'undefined' ? window.matchMedia(PC).matches : true));
  useEffect(() => {
    const mq = window.matchMedia(PC);
    const on = () => setPc(mq.matches);
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, []);
  return pc;
}
