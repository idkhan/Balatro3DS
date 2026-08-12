#!/usr/bin/env python3
"""Serve a built CIA over the LAN and print a QR code for FBI's remote install.

    ./dev/server/serve.py                serve the newest CIA in dev/dist
    ./dev/server/serve.py --file x.cia   serve a specific file
    ./dev/server/serve.py --port 9000

On the 3DS: FBI -> Remote Install -> Scan QR Code, point it at the code in the
terminal or at http://<this machine>:<port>/ in a browser.

The console and this machine have to be on the same network, and macOS may ask
to allow incoming connections the first time.
"""

import argparse
import html
import http.server
import io
import os
import re
import socket
import socketserver
import subprocess
import sys
import threading
import time
import urllib.parse
import venv
from pathlib import Path

DEV_DIR = Path(__file__).resolve().parent.parent
DIST_DIR = DEV_DIR / "dist"
VENV_DIR = DEV_DIR / ".venv"
REPO_ROOT = DEV_DIR.parent


def ensure_segno():
    """Import segno, bootstrapping a repo-local venv on first run."""
    try:
        import segno  # noqa: F401
        return
    except ImportError:
        pass

    python = VENV_DIR / ("Scripts" if os.name == "nt" else "bin") / "python"
    if not python.exists():
        print(f"creating venv at {VENV_DIR}", file=sys.stderr)
        venv.EnvBuilder(with_pip=True).create(VENV_DIR)
        subprocess.check_call(
            [str(python), "-m", "pip", "install", "--quiet", "segno"]
        )

    if Path(sys.executable).resolve() == python.resolve():
        raise SystemExit("segno is still missing inside the venv")

    os.execv(str(python), [str(python), os.path.abspath(__file__), *sys.argv[1:]])


def lan_address() -> str:
    """Best guess at the address the 3DS can reach this machine on."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        probe.close()


def newest_cia() -> Path:
    candidates = sorted(
        DIST_DIR.glob("*.cia"), key=lambda p: p.stat().st_mtime, reverse=True
    )
    if not candidates:
        raise SystemExit(
            f"no .cia found in {DIST_DIR} — run ./dev/build.sh cia first"
        )
    return candidates[0]


def human(size: int) -> str:
    value = float(size)
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024 or unit == "GB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{value:.1f} GB"


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<style>
  body {{
    margin: 0; min-height: 100vh; display: flex; flex-direction: column;
    align-items: center; justify-content: center; gap: 1.5rem;
    background: #14181d; color: #e8e6e3;
    font: 15px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
  }}
  img {{ width: 360px; height: 360px; image-rendering: pixelated; background: #fff; padding: 16px; }}
  a {{ color: #e8e6e3; }}
  .meta {{ color: #8b949e; }}
  button {{
    border: 0; border-radius: 4px; padding: .75rem 1rem;
    background: #e8e6e3; color: #14181d; cursor: pointer;
    font: inherit;
  }}
  button:disabled {{ opacity: .5; cursor: wait; }}
  #status {{ min-height: 1.5em; color: #8b949e; }}
</style>
</head>
<body>
  <img src="/qr.png" alt="QR code for {url}">
  <div><a href="{url}">{url}</a></div>
  <div class="meta" id="meta">{name} &middot; {size} &middot; built {built}</div>
  <button id="rebuild" type="button">Rebuild CIA</button>
  <button id="reveal" type="button">Reveal in File Explorer</button>
  <div id="status" role="status" aria-live="polite"></div>
  <script>
    const button = document.getElementById('rebuild');
    const revealButton = document.getElementById('reveal');
    const status = document.getElementById('status');
    const meta = document.getElementById('meta');
    let timer;

    function updateStatus() {{
      fetch('/status', {{ cache: 'no-store' }})
        .then(response => response.json())
        .then(state => {{
          button.disabled = state.running;
          status.textContent = state.running ? 'Building CIA…' : (state.message || '');
          if (state.meta) {{
            meta.textContent = `${{state.meta.name}} · ${{state.meta.size}} · built ${{state.meta.built}}`;
          }}
          if (state.running) timer = setTimeout(updateStatus, 1000);
          else if (timer) clearTimeout(timer);
        }});
    }}

    button.addEventListener('click', () => {{
      button.disabled = true;
      status.textContent = 'Starting build…';
      fetch('/rebuild', {{ method: 'POST' }})
        .then(response => response.json())
        .then(() => updateStatus())
        .catch(() => {{
          button.disabled = false;
          status.textContent = 'Could not start the build.';
        }});
    }});

    revealButton.addEventListener('click', () => {{
      revealButton.disabled = true;
      fetch('/reveal', {{ method: 'POST' }})
        .then(response => response.json())
        .then(result => {{
          if (!result.ok) status.textContent = result.message || 'Could not open File Explorer.';
        }})
        .catch(() => {{
          status.textContent = 'Could not open File Explorer.';
        }})
        .finally(() => {{ revealButton.disabled = false; }});
    }});

    updateStatus();
  </script>
</body>
</html>
"""


class BuildState:
    def __init__(self):
        self.lock = threading.Lock()
        self.running = False
        self.message = ""

    def start(self) -> bool:
        with self.lock:
            if self.running:
                return False
            self.running = True
            self.message = ""
        threading.Thread(target=self._run, daemon=True).start()
        return True

    def snapshot(self) -> dict[str, object]:
        with self.lock:
            return {"running": self.running, "message": self.message}

    def _run(self):
        try:
            result = subprocess.run(
                ["bash", str(DEV_DIR / "build.sh"), "cia"],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            output = (result.stdout + result.stderr).strip().splitlines()
            with self.lock:
                if result.returncode == 0:
                    self.message = output[-1] if output else "CIA build complete."
                else:
                    self.message = output[-1] if output else "CIA build failed."
        except OSError as error:
            with self.lock:
                self.message = f"CIA build could not start: {error}"
        finally:
            with self.lock:
                self.running = False


def reveal_in_file_manager(target: Path) -> tuple[bool, str]:
    """Open the host machine's file manager at target, selecting it if the platform allows."""
    if sys.platform == "darwin":
        command = ["open", "-R", str(target)]
    elif os.name == "nt":
        command = ["explorer", f"/select,{target}"]
    elif sys.platform.startswith("linux"):
        command = ["xdg-open", str(target.parent)]
    else:
        return False, f"don't know how to open a file manager on {sys.platform}"

    try:
        subprocess.Popen(command)
    except OSError as error:
        return False, f"could not launch file manager: {error}"
    return True, ""


def target_meta(target: Path) -> dict[str, str]:
    stat = target.stat()
    return {
        "name": target.name,
        "size": human(stat.st_size),
        "built": time.strftime("%H:%M:%S", time.localtime(stat.st_mtime)),
    }


def build_handler(target: Path, url: str, qr_png: bytes, build_state: BuildState):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        server_version = "balatro3ds-dev"

        def log_message(self, fmt, *args):
            sys.stderr.write(
                f"[{time.strftime('%H:%M:%S')}] {self.address_string()} {fmt % args}\n"
            )

        def _send(self, body: bytes, content_type: str, status: int = 200):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def _serve_file(self):
            size = target.stat().st_size
            start, end = 0, size - 1
            status = 200

            # FBI resumes interrupted downloads with a range request.
            match = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
            if match and (match.group(1) or match.group(2)):
                if match.group(1):
                    start = int(match.group(1))
                    if match.group(2):
                        end = min(int(match.group(2)), size - 1)
                else:
                    start = max(size - int(match.group(2)), 0)
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                status = 206

            length = end - start + 1
            self.send_response(status)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(length))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header(
                "Content-Disposition", f'attachment; filename="{target.name}"'
            )
            if status == 206:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.end_headers()

            if self.command == "HEAD":
                return

            started = time.monotonic()
            sent = 0
            with target.open("rb") as handle:
                handle.seek(start)
                while sent < length:
                    chunk = handle.read(min(64 * 1024, length - sent))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    sent += len(chunk)

            elapsed = max(time.monotonic() - started, 1e-6)
            self.log_message(
                "sent %s in %.1fs (%s/s)",
                human(sent),
                elapsed,
                human(int(sent / elapsed)),
            )

        def do_HEAD(self):
            self.do_GET()

        def do_GET(self):
            path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)

            if path == f"/{target.name}":
                try:
                    self._serve_file()
                except (BrokenPipeError, ConnectionResetError):
                    self.log_message("download aborted by client")
                return

            if path == "/qr.png":
                self._send(qr_png, "image/png")
                return

            if path == "/status":
                import json

                state = build_state.snapshot()
                state["meta"] = target_meta(target)
                self._send(
                    json.dumps(state).encode(),
                    "application/json; charset=utf-8",
                )
                return

            if path == "/":
                meta = target_meta(target)
                page = PAGE.format(
                    title=html.escape(target.stem),
                    url=html.escape(url),
                    name=html.escape(meta["name"]),
                    size=meta["size"],
                    built=meta["built"],
                )
                self._send(page.encode(), "text/html; charset=utf-8")
                return

            self._send(b"not found\n", "text/plain; charset=utf-8", status=404)

        def do_POST(self):
            path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
            import json

            if path == "/rebuild":
                started = build_state.start()
                status = 202 if started else 409
                message = "CIA rebuild started." if started else "CIA rebuild already running."
                self._send(
                    json.dumps({"started": started, "message": message}).encode(),
                    "application/json; charset=utf-8",
                    status=status,
                )
                return

            if path == "/reveal":
                ok, message = reveal_in_file_manager(target)
                self._send(
                    json.dumps({"ok": ok, "message": message}).encode(),
                    "application/json; charset=utf-8",
                    status=200 if ok else 500,
                )
                return

            self._send(b"not found\n", "text/plain; charset=utf-8", status=404)

    return Handler


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, help="CIA to serve (default: newest in dev/dist)")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--host", help="address to advertise (default: detected LAN IP)")
    args = parser.parse_args()

    target = (args.file or newest_cia()).resolve()
    if not target.is_file():
        raise SystemExit(f"not a file: {target}")

    address = args.host or lan_address()
    url = f"http://{address}:{args.port}/{urllib.parse.quote(target.name)}"

    import segno

    code = segno.make(url, error="m")
    buffer = io.BytesIO()
    code.save(buffer, kind="png", scale=8, border=2)
    qr_png = buffer.getvalue()

    print()
    code.terminal(compact=True)
    print()
    print(f"  {target.name}  ({human(target.stat().st_size)})")
    print(f"  {url}")
    print(f"  browser view: http://{address}:{args.port}/")
    print()
    print("  FBI -> Remote Install -> Scan QR Code. Ctrl-C to stop.")
    print(flush=True)

    build_state = BuildState()
    handler = build_handler(target, url, qr_png, build_state)
    try:
        server = Server(("0.0.0.0", args.port), handler)
    except OSError as error:
        raise SystemExit(f"cannot listen on port {args.port}: {error}\ntry --port")

    with server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nstopped")
    return 0


if __name__ == "__main__":
    ensure_segno()
    raise SystemExit(main())
