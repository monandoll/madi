# 두 AI CLI 에 madi-mcp 를 붙여 봤다 — 도구 2개만 · 시트 이미지까지 (2026-09-27)

`docs/stage-4.spec.md` 3번(AgentProvider)에 들어가기 전 확인. 재료는 3단계 판정 때 앱 DB 에 남은
대용 영상(`uw1aUHnMfo8` 앞 60초) 다이제스트 — **DB 를 복사해서** 그 사본에 붙였다. 앱 DB 는 건드리지 않았다.
작업 폴더는 빈 폴더(CLAUDE.md · AGENTS.md 가 딸려 오지 않게).

| | Claude Code 2.1.283 | Codex CLI 0.156.1 |
|---|---|---|
| 보이는 도구 | `mcp__madi__read_digest` · `mcp__madi__write_composition` **뿐** | madi 2개 + 끌 수 없는 것 몇 개 (아래) |
| `read_digest` 텍스트 | ✅ | ✅ |
| 시트 이미지(MCP 이미지 블록) | ✅ 인물 · 매트 · 박힌 제목까지 읽었다 | ✅ 인물 · 자세를 읽었다 |
| 셸 | 없음 ("Bash 없음") | 없음 ("셸 실행 도구가 제공되지 않아") |
| 기본 모델 | `claude-opus-5-5` (`modelUsage` 에 찍힌다) | 사용자 설정을 무시하면 CLI 기본값 (이벤트에 모델 이름이 안 찍힌다) |

## Claude — 옵션만으로 닫힌다

```
claude -p <프롬프트> --mcp-config <파일> --strict-mcp-config --tools "" \
  --allowedTools mcp__madi__read_digest,mcp__madi__write_composition \
  --setting-sources "" --no-session-persistence --output-format stream-json
```

- `--tools ""` 로 기본 도구가 전부 꺼진다. `--strict-mcp-config` 로 사용자 MCP 서버가 안 딸려 온다
- `--setting-sources ""` 로 사용자 · 프로젝트 설정(훅 등)을 안 읽는다

## Codex — 사용자 설정을 무시하고 기능을 하나씩 끈다

처음엔 사용자 `~/.codex/config.toml` 이 플러그인 · 브라우저 · 컴퓨터 사용 · 노드 REPL MCP 를 같이 실었다.
크리에이터 Mac 의 설정도 제각각일 것이므로 **`--ignore-user-config`** (로그인은 그대로 쓴다)로 띄운다.

```
codex exec --json --ignore-user-config --skip-git-repo-check -s read-only -C <빈 폴더> \
  -c features.<아래>=false … -c web_search="disabled" \
  -c mcp_servers.madi.command="…/madi-mcp" -c mcp_servers.madi.args=[…] \
  -c mcp_servers.madi.default_tools_approval_mode="approve"
```

끈 기능: `shell_tool` · `unified_exec` · `apps` · `plugins` · `multi_agent` · `image_generation` · `browser_use` ·
`browser_use_external` · `computer_use` · `goals` · `view_image` · `sleep_tool` · `tool_suggest` · `skill_search` ·
`in_app_browser` · `hooks`.

겪은 것:

1. **코드 모드(`code_mode_host`)는 끄면 안 된다.** 이 판에서는 MCP 도구도 코드 모드의 `exec` 안에서 불린다.
   끄면 "Code Mode is unavailable … fail closed" 로 아무 도구도 못 부른다. 그래서 모델에게 도구 목록을 물으면
   madi 가 안 보이고 `exec` 만 보인다 — **자기 보고를 믿지 말고 이벤트의 `mcp_tool_call` 을 본다**
2. **MCP 호출은 기본이 승인 필요**다. `exec` 는 승인 정책이 `never` 라 그대로 실패한다
   ("MCP tool call requires approval, but approval policy is never"). 서버 단위로
   `default_tools_approval_mode="approve"` (값: `auto` · `prompt` · `writes` · `approve`)
3. `include_apply_patch_tool` 은 이 판에서 없어진 키다 (무시된다고 경고)
4. 끄지 못한 것: `wait` · `request_user_input` · 협업(`collaboration.*`) · `apply_patch` · MCP 리소스 읽기 · 시계.
   `-s read-only` 라 `apply_patch` 는 파일을 못 쓴다. `request_user_input` 은 사람이 없는 `exec` 에서 답이 오지 않는다.
   **파일을 읽는 도구는 남지 않았다** (셸 · `view_image` 꺼짐)

## 3번 단위에 가져갈 것

- Codex 는 **판마다 기능 이름이 바뀐다**(위 3번). 끄는 목록을 코드에 박되, 모르는 키 경고(`item.completed` 의 `error`)를
  `events` 에 남겨 판이 바뀐 걸 알아챈다
- 두 CLI 다 판을 적는다 (`--version`). 모델 이름은 Claude 는 결과에서, Codex 는 따로 알아내야 한다 — 결정 ②
- 확인한 판: Claude Code 2.1.283 · Codex CLI 0.156.1 (Homebrew Cask)
