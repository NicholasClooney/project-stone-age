"""Strict original handler subsets for explicitly declared quest instances."""
import re


def keyword_warp(source, script, events):
    fields = {}
    for line in source.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        key, separator, value = line.partition(':')
        if not separator or key in fields:
            raise ValueError('Unsupported keyword source line')
        fields[key] = value
    # Do not turn unrelated WarpMan fields/actions into an unconditional door.
    if set(fields) != {'WARP', 'FREE', 'warp_msg', 'nomal_msg'}:
        raise ValueError('Unreviewed keyword WarpMan fields')
    if fields['FREE'] != 'LV>0' or not fields['warp_msg'] or not re.fullmatch(r'\d+,\d+,\d+', fields['WARP']):
        raise ValueError('Unreviewed keyword WarpMan condition or destination')
    return fields['nomal_msg'].replace('\\n', '\n'), [dict(
        event=-1, type='KEYWORD', condition=fields['FREE'],
        texts={'AcceptMsg':fields['nomal_msg'].replace('\\n', '\n')},
        actions={'Warp':fields['WARP']}, keyword=fields['warp_msg'],
        enabled=True, events=events, source=script,
        source_fields=fields,
        source_rule='gmsv/npc/npc_warpman.c:798-844; exact strcmp then FREE and Warp')]
