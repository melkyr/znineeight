# HTTP — `std_http`

| | |
|---|---|
| **Modules** | `std_http` |
| **Layers** | `L5` — HTTP/1.1 client over a caller-supplied transport (plain TCP or TLS) |
| **Import (by path)** | `const std_http = @import("std_http");` |

## Module overview

`std_http` is a minimal HTTP/1.1 client. The pure helpers (`parseUrl`,
`percentEncode`, `parseResponse`) do no I/O; the network entry points
(`get`, `post`) open a plain-TCP socket through `std.net`, while the `*Over`
entry points drive a caller-supplied `HttpTransport` so the same code runs over
TLS (`std_tls`) or a mock in tests.

The transfer contract is deliberately simple. Every request uses HTTP/1.1 and
sends `Connection: close`; there is no keep-alive, no `Host` virtual hosting
beyond the URL authority, and no chunked **request** body (the POST body is
length-delimited). Response bodies are decoded from `Content-Length`, chunked
transfer-encoding, or connection close. The buffered paths cap the header block
at 8 KiB and the body at 1 MiB; the streaming POST/GET paths route de-chunked
body bytes to a caller sink through a fixed ~1 MiB buffer and are not subject
to the 1 MiB whole-body cap. GET can carry caller headers (including `Range`)
for static servers, and a POST body can come from a streaming `RequestSource`
instead of a contiguous slice.

Everything allocated comes from the caller's arena (R1). The module's one error
set is `HttpError` (R2); transport callbacks may return their own errors, which
propagate.

## Quick start

```zig
const std = @import("std");
const std_http = @import("std_http");

var backing: [16384]u8 = undefined;

pub fn main() !void {
    var arena = std.arena.init(backing[0..]);
    const resp = std_http.get(&arena, "http://example.com/", 5000) catch |e| {
        if (e == error.Timeout) std.io.write("timeout\n");
        return;
    };
    std.io.write(resp.body);
    std.arena.reset(&arena);
}
```

## API

### `Url`

**Purpose** — the parsed components of an `http://` URL.

**When to use** — as the return of `parseUrl`, or when building a request by
hand.

**Signature** — `pub const Url = struct { host: []const u8, port: u16, path: []const u8, query: []const u8 };`

**Parameters** (fields)
- `host` — the authority host (no scheme or port).
- `port` — the explicit port, or `80` when the URL omits it.
- `path` — the path beginning with `/` (`/` when the URL has no path).
- `query` — the text after `?` (empty when absent).

**Returns** — a plain value; its slices alias the input URL.

**Errors** — none.

**Gotchas** — `parseUrl` accepts only the `http` scheme; the `*Over` transport
paths also accept `https` (the caller supplies the TLS transport). Keep the URL
bytes alive while the returned slices are used.

### `Header`

**Purpose** — one response header name/value pair.

**Signature** — `pub const Header = struct { name: []const u8, value: []const u8 };`

**Parameters** (fields)
- `name` — the header name as received.
- `value` — the value with leading/trailing spaces trimmed.

**Returns** — a plain value; both slices belong to the response's backing
storage (the raw input for `parseResponse`, the arena copy for the `*Over`
paths).

**Errors** — none.

### `Response`

**Purpose** — a decoded HTTP response.

**Signature** — `pub const Response = struct { status: u16, headers: []Header, body: []u8 };`

**Parameters** (fields)
- `status` — the three-digit status code.
- `headers` — arena-owned header array.
- `body` — the decoded body (`[]u8`; empty for the streaming POST head).

**Returns** — a plain value.

**Errors** — none.

### `HttpError`

**Purpose** — the module's single error set.

**Signature** — `pub const HttpError = error{ BadUrl, DnsFailed, ConnectFailed, Timeout, BadResponse, BadHeader, TooLarge, OutOfMemory };`

**Gotchas** — `BadHeader` is produced by a caller-supplied POST
`content_type`/`accept` or an `httpGetHeadersOver`/`httpGetStreamOver` header
name/value containing CR, LF, or NUL. `TooLarge` covers the 8 KiB header cap,
the 1 MiB buffered-body cap, and oversized streaming lengths.

### `parseUrl`

**Purpose** — parses an absolute `http://` URL into a `Url`.

**When to use** — to inspect a URL or build a request without opening a socket.
The network paths parse defensively themselves.

**Signature** — `pub fn parseUrl(url: []const u8) HttpError!Url`

**Parameters**
- `url` — `http://host[:port][/path][?query]`. The authority must be non-empty;
  the port must be all digits and at most 65535.

**Returns** — a `Url` whose slices alias `url`; the default port is 80.

**Errors**
- `error.BadUrl` — missing `://`, a scheme other than `http`, an empty host, a
  non-numeric or out-of-range port.

**Example**
```zig
const u = try std_http.parseUrl("http://example.com:8080/a?q=1");
// u.host == "example.com", u.port == 8080, u.path == "/a", u.query == "q=1"
```

**Gotchas** — no userinfo, IPv6 literal, fragment, or `https` handling here.

### `percentEncode`

**Purpose** — percent-encodes bytes for a URL component, preserving the RFC 3986
unreserved characters.

**When to use** — when composing a query or path component from user bytes; the
network paths do not encode for you.

**Signature** — `pub fn percentEncode(arena: *std.arena.Arena, bytes: []const u8) HttpError![]u8`

**Parameters**
- `arena` — allocation source; the call reserves `bytes.len * 3` bytes and
  returns a shorter slice.
- `bytes` — raw bytes to encode.

**Returns** — a slice in the arena. `A-Z a-z 0-9 . _ ~ -` are emitted as-is;
every other byte becomes `%XX` with uppercase hex.

**Errors** — `error.OutOfMemory` when the arena cannot supply `bytes.len * 3`
bytes.

**Example**
```zig
const q = try std_http.percentEncode(&arena, "a b/c");
// q == "a%20b%2Fc"
```

**Gotchas** — the arena advances by the full `3 * len` reservation even though
the returned slice may be shorter.

### `parseResponse`

**Purpose** — parses a complete raw HTTP response (status line, headers, body)
from a byte slice.

**When to use** — in unit tests and when you already have the whole response
bytes. The transport paths use their own streaming reader because they must not
require the whole response in memory.

**Signature** — `pub fn parseResponse(arena: *std.arena.Arena, raw: []const u8) HttpError!Response`

**Parameters**
- `arena` — allocation source for the header array and body copy.
- `raw` — status line + `\r\n` + headers + `\r\n\r\n` + body.

**Returns** — a `Response`. Header name/value slices alias `raw`; the body is
copied into the arena.

**Errors**
- `error.BadResponse` — a missing header terminator/status line, malformed
  header line, invalid status digits, or `Transfer-Encoding: chunked` (the pure
  parser rejects chunked).
- `error.TooLarge` — header block above 8 KiB, or a body above 1 MiB.
- `error.OutOfMemory` — arena exhaustion.

**Example**
```zig
const resp = try std_http.parseResponse(&arena, raw);
std.io.write(resp.body);
```

**Gotchas** — with `Content-Length` the body is exactly that many bytes; without
it the body is the remaining input (close-delimited). Keep `raw` alive while
using `resp.headers`. The `*Over` transport paths **do** decode chunked bodies;
only this pure parser rejects them.

### `HttpTransport`

**Purpose** — the caller-supplied byte transport used by the `*Over` entry
points.

**Signature** — `pub const HttpTransport = struct { state: *void, read_fn: fn (*void, []u8) !usize, write_fn: fn (*void, []const u8) !usize, close_fn: fn (*void) void };`

**Parameters** (fields)
- `state` — opaque pointer handed back to every callback.
- `read_fn` — reads up to the slice length; returns `0` at EOF.
- `write_fn` — writes the slice; returns the bytes written (0 is an error).
- `close_fn` — releases the connection; the module calls it exactly once.

**Returns** — a plain value.

**Gotchas** — the module writes the whole request/body before reading, always
closes (including on error), and treats a short write as a failure it retries
until the slice is consumed.

### `ResponseSink`

**Purpose** — the destination callback for a streaming response body.

**Signature** — `pub const ResponseSink = struct { state: *void, write_fn: fn (*void, []const u8) HttpError!void };`

**Parameters** (fields)
- `state` — opaque pointer passed to `write_fn`.
- `write_fn` — consumes one bounded body slice; returning an error aborts the
  transfer.

**Returns** — a plain value.

**Gotchas** — slices are valid only for the duration of the call and never
exceed the fixed ~1 MiB stream buffer; copy what you need to keep.

### `httpGetOver`

**Purpose** — performs a GET over a caller-supplied transport and buffers the
whole response.

**When to use** — HTTPS (wrap the connection in `std_tls`), mocked tests, or any
transport that is not a plain `std.net` socket.

**Signature** — `pub fn httpGetOver(arena: *std.arena.Arena, t: *HttpTransport, url: []const u8, out: *Response) !void`

**Parameters**
- `arena` — source for the request buffer, headers, and body.
- `t` — the transport; it is closed before return.
- `url` — `http://` or `https://` URL.
- `out` — receives the response.

**Returns** — nothing; `out.*` holds the response.

**Errors** — `HttpError` members plus transport errors. `error.TooLarge` applies
to the 8 KiB header block and 1 MiB buffered body.

**Example**
```zig
var resp: std_http.Response = undefined;
try std_http.httpGetOver(&arena, &transport, "https://example.com/", &resp);
```

**Gotchas** — the URL scheme selects the default port (80/443) but the module
does not itself add TLS; the transport must already be the right channel.

### `httpPostOver`

**Purpose** — performs a POST over a caller-supplied transport and buffers the
whole response.

**When to use** — form or API POSTs over TLS or a mock transport, where the
response fits the 1 MiB buffered cap.

**Signature** — `pub fn httpPostOver(arena: *std.arena.Arena, t: *HttpTransport, url: []const u8, body: []const u8, content_type: []const u8, accept: []const u8, out: *Response) !void`

**Parameters**
- `arena` — source for the request buffer, headers, and response body.
- `t` — the transport; closed before return.
- `url` — `http://` or `https://` URL.
- `body` — the complete request body; `Content-Length` is always sent.
- `content_type` — `Content-Type` value; an empty slice omits the header.
- `accept` — `Accept` value; an empty slice omits the header.
- `out` — receives the response.

**Returns** — nothing; `out.*` holds the response.

**Errors** — `HttpError` members plus transport errors. `error.BadHeader` when
`content_type`/`accept` contains CR, LF, or NUL; `error.TooLarge` for an
over-cap response.

**Example**
```zig
var resp: std_http.Response = undefined;
try std_http.httpPostOver(&arena, &transport, url, request[0..],
    "application/x-git-upload-pack-request", "application/x-git-upload-pack-result", &resp);
```

**Gotchas** — the request body is written immediately after the head; the
transport is closed on every path. For a response larger than 1 MiB use
`httpPostStreamOver`.

### `httpPostStreamOver`

**Purpose** — performs a POST and streams the de-chunked response body to a
`ResponseSink`, while returning the status and headers separately.

**When to use** — large or unbounded downloads (for example a Git pack result).
The buffered POST would reject these with `error.TooLarge`.

**Signature** — `pub fn httpPostStreamOver(arena: *std.arena.Arena, t: *HttpTransport, url: []const u8, body: []const u8, content_type: []const u8, accept: []const u8, sink: *ResponseSink, out_head: *Response) !void`

**Parameters**
- `arena` — source for the request buffer, headers, and the fixed ~1 MiB stream
  buffer.
- `t` — the transport; closed before return.
- `url` — `http://` or `https://` URL.
- `body` — the complete request body.
- `content_type` / `accept` — as for `httpPostOver` (empty omits the header).
- `sink` — receives body bytes in bounded chunks.
- `out_head` — receives the status and headers; its body is empty.

**Returns** — nothing; headers/status in `out_head`, body via `sink`.

**Errors** — `HttpError` members plus transport/sink errors. A malformed or
truncated body is `error.BadResponse`; oversize accounting is `error.TooLarge`.

**Example**
```zig
var head: std_http.Response = undefined;
try std_http.httpPostStreamOver(&arena, &transport, url, want[0..],
    "application/x-git-upload-pack-request", "application/x-git-upload-pack-result",
    &sink, &head);
```

**Gotchas** — the sink sees de-chunked body bytes only; chunk framing and
trailers are consumed internally. Body length is unbounded apart from the
32-bit chunk/`Content-Length` accounting and hardware. A sink error aborts the
transfer and propagates after the transport is closed.

### `RequestSource`

**Purpose** — a caller-supplied stream for a POST request body that is not
already materialized in memory.

**Signature** — `pub const RequestSource = struct { state: *void, read_fn: fn (*void, []u8) HttpError!usize };`

**Parameters** (fields)
- `state` — opaque pointer passed to `read_fn`.
- `read_fn` — fills up to the slice length with body bytes and returns the
  count; returns `0` at the declared end. Returning `0` before the declared
  `body_len`, or more than the slice length, is `error.BadResponse`.

**Gotchas** — the declared `body_len` is written as `Content-Length`, so the
source must produce exactly that many bytes; there is no chunked request body.

### `httpGetHeadersOver`

**Purpose** — a buffered GET with caller-supplied request headers, including
`Range` for a static/dumb HTTP server.

**When to use** — self-hosted static object servers where a byte range is
available; GitHub/GitLab smart HTTP is POST-based and does not use this path.

**Signature** — `pub fn httpGetHeadersOver(arena: *std.arena.Arena, t: *HttpTransport, url: []const u8, extra_headers: []const Header, out: *Response) !void`

**Parameters**
- `arena` — source for the request buffer, headers, and body.
- `t` — the transport; closed before return.
- `url` — `http://` or `https://` URL.
- `extra_headers` — additional request header lines, e.g.
  `Header{ .name = "Range", .value = "bytes=0-1023" }`. Empty values are sent
  as an empty header value; CR/LF/NUL in a name or value is `error.BadHeader`.
- `out` — receives the buffered response (1 MiB body cap).

**Errors** — `HttpError` members plus transport errors.

**Gotchas** — the header list is appended after `Connection: close`; duplicate
names are allowed (the server decides). `Host`/`Connection` are owned by the
module and cannot be overridden here.

### `httpGetStreamOver`

**Purpose** — performs a GET and streams the de-chunked response body to a
`ResponseSink`, while returning the status and headers separately.

**When to use** — a large static download over an `http://`/`https://`
transport where the body must not be buffered.

**Signature** — `pub fn httpGetStreamOver(arena: *std.arena.Arena, t: *HttpTransport, url: []const u8, extra_headers: []const Header, sink: *ResponseSink, out_head: *Response) !void`

**Parameters** — as `httpGetHeadersOver`, but the body goes to `sink` and
`out_head` receives the status/headers with an empty body. The fixed ~1 MiB
stream buffer comes from `arena`; the body length is unbounded apart from the
32-bit accounting and hardware.

**Errors** — `HttpError` members plus transport/sink errors. Truncated or
malformed chunk framing is `error.BadResponse`.

**Gotchas** — the sink sees de-chunked body bytes only; trailing headers are
consumed. The response `Content-Length`, when present, is the body byte count
(not the encoded chunk framing).

### `httpPostStreamBodyOver`

**Purpose** — a POST whose request body comes from a `RequestSource` in bounded
chunks, with the response streamed to a `ResponseSink`.

**When to use** — a body assembled from a writer/pipeline (for example a want
list built without a contiguous arena buffer) whose response is large.

**Signature** — `pub fn httpPostStreamBodyOver(arena: *std.arena.Arena, t: *HttpTransport, url: []const u8, body_len: usize, content_type: []const u8, accept: []const u8, body: *RequestSource, sink: *ResponseSink, out_head: *Response) !void`

**Parameters**
- `body_len` — exact `Content-Length` bytes the source will produce.
- `body` — the streaming body source.
- `content_type` / `accept` — as for `httpPostOver` (empty omits the header).
- `sink` / `out_head` — as for `httpPostStreamOver`.

**Errors** — `HttpError` members plus transport/sink errors. A source that
returns `0` early is `error.BadResponse`.

**Gotchas** — the source is read into a fixed 64 KiB stack buffer and written
straight to the transport; the request body itself is never buffered whole.

### `get`


**Purpose** — performs a plain-TCP HTTP GET with a timeout, following one
redirect.

**When to use** — a simple `http://` GET without TLS. For HTTPS use
`httpGetOver` with a `std_tls` transport.

**Signature** — `pub fn get(arena: *std.arena.Arena, url: []const u8, timeout_ms: u32) HttpError!Response`

**Parameters**
- `arena` — source for the request/response buffers and body.
- `url` — `http://` URL.
- `timeout_ms` — per-`select` timeout while connecting/reading.

**Returns** — the decoded response.

**Errors** — `BadUrl`, `DnsFailed`, `ConnectFailed`, `Timeout`, `BadResponse`,
`TooLarge`, `OutOfMemory`.

**Example**
```zig
const resp = try std_http.get(&arena, "http://example.com/", 5000);
```

**Gotchas** — only `http` is accepted by `parseUrl`; a 301/302/303/307 with a
`Location` is followed **once** (same method). The receive buffer is capped at
8 KiB headers + 1 MiB body + 4 bytes.

### `post`

**Purpose** — performs a plain-TCP HTTP POST with a timeout, following one
redirect.

**When to use** — a simple `http://` POST without TLS, with a response that fits
the 1 MiB buffered cap. For HTTPS use `httpPostOver`; for large responses use
`httpPostStreamOver`.

**Signature** — `pub fn post(arena: *std.arena.Arena, url: []const u8, body: []const u8, content_type: []const u8, accept: []const u8, timeout_ms: u32) HttpError!Response`

**Parameters**
- `arena` — source for the request/response buffers and body.
- `url` — `http://` URL.
- `body` — the complete request body.
- `content_type` / `accept` — as for `httpPostOver` (empty omits the header).
- `timeout_ms` — per-`select` timeout while connecting/reading.

**Returns** — the decoded response.

**Errors** — `HttpError` members; `error.BadHeader` is returned before a socket
is opened when a caller header value contains CR, LF, or NUL.

**Example**
```zig
const resp = try std_http.post(&arena, "http://example.com/api", form[0..],
    "application/x-www-form-urlencoded", "", 5000);
```

**Gotchas** — like `get`, this path is plain `http` only and follows one
redirect. The transport is always closed exactly once, including on validation
errors.

## See also

- [`tls.md`](tls.md) — the TLS record/handshake layer used to build an HTTPS
  `HttpTransport`.
- [`net.md`](net.md) — the TCP/UDP socket layer under `get`/`post`.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
