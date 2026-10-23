#!/usr/bin/env bash
# Python handles paths and subprocesses; Lua measures Neovim's drawn grid.
set -euo pipefail
exec python3 - "$0" "$@" <<'PY'
import argparse
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

parser = argparse.ArgumentParser(prog='rbf/scripts/measure-blank-rows.sh', description='Count blank wrapped rows left by hidden ymd text. Requires Python 3 and Neovim.', epilog='A wrapped row counts when its drawn text cells are blank and its line uses more rows than its visible display width needs. Widths are text columns; the number column is extra. Any file that cannot be measured fails the run. Any [ymd] message containing "error", in any case, fails its file. Exit: 0 clean, 1 rows remain or measurement failed, 2 bad arguments, 3 oracle counted nothing.')
parser.add_argument('--nvim', default='nvim', help='binary to measure (default: nvim on PATH)')
parser.add_argument('--oracle', default=str(Path.home() / '.local/nvim-rbf/oracle-d714648b8e/bin/nvim'), help='known-buggy binary (default: ~/.local/nvim-rbf/oracle-d714648b8e/bin/nvim)')
parser.add_argument('--widths', default='80 100 120 160', help='space-separated text widths (default: 80 100 120 160)')
parser.add_argument('--ymd', required=True, help='path to nvim.ymd (required)')
parser.add_argument('--verbose', action='store_true', help='show ymd\'s Invalid pattern warnings, per-file progress and oracle hits')
parser.add_argument('--timeout', type=float, default=900, metavar='seconds', help='timeout for each binary run (default: 900 seconds)')
parser.add_argument('paths', nargs='*', metavar='file-or-dir')
if not sys.argv[2:]:
    parser.print_help(sys.stderr)
    sys.exit(2)
args = parser.parse_args(sys.argv[2:])
if not math.isfinite(args.timeout) or args.timeout <= 0:
    parser.error('--timeout must be a positive number of seconds')
if not args.paths:
    parser.print_help(sys.stderr)
    parser.exit(2, 'error: give at least one file or directory\n')
if not args.ymd or not (Path(args.ymd) / 'lua/ymd/init.lua').is_file():
    parser.error('missing ymd: ' + (args.ymd or '--ymd is required'))
try:
    widths = [int(w) for w in args.widths.split()]
    if not widths or any(w < 12 or w > 9994 for w in widths):
        raise ValueError()
except ValueError:
    parser.error('--widths must contain integers from 12 to 9994 (text columns)')

binaries = []
for name in (args.oracle, args.nvim):
    binary = shutil.which(os.path.expanduser(name))
    if not binary:
        parser.error('Neovim binary not executable: ' + name)
    binaries.append(Path(binary).resolve())

files = set()
try:
    for name in args.paths:
        path = Path(name).expanduser().absolute()
        if path.is_dir():
            def walk_error(error):
                raise error
            for root, dirs, names in os.walk(path, onerror=walk_error):
                dirs[:] = sorted(d for d in dirs if d not in ('.git', '.jj'))
                files.update(str(Path(root) / n) for n in names if n.endswith('.md'))
        elif path.is_file():
            files.add(str(path))
        else:
            print('ERR ' + str(path) + ': does not exist', file=sys.stderr)
            sys.exit(2)
except OSError as error:
    print('ERR ' + str(error), file=sys.stderr)
    sys.exit(1)
if not files:
    parser.error('no markdown files found')

script = Path(sys.argv[1]).resolve().with_suffix('.lua')
with tempfile.TemporaryDirectory(prefix='nv-1-blank-rows-') as scratch:
    corpus = Path(scratch) / 'corpus.json'
    corpus.write_text(json.dumps(sorted(files)))

    def measure(binary, oracle):
        output = Path(scratch) / ('oracle.json' if oracle else 'build.json')
        output.unlink(missing_ok=True)
        progress = Path(scratch) / 'last-file'
        progress.unlink(missing_ok=True)
        env = os.environ.copy()
        env.pop('VIMRUNTIME', None)
        # Both the usual build/ and an independently configured build-release/.
        runtime = binary.parent.parent.parent / 'runtime'
        if (runtime / 'doc').is_dir():
            env['VIMRUNTIME'] = str(runtime)
        env.update(NVIM_LOG_FILE=str(Path(scratch) / 'nvim.log'), YMD_ROOT=str(Path(args.ymd).resolve()), CORPUS=str(corpus),
                   WIDTHS=' '.join(map(str, widths)), OUT=str(output),
                   ORACLE='1' if oracle else '0', MEASURE_LUA=str(script),
                   VERBOSE='1' if args.verbose else '0', PROGRESS=str(progress))
        child = subprocess.Popen([str(binary), '--headless', '--clean', '-i', 'NONE', '-n',
                                  '-c', 'lua dofile(vim.env.MEASURE_LUA)', '-c', 'cquit 1'],
                                 env=env, stderr=subprocess.PIPE)

        def relay_stderr():
            last = b''
            with child.stderr:
                while chunk := child.stderr.read1(8192):
                    sys.stderr.buffer.write(chunk)
                    sys.stderr.buffer.flush()
                    last = chunk[-1:]
            if last and last != b'\n':
                sys.stderr.buffer.write(b'\n')
                sys.stderr.buffer.flush()

        relay = threading.Thread(target=relay_stderr)
        relay.start()
        try:
            rc = child.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
            rc = 'timeout after %g seconds' % args.timeout
            if progress.is_file():
                width, path = progress.read_text().rstrip('\n').split('\t', 1)
                rc += '; last width %s: %s' % (width, path)
        except BaseException:
            child.kill()
            raise
        finally:
            relay.join()
        if rc != 0 or not output.is_file():
            print('ERR measurement: %s exited %s' % (binary, rc), file=sys.stderr)
            sys.exit(2 if rc == 2 else 1)
        return json.loads(output.read_text())

    try:
        result = measure(binaries[0], True)
        counts = result['counts']
        print('oracle ' + result['version'] + ' | ' + str(len(files)) + ' files | '
              + ' / '.join(map(str, counts)) + ' blank rows at ' + ' / '.join(map(str, widths)), flush=True)
        if args.verbose:
            for hit in result['hits']:
                print('  oracle width %d: %s:%d (%d blank rows)' % tuple(hit), flush=True)
        if sum(counts) == 0:
            print('oracle counted nothing', file=sys.stderr)
            sys.exit(3)
        result = measure(binaries[1], False)
        sys.exit(1 if sum(result['counts']) else 0)
    except (OSError, ValueError, KeyError) as error:
        print('ERR measurement: ' + str(error), file=sys.stderr)
        sys.exit(1)
PY
