/** 썸네일 없을 때 시안의 회색 실루엣. ratio 는 CSS aspect-ratio 값. */
export function Thumb({ src, ratio, className = '' }: { src: string | null; ratio: '16/9' | '9/16'; className?: string }) {
  const vertical = ratio === '9/16';
  return (
    <div className={`relative overflow-hidden bg-thumb ${className}`} style={{ aspectRatio: ratio }}>
      {src ? (
        <img src={src} alt="" className="absolute inset-0 h-full w-full object-cover" loading="lazy" />
      ) : (
        <>
          <div className="absolute inset-x-0 bottom-0 bg-thumb-2" style={{ height: vertical ? '32%' : '34%' }} />
          <div
            className="absolute left-1/2 -translate-x-1/2 rounded-[4px] bg-thumb-3"
            style={{ bottom: vertical ? '14%' : '16%', width: vertical ? '44%' : '38%', height: vertical ? '32%' : '30%' }}
          />
        </>
      )}
    </div>
  );
}
