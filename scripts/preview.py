#!/usr/bin/env python3
"""Prévisualisation locale, avec HTTP Range pour PMTiles. Production : nginx."""
import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
from urllib.parse import urlsplit


def handler(webroot, map_path):
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(webroot), **kwargs)

        def send_head(self):
            if urlsplit(self.path).path != '/maps/europe.pmtiles':
                return super().send_head()
            if not map_path.is_file():
                self.send_error(404, 'Carte absente')
                return None
            size = map_path.stat().st_size
            start, end = 0, size - 1
            requested = self.headers.get('Range')
            if requested:
                match = re.fullmatch(r'bytes=(\d+)-(\d*)', requested)
                if not match:
                    self.send_error(416)
                    return None
                start = int(match[1])
                end = min(int(match[2]) if match[2] else end, size - 1)
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header('Content-Range', f'bytes */{size}')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return None
            self.send_response(206 if requested else 200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(end - start + 1))
            if requested:
                self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.end_headers()
            src = map_path.open('rb')
            src.seek(start)
            self.range_remaining = end - start + 1
            return src

        def copyfile(self, source, outputfile):
            if urlsplit(self.path).path != '/maps/europe.pmtiles':
                return super().copyfile(source, outputfile)
            remaining = self.range_remaining
            while remaining:
                block = source.read(min(65536, remaining))
                if not block:
                    break
                outputfile.write(block)
                remaining -= len(block)
    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--map', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent / 'web'
    print(f'Aperçu : http://127.0.0.1:{args.port}/ (Kiwix disponible uniquement sur le Pi)', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), handler(root, args.map)).serve_forever()
