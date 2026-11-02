// The browser page's emulator: jsbeeb's BBC Micro, booting caterpillar.ssd, drawn as the bare
// screen. Keys reach the BBC as they are; the touch buttons press Z and M (either one also
// answers BASIC's "PRESS ANY KEY").
// Built into web/ by tools/web/build.mjs. jsbeeb is GPL-3.0, so this bundle is too.
import { Cpu6502 } from "jsbeeb/6502.js";
import { findModel } from "jsbeeb/models.js";
import { Video } from "jsbeeb/video.js";
import { Canvas } from "jsbeeb/canvas.js";
import { Cmos } from "jsbeeb/cmos.js";
import * as fdc from "jsbeeb/fdc.js";
import * as utils from "jsbeeb/utils.js";
import { AudioHandler } from "jsbeeb/web/audio-handler.js";

const ROMS = "https://bbc.xania.org/"; // not ours to publish: jsbeeb's site serves them, CORS open
const DISC = "caterpillar.ssd";
const KEYS = { left: 90, right: 77 }; // Z, M
const SHIFT = 16;
const CLOCK = 2e6;
const MIN_HOLD = 60; // ms
// The 640x512 screen in jsbeeb's 1024x625 frame. MODE 7 (the BASIC title and game-over
// screens) sits further right and higher than MODE 2 (the game), measured in jsbeeb.
const W = 640, H = 512;
const CROP_MODE2 = { x: 200, y: 64 };
const CROP_MODE7 = { x: 218, y: 42 };

const screen = document.getElementById("screen");
screen.width = W;
screen.height = H;
const canvas = new Canvas(screen);
const video = new Video(false, canvas.fb32, function () {
  const { x, y } = this.teletextMode ? CROP_MODE7 : CROP_MODE2; // this: the Video (it paints from its constructor)
  canvas.paint(x, y, x + W, y + H);
});

const quiet = { toggle() {}, html() {}, on() {}, fadeIn() {}, fadeOut() {} }; // jsbeeb's audio warning, not shown here
const audio = new AudioHandler(quiet, document.createElement("canvas"), 7000, 5, true);
const resumeAudio = () => audio.tryResume().catch(() => {});

utils.setBaseUrl(ROMS);
const cpu = new Cpu6502(findModel("B-DFS1.2"), { setCpu() {} }, video, audio.soundChip, audio.ddNoise, null,
  new Cmos(), {});

const held = new Map(); // a key held by more than one source stays down until all let go
function press(code) {
  held.set(code, (held.get(code) ?? 0) + 1);
  if (held.get(code) === 1) cpu.sysvia.keyDown(code, false);
}
function release(code) {
  const n = (held.get(code) ?? 0) - 1;
  if (n > 0) return void held.set(code, n);
  held.delete(code);
  cpu.sysvia.keyUp(code);
}

// the emulator runs in a burst each animation frame: a tap shorter than that would go
// down and up between bursts and never reach the BBC, so every key stays down MIN_HOLD
const pressedAt = new Map();
window.addEventListener("keydown", (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey || e.key === "Escape" || e.key === "F11") return;
  e.preventDefault();
  resumeAudio();
  if (e.repeat) return;
  press(e.keyCode);
  pressedAt.set(e.keyCode, performance.now());
});
window.addEventListener("keyup", (e) => {
  if (!held.has(e.keyCode)) return;
  e.preventDefault();
  const wait = (pressedAt.get(e.keyCode) ?? 0) + MIN_HOLD - performance.now();
  setTimeout(() => held.has(e.keyCode) && release(e.keyCode), Math.max(0, wait));
});
window.addEventListener("blur", () => [...held.keys()].forEach((code) => {
  held.set(code, 1);
  release(code);
}));

for (const button of document.querySelectorAll("[data-key]")) {
  const code = KEYS[button.dataset.key];
  const down = new Set();
  let since = 0, letGo = 0;
  button.addEventListener("pointerdown", (e) => {
    e.preventDefault();
    resumeAudio();
    button.setPointerCapture(e.pointerId);
    if (!down.size) {
      if (letGo) clearTimeout(letGo), (letGo = 0);
      else press(code), (since = performance.now());
      button.classList.add("down");
    }
    down.add(e.pointerId);
  });
  // the game reads the keyboard once a frame: a quick tap stays down for 3 frames
  const up = (e) => {
    if (!down.delete(e.pointerId) || down.size) return;
    button.classList.remove("down");
    letGo = setTimeout(() => (letGo = 0, release(code)), Math.max(0, since + MIN_HOLD - performance.now()));
  };
  button.addEventListener("pointerup", up);
  button.addEventListener("pointercancel", up);
  button.addEventListener("contextmenu", (e) => e.preventDefault());
}
screen.addEventListener("pointerdown", resumeAudio);

// SHIFT is let go after a second of emulated time, not wall time: a slow or hidden tab
// would otherwise release it before the BBC has reset, and the disc wouldn't boot
let last = 0, shiftLeft = CLOCK;
function frame(now) {
  requestAnimationFrame(frame);
  audio.soundChip.catchUp();
  if (last) {
    const cycles = Math.min(((now - last) * CLOCK) / 1000, CLOCK / 10) | 0;
    cpu.execute(cycles);
    if (shiftLeft > 0 && (shiftLeft -= cycles) <= 0) cpu.sysvia.keyUp(SHIFT);
  }
  last = now;
}

async function boot() {
  await cpu.initialise();
  const data = new Uint8Array(await (await fetch(DISC)).arrayBuffer());
  cpu.fdc.loadDisc(0, fdc.discFor(cpu.fdc, DISC, data));
  cpu.sysvia.keyDown(SHIFT, true); // SHIFT held from power on: the disc boots
  requestAnimationFrame(frame);
  document.body.classList.add("running");
}

boot().catch((e) => {
  document.getElementById("status").textContent = `Couldn't start the emulator: ${e.message}`;
  throw e;
});
