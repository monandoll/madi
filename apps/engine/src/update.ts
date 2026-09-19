import { EventEmitter } from 'node:events';
import type { UpdateState } from '@madi/shared';

/**
 * 새 버전 상태 (기획안 밖 — 사용성). electron-updater 가 6시간마다 GitHub Releases 를 보고 받아 두면
 * 여기에 적히고, 화면(설정 · 사이드바)이 "새 버전 · 지금 업데이트" 를 조용히 보여 준다.
 * 개발 모드(브라우저만)에서는 훅이 없어 항상 "최신".
 */
export interface UpdateHooks {
  /** 지금 확인하기 (electron-updater checkForUpdates) */
  check: () => Promise<void>;
  /** 받아 둔 새 버전으로 다시 시작 (quitAndInstall) */
  install: () => void;
}

export interface UpdateEvents {
  'update.changed': [UpdateState];
}

export class UpdateStatus extends EventEmitter<UpdateEvents> {
  private st: UpdateState;
  private hooks: UpdateHooks | null = null;

  constructor(current: string) {
    super();
    this.st = { current, available: null, downloaded: false, checking: false, checkedAt: null, error: null, canInstall: false };
  }

  get state(): UpdateState {
    return { ...this.st, canInstall: this.st.downloaded && this.hooks !== null };
  }

  setHooks(hooks: UpdateHooks | null): void {
    this.hooks = hooks;
    this.emit('update.changed', this.state);
  }

  patch(p: Partial<Omit<UpdateState, 'current' | 'canInstall'>>): UpdateState {
    this.st = { ...this.st, ...p };
    this.emit('update.changed', this.state);
    return this.state;
  }

  // ---- electron-updater 이벤트가 부르는 것들 ----
  checking(): void {
    this.patch({ checking: true, error: null });
  }
  available(version: string): void {
    this.patch({ checking: false, available: version, downloaded: false, checkedAt: Date.now(), error: null });
  }
  notAvailable(): void {
    this.patch({ checking: false, available: null, downloaded: false, checkedAt: Date.now(), error: null });
  }
  downloaded(version: string): void {
    this.patch({ checking: false, available: version, downloaded: true, checkedAt: Date.now(), error: null });
  }
  failed(message: string): void {
    this.patch({ checking: false, checkedAt: Date.now(), error: message.slice(0, 200) });
  }

  /** 지금 확인. 훅이 없으면(개발 모드) false. */
  async check(): Promise<boolean> {
    if (!this.hooks) return false;
    this.checking();
    try {
      await this.hooks.check();
    } catch (err) {
      this.failed(err instanceof Error ? err.message : String(err));
    }
    return true;
  }

  /** 받아 둔 새 버전 설치 (앱이 꺼졌다 켜진다). 받아 둔 게 없거나 훅이 없으면 false. */
  install(): boolean {
    if (!this.hooks || !this.st.downloaded) return false;
    this.hooks.install();
    return true;
  }
}
