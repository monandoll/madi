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
    settings: '설정',
  },
  setup: {
    title: '처음이시죠? 두 가지만 정하면 돼요',
    subtitle: '나중에 언제든 오른쪽 위 설정에서 바꿀 수 있어요.',
    nameLabel: '스튜디오 이름',
    namePlaceholder: '예: 우리 재활 스튜디오',
    folderLabel: '영상이 있는 폴더',
    start: '시작하기',
    belowCard: '폴더를 고르면 영상이 여기에 나타나요.',
  },
  folders: {
    count: (n: number) => (n === 0 ? '영상 없음' : `영상 ${n}개`),
    pickOther: '다른 폴더 고르기…',
    add: '폴더 추가…',
    remove: '빼기',
    noPicker: '폴더 선택창은 마디가 설치된 PC에서만 열려요. 트레이 아이콘에서도 고를 수 있어요.',
    noneFound: '영상 폴더를 찾지 못했어요. 아래에서 직접 골라 주세요.',
    loading: '폴더를 찾는 중',
  },
  settings: {
    title: '설정',
    back: '뒤로',
    nameLabel: '스튜디오 이름',
    nameHelp: '화면 맨 위에 보이는 이름이에요.',
    foldersLabel: '영상 폴더',
    foldersHelp: '여기 있는 영상이 갤러리에 나타나요',
    aiLabel: 'AI',
    aiOff: '연결 안 됨',
    aiSoon: '곧 연결할 수 있어요',
    aiHelp: 'AI 없이도 자막·무음 제거·규격 변환·숏폼 자르기는 돼요.',
    version: (v: string) => `마디 ${v}`,
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
    noFolder: '아직 영상 폴더가 없어요.\n오른쪽 위 설정에서 폴더를 골라 주세요.',
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
