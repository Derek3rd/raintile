#!/usr/bin/env python3
"""Checks and tests of Raintile: run before every commit, and by the
"checks" job of .github/workflows/release.yml on every pull request.

    python tools/check.py                 everything
    python tools/check.py --static        only the checks on the files
    python tools/check.py --tests         only the tests
    python tools/check.py --base <ref>    the branch the change goes to (default:
                                          the PR's base, else origin/nightly)
    python tools/check.py --install-hook  makes them required before every push
                                          (.git/hooks/pre-push, local)

Checks on the files: scripts and .ini/.inc ASCII only without BOM, every .ps1
parses with Windows PowerShell 5.1 (so no PowerShell 7 syntax), XAML and
JSON load, Raintile.lua compiles with Lua 5.1, the widget gallery points to
files that exist, every setting of Settings.inc is in the Options schema and
SchemaData.cs is up to date, GRID_VERSION is bumped when writeGrid() changes,
every page of docs/ goes to the wiki, the Options window takes its glyphs, type
sizes and spacing from Ui.cs / $GLYPH, $FS, $GAP (docs/OptionsUI.md).

Tests: tests/ps (PowerShell scripts run on temporary folders) and tests/lua
(Raintile.lua run against a fake Rainmeter, tests/lua/rainmeter.lua).

Needs Python 3, PowerShell (Windows PowerShell 5.1 on Windows, pwsh
elsewhere) and lupa for Lua 5.1, the version of Rainmeter: pip install lupa
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA_SCRIPT = os.path.join(ROOT, '@Resources', 'Scripts', 'Raintile.lua')

# ASCII only and no BOM (PowerShell 5.1 and Rainmeter read BOM-less files as
# ANSI); C# writes non-ASCII characters as \uXXXX
ASCII_EXT = ('.ps1', '.lua', '.ini', '.inc', '.cs', '.xaml', '.csproj', '.yml', '.json')
# no BOM
TEXT_EXT = ASCII_EXT + ('.md', '.py', '.txt')

failures = []


def fail(msg):
    failures.append(msg)
    print('  FAIL ' + msg)


def section(title):
    print('\n== ' + title)


def rel(path):
    return os.path.relpath(path, ROOT).replace('\\', '/')


def tracked_files():
    """Files of the repository (tracked or new, not ignored)."""
    try:
        out = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard'],
                             cwd=ROOT, capture_output=True, text=True, check=True).stdout
        files = [os.path.join(ROOT, f) for f in out.splitlines() if f]
        return [f for f in files if os.path.isfile(f)]
    except (OSError, subprocess.CalledProcessError):
        result = []
        for folder, dirs, names in os.walk(ROOT):
            dirs[:] = [d for d in dirs if d not in ('.git', 'Generated', 'bin', 'obj', 'Bin')]
            result += [os.path.join(folder, n) for n in names]
        return result


def powershell():
    """Windows PowerShell 5.1 where there is one (what Raintile runs on),
    otherwise pwsh."""
    return shutil.which('powershell') or shutil.which('pwsh')


# Checks on the files -----------------------------------------------------------

def check_text(files):
    section('Text files: ASCII, no BOM')
    n = 0
    for path in files:
        ext = os.path.splitext(path)[1].lower()
        if ext not in TEXT_EXT:
            continue
        n += 1
        data = open(path, 'rb').read()
        if data.startswith(b'\xef\xbb\xbf'):
            fail('%s starts with a BOM' % rel(path))
        if ext in ASCII_EXT:
            for i, line in enumerate(data.split(b'\n'), 1):
                if any(b > 127 for b in line):
                    fail('%s:%d is not ASCII' % (rel(path), i))
                    break
    print('  %d files' % n)


PARSE_PS = r'''
$bad = 0
foreach ($f in $input) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
    foreach ($e in $errors) { $bad++; "{0}:{1}: {2}" -f $f, $e.Extent.StartLineNumber, $e.Message }
}
"PARSED $($PSVersionTable.PSVersion)"
'''


def check_powershell(files):
    section('PowerShell scripts parse')
    scripts = [f for f in files if f.lower().endswith('.ps1')]
    shell = powershell()
    if not shell:
        fail('PowerShell not found: the .ps1 files were not checked')
        return
    out = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-Command', PARSE_PS],
                         input='\n'.join(scripts), capture_output=True, text=True)
    lines = out.stdout.splitlines()
    version = ''
    for line in lines:
        if line.startswith('PARSED '):
            version = line[7:]
        elif line.strip():
            fail(line.replace(ROOT + os.sep, '').replace('\\', '/'))
    if not version:
        fail('PowerShell failed: ' + out.stderr.strip())
        return
    print('  %d scripts, PowerShell %s' % (len(scripts), version))
    if not version.startswith('5.'):
        print('  note: not Windows PowerShell 5.1, PowerShell 7 syntax would not be caught')


def check_xml_json(files):
    section('XAML and JSON load')
    n = 0
    for path in files:
        low = path.lower()
        try:
            if low.endswith('.xaml') or low.endswith('.csproj'):
                n += 1
                ET.parse(path)
            elif low.endswith('.json'):
                n += 1
                with open(path, encoding='utf-8') as f:
                    json.load(f)
        except Exception as e:  # noqa: BLE001 - any error is a failure of the file
            fail('%s: %s' % (rel(path), e))
    print('  %d files' % n)


def check_widgets():
    section('Widget gallery (widgets/index.json)')
    path = os.path.join(ROOT, 'widgets', 'index.json')
    try:
        with open(path, encoding='utf-8') as f:
            index = json.load(f)
    except Exception as e:  # noqa: BLE001
        fail('widgets/index.json: %s' % e)
        return
    ids = set()
    for w in index.get('widgets', []):
        wid = w.get('id', '')
        if not re.match(r'^[A-Za-z0-9_-]+$', wid):
            fail('widget with a bad id: %r' % wid)
            continue
        if wid in ids:
            fail('widget %s listed twice' % wid)
        ids.add(wid)
        for key in ('name', 'kind', 'category', 'base', 'files'):
            if not w.get(key):
                fail('widget %s has no %s' % (wid, key))
        base = w.get('base', '')
        files = w.get('files') or []
        for name in files:
            if '/' in name or '\\' in name or name.startswith('.'):
                fail('widget %s: file name %r leaves its folder' % (wid, name))
        if base.startswith('https://'):
            continue
        if '://' in base:
            fail('widget %s: base is not https: %s' % (wid, base))
            continue
        folder = os.path.join(ROOT, 'widgets', base)
        for name in files:
            if not os.path.isfile(os.path.join(folder, name)):
                fail('widget %s: widgets/%s/%s does not exist' % (wid, base, name))
    print('  %d widgets' % len(ids))


def ini_keys(path):
    keys = []
    for line in open(path, encoding='ascii', errors='replace'):
        m = re.match(r'^\s*([A-Za-z0-9_]+)\s*=', line)
        if m:
            keys.append(m.group(1))
    return keys


def check_settings_schema():
    section('Settings.inc and the Options schema')
    settings = ini_keys(os.path.join(ROOT, '@Resources', 'Settings.inc'))
    schema = open(os.path.join(ROOT, 'src', 'Options', 'SchemaData.cs'), encoding='utf-8').read()
    covered = set(re.findall(r'Key = "([^"]+)"', schema))
    for pair in re.findall(r'Pair = new\[\] \{([^}]*)\}', schema):
        covered.update(re.findall(r'"([^"]+)"', pair))
    # the "screen" control sets the four values of the area
    if re.search(r'Kind = "screen", Key = "ScreenX"', schema):
        covered.update(('ScreenY', 'ScreenW', 'ScreenH'))
    seen = set()
    for key in settings:
        if key in seen:
            fail('Settings.inc: %s is there twice' % key)
        seen.add(key)
        if key not in covered:
            fail('Settings.inc: %s is not in the schema of Options.ps1 (and SchemaData.cs)' % key)
    for key in sorted(set(re.findall(r'Key = "([^"]+)"', schema)) - seen):
        fail('the Options schema has %s, which is not in Settings.inc' % key)
    print('  %d settings' % len(settings))
    # gen_options_schema.py needs pwsh (Windows PowerShell prints the schema
    # in the console's code page); the package check runs it on every PR
    if not shutil.which('pwsh'):
        print('  SchemaData.cs not compared with Options.ps1: needs pwsh (the package check does it)')
        return
    out = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'gen_options_schema.py'), '--check'],
                         capture_output=True, text=True, encoding='utf-8', errors='replace')
    if out.returncode != 0:
        fail((out.stderr or out.stdout).strip())
    else:
        print('  SchemaData.cs is up to date')


def lua_runtime():
    try:
        import lupa.lua51 as lua51
    except ImportError:
        return None
    return lua51.LuaRuntime(unpack_returned_tuples=True)


def check_lua(files):
    section('Lua compiles (Lua 5.1)')
    lua = lua_runtime()
    if lua is None:
        fail('lupa is not installed (pip install lupa): Lua not checked')
        return
    compile_file = lua.eval('function(p) local f, e = loadfile(p) return f ~= nil, e end')
    scripts = [f for f in files if f.lower().endswith('.lua')]
    for path in scripts:
        ok, err = compile_file(path)
        if not ok:
            fail(str(err))
    print('  %d files' % len(scripts))


def write_grid_body(text):
    m = re.search(r'^local function writeGrid\(.*?^end\b', text, re.S | re.M)
    return m.group(0) if m else ''


def grid_version(text):
    m = re.search(r'^local GRID_VERSION = (\d+)', text, re.M)
    return m.group(1) if m else None


def check_grid_version(base):
    section('GRID_VERSION bumped when writeGrid() changes')
    if not base:
        ref = os.environ.get('GITHUB_BASE_REF')
        base = 'origin/' + ref if ref else 'origin/nightly'
    out = subprocess.run(['git', 'show', base + ':@Resources/Scripts/Raintile.lua'],
                         cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0:
        print('  skipped: %s not found (git fetch?)' % base)
        return
    old = out.stdout.replace('\r\n', '\n')
    new = open(LUA_SCRIPT, encoding='utf-8').read().replace('\r\n', '\n')
    if write_grid_body(old) != write_grid_body(new) and grid_version(old) == grid_version(new):
        fail('writeGrid() changed since %s but GRID_VERSION is still %s: skins keep their old Grid.inc'
             % (base, grid_version(new)))
    else:
        print('  compared with %s' % base)


def check_wiki_pages():
    section('Pages of docs/ in the wiki (tools/build_wiki.py)')
    text = open(os.path.join(ROOT, 'tools', 'build_wiki.py'), encoding='utf-8').read()
    pages = re.search(r'PAGES = \{(.*?)\}', text, re.S)
    listed = set(re.findall(r"'([^']+\.md)'", pages.group(1) if pages else ''))
    docs = glob.glob(os.path.join(ROOT, 'docs', '*.md'))
    for path in docs:
        name = os.path.basename(path)
        if name not in listed:
            fail('docs/%s is not in PAGES of tools/build_wiki.py' % name)
    print('  %d pages' % len(docs))


# docs/OptionsUI.md: glyphs come from Glyph / $GLYPH, type sizes from Fs / $FS and
# margins and paddings from Gap / $GAP, so the same action keeps the same icon and
# text the same size and spacing on every page. A line that has to differ (a
# drawing, the menu chrome, the on-screen keyboard) says why with "ui-exempt: <why>".
UI_GLYPH = re.compile(r'0x[Ee][0-9A-Fa-f]{3}\b|\\u[Ee][0-9A-Fa-f]{3}')
UI_RULES = {
    'cs': [
        (UI_GLYPH, 'glyph code: use Glyph'),
        (re.compile(r'\bFontSize\s*=\s*\d'), 'font size: use Fs'),
        (re.compile(r'\bNew(?:Text|Glyph)\((?:"[^"]*"|[^,()"]+),\s*\d'), 'font size: use Fs'),
    ],
    'ps1': [
        (UI_GLYPH, 'glyph code: use $GLYPH'),
        (re.compile(r'\.FontSize\s*=\s*\d'), 'font size: use $FS'),
        (re.compile(r"\bNew-(?:Text|Glyph)\s+(?:'[^']*'|\"[^\"]*\"|\S+)\s+\d"), 'font size: use $FS'),
    ],
}


# A margin or padding: what is assigned to it may hold no number but 0 once the
# Gap / $GAP names are taken out (C#: up to the end of the call or of the property
# in an initializer; PowerShell: up to the end of the statement). XAML attributes
# (Margin="...") are the window's chrome and styles, not checked.
UI_SPACING = {
    'cs': re.compile(r'\b(?:Margin|Padding)\s*=\s*(?!")'),
    'ps1': re.compile(r'\.(?:Margin|Padding)\s*=\s*'),
}
UI_GAP_NAME = re.compile(r'\bGap\.\w+(?:\.\w+)?|\$GAP\.\w+')
UI_NUMBER = re.compile(r'(?<![\w.])(?:[1-9]\d*(?:\.\d+)?|0\.\d*[1-9])')


def spacing_values(line, kind):
    for m in UI_SPACING[kind].finditer(line):
        rest = line[m.end():]
        if kind == 'ps1':
            yield re.split(r';|#', rest)[0]
            continue
        depth, end = 0, len(rest)
        for i, c in enumerate(rest):
            if c in '([{':
                depth += 1
            elif c in ')]}':
                if depth == 0:
                    end = i
                    break
                depth -= 1
            elif c in ',;' and depth == 0:
                end = i
                break
        yield rest[:end]


def spacing_by_hand(line, kind):
    if line.lstrip().startswith('//' if kind == 'cs' else '#'):
        return False
    return any(UI_NUMBER.search(UI_GAP_NAME.sub('', v)) for v in spacing_values(line, kind))


def check_options_ui():
    section('Options window: glyphs, type sizes and spacing from Ui.cs / $GLYPH, $FS, $GAP (docs/OptionsUI.md)')
    files = [f for f in glob.glob(os.path.join(ROOT, 'src', 'Options', '*.cs'))
             if os.path.basename(f) not in ('Ui.cs', 'SchemaData.cs')]
    files.append(os.path.join(ROOT, '@Resources', 'Scripts', 'Options.ps1'))
    for path in files:
        kind = 'cs' if path.endswith('.cs') else 'ps1'
        in_glyphs = False
        for i, line in enumerate(open(path, encoding='utf-8'), 1):
            if 'ui-exempt:' in line:
                continue
            if kind == 'ps1':
                # where the rules are defined: the $GLYPH table, the helpers'
                # defaults, and the menu icon of each page in the schema
                stripped = line.strip()
                if stripped.startswith('$GLYPH = @{'):
                    in_glyphs = True
                if in_glyphs:
                    in_glyphs = stripped != '}'
                    continue
                if stripped.startswith('function ') or re.search(r'\bIcon = 0x', line):
                    continue
            what = next((w for rx, w in UI_RULES[kind] if rx.search(line)), None)
            if what is None and spacing_by_hand(line, kind):
                what = 'margin or padding: use ' + ('Gap' if kind == 'cs' else '$GAP')
            if what:
                fail('%s:%d %s (docs/OptionsUI.md), or say why with "ui-exempt: ..."' % (rel(path), i, what))
    print('  %d files' % len(files))


# Tests ----------------------------------------------------------------------------

def run_ps_tests():
    section('PowerShell tests (tests/ps)')
    shell = powershell()
    if not shell:
        fail('PowerShell not found: tests/ps not run')
        return
    out = subprocess.run([shell, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                          '-File', os.path.join(ROOT, 'tests', 'ps', 'run.ps1')],
                         capture_output=True, text=True)
    failed = False
    for line in out.stdout.splitlines():
        if line.startswith('FAIL '):
            failed = True
            fail(line[5:])
        elif line.strip():
            print('  ' + line)
    if out.returncode != 0 and not failed:
        fail('tests/ps/run.ps1 failed: ' + (out.stderr.strip() or 'exit code %d' % out.returncode))


def native(path):
    return path if os.sep == '\\' else path.replace('\\', '/')


def run_lua_tests():
    section('Lua tests (tests/lua)')
    if lua_runtime() is None:
        fail('lupa is not installed (pip install lupa): tests/lua not run')
        return
    folder = os.path.join(ROOT, 'tests', 'lua')
    for path in sorted(glob.glob(os.path.join(folder, 'test_*.lua'))):
        lua = lua_runtime()
        temps = []

        def mkdtemp():
            d = tempfile.mkdtemp(prefix='raintile-test-')
            temps.append(d)
            return d

        def copytree(src, dst, exclude):
            src, dst = native(src).rstrip('\\/'), native(dst).rstrip('\\/')
            if os.path.isfile(src):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
            elif os.path.isdir(src):
                ignore = shutil.ignore_patterns(*exclude.split('|')) if exclude else None
                shutil.copytree(src, dst, ignore=ignore, dirs_exist_ok=True)

        def mkdir(d):
            os.makedirs(native(d), exist_ok=True)

        def listdir(d):
            d = native(d)
            return '\n'.join(sorted(os.listdir(d))) if os.path.isdir(d) else ''

        def rmtree(d):
            shutil.rmtree(native(d), ignore_errors=True)

        g = lua.globals()
        g.host_mkdtemp, g.host_copytree, g.host_mkdir = mkdtemp, copytree, mkdir
        g.host_listdir, g.host_rmtree = listdir, rmtree
        g.REPO = ROOT
        lua.execute('package.path = ... .. "/?.lua;" .. package.path', folder.replace('\\', '/'))
        load = lua.eval('function(p) local f, e = loadfile(p) if not f then return nil, e end return f(), "" end')
        protect = lua.eval('function(f) local ok, e = xpcall(f, debug.traceback) return ok, tostring(e or "") end')
        try:
            tests, err = load(path)
            if tests is None:
                fail('%s: %s' % (rel(path), err))
                continue
            for name in sorted(tests.keys()):
                ok, err = protect(tests[name])
                label = '%s %s' % (os.path.basename(path)[5:-4], name)
                if ok:
                    print('  ok   ' + label)
                else:
                    fail('%s\n%s' % (label, '\n'.join('       ' + l for l in str(err).splitlines()[:30])))
        finally:
            for d in temps:
                shutil.rmtree(d, ignore_errors=True)


# Pre-push hook ------------------------------------------------------------------

HOOK_MARK = '# raintile-check-hook'
HOOK = '''#!/bin/sh
%s
# Installed by "python tools/check.py --install-hook": every commit pushed is
# checked first (tools/check.py --pre-push); if a check fails the push stops.
# Local only (.git/hooks). "git push --no-verify" skips it.
[ -f tools/check.py ] || { echo "[pre-push] tools/check.py is not in this branch: not checked"; exit 0; }
for p in python py python3; do
    if "$p" -c "import sys; sys.exit(sys.version_info[0] != 3)" >/dev/null 2>&1; then
        exec "$p" tools/check.py --pre-push
    fi
done
echo "[pre-push] Python 3 not found: push stopped"
exit 1
''' % HOOK_MARK


def git_path(name):
    out = subprocess.run(['git', 'rev-parse', '--git-path', name], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.strip()
    return os.path.join(ROOT, out) if not os.path.isabs(out) else out


def install_hook():
    path = git_path('hooks/pre-push')
    if os.path.exists(path) and HOOK_MARK not in open(path, encoding='utf-8', errors='replace').read():
        sys.exit('%s exists and is not this hook: not replaced' % path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='ascii', newline='\n') as f:
        f.write(HOOK)
    os.chmod(path, 0o755)
    print('Installed %s: the checks run before every push' % path)


def pre_push():
    """The pre-push hook: git gives one line per ref pushed ("<local ref>
    <local sha> <remote ref> <remote sha>"). Each commit is checked out in a
    temporary worktree and checked there with its own tools/check.py: what is
    checked is what is pushed, not the working folder."""
    zero = '0' * 40
    shas = []
    for line in sys.stdin:
        parts = line.split()
        if len(parts) == 4 and parts[1] != zero and parts[1] not in shas:
            shas.append(parts[1])
    for sha in shas:
        print('[pre-push] checking %s...' % sha[:10], flush=True)
        base = tempfile.mkdtemp(prefix='raintile-push-')
        tree = os.path.join(base, 'tree')
        nohooks = os.path.join(base, 'nohooks')
        os.mkdir(nohooks)
        try:
            # without the local hooks (post-checkout would build Options there)
            subprocess.run(['git', '-c', 'core.hooksPath=' + nohooks, 'worktree', 'add', '--detach', '--quiet', tree, sha],
                           cwd=ROOT, check=True)
            script = os.path.join(tree, 'tools', 'check.py')
            if not os.path.isfile(script):
                print('[pre-push] %s has no tools/check.py: not checked' % sha[:10])
                continue
            if subprocess.run([sys.executable, script], cwd=tree).returncode != 0:
                print('\n[pre-push] %s does not pass the checks: push stopped. Fix it, commit, push again.' % sha[:10])
                return 1
        finally:
            subprocess.run(['git', 'worktree', 'remove', '--force', tree], cwd=ROOT, capture_output=True)
            shutil.rmtree(base, ignore_errors=True)
            subprocess.run(['git', 'worktree', 'prune'], cwd=ROOT, capture_output=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description='Checks and tests of Raintile')
    parser.add_argument('--static', action='store_true', help='only the checks on the files')
    parser.add_argument('--tests', action='store_true', help='only the tests')
    parser.add_argument('--base', help='branch the change goes to, for the GRID_VERSION check')
    parser.add_argument('--install-hook', action='store_true', help='run the checks before every push')
    parser.add_argument('--pre-push', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.install_hook:
        install_hook()
        return
    if args.pre_push:
        sys.exit(pre_push())
    both = not args.static and not args.tests
    if args.static or both:
        files = tracked_files()
        check_text(files)
        check_powershell(files)
        check_xml_json(files)
        check_widgets()
        check_settings_schema()
        check_lua(files)
        check_grid_version(args.base)
        check_wiki_pages()
        check_options_ui()
    if args.tests or both:
        run_ps_tests()
        run_lua_tests()
    print()
    if failures:
        print('%d problem(s)' % len(failures))
        sys.exit(1)
    print('All checks passed')


if __name__ == '__main__':
    main()
