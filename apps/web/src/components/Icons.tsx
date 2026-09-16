/** 인라인 SVG 아이콘. design/v2 의 선 아이콘(24 그리드, 선 1.5~1.8). 이모지 금지. */
type P = { size?: number; className?: string };

const base = (size: number, stroke: number, className?: string) => ({
  width: size,
  height: size,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: stroke,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  'aria-hidden': true,
  className,
});

export function GearIcon({ size = 17, className }: P) {
  return (
    <svg {...base(size, 1.5, className)}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.6h.09A1.65 1.65 0 0 0 10 3.09V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9v.09a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
  );
}

/** 영상 (사이드바 · 탭) */
export function VideoIcon({ size = 16, className }: P) {
  return (
    <svg {...base(size, 1.5, className)}>
      <path d="M2.5 6.5A2 2 0 0 1 4.5 4.5h9a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2Z" />
      <path d="M15.5 10.5 21.5 7v10l-6-3.5" />
    </svg>
  );
}

/** 결과물 (폴더) */
export function FolderIcon({ size = 16, className }: P) {
  return (
    <svg {...base(size, 1.5, className)}>
      <path d="M4 4.5h7l2 2.5h7v12a1.5 1.5 0 0 1-1.5 1.5h-14A1.5 1.5 0 0 1 3 19V6a1.5 1.5 0 0 1 1-1.5Z" />
      <path d="M9.5 14.5h5" />
    </svg>
  );
}

/** 진행 중 (시계) */
export function ClockIcon({ size = 16, className }: P) {
  return (
    <svg {...base(size, 1.5, className)}>
      <path d="M12 3a9 9 0 1 1-9 9" />
      <path d="M12 8v4l3 2" />
    </svg>
  );
}

export function BackIcon({ size = 18, className }: P) {
  return (
    <svg {...base(size, 1.6, className)}>
      <path d="m15 18-6-6 6-6" />
    </svg>
  );
}

export function CloseIcon({ size = 15, className }: P) {
  return (
    <svg {...base(size, 1.5, className)}>
      <path d="M18 6 6 18M6 6l12 12" />
    </svg>
  );
}

export function CheckIcon({ size = 10, className }: P) {
  return (
    <svg {...base(size, 3, className)}>
      <path d="M5 12l5 5L20 7" />
    </svg>
  );
}

export function PlayIcon({ size = 11, className }: P) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" className={className}>
      <path d="M8 5v14l11-7z" />
    </svg>
  );
}

export function PauseIcon({ size = 11, className }: P) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" className={className}>
      <path d="M6 5h4v14H6zM14 5h4v14h-4z" />
    </svg>
  );
}

/** 보내기 (위 화살표, 선 1.8) */
export function ArrowUpIcon({ size = 15, className }: P) {
  return (
    <svg {...base(size, 1.8, className)}>
      <path d="M12 19V5M5 12l7-7 7 7" />
    </svg>
  );
}

export function StopIcon({ size = 12, className }: P) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" className={className}>
      <rect x="6" y="6" width="12" height="12" rx="2" />
    </svg>
  );
}

export function DownloadIcon({ size = 16, className }: P) {
  return (
    <svg {...base(size, 1.6, className)}>
      <path d="M12 4v11" />
      <path d="m7 11 5 4 5-4" />
      <path d="M4 19.5h16" />
    </svg>
  );
}
