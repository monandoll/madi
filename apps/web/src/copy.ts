import type { EditDiff } from '@madi/shared';
/**
 * UI 문구는 전부 여기. 하드코딩 금지.
 *
 * 말투 규칙 (시안의 문구보다 이쪽이 우선). 국내 앱들이 쓰는 방식을 그대로 따른다:
 * - **제목은 그 화면에서 할 일 하나.** 명사형이나 짧은 지시. 상태를 설명하는 문장을 쓰지 않는다.
 *   ("처음 들어온 기기입니다" ✗ → "인증번호 입력" ○ / "두 가지만 정하면 시작합니다" ✗ → "스튜디오 설정" ○)
 * - **잡초 제거.** 빼도 뜻이 안 변하는 말은 뺀다 (아직, 지금, 이, 그때는, 한 번만 하면 됩니다).
 *   토스가 "잡초"라 부르는 것. 화면 안에서 한 번 더 설명하는 문장도 잡초다.
 * - **한 화면에 한 가지.** 도움말은 한 줄까지. 두 줄째가 필요하면 대개 필요 없는 문장이다.
 * - 서술은 `-합니다`, 지시는 `-하세요`. `-해요` · `-네요` · `-죠?` 는 쓰지 않는다.
 * - 버튼은 명사형 한 단어~두 단어. 한국어 버튼은 "둘러보기"처럼 명사형으로 쓴다 ("확인", "설치", "다시 시도").
 * - 사과 · 추임새 · 감탄 없음. 오류는 "무슨 일 + 무엇을 하면 되는지" 두 가지만.
 * - 전문 용어 금지: 인코딩→만드는 중, 프록시→노출 안 함, 트랜스크립트→자막.
 * - 기기는 "폰"이 아니라 "휴대폰". 잠금 숫자가 아니라 "인증번호".
 */
export const copy = {
  app: {
    title: '마디',
  },
  header: {
    aiOff: 'AI 연결 안 됨',
    aiOn: (label: string) => `${label} 연결됨`,
    settings: '설정',
    engineOk: '연결됨',
    engineOff: '엔진 연결 안 됨',
    engineBusy: (n: number) => `연결됨 · ${n}개 만드는 중`,
    videoCount: (n: number) => `영상 ${n}개`,
    gallery: '갤러리',
    panelOpen: '결과물 보기',
    panelClose: '결과물 닫기',
    outputs: '결과물',
    thisComputer: '이 컴퓨터',
    sectionMeta: {
      videos: '폴더에 들어온 영상',
      outputs: '만들어진 결과물',
      running: '진행 중인 작업',
      settings: '이 컴퓨터에만 저장',
    } as Record<string, string>,
    galleryActions: { openFolder: '폴더 열기', upload: '영상 가져오기' },
  },
  setup: {
    title: '스튜디오 설정',
    subtitle: '나중에 설정에서 바꿀 수 있습니다.',
    nameLabel: '스튜디오 이름',
    namePlaceholder: '예: 우리 재활 스튜디오',
    folderLabel: '영상이 있는 폴더',
    start: '시작하기',
    hint: 'AI 연결은 나중에 해도 됩니다. 자막과 쉬는 구간 자르기는 바로 됩니다.',
  },
  folders: {
    count: (n: number) => (n === 0 ? '영상 없음' : `영상 ${n}개`),
    pickOther: '다른 폴더 고르기…',
    add: '폴더 추가…',
    remove: '빼기',
    noPicker: '폴더 선택창은 마디가 설치된 PC에서만 열립니다. 트레이 아이콘에서도 고를 수 있습니다.',
    noneFound: '영상 폴더를 찾지 못했습니다. 아래에서 직접 선택하세요.',
    loading: '폴더 찾는 중',
  },
  /** 새 버전 (조용하게. 오류가 아니다) */
  update: {
    ready: (v: string) => `새 버전 ${v}`,
    downloading: (v: string) => `새 버전 ${v} 받는 중`,
    installNow: '지금 업데이트',
    installing: '업데이트하는 중입니다. 잠시 뒤 다시 열립니다.',
    check: '새 버전 확인',
    checking: '확인하는 중',
    latest: '최신',
    failed: '새 버전을 확인하지 못했습니다. 인터넷을 보고 다시 시도하세요.',
  },
  settings: {
    title: '설정',
    back: '뒤로',
    nameLabel: '스튜디오 이름',
    nameHelp: '화면 맨 위에 표시됩니다.',
    foldersLabel: '영상 폴더',
    foldersChange: '바꾸기',
    foldersDone: '닫기',
    computerLabel: '이 컴퓨터',
    engineLabel: '편집 엔진',
    versionLabel: '버전',
    versionLatest: '최신',
    restartFirstRun: '첫 실행 화면 다시 보기',
    aiLabel: 'AI 연결',
    aiIntro: '쓰던 구독 계정으로 로그인합니다. 이 컴퓨터에서만 사용됩니다.',
    aiOff: '연결 안 됨',
    aiOn: (label: string) => `${label} 연결됨`,
    aiMissing: (label: string) => `${label}를 이 PC에서 찾지 못했습니다`,
    aiHelp: '연결하지 않아도 자막 · 쉬는 구간 자르기 · 규격 변환은 됩니다.',
    /** 밖으로 나가는 것을 분명히 (기획안 §12) */
    aiDataNotice: '연결하면 자막과 편집 요청이 그 도구를 통해 AI 회사 서버로 갑니다. "화면도 보여 주기"를 켜면 장면마다 뽑은 화면 몇 장(최대 24칸)도 함께 갑니다. 영상 파일은 이 컴퓨터를 떠나지 않습니다.',
    /** 대표 프레임 시트 (기획안 §10) */
    aiFrames: '화면도 보여 주기',
    aiFramesHelp: '편집안과 완성본 메모를 만들 때 장면이 바뀌는 곳의 화면을 작게 모아 같이 보여 줍니다. 사람이 어느 쪽에 있는지, 동작이 언제 시작되는지 알아냅니다.',
    aiInstalled: (v: string | null) => (v ? `설치됨 · ${v}` : '설치됨'),
    aiNotInstalled: '설치 안 됨',
    aiUse: '연결하기',
    aiInUse: '연결됨',
    aiDisconnect: '연결 해제',
    aiChecking: '찾는 중',
    aiRetry: '다시 찾기',
    aiRetrying: '다시 찾는 중',
    aiRetryHelp: '방금 설치했다면 다시 찾기를 누르세요.',
    aiPick: '직접 찾기',
    aiPicking: '선택창 열림',
    aiPickHelp: '못 찾으면 실행 파일을 직접 선택하세요.',
    aiPickBad: '이 파일로는 연결할 수 없습니다.',
    aiPickFailed: '파일 선택창을 열지 못했습니다.',
    aiCustom: '직접 선택한 파일',
    aiCustomClear: '직접 선택 해제',
    aiInstall: '이 컴퓨터에 설치',
    aiInstalling: '내려받는 중',
    aiInstallChecking: '설치 확인 중',
    aiInstallDone: '설치했습니다. 이제 연결하세요.',
    aiInstallHelp: '마디가 대신 설치합니다. 3분쯤 걸립니다.',
    aiInstallFail: {
      network: '인터넷이 끊겨 내려받지 못했습니다.',
      permission: '이 컴퓨터가 설치를 막았습니다. 아래 방법으로 진행하세요.',
      unsupported: '이 컴퓨터에서는 마디가 대신 설치할 수 없습니다. 아래 방법으로 진행하세요.',
      timeout: '오래 걸려 중단했습니다.',
      failed: '설치하지 못했습니다. 다시 시도하거나 아래 방법으로 진행하세요.',
    } as Record<string, string>,
    aiInstallRetry: '다시 시도',
    aiInstallClose: '닫기',
    aiLogin: '로그인',
    aiLoginHelp: '로그인이 풀렸을 때만 쓰면 됩니다. 휴대폰으로 접속해 있어도 여기서 됩니다.',
    aiLoginFailed: '로그인 창을 열지 못했습니다.',
    aiManual: '터미널에서 직접 실행',
    aiManualHelp: '아래 줄을 복사해 터미널(윈도우는 PowerShell)에 붙여 넣으세요.',
    aiManualCopy: '복사',
    aiManualCopied: '복사함',
    termOpening: '여는 중',
    termClose: '닫기',
    termHelp: '창에 주소가 보이면 눌러서 엽니다. 묻는 말은 여기에 입력하세요.',
    termDone: '완료했습니다. 창을 닫으세요.',
    termStopped: '중간에 끝났습니다.',
    termBusy: '열려 있는 창을 먼저 닫으세요.',
    termMissing: '도구를 먼저 설치하세요.',
    termFailed: '창을 열지 못했습니다.',
    termNoPty: '이 컴퓨터에서는 창을 열지 못했습니다. 아래 줄을 터미널에 붙여 넣으세요.',
    termLine: (line: string) => `터미널에서 직접 실행: ${line}`,
    termNative: '이 컴퓨터 창으로 열기',
    styleLabel: '내 편집 스타일',
    styleHelp: '여기 적힌 대로 AI가 편집합니다.',
    styleOff: 'AI를 연결하면 기존 영상에서 편집 스타일을 배웁니다.',
    styleConnect: '연결하기',
    styleLearnedTag: '배움',
    styleNoRules: '규칙 없음',
    styleAddPlaceholder: '규칙 한 줄 (예: 인트로는 3초만)',
    styleAdd: '추가',
    styleRemove: '빼기',
    referencesLabel: '기존 영상으로 배우기',
    referencesIntro: '예전에 만든 영상에서 길이 · 비율 · 쉬는 구간 기준을 배웁니다.',
    referencesFoldersLabel: '완성본 폴더',
    referencesHelp: '완성본 폴더를 정하면 거기서 배웁니다. 갤러리에는 나타나지 않습니다.',
    referencesEmpty: '완성본 폴더 없음',
    referencesCount: (done: number, busy: number, failed: number) =>
      [`완성본 ${done}개`, busy ? `배우는 중 ${busy}개` : '', failed ? `못 읽음 ${failed}개` : ''].filter(Boolean).join(' · '),
    referencesRelearn: '다시 배우기',
    /** 완성본별 메모 (AI 가 자막을 읽고 남긴 것) */
    referencesList: '완성본',
    insightOpen: '메모',
    insightClose: '닫기',
    insightNone: 'AI 를 연결하면 화면과 음성을 보고 구성 · 자막 · 편집 스타일을 메모합니다.',
    insightPending: '화면과 음성을 분석할 예정',
    insightCategories: { hook: '도입 방식', structure: '구성 방식', pacing: '편집 속도', captions: '자막 방식', framing: '구도' },
    insightEvidence: { visual: '화면', audio: '음성', timing: '시간' },
    insightScreenText: '화면 문구',
    insightPurpose: '취지',
    insightHook: '도입',
    insightSections: '구성',
    insightKeep: '남긴 것',
    insightShorts: '숏폼 후보',
    insightTerms: '용어',
    insightTitle: '제목과 내용',
    insightVisual: '화면',
    /** 제작자 기억 */
    memoryLabel: 'AI 가 기억한 것',
    memoryIntro: '여기 있는 것만 편집에 씁니다. 완성본에서 찾은 것은 확인해야 쓰이고, 편집 중 "앞으로도 이렇게" 한 것과 직접 쓴 것은 바로 쓰입니다.',
    memoryEmpty: '아직 기억한 것이 없습니다.',
    memoryOff: 'AI 를 연결하면 완성본을 읽고 기억합니다.',
    memoryKind: { style: '방식', keep: '반드시', avoid: '피함', term: '용어' } as Record<string, string>,
    memoryScope: { all: '모든 영상', topic: '주제', video: '한 영상' } as Record<string, string>,
    memorySource: { reference: '완성본에서', feedback: '편집 중', user: '직접' } as Record<string, string>,
    memoryAddPlaceholder: '기억할 것 한 줄 (예: 도입은 질문으로 연다)',
    memoryAdd: '추가',
    memoryRemove: '빼기',
    /** 완성본에서 찾은 것 — 확인해야 쓴다 */
    memoryProposedLabel: (n: number) => `완성본에서 찾은 것 ${n}개`,
    memoryProposedHelp: '확인한 것만 편집에 씁니다. 뺀 것은 다시 제안하지 않습니다.',
    memoryApprove: '쓰기',
    memoryApproveAll: '모두 쓰기',
    memoryEdit: '고치기',
    memoryEditSave: '저장',
    memoryEditCancel: '취소',
    memoryClearAll: '전부 지우기',
    memoryClearConfirm: '기억을 전부 지웁니다. 되돌릴 수 없습니다.',
    memoryClearYes: '지우기',
    memoryClearNo: '취소',
    /** 자막에서 고친 말 (틀린 말 → 바른 말) */
    correctionsLabel: '자막에서 고친 말',
    correctionsIntro: '자막을 고치면 여기 남습니다. 바른 말은 다음 자막부터 알려 주고, 두 번 이상 고친 말은 바로 바꿔 씁니다.',
    correctionsCount: (n: number) => (n >= 2 ? `${n}번 고침 · 바로 바꿈` : '1번 고침'),
    correctionsRemove: '빼기',
    /** 완성본 학습 제외 */
    referenceExclude: '학습에서 빼기',
    referenceInclude: '다시 넣기',
    referenceExcluded: '학습에서 뺌',
    linksLabel: '링크로 배우기',
    linksPlaceholder: '유튜브 · 틱톡 · 릴스 링크 붙여넣기',
    linksAdd: '가져오기',
    linksHelp: '링크를 붙여 넣으면 내려받아 배웁니다. 공개 영상만 됩니다.',
    linksOff: '링크 도구를 찾지 못했습니다. 도구를 준비한 뒤 다시 확인해 주세요. 파일로도 등록할 수 있습니다.',
    linksRetry: '다시 확인',
    linkBad: '영상 링크가 아닙니다.',
    linkStatus: {
      queued: '기다리는 중',
      downloading: '가져오는 중',
      analyzing: '배우는 중',
      done: '배움',
      failed: '못 읽음',
      missing: '파일 없음',
    } as Record<string, string>,
    linkErrors: {
      link_private: '로그인해야 볼 수 있는 영상이라 가져오지 못했습니다.',
      link_unsupported: '이 링크에서는 영상을 찾지 못했습니다.',
      link_unavailable: '지금은 볼 수 없는 영상입니다.',
      link_network: '인터넷 연결이 끊겨 가져오지 못했습니다.',
      link_failed: '이 링크는 가져오지 못했습니다.',
      link_unreadable: '받았는데 영상을 읽지 못했습니다. "다시 배우기"로 한 번 더 받아 보세요.',
    } as Record<string, string>,
    remoteLabel: '밖에서 접속하기',
    remoteOn: '연결됨',
    remoteHelp: '켜면 주소가 생깁니다. 휴대폰으로 스캔하면 어디서든 접속합니다.',
    remoteStart: '켜기',
    remoteStarting: '주소 만드는 중',
    remoteQrTitle: '휴대폰으로 스캔',
    remoteQrHelp: '주소를 직접 입력하면 아래 인증번호를 물어봅니다.',
    remotePin: (pin: string) => `인증번호 ${pin}`,
    remoteDevices: (n: number) => (n === 0 ? '들어온 기기 없음' : `기기 ${n}대 들어와 있음`),
    remoteWarn: '마디를 다시 시작하면 주소가 바뀝니다.',
    remoteAdvanced: '고정 주소 쓰기 (고급)',
    remoteAdvancedHelp: 'Cloudflare Tunnel 토큰이 있으면 주소가 바뀌지 않습니다.',
    remotePlaceholder: '토큰 붙여넣기',
    remoteSave: '연결',
    remoteClear: '끊기',
    remoteStatus: {
      off: '연결 안 함',
      starting: '연결하는 중',
      running: '연결됨',
      error: '연결하지 못했습니다. 토큰을 확인하세요.',
    } as Record<string, string>,
    version: (v: string) => `마디 ${v}`,
  },
  /** 휴대폰에서 올리기 (갤러리 헤더 "올리기" · PC "휴대폰에서 업로드") */
  upload: {
    button: '올리기',
    pcTitle: '영상 가져오기',
    dropHint: '갤러리로 끌어다 놓아도 됩니다.',
    dropping: '여기에 놓으세요',
    pcHelp: '휴대폰에서 마디를 열면 화면 위에 "올리기" 버튼이 있습니다. 고른 영상은 이 컴퓨터의 영상 폴더로 들어옵니다.',
    pcRemoteOn: '어디서든 올릴 수 있습니다',
    pcRemoteOff: '설정에서 "밖에서 접속하기"를 켜세요',
    pcSettings: '설정 열기',
    pickHere: '파일 고르기',
    close: '닫기',
    uploading: (pct: number) => `올리는 중 ${pct}%`,
    done: '올렸습니다. 잠시 뒤 갤러리에 나타납니다.',
    failed: '올리다가 끊겼습니다.',
    noFolder: '설정에서 영상 폴더를 먼저 정하세요.',
    notVideo: '영상 파일만 올릴 수 있습니다.',
    tooMany: '한 번에 10개까지 올릴 수 있습니다.',
    remove: '빼기',
    retry: '다시 시도',
  },
  /** 자막 직접 쓰기 (AI 없이, 소리 없는 영상에도) */
  subtitleEditor: {
    secondary: '보조 문구·번역',
    open: '자막 직접 쓰기',
    edit: '자막 고치기',
    title: '자막 직접 쓰기',
    hint: '원본 영상 시각 · 초 또는 분:초 (예: 3, 0:03.5, 1:02)',
    hintOutput: '원본 영상 시각 · 초 또는 분:초. 모든 줄을 빼면 자막 없이 저장합니다.',
    start: '시작',
    end: '끝',
    text: '자막 글',
    placeholder: '이 구간에 보일 글',
    add: '+ 줄 추가',
    remove: '줄 빼기',
    save: '저장하고 자막 넣기',
    cancel: '취소',
    badTime: '시각은 3 또는 0:03 형식으로 입력하세요.',
    badRange: '끝 시각은 시작보다 뒤이고 영상 길이 안이어야 합니다.',
    empty: '글을 한 줄 이상 써 주세요.',
  },
  /** 밖에서 처음 들어온 기기에 인증번호를 묻는 화면 */
  pair: {
    title: '인증번호 입력',
    help: 'PC 화면에 보이는 6자리 숫자를 입력하세요.',
    placeholder: '인증번호 6자리',
    submit: '확인',
    wrong: '인증번호가 맞지 않습니다.',
    off: 'PC에서 "밖에서 접속하기"를 먼저 켜세요.',
    checking: '확인 중',
  },
  tabs: {
    videos: '영상',
    outputs: '결과물',
    inProgress: '진행 중',
    settings: '설정',
  },
  /** 진행 중 카드 제목: 잡 종류 → 문장 */
  running: {
    probe: '준비 중',
    proxy: '준비 중',
    thumbnail: '준비 중',
    transcribe: '자막 만드는 중',
    silence: '쉬는 구간 찾는 중',
    render: '만드는 중',
    chapters: '챕터 나누는 중',
    plan: '편집안 만드는 중',
    analyze: '완성본 배우는 중',
    download: '링크 영상 가져오는 중',
  } as Record<string, string>,
  status: {
    preparing: '준비 중',
    failed: '열 수 없음',
    missing: '파일 없음',
    working: '만드는 중',
    outputs: (n: number) => `결과물 ${n}개`,
  },
  empty: {
    noFolder: '영상 폴더 없음\n설정에서 폴더를 선택하세요.',
    noVideos: '폴더에 영상이 들어오면 여기에 나타납니다.',
    noOutputs: '만든 결과물이 없습니다.',
    nothingInProgress: '진행 중인 작업이 없습니다.',
    loading: '불러오는 중',
    disconnected: '엔진이 응답하지 않습니다. 잠시 뒤 다시 시도합니다.',
  },
  detail: {
    back: '뒤로',
    outputs: (n: number) => `결과물 ${n}개`,
    noOutputs: '결과물 없음',
    previewOpen: '프리뷰 보기',
    previewClose: '프리뷰 닫기',
    props: { duration: '길이', recorded: '촬영일', outputs: '결과물', none: '아직 없음', count: (n: number) => `${n}개` },
    /** AI 미연결 상태의 버튼 4개 (+ 긴 영상이면 2개 더) */
    actions: {
      subtitle: '자막 넣기',
      silence: '쉬는 구간 자르기',
      vertical: '인스타 규격',
      short: '숏폼 자르기',
      chapters: '챕터 나누기',
      autoShorts: '숏폼 3개 뽑기',
    },
    actionHints: {
      subtitle: '한국어 자동',
      silence: '쉬는 곳 자동',
      vertical: '9:16',
      short: '구간 골라서',
      chapters: '2분 이상',
      autoShorts: '챕터마다',
    } as Record<string, string>,
    aiOffHint: 'AI를 연결하면 말로 편집할 수 있습니다.',
    aiOffLink: '연결하기',
    me: '나',
    ai: '마디',
    chaptersCard: {
      title: (n: number) => `챕터 ${n}개`,
      makeShort: '숏폼으로',
      noHighlight: '너무 짧음',
    },
    /** 편집안 버튼 (AI 연결 시) */
    planMake: '편집안 만들기',
    planRemake: '편집안 다시 만들기',
    /** 편집안 카드 — 취지 · 구성(시간 · 내용 · 편집 초안) · 남길 곳 · 잘라낼 후보 · 숏폼 후보 */
    planCard: {
      title: '편집안',
      purpose: '취지',
      hook: '시작',
      recipe: '반영할 방식',
      order: '장면 순서',
      captions: '자막 문구',
      captionCount: (n: number, two: number) => `${n}개${two ? ` · 보조 문구 ${two}개` : ''}`,
      limitations: '남은 제한',
      sections: '구성',
      sectionKind: { intro: '도입', setup: '준비', demo: '시범', qa: '질문', closing: '마무리', other: '' } as Record<string, string>,
      keeps: '남길 곳',
      cuts: '잘라낼 후보',
      cutKind: { repeat: '반복', ng: 'NG', aside: '잡담', silence: '침묵', other: '' } as Record<string, string>,
      shorts: '숏폼 후보',
      channel: { reels: '릴스', shorts: '쇼츠', tiktok: '틱톡', any: '' } as Record<string, string>,
      makeShort: '숏폼으로',
      apply: (cuts: number) => (cuts ? `후보 ${cuts}곳을 빼고 이 편집안으로 만들기` : '이 편집안으로 만들기'),
      noTranscript: '음성 받아쓰기 없이 화면과 장면 정보를 참고한 초안입니다.',
      terms: '용어',
      /** 후보 빼기 · 되돌리기 (뺀 것은 만들기에서 빠지고, 다시 제안하지 않는다) */
      reject: '빼기',
      restore: '되돌리기',
      rejected: '뺌',
      made: '만듦',
    },
    shortPicker: {
      title: '구간 선택',
      start: '시작',
      end: '끝',
      withSubtitles: '자막도 넣기',
      make: '이 구간으로 만들기',
      cancel: '취소',
      tooShort: '1초보다 길게 정하세요.',
    },
    outputCard: {
      download: '다운로드',
      revise: '수정 요청',
      more: '자세히',
      reviseHint: 'AI를 연결하면 말로 고칠 수 있습니다.',
      /** 수정 요청을 누르면 입력창에 미리 채우는 말 */
      revisePrefill: (title: string) => `「${title}」 고쳐줘: `,
    },
    /** AI 연결 뒤의 채팅 입력 */
    chat: {
      placeholder: '말로 요청하세요',
      send: '보내기',
      stop: '멈추기',
      chips: ['숏폼 뽑아줘', '자막 넣어줘', '쉬는 구간 잘라줘', '인스타 규격으로'],
      /** 긴 영상(2분 이상) */
      chipsLong: ['챕터로 나눠줘', '숏폼 3개 뽑아줘', '자막 넣어줘', '쉬는 구간 잘라줘'],
      thinking: '살펴보는 중…',
      errorDetail: (d: string) => `이유: ${d}`,
      working: '만드는 중…',
    },
    progressEta: (sec: number) => (sec < 60 ? '1분 미만' : `약 ${Math.max(1, Math.round(sec / 60))}분`),
  },
  output: {
    back: '뒤로',
    close: '닫기',
    download: '다운로드',
    revise: '수정 요청',
    cutMeta: (sec: number) => `${sec}초 잘림`,
    cuts: (n: number) => `잘린 구간 ${n}곳`,
    lines: (n: number) => `자막 ${n}문장`,
    fixLine: '이 문장 고쳐줘',
    restoreLine: '이 부분 살려줘',
    fixPrefill: (text: string) => `이 문장 고쳐줘: ${text}`,
    restorePrefill: (text: string) => `이 부분 살려줘: ${text}`,
    noSubtitles: '자막 없음',
    notFound: '결과물을 찾지 못했습니다. 지워졌을 수 있습니다.',
    /** 수정안 비교 (기획안 §6): 고쳐서 만든 결과물이면 전후를 같이 */
    diffTitle: '이전과 달라진 점',
    diffNone: '달라진 게 없습니다.',
    before: '이전',
    after: '지금',
    compareOpen: '이전 것과 견주기',
    compareClose: '견주기 닫기',
    diff: (d: EditDiff): string[] => {
      const r = (x: { start: number; end: number }) => `${fmtClock(x.start)}–${fmtClock(x.end)}`;
      const out: string[] = [];
      if (d.keep) out.push(d.keep.to ? (d.keep.from ? `구간을 ${r(d.keep.from)} 에서 ${r(d.keep.to)} 로 바꿨습니다.` : `${r(d.keep.to)} 구간만 씁니다.`) : '영상 전체를 씁니다.');
      if (d.parts) out.push(d.parts.to.length ? `조각 ${d.parts.to.length}개를 ${d.parts.to.map(r).join(', ')} 순서로 이어 붙였습니다.` : '조각 구성을 풀었습니다.');
      if (d.cuts.added.length) out.push(`${d.cuts.added.map(r).join(', ')} 을 더 잘라냈습니다.`);
      if (d.cuts.removed.length) out.push(`${d.cuts.removed.map(r).join(', ')} 을 다시 살렸습니다.`);
      if (d.crop) out.push(d.crop.to === 'vertical' ? '세로로 바꿨습니다.' : '가로로 돌렸습니다.');
      if (d.cropFocus) out.push(d.cropFocus.to === null ? '화면의 어느 쪽을 잡을지 다시 고릅니다.' : `화면 ${d.cropFocus.to < 0.25 ? '왼쪽' : d.cropFocus.to > 0.75 ? '오른쪽' : '가운데'}을 잡았습니다.`);
      if (d.subtitles) out.push(d.subtitles.to ? '자막을 넣었습니다.' : '자막을 뺐습니다.');
      if (d.subtitleBottom) out.push(d.subtitleBottom.to > d.subtitleBottom.from ? '자막을 위로 올렸습니다.' : '자막을 아래로 내렸습니다.');
      if (d.subtitleText) out.push('자막 문구를 수정했습니다.');
      if (d.subtitleAppearance) out.push('자막 모양을 수정했습니다.');
      if (d.emphasis?.added.length) out.push(`${d.emphasis.added.map((t) => `"${t}"`).join(', ')} 을 강조했습니다.`);
      if (d.emphasis?.removed.length) out.push(`${d.emphasis.removed.map((t) => `"${t}"`).join(', ')} 강조를 뺐습니다.`);
      return out;
    },
  },
  /**
   * 엔진이 남기는 대화 코드 → 문장. params 로 채운다.
   * 마디가 말하는 자리지만 말투는 위 규칙 그대로. 새 코드를 엔진에 추가하면 여기도 같이.
   */
  chat: {
    greeting: (p: { durationSec: number; hasAudio: boolean; plan?: boolean }) =>
      p.hasAudio
        ? p.plan
          ? `${fmtMin(p.durationSec)}짜리 영상입니다. 먼저 훑어보고 편집안을 만듭니다.`
          : `${fmtMin(p.durationSec)}짜리 영상입니다. 무엇을 해드릴까요?`
        : `${fmtMin(p.durationSec)}짜리 영상입니다. 소리가 없어 자막을 자동으로 만들 수는 없지만, 직접 써서 넣을 수 있습니다. 세로 변환과 숏폼도 됩니다.`,
    'action.plan': () => '편집안 만들어줘',
    'action.apply_plan': (p: { cuts: number }) => (p.cuts ? `잘라낼 후보 ${p.cuts}곳을 빼고 롱폼으로 만들어줘` : '편집안대로 롱폼으로 만들어줘'),
    'progress.plan': (p: { hasAudio?: boolean }) => (p.hasAudio === false ? '장면을 보고 편집안 만드는 중' : '자막을 읽고 편집안 만드는 중'),
    'plan.ready': (p: { sections: number; shorts: number; cuts: number; keeps: number }) =>
      [`편집안을 만들었습니다. 구성 ${p.sections}개`, p.shorts ? `숏폼 후보 ${p.shorts}개` : '', p.cuts ? `잘라낼 후보 ${p.cuts}곳` : '', p.keeps ? `남길 곳 ${p.keeps}곳` : '']
        .filter(Boolean)
        .join(' · ') + '. 원하는 후보를 골라 만드세요.',
    'action.subtitle': () => '자막 넣어줘',
    'action.silence': () => '쉬는 구간 잘라줘',
    'action.vertical': () => '세로로 바꿔줘',
    'action.short': (p: { start: number; end: number }) => `${fmtClock(p.start)}부터 ${fmtClock(p.end)}까지 숏폼으로 잘라줘`,
    'action.chapters': () => '챕터로 나눠줘',
    'action.auto_shorts': (p: { max: number }) => `숏폼 ${p.max}개 뽑아줘`,
    'progress.chapters': (p: { hasAudio?: boolean }) => (p.hasAudio === false ? '장면을 보고 챕터 나누는 중' : '자막을 보고 챕터 나누는 중'),
    'chapters.ready': (p: { count: number }) => `챕터 ${p.count}개로 나눴습니다. 원하는 챕터는 바로 숏폼으로 만들 수 있습니다.`,
    'chapters.shorts': (p: { count: number; shorts: number }) => `챕터 ${p.count}개로 나누고, ${p.shorts}개를 숏폼으로 만들고 있습니다.`,
    'progress.transcribe': () => '자막 만드는 중',
    'progress.silence': () => '쉬는 구간 찾는 중',
    'progress.render': (p: { action?: string; cuts?: number; removedSec?: number; title?: string }) =>
      p.action === 'silence' && p.cuts
        ? `쉬는 구간 ${p.cuts}곳, ${p.removedSec ?? 0}초를 빼고 만드는 중`
        : p.action === 'short'
          ? '숏폼 만드는 중'
          : p.action === 'vertical'
            ? '세로로 만드는 중'
            : p.action === 'plan'
              ? p.cuts
                ? `잘라낼 후보 ${p.cuts}곳, ${p.removedSec ?? 0}초를 빼고 롱폼 만드는 중`
                : '편집안대로 롱폼 만드는 중'
              : p.action === 'ai' && p.title
                ? `「${p.title}」 만드는 중`
                : '만드는 중',
    'transcript.ready': (p: { segments: number }) => `자막 ${p.segments}줄을 만들었습니다.`,
    'transcript.empty': () => '말소리를 찾지 못해 자막이 비어 있습니다. 소리가 작거나 음악만 있는 영상일 수 있습니다.',
    'silence.none': (p: { kept?: number }) => (p.kept ? `쉬는 구간 ${p.kept}곳은 동작이 이어져 남겼습니다. 잘라낼 곳이 없어 그대로 두었습니다.` : '쉬는 구간이 없어 그대로 두었습니다.'),
    'output.ready': (p: { action?: string; cuts?: number; removedSec?: number; title?: string; kept?: number; focus?: string; subtitleTop?: boolean }) =>
      outputReadyLine(p) + placementNote(p),
    'user.text': (p: { text: string }) => p.text,
    'ai.text': (p: { text: string }) => p.text,
    'ai.done': () => '끝났습니다.',
    'ai.stopped': () => '멈췄습니다.',
  } as unknown as Record<string, (p: Record<string, any>) => string>,
  error: {
    no_video_stream: '영상이 없는 파일이라 열지 못했습니다.',
    no_duration: '길이를 읽을 수 없어 열지 못했습니다.',
    ffmpeg_missing: '영상 도구를 찾지 못했습니다. 마디를 다시 설치하세요.',
    unreadable: '파일이 깨져 있어 열지 못했습니다.',
    media_failed: '이 영상을 열지 못했습니다. 다른 형식으로 저장해 다시 넣으세요.',
    no_audio: '소리가 없어 자막을 자동으로 만들 수 없습니다. "자막 직접 쓰기"로 원하는 자리에 넣을 수는 있습니다.',
    whisper_missing: '자막 도구가 없습니다. 마디를 다시 설치하세요.',
    whisper_model_missing: '자막 모델을 내려받지 못했습니다. 인터넷 연결을 확인하세요.',
    nothing_left: '잘라내고 나면 남는 구간이 없어 만들지 않았습니다.',
    range_too_short: '구간이 너무 짧습니다. 1초보다 길게 정하세요.',
    video_not_ready: '준비 중인 영상입니다. 잠시 뒤 다시 시도하세요.',
    too_short_for_chapters: '영상이 짧아 나눌 챕터가 없습니다.',
    plan_failed: '편집안을 만들지 못했습니다. 다시 시도하세요.',
    plan_missing: '편집안이 아직 없습니다. 먼저 편집안을 만드세요.',
    plan_outdated: '편집 스타일이 바뀌었습니다. 편집안을 다시 만들면 최신 지침으로 반영됩니다.',
    edit_failed: '만드는 중에 문제가 생겼습니다. 한 번 더 시도합니다.',
    ai_off: 'AI가 연결되어 있지 않습니다. 설정에서 연결하세요.',
    ai_busy: '앞 요청을 처리하는 중입니다.',
    ai_missing: 'AI 도구를 찾지 못했습니다. 설정 → AI 연결에서 다시 찾거나 설치하세요.',
    ai_failed: 'AI가 답하는 중에 문제가 생겼습니다. 다시 요청하세요.',
    ai_login: 'AI 도구에 로그인되어 있지 않습니다. 설정 → AI 연결에서 로그인하세요.',
    ai_node_missing: 'AI 도구를 실행하지 못했습니다. 마디를 다시 시작하고, 그래도 안 되면 AI 도구를 다시 설치하세요.',
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

/** 결과물 카드의 한 줄. 어떤 버튼 · 요청에서 온 결과인지에 따라 다르다. */
function outputReadyLine(p: { action?: string; cuts?: number; removedSec?: number; title?: string; kept?: number }): string {
  return (

      p.action === 'silence'
        ? `쉬는 구간 ${p.cuts ?? 0}곳, ${p.removedSec ?? 0}초를 잘라냈습니다.${p.kept ? ` 동작이 이어지는 ${p.kept}곳은 남겼습니다.` : ''}`
        : p.action === 'vertical'
          ? '세로로 바꿨습니다.'
          : p.action === 'short'
            ? '숏폼 하나를 만들었습니다.'
            : p.action === 'subtitle'
              ? '자막을 넣었습니다.'
              : p.action === 'plan'
                ? p.cuts
                  ? `편집안대로 ${p.cuts}곳, ${p.removedSec ?? 0}초를 빼고 롱폼을 만들었습니다.`
                  : '편집안대로 롱폼을 만들었습니다.'
                : p.action === 'ai' && p.title
                  ? `「${p.title}」 만들었습니다.`
                  : '끝났습니다.'
  );
}

/** 렌더가 알아서 정한 것: 세로 초점 · 자막 위치. 정한 게 없으면 빈 문자열 (조용하게). */
function placementNote(p: { focus?: string; subtitleTop?: boolean }): string {
  const parts: string[] = [];
  if (p.focus === 'left' || p.focus === 'right') parts.push(`화면 ${p.focus === 'left' ? '왼쪽' : '오른쪽'}에서 움직여서 그쪽을 잡았습니다.`);
  if (p.subtitleTop) parts.push('아래쪽 동작을 가리지 않게 자막을 위에 두었습니다.');
  return parts.length ? ` ${parts.join(' ')}` : '';
}
