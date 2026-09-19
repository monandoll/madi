import { describe, expect, it } from 'vitest';
import { linkSiteLabel, normalizeVideoUrl } from '@madi/shared';
import { classifyLinkError, parseYtdlpOutput, ytdlpArgs } from '../src/style/link.js';

describe('yt-dlp 오류 → 코드 (JS 런타임)', () => {
  it('JS 런타임 · 챌린지 문제는 도구 쪽 실패로 (지금은 볼 수 없는 영상이 아니다)', () => {
    expect(classifyLinkError('WARNING: [youtube] No supported JavaScript runtime could be found. ERROR: Requested format is not available')).toBe('link_failed');
    expect(classifyLinkError('ERROR: [youtube] abc: n challenge solving failed')).toBe('link_failed');
  });
});

describe('링크 고르기', () => {
  it('글 안에서 http(s) 주소 하나를 집어낸다', () => {
    expect(normalizeVideoUrl('https://www.youtube.com/watch?v=abc123')).toBe('https://www.youtube.com/watch?v=abc123');
    expect(normalizeVideoUrl('  이거 봐 https://youtu.be/abc123 좋더라')).toBe('https://youtu.be/abc123');
    expect(normalizeVideoUrl('https://www.tiktok.com/@u/video/123.')).toBe('https://www.tiktok.com/@u/video/123');
    expect(normalizeVideoUrl('http://instagram.com/reel/xyz/')).toBe('http://instagram.com/reel/xyz/');
  });
  it('주소가 아니면 null', () => {
    expect(normalizeVideoUrl('')).toBeNull();
    expect(normalizeVideoUrl('햄스트링 스트레칭')).toBeNull();
    expect(normalizeVideoUrl('ftp://x.com/a')).toBeNull();
    expect(normalizeVideoUrl('https://localhost/a')).toBeNull();
    expect(normalizeVideoUrl('youtube.com/watch?v=1')).toBeNull();
  });
  it('출처 이름', () => {
    expect(linkSiteLabel('https://www.youtube.com/shorts/x')).toBe('유튜브');
    expect(linkSiteLabel('https://youtu.be/x')).toBe('유튜브');
    expect(linkSiteLabel('https://vm.tiktok.com/x')).toBe('틱톡');
    expect(linkSiteLabel('https://www.instagram.com/reel/x')).toBe('인스타그램');
    expect(linkSiteLabel('https://vimeo.com/1')).toBe('vimeo.com');
    expect(linkSiteLabel('nope')).toBe('');
  });
});

describe('yt-dlp', () => {
  it('인자: 재생목록 제외 · 720p 이하 mp4 · 표시 줄 · URL 은 -- 뒤', () => {
    const args = ytdlpArgs({ url: 'https://youtu.be/x', outBase: '/tmp/refs/abc', ffmpeg: '/bin/ffmpeg' });
    expect(args).toContain('--no-playlist');
    expect(args[args.indexOf('-o') + 1]).toBe('/tmp/refs/abc.%(ext)s');
    expect(args[args.indexOf('-f') + 1]).toContain('height<=720');
    expect(args[args.indexOf('--ffmpeg-location') + 1]).toBe('/bin/ffmpeg');
    expect(args.slice(-2)).toEqual(['--', 'https://youtu.be/x']);
    expect(args.filter((a) => a === '--print')).toHaveLength(2);
    expect(ytdlpArgs({ url: 'u', outBase: 'b' })).not.toContain('--ffmpeg-location');
    // 유튜브용 JS 런타임: 우리 node 를 직접 알려 준다 (트레이 앱은 PATH 가 비어 있다)
    const withNode = ytdlpArgs({ url: 'u', outBase: 'b', nodeBin: '/Applications/madi-engine.app/Contents/MacOS/madi-engine' });
    expect(withNode[withNode.indexOf('--js-runtimes') + 1]).toBe('node:/Applications/madi-engine.app/Contents/MacOS/madi-engine');
    expect(withNode.slice(-2)).toEqual(['--', 'u']);
  });
  it('출력에서 파일·제목을 읽는다', () => {
    const out = '[download] 100%\nMADI_FILE\t/tmp/refs/abc.mp4\nMADI_TITLE\t햄스트링 루틴\n';
    expect(parseYtdlpOutput(out)).toEqual({ filePath: '/tmp/refs/abc.mp4', title: '햄스트링 루틴' });
    expect(parseYtdlpOutput('MADI_FILE\t/tmp/refs/abc.mp4\n')).toEqual({ filePath: '/tmp/refs/abc.mp4', title: 'abc' });
    expect(parseYtdlpOutput('nothing here')).toBeNull();
  });
  it('오류 분류', () => {
    expect(classifyLinkError('ERROR: Sign in to confirm you’re not a bot')).toBe('link_private');
    expect(classifyLinkError('ERROR: Private video. Login required')).toBe('link_private');
    expect(classifyLinkError('ERROR: Unsupported URL: https://x.com')).toBe('link_unsupported');
    expect(classifyLinkError('ERROR: Video unavailable')).toBe('link_unavailable');
    expect(classifyLinkError('ERROR: Unable to download webpage: <urlopen error timed out>')).toBe('link_network');
    expect(classifyLinkError('something odd')).toBe('link_failed');
  });
});
