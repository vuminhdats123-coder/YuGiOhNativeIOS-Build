"""Read-only native integration preflight. Never compiles or dispatches Actions."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

from apply_native_patches import apply_native_integration, PatchError

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_RUNTIME = (
    'cards.cdb', 'script/constant.lua', 'script/utility.lua', 'config/strings.conf',
    'config/configs.json', 'fonts/NotoSansJP-Regular.otf', 'reports/upstream.lock.json',
    'offline-ai/offline_ai.js',
)


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def gate(status):
    # Runtime proof comes after an authorized verification build, never before it.
    return all(status.get(key) is True for key in ('buildAuthorized', 'implementationReady'))


def object_file(path, label, errors):
    try:
        value = read_json(path)
        if not isinstance(value, dict):
            raise ValueError('expected a JSON object')
        return value
    except (OSError, ValueError) as error:
        errors.append(f'{label}: {error}')
        return None


def validate_source_pins(sources, lock, label, errors):
    for name, component in (('BabelCDB', 'database'), ('CardScripts', 'scripts')):
        actual = sources.get(name, {}) if isinstance(sources, dict) else {}
        for key in ('repository', 'commit'):
            if not isinstance(actual, dict) or actual.get(key) != lock[component][key]:
                errors.append(f'{label}: {name} {key} differs from lock')


def validate_runtime(runtime, lock):
    errors = []
    runtime = Path(runtime)
    manifest = object_file(runtime / 'package-manifest.json', 'Runtime manifest', errors)
    if manifest is None:
        return errors
    if type(manifest.get('schemaVersion')) is not int or manifest['schemaVersion'] != 1:
        errors.append('Runtime manifest: unsupported schemaVersion')
    if manifest.get('sourceOBBSHA256') != lock['sourceOBB']['sha256']:
        errors.append('Runtime manifest: OBB hash differs from lock')
    if manifest.get('sourceCDBSHA256') != lock['database']['sha256']:
        errors.append('Runtime manifest: CDB hash differs from lock')
    validate_source_pins(manifest.get('sourcePins'), lock, 'Runtime manifest', errors)
    entries = manifest.get('files')
    if not isinstance(entries, dict):
        errors.append('Runtime manifest: missing files map')
        entries = {}
    validated_paths = set()
    for relative in REQUIRED_RUNTIME:
        path = runtime / relative
        record = entries.get(relative)
        if (not isinstance(record, dict) or type(record.get('bytes')) is not int or record['bytes'] <= 0
                or not isinstance(record.get('sha256'), str) or not re.fullmatch(r'[0-9a-f]{64}', record['sha256'])):
            errors.append(f'Runtime manifest: invalid/missing record for {relative}')
            continue
        current = runtime
        symlink = current.is_symlink()
        for component in Path(relative).parts:
            current /= component
            symlink = symlink or current.is_symlink()
        if symlink or not path.is_file():
            errors.append(f'Runtime package: missing or symlink resource {relative}')
            continue
        validated_paths.add(relative)
        if path.stat().st_size != record['bytes'] or digest(path) != record['sha256']:
            errors.append(f'Runtime package: size/hash mismatch for {relative}')
    cdb = runtime / 'cards.cdb'
    if 'cards.cdb' in validated_paths and digest(cdb) != lock['database']['sha256']:
        errors.append('Runtime package: cards.cdb content differs from locked database')
    copied_lock = object_file(runtime / 'reports/upstream.lock.json', 'Runtime source lock', errors) if 'reports/upstream.lock.json' in validated_paths else None
    if copied_lock is not None:
        if copied_lock != lock:
            errors.append('Runtime source lock: contents differ from checkout lock')
        if digest(runtime / 'reports/upstream.lock.json') != manifest.get('sourceLockSHA256'):
            errors.append('Runtime manifest: source lock hash mismatch')
    return errors


def validate_coverage(path, lock):
    errors = []
    audit = object_file(path, 'Coverage audit', errors)
    if audit is None:
        return errors
    if audit.get('auditCompleted') is not True:
        errors.append('Coverage audit is not completed')
    sources = audit.get('sources', {})
    validate_source_pins(sources, lock, 'Coverage audit', errors)
    obb_source = sources.get('OBB') if isinstance(sources, dict) else None
    if not isinstance(obb_source, dict) or obb_source.get('sha256') != lock['sourceOBB']['sha256']:
        errors.append('Coverage audit: OBB hash differs from lock')
    downloads = sources.get('downloads', {}) if isinstance(sources, dict) else {}
    hashes = {item.get('sha256') for item in downloads.values() if isinstance(item, dict)} if isinstance(downloads, dict) else set()
    for expected in (lock['database']['sha256'], lock['scripts']['archiveSHA256']):
        if expected not in hashes:
            errors.append('Coverage audit: missing locked source download hash')
    return errors


def inspect(runtime, root=None):
    root = ROOT if root is None else Path(root)
    lock = read_json(root / 'NativeClient/upstream.lock.json')
    status = read_json(root / 'NativeClient/port-status.json')
    pins, errors = {}, []
    for component in ('client', 'core', 'lua', 'distribution'):
        expected = lock[component]
        path = root / expected['path']
        actual = None
        if (path / '.git').exists():
            result = subprocess.run(['git', '-C', str(path), 'rev-parse', 'HEAD'],
                                    capture_output=True, text=True, check=False)
            actual = result.stdout.strip() if result.returncode == 0 else None
        pins[component] = {'expected': expected['commit'], 'actual': actual,
                           'matches': actual == expected['commit']}
        if not pins[component]['matches']:
            errors.append(f'{component}: source pin missing or differs')
    required = [
        'NativeClient/edopro/gframe/iOS/porting_ios.mm',
        'NativeClient/edopro/gframe/duelclient.cpp',
        'NativeClient/edopro/ocgcore/ocgapi.h',
        'NativeClient/edopro/ocgcore/lua/src/lua.h',
        'NativeClient/distribution/config/strings.conf',
        'NativeClient/distribution/fonts/NotoSansJP-Regular.otf',
        'NativeClient/patches/0001-bundled-game.patch',
    ]
    files = {path: (root / path).is_file() for path in required}
    errors += [f'Missing {path}' for path, present in files.items() if not present]
    patch_verified = False
    try:
        apply_native_integration(root / lock['client']['path'], root / 'NativeClient/patches/series.json',
                           expected_revision=lock['client']['commit'], check_only=True)
        patch_verified = True
    except (PatchError, OSError) as error:
        errors.append(f'Bootstrap patch: {error}')
    coverage_path = root / 'YuGiOhNativeIOS/GeneratedData/ocg-coverage.json'
    coverage_errors = validate_coverage(coverage_path, lock)
    runtime_errors = validate_runtime(runtime, lock)
    ai_source = root / 'NativeClient/overlays/offline-ai/offline_ai.js'
    ai_bundled = Path(runtime) / 'offline-ai/offline_ai.js'
    ai_matches = ai_source.is_file() and ai_bundled.is_file() and digest(ai_source) == digest(ai_bundled)
    if not ai_matches:
        runtime_errors.append('Runtime AI script differs from the tested source module or is missing')
    errors += coverage_errors + runtime_errors
    return {
        'scope': 'Pinned source, exact applied patch series and native overlays, coverage provenance, runtime manifest and required-resource hashes only',
        'pins': pins, 'files': files, 'errors': errors,
        'sourcePreparationValid': not errors, 'bootstrapPatchVerified': patch_verified,
        'nativeIntegrationVerified': patch_verified,
        'coverageAuditValid': not coverage_errors, 'runtimePackageValid': not runtime_errors,
        'offlineAIScriptMatchesSource': ai_matches,
        'runtimePackageManifestPresent': (Path(runtime) / 'package-manifest.json').is_file(),
        'fullPackageHashesVerified': False,
        'buildHeld': not gate(status) or bool(errors),
        'runtimeVerified': False, 'fullGameReady': False,
        'remaining': status['remaining'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, default=ROOT / 'outputs/edopro-game-v4')
    parser.add_argument('--report', type=Path, default=ROOT / 'NativeClient/native-readiness.json')
    parser.add_argument('--require-ready', action='store_true')
    args = parser.parse_args()
    try:
        status = read_json(ROOT / 'NativeClient/port-status.json')
        if args.require_ready and not gate(status):
            print('BUILD HELD: native EDOPro integration/runtime is not complete; no compiler was run.', file=sys.stderr)
            return 1
        report = inspect(args.runtime)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0 if report['sourcePreparationValid'] else 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'Preflight failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
