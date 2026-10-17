#!/usr/bin/env python3
"""Téléchargement séquentiel, vérification et index Kiwix (stdlib, Python >= 3.9)."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlparse
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
RESERVE = 2 * 1024**3


def manifest(path):
    entries = json.loads(Path(path).read_text())
    seen = set()
    if not isinstance(entries, list) or not entries:
        raise ValueError('Le manifeste est vide ou invalide.')
    for e in entries:
        name = e['id']
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]+', name) or name in seen:
            raise ValueError('Identifiant invalide ou dupliqué : ' + name)
        seen.add(name)
        u = urlparse(e['url'])
        if u.scheme != 'https' or u.hostname != 'download.kiwix.org' or u.path.split('/')[-1] != name + '.zim':
            raise ValueError('URL Kiwix invalide : ' + e['url'])
        if not isinstance(e['bytes'], int) or e['bytes'] <= 0 or not re.fullmatch('[0-9a-f]{64}', e['sha256']):
            raise ValueError('Taille/empreinte invalide : ' + name)
    return entries


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as src:
        for block in iter(lambda: src.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def verified(path, entry):
    return path.is_file() and path.stat().st_size == entry['bytes'] and sha256(path) == entry['sha256']


def atomic_json(path, data):
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    tmp.chmod(0o644)
    tmp.replace(path)


def download_one(entry, directory, offline=False):
    target = directory / (entry['id'] + '.zim')
    if target.exists():
        print('Vérification :', target.name, flush=True)
        if verified(target, entry):
            target.chmod(0o644)
            return target
        raise ValueError(f'{target} est corrompu ou ne correspond pas au manifeste. '
                         'Le déplacer avant de relancer ; il ne sera pas écrasé.')
    if offline:
        raise ValueError('Archive locale manquante : ' + str(target))
    part = target.with_suffix('.zim.part')
    if part.exists() and part.stat().st_size > entry['bytes']:
        raise ValueError('Fichier partiel trop grand, le déplacer : ' + str(part))
    remaining = entry['bytes'] - (part.stat().st_size if part.exists() else 0)
    if shutil.disk_usage(directory).free < remaining + RESERVE:
        raise ValueError('Espace insuffisant pour ' + target.name + ' (+ 2 Gio de réserve).')
    if remaining:
        print('Téléchargement avec reprise :', target.name, flush=True)
        subprocess.run(['curl', '--fail', '--location', '--proto', '=https',
                        '--proto-redir', '=https', '--retry', '6', '--retry-delay', '5',
                        '--connect-timeout', '30', '--speed-time', '120', '--speed-limit', '1024',
                        '--continue-at', '-', '--output', str(part), entry['url']], check=True)
    if not verified(part, entry):
        raise ValueError('Taille ou SHA-256 incorrect : ' + str(part) +
                         '. Déplacer ce fichier avant de recommencer.')
    part.chmod(0o644)
    part.replace(target)
    return target


def build_index(paths, destination):
    """Ne jamais remplacer l'index existant en cas d'échec de kiwix-manage."""
    fd, name = tempfile.mkstemp(prefix='library-', suffix='.xml', dir=destination.parent)
    os.close(fd)
    tmp = Path(name)
    try:
        tmp.write_text('<?xml version="1.0" encoding="UTF-8"?>\n<library version="20110515"/>\n')
        for path in paths:
            subprocess.run(['kiwix-manage', str(tmp), 'add', str(path.resolve())], check=True)
        # Même un outil qui sort avec succès doit avoir réellement ajouté les livres.
        books = [el for el in ET.parse(tmp).getroot().iter() if el.tag.split('}')[-1] == 'book']
        if len(books) != len(paths):
            raise ValueError(f'Index incomplet : {len(books)}/{len(paths)} archives.')
        tmp.chmod(0o644)
        tmp.replace(destination)
    finally:
        tmp.unlink(missing_ok=True)


def check_remote(entries):
    ns = {'m': 'urn:ietf:params:xml:ns:metalink'}
    errors = []
    for e in entries:
        try:
            result = subprocess.run(['curl', '-fsSL', '--proto', '=https', '--proto-redir', '=https',
                                     '--max-time', '60', e['url'] + '.meta4'],
                                    check=True, capture_output=True)
            file = ET.fromstring(result.stdout).find('m:file', ns)
            if (file is None or file.get('name') != e['id'] + '.zim'
                or int(file.findtext('m:size', namespaces=ns)) != e['bytes']
                or file.find("m:hash[@type='sha-256']", ns).text != e['sha256']):
                raise ValueError('métadonnées différentes du manifeste')
            print('OK', e['id'])
        except (subprocess.CalledProcessError, ET.ParseError, ValueError, AttributeError) as exc:
            errors.append(e['id'] + ' : ' + str(exc))
    if errors:
        raise ValueError('\n'.join(errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['plan', 'check-remote', 'download', 'index', 'sync'])
    parser.add_argument('--manifest', type=Path, default=ROOT / 'config/contents.json')
    parser.add_argument('--data-dir', type=Path, default=ROOT / 'data')
    args = parser.parse_args()
    entries = manifest(args.manifest)
    if args.command == 'plan':
        for e in entries:
            print(f"{e['bytes'] / 1024**3:7.2f} Gio  {e['id']}")
        print(f"Total ZIM : {sum(e['bytes'] for e in entries) / 1024**3:.2f} Gio, hors carte et OS.")
        return
    if args.command == 'check-remote':
        check_remote(entries)
        return
    base = args.data_dir.resolve()
    directory = base / 'zim'
    directory.mkdir(parents=True, exist_ok=True)
    with (base / '.content.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('Un téléchargement ou une indexation est déjà en cours.') from None
        needed = sum(max(0, e['bytes'] - (directory / (e['id'] + '.zim.part')).stat().st_size)
                     if (directory / (e['id'] + '.zim.part')).exists() else e['bytes']
                     for e in entries if not (directory / (e['id'] + '.zim')).exists())
        if args.command in ('download', 'sync') and shutil.disk_usage(base).free < needed + RESERVE:
            raise ValueError(f'Espace insuffisant : {needed / 1024**3:.2f} Gio à télécharger + 2 Gio de réserve.')
        paths = [download_one(e, directory, offline=args.command == 'index') for e in entries]
        if args.command in ('index', 'sync'):
            build_index(paths, base / 'library.xml')
        atomic_json(base / 'contents-installed.json', entries)
        print(f'{len(paths)} archives vérifiées.' + (' Index créé.' if args.command in ('index', 'sync') else ''))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print('ERREUR :', exc, file=sys.stderr)
        sys.exit(1)
