// std_dsound_pal.zig — Z98 std-side PAL for DirectSound + waveOut audio.
//
// DirectSound path: dynamic dsound.dll load -> DirectSoundCreate ->
// SetCooperativeLevel(DSSCL_PRIORITY) -> a 2,048-frame 16-bit PCM buffer with
// DSBCAPS_GETCURRENTPOSITION2 | DSBCAPS_GLOBALFOCUS -> silence prefill ->
// Play(0,0,DSBPLAY_LOOPING). dsoundWrite polls GetCurrentPosition and locks
// only the free region (DirectSound returns at most two wrapped spans), copies,
// unlocks, and never sleeps. On a detected underrun it silence-fills the whole
// ring (QPC detects stalls longer than one buffer, so multi-lap stalls are
// covered) and restarts the write cursor at the play cursor without rewinding.
//
// waveOut fallback: waveOutOpen(WAVE_MAPPER) with two 2,048-frame device
// buffers, waveOutPrepareHeader/waveOutWrite and WHDR_DONE polling. A queued
// device buffer is never reused and the writer never blocks or discards an
// accepted sample: when both device buffers are busy, offered bytes go to a
// bounded static pending area and are flushed into the next freed buffer.
// Device buffers are fully silence-padded before submission, so a partially
// filled/unready buffer is padded rather than waited for.
//
// The COM vtables are hand-written with the exact MinGW dsound.h slot order
// (IDirectSound at :575, IDirectSoundBuffer at :686); unused slots stay as
// typed placeholders. The C prototypes for the Win32/DSound/WINMM symbols come
// from <windows.h>, <dsound.h>, and <mmsystem.h>; Z98 emits no extern
// prototypes. No static DSOUND.DLL import is produced: dsound.dll is loaded
// with LoadLibraryA/GetProcAddress.
//
// State lives only in std_dsound.zig's one module-scope DsoundState; this PAL is
// stateless and every function receives the state pointer.

@cInclude("<windows.h>");
@cInclude("<dsound.h>");
@cInclude("<mmsystem.h>");

// --- constants -------------------------------------------------------------
const DSSCL_PRIORITY: u32 = 2;
const DSBCAPS_GLOBALFOCUS: u32 = 0x00008000;
const DSBCAPS_GETCURRENTPOSITION2: u32 = 0x00010000;
const DSBPLAY_LOOPING: u32 = 0x00000001;
const S_OK: u32 = 0;
const WAVE_FORMAT_PCM: u16 = 1;
const WAVE_MAPPER: u32 = 0xFFFFFFFF;
const CALLBACK_NULL: u32 = 0;
const WHDR_DONE: u32 = 0x00000001;

const NBUF: usize = 2;
const FRAMES: u32 = 2048;
const BUF_CAP: usize = 8192;
const PEND_CAP: usize = NBUF * BUF_CAP;
const FRAME_MASK: u32 = 2047;

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

fn isNull(p: *void) bool {
    return @ptrToInt(p) == 0;
}

fn copyCstr(s: []const u8, out: []u8) void {
    var n: usize = s.len;
    if (n >= out.len) n = out.len - 1;
    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = s[i];
    out[n] = 0;
}

// --- Win32 / DirectSound struct mirrors ------------------------------------
const Guid = struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

const WaveFormatEx = struct {
    wFormatTag: u16,
    nChannels: u16,
    nSamplesPerSec: u32,
    nAvgBytesPerSec: u32,
    nBlockAlign: u16,
    wBitsPerSample: u16,
    cbSize: u16,
};

// DSBUFFERDESC with the DS7+ guid3DAlgorithm tail (MinGW default version):
// five DWORD/pointer fields plus a 16-byte GUID = 36 bytes.
const DsBufferDesc = struct {
    dwSize: u32,
    dwFlags: u32,
    dwBufferBytes: u32,
    dwReserved: u32,
    lpwfxFormat: *void,
    guid3DAlgorithm: Guid,
};

const WaveHdr = struct {
    lpData: [*]u8,
    dwBufferLength: u32,
    dwBytesRecorded: u32,
    dwUser: u32,
    dwFlags: u32,
    dwLoops: u32,
    lpNext: *void,
    reserved: u32,
};

fn zeroGuid() Guid {
    return Guid{
        .data1 = 0,
        .data2 = 0,
        .data3 = 0,
        .data4 = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };
}

// --- COM vtables (exact dsound.h slot order) -------------------------------
const DsVtbl = struct {
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
    AddRef: extern "stdcall" fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    CreateSoundBuffer: extern "stdcall" fn(iface: *void, desc: *void, out: **void, outer: *void) u32,
    GetCaps: extern "stdcall" fn() void,
    DuplicateSoundBuffer: extern "stdcall" fn() void,
    SetCooperativeLevel: extern "stdcall" fn(iface: *void, hwnd: *void, level: u32) u32,
    Compact: extern "stdcall" fn() void,
    GetSpeakerConfig: extern "stdcall" fn() void,
    SetSpeakerConfig: extern "stdcall" fn() void,
    Initialize: extern "stdcall" fn() void,
};

const BufVtbl = struct {
    QueryInterface: extern "stdcall" fn(iface: *void, riid: *const void, out: **void) u32,
    AddRef: extern "stdcall" fn() void,
    Release: extern "stdcall" fn(iface: *void) u32,
    GetCaps: extern "stdcall" fn() void,
    GetCurrentPosition: extern "stdcall" fn(iface: *void, play: *u32, write: *u32) u32,
    GetFormat: extern "stdcall" fn() void,
    GetVolume: extern "stdcall" fn() void,
    GetPan: extern "stdcall" fn() void,
    GetFrequency: extern "stdcall" fn() void,
    GetStatus: extern "stdcall" fn() void,
    Initialize: extern "stdcall" fn() void,
    Lock: extern "stdcall" fn(iface: *void, offset: u32, bytes: u32, ptr1: **void, bytes1: *u32, ptr2: **void, bytes2: *u32, flags: u32) u32,
    Play: extern "stdcall" fn(iface: *void, r1: u32, r2: u32, flags: u32) u32,
    SetCurrentPosition: extern "stdcall" fn() void,
    SetFormat: extern "stdcall" fn() void,
    SetVolume: extern "stdcall" fn() void,
    SetPan: extern "stdcall" fn() void,
    SetFrequency: extern "stdcall" fn() void,
    Stop: extern "stdcall" fn(iface: *void) u32,
    Unlock: extern "stdcall" fn(iface: *void, ptr1: *void, bytes1: u32, ptr2: *void, bytes2: u32) u32,
    Restore: extern "stdcall" fn(iface: *void) u32,
};

const DsObj = struct { vtbl: *const DsVtbl };
const BufObj = struct { vtbl: *const BufVtbl };

fn dsVtbl(p: *void) *const DsVtbl {
    const o: *const DsObj = @ptrCast(*const DsObj, p);
    return o.vtbl;
}

fn bufVtbl(p: *void) *const BufVtbl {
    const o: *const BufObj = @ptrCast(*const BufObj, p);
    return o.vtbl;
}

// --- external Win32 / DirectSound / WINMM symbols --------------------------
const DirectSoundCreateFn = extern "stdcall" fn(lpGuid: *void, out: **void, outer: *void) u32;
pub extern "stdcall" fn LoadLibraryA(name: [*]const u8) *void;
pub extern "stdcall" fn GetProcAddress(mod: *void, name: [*]const u8) *void;
pub extern "stdcall" fn FreeLibrary(mod: *void) i32;

pub extern "stdcall" fn QueryPerformanceCounter(counter: *i64) i32;
pub extern "stdcall" fn QueryPerformanceFrequency(freq: *i64) i32;

pub extern "stdcall" fn waveOutOpen(phwo: *void, uDeviceID: u32, pwfx: *void, dwCallback: u32, dwInstance: u32, fdwOpen: u32) u32;
pub extern "stdcall" fn waveOutPrepareHeader(hwo: *void, pwh: *void, cbwh: u32) u32;
pub extern "stdcall" fn waveOutWrite(hwo: *void, pwh: *void, cbwh: u32) u32;
pub extern "stdcall" fn waveOutUnprepareHeader(hwo: *void, pwh: *void, cbwh: u32) u32;
pub extern "stdcall" fn waveOutReset(hwo: *void) u32;
pub extern "stdcall" fn waveOutClose(hwo: *void) u32;

// --- state -----------------------------------------------------------------
pub const State = struct {
    backend: u8,
    hwnd: *void,
    rate: u32,
    channels: u32,
    block_align: u32,
    buf_bytes: u32,
    ds_lib: *void,
    ds_create: *void,
    ds: *void,
    dsbuf: *void,
    write_cursor: u32,
    last_play: u32,
    queued_frames: u32,
    qpc_freq: i64,
    last_qpc: i64,
    hwo: *void,
    wave_bufs: [NBUF * BUF_CAP]u8,
    wave_hdrs: [NBUF]WaveHdr,
    wave_queued: [NBUF]bool,
    fill_idx: u32,
    fill_len: u32,
    wave_pending: [PEND_CAP]u8,
    pending_len: u32,
};

// --- small helpers ---------------------------------------------------------
fn zeroRegion(p: *void, bytes: u32) void {
    if (isNull(p)) return;
    const base: [*]u8 = @ptrCast([*]u8, p);
    const n: usize = @intCast(usize, bytes);
    var i: usize = 0;
    while (i < n) : (i += 1) base[i] = 0;
}

fn copyRegion(p: *void, bytes: u32, src: [*]const u8, off: *usize) void {
    const base: [*]u8 = @ptrCast([*]u8, p);
    const n: usize = @intCast(usize, bytes);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        base[i] = src[off.*];
        off.* += 1;
    }
}

fn hdrDone(h: *WaveHdr) bool {
    var f: *volatile u32 = @ptrCast(*volatile u32, &h.dwFlags);
    return (f.* & WHDR_DONE) != 0;
}

fn makeFormat(st: *State) WaveFormatEx {
    var wfx = WaveFormatEx{
        .wFormatTag = 0,
        .nChannels = 0,
        .nSamplesPerSec = 0,
        .nAvgBytesPerSec = 0,
        .nBlockAlign = 0,
        .wBitsPerSample = 0,
        .cbSize = 0,
    };
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = @intCast(u16, st.channels);
    wfx.nSamplesPerSec = st.rate;
    wfx.nAvgBytesPerSec = st.rate * st.channels * 2;
    wfx.nBlockAlign = @intCast(u16, st.block_align);
    wfx.wBitsPerSample = 16;
    wfx.cbSize = 0;
    return wfx;
}

// --- DirectSound resources -------------------------------------------------
fn releaseDsBuffer(st: *State) void {
    if (!isNull(st.dsbuf)) {
        _ = bufVtbl(st.dsbuf).Stop(st.dsbuf);
        _ = bufVtbl(st.dsbuf).Release(st.dsbuf);
    }
    st.dsbuf = nullVoid();
}

fn releaseDs(st: *State) void {
    releaseDsBuffer(st);
    if (!isNull(st.ds)) {
        _ = dsVtbl(st.ds).Release(st.ds);
    }
    st.ds = nullVoid();
    if (!isNull(st.ds_lib)) {
        _ = FreeLibrary(st.ds_lib);
    }
    st.ds_lib = nullVoid();
    st.ds_create = nullVoid();
}

fn loadDs(st: *State) bool {
    var dll_name: [32]u8 = undefined;
    copyCstr("dsound.dll", dll_name[0..]);
    const lib = LoadLibraryA(@ptrCast([*]const u8, &dll_name[0]));
    if (isNull(lib)) return false;
    st.ds_lib = lib;
    var fn_name: [32]u8 = undefined;
    copyCstr("DirectSoundCreate", fn_name[0..]);
    const proc = GetProcAddress(lib, @ptrCast([*]const u8, &fn_name[0]));
    if (isNull(proc)) {
        releaseDs(st);
        return false;
    }
    st.ds_create = proc;
    return true;
}

fn zeroDsRange(st: *State, offset: u32, bytes: u32) bool {
    var p1: *void = nullVoid();
    var b1: u32 = 0;
    var p2: *void = nullVoid();
    var b2: u32 = 0;
    var hr = bufVtbl(st.dsbuf).Lock(st.dsbuf, offset, bytes, &p1, &b1, &p2, &b2, 0);
    if (hr != S_OK) return false;
    zeroRegion(p1, b1);
    zeroRegion(p2, b2);
    hr = bufVtbl(st.dsbuf).Unlock(st.dsbuf, p1, b1, p2, b2);
    return hr == S_OK;
}

fn prefillSilence(st: *State) bool {
    return zeroDsRange(st, 0, st.buf_bytes);
}

fn tryDs(st: *State, hwnd: *void) u8 {
    if (!loadDs(st)) return 1;
    const create: DirectSoundCreateFn = @ptrCast(DirectSoundCreateFn, st.ds_create);
    var ds_raw: *void = nullVoid();
    var hr = create(nullVoid(), &ds_raw, nullVoid());
    if (hr != S_OK or isNull(ds_raw)) {
        releaseDs(st);
        return 1;
    }
    st.ds = ds_raw;
    hr = dsVtbl(st.ds).SetCooperativeLevel(st.ds, hwnd, DSSCL_PRIORITY);
    if (hr != S_OK) {
        releaseDs(st);
        return 1;
    }

    var wfx = makeFormat(st);
    var desc = DsBufferDesc{
        .dwSize = @intCast(u32, @sizeOf(DsBufferDesc)),
        .dwFlags = DSBCAPS_GETCURRENTPOSITION2 | DSBCAPS_GLOBALFOCUS,
        .dwBufferBytes = st.buf_bytes,
        .dwReserved = 0,
        .lpwfxFormat = @ptrCast(*void, &wfx),
        .guid3DAlgorithm = zeroGuid(),
    };
    var buf_raw: *void = nullVoid();
    hr = dsVtbl(st.ds).CreateSoundBuffer(st.ds, @ptrCast(*void, &desc), &buf_raw, nullVoid());
    if (hr != S_OK or isNull(buf_raw)) {
        releaseDs(st);
        return 2;
    }
    st.dsbuf = buf_raw;
    if (!prefillSilence(st)) {
        releaseDs(st);
        return 2;
    }
    hr = bufVtbl(st.dsbuf).Play(st.dsbuf, 0, 0, DSBPLAY_LOOPING);
    if (hr != S_OK) {
        releaseDs(st);
        return 2;
    }

    var play: u32 = 0;
    var wpos: u32 = 0;
    if (bufVtbl(st.dsbuf).GetCurrentPosition(st.dsbuf, &play, &wpos) == S_OK) {
        st.last_play = play / st.block_align;
    } else {
        st.last_play = 0;
    }
    st.write_cursor = st.last_play & FRAME_MASK;
    st.queued_frames = 0;
    st.qpc_freq = 0;
    st.last_qpc = 0;
    var freq: i64 = 0;
    if (QueryPerformanceFrequency(&freq) != 0 and freq > 0) {
        st.qpc_freq = freq;
        var counter: i64 = 0;
        if (QueryPerformanceCounter(&counter) != 0) st.last_qpc = counter;
    }
    st.backend = 1;
    return 0;
}

// --- waveOut resources -----------------------------------------------------
fn releaseWave(st: *State) void {
    if (!isNull(st.hwo)) {
        _ = waveOutReset(st.hwo);
        var i: usize = 0;
        while (i < NBUF) : (i += 1) {
            if (st.wave_queued[i]) {
                _ = waveOutUnprepareHeader(st.hwo, @ptrCast(*void, &st.wave_hdrs[i]), @intCast(u32, @sizeOf(WaveHdr)));
                st.wave_queued[i] = false;
            }
        }
        _ = waveOutClose(st.hwo);
    }
    st.hwo = nullVoid();
    st.fill_idx = 0;
    st.fill_len = 0;
    st.pending_len = 0;
    st.backend = 0;
}

fn initWaveHeaders(st: *State) void {
    var i: usize = 0;
    while (i < NBUF) : (i += 1) {
        st.wave_hdrs[i] = WaveHdr{
            .lpData = @ptrCast([*]u8, &st.wave_bufs[i * BUF_CAP]),
            .dwBufferLength = 0,
            .dwBytesRecorded = 0,
            .dwUser = 0,
            .dwFlags = 0,
            .dwLoops = 0,
            .lpNext = nullVoid(),
            .reserved = 0,
        };
        st.wave_queued[i] = false;
    }
    st.fill_idx = 0;
    st.fill_len = 0;
    st.pending_len = 0;
}

fn submitWave(st: *State) bool {
    const idx: usize = @intCast(usize, st.fill_idx);
    const h: *WaveHdr = &st.wave_hdrs[idx];
    const base: usize = idx * BUF_CAP;
    const length: usize = @intCast(usize, st.buf_bytes);
    // Silence-fill the unfilled tail: a buffer that is not full is padded to
    // its full length rather than blocking the writer for more samples.
    var i: usize = @intCast(usize, st.fill_len);
    while (i < length) : (i += 1) st.wave_bufs[base + i] = 0;
    h.dwBufferLength = st.buf_bytes;
    h.dwFlags = 0;
    const hdr_size: u32 = @intCast(u32, @sizeOf(WaveHdr));
    var rc = waveOutPrepareHeader(st.hwo, @ptrCast(*void, h), hdr_size);
    if (rc != 0) return false;
    rc = waveOutWrite(st.hwo, @ptrCast(*void, h), hdr_size);
    if (rc != 0) {
        _ = waveOutUnprepareHeader(st.hwo, @ptrCast(*void, h), hdr_size);
        return false;
    }
    st.wave_queued[idx] = true;
    st.fill_idx = (st.fill_idx + 1) % @intCast(u32, NBUF);
    st.fill_len = 0;
    return true;
}

// Move bytes from the bounded pending area into the current free device
// buffer. The caller guarantees fill_idx is not queued. The device buffer is
// submitted immediately (submitWave silence-pads a short tail); any pending
// remainder stays at the front for the next freed buffer.
fn flushPending(st: *State) bool {
    if (st.pending_len == 0) return true;
    const idx: usize = @intCast(usize, st.fill_idx);
    const base: usize = idx * BUF_CAP;
    const limit: usize = @intCast(usize, st.buf_bytes);
    var fill: usize = @intCast(usize, st.fill_len);
    const space: usize = limit - fill;
    if (space == 0) return submitWave(st);
    const plen: usize = @intCast(usize, st.pending_len);
    var take: usize = plen;
    if (take > space) take = space;
    var i: usize = 0;
    while (i < take) : (i += 1) st.wave_bufs[base + fill + i] = st.wave_pending[i];
    const remain: usize = plen - take;
    i = 0;
    while (i < remain) : (i += 1) st.wave_pending[i] = st.wave_pending[take + i];
    st.pending_len = @intCast(u32, remain);
    fill += take;
    st.fill_len = @intCast(u32, fill);
    // Submit now even when the tail is short: submitWave silence-pads the rest,
    // so an unready/partial buffer is filled with silence rather than blocking.
    return submitWave(st);
}

// Append offered bytes to the bounded pending area when both device buffers are
// busy. Pending preserves every accepted sample; a sustained overload returns
// short (the caller keeps the rest) rather than dropping copied samples.
fn appendPending(st: *State, src: [*]const u8, off: usize, total: usize) usize {
    const used: usize = @intCast(usize, st.pending_len);
    var space: usize = PEND_CAP - used;
    if (space == 0) return 0;
    var take: usize = total - off;
    if (take > space) take = space;
    var i: usize = 0;
    while (i < take) : (i += 1) st.wave_pending[used + i] = src[off + i];
    st.pending_len = @intCast(u32, used + take);
    return take;
}

fn tryWave(st: *State) bool {
    var wfx = makeFormat(st);
    var rc = waveOutOpen(@ptrCast(*void, &st.hwo), WAVE_MAPPER, @ptrCast(*void, &wfx), CALLBACK_NULL, 0, 0);
    if (rc != 0 or isNull(st.hwo)) {
        st.hwo = nullVoid();
        return false;
    }
    var i: usize = 0;
    while (i < NBUF * BUF_CAP) : (i += 1) st.wave_bufs[i] = 0;
    initWaveHeaders(st);
    st.backend = 2;
    return true;
}

// --- open/close ------------------------------------------------------------
pub fn open(window: *void, sample_rate: u32, channels: u16, st: *State) u8 {
    st.backend = 0;
    st.hwnd = window;
    st.rate = sample_rate;
    st.channels = @intCast(u32, channels);
    st.block_align = st.channels * 2;
    st.buf_bytes = FRAMES * st.block_align;
    st.ds_lib = nullVoid();
    st.ds_create = nullVoid();
    st.ds = nullVoid();
    st.dsbuf = nullVoid();
    st.write_cursor = 0;
    st.last_play = 0;
    st.queued_frames = 0;
    st.qpc_freq = 0;
    st.last_qpc = 0;
    st.hwo = nullVoid();
    st.fill_idx = 0;
    st.fill_len = 0;
    st.pending_len = 0;

    if (sample_rate < 8000 or sample_rate > 192000) return 1;
    if (channels != 1 and channels != 2) return 1;
    if (st.buf_bytes > @intCast(u32, NBUF * BUF_CAP)) return 1;

    const ds_rc = tryDs(st, window);
    if (ds_rc == 0) return 0;
    releaseDs(st);
    if (tryWave(st)) return 0;
    if (ds_rc == 2) return 2;
    return 1;
}

pub fn close(st: *State) void {
    if (st.backend == 1) {
        releaseDs(st);
    } else if (st.backend == 2) {
        releaseWave(st);
    }
    st.backend = 0;
}

// --- writes ----------------------------------------------------------------
fn writeDs(st: *State, samples: []const i16) usize {
    if (isNull(st.dsbuf)) return 0;
    const ch: usize = @intCast(usize, st.channels);
    const usable: usize = samples.len - (samples.len % ch);
    if (usable == 0) return 0;

    var play: u32 = 0;
    var wpos: u32 = 0;
    const hr = bufVtbl(st.dsbuf).GetCurrentPosition(st.dsbuf, &play, &wpos);
    if (hr != S_OK) {
        _ = bufVtbl(st.dsbuf).Restore(st.dsbuf);
        return 0;
    }
    const play_frames: u32 = play / st.block_align;
    // Positions alone only give one modulo lap. Use QPC to detect a stall
    // longer than the whole buffer: then the queue is definitely drained, even
    // if the play cursor came back to a similar position after several laps.
    var long_stall: bool = false;
    if (st.qpc_freq > 0) {
        var now: i64 = 0;
        if (QueryPerformanceCounter(&now) != 0) {
            var dt: i64 = 0;
            if (now >= st.last_qpc) dt = now - st.last_qpc;
            if (dt > 0) {
                const lhs: i64 = dt * @intCast(i64, st.rate);
                const rhs: i64 = @intCast(i64, FRAMES) * st.qpc_freq;
                if (lhs >= rhs) long_stall = true;
            }
            st.last_qpc = now;
        }
    }
    var delta: u32 = 0;
    if (play_frames >= st.last_play) {
        delta = play_frames - st.last_play;
    } else {
        delta = (FRAMES - st.last_play) + play_frames;
    }
    if (long_stall or delta >= st.queued_frames) {
        // Queue drained (or the play cursor passed it). Silence-fill the whole
        // ring instead of blocking or rewinding; this covers the actual missed
        // gap and any number of full laps in a long stall. Then restart at the
        // play cursor.
        _ = zeroDsRange(st, 0, st.buf_bytes);
        st.queued_frames = 0;
        st.write_cursor = play_frames & FRAME_MASK;
    } else {
        st.queued_frames -= delta;
    }
    st.last_play = play_frames;

    const free: u32 = FRAMES - st.queued_frames;
    if (free == 0) return 0;

    const want_samples: usize = usable / ch;
    var frames: u32 = @intCast(u32, want_samples);
    if (frames > free) frames = free;
    if (frames == 0) return 0;

    const offset: u32 = st.write_cursor * st.block_align;
    const bytes: u32 = frames * st.block_align;
    var p1: *void = nullVoid();
    var b1: u32 = 0;
    var p2: *void = nullVoid();
    var b2: u32 = 0;
    var lr = bufVtbl(st.dsbuf).Lock(st.dsbuf, offset, bytes, &p1, &b1, &p2, &b2, 0);
    if (lr != S_OK) {
        _ = bufVtbl(st.dsbuf).Restore(st.dsbuf);
        return 0;
    }
    const src: [*]const u8 = @ptrCast([*]const u8, samples.ptr);
    var off: usize = 0;
    copyRegion(p1, b1, src, &off);
    copyRegion(p2, b2, src, &off);
    const ur = bufVtbl(st.dsbuf).Unlock(st.dsbuf, p1, b1, p2, b2);
    if (ur != S_OK) return 0;

    const consumed_frames: usize = @intCast(usize, frames);
    st.write_cursor = (st.write_cursor + frames) & FRAME_MASK;
    st.queued_frames += frames;
    return consumed_frames * ch;
}

fn writeWave(st: *State, samples: []const i16) usize {
    if (isNull(st.hwo)) return 0;
    if (samples.len == 0) return 0;
    const src: [*]const u8 = @ptrCast([*]const u8, samples.ptr);
    const total_bytes: usize = samples.len * 2;
    const limit: usize = @intCast(usize, st.buf_bytes);
    var off: usize = 0;
    var consumed_bytes: usize = 0;

    while (off < total_bytes) {
        const idx: usize = @intCast(usize, st.fill_idx);
        if (st.wave_queued[idx]) {
            const h: *WaveHdr = &st.wave_hdrs[idx];
            // The device still owns this buffer: do not reuse it and do not
            // block. Any new samples are staged in pending below.
            if (!hdrDone(h)) break;
            _ = waveOutUnprepareHeader(st.hwo, @ptrCast(*void, h), @intCast(u32, @sizeOf(WaveHdr)));
            st.wave_queued[idx] = false;
            st.fill_len = 0;
        }
        if (st.pending_len > 0) {
            if (!flushPending(st)) break;
            continue;
        }
        var fill: usize = @intCast(usize, st.fill_len);
        var space: usize = limit - fill;
        if (space == 0) {
            if (!submitWave(st)) break;
            continue;
        }
        var take: usize = total_bytes - off;
        if (take > space) take = space;
        const base: usize = idx * BUF_CAP;
        var i: usize = 0;
        while (i < take) : (i += 1) {
            st.wave_bufs[base + fill + i] = src[off + i];
        }
        fill += take;
        off += take;
        consumed_bytes += take;
        st.fill_len = @intCast(u32, fill);
        if (fill >= limit) {
            if (!submitWave(st)) break;
        }
    }
    if (off < total_bytes) {
        const take = appendPending(st, src, off, total_bytes);
        off += take;
        consumed_bytes += take;
    }
    return consumed_bytes / 2;
}

pub fn write(st: *State, samples: []const i16) usize {
    if (st.backend == 1) return writeDs(st, samples);
    if (st.backend == 2) return writeWave(st, samples);
    return 0;
}

pub fn queued(st: *State) usize {
    if (st.backend == 1) {
        return @intCast(usize, st.queued_frames) * @intCast(usize, st.channels);
    }
    if (st.backend == 2) {
        var bytes: usize = @intCast(usize, st.fill_len) + @intCast(usize, st.pending_len);
        var i: usize = 0;
        while (i < NBUF) : (i += 1) {
            if (st.wave_queued[i]) {
                bytes += @intCast(usize, st.wave_hdrs[i].dwBufferLength);
            }
        }
        return bytes / 2;
    }
    return 0;
}
