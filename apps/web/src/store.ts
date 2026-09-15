import { create } from 'zustand';

export type GalleryTab = 'videos' | 'outputs' | 'inProgress';

interface UiState {
  tab: GalleryTab;
  setTab(tab: GalleryTab): void;
}

export const useUi = create<UiState>((set) => ({
  tab: 'videos',
  setTab: (tab) => set({ tab }),
}));
