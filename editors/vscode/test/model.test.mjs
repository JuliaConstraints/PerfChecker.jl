import test from 'node:test';
import assert from 'node:assert/strict';
import {compareVersions, comparisonsForRuns, filterRuns, logicalFeature, moveRun, outputsForRuns, seriesForRuns} from '../dist/model.js';

const runs = [
  {id: 'a', package: 'Bib', feature: 'parse', backend: 'benchmark', version: '1.2.0', description: ''},
  {id: 'b', package: 'Bib', feature: 'render', backend: 'alloc', version: 'dev@1.10.0', description: ''},
  {id: 'c', package: 'Core', feature: 'parse', backend: 'benchmark', version: '1.10.0', description: ''},
];

test('semantic versions and dev order naturally', () => {
  assert.ok(compareVersions('1.10.0', '1.2.0') > 0);
  assert.ok(compareVersions('dev', '99.0.0') > 0);
  assert.ok(compareVersions('dev@1.10.0', '1.10.0') > 0);
  assert.ok(compareVersions('dev@1.10.0', '2.0.0') < 0);
});

test('filters and sorts the common plan', () => {
  assert.deepEqual(filterRuns(runs, {features: ['parse'], sort: 'version'}).map(run => run.id), ['a', 'c']);
  assert.deepEqual(filterRuns(runs, {search: 'render'}).map(run => run.id), ['b']);
});

test('drag ordering is stable', () => {
  assert.deepEqual(moveRun(['a', 'b', 'c'], 'c', 'a'), ['c', 'a', 'b']);
});

test('measurement backends do not leak into the workload name', () => {
  assert.equal(logicalFeature({feature: 'import_bibtex_allocations', backend: 'profile_alloc'}), 'import_bibtex');
  assert.equal(logicalFeature({feature: 'import_bibtex_profile', backend: 'profile'}), 'import_bibtex');
  assert.equal(logicalFeature({feature: 'import_bibtex_wall_profile', backend: 'wall_profile'}), 'import_bibtex');
  assert.equal(logicalFeature({feature: 'read_and_filter', backend: 'benchmark'}), 'read_and_filter');
});

test('visual outputs follow the selected package, feature and version scope', () => {
  const planned = [{...runs[0], target_kind: 'release', comparison_key: 'parse/v1'}];
  const outputs = [
    {package: 'Bib', feature: 'parse', version: '1.2.0', target_kind: 'release', comparison_key: 'parse/v1'},
    {package: 'Bib', feature: 'parse', version: '1.3.0', target_kind: 'release', comparison_key: 'parse/v1'},
    {package: 'Core', feature: 'parse', version: '1.2.0', target_kind: 'release', comparison_key: 'parse/v1'},
  ];
  assert.deepEqual(outputsForRuns(outputs, planned), [outputs[0]]);

  const series = [
    {package: 'Bib', feature: 'parse'},
    {package: 'Bib', feature: 'render'},
    {package: 'Core', feature: 'parse'},
  ];
  assert.deepEqual(seriesForRuns(series, planned), [series[0]]);
  assert.deepEqual(comparisonsForRuns(series, planned), [series[0]]);
});
