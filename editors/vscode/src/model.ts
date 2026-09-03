export interface PlanRun {
  id: string;
  package: string;
  package_id: string;
  feature: string;
  workload?: string;
  description: string;
  backend: string;
  julia_compatibility?: {since: string | null; until: string | null; excluded: string[]};
  entrypoint: string;
  version: string;
  target_kind: string;
  target_source?: string | null;
  target_revision?: string | null;
  comparison_key: string;
  status: string;
  reason: string;
}

export interface SuitePlan {
  schema_version: 'perfchecker-suite-plan/1';
  suite: string;
  description: string;
  profile: string;
  plan_revision: string;
  runs: PlanRun[];
}

export interface SuiteRunOutput {
  package: string;
  feature: string;
  workload?: string;
  version: string;
  target_kind: string;
  comparison_key: string;
  status: string;
  elapsed_seconds: number;
  message: string;
  summary: Record<string, unknown>;
}

export interface VersionPoint {
  version: string;
  target_kind: string;
  median: number | null;
  samples: number;
  aggregation: string;
}

export interface VersionSeries {
  package: string;
  feature: string;
  workload?: string;
  metric: string;
  unit: string;
  measurement_definition: string;
  points: VersionPoint[];
}

export interface ComparisonRecord {
  package: string;
  feature: string;
  workload?: string;
  metric: string;
  measurement_definition?: string;
  unit: string;
  baseline_version: string;
  candidate_version: string;
  baseline_median: number;
  candidate_median: number;
  absolute_delta: number;
  relative_delta: number | null;
  status: string;
  reason: string;
}

export interface RunFilter {
  search?: string;
  packages?: string[];
  features?: string[];
  backends?: string[];
  fromVersion?: string;
  toVersion?: string;
  sort?: 'suite' | 'package' | 'feature' | 'version';
}

export interface ParsedGitReference {
  revision: string;
  source?: string;
  suggestedLabel: string;
}

function readableReference(reference: string): string {
  try { return decodeURIComponent(reference); } catch { return reference; }
}

/** Parse the common forms developers paste from GitHub, GitLab, or Git itself. */
export function parseGitReference(input: string, sourceInput = ''): ParsedGitReference {
  let value = input.trim();
  let source = sourceInput.trim() || undefined;
  if (!value) throw new Error('Choose or paste a branch, tag, or commit.');

  const sshFragment = value.match(/^(git@[^:]+:[^#]+?\.git)#(.+)$/);
  if (sshFragment) {
    source ||= sshFragment[1];
    value = readableReference(sshFragment[2]);
  } else if (/^https?:\/\//i.test(value)) {
    const url = new URL(value);
    const github = url.pathname.match(/^\/([^/]+)\/([^/]+?)(?:\.git)?\/(tree|commit|releases\/tag|tags)\/(.+)$/);
    const gitlab = url.pathname.match(/^\/(.+\/[^/]+?)(?:\.git)?\/-\/(tree|commit|tags)\/(.+)$/);
    if (github) {
      source ||= `${url.origin}/${github[1]}/${github[2]}.git`;
      value = readableReference(github[4]);
    } else if (gitlab) {
      source ||= `${url.origin}/${gitlab[1]}.git`;
      value = readableReference(gitlab[3]);
    } else if (url.hash.length > 1) {
      value = readableReference(url.hash.slice(1));
      url.hash = '';
      source ||= url.toString();
    } else {
      throw new Error('This Git URL does not identify a branch, tag, or commit.');
    }
  } else {
    const shorthand = value.match(/^([^/\s]+)\/([^@\s]+)@(.+)$/);
    if (shorthand) {
      source ||= `https://github.com/${shorthand[1]}/${shorthand[2].replace(/\.git$/, '')}.git`;
      value = readableReference(shorthand[3]);
    }
  }

  value = value.replace(/^refs\/heads\//, '').replace(/^refs\/tags\//, '')
    .replace(/^refs\/remotes\/[^/]+\//, '');
  if (!value || value === 'HEAD') throw new Error('Choose a concrete branch, tag, or commit.');
  return {revision: value, ...(source ? {source} : {}),
    suggestedLabel: /^[0-9a-f]{13,40}$/i.test(value) ? value.slice(0, 12) : value};
}

const CHECK_SUFFIXES: Record<string, string[]> = {
  profile_alloc: ['_allocations', '_profile_alloc'],
  wall_profile: ['_wall_profile'],
  profile: ['_profile'],
  chairmark: ['_chairmark'],
  alloc: ['_alloc'],
  network_isolated: ['_network_isolated'],
  network_interface: ['_network_interface'],
  network: ['_network'],
};

/** Human-facing workload name. Measurement backends are separate UI dimensions. */
export function logicalFeature(run: Pick<PlanRun, 'feature' | 'backend' | 'workload'>): string {
  if (run.workload) return run.workload;
  for (const suffix of CHECK_SUFFIXES[run.backend] ?? []) {
    if (run.feature.endsWith(suffix) && run.feature.length > suffix.length) {
      return run.feature.slice(0, -suffix.length);
    }
  }
  return run.feature;
}

function versionParts(value: string): number[] | undefined {
  const normalized = value.startsWith('dev@') ? value.slice(4) : value;
  const match = normalized.match(/^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?/);
  return match ? [Number(match[1]), Number(match[2] ?? 0), Number(match[3] ?? 0)] : undefined;
}

export function compareVersions(left: string, right: string): number {
  if (left === right) return 0;
  if (left === 'dev') return 1;
  if (right === 'dev') return -1;
  const a = versionParts(left);
  const b = versionParts(right);
  if (!a || !b) return left.localeCompare(right);
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) return a[index] - b[index];
  }
  const leftDev = left.startsWith('dev@');
  const rightDev = right.startsWith('dev@');
  if (leftDev !== rightDev) return leftDev ? 1 : -1;
  return left.localeCompare(right);
}

export function filterRuns(runs: PlanRun[], filter: RunFilter): PlanRun[] {
  const needle = (filter.search ?? '').trim().toLocaleLowerCase();
  const selected = runs.filter(run => {
    if (filter.packages?.length && !filter.packages.includes(run.package)) return false;
    if (filter.features?.length && !filter.features.includes(run.feature)) return false;
    if (filter.backends?.length && !filter.backends.includes(run.backend)) return false;
    if (run.target_kind === 'release' && filter.fromVersion && compareVersions(run.version, filter.fromVersion) < 0) return false;
    if (run.target_kind === 'release' && filter.toVersion && compareVersions(run.version, filter.toVersion) > 0) return false;
    return !needle || [run.package, logicalFeature(run), run.feature, run.backend, run.version, run.description]
      .some(value => value.toLocaleLowerCase().includes(needle));
  });
  const sort = filter.sort ?? 'suite';
  if (sort === 'suite') return selected;
  return [...selected].sort((a, b) => {
    if (sort === 'version') return compareVersions(a.version, b.version);
    return a[sort].localeCompare(b[sort]) || compareVersions(a.version, b.version);
  });
}

export function moveRun(order: string[], source: string, target: string): string[] {
  const next = order.filter(id => id !== source);
  const index = next.indexOf(target);
  if (index < 0) return [...next, source];
  next.splice(index, 0, source);
  return next;
}

function samePlannedRun(output: Pick<SuiteRunOutput, 'package' | 'feature' | 'version' | 'target_kind' | 'comparison_key'>,
  planned: PlanRun): boolean {
  return output.package === planned.package && output.feature === planned.feature &&
    output.version === planned.version && output.target_kind === planned.target_kind &&
    (!output.comparison_key || !planned.comparison_key || output.comparison_key === planned.comparison_key);
}

/** Select persisted output for a tree node represented by one or more planned runs. */
export function outputsForRuns(outputs: SuiteRunOutput[], runs: PlanRun[]): SuiteRunOutput[] {
  return outputs.filter(output => runs.some(planned => samePlannedRun(output, planned)));
}

/** Series are version-spanning, so a package/feature match is the useful visual scope. */
export function seriesForRuns(series: VersionSeries[], runs: PlanRun[]): VersionSeries[] {
  return series.filter(item => runs.some(planned => item.package === planned.package && item.feature === planned.feature));
}

/** Comparisons are version-spanning, so a package/feature match is the useful visual scope. */
export function comparisonsForRuns(records: ComparisonRecord[], runs: PlanRun[]): ComparisonRecord[] {
  return records.filter(item => runs.some(planned => item.package === planned.package && item.feature === planned.feature));
}
