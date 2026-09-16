import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Settings as SettingsSchema } from '@madi/shared';
import { FolderChooser } from '../components/FolderChooser.js';
import { Card, CardRow, GhostButton, PillButton, SectionTitle, Status } from '../components/Settings.js';
import { StyleSection } from '../components/StyleSection.js';
import { TopBar } from '../components/TopBar.js';
import { copy } from '../copy.js';
import { api, queryKeys } from '../lib/api.js';
import { usePatchSettings, useSettings } from '../lib/settings.js';

/**
 * design/v2 설정: 스튜디오 이름 · AI 연결 · 내 편집 스타일 · 이 컴퓨터(영상 폴더 · 편집 엔진 · 밖에서 접속 · 버전) · 첫 실행 화면 다시 보기.
 * PC 는 320px 격자, 모바일은 한 열. 저장 버튼 없이 바로 반영.
 */
export function SettingsScreen() {
  const { settings } = useSettings();
  const patch = usePatchSettings();
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
  useEffect(() => setName(settings.workspaceName), [settings.workspaceName]);
  const tunnel = health.data?.tunnel;
  const tunnelOn = !!settings.tunnelToken;
  const aiOn = ai?.connected ?? false;
  const aiStatus = !ai || ai.provider === 'none' ? copy.settings.aiOff : ai.connected ? copy.settings.aiOn(labelOfProvider(ai.provider)) : copy.settings.aiMissing(labelOfProvider(ai.provider));

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
                  <span className="flex h-7 w-7 flex-none items-center justify-center rounded-thumb bg-track text-11 font-bold text-text-4">{p.label.charAt(0)}</span>
                  <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="text-14 font-medium">{p.label}</span>
                    <Status on={on} busy={selected && !on}>
                      {selected ? aiStatus : p.installed ? copy.settings.aiInstalled(p.version) : copy.settings.aiNotInstalled}
                    </Status>
                  </span>
                  {selected ? (
                    <PillButton onClick={() => patch.mutate({ ai: { provider: 'none' } })} disabled={patch.isPending} testId="ai-disconnect">
                      {copy.settings.aiDisconnect}
                    </PillButton>
                  ) : (
                    <PillButton primary onClick={() => patch.mutate({ ai: { provider: p.id } })} disabled={!p.installed || patch.isPending}>
                      {copy.settings.aiUse}
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
          </Card>
          <p className="text-12 text-text-3">
            <span data-testid="ai-status">{aiStatus}</span> · {copy.settings.aiHelp}
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
                <Status on={tunnel?.status === 'running'} busy={tunnelOn && tunnel?.status !== 'running'} testId="remote-status">
                  {copy.settings.remoteStatus[tunnelOn ? (tunnel?.status ?? 'starting') : 'off']}
                </Status>
                {tunnelOn && (
                  <PillButton onClick={() => patch.mutate({ tunnelToken: null })} disabled={patch.isPending}>
                    {copy.settings.remoteClear}
                  </PillButton>
                )}
              </CardRow>
              {!tunnelOn && (
                <div className="flex gap-2 border-t border-line-soft px-3 py-2.5">
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
                      patch.mutate({ tunnelToken: token.trim() });
                      setToken('');
                    }}
                    className="rounded-thumb border border-line px-3.5 text-13 font-medium hover:bg-hover disabled:text-text-3"
                  >
                    {copy.settings.remoteSave}
                  </button>
                </div>
              )}
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
