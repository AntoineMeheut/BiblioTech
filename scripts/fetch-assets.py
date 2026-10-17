#!/usr/bin/env python3
"""Installe les scripts et toutes les polices de la carte, sans CDN à l'exécution."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
ASSETS = [
    ('maplibre.tgz', 'https://registry.npmjs.org/maplibre-gl/-/maplibre-gl-5.6.1.tgz',
     'sha512', 'TTSfoTaF7RqKUR9wR5qDxCHH2J1XfZ1E85luiLOx0h8r50T/LnwAwwfV0WVNh9o8dA7rwt57Ucivf1emyeukXg=='),
    ('pmtiles.tgz', 'https://registry.npmjs.org/pmtiles/-/pmtiles-4.3.0.tgz',
     'sha512', 'wnzQeSiYT/MyO63o7AVxwt7+uKqU0QUy2lHrivM7GvecNy0m1A4voVyGey7bujnEW5Hn+ZzLdvHPoFaqrOzbPA=='),
    ('fonts.zip', 'https://raw.githubusercontent.com/openmaptiles/fonts/025ff2b2f84cc0fdf11f7b1d74b3a784595fe7a4/Klokantech%20Noto%20Sans%20Regular.zip',
     'sha256', 'f9ff9f2c202ef2822106b713e0ed5f19490e215266850ecf90d53ba1b0256e24'),
]


def fetch(asset, cache):
    name, url, algorithm, expected = asset
    path = cache / name
    if not path.exists():
        part = path.with_suffix(path.suffix + '.part')
        subprocess.run(['curl', '-fL', '--proto', '=https', '--proto-redir', '=https',
                        '--retry', '5', '--connect-timeout', '30', '--max-time', '600',
                        '--output', str(part), url], check=True)
        part.replace(path)
    digest = hashlib.new(algorithm, path.read_bytes()).digest()
    actual = base64.b64encode(digest).decode() if algorithm == 'sha512' else digest.hex()
    if actual != expected:
        raise ValueError('Empreinte incorrecte : ' + str(path))
    return path


def install(destination, cache):
    destination.mkdir(parents=True, exist_ok=True)
    marker = destination / 'assets.json'
    if marker.exists():
        previous = json.loads(marker.read_text())
        if previous.get('sources') == ASSETS_AS_JSON and all(
            (destination / p).is_file() and hashlib.sha256((destination / p).read_bytes()).hexdigest() == h
            for p, h in previous.get('files', {}).items()
        ) and len(previous.get('files', {})) >= 260:
            print('Ressources cartographiques locales vérifiées.')
            return
    cache.mkdir(parents=True, exist_ok=True)
    files = {}

    def write(name, data):
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(0o644)
        files[name] = hashlib.sha256(data).hexdigest()

    for asset, members in [
        (ASSETS[0], {'package/dist/maplibre-gl.js': 'maplibre-gl.js',
                     'package/dist/maplibre-gl.css': 'maplibre-gl.css',
                     'package/dist/LICENSE.txt': 'maplibre-LICENSE.txt'}),
        (ASSETS[1], {'package/dist/pmtiles.js': 'pmtiles.js'}),
    ]:
        with tarfile.open(fetch(asset, cache)) as archive:
            for member, target in members.items():
                write(target, archive.extractfile(member).read())
    with zipfile.ZipFile(fetch(ASSETS[2], cache)) as archive:
        for name in archive.namelist():
            if re.fullmatch(r'Klokantech Noto Sans Regular/[0-9]+-[0-9]+\.pbf', name):
                write('fonts/' + name, archive.read(name))
    marker.write_text(json.dumps({'sources': ASSETS, 'files': files}, indent=2) + '\n')
    print(f'{len(files)} ressources installées localement.')


ASSETS_AS_JSON = json.loads(json.dumps(ASSETS))
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, default=ROOT / 'web/vendor')
    parser.add_argument('--cache', type=Path, default=ROOT / 'build/assets')
    args = parser.parse_args()
    install(args.destination, args.cache)
