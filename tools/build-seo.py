#!/usr/bin/env python3
"""Run after adding or editing a course:  python tools/build-seo.py
Rewrites the crawlable syllabus and the Course structured data inside index.html
from courses/catalog.json and each live course's course.json."""
import json, os, re, html
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = 'https://akileswar1606.github.io/Brainforging/'   # change if your address changes
cat = json.load(open(R + '/courses/catalog.json', encoding='utf-8'))['courses']
e = html.escape
body, ld, soon = [], [{'@context': 'https://schema.org', '@type': 'Organization', 'name': 'BrainForging', 'url': URL}], []
for c in cat:
    if c['status'] != 'live':
        soon.append(e(c['title'])); continue
    m = json.load(open(R + '/courses/%s/course.json' % c['slug'], encoding='utf-8'))
    items = ''.join('<li><strong>%s</strong>: %s</li>' % (e(x['title']), e('; '.join(x['lessons']))) for x in m['modules'])
    body.append('<article><h3>%s</h3><p>%s</p><ol>%s</ol></article>' % (e(m['title']), e(m.get('summary', c['short'])), items))
    ld.append({'@context': 'https://schema.org', '@type': 'Course', 'name': m['title'], 'description': m.get('summary', c['short']),
               'url': URL + '#course-' + c['slug'], 'inLanguage': 'en', 'educationalLevel': c.get('level', 'Beginner'),
               'provider': {'@type': 'Organization', 'name': 'BrainForging', 'url': URL},
               'syllabusSections': [{'@type': 'Syllabus', 'name': x['title'], 'description': '; '.join(x['lessons'])} for x in m['modules']]})
if soon: body.append('<p>Coming soon: %s.</p>' % ', '.join(soon))
p = R + '/index.html'
s = open(p, encoding='utf-8').read()
s = re.sub(r'<!--SEO-START-->.*?<!--SEO-END-->', lambda _: '<!--SEO-START-->' + ''.join(body) + '<!--SEO-END-->', s, flags=re.S)
s = re.sub(r'<!--LD-START-->.*?<!--LD-END-->', lambda _: '<!--LD-START--><script type="application/ld+json">' + json.dumps(ld, ensure_ascii=False) + '</script><!--LD-END-->', s, flags=re.S)
open(p, 'w', encoding='utf-8').write(s)
print('index.html updated:', len([c for c in cat if c['status'] == 'live']), 'live course(s),', len(soon), 'coming soon')
