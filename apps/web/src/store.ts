import { useEffect, useState } from 'react';
import { create } from 'zustand';

interface UiState {
  /** 결과물 화면의 "이 문장 고쳐줘" 같은 말을 채팅 입력창에 미리 채운다 */
  prefill: { videoId: string; text: string; at: number } | null;
  setPrefill(videoId: string, text: string): void;
}

export const useUi = create<UiState>((set) => ({
  prefill: null,
  setPrefill: (videoId, text) => set({ prefill: { videoId, text, at: Date.now() } }),
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
