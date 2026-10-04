"""A tiny frame-accurate non-linear editor in Python: items (video shots, graphics layers, procedural cards, subtitles) on a timeline,
composited per frame with numpy / OpenCV, piped to ffmpeg.  Audio is mixed separately (promo/audio.py) and muxed at the end.

  tl = Timeline(fps=60)
  tl.add(Shot("promo_work/rec/m1_day.avi", src_in=20.0, dur=3.0, start=16.9, zoom=(1.0, 1.08)))
  tl.add(LayerItem(layer_rgba, start=17.0, end=20.0, pos=(300, 900), anim_in=slide_in('left'), anim_out=fade_out(0.3)))
  tl.render("out.mp4", t0=0, t1=30)            # or tl.frame_at(12.3) -> BGR image for stills / QA
"""
from __future__ import annotations

import ctypes
import math
import os
import subprocess
import sys
import time
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gfx  # noqa: E402

FFMPEG = "ffmpeg"
W, H = gfx.W, gfx.H


def free_ram_gb():
    """free physical memory in GB (Windows), None when unknown"""
    try:
        class MEMSTAT(ctypes.Structure):
            _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong), ("ullTotalPhys", ctypes.c_ulonglong),
                        ("ullAvailPhys", ctypes.c_ulonglong), ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                        ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong), ("sullAvailExtendedVirtual", ctypes.c_ulonglong)]
        m = MEMSTAT()
        m.dwLength = ctypes.sizeof(MEMSTAT)
        ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
        return m.ullAvailPhys / (1024 ** 3)
    except Exception:
        return None


# ------------------------------------------------------------------ video source
class ShotReader:
    """sequential frame access into a recording via an ffmpeg rawvideo pipe (re-seeks when the access is not sequential)"""

    def __init__(self, path: str, fps: float = 60.0, w: int = W, h: int = H, fit: str = "cover"):
        self.path, self.fps, self.w, self.h, self.fit = str(path), fps, w, h, fit
        self.proc = None
        self.next_idx = 0
        self.cache = None
        self.cache_idx = -1
        self.src_w = self.src_h = None
        self._probe()

    def _probe(self) -> None:
        out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height,r_frame_rate,duration",
                              "-of", "csv=p=0", self.path], capture_output=True, text=True).stdout.strip().split(",")
        self.src_w, self.src_h = int(out[0]), int(out[1])
        n, d = out[2].split("/")
        self.fps = float(n) / float(d)
        try:
            self.duration = float(out[3])
        except ValueError:
            self.duration = 1e9

    def _vf(self) -> str:
        if (self.src_w, self.src_h) == (self.w, self.h):
            return "null"
        if self.fit == "contain":
            return f"scale={self.w}:{self.h}:flags=area:force_original_aspect_ratio=decrease,pad={self.w}:{self.h}:(ow-iw)/2:(oh-ih)/2"
        return f"scale={self.w}:{self.h}:flags=area:force_original_aspect_ratio=increase,crop={self.w}:{self.h}"

    def _open(self, idx: int) -> None:
        self.close()
        t = max(0.0, idx / self.fps)
        cmd = [FFMPEG, "-v", "error", "-ss", f"{t:.5f}", "-i", self.path, "-an", "-vf", self._vf(), "-f", "rawvideo", "-pix_fmt", "bgr24", "-"]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=self.w * self.h * 3)
        self.next_idx = idx

    def close(self) -> None:
        if self.proc is not None:
            try:
                self.proc.stdout.close()
                self.proc.kill()
                self.proc.wait(timeout=5)
            except Exception:
                pass
            self.proc = None

    def release(self) -> None:
        """the shot is over: kill its ffmpeg and drop the cached frame (a re-visit simply reopens the reader)"""
        self.close()
        self.cache = None
        self.cache_idx = -1

    def get(self, t: float) -> np.ndarray:
        idx = max(0, int(round(t * self.fps)))
        if idx == self.cache_idx and self.cache is not None:
            return self.cache
        if self.proc is None or idx < self.next_idx - 1 or idx > self.next_idx + 90:
            self._open(idx)
        size = self.w * self.h * 3
        while self.next_idx <= idx:
            buf = self.proc.stdout.read(size)
            if len(buf) < size:                      # end of the clip: hold the last frame
                if self.cache is None:
                    self.cache = np.zeros((self.h, self.w, 3), np.uint8)
                self.cache_idx = idx
                return self.cache
            self.cache = np.frombuffer(buf, np.uint8).reshape(self.h, self.w, 3)
            self.cache_idx = self.next_idx
            self.next_idx += 1
        return self.cache


# ------------------------------------------------------------------ items
class Item:
    z = 0
    start = 0.0
    end = 0.0

    def active(self, t: float) -> bool:
        return self.start <= t < self.end

    def draw(self, canvas: np.ndarray, t: float) -> None:  # pragma: no cover
        raise NotImplementedError

    def close(self) -> None:
        pass


def _fade_alpha(t, start, end, fi, fo):
    a = 1.0
    if fi > 0:
        a = min(a, gfx.clamp01((t - start) / fi))
    if fo > 0:
        a = min(a, gfx.clamp01((end - t) / fo))
    return a


class Shot(Item):
    """a piece of a recording.  zoom=(z0, z1) animates a push-in / pull-out over the shot, `center` is the zoom target (0..1),
    `rect`/`radius` place the shot inside a rounded window instead of full frame (picture-in-picture, phone mock-ups)."""

    def __init__(self, path: str, src_in: float, dur: float, start: float, speed: float = 1.0, zoom=(1.0, 1.0), center=(0.5, 0.5),
                 center_to=None, fade_in: float = 0.0, fade_out: float = 0.0, z: int = 0, fit: str = "cover", rect=None, radius: int = 0,
                 grade=None, shake: float = 0.0, hold_last: bool = False, res: int = 1920):
        self.path, self.src_in, self.dur, self.start, self.speed = path, src_in, dur, start, speed
        self.end = start + dur
        self.zoom, self.center, self.center_to = zoom, center, center_to or center
        self.fade_in, self.fade_out, self.z = fade_in, fade_out, z
        self.rect, self.radius, self.grade, self.shake = rect, radius, grade, shake
        if rect is not None:
            rw, rh = rect[2], rect[3]
            self.reader = ShotReader(path, w=int(rw * 1.5) // 2 * 2, h=int(rh * 1.5) // 2 * 2, fit=fit)
        else:
            self.reader = ShotReader(path, w=res, h=res * 9 // 16, fit=fit)
        self._mask = None

    def draw(self, canvas: np.ndarray, t: float) -> None:
        u = (t - self.start) / max(self.dur, 1e-6)
        frame = self.reader.get(self.src_in + (t - self.start) * self.speed)
        z = gfx.lerp(self.zoom[0], self.zoom[1], gfx.ease_in_out(u)) if self.zoom[0] != self.zoom[1] else self.zoom[0]
        cx = gfx.lerp(self.center[0], self.center_to[0], u)
        cy = gfx.lerp(self.center[1], self.center_to[1], u)
        h, w = frame.shape[:2]
        if self.rect is None and (z != 1.0 or self.shake or w != W):
            cw, ch = w / z, h / z
            x0 = min(max(cx * w - cw / 2, 0), w - cw)
            y0 = min(max(cy * h - ch / 2, 0), h - ch)
            if self.shake:
                x0 = min(max(x0 + math.sin(t * 37.0) * self.shake * w, 0), w - cw)
                y0 = min(max(y0 + math.cos(t * 41.0) * self.shake * h, 0), h - ch)
            ix0, iy0 = int(round(x0)), int(round(y0))
            iw, ih = int(round(cw)), int(round(ch))
            roi = frame[iy0:iy0 + ih, ix0:ix0 + iw]
            frame = cv2.resize(roi, (W, H), interpolation=cv2.INTER_AREA if iw > W else cv2.INTER_LINEAR)
        if self.grade is not None:
            frame = self.grade(frame)
        a = _fade_alpha(t, self.start, self.end, self.fade_in, self.fade_out)
        if self.rect is None:
            if a >= 0.999:
                canvas[:] = frame
            else:
                canvas[:] = cv2.addWeighted(canvas, 1 - a, frame, a, 0)
            return
        x, y, rw, rh = self.rect
        small = cv2.resize(frame, (rw, rh), interpolation=cv2.INTER_AREA)
        if self._mask is None:
            mk = np.zeros((rh, rw), np.uint8)
            cv2.rectangle(mk, (self.radius, 0), (rw - self.radius, rh), 255, -1)
            cv2.rectangle(mk, (0, self.radius), (rw, rh - self.radius), 255, -1)
            for cxx, cyy in ((self.radius, self.radius), (rw - self.radius, self.radius), (self.radius, rh - self.radius), (rw - self.radius, rh - self.radius)):
                cv2.circle(mk, (cxx, cyy), self.radius, 255, -1)
            self._mask = (cv2.GaussianBlur(mk, (3, 3), 0).astype(np.float32) / 255.0)[:, :, None]
        roi = canvas[y:y + rh, x:x + rw].astype(np.float32)
        out = roi * (1 - self._mask * a) + small.astype(np.float32) * (self._mask * a)
        canvas[y:y + rh, x:x + rw] = out.astype(np.uint8)

    def close(self) -> None:
        self.reader.close()


class LayerItem(Item):
    """a pre-rendered RGBA layer (text, pill, icon ...) with an animation curve.  anim(u, dur) -> dict(x, y, scale, rot, alpha) deltas."""

    def __init__(self, layer: np.ndarray, start: float, end: float, pos=(W / 2, H / 2), anchor=(0.5, 0.5), anim_in=None, anim_out=None,
                 z: int = 10, scale: float = 1.0, rot: float = 0.0, alpha: float = 1.0, idle=None):
        self.layer, self.start, self.end, self.pos, self.anchor = layer, start, end, pos, anchor
        self.anim_in, self.anim_out, self.z = anim_in, anim_out, z
        self.scale, self.rot, self.alpha, self.idle = scale, rot, alpha, idle

    def draw(self, canvas: np.ndarray, t: float) -> None:
        x, y = self.pos
        s, r, a = self.scale, self.rot, self.alpha
        ti = t - self.start
        to = self.end - t
        for anim, tt in ((self.anim_in, ti), (self.anim_out, to)):
            if anim is None:
                continue
            d = anim(tt)
            if d is None:
                continue
            x += d.get("x", 0.0)
            y += d.get("y", 0.0)
            s *= d.get("scale", 1.0)
            r += d.get("rot", 0.0)
            a *= d.get("alpha", 1.0)
        if self.idle is not None:
            d = self.idle(t - self.start)
            x += d.get("x", 0.0)
            y += d.get("y", 0.0)
            s *= d.get("scale", 1.0)
            r += d.get("rot", 0.0)
        gfx.blit(canvas, self.layer, x, y, scale=s, rot=r, alpha=a, anchor=self.anchor)


class Procedural(Item):
    """full control: fn(canvas, t_local, dur) draws whatever it wants (cards, charts, particle effects)"""

    def __init__(self, fn, start: float, end: float, z: int = 5):
        self.fn, self.start, self.end, self.z = fn, start, end, z

    def draw(self, canvas: np.ndarray, t: float) -> None:
        self.fn(canvas, t - self.start, self.end - self.start)


class Flash(Item):
    def __init__(self, start: float, dur: float = 0.25, color=(255, 255, 255), peak: float = 0.9, z: int = 90):
        self.start, self.end, self.color, self.peak, self.z = start, start + dur, color, peak, z

    def draw(self, canvas: np.ndarray, t: float) -> None:
        u = (t - self.start) / (self.end - self.start)
        gfx.fill_rect(canvas, 0, 0, W, H, self.color, self.peak * (1 - u) ** 2)


class FadeBlack(Item):
    """fade from / to black over the whole frame: kind 'in' (black -> picture) or 'out' (picture -> black)"""

    def __init__(self, start: float, dur: float, kind: str = "out", color=(0, 0, 0), z: int = 99):
        self.start, self.end, self.kind, self.color, self.z = start, start + dur, kind, color, z

    def draw(self, canvas: np.ndarray, t: float) -> None:
        u = gfx.clamp01((t - self.start) / (self.end - self.start))
        a = u if self.kind == "out" else 1 - u
        gfx.fill_rect(canvas, 0, 0, W, H, self.color, a)

    def active(self, t: float) -> bool:
        return self.start <= t < self.end or (self.kind == "out" and t >= self.end and False)


# ------------------------------------------------------------------ animation curves (for LayerItem)
def slide_in(side: str = "left", dist: float = 160, dur: float = 0.45, overshoot: bool = True):
    def f(t):
        if t >= dur:
            return None
        u = gfx.ease_out_back(t / dur) if overshoot else gfx.ease_out_cubic(t / dur)
        d = (1 - u) * dist
        a = gfx.clamp01(t / (dur * 0.5))
        return {"x": -d if side == "left" else d if side == "right" else 0, "y": -d if side == "top" else d if side == "bottom" else 0, "alpha": a}
    return f


def pop_in(dur: float = 0.5, elastic: bool = True, rot: float = 0.0):
    def f(t):
        if t >= dur:
            return None
        u = gfx.ease_out_elastic(t / dur) if elastic else gfx.ease_out_back(t / dur)
        return {"scale": max(u, 0.001), "alpha": gfx.clamp01(t / (dur * 0.35)), "rot": rot * (1 - u)}
    return f


def fade_in(dur: float = 0.3):
    return lambda t: None if t >= dur else {"alpha": gfx.clamp01(t / dur)}


def fade_out(dur: float = 0.3):
    return lambda t: None if t >= dur else {"alpha": gfx.clamp01(t / dur)}


def slide_out(side: str = "left", dist: float = 160, dur: float = 0.3):
    def f(t):
        if t >= dur:
            return None
        u = gfx.ease_in_back(1 - t / dur)
        d = u * dist
        return {"x": -d if side == "left" else d if side == "right" else 0, "y": -d if side == "top" else d if side == "bottom" else 0,
                "alpha": gfx.clamp01(t / (dur * 0.6))}
    return f


def pop_out(dur: float = 0.25):
    def f(t):
        if t >= dur:
            return None
        u = t / dur
        return {"scale": max(gfx.ease_out_cubic(u), 0.001), "alpha": gfx.clamp01(u * 1.5)}
    return f


def bob(amp: float = 6.0, speed: float = 3.0):
    return lambda t: {"y": math.sin(t * speed) * amp}


# ------------------------------------------------------------------ timeline
class Timeline:
    def __init__(self, fps: int = 60, duration: float = 0.0):
        self.fps = fps
        self.items: list[Item] = []
        self.duration = duration

    def add(self, *items: Item) -> None:
        for it in items:
            self.items.append(it)
            self.duration = max(self.duration, it.end)

    def open_readers(self) -> int:
        return sum(1 for i in self.items if getattr(i, "reader", None) is not None and i.reader.proc is not None)

    def frame_at(self, t: float, bg=(0, 0, 0)) -> np.ndarray:
        # a finished Shot must not keep its ffmpeg process / cached 1440p frame alive (that was a ~30 GB leak on a full render)
        for i in self.items:
            r = getattr(i, "reader", None)
            if r is not None and t >= i.end + 0.5 and (r.proc is not None or r.cache is not None):
                r.release()
        canvas = np.empty((H, W, 3), np.uint8)
        canvas[:] = (bg[2], bg[1], bg[0])
        for it in sorted((i for i in self.items if i.active(t)), key=lambda i: (i.z, i.start)):
            it.draw(canvas, t)
        return canvas

    def close(self) -> None:
        for it in self.items:
            it.close()

    def render(self, out_path: str, t0: float = 0.0, t1: float | None = None, crf: int = 16, preset: str = "fast", scale: float = 1.0,
               audio: str | None = None, nvenc: bool = False, progress: bool = True) -> None:
        t1 = self.duration if t1 is None else t1
        n0, n1 = int(round(t0 * self.fps)), int(round(t1 * self.fps))
        ow, oh = int(W * scale) // 2 * 2, int(H * scale) // 2 * 2
        cmd = [FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{ow}x{oh}", "-r", str(self.fps), "-i", "-"]
        if audio:
            cmd += ["-ss", f"{t0:.4f}", "-i", audio, "-map", "0:v", "-map", "1:a", "-c:a", "aac", "-b:a", "256k", "-shortest"]
        if nvenc:
            cmd += ["-c:v", "h264_nvenc", "-preset", "p6", "-tune", "hq", "-rc", "vbr", "-cq", str(crf + 2), "-b:v", "0"]
        else:
            cmd += ["-c:v", "libx264", "-preset", preset, "-crf", str(crf)]
        cmd += ["-pix_fmt", "yuv420p", "-movflags", "+faststart", out_path]
        enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        t_start = time.time()
        min_free_gb = float(os.environ.get("PROMO_MIN_FREE_GB", "6"))
        try:
            for n in range(n0, n1):
                t = n / self.fps
                fr = self.frame_at(t)
                if scale != 1.0:
                    fr = cv2.resize(fr, (ow, oh), interpolation=cv2.INTER_AREA)
                enc.stdin.write(fr.tobytes())
                if (n - n0) % 120 == 0:
                    free = free_ram_gb()
                    if free is not None and free < min_free_gb:
                        raise MemoryError(f"free RAM {free:.1f} GB < {min_free_gb} GB at frame {n}: aborting the render before the machine stalls")
                if progress and (n - n0) % 120 == 0:
                    done = n - n0 + 1
                    el = time.time() - t_start
                    print(f"  frame {done}/{n1 - n0}  {done / max(el, 1e-3):.1f} fps  eta {(n1 - n0 - done) / max(done / max(el, 1e-3), 1e-3):.0f}s  "
                          f"readers {self.open_readers()}  free RAM {free_ram_gb() or 0:.1f} GB", flush=True)
        finally:
            try:
                enc.stdin.close()
            except Exception:
                pass
            enc.wait()
            self.close()
