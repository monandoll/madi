import React from 'react';
import { interpolate, useCurrentFrame, useVideoConfig } from 'remotion';
import type { Overlay as OverlayData } from '@madi/shared';
import { HOOK } from './tokens.js';

/**
 * 0단계에서는 titleCard 만 구현한다. arrow · circle · image · counter · progress 는
 * 원본 1편에 실제로 나올 때만 만든다. 안 나오면 만들지 않는다 (stage-0.spec.md 범위).
 */
export const Overlay: React.FC<{ overlay: OverlayData }> = ({ overlay }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();

  if (overlay.kind !== 'titleCard') {
    // 아직 구현 안 한 kind 는 조용히 넘어가지 않는다. 렌더 중 눈에 띄어야 한다.
    return (
      <div style={{ position: 'absolute', top: 16, left: 16, color: '#FF3B30', fontSize: 28 }}>
        [미구현 overlay: {overlay.kind}]
      </div>
    );
  }

  const text = String(overlay.payload.text ?? '');
  const inFrames = Math.round(0.25 * fps);
  const opacity = interpolate(frame, [0, inFrames], [0, 1], { extrapolateRight: 'clamp' });

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        top: height * HOOK.topRatio,
        textAlign: 'center',
        fontSize: HOOK.fontSize,
        fontWeight: HOOK.fontWeight,
        color: HOOK.color,
        maxWidth: width * 0.9,
        margin: '0 auto',
        wordBreak: 'keep-all',
        WebkitTextStrokeWidth: `${HOOK.strokeWidth}px`,
        WebkitTextStrokeColor: HOOK.strokeColor,
        paintOrder: 'stroke fill',
        opacity,
      }}
    >
      {text}
    </div>
  );
};
