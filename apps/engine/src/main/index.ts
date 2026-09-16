/**
 * Electron 진입. 창 없음, 트레이만.
 * 엔진을 띄우고 브라우저로 열 수 있는 메뉴를 준다.
 */
import path from 'node:path';
import { app, dialog, Menu, nativeImage, shell, Tray } from 'electron';
import { ENGINE_PORT } from '@madi/shared';
import { type Engine, startEngine } from '../engine.js';

let tray: Tray | null = null;
let engine: Engine | null = null;

const single = app.requestSingleInstanceLock();
if (!single) app.quit();

app.on('window-all-closed', () => {
  /* 창이 없으니 종료하지 않는다 */
});

function buildMenu(): Menu {
  const s = engine?.settings.get();
  const folders = s?.watchFolders ?? [];
  return Menu.buildFromTemplate([
    { label: '마디 열기', click: () => void shell.openExternal(engine?.url ?? `http://127.0.0.1:${ENGINE_PORT}`) },
    { type: 'separator' },
    {
      label: folders.length ? `영상 폴더: ${folders.map((f) => path.basename(f)).join(', ')}` : '영상 폴더 정하기…',
      click: () => void pickFolder(),
    },
    { type: 'separator' },
    { label: '종료', role: 'quit' },
  ]);
}

async function pickFolder(): Promise<void> {
  if (!engine) return;
  const res = await dialog.showOpenDialog({ properties: ['openDirectory', 'createDirectory'] });
  if (res.canceled || !res.filePaths[0]) return;
  engine.settings.patch({ watchFolders: [res.filePaths[0]] });
  await engine.watcher.setFolders([res.filePaths[0]]);
  tray?.setContextMenu(buildMenu());
}

app.whenReady().then(async () => {
  if (process.platform === 'darwin') app.dock?.hide();
  app.setLoginItemSettings({ openAtLogin: app.isPackaged });

  // 패키징된 앱만 resources 경로를 쓴다. 개발 모드에서 undefined 를 대입하면 문자열 "undefined" 가 된다.
  if (app.isPackaged) process.env['MADI_ROOT'] = process.resourcesPath;
  engine = await startEngine();
  engine.setFolderPicker(async () => {
    const res = await dialog.showOpenDialog({ properties: ['openDirectory', 'createDirectory'] });
    const picked = res.canceled ? null : (res.filePaths[0] ?? null);
    tray?.setContextMenu(buildMenu());
    return picked;
  });

  const iconName = process.platform === 'darwin' ? 'trayTemplate.png' : 'tray.png';
  const icon = nativeImage.createFromPath(path.join(process.resourcesPath, iconName));
  if (process.platform === 'darwin') icon.setTemplateImage(true);
  tray = new Tray(icon.isEmpty() ? nativeImage.createEmpty() : icon);
  tray.setToolTip('마디');
  tray.setContextMenu(buildMenu());
  tray.on('click', () => tray?.popUpContextMenu());

  // 설치 직후(첫 실행, 설정 전) 브라우저를 바로 연다. 설치 파일을 누른 사람이 트레이를 찾아다니지 않게.
  if (app.isPackaged && !engine.settings.get().setupDone) void shell.openExternal(engine.url);

  if (app.isPackaged) {
    // GitHub Releases 에서 새 버전을 받아 다음 실행 때 적용한다. 6시간마다 다시 본다.
    const { autoUpdater } = await import('electron-updater');
    autoUpdater.logger = null;
    autoUpdater.autoDownload = true;
    autoUpdater.autoInstallOnAppQuit = true;
    const check = () => void autoUpdater.checkForUpdatesAndNotify().catch(() => {});
    check();
    setInterval(check, 6 * 60 * 60 * 1000);
  }
});

app.on('before-quit', () => {
  void engine?.stop();
});
