import { DetailedError, Upload } from 'tus-js-client';
import { create } from 'zustand';
import { isVideoFile } from '@madi/shared';

/**
 * 폰에서 올리기. tus 로 8MB 씩 이어 올리고, 끊기면 몇 번 다시 붙는다.
 * 목록은 화면(갤러리 위 진행 카드)이 그린다. 다 올라간 영상이 갤러리에 나타나면 줄이 사라진다.
 */
export interface UploadItem {
  id: string;
  name: string;
  size: number;
  sent: number;
  status: 'uploading' | 'done' | 'failed';
  /** 실패 코드: no_folder · not_video · network */
  error: string | null;
}

interface UploadsState {
  items: UploadItem[];
  start(files: ArrayLike<File>): void;
  remove(id: string): void;
  retry(id: string): void;
}

export const MAX_AT_ONCE = 10;
const CHUNK = 8 * 1024 * 1024;

const uploads = new Map<string, { upload: Upload; file: File }>();

export const useUploads = create<UploadsState>((set, get) => {
  const patch = (id: string, p: Partial<UploadItem>) => set((s) => ({ items: s.items.map((it) => (it.id === id ? { ...it, ...p } : it)) }));

  const run = (id: string, file: File) => {
    const upload = new Upload(file, {
      endpoint: '/api/uploads',
      chunkSize: CHUNK,
      retryDelays: [0, 1000, 3000, 5000, 10000],
      metadata: { filename: file.name, filetype: file.type || 'video/mp4' },
      storeFingerprintForResuming: false,
      onProgress: (sent) => patch(id, { sent }),
      onSuccess: () => {
        uploads.delete(id);
        patch(id, { status: 'done', sent: file.size, error: null });
      },
      onError: (err) => {
        uploads.delete(id);
        patch(id, { status: 'failed', error: codeOf(err) });
      },
    });
    uploads.set(id, { upload, file });
    upload.start();
  };

  return {
    items: [],
    start(files) {
      const list = Array.from(files).slice(0, MAX_AT_ONCE);
      const fresh: UploadItem[] = list.map((f) => ({
        id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
        name: f.name,
        size: f.size,
        sent: 0,
        status: isVideoFile(f.name) ? 'uploading' : 'failed',
        error: isVideoFile(f.name) ? null : 'not_video',
      }));
      set((s) => ({ items: [...s.items, ...fresh] }));
      fresh.forEach((it, i) => {
        if (it.status === 'uploading') run(it.id, list[i]!);
      });
    },
    remove(id) {
      const live = uploads.get(id);
      if (live) {
        void live.upload.abort(true).catch(() => {});
        uploads.delete(id);
      }
      set((s) => ({ items: s.items.filter((it) => it.id !== id) }));
    },
    retry(id) {
      const it = get().items.find((x) => x.id === id);
      const live = uploads.get(id);
      if (!it || it.status !== 'failed') return;
      // 파일 핸들이 남아 있을 때만 (새로고침 뒤엔 다시 골라야 한다)
      const file = live?.file ?? failedFiles.get(id);
      if (!file) return;
      patch(id, { status: 'uploading', sent: 0, error: null });
      run(id, file);
    },
  };
});

/** 실패한 올리기의 파일을 잠시 들고 있는다 (다시 누를 때). */
const failedFiles = new Map<string, File>();
useUploads.subscribe((s) => {
  for (const it of s.items) {
    const live = uploads.get(it.id);
    if (it.status === 'failed' && live) failedFiles.set(it.id, live.file);
  }
  for (const id of failedFiles.keys()) if (!s.items.some((it) => it.id === id)) failedFiles.delete(id);
});

function codeOf(err: Error | DetailedError): string {
  if (err instanceof DetailedError && err.originalResponse) {
    const body = err.originalResponse.getBody()?.trim();
    if (body === 'no_folder' || body === 'not_video') return body;
  }
  return 'network';
}

export function percent(it: UploadItem): number {
  return it.size ? Math.min(100, Math.floor((it.sent / it.size) * 100)) : 0;
}
