"""Allowlisted bounded log reads; integrate behind existing bearer authentication."""
import os
import re
import stat
from datetime import datetime, timezone
from pathlib import Path

SECRET_FIELDS = re.compile(r'(?i)(authorization|cookie|api[_-]?key|access[_-]?token|password|secret)(\s*[:=]\s*)([^\s,;]+)')
BEARER = re.compile(r'(?i)\bBearer\s+[^\s,;]+')
KEYS = re.compile(r'AIza[\w-]{20,}|\bsk-[\w-]{16,}')

def redact(text):
    text = re.sub(r'(?i)(authorization\s*:\s*).*', r'\1[redacted]', text)
    text = SECRET_FIELDS.sub(lambda m: m[1] + m[2] + '[redacted]', text)
    return KEYS.sub('[redacted]', BEARER.sub('Bearer [redacted]', text))[:2000]

class LogsAdapter:
    def __init__(self, *, log_roots=(), processes=None, docker_readers=None):
        self.roots = [Path(root).resolve(strict=True) for root in log_roots]
        self.processes = {}
        for ident, streams in (processes or {}).items():
            if not isinstance(ident, int) or ident < 0:
                raise ValueError('Invalid registered PM2 ID')
            checked = {}
            for stream, filename in streams.items():
                if stream not in ('stdout', 'stderr'): raise ValueError('Unknown stream')
                path = Path(filename).resolve(strict=True)
                if not any(path.is_relative_to(root) for root in self.roots):
                    raise ValueError('Log outside registered roots')
                if not path.is_file(): raise ValueError('Log is not a regular file')
                checked[stream] = path
            self.processes[str(ident)] = checked
        self.docker = {name: callback for name, callback in (docker_readers or {}).items() if callable(callback)}

    def handle(self, method, path, *, authenticated=False, limit=500):
        if not authenticated: return 401, {'ok': False}
        parts = path.split('/')
        if method != 'GET' or len(parts) != 5 or parts[:2] != ['', 'api'] or parts[4] != 'logs':
            return 404, {'ok': False}
        try: limit = min(max(int(limit), 1), 500)
        except (ValueError, TypeError): return 400, {'ok': False}
        kind, ident = parts[2:4]
        try:
            if kind == 'process' and ident in self.processes:
                rows = []
                truncated = False
                streams = self.processes[ident]
                per_stream = max(1, limit // max(len(streams), 1))
                for stream, filename in streams.items():
                    lines, cut = self.tail(filename, stream, per_stream)
                    rows.extend(lines); truncated |= cut
            elif kind == 'docker' and ident in self.docker:
                # Callback is fixed server-side, bounded, and returns normalized stream/text rows.
                raw = self.docker[ident](limit)
                rows = [{'id': str(i), 'stream': row['stream'], 'text': redact(row['text']),
                         'timestamp': None} for i, row in enumerate(raw[-limit:]) if row.get('stream') in ('stdout', 'stderr')]
                truncated = len(raw) >= limit
            else: return 404, {'ok': False}
            return 200, {'lines': rows[-limit:], 'truncated': truncated,
                         'fetchedAt': datetime.now(timezone.utc).isoformat()}
        except Exception:
            return 503, {'ok': False}  # Do not expose paths, credentials or exception details.

    def tail(self, filename, stream, limit):
        # Revalidate after rotation; never follow a replacement symlink.
        path = filename.resolve(strict=True)
        if path != filename or not any(path.is_relative_to(root) for root in self.roots):
            raise ValueError('Unsafe rotated path')
        fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0))
        with os.fdopen(fd, 'rb') as handle:
            meta = os.fstat(handle.fileno())
            if not stat.S_ISREG(meta.st_mode): raise ValueError('Not a regular file')
            offset = max(0, meta.st_size - 65536)
            handle.seek(offset)
            data = handle.read(65536)
        if offset and b'\n' in data:
            skipped, data = data.split(b'\n', 1); offset += len(skipped) + 1
        chunks = data.splitlines(keepends=True)
        skipped = chunks[:-limit]
        offset += sum(map(len, skipped))
        rows = []
        for chunk in chunks[-limit:]:
            rows.append({'id': f'{stream}:{meta.st_ino}:{offset}', 'stream': stream,
                         'text': redact(chunk.decode('utf-8', errors='replace').rstrip()), 'timestamp': None})
            offset += len(chunk)
        return rows, meta.st_size > 65536 or len(chunks) > limit
