import React from 'react';
import { interpolate, useCurrentFrame, useVideoConfig } from 'remotion';
import type { Caption as CaptionData } from '@madi/shared';
import { CAPTION, CAPTION_EMPHASIS, CAPTION_SECONDARY } from './tokens.js';

/**
 * 0단계의 핵심. stage-0.spec.md 작업순서 4.
 *
 * 이 컴포넌트 하나가 원본과 구분 안 되면 0단계는 사실상 통과다.
 * 반대로 여기서 다르면 영상 전체가 다르게 보인다. 다른 걸 만들기 전에 여기부터 맞춘다.
 *
 * 스타일 값은 전부 tokens.ts 에서 온다. props 로 색·크기를 받지 않는다 (AGENTS.md §1-2).
 */

/** text 를 강조 구간 기준으로 쪼갠다. */
function split(text: string, emphasis: CaptionData['emphasis']) {
  if (!emphasis.length) return [{ text, strong: false }];
  const sorted = [...emphasis].sort((a, b) => a.from - b.from);
  const out: { text: string; strong: boolean }[] = [];
  let cursor = 0;
  for (const e of sorted) {
    if (e.from > cursor) out.push({ text: text.slice(cursor, e.from), strong: false });
    out.push({ text: text.slice(e.from, e.to), strong: true });
    cursor = e.to;
  }
  if (cursor < text.length) out.push({ text: text.slice(cursor), strong: false });
  return out.filter((p) => p.text.length > 0);
}

/**
 * `-webkit-text-stroke` 는 획을 글자 경계의 **가운데** 기준으로 그린다.
 * 즉 8px 를 주면 바깥으로 나가는 건 4px 뿐이고, 나머지 4px 는 글자 안쪽을 파먹는다.
 * tokens.ts 의 strokeWidth 는 "눈에 보이는 바깥 두께"를 뜻하므로 2배로 넘긴다.
 * (paintOrder: 'stroke fill' 이라 안쪽으로 들어간 절반은 글자 색이 덮는다)
 */
const stroke = (visibleWidth: number, color: string) =>
  ({
    WebkitTextStrokeWidth: `${visibleWidth * 2}px`,
    WebkitTextStrokeColor: color,
    paintOrder: 'stroke fill',
  }) as React.CSSProperties;

export const Caption: React.FC<{ caption: CaptionData }> = ({ caption }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();

  const popFrames = Math.max(1, Math.round((CAPTION.popInMs / 1000) * fps));
  const scale = interpolate(frame, [0, popFrames], [CAPTION.popInScaleFrom, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const opacity = interpolate(frame, [0, Math.round(popFrames * 0.6)], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  const parts = split(caption.text, caption.emphasis);
  const secondarySize = CAPTION.fontSize * CAPTION_SECONDARY.scale;

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: height * CAPTION.bottomRatio,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: CAPTION.fontSize * CAPTION_SECONDARY.gapRatio,
        transform: `scale(${scale})`,
        opacity,
      }}
    >
      <div
        style={{
          maxWidth: width * CAPTION.maxWidthRatio,
          textAlign: 'center',
          fontFamily: CAPTION.fontFamily,
          fontSize: CAPTION.fontSize,
          fontWeight: CAPTION.fontWeight,
          lineHeight: CAPTION.lineHeight,
          color: CAPTION.color,
          wordBreak: 'keep-all',
          ...stroke(CAPTION.strokeWidth, CAPTION.strokeColor),
        }}
      >
        {parts.map((p, i) => (
          <span key={i} style={p.strong ? { color: CAPTION_EMPHASIS.color } : undefined}>
            {p.text}
          </span>
        ))}
      </div>

      {caption.secondary ? (
        <div
          style={{
            maxWidth: width * CAPTION.maxWidthRatio,
            textAlign: 'center',
            fontFamily: CAPTION.fontFamily,
            fontSize: secondarySize,
            fontWeight: 600,
            fontStyle: CAPTION_SECONDARY.italic ? 'italic' : 'normal',
            color: CAPTION_SECONDARY.color,
            ...stroke(CAPTION_SECONDARY.strokeWidth, CAPTION.strokeColor),
          }}
        >
          {caption.secondary}
        </div>
      ) : null}
    </div>
  );
};
