import React from 'react';
import { AbsoluteFill, Img, staticFile } from 'remotion';
import { Caption } from './Caption.js';
import { loadPretendard } from './font.js';

/**
 * 0단계 작업순서 4용. 영상 없이 자막 한 장만 그린다.
 * reference/frames/ 의 원본 프레임과 나란히 놓고 tokens.ts 값을 맞추는 데 쓴다.
 *
 * 영상이 들어오기 전에 렌더 파이프라인(번들 · 폰트 · 외곽선 · 레이아웃)이
 * 도는지 먼저 확인하는 용도이기도 하다.
 */
export const Probe: React.FC<{
  text: string;
  secondary?: string;
  emphasis?: { from: number; to: number }[];
  /** reference/frames/ 의 파일명. 주면 배경으로 깔아 겹쳐 본다. */
  backdrop?: string;
}> = ({ text, secondary, emphasis = [], backdrop }) => {
  loadPretendard();
  return (
    <AbsoluteFill style={{ backgroundColor: '#3A3F45' }}>
      {backdrop ? (
        <Img src={staticFile(backdrop)} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
      ) : null}
      <Caption
        caption={{
          id: 'probe',
          start: 0,
          end: 2,
          text,
          ...(secondary ? { secondary } : {}),
          emphasis,
          slot: 'main',
        }}
      />
    </AbsoluteFill>
  );
};
