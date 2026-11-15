import importlib.util
import hashlib
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
import tempfile
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
spec = importlib.util.spec_from_file_location('check_native_port', ROOT / 'tools/check_native_port.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReadinessGateTests(unittest.TestCase):
    def test_missing_or_unverified_status_blocks(self):
        self.assertFalse(module.gate({}))
        for key in ('buildAuthorized', 'implementationReady'):
            status = dict.fromkeys(('buildAuthorized', 'implementationReady'), True)
            status[key] = False
            self.assertFalse(module.gate(status))
            status[key] = 'true'
            self.assertFalse(module.gate(status))

    def test_checked_in_status_remains_on_hold(self):
        self.assertFalse(module.gate(module.read_json(ROOT / 'NativeClient/port-status.json')))

    def test_runtime_proof_is_not_a_prerequisite_to_verification_build(self):
        self.assertTrue(module.gate({'buildAuthorized': True, 'implementationReady': True,
                                    'runtimeVerified': False, 'fullGameReady': False}))


class RuntimePreparationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='native-preflight-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.runtime = self.root / 'runtime'
        self.runtime.mkdir()
        self.lock = module.read_json(ROOT / 'NativeClient/upstream.lock.json')
        self.lock['database']['sha256'] = hashlib.sha256(b'database fixture').hexdigest()
        self.lock['scripts']['archiveSHA256'] = 'a' * 64
        self.lock_path = self.root / 'NativeClient/upstream.lock.json'
        self.write_json(self.lock_path, self.lock)
        self.write_json(self.root / 'NativeClient/port-status.json', {
            'buildAuthorized': True, 'implementationReady': True, 'remaining': []})
        for relative in module.REQUIRED_RUNTIME:
            path = self.runtime / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            if relative == 'reports/upstream.lock.json':
                path.write_bytes(self.lock_path.read_bytes())
            else:
                path.write_bytes(b'database fixture' if relative == 'cards.cdb' else b'fixture content')
        self.source_pins = {
            name: {key: self.lock[component][key] for key in ('repository', 'commit')}
            for name, component in (('BabelCDB', 'database'), ('CardScripts', 'scripts'))
        }
        self.manifest = {
            'schemaVersion': 1, 'sourceOBBSHA256': self.lock['sourceOBB']['sha256'],
            'sourceCDBSHA256': self.lock['database']['sha256'], 'sourcePins': self.source_pins,
            'sourceLockSHA256': module.digest(self.runtime / 'reports/upstream.lock.json'),
            'files': {relative: {'bytes': (self.runtime / relative).stat().st_size,
                                'sha256': module.digest(self.runtime / relative)}
                      for relative in module.REQUIRED_RUNTIME},
        }
        self.manifest_path = self.runtime / 'package-manifest.json'
        self.write_json(self.manifest_path, self.manifest)
        self.coverage = {
            'auditCompleted': True,
            'sources': {**self.source_pins,
                        'OBB': {'sha256': self.lock['sourceOBB']['sha256']},
                        'downloads': {'database': {'sha256': self.lock['database']['sha256']},
                                      'scripts': {'sha256': self.lock['scripts']['archiveSHA256']}}},
        }
        self.coverage_path = self.root / 'YuGiOhNativeIOS/GeneratedData/ocg-coverage.json'
        self.write_json(self.coverage_path, self.coverage)

    @staticmethod
    def write_json(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding='utf-8')

    def test_valid_required_resources(self):
        self.assertEqual(module.validate_runtime(self.runtime, self.lock), [])
        self.assertEqual(module.validate_coverage(self.coverage_path, self.lock), [])

    def test_missing_or_invalid_manifest_rejected(self):
        for content in (None, '{broken', '[]'):
            if content is None:
                self.manifest_path.unlink()
            else:
                self.manifest_path.write_text(content, encoding='utf-8')
            self.assertTrue(module.validate_runtime(self.runtime, self.lock))

    def test_missing_required_resource_rejected(self):
        (self.runtime / 'script/utility.lua').unlink()
        self.assertTrue(any('script/utility.lua' in error for error in module.validate_runtime(self.runtime, self.lock)))

    def test_changed_resource_hash_rejected(self):
        (self.runtime / 'script/utility.lua').write_bytes(b'changed content')
        self.assertTrue(any('size/hash' in error for error in module.validate_runtime(self.runtime, self.lock)))

    def test_manifest_source_hash_and_pin_mismatch_rejected(self):
        self.manifest['sourceOBBSHA256'] = '0' * 64
        self.manifest['sourcePins']['CardScripts']['commit'] = '0' * 40
        self.write_json(self.manifest_path, self.manifest)
        errors = module.validate_runtime(self.runtime, self.lock)
        self.assertTrue(any('OBB hash' in error for error in errors))
        self.assertTrue(any('CardScripts commit' in error for error in errors))

    def test_copied_lock_mismatch_rejected(self):
        copied = dict(self.lock, unexpectedChange=True)
        self.write_json(self.runtime / 'reports/upstream.lock.json', copied)
        self.assertTrue(any('source lock' in error for error in module.validate_runtime(self.runtime, self.lock)))

    def test_missing_or_unfinished_coverage_rejected(self):
        self.coverage_path.unlink()
        self.assertTrue(module.validate_coverage(self.coverage_path, self.lock))
        self.coverage['auditCompleted'] = False
        self.write_json(self.coverage_path, self.coverage)
        self.assertTrue(module.validate_coverage(self.coverage_path, self.lock))

    def test_unapplied_bootstrap_fails_preparation_even_with_manifest(self):
        for component in ('client', 'core', 'lua', 'distribution'):
            path = self.root / self.lock[component]['path']
            path.mkdir(parents=True, exist_ok=True)
            (path / '.git').write_text('fixture', encoding='utf-8')
        revisions = [SimpleNamespace(returncode=0, stdout=self.lock[component]['commit'])
                     for component in ('client', 'core', 'lua', 'distribution')]
        with patch.object(module.subprocess, 'run', side_effect=revisions), \
             patch.object(module, 'apply_native_patch', side_effect=module.PatchError('Bootstrap patch has not been applied')):
            report = module.inspect(self.runtime, self.root)
        self.assertFalse(report['sourcePreparationValid'])
        self.assertFalse(report['bootstrapPatchVerified'])
        self.assertTrue(any('has not been applied' in error for error in report['errors']))

    def test_require_ready_still_fails_when_dependencies_missing(self):
        report_path = self.root / 'result.json'
        with patch.object(module, 'ROOT', self.root), \
             patch.object(sys, 'argv', ['check_native_port.py', '--require-ready', '--runtime', str(self.root / 'absent'), '--report', str(report_path)]), \
             patch.object(module, 'apply_native_patch', side_effect=FileNotFoundError('client missing')), \
             redirect_stdout(io.StringIO()):
            self.assertEqual(module.main(), 1)
        report = module.read_json(report_path)
        self.assertFalse(report['runtimePackageValid'])
        self.assertFalse(report['sourcePreparationValid'])
        self.assertFalse(report['runtimeVerified'])
        self.assertTrue(report['buildHeld'])

    def test_workflow_has_no_build_and_only_manual_trigger(self):
        workflow = (ROOT / '.github/workflows/ios-build.yml').read_text(encoding='utf-8')
        self.assertIn('workflow_dispatch:', workflow)
        self.assertNotIn('\n  push:', workflow)
        self.assertIn('NativeClient/edopro NativeClient/distribution', workflow)
        self.assertIn('NativeClient/edopro submodule update --init --recursive --depth 1 ocgcore', workflow)
        self.assertIn('python tools/apply_native_patches.py', workflow)
        self.assertNotIn('xcodebuild', workflow)
        self.assertNotIn('premake5', workflow)


if __name__ == '__main__':
    unittest.main()
