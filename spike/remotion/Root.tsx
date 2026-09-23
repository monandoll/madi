import React from 'react';
import { Composition, getInputProps } from 'remotion';
import { compositionDuration, parseComposition } from '@madi/shared';
import { Short } from './Short.js';
import { FRAME } from './tokens.js';

// Remotion Studio 에서도 composition.json 을 쓰도록 한다.
// studio 실행 시 --props=composition.json 을 주거나 inputProps 로 넘긴다.
const props = getInputProps() as { spec?: unknown };
const fallback = { spec: props.spec ?? null };

export const RemotionRoot: React.FC = () => {
  const spec = fallback.spec;
  let durationInFrames = 30 * 30;
  if (spec) {
    try {
      durationInFrames = Math.max(1, Math.round(compositionDuration(parseComposition(spec)) * FRAME.fps));
    } catch {
      // 스키마가 안 맞으면 기본 길이로 띄우고 Short 안에서 에러를 보여준다.
    }
  }
  return (
    <Composition
      id="Short"
      component={Short as never}
      durationInFrames={durationInFrames}
      fps={FRAME.fps}
      width={FRAME.width}
      height={FRAME.height}
      defaultProps={{ spec } as never}
    />
  );
};
