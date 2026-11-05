#!/usr/bin/env python3
"""Tiny CGI front end for `git http-backend` (z9git Task 8 tier).

usage: git_http_server.py <project-root> <port-file>

Binds 127.0.0.1 on an ephemeral port, writes the port number to <port-file>,
and serves GET/POST requests by invoking `git http-backend` with the CGI
environment. Response bodies are buffered and returned with a Content-Length
(the fixture repositories are small); git remains the only smart-HTTP server
implementation under test.
"""

import http.server
import os
import subprocess
import sys
import urllib.parse


def main() -> int:
    root = sys.argv[1]
    port_file = sys.argv[2]

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_GET(self) -> None:
            self.handle_git()

        def do_POST(self) -> None:
            self.handle_git()

        def log_message(self, fmt, *args) -> None:
            pass

        def handle_git(self) -> None:
            split = urllib.parse.urlsplit(self.path)
            body = b""
            if self.command == "POST":
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                except ValueError:
                    length = 0
                body = self.rfile.read(length)

            env = os.environ.copy()
            env.update(
                {
                    "GIT_PROJECT_ROOT": root,
                    "GIT_HTTP_EXPORT_ALL": "1",
                    "REQUEST_METHOD": self.command,
                    "PATH_INFO": urllib.parse.unquote(split.path),
                    "QUERY_STRING": split.query,
                    "CONTENT_TYPE": self.headers.get("Content-Type", ""),
                    "CONTENT_LENGTH": str(len(body)),
                    "REMOTE_ADDR": "127.0.0.1",
                    "SERVER_NAME": "127.0.0.1",
                    "SERVER_PORT": str(self.server.server_address[1]),
                    "SERVER_PROTOCOL": "HTTP/1.1",
                    "GATEWAY_INTERFACE": "CGI/1.1",
                }
            )
            proc = subprocess.run(
                ["git", "http-backend"],
                input=body,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            out = proc.stdout
            sep = out.find(b"\r\n\r\n")
            sep_len = 4
            if sep < 0:
                sep = out.find(b"\n\n")
                sep_len = 2
            if sep < 0:
                self.send_error(500, "missing CGI headers")
                return
            header_blob = out[:sep]
            response_body = out[sep + sep_len :]

            status = 200
            headers = []
            for line in header_blob.splitlines():
                if b":" not in line:
                    continue
                key, value = line.split(b":", 1)
                name = key.decode("latin-1")
                val = value.strip().decode("latin-1")
                if name.lower() == "status":
                    try:
                        status = int(val.split()[0])
                    except (ValueError, IndexError):
                        status = 500
                else:
                    headers.append((name, val))

            self.send_response(status)
            for name, val in headers:
                self.send_header(name, val)
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            if response_body:
                self.wfile.write(response_body)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(port_file, "w", encoding="ascii") as fh:
        fh.write(str(server.server_address[1]))
        fh.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
