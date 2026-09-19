import type { AppUpdater } from 'electron-updater';

/**
 * electron-updater 는 CommonJS 패키지다. Node/Electron 버전에 따라 동적 import 결과가
 * named export 또는 default export 로 보이므로 두 모양을 모두 받는다.
 */
export interface ElectronUpdaterModule {
  autoUpdater?: AppUpdater;
  default?: { autoUpdater?: AppUpdater };
}

export function resolveAutoUpdater(module: ElectronUpdaterModule): AppUpdater {
  const updater = module.autoUpdater ?? module.default?.autoUpdater;
  if (!updater) throw new Error('electron-updater did not expose autoUpdater');
  return updater;
}

export async function loadAutoUpdater(): Promise<AppUpdater> {
  const module = (await import('electron-updater')) as unknown as ElectronUpdaterModule;
  return resolveAutoUpdater(module);
}
