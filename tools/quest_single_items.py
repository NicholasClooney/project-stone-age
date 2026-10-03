"""Narrow source-reviewed one-instance creation; not stack support."""
import hashlib
import json
from pathlib import Path

AUDIT = json.loads(Path(__file__).with_name('quest_single_item_reviews.json').read_text())
SOURCES = AUDIT['sources']


def reviewed_single_items(reference, spec):
    entries = spec.get('single_item_pile_reviews', [])
    if not isinstance(entries, list):
        raise ValueError('Invalid single item pile reviews')
    if not entries:
        return {}
    for path, sha in SOURCES.items():
        if (spec.get('sources', {}).get(path) != sha
                or hashlib.sha256((Path(reference) / path).read_bytes()).hexdigest() != sha):
            raise ValueError('Unreviewed single item creation source: ' + path)
    result = {}
    for review in entries:
        if not isinstance(review, dict) or type(review.get('id')) is not int:
            raise ValueError('Invalid single item review')
        ident = review['id']
        if (ident in result or ident not in spec.get('items', [])
                or review != AUDIT['items'].get(str(ident))):
            raise ValueError('Unreviewed single item pile declaration')
        result[ident] = review
    return result


def pile_metadata(review, row, source_line):
    if (review is None or source_line != review['source_line']
            or row[24:26] != review['columns']):
        raise ValueError('Explicit pile fields require exact single item review')
    return dict(upinums=1, canpile=1, creation_quantity=1, stacking_supported=False,
                source_columns=review['columns'], source_line=source_line, audit=review['audit'])
