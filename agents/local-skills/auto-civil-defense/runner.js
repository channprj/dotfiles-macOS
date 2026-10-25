// kcmes 민방위 사이버 교육 자동 시청 드라이버 (1x, 정상 시청 모드)
//
// 서버는 `POST /api/record` 의 currentWatchTime 진행을 wall-clock 으로 검증한다.
// 1x 보다 빠르게 재생하면 `INVALID_COMPLETE_RECORD` 로 거부되며 해당 차시를 다시 들어야 한다.
// 따라서 이 드라이버는 playbackRate 를 건드리지 않고, mute + 자동 클릭만 수행한다.
(function () {
  if (window.__kcmesEdu) return window.__kcmesEdu.status();

  const state = {
    started: Date.now(),
    completedCount: 0,
    lastVideoSrc: null,
    lastCurrentTime: 0,
    lastProgressAt: Date.now(),
    stallTimeoutMs: 30000,
    backCooldownMs: 5000,
    lastBackAt: 0,
    autoBack: true,
    clickCount: {}, // parentText -> count, prevents infinite click loops
    maxClicksPerLecture: 3,
    log: [],
    done: false,
    intervalId: null,
  };

  function logMsg(msg) {
    state.log.push({
      t: Math.round((Date.now() - state.started) / 1000),
      msg: msg,
    });
    if (state.log.length > 60) state.log.shift();
  }

  function isEvalButton(btn) {
    return /평가\s*시작/.test(btn.textContent || "");
  }

  // 번호가 매겨진 정규 강의(예: "1. 민방위 기본")의 "교육 시작" 버튼만 자동 클릭한다.
  // Intro/분대/평가 등은 사용자가 수동으로 처리하도록 둔다 (각각 별도 정책으로
  // 서버가 처리하므로 자동화하면 무한 클릭 루프 또는 시험 잘못 응시 위험).
  function findStartableButton() {
    return Array.from(document.querySelectorAll("button")).find((b) => {
      if (b.disabled) return false;
      const text = (b.textContent || "").trim();
      if (!/(교육 시작|영상 시청)/.test(text)) return false;
      if (isEvalButton(b)) return false;
      const parent = (b.parentElement?.textContent || "").trim();
      return /^\d+\./.test(parent);
    });
  }

  function findListButton() {
    return Array.from(document.querySelectorAll("button")).find((b) =>
      /^목록\s*$/.test((b.textContent || "").trim()),
    );
  }

  function abort(reason) {
    logMsg("ABORT: " + reason);
    state.done = true;
    if (state.intervalId) clearInterval(state.intervalId);
  }

  function tick() {
    try {
      const v = document.querySelector("video");

      if (v) {
        try { v.muted = true; } catch (_) {}
        if (v.paused && !v.ended && v.readyState >= 2) {
          try { v.play().catch(() => {}); } catch (_) {}
        }

        const src = v.src || v.currentSrc || "";
        if (src && src !== state.lastVideoSrc) {
          if (state.lastVideoSrc) {
            state.completedCount++;
            logMsg("lecture advanced (count=" + state.completedCount + ")");
          } else {
            logMsg("first lecture started");
          }
          state.lastVideoSrc = src;
          state.lastCurrentTime = 0;
          state.lastProgressAt = Date.now();
        } else if (v.currentTime > state.lastCurrentTime + 0.1) {
          state.lastCurrentTime = v.currentTime;
          state.lastProgressAt = Date.now();
        }

        if (
          Date.now() - state.lastProgressAt > state.stallTimeoutMs &&
          Date.now() - state.lastBackAt > state.backCooldownMs &&
          state.autoBack
        ) {
          const back = findListButton();
          if (back) {
            logMsg("stalled " + Math.round((Date.now() - state.lastProgressAt) / 1000) + "s, clicking 목록");
            back.click();
            state.lastBackAt = Date.now();
            state.lastProgressAt = Date.now();
          }
        }
      } else if (location.pathname.includes("/edu/list")) {
        const btn = findStartableButton();
        if (btn) {
          const parent = (btn.parentElement?.textContent || "")
            .trim()
            .replace(/\s+/g, " ")
            .slice(0, 60);

          state.clickCount[parent] = (state.clickCount[parent] || 0) + 1;
          if (state.clickCount[parent] > state.maxClicksPerLecture) {
            abort(
              '"' + parent + '" 을 ' + state.clickCount[parent] +
              "회 클릭 — 서버가 완료 기록을 거부 중일 가능성 높음. 수동 확인 필요.",
            );
            return;
          }

          logMsg("clicking #" + state.clickCount[parent] + ": " + parent);
          btn.click();
          state.lastProgressAt = Date.now();
        } else {
          logMsg("no more startable numbered lectures - DONE");
          state.done = true;
          if (state.intervalId) clearInterval(state.intervalId);
        }
      } else {
        logMsg("unexpected page: " + location.pathname);
      }
    } catch (e) {
      logMsg("tick error: " + ((e && e.message) || String(e)));
    }
  }

  state.intervalId = setInterval(tick, 1000);
  setTimeout(tick, 100);

  window.__kcmesEdu = {
    state: state,
    status: function () {
      const v = document.querySelector("video");
      return {
        done: state.done,
        completedCount: state.completedCount,
        url: location.href,
        currentVideo: state.lastVideoSrc,
        currentTime: v ? v.currentTime : null,
        duration: v ? v.duration : null,
        rate: v ? v.playbackRate : null,
        muted: v ? v.muted : null,
        stallSec: Math.round((Date.now() - state.lastProgressAt) / 1000),
        clickCount: Object.assign({}, state.clickCount),
        lastLog: state.log.slice(-5),
      };
    },
    stop: function () {
      if (state.intervalId) clearInterval(state.intervalId);
      state.done = true;
      logMsg("stopped by user");
      return state;
    },
    setAutoBack: function (b) {
      state.autoBack = !!b;
      return state.autoBack;
    },
    resetClickCount: function (parent) {
      if (parent) delete state.clickCount[parent];
      else state.clickCount = {};
      return state.clickCount;
    },
  };

  return window.__kcmesEdu.status();
})();
