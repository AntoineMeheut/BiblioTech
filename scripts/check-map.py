#!/usr/bin/env python3
"""Vérifie l'en-tête PMTiles v3 et le schéma OpenMapTiles, sans charger la carte."""
import gzip
import json
from pathlib import Path
import struct
import sys


def check(path):
    path = Path(path)
    size = path.stat().st_size
    with path.open('rb') as src:
        header = src.read(127)
        if len(header) != 127 or header[:8] != b'PMTiles\x03':
            raise ValueError('Fichier PMTiles v3 requis.')
        if header[99] != 1:
            raise ValueError('La carte doit contenir des tuiles vectorielles MVT.')
        if not (0 <= header[100] <= header[101] <= 16):
            raise ValueError('Niveaux de zoom invalides.')
        ranges = [struct.unpack_from('<QQ', header, pos) for pos in (8, 24, 40, 56)]
        for offset, length in ranges:
            if length and (offset < 127 or offset + length > size):
                raise ValueError('Fichier PMTiles tronqué ou offsets invalides.')
        if not ranges[0][1] or not ranges[3][1]:
            raise ValueError('La carte ne contient aucune tuile.')
        offset, length = ranges[1]
        if not 0 < length <= 2 * 1024**2:
            raise ValueError('Métadonnées PMTiles absentes ou trop grandes.')
        src.seek(offset)
        raw = src.read(length)
        if header[97] == 2:
            raw = gzip.decompress(raw)
        elif header[97] != 1:
            raise ValueError('Compression des métadonnées non prise en charge.')
        metadata = json.loads(raw)
        layers = {x['id'] for x in metadata.get('vector_layers', [])}
        if not {'water', 'transportation', 'place'}.issubset(layers):
            raise ValueError('Schéma OpenMapTiles requis : water, transportation et place manquants.')
        return {'bytes': size, 'maxzoom': header[101], 'layers': sorted(layers)}


if __name__ == '__main__':
    try:
        print(json.dumps(check(sys.argv[1]), ensure_ascii=False))
    except (ValueError, OSError, IndexError, KeyError) as exc:
        print('ERREUR carte :', exc, file=sys.stderr)
        sys.exit(1)
