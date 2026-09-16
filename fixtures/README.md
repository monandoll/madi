# fixtures

워커·e2e 테스트용 짧은 샘플. ffmpeg `testsrc2`/`sine` 로 만든 합성 영상이라 저작권 문제 없음.

| 파일 | 내용 |
|---|---|
| `sample-5s.mp4` | 1280×720, 30fps, 5초, 440Hz 사인파 오디오 |
| `sample-silent-3s.mp4` | 640×360, 24fps, 3초, 오디오 없음 |

다시 만들려면:

```
ffmpeg -f lavfi -i "testsrc2=size=1280x720:rate=30" -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 5 \
  -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -c:a aac -b:a 64k -shortest -movflags +faststart fixtures/sample-5s.mp4
ffmpeg -f lavfi -i "testsrc2=size=640x360:rate=24" -t 3 -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -an -movflags +faststart fixtures/sample-silent-3s.mp4
```
| `sample-gaps-8s.mp4` | 640×360, 24fps, 8초, 사인파에 2–4초·6–8초 무음 구간 (무음 제거 테스트) |

```
ffmpeg -f lavfi -i "testsrc2=size=640x360:rate=24" -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 8 \
  -filter_complex "[1:a]volume='if(between(t,2,4)+between(t,6,8),0,1)':eval=frame[a]" -map 0:v -map "[a]" \
  -c:v libx264 -preset veryfast -crf 32 -pix_fmt yuv420p -c:a aac -b:a 64k -shortest -movflags +faststart fixtures/sample-gaps-8s.mp4
```
