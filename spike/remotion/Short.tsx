import React from 'react';
import { AbsoluteFill, OffthreadVideo, Sequence, staticFile } from 'remotion';
import { parseComposition, sceneDuration, type Composition as Comp } from '@madi/shared';
import { Caption } from './Caption.js';
import { Overlay } from './Overlay.js';
import { REFRAME, warnIfUnmeasured } from './tokens.js';

/**
 * 9:16 컴포지션 루트.
 * 0단계에서는 reframe.keyframes 를 손으로 적는다. 자동 추적은 1단계.
 */
export const Short: React.FC<{ spec: unknown }> = ({ spec }) => {
  warnIfUnmeasured();
  const comp: Comp = parseComposition(spec);

  let offsetSec = 0;
  return (
    <AbsoluteFill style={{ backgroundColor: '#000' }}>
      {comp.scenes.map((scene) => {
        const durSec = sceneDuration(scene);
        const from = Math.round(offsetSec * comp.fps);
        const durFrames = Math.round(durSec * comp.fps);
        offsetSec += durSec;

        // 0단계: 첫 키프레임을 전 구간 고정으로 쓴다. 시간축 보간은 1단계.
        const kf = scene.reframe.keyframes[0]?.rect ?? { x: 0, y: 0, w: 1, h: 1 };

        return (
          <Sequence key={scene.id} from={from} durationInFrames={durFrames}>
            <AbsoluteFill style={{ overflow: 'hidden' }}>
              <div
                style={{
                  position: 'absolute',
                  width: `${100 / kf.w}%`,
                  height: `${100 / kf.h}%`,
                  left: `${(-kf.x / kf.w) * 100}%`,
                  top: `${(-kf.y / kf.h) * 100}%`,
                }}
              >
                <OffthreadVideo
                  src={staticFile(`${scene.source.videoId}.mp4`)}
                  startFrom={Math.round(scene.source.in * comp.fps)}
                  endAt={Math.round(scene.source.out * comp.fps)}
                  playbackRate={scene.speed}
                  style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                />
              </div>
            </AbsoluteFill>

            {scene.overlays.map((ov) => (
              <Sequence
                key={ov.id}
                from={Math.round(ov.start * comp.fps)}
                durationInFrames={Math.round((ov.end - ov.start) * comp.fps)}
              >
                <Overlay overlay={ov} />
              </Sequence>
            ))}

            {scene.captions.map((cap) => (
              <Sequence
                key={cap.id}
                from={Math.round(cap.start * comp.fps)}
                durationInFrames={Math.round((cap.end - cap.start) * comp.fps)}
              >
                <Caption caption={cap} />
              </Sequence>
            ))}
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};

/** REFRAME 목표치는 1단계 자동 리프레이밍에서 쓴다. 0단계에서는 참조만. */
export const _reframeTarget = REFRAME.targetSubjectHeightRatio;
