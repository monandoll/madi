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
    aiOn: (label: string) => `${label}로 연결됨`,
    aiMissing: (label: string) => `${label}를 이 PC에서 찾지 못했어요`,
    aiHelp: 'AI 없이도 자막·무음 제거·규격 변환·숏폼 자르기는 돼요.',
    aiPickHelp: '이 PC에 설치된 도구 중 하나를 고르면 채팅으로 편집을 시킬 수 있어요. 본인 구독으로 돌아가요.',
    aiInstalled: (v: string | null) => (v ? `설치됨 · ${v}` : '설치됨'),
    aiNotInstalled: '설치 안 됨',
    aiUse: '쓰기',
    aiInUse: '쓰는 중',
    aiDisconnect: '연결 끊기',
    aiChecking: '찾는 중',
    styleLabel: '편집 스타일',
    styleHelp: '여기 적힌 대로 AI가 편집해요. 채팅에서 "앞으로도 이렇게"라고 하면 한 줄씩 늘어나요.',
    styleLearnedTag: '배움',
    styleNoRules: '아직 규칙이 없어요.',
    styleAddPlaceholder: '규칙 한 줄 (예: 인트로는 3초만)',
    styleAdd: '추가',
    styleRemove: '빼기',
    referencesLabel: '완성본에서 배우기',
    referencesHelp: '예전에 만든 완성본 폴더를 정하면 길이·비율·쉬는 구간 기준을 배워요. 갤러리엔 안 나타나요.',
    referencesEmpty: '완성본 폴더가 아직 없어요.',
    referencesCount: (done: number, busy: number, failed: number) =>
      [`완성본 ${done}개`, busy ? `배우는 중 ${busy}개` : '', failed ? `못 읽음 ${failed}개` : ''].filter(Boolean).join(' · '),
    referencesRelearn: '다시 배우기',
    remoteLabel: '밖에서 접속하기',
    remoteHelp: 'Cloudflare Tunnel 토큰을 붙여 넣으면 폰이나 다른 PC에서도 이 마디에 들어올 수 있어요.',
    remotePlaceholder: '토큰 붙여넣기',
    remoteSave: '연결',
    remoteClear: '끊기',
    remoteStatus: {
      off: '연결 안 함',
      starting: '연결하는 중',
      running: '연결됨',
      error: '연결이 안 돼요. 토큰을 다시 확인해 주세요.',
    } as Record<string, string>,
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
    working: '만드는 중',
    outputs: (n: number) => `결과물 ${n}개`,
  },
  empty: {
    noFolder: '아직 영상 폴더가 없어요.\n오른쪽 위 설정에서 폴더를 골라 주세요.',
    noVideos: '폴더에 영상이 아직 없어요.\n영상을 넣으면 여기에 나타나요.',
    noOutputs: '아직 만든 결과물이 없어요.',
    nothingInProgress: '지금 하고 있는 일이 없어요.',
    loading: '불러오는 중',
    disconnected: '엔진이 응답하지 않아요. 잠시 뒤 다시 시도할게요.',
  },
  detail: {
    back: '뒤로',
    outputs: (n: number) => `결과물 ${n}개`,
    noOutputs: '결과물 없음',
    previewOpen: '프리뷰 펼치기',
    previewClose: '프리뷰 접기',
    /** AI 미연결 상태의 버튼 4개 (+ 긴 영상이면 2개 더) */
    actions: {
      subtitle: '자막 넣기',
      silence: '쉬는 구간 잘라내기',
      vertical: '세로로 바꾸기',
      short: '숏폼 자르기',
      chapters: '챕터 나누기',
      autoShorts: '숏폼 3개 뽑기',
    },
    chaptersCard: {
      title: (n: number) => `챕터 ${n}개`,
      makeShort: '숏폼으로',
      noHighlight: '너무 짧아요',
    },
    shortPicker: {
      title: '어디부터 어디까지 자를까요?',
      start: '시작',
      end: '끝',
      withSubtitles: '자막도 넣기',
      make: '이 구간으로 만들기',
      cancel: '취소',
      tooShort: '1초보다 길어야 해요.',
    },
    outputCard: {
      download: '다운로드',
      revise: '수정 요청',
      more: '자세히',
      reviseHint: 'AI를 연결하면 말로 고칠 수 있어요.',
      /** 수정 요청을 누르면 입력창에 미리 채우는 말 */
      revisePrefill: (title: string) => `「${title}」 고쳐줘: `,
    },
    /** AI 연결 뒤의 채팅 입력 */
    chat: {
      placeholder: '말로 요청하세요',
      send: '보내기',
      stop: '멈추기',
      chips: ['숏폼 뽑아줘', '자막 넣어줘', '쉬는 구간 잘라줘'],
      /** 긴 영상(2분 이상) */
      chipsLong: ['챕터 나눠줘', '숏폼 3개 뽑아줘', '자막 넣어줘'],
      thinking: '생각하는 중',
      working: '만드는 중',
    },
    progressEta: (sec: number) => (sec < 60 ? '금방 돼요' : `약 ${Math.max(1, Math.round(sec / 60))}분`),
  },
  output: {
    back: '뒤로',
    download: '다운로드',
    revise: '수정 요청',
    cutMeta: (sec: number) => `${sec}초 잘림`,
    noSubtitles: '이 결과물엔 자막이 없어요.',
    notFound: '이 결과물을 찾지 못했어요. 지워졌을 수도 있어요.',
  },
  /**
   * 엔진이 남기는 대화 코드 → 문장. AI 말투. params 로 채운다.
   * 새 코드를 엔진에 추가하면 여기도 같이.
   */
  chat: {
    greeting: (p: { durationSec: number; hasAudio: boolean }) =>
      p.hasAudio
        ? `이 영상 ${fmtMin(p.durationSec)}이네요. 무엇을 해드릴까요?`
        : `이 영상 ${fmtMin(p.durationSec)}이네요. 소리가 없어서 자막이랑 쉬는 구간 잘라내기는 안 되지만, 세로 변환이랑 숏폼은 돼요.`,
    'action.subtitle': () => '자막 넣어줘',
    'action.silence': () => '쉬는 구간 잘라줘',
    'action.vertical': () => '세로로 바꿔줘',
    'action.short': (p: { start: number; end: number }) => `${fmtClock(p.start)}부터 ${fmtClock(p.end)}까지 숏폼으로 잘라줘`,
    'action.chapters': () => '챕터로 나눠줘',
    'action.auto_shorts': (p: { max: number }) => `숏폼 ${p.max}개 뽑아줘`,
    'progress.chapters': (p: { hasAudio?: boolean }) => (p.hasAudio === false ? '장면을 보고 챕터 나누는 중' : '자막을 보고 챕터 나누는 중'),
    'chapters.ready': (p: { count: number }) => `챕터 ${p.count}개로 나눴어요. 마음에 드는 챕터는 바로 숏폼으로 만들 수 있어요.`,
    'chapters.shorts': (p: { count: number; shorts: number }) => `챕터 ${p.count}개로 나누고, ${p.shorts}개를 숏폼으로 만들고 있어요.`,
    'progress.transcribe': () => '자막 만드는 중',
    'progress.silence': () => '쉬는 구간 찾는 중',
    'progress.render': (p: { action?: string; cuts?: number; removedSec?: number; title?: string }) =>
      p.action === 'silence' && p.cuts
        ? `쉬는 구간 ${p.cuts}곳, ${p.removedSec ?? 0}초를 빼고 만드는 중`
        : p.action === 'short'
          ? '숏폼 만드는 중'
          : p.action === 'vertical'
            ? '세로로 만드는 중'
            : p.action === 'ai' && p.title
              ? `「${p.title}」 만드는 중`
              : '만드는 중',
    'transcript.ready': (p: { segments: number }) => `자막 ${p.segments}줄을 만들었어요.`,
    'silence.none': () => '쉬는 구간이 없어서 그대로 두었어요.',
    'output.ready': (p: { action?: string; cuts?: number; removedSec?: number; title?: string }) =>
      p.action === 'silence'
        ? `쉬는 구간 ${p.cuts ?? 0}곳, ${p.removedSec ?? 0}초를 잘라냈어요.`
        : p.action === 'vertical'
          ? '세로로 바꿨어요.'
          : p.action === 'short'
            ? '숏폼 하나 만들었어요.'
            : p.action === 'subtitle'
              ? '자막을 넣었어요.'
              : p.action === 'ai' && p.title
                ? `「${p.title}」 만들었어요.`
                : '다 됐어요.',
    'user.text': (p: { text: string }) => p.text,
    'ai.text': (p: { text: string }) => p.text,
    'ai.done': () => '다 했어요.',
    'ai.stopped': () => '멈췄어요.',
  } as unknown as Record<string, (p: Record<string, any>) => string>,
  error: {
    no_video_stream: '이 파일엔 영상이 없어서 열지 못했어요.',
    no_duration: '이 영상은 길이를 읽을 수 없어서 열지 못했어요.',
    ffmpeg_missing: '영상 도구를 찾지 못했어요. 마디를 다시 설치해 주세요.',
    unreadable: '이 파일은 깨져 있어서 열지 못했어요.',
    media_failed: '이 영상은 열지 못했어요. 다른 형식으로 저장해서 다시 넣어 주세요.',
    no_audio: '이 영상은 소리가 없어서 자막을 못 만들었어요.',
    whisper_missing: '자막 도구가 아직 설치되지 않았어요. 마디를 다시 설치하면 들어와요.',
    whisper_model_missing: '자막 모델을 받지 못했어요. 인터넷이 연결되어 있는지 봐 주세요.',
    nothing_left: '잘라내고 나니 남는 게 없어서 만들지 않았어요.',
    range_too_short: '구간이 너무 짧아요. 1초보다 길게 잡아 주세요.',
    video_not_ready: '이 영상은 아직 준비 중이에요. 잠시 뒤에 다시 해 주세요.',
    too_short_for_chapters: '이 영상은 짧아서 챕터로 나눌 게 없어요. 숏폼 자르기로 바로 만들어 보세요.',
    edit_failed: '만들다가 문제가 생겼어요. 한 번 더 해 볼게요.',
    ai_off: 'AI가 연결되어 있지 않아요. 설정에서 연결해 주세요.',
    ai_busy: '아직 앞 요청을 하고 있어요. 끝나면 다시 말해 주세요.',
    ai_missing: 'AI 도구를 이 PC에서 찾지 못했어요. 설정에서 다시 골라 주세요.',
    ai_failed: 'AI가 답하다가 문제가 생겼어요. 한 번 더 말해 주세요.',
  } as Record<string, string>,
} as const;

function fmtMin(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.round(sec % 60);
  if (m === 0) return `${s}초`;
  return s === 0 ? `${m}분` : `${m}분 ${s}초`;
}

function fmtClock(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

/** 대화 코드 → 문장. 모르는 코드는 코드 그대로 (놓친 문구가 눈에 띄게). */
export function chatText(code: string, params: Record<string, any>): string {
  const fn = copy.chat[code];
  return fn ? fn(params) : code;
}

export function errorMessage(code: string | null | undefined): string {
  return (code && copy.error[code]) || copy.error['media_failed']!;
}
