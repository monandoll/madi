/**
 * UI 문구는 전부 여기. 하드코딩 금지.
 * 전문 용어 금지: 인코딩→만드는 중, 프록시→노출 안 함, 트랜스크립트→자막.
 * 오류 문구도 AI 말투.
 */
export const copy = {
  app: {
    title: '마디',
  },
  header: {
    aiOff: 'AI 연결 안 됨',
    aiOn: 'AI 연결됨',
    renameHint: '스튜디오 이름 바꾸기',
    namePlaceholder: '스튜디오 이름',
  },
  tabs: {
    videos: '영상',
    outputs: '결과물',
    inProgress: '진행 중',
  },
  status: {
    preparing: '준비 중',
    failed: '열 수 없음',
    missing: '파일 없음',
  },
  empty: {
    noFolder: '아직 영상 폴더가 없어요.\n트레이 아이콘에서 폴더를 정해 주세요.',
    noVideos: '폴더에 영상이 아직 없어요.\n영상을 넣으면 여기에 나타나요.',
    noOutputs: '아직 만든 결과물이 없어요.',
    nothingInProgress: '지금 하고 있는 일이 없어요.',
    loading: '불러오는 중',
    disconnected: '엔진이 응답하지 않아요. 잠시 뒤 다시 시도할게요.',
  },
  error: {
    no_video_stream: '이 파일엔 영상이 없어서 열지 못했어요.',
    no_duration: '이 영상은 길이를 읽을 수 없어서 열지 못했어요.',
    ffmpeg_missing: '영상 도구를 찾지 못했어요. 마디를 다시 설치해 주세요.',
    unreadable: '이 파일은 깨져 있어서 열지 못했어요.',
    media_failed: '이 영상은 열지 못했어요. 다른 형식으로 저장해서 다시 넣어 주세요.',
  } as Record<string, string>,
} as const;

export function errorMessage(code: string | null | undefined): string {
  return (code && copy.error[code]) || copy.error['media_failed']!;
}
