"""Build the reviewed auto-only answer table; never run an asset importer."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'client/server/quest_auto_source_answers.json'
REVISION = '0c58fb6683a49a178a8ad845a8c296c2cb83bd81'
QUESTION_SOURCE = 'gmsv/data/question.txt'
QUIZ_CREATE = 'gmsv/data/npc/genout/quizman.create'
KEYWORDS = ('genout/wpm_100_443_127', 'genout/wpm_20604_11_53',
            'genout/wpm_20605_51_4', 'genout/wpm_20606_9_23')
# Independent pins: changing another import manifest cannot expand this table.
SOURCES = {
    'gmsv/data/npc/genout/quizman.create': 'fd03715c723a7e63d9200a425c97ca22595c84f823be861b8facf7993a83b3ba',
    'gmsv/data/npc/genout/quz_800_29_19': 'ccedfecc1971acb89f460530ecc49331884a6103f22e231d5ce90f60b6211340',
    'gmsv/data/npc/genout/quz_801_18_19': '2b31b5ad18657bd23b5eed610e06e7b9d2c33f8e9a27c2cde3b0de73d492ad4b',
    'gmsv/data/npc/genout/quz_803_18_19': 'b86ca84c382a63a308a3e78603df4fd14e60ffdb608774e64e5736c2d6bdded3',
    'gmsv/data/npc/genout/quz_805_18_19': 'e5d02312a3ac691338247ee8adf0ab462e88f5c08400c6389d8225145d2d095c',
    'gmsv/data/npc/genout/quz_806_29_19': 'fd17f5bbdf93badce16b7ef03dc77906e83f9e092752125366e0ac0d11c3ea70',
    'gmsv/data/npc/genout/quz_808_29_19': '2af2e17cc4c9d9f76e2bfb745eb7dc7926c43c63861d5a38af2b3b090729a90c',
    'gmsv/data/npc/genout/quz_809_18_19': 'cd3db560b516720b52cdfb0241c00bba9941b71532bb94183168b82572a07627',
    'gmsv/data/npc/genout/quz_820_29_19': 'ddb4b6ce8f827ff9c9972cffea33caededa60b4b13b0d4450fac66e1936de9fa',
    'gmsv/data/npc/genout/quz_821_18_19': '1ade8665186f818d8c25a17f288f3699173117fa1003c8fca0db26f4368c12bf',
    'gmsv/data/npc/genout/quz_823_18_19': '755718c7b3e636bb21ad2951e700c56c8c7c66e2a01122dc0f3ed061fe5a0185',
    'gmsv/data/npc/genout/quz_825_18_19': '875d0feb7a20cbca55c335a0a28d8419f82febc7ecf4d4917d7d5cb1ce57182e',
    'gmsv/data/npc/genout/quz_826_29_19': '1ca23787d46cabeb490593edd7ec2c6a9bdafe1c077bda34e89e7d7455f0962d',
    'gmsv/data/npc/genout/quz_828_29_19': '227b54ce9134ca70ee25ffdc56f59f6bfd15052ec6018970c27cb677671a303c',
    'gmsv/data/npc/genout/quz_829_18_19': '476c9b348709e18d5e04971530c66a5bfc53b204053cc631d6b42149123d83e9',
    'gmsv/data/npc/genout/quz_840_29_19': '993132a85dfba1eaf16b00ef00c3f545b45d4bf4318e5118bf3fd3c7895fbea4',
    'gmsv/data/npc/genout/quz_841_18_19': 'c9393ee19f7dad7cc585e5738805a365715943354ed920078d5851cd7f939f0d',
    'gmsv/data/npc/genout/quz_843_18_19': 'f4fa6bded3d4cabc0dab7d7705ea0eec20162e7566631d7ca01843b5d53dffdf',
    'gmsv/data/npc/genout/quz_845_18_19': 'bada17318c23f98bc871cd356df91b8dea1f90e98bbd88999fa4c8558635beb9',
    'gmsv/data/npc/genout/quz_846_29_19': 'e8c15842084dffd4e924ad71987d7b4cfdbc1f739906635d9a20a3b75f2bd19b',
    'gmsv/data/npc/genout/quz_848_29_19': '3ab4bd38eedce92426e824e4afe253dca263c476644d80cedea5cf8dbbe7c689',
    'gmsv/data/npc/genout/quz_849_18_19': 'b686babbfaca93d828ef07895efd178ae0758498444799d108afc312d1e42271',
    'gmsv/data/npc/genout/wpm_100_443_127': 'ab24fd28d53a0230943ff27ed0c852b4cde5d4b2d1ad22de4fccafadba700da5',
    'gmsv/data/npc/genout/wpm_20604_11_53': 'f8b7c37293c00d1b823f7bfb5841337c307554dae82f95d841ce32905767ce36',
    'gmsv/data/npc/genout/wpm_20605_51_4': '1041e0f8ed17b33db3492eb4368868b9b15c7c9997c3173233dbc801dc63e355',
    'gmsv/data/npc/genout/wpm_20606_9_23': 'c9dbab118a5c7480bbe01ed5f8029e3e4120aea3ec7d2407a2017a10c156be23',
    'gmsv/data/question.txt': 'b9ebc526f4cdcbc2f52c1a914089ba699a769bb483ed0d92f2caaf11ebbf57d8',
    'gmsv/npc/npc_quiz.c': 'bd453d39d6ad48a9ba3e630d7397af5b61e67e60fb71fa0d95768add4f3ffe0f',
}


def read_sources(reference):
    result = {}
    for name, digest in SOURCES.items():
        raw = (Path(reference) / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError('Unreviewed answer source: ' + name)
        result[name] = raw.decode('gb18030')
    return result


def parse_questions(text):
    questions = []
    for line, raw in enumerate(text.splitlines(), 1):
        if not raw or raw.startswith('#'):
            continue
        # npc_quiz.c:957-994 requires nine comma fields; do not repair line8.
        columns = raw.split(',')
        if len(columns) < 9:
            continue
        ident, kind, level, form, answer = map(int, columns[:5])
        if form not in (1, 2, 4) or not 1 <= answer <= 3:
            raise ValueError('Unknown original question form')
        if (form == 1 and answer == 3) or (form == 4 and answer != 1):
            raise ValueError('Invalid original answer index')
        questions.append(dict(id=ident, type=kind, level_mask=level,
                              answer_type=form, answer=answer - 1,
                              text=columns[5], options=columns[6:9], source_line=line))
    if len({q['id'] for q in questions}) != len(questions):
        raise ValueError('Duplicate original question id')
    return questions


def fields(text):
    return dict(line.split(':', 1) for line in text.splitlines()
                if ':' in line and not line.startswith('#'))


def eligible(question, rule):
    return (rule['type_mask'] & (1 << (question['type'] - 1)) != 0
            and rule['level_mask'] & question['level_mask'] == question['level_mask']
            and rule['answer_mask'] & question['answer_type'] == question['answer_type'])


def build(reference):
    texts = read_sources(reference)
    questions = parse_questions(texts[QUESTION_SOURCE])
    services = {}
    for block in re.findall(r'\{([^}]+)\}', texts[QUIZ_CREATE]):
        values = dict(line.strip().split('=', 1) for line in block.splitlines()
                      if '=' in line and not line.lstrip().startswith('#'))
        match = re.fullmatch(r'npcgen_quiz\|file:(\S+)', values.get('enemy', ''))
        if not match or 'gmsv/data/npc/' + match[1] not in SOURCES:
            continue
        source = match[1]
        rule = fields(texts['gmsv/data/npc/' + source])
        corners = list(map(int, values['borncorner'].split(',')))
        if corners[:2] != corners[2:] or values['createnum'] != '1' or source in services:
            raise ValueError('Ambiguous quiz source binding')
        service = dict(npc_id='%s@%s:%d:%d' % (source, values['floorid'], *corners[:2]),
                       type_mask=int(rule['Type']), level_mask=int(rule['Level']),
                       answer_mask=int(rule['Answer']), count=int(rule['Quiznum']))
        service['question_ids'] = [q['id'] for q in questions if eligible(q, service)]
        services[source] = service
    expected = {'genout/quz_%d_%d_19' % (base + offset, 29 if offset % 2 == 0 else 18)
                for base in (800, 820, 840) for offset in (0, 1, 3, 5, 6, 8, 9)}
    if set(services) != expected or len(questions) != 149 or 8 in [q['id'] for q in questions]:
        raise ValueError('Reviewed question/service scope changed')
    keywords = {}
    for source in KEYWORDS:
        rule = fields(texts['gmsv/data/npc/' + source])
        _, map_id, x, y = source.split('_')
        keywords[source] = dict(npc_id=f'{source}@{map_id}:{x}:{y}',
                                prompt=rule['nomal_msg'].replace('\\n', '\n'),
                                answer=rule['warp_msg'], source_line=3)
    return dict(version=1, reference_revision=REVISION, sources=SOURCES,
                question_source=QUESTION_SOURCE, questions=questions,
                services=services, keywords=keywords)


def serialize(data):
    return json.dumps(data, ensure_ascii=False, sort_keys=True, indent=2) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, default=ROOT / 'references/chenmingbiao-stone-age')
    parser.add_argument('--check', action='store_true', help='Verify the committed table without writing')
    args = parser.parse_args()
    payload = serialize(build(args.reference))
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != payload:
            raise SystemExit('Static source answer table needs regeneration')
    else:
        # This tool has exactly one owned output, never an assets/ destination.
        OUTPUT.write_text(payload)
    print('149 questions, 21 quiz services, 4 keywords; sha256=' + hashlib.sha256(payload.encode()).hexdigest())


if __name__ == '__main__':
    main()
