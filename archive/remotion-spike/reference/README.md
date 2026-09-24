# 0단계 입력

여기에 아래 파일을 둔다. **git 에 커밋하지 않는다** (.gitignore).

| 파일 | 필수 | 설명 |
|---|---|---|
| `final.mp4` | ★ 필수 | 크리에이터가 실제로 업로드한 숏폼 1편. **목표**다 |
| `raw.mp4` | 있으면 좋음 | 같은 편의 편집 전 촬영 원본. 1단계 리프레이밍 정답지로도 쓴다 |
| — | — | 프레임은 `spike/public/frames/` 로 나간다 (Remotion 이 서빙해야 배경으로 겹쳐 볼 수 있다) |

`raw.mp4` 가 없으면 `final.mp4` 를 소스로 쓰고 자막만 다시 얹어서 비교한다.
구도 비교(통과조건 2)는 그 경우 의미가 약해지므로, 가능하면 쌍으로 받는다.

## 하는 일

```
pnpm spike:frames   # public/frames/ 생성 → 자막 크기·위치·색·분절을 눈으로 잰다
                    # → spike/remotion/tokens.ts 에 채우고 MEASURED=true
PROBE_BACKDROP=frames/0001.png pnpm spike:probe   # 원본 프레임 위에 자막 겹쳐 보기
pnpm spike:studio   # Remotion Studio 로 실시간 조정
pnpm spike          # 렌더 + 비교 시트 (out/compare.png)
```

`tokens.ts` 를 실측 없이 채우지 않는다. 전작이 망한 지점이다 (AGENTS.md §0-4).
