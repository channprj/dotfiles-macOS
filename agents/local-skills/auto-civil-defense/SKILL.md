---
name: auto-civil-defense
description: Use when the user asks to automate the kcmes.kr 민방위 (civil defense) 사이버 교육 lectures — sequentially clicks 교육 시작 buttons of numbered lectures, plays each video at 1x to completion, and continues until no lectures remain. Triggers on phrases like "민방위 교육 자동", "kcmes 자동 시청", "민방위 사이버교육 끝까지 들어줘", "kcmes.kr 교육 자동 수강", "auto-civil-defense".
---

# kcmes 민방위 사이버 교육 자동 수강

## Overview

`https://www.kcmes.kr/edu/list` 의 민방위 사이버 교육 강의를 chrome-cdp 로 제어하여 자동 수강한다. 한 번 드라이버를 주입하면 페이지 안에서 `setInterval` 로 자율 동작 — 번호가 매겨진 정규 강의의 `교육 시작` 버튼 클릭 → 영상 mute → 영상 종료 시 LMS 가 다음 강의로 자동 전환 → 더 이상 시청할 정규 강의가 없으면 종료.

## ⚠️ 핵심 제약: 1x 재생만 가능

서버는 `POST https://kcmes.api-kpec.kr/api/record` 로 들어오는 `currentWatchTime` 의 진행 속도를 wall-clock 으로 검증한다. `playbackRate` 를 1보다 크게 잠그면:

```json
{"statusCode":400,"message":{"error":{"code":"INVALID_COMPLETE_RECORD","message":"교육수강 기록이 비정상적인 수강으로 판단됩니다. 해당 차시 강의를 다시 수강해주세요."}}}
```

라는 응답으로 완료 기록이 **거부**되며 그 차시는 다시 들어야 한다. 따라서 이 드라이버는 `playbackRate` 를 **건드리지 않는다**. 영상은 1x 정상 속도로 재생되며, 13개 강의 × 평균 6분 ≈ **약 80분** 소요.

## Scope

자동 클릭 대상:
- 번호가 매겨진 정규 강의 (`1. 민방위 기본`, `2. 민방위 조직운영`, ..., `13. 미세먼지`)

자동 클릭 **제외** (사용자가 직접 처리):
- `Intro 영상 시청` — 항상 활성 상태로 남아 무한 클릭 루프 위험
- `분대 분대_복구` — 분대별 별도 처리
- `평가 시작` — 시험은 사용자가 직접 응시

## When to Use

- 사용자가 "민방위 교육 자동", "kcmes 사이버교육 다 들어줘" 등을 요청한 경우
- `https://www.kcmes.kr/edu/list` 탭이 Chrome 에 열려 있고 로그인 상태인 경우

**Do NOT use when:**
- 1x 보다 빠르게 끝내고 싶은 경우 — 서버가 거부함
- 다른 LMS — kcmes.kr 의 DOM 구조 전용

## Prerequisites

- chrome-cdp 스킬 사용 가능 (Chrome 원격 디버깅 활성)
- `https://www.kcmes.kr/edu/list` 가 열린 채 로그인 상태

## Workflow

1. **탭 찾기** — `cdp.mjs list` 출력에서 `kcmes.kr` 의 targetId prefix 확인
2. **드라이버 주입** — `runner.js` 를 `cdp.mjs eval` 로 주입 (재주입 idempotent)
3. **상태 폴링** — `__kcmesEdu.status()` 를 주기적(2~5분)으로 호출, `done: true` 가 나올 때까지 반복
4. **완료 보고** — 완료된 강의 수 사용자에게 알림. Intro / 분대 / 평가는 사용자가 직접 처리하도록 안내

## Steps

### 1. Find / open the kcmes tab

```bash
~/.claude/skills/chrome-cdp/scripts/cdp.mjs list
```

`kcmes.kr` 행의 8자리 prefix(예: `4DD71FBA`)를 다음 명령에 사용. `<TARGET>` 으로 표기.

### 2. Inject the runner

```bash
~/.claude/skills/chrome-cdp/scripts/cdp.mjs eval <TARGET> "$(cat ~/.claude/skills/auto-civil-defense/runner.js)"
```

기본 동작:
- 모든 `<video>` 를 `muted=true` 로 설정 (재생속도는 건드리지 않음)
- 영상이 끝나면 LMS 가 다음 강의로 자동 전환 — 그대로 대기
- `/edu/list` 로 돌아오면 `^\d+\.` 로 시작하는 정규 강의의 활성 `교육 시작` 자동 클릭
- 활성 정규 강의가 없으면 `done=true`
- 30초간 진척이 없으면 `목록` 버튼 클릭 (stall 복구). 한 번 클릭하면 5초간 재클릭 안 함
- **동일 강의 클릭이 3회를 넘으면 abort** (서버가 그 차시 완료 기록을 거부 중일 가능성)

### 3. Poll status

```bash
~/.claude/skills/chrome-cdp/scripts/cdp.mjs eval <TARGET> "window.__kcmesEdu.status()"
```

응답 예:
```json
{
  "done": false,
  "completedCount": 3,
  "currentVideo": "https://kpec3-dlacc.myskcdn.net/.../min_xxxx.mp4",
  "currentTime": 120.5,
  "duration": 380.55,
  "url": "https://www.kcmes.kr/edu/detail",
  "rate": 1,
  "muted": true,
  "stallSec": 0,
  "clickCount": { "4. 동원 및 자율참여 교육 시작": 1 },
  "lastLog": [{"t": 12, "msg": "lecture advanced (count=3)"}]
}
```

`done: true` 가 될 때까지 2~5분 간격으로 반복. 강의당 6~7분 1x 재생.

### 4. Stop early or adjust

```bash
# 멈추기
~/.claude/skills/chrome-cdp/scripts/cdp.mjs eval <TARGET> "window.__kcmesEdu.stop()"

# stall 시 자동 목록 클릭 끄기
~/.claude/skills/chrome-cdp/scripts/cdp.mjs eval <TARGET> "window.__kcmesEdu.setAutoBack(false)"

# 클릭 카운트 리셋 (abort 후 재시도 시)
~/.claude/skills/chrome-cdp/scripts/cdp.mjs eval <TARGET> "window.__kcmesEdu.resetClickCount()"
```

## Quick Reference

| 작업                     | 명령                                                                                  |
| ------------------------ | ------------------------------------------------------------------------------------- |
| 탭 찾기                  | `cdp.mjs list`                                                                        |
| 드라이버 주입            | `cdp.mjs eval <T> "$(cat ~/.claude/skills/auto-civil-defense/runner.js)"`        |
| 상태 확인                | `cdp.mjs eval <T> "window.__kcmesEdu.status()"`                                       |
| 중지                     | `cdp.mjs eval <T> "window.__kcmesEdu.stop()"`                                         |
| auto-back 끄기           | `cdp.mjs eval <T> "window.__kcmesEdu.setAutoBack(false)"`                             |
| 클릭 카운트 리셋         | `cdp.mjs eval <T> "window.__kcmesEdu.resetClickCount()"`                              |
| 화면 캡처                | `cdp.mjs shot <T> /tmp/kcmes.png`                                                     |

## How It Works

- **No rate manipulation**: 서버가 wall-clock 검증을 하므로 `playbackRate` 는 1로 그대로 둔다. 드라이버는 `<video>.muted = true` 만 적용.
- **Auto-advance detection**: `video.src` 가 바뀌면 새 강의로 전환된 것으로 간주하고 `completedCount` 증가. 이 LMS 는 영상 종료 시 같은 페이지에서 새 `<video>` 로 교체된다.
- **Numbered-only filter**: `/^\d+\./` 로 시작하는 항목만 클릭 (parent textContent 에 `.` 뒤 공백이 없음). Intro 등 무한 활성 항목 차단.
- **Click-count safety**: 동일 강의를 3회 이상 클릭하면 abort. 이는 서버가 해당 차시 완료를 거부하면서 페이지가 같은 강의로 다시 떨어지는 루프를 막는다.
- **Stall recovery**: 30초간 `currentTime` 이 안 움직이면 `목록` 클릭. 5초 쿨다운으로 폭주 방지.
- **End detection**: `/edu/list` 페이지에서 활성 번호 강의가 없으면 `done=true`.

## Recovering from a Rejected Lecture

서버가 한 차시를 거부하면 그 차시는 다시 `교육 시작` 으로 돌아오고 후속 강의가 잠긴다. 이 때:

1. 드라이버는 같은 강의를 자동 재시도 (최대 3회까지).
2. 3회 모두 거부되면 abort. 페이지를 새로고침하고, `resetClickCount()` 후 재주입하거나, 사용자가 수동으로 1회 시청.
3. 잠긴 후속 강의들은 거부된 차시를 통과하면 자동으로 풀린다.

## Common Mistakes

| 실수                                          | 결과                                       | 해결                                                |
| --------------------------------------------- | ------------------------------------------ | --------------------------------------------------- |
| `playbackRate` 를 직접 1보다 크게 설정        | 서버가 `INVALID_COMPLETE_RECORD` 로 거부   | 1x 유지, 드라이버가 손대지 않음                     |
| `cdp.mjs list` 없이 하드코딩된 target 사용    | 잘못된 탭에 주입                           | 매번 list 로 확인                                   |
| 로그인 안 된 상태에서 실행                    | `unexpected page`                          | 먼저 수동 로그인                                    |
| 페이지 새로고침 후 status 확인                | `__kcmesEdu is undefined`                  | 다시 주입                                           |
| Intro 자동 클릭 기대                          | Intro 는 의도적으로 제외 (무한 루프 방지)  | 사용자가 직접 클릭                                  |
| 평가 자동 응시 기대                           | 평가는 의도적으로 제외                     | 사용자가 직접 응시                                  |
