/** 설정 화면의 공통 조각 (design/v2 Desktop 설정): 섹션 제목 15/600 · 카드(1px 선, 8px) · 카드 줄(12px 패딩). */

export function SectionTitle({ children, aside }: { children: React.ReactNode; aside?: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-baseline gap-2.5">
      <h2 className="text-14 font-semibold pc:text-15">{children}</h2>
      {aside && <span className="text-12 text-text-3">{aside}</span>}
    </div>
  );
}

export function Card({ children, testId }: { children: React.ReactNode; testId?: string }) {
  return (
    <div className="flex flex-col overflow-hidden rounded-thumb border border-line" data-testid={testId}>
      {children}
    </div>
  );
}

export function CardRow({
  children,
  first = false,
  active = false,
  testId,
  ...rest
}: {
  children: React.ReactNode;
  first?: boolean;
  active?: boolean;
  testId?: string;
  'data-learned'?: string;
}) {
  return (
    <div className={`flex min-h-11 items-center gap-2.5 px-3 py-3 pc:gap-3 ${first ? '' : 'border-t border-line-soft'} ${active ? 'bg-surface-2' : ''}`} data-testid={testId} {...rest}>
      {children}
    </div>
  );
}

/** 상태 점 + 글자 (연결됨 등) */
export function Status({ on, busy = false, children, testId }: { on: boolean; busy?: boolean; children: React.ReactNode; testId?: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span className="h-1.5 w-1.5 flex-none rounded-pill" style={{ background: on ? 'var(--color-ok)' : busy ? 'var(--color-busy)' : 'var(--color-off)' }} />
      <span className="truncate text-12 text-text-3 pc:text-13 pc:text-text-2" data-testid={testId}>
        {children}
      </span>
    </span>
  );
}

/** 작은 알약 버튼 (연결하기 / 연결 해제) */
export function PillButton({ children, primary = false, onClick, disabled = false, testId }: { children: React.ReactNode; primary?: boolean; onClick(): void; disabled?: boolean; testId?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      data-testid={testId}
      className={`flex-none rounded-pill border px-[13px] py-[7px] text-13 font-medium whitespace-nowrap pc:rounded-thumb pc:py-1.5 ${
        primary ? 'border-accent bg-accent text-white hover:bg-accent-hover' : 'border-line bg-surface text-text-2 hover:bg-hover'
      } disabled:cursor-default disabled:border-line disabled:bg-surface disabled:text-text-3`}
    >
      {children}
    </button>
  );
}

/** 테두리만 있는 작은 버튼 (첫 실행 화면 다시 보기 등) */
export function GhostButton({ children, onClick, disabled = false, testId }: { children: React.ReactNode; onClick(): void; disabled?: boolean; testId?: string }) {
  return (
    <button type="button" onClick={onClick} disabled={disabled} data-testid={testId} className="self-start rounded-thumb border border-line px-3.5 py-2 text-13 text-text-2 hover:bg-hover disabled:text-text-3">
      {children}
    </button>
  );
}
