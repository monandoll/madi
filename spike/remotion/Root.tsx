import React from 'react';
import { Composition, getInputProps } from 'remotion';
import { compositionDuration, parseComposition } from '@madi/shared';
import { Short } from './Short.js';
import { Probe } from './Probe.js';
import { FRAME } from './tokens.js';

// Remotion Studio 에서도 composition.json 을 쓰도록 한다.
// studio 실행 시 --props=composition.json 을 주거나 inputProps 로 넘긴다.
const props = getInputProps() as { spec?: unknown };
const inputSpec = props.spec ?? null;

export const RemotionRoot: React.FC = () => {
  let shortFrames = FRAME.fps * 30;
  if (inputSpec) {
    try {
      shortFrames = Math.max(1, Math.round(compositionDuration(parseComposition(inputSpec)) * FRAME.fps));
    } catch {
      // 스키마가 안 맞으면 기본 길이로 띄우고 Short 안에서 에러를 보여준다.
    }
  }

  return (
    <>
      <Composition
        id="Short"
        component={Short as never}
        durationInFrames={shortFrames}
        fps={FRAME.fps}
        width={FRAME.width}
        height={FRAME.height}
        defaultProps={{ spec: inputSpec } as never}
      />

      {/* 자막 한 장만 그리는 검사용. docs/style-authoring.md §3 */}
      <Composition
        id="CaptionProbe"
        component={Probe as never}
        durationInFrames={FRAME.fps}
        fps={FRAME.fps}
        width={FRAME.width}
        height={FRAME.height}
        defaultProps={
          {
            text: '골반 틀어졌으면',
            secondary: 'If your pelvis is tilted',
            emphasis: [{ from: 0, to: 2 }],
          } as never
        }
      />
    </>
  );
};
