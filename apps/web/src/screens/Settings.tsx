import { lazy, Suspense, useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Settings as SettingsSchema, type TermKind } from '@madi/shared';
import { FolderChooser } from '../components/FolderChooser.js';
import { AiMark } from '../components/AiMark.js';
// 터미널은 열 때만 받아 온다 (xterm 이 크다 — 첫 화면, 특히 폰에서 느려지지 않게)
const Term = lazy(() => import('../components/Term.js').then((m) => ({ default: m.Term })));
import { Qr } from '../components/Qr.js';
import { Card, CardRow, GhostButton, PillButton, SectionTitle, Status } from '../components/Settings.js';
import { StyleSection } from '../components/StyleSection.js';
import { TopBar } from '../components/TopBar.js';
import { copy } from '../copy.js';
import { api, ApiError, queryKeys } from '../lib/api.js';
import { usePatchSettings, useSettings } from '../lib/settings.js';

/**
 * design/v2 설정: 스튜디오 이름 · AI 연결 · 내 편집 스타일 · 이 컴퓨터(영상 폴더 · 편집 엔진 · 밖에서 접속 · 버전) · 첫 실행 화면 다시 보기.
 * PC 는 320px 격자, 모바일은 한 열. 저장 버튼 없이 바로 반영.
 */
export function SettingsScreen() {
  const { settings } = useSettings();
  const patch = usePatchSettings();
  const qc = useQueryClient();
  const health = useQuery({ queryKey: queryKeys.health, queryFn: api.health, refetchInterval: 5_000 });
  // 설치된 AI 도구. 설정 화면을 열 때마다 새로 찾는다 (설치 직후 바로 보이게).
  const providers = useQuery({ queryKey: queryKeys.aiProviders, queryFn: () => api.aiProviders(true), staleTime: 30_000 });
  const ai = health.data?.ai;
  const labelOfProvider = (id: string) => providers.data?.providers.find((p) => p.id === id)?.label ?? id;
  const suggest = useQuery({ queryKey: queryKeys.folders, queryFn: api.suggestFolders });
  const labelOf = (p: string) => suggest.data?.folders.find((f) => f.path === p)?.label ?? baseName(p);
  const [name, setName] = useState(settings.workspaceName);
  const [adding, setAdding] = useState(false);
  const [token, setToken] = useState('');
  const [advanced, setAdvanced] = useState(false);
  // AI 도구 다시 찾기 / 이 PC 에서 실행 파일 직접 고르기
  const [rechecking, setRechecking] = useState(false);
  const [pathBusy, setPathBusy] = useState<'claude' | 'codex' | null>(null);
  const [pathError, setPathError] = useState<string | null>(null);
  // 마디가 대신 깔기 / 로그인 창 열기 / 터미널에서 직접 하기
  const [manual, setManual] = useState<'claude' | 'codex' | null>(null);
  const [copied, setCopied] = useState(false);
  const [loginError, setLoginError] = useState<string | null>(null);
  // 화면 안 터미널 (로그인). 열려 있으면 그 종류.
  const [term, setTerm] = useState<TermKind | null>(null);
  const install = useQuery({
    queryKey: queryKeys.aiInstall,
    queryFn: api.aiInstallState,
    // 깔고 있는 동안만 자주 물어본다
    refetchInterval: (q) => (q.state.data?.install.status === 'running' ? 2_000 : false),
  });
  const installing = install.data?.install.status === 'running' ? install.data.install.provider : null;
  const installStep = install.data?.install.step ?? null;
  const installFailed = install.data?.install.status === 'failed' ? install.data.install : null;
  const aiAllInstalled = (providers.data?.providers ?? []).some((p) => p.installed);
  // 켜져 있으면 주소·숫자를 계속 지켜본다 (주소가 몇 초 뒤에 나온다)
  const remote = useQuery({ queryKey: queryKeys.remote, queryFn: api.remote, refetchInterval: settings.remoteMode === 'off' ? false : 3_000 });
  useEffect(() => setName(settings.workspaceName), [settings.workspaceName]);
  // 다 깔리면(또는 실패하면) 찾은 결과를 화면에 바로 반영한다
  const installStatus = install.data?.install.status;
  useEffect(() => {
    if (installStatus === 'done' && install.data) {
      qc.setQueryData(queryKeys.aiProviders, { providers: install.data.providers });
      void qc.invalidateQueries({ queryKey: queryKeys.health });
    }
  }, [installStatus, install.data, qc]);
  const tunnel = health.data?.tunnel;
  const remoteOn = settings.remoteMode !== 'off';
  const remoteUrl = remote.data?.url ?? null;
  const qrUrl = remoteUrl && remote.data?.pin ? `${remoteUrl}/?pin=${remote.data.pin}` : remoteUrl;
  const aiOn = ai?.connected ?? false;
  const aiStatus = !ai || ai.provider === 'none' ? copy.settings.aiOff : ai.connected ? copy.settings.aiOn(labelOfProvider(ai.provider)) : copy.settings.aiMissing(labelOfProvider(ai.provider));

  /** 다시 찾기: 캐시를 버리고 처음부터 찾은 다음 연결 상태도 새로 본다. */
  const recheck = async () => {
    setRechecking(true);
    setPathError(null);
    try {
      qc.setQueryData(queryKeys.aiProviders, await api.aiProviders(true));
      await qc.invalidateQueries({ queryKey: queryKeys.health });
    } finally {
      setRechecking(false);
    }
  };

  /** 이 PC 의 실행 파일을 파일 선택창에서 고른다. 트레이 앱이 아니면 창을 못 연다. */
  const pickPath = async (provider: 'claude' | 'codex') => {
    setPathBusy(provider);
    setPathError(null);
    try {
      const res = await api.aiPickPath(provider);
      if (!res.canceled) {
        qc.setQueryData(queryKeys.aiProviders, await api.aiProviders(true));
        await qc.invalidateQueries({ queryKey: queryKeys.health });
      }
    } catch (err) {
      setPathError(err instanceof ApiError && err.code === 'ai_path_bad' ? copy.settings.aiPickBad : copy.settings.aiPickFailed);
    } finally {
      setPathBusy(null);
    }
  };

  /** 직접 고른 파일 지우기 (다시 자동으로 찾게). */
  const setPath = (provider: 'claude' | 'codex', value: string | null) => {
    setPathBusy(provider);
    setPathError(null);
    api
      .aiSetPath(provider, value)
      .then((res) => {
        qc.setQueryData(queryKeys.aiProviders, res);
        return qc.invalidateQueries({ queryKey: queryKeys.health });
      })
      .catch((err: unknown) => setPathError(err instanceof ApiError && err.code === 'ai_path_bad' ? copy.settings.aiPickBad : copy.settings.aiPickFailed))
      .finally(() => setPathBusy(null));
  };

  /** 깔기 상태가 바뀌면 찾은 결과도 같이 갈아 끼운다 (끝나면 바로 연결까지 이어지게). */
  const applyInstall = (data: { providers: unknown }) => {
    qc.setQueryData(queryKeys.aiInstall, data);
    qc.setQueryData(queryKeys.aiProviders, { providers: data.providers });
    void qc.invalidateQueries({ queryKey: queryKeys.health });
  };

  const startInstall = (provider: 'claude' | 'codex') => {
    setPathError(null);
    setLoginError(null);
    api
      .aiInstall(provider)
      .then((res) => qc.setQueryData(queryKeys.aiInstall, res))
      .catch(() => setPathError(copy.settings.aiInstallFail['failed'] ?? null));
  };

  const closeInstall = () => {
    api.aiInstallClear().then(applyInstall).catch(() => undefined);
  };

  /** 로그인은 화면 안 터미널에서 한다 (폰에서도 되게). */
  const openLogin = (provider: 'claude' | 'codex') => {
    setLoginError(null);
    setManual(null);
    setTerm(provider === 'claude' ? 'login-claude' : 'login-codex');
  };

  const copyLine = (line: string) => {
    void navigator.clipboard?.writeText(line).then(
      () => {
        setCopied(true);
        setTimeout(() => setCopied(false), 2_000);
      },
      () => undefined,
    );
  };

  const commitName = () => {
    const parsed = SettingsSchema.shape.workspaceName.safeParse(name);
    if (!parsed.success) {
      setName(settings.workspaceName);
      return;
    }
    if (parsed.data !== settings.workspaceName) patch.mutate({ workspaceName: parsed.data });
  };
  const setFolders = (next: string[]) => patch.mutate({ watchFolders: next, setupDone: true });

  return (
    <div className="flex h-full min-h-0 flex-col bg-surface" data-testid="settings-screen">
      <TopBar title={copy.settings.title} meta={copy.header.sectionMeta['settings']} showBack aside={<span className="hidden text-12 text-text-3 pc:inline" />} />
      <main className="grid min-h-0 flex-1 auto-rows-max grid-cols-1 gap-[22px] overflow-y-auto px-3.5 pt-3.5 pb-8 pc:grid-cols-[repeat(auto-fit,minmax(320px,1fr))] pc:gap-x-6 pc:gap-y-[26px] pc:px-6 pc:pt-[22px] pc:pb-20">
        {/* 스튜디오 이름 */}
        <section className="flex flex-col gap-[9px]">
          <SectionTitle>{copy.settings.nameLabel}</SectionTitle>
          <label className="flex rounded-thumb border border-input px-3 py-[9px] focus-within:border-accent">
            <input
              data-testid="settings-name"
              className="w-full bg-transparent text-14 outline-none"
              value={name}
              maxLength={40}
              onChange={(e) => setName(e.target.value)}
              onBlur={commitName}
              onKeyDown={(e) => {
                if (e.key === 'Enter') (e.target as HTMLInputElement).blur();
              }}
            />
          </label>
          <p className="text-12 text-text-3">{copy.settings.nameHelp}</p>
        </section>

        {/* AI 연결 */}
        <section className="flex flex-col gap-[9px] pc:col-span-full" data-testid="ai-section">
          <SectionTitle aside={copy.settings.aiIntro}>{copy.settings.aiLabel}</SectionTitle>
          <Card testId="ai-providers">
            {(providers.data?.providers ?? []).map((p, i) => {
              const selected = settings.ai.provider === p.id;
              const on = selected && aiOn;
              return (
                <CardRow key={p.id} first={i === 0} active={selected} testId={`ai-provider-${p.id}`}>
                  <span className="flex h-7 w-7 flex-none items-center justify-center rounded-thumb bg-track text-text-2">
                    <AiMark id={p.id} />
                  </span>
                  <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="text-14 font-medium">{p.label}</span>
                    <Status on={on} busy={selected && !on}>
                      {selected ? aiStatus : p.installed ? copy.settings.aiInstalled(p.version) : copy.settings.aiNotInstalled}
                    </Status>
                    {p.custom && (
                      <span className="text-12 text-text-3" data-testid={`ai-custom-${p.id}`}>
                        {copy.settings.aiCustom} ·{' '}
                        <button type="button" className="text-accent hover:text-accent-hover" onClick={() => setPath(p.id, null)} disabled={pathBusy !== null}>
                          {copy.settings.aiCustomClear}
                        </button>
                      </span>
                    )}
                    {!p.installed && installing !== p.id && (
                      <span className="flex flex-wrap items-center gap-x-3 gap-y-1 text-12">
                        <button type="button" className="text-accent hover:text-accent-hover disabled:text-text-3" onClick={() => void pickPath(p.id)} disabled={pathBusy !== null} data-testid={`ai-pick-${p.id}`}>
                          {pathBusy === p.id ? copy.settings.aiPicking : copy.settings.aiPick}
                        </button>
                        {p.installLine && (
                          <button type="button" className="text-text-3 hover:text-accent" onClick={() => setManual(manual === p.id ? null : p.id)} data-testid={`ai-manual-${p.id}`}>
                            {copy.settings.aiManual}
                          </button>
                        )}
                      </span>
                    )}
                    {installing === p.id && (
                      <span className="text-12 text-busy" data-testid={`ai-installing-${p.id}`}>
                        {installStep === 'checking' ? copy.settings.aiInstallChecking : copy.settings.aiInstalling}
                      </span>
                    )}
                    {p.installed && (
                      <button type="button" className="self-start text-12 text-accent hover:text-accent-hover" onClick={() => openLogin(p.id)} data-testid={`ai-login-${p.id}`}>
                        {copy.settings.aiLogin}
                      </button>
                    )}
                  </span>
                  {selected ? (
                    <PillButton onClick={() => patch.mutate({ ai: { ...settings.ai, provider: 'none' } })} disabled={patch.isPending} testId="ai-disconnect">
                      {copy.settings.aiDisconnect}
                    </PillButton>
                  ) : p.installed ? (
                    <PillButton primary onClick={() => patch.mutate({ ai: { ...settings.ai, provider: p.id } })} disabled={patch.isPending}>
                      {copy.settings.aiUse}
                    </PillButton>
                  ) : (
                    <PillButton primary onClick={() => startInstall(p.id)} disabled={!p.canInstall || installing !== null} testId={`ai-install-${p.id}`}>
                      {copy.settings.aiInstall}
                    </PillButton>
                  )}
                </CardRow>
              );
            })}
            {providers.isPending && (
              <CardRow first>
                <span className="text-13 text-text-3">{copy.settings.aiChecking}</span>
              </CardRow>
            )}
            <CardRow>
              <span className="flex-1 text-12 text-text-3">{copy.settings.aiRetryHelp}</span>
              <PillButton onClick={() => void recheck()} disabled={rechecking || pathBusy !== null} testId="ai-recheck">
                {rechecking ? copy.settings.aiRetrying : copy.settings.aiRetry}
              </PillButton>
            </CardRow>
          </Card>
          {installFailed && (
            <p className="flex flex-wrap items-center gap-x-2 text-12 text-error" data-testid="ai-install-error">
              {copy.settings.aiInstallFail[installFailed.error ?? 'failed'] ?? copy.settings.aiInstallFail['failed']}
              <button type="button" className="text-accent hover:text-accent-hover" onClick={() => installFailed.provider && startInstall(installFailed.provider)}>
                {copy.settings.aiInstallRetry}
              </button>
              <button type="button" className="text-text-3 hover:text-accent" onClick={closeInstall}>
                {copy.settings.aiInstallClose}
              </button>
            </p>
          )}
          {loginError && (
            <p className="text-12 text-error" data-testid="ai-login-error">
              {loginError}
            </p>
          )}
          {pathError && (
            <p className="text-12 text-error" data-testid="ai-path-error">
              {pathError}
            </p>
          )}
          {term && (
            <Suspense fallback={<p className="text-12 text-text-3">{copy.settings.termOpening}</p>}>
              <Term
                kind={term}
                onClose={() => setTerm(null)}
                onFallback={() => {
                  const provider = term === 'login-claude' ? 'claude' : 'codex';
                  api.aiLogin(provider).catch(() => {
                    setLoginError(copy.settings.aiLoginFailed);
                    setManual(provider);
                  });
                }}
              />
            </Suspense>
          )}
          {manual && (
            <div className="flex flex-col gap-1.5 rounded-thumb border border-line px-3 py-2.5" data-testid="ai-manual-box">
              <span className="text-12 text-text-3">{copy.settings.aiManualHelp}</span>
              <div className="flex items-center gap-2">
                <code className="min-w-0 flex-1 overflow-x-auto rounded-row bg-surface-2 px-2.5 py-2 text-12 whitespace-nowrap text-text-2" data-testid="ai-manual-line">
                  {providers.data?.providers.find((p) => p.id === manual)?.installLine}
                </code>
                <button
                  type="button"
                  className="flex-none rounded-thumb border border-line px-2.5 py-1.5 text-12 hover:bg-hover"
                  onClick={() => copyLine(providers.data?.providers.find((p) => p.id === manual)?.installLine ?? '')}
                >
                  {copied ? copy.settings.aiManualCopied : copy.settings.aiManualCopy}
                </button>
              </div>
            </div>
          )}
          <p className="text-12 text-text-3">
            <span data-testid="ai-status">{aiStatus}</span> · {copy.settings.aiHelp}
          </p>
          <p className="text-12 text-text-3">{installing ? copy.settings.aiInstallHelp : aiAllInstalled ? copy.settings.aiLoginHelp : copy.settings.aiPickHelp}</p>
          <label className="flex cursor-pointer items-start gap-2.5 text-13" data-testid="ai-frames">
            <input
              type="checkbox"
              className="mt-0.5 h-4 w-4 flex-none accent-accent"
              checked={settings.ai.frames}
              onChange={(e) => patch.mutate({ ai: { ...settings.ai, frames: e.target.checked } })}
              data-testid="ai-frames-toggle"
            />
            <span className="flex flex-col gap-0.5">
              <span className="font-medium">{copy.settings.aiFrames}</span>
              <span className="text-12 text-text-3">{copy.settings.aiFramesHelp}</span>
            </span>
          </label>
          <p className="text-12 text-text-3" data-testid="ai-data-notice">
            {copy.settings.aiDataNotice}
          </p>
        </section>

        <StyleSection aiOn={aiOn} />

        {/* 이 컴퓨터 */}
        <section className="flex flex-col gap-[9px] pc:col-span-full">
          <SectionTitle>{copy.settings.computerLabel}</SectionTitle>
          <Card testId="folder-list">
            {settings.watchFolders.map((p, i) => (
              <CardRow key={p} first={i === 0}>
                <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                  <span className="text-14 font-medium">
                    <span className="text-text-3">{copy.settings.foldersLabel} · </span>
                    <span>{labelOf(p)}</span>
                  </span>
                  <span className="truncate text-12 text-text-3">{p}</span>
                </span>
                <button type="button" onClick={() => setFolders(settings.watchFolders.filter((x) => x !== p))} className="flex-none text-13 text-text-2 hover:text-accent">
                  {copy.folders.remove}
                </button>
              </CardRow>
            ))}
            {settings.watchFolders.length === 0 && (
              <CardRow first>
                <span className="flex-1 text-14 font-medium">{copy.settings.foldersLabel}</span>
                <span className="text-12 text-text-3">{copy.empty.noFolder.split('\n')[0]}</span>
              </CardRow>
            )}
            {!adding && (
              <button type="button" onClick={() => setAdding(true)} className="flex min-h-11 items-center border-t border-line-soft px-3 text-left text-13 font-medium text-accent hover:bg-surface-2">
                {copy.folders.add}
              </button>
            )}
          </Card>
          {adding && (
            <FolderChooser
              value={settings.watchFolders}
              onChange={(next) => {
                setFolders(next);
                setAdding(false);
              }}
              hideSelected
            />
          )}
          <Card>
            <CardRow first>
              <span className="flex-1 text-14">{copy.settings.engineLabel}</span>
              <Status on={health.isSuccess}>{health.isSuccess ? copy.header.engineOk : copy.header.engineOff}</Status>
            </CardRow>
            <div data-testid="remote-section">
              <CardRow>
                <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                  <span className="text-14">{copy.settings.remoteLabel}</span>
                  <span className="text-12 text-text-3">{copy.settings.remoteHelp}</span>
                </span>
                <Status on={tunnel?.status === 'running'} busy={remoteOn && tunnel?.status !== 'running'} testId="remote-status">
                  {copy.settings.remoteStatus[remoteOn ? (tunnel?.status ?? 'starting') : 'off']}
                </Status>
                {remoteOn ? (
                  <PillButton onClick={() => patch.mutate({ remoteMode: 'off', tunnelToken: null })} disabled={patch.isPending} testId="remote-stop">
                    {copy.settings.remoteClear}
                  </PillButton>
                ) : (
                  <PillButton primary onClick={() => patch.mutate({ remoteMode: 'quick' })} disabled={patch.isPending} testId="remote-start">
                    {copy.settings.remoteStart}
                  </PillButton>
                )}
              </CardRow>
              {remoteOn && (
                <div className="flex flex-col gap-2.5 border-t border-line-soft px-3 py-3" data-testid="remote-qr">
                  {qrUrl ? (
                    <div className="flex items-start gap-3.5">
                      <Qr value={qrUrl} size={148} />
                      <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                        <span className="text-14 font-medium">{copy.settings.remoteQrTitle}</span>
                        <span className="text-12 leading-normal text-text-3">{copy.settings.remoteQrHelp}</span>
                        <a href={remoteUrl ?? undefined} target="_blank" rel="noreferrer" className="truncate text-12 text-accent" data-testid="remote-url">
                          {remoteUrl}
                        </a>
                        {remote.data?.pin && (
                          <span className="text-13 font-semibold tracking-[0.12em]" data-testid="remote-pin">
                            {copy.settings.remotePin(remote.data.pin)}
                          </span>
                        )}
                        <span className="text-12 text-text-3">{copy.settings.remoteDevices(remote.data?.devices ?? 0)}</span>
                      </div>
                    </div>
                  ) : (
                    <span className="text-13 text-text-3">{copy.settings.remoteStarting}</span>
                  )}
                  <p className="text-12 text-text-3">{copy.settings.remoteWarn}</p>
                </div>
              )}
              <div className="border-t border-line-soft px-3 py-2.5">
                <button type="button" onClick={() => setAdvanced((v) => !v)} className="text-13 text-text-2 hover:text-accent" data-testid="remote-advanced-toggle">
                  {copy.settings.remoteAdvanced}
                </button>
                {advanced && (
                  <div className="flex flex-col gap-2 pt-2.5">
                    <p className="text-12 text-text-3">{copy.settings.remoteAdvancedHelp}</p>
                    <div className="flex gap-2">
                      <input
                        data-testid="remote-token"
                        className="min-w-0 flex-1 rounded-thumb border border-input bg-surface px-3 py-2 text-13 outline-none placeholder:text-text-3 focus:border-accent"
                        value={token}
                        placeholder={copy.settings.remotePlaceholder}
                        autoComplete="off"
                        spellCheck={false}
                        onChange={(e) => setToken(e.target.value)}
                      />
                      <button
                        type="button"
                        disabled={!token.trim() || patch.isPending}
                        onClick={() => {
                          patch.mutate({ remoteMode: 'token', tunnelToken: token.trim() });
                          setToken('');
                        }}
                        className="rounded-thumb border border-line px-3.5 text-13 font-medium hover:bg-hover disabled:text-text-3"
                      >
                        {copy.settings.remoteSave}
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </div>
            <CardRow>
              <span className="flex-1 text-14">{copy.settings.versionLabel}</span>
              <span className="text-13 text-text-3">{health.data ? copy.settings.version(health.data.version) : ''}</span>
            </CardRow>
          </Card>
        </section>

        <div className="pc:col-span-full">
          <GhostButton onClick={() => patch.mutate({ setupDone: false })} disabled={patch.isPending} testId="restart-first-run">
            {copy.settings.restartFirstRun}
          </GhostButton>
        </div>
      </main>
    </div>
  );
}

function baseName(p: string): string {
  const parts = p.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] ?? p;
}
