#!/usr/bin/env python3
"""Verify documentation and, on macOS, build and test the native application."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
CORE = ('AGENTS.md', 'CURRENT.md', 'ARCHITECTURE.md', 'CODEMAP.md',
        'TESTING.md', 'OPERATIONS.md', 'README.md',
        'decisions/README.md', 'sessions/README.md')


def check_documents(root, full=False):
    errors = []
    paths = {root / name for name in CORE}
    if full:
        paths.update((root / 'decisions').glob('*.md'))
        paths.update((root / 'sessions').glob('*.md'))
        paths.update(p for p in root.rglob('AGENTS.md')
                     if not any(part.startswith('.') or part in
                                {'node_modules', 'dist', 'build', 'vendor'}
                                for part in p.relative_to(root).parts))
    for path in sorted(paths):
        if not path.is_file():
            errors.append(f'{path.relative_to(root)}: missing document')
            continue
        try:
            text = path.read_text(encoding='utf-8')
        except (OSError, UnicodeError) as exc:
            errors.append(f'{path.relative_to(root)}: {exc}')
            continue
        if not text.strip():
            errors.append(f'{path.relative_to(root)}: empty document')
        in_fence = False
        for number, line in enumerate(text.splitlines(), 1):
            label = f'{path.relative_to(root)}:{number}'
            if line.rstrip() != line:
                errors.append(f'{label}: trailing whitespace')
            if line.lstrip().startswith('```'):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            # Inline Markdown links only; reference links and anchors are manual checks.
            for target in re.findall(r'\]\(([^\s)]+)\)', line):
                url = urlsplit(target.strip('<>'))
                if url.scheme or url.netloc or not url.path:
                    continue
                dest = (path.parent / unquote(url.path)).resolve()
                if not dest.is_relative_to(root.resolve()):
                    errors.append(f'{label}: link escapes repository: {target}')
                elif not dest.exists():
                    errors.append(f'{label}: broken link: {target}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fast', action='store_true', help='check core documents only')
    args = parser.parse_args()
    errors = check_documents(ROOT, full=not args.fast)
    if not args.fast:
        for command in (['git', 'diff', '--check'], ['git', 'diff', '--cached', '--check']):
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            if result.returncode:
                errors.append(' '.join(command) + ':\n' + result.stdout + result.stderr)
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    if not args.fast:
        if sys.platform == 'darwin':
            for command in (['sh', 'scripts/test.sh'], ['sh', 'scripts/build.sh']):
                result = subprocess.run(command, cwd=ROOT)
                if result.returncode:
                    return result.returncode
        else:
            print('SKIP: native build/tests require macOS and Xcode')
    print('PASS: ' + ('Fast' if args.fast else 'Full') + ' validation')
    return 0


if __name__ == '__main__':
    sys.exit(main())
