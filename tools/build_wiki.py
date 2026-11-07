"""Builds the pages of the GitHub wiki from docs/ (the wiki is a copy: the
docs are written in docs/ and the wiki is rewritten from them by
.github/workflows/wiki.yml).

    python tools/build_wiki.py <out folder> [<owner/repo> [<branch>]]

Pages: Home, Guide (docs/Guide.md), Writing-widgets (docs/Widgets.md) and
the sidebar. Links between the docs become links between wiki pages; links
to other files of the repository become links to them on GitHub.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# docs file -> wiki page
PAGES = {
    'Guide.md': 'Guide',
    'Widgets.md': 'Writing-widgets',
}

LINK = re.compile(r'\]\(([^)\s]+)\)')


def rewrite(text, repo, branch):
    def fix(m):
        target = m.group(1)
        if re.match(r'^[a-z]+:', target) or target.startswith('#'):
            return m.group(0)
        path, _, anchor = target.partition('#')
        anchor = '#' + anchor if anchor else ''
        name = os.path.basename(path)
        # another page of the docs
        if os.path.dirname(path) in ('', '.') and name in PAGES:
            return '](' + PAGES[name] + anchor + ')'
        # a file of the repository (docs/ is one level down)
        full = os.path.normpath(os.path.join('docs', path)).replace('\\', '/')
        if full.startswith('..'):
            return m.group(0)
        return '](https://github.com/%s/blob/%s/%s%s)' % (repo, branch, full, anchor)
    return LINK.sub(fix, text)


def main():
    out = sys.argv[1]
    repo = sys.argv[2] if len(sys.argv) > 2 else 'Derek3rd/raintile'
    branch = sys.argv[3] if len(sys.argv) > 3 else 'main'
    os.makedirs(out, exist_ok=True)
    note = ('> This page is written from [`docs/`](https://github.com/%s/tree/%s/docs) of the repository; '
            'edits go there, not here.\n\n') % (repo, branch)
    for src, page in PAGES.items():
        with open(os.path.join(ROOT, 'docs', src), encoding='utf-8') as f:
            text = f.read()
        with open(os.path.join(out, page + '.md'), 'w', encoding='utf-8', newline='\n') as f:
            f.write(note + rewrite(text, repo, branch))
    with open(os.path.join(out, 'Home.md'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(note + '# Raintile\n\n'
                'A tile launcher for Rainmeter: your games, apps and links in categories, full screen, '
                'in a window or docked on a side, with widgets.\n\n'
                '- [Guide](Guide): installing, using and setting up Raintile, every setting.\n'
                '- [Writing widgets](Writing-widgets): custom widgets and what Raintile offers them.\n'
                '- [Downloads](https://github.com/%s/releases): the releases and the nightly build.\n' % repo)
    with open(os.path.join(out, '_Sidebar.md'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('**Raintile**\n\n- [Home](Home)\n- [Guide](Guide)\n- [Writing widgets](Writing-widgets)\n'
                '- [Releases](https://github.com/%s/releases)\n' % repo)
    print('wiki pages written to', out)


if __name__ == '__main__':
    main()
