import * as vscode from 'vscode';
import { spawn } from 'node:child_process';
import * as path from 'node:path';
import { createReadStream } from 'node:fs';
import { promises as fs } from 'node:fs';
import * as readline from 'node:readline';
import {
  ComparisonRecord, PlanRun, SuitePlan, SuiteRunOutput, VersionSeries,
  comparisonsForRuns, logicalFeature, moveRun, outputsForRuns, seriesForRuns,
} from './model';

type NodeKind = 'package' | 'feature' | 'check' | 'run';

function checkLabel(backend: string): string {
  return ({
    benchmark: 'BenchmarkTools', chairmark: 'Chairmarks', alloc: 'Line allocations',
    profile_alloc: 'Allocation profile', profile: 'CPU profile',
    wall_profile: 'Wall-time profile', network: 'Network workload',
    network_interface: 'Network interface', network_isolated: 'Isolated network',
  } as Record<string, string>)[backend] ?? backend.replaceAll('_', ' ');
}

interface SuiteResultFile {
  schema_version: string;
  suite: string;
  description: string;
  profile: string;
  passed: boolean;
  started_at: string;
  finished_at: string;
  runs: SuiteRunOutput[];
}

interface VersionSeriesFile {
  schema_version: string;
  run_id?: string;
  series: VersionSeries[];
}

interface VersionComparisonFile {
  schema_version: string;
  records: ComparisonRecord[];
}

interface GitTarget {
  package: string;
  label: string;
  revision: string;
  source?: string;
  compatibility_version?: string;
}

interface ComparisonPolicyConfig {
  id: string;
  package: string;
  feature?: string;
  comparison_key: string;
  baselines: string[];
  candidates: string[];
  aggregation: 'median' | 'mean' | 'minimum' | 'maximum';
}

function html(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[character]!));
}

function finite(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function compact(value: number): string {
  return new Intl.NumberFormat(undefined, {maximumFractionDigits: 2, notation: 'compact'}).format(value);
}

function formatSeconds(value: number): string {
  if (value < 1e-6) return `${compact(value * 1e9)} ns`;
  if (value < 1e-3) return `${compact(value * 1e6)} µs`;
  if (value < 1) return `${compact(value * 1e3)} ms`;
  return `${compact(value)} s`;
}

function formatBytes(value: number): string {
  const units = ['B', 'KiB', 'MiB', 'GiB'];
  let amount = value; let index = 0;
  while (Math.abs(amount) >= 1024 && index < units.length - 1) { amount /= 1024; index += 1; }
  return `${new Intl.NumberFormat(undefined, {maximumFractionDigits: 2}).format(amount)} ${units[index]}`;
}

function formatValue(value: unknown, key = '', unit = ''): string {
  if (!finite(value)) return value === null || value === undefined ? '—' : String(value);
  if (unit === 'ns' || key.endsWith('_time')) return formatSeconds(value / 1e9);
  if (unit === 's') return formatSeconds(value);
  if (unit === 'By' || key.includes('memory') || key.includes('bytes')) return formatBytes(value);
  if (unit === '%') return `${compact(value)}%`;
  return new Intl.NumberFormat(undefined, {maximumFractionDigits: 2}).format(value);
}

function sparkline(series: VersionSeries, highlightedVersions: Set<string>, id: string): string {
  const points = series.points.filter(point => finite(point.median));
  if (!points.length) return '<div class="empty-chart">No numeric samples</div>';
  const values = points.map(point => point.median as number);
  const minimum = Math.min(...values); const maximum = Math.max(...values);
  const width = 420; const height = 96; const padding = 12;
  const x = (index: number) => points.length === 1 ? width / 2 :
    padding + index * (width - padding * 2) / (points.length - 1);
  const y = (value: number) => maximum === minimum ? height / 2 :
    height - padding - (value - minimum) * (height - padding * 2) / (maximum - minimum);
  const coordinates = points.map((point, index) => `${x(index)},${y(point.median as number)}`).join(' ');
  const circles = points.map((point, index) => {
    const selected = highlightedVersions.has(point.version) ? ' current' : '';
    const label = `${point.version}: ${formatValue(point.median, '', series.unit)} (${point.samples} samples)`;
    return `<circle class="point hover-value${selected}" tabindex="0" data-detail="${html(label)}" data-target="${html(id)}" cx="${x(index)}" cy="${y(point.median as number)}" r="${selected ? 5 : 3}"><title>${html(label)}</title></circle>`;
  }).join('');
  return `<svg class="spark" viewBox="0 0 ${width} ${height}" role="img" aria-label="${html(series.metric)} by version"><polyline points="${coordinates}"></polyline>${circles}</svg><pre class="plot-detail" id="${html(id)}">Hover or focus a point to inspect it.</pre>`;
}

interface ProfileObservation {
  case_id: string;
  target_id: string;
  metric: string;
  measurement_definition: string;
  unit: string;
  value: number;
  aggregation?: string;
  attributes: {
    package?: string;
    feature?: string;
    workload?: string;
    version?: string;
    stack?: string[];
    runtime_dispatch?: boolean[];
    inference_status?: string[];
    inferred_return_type?: string[];
    gc_event?: boolean[];
    source_file?: string;
    source_line?: number;
  };
}

function quantile(sorted: number[], fraction: number): number {
  if (!sorted.length) return Number.NaN;
  const position = (sorted.length - 1) * fraction;
  const lower = Math.floor(position); const upper = Math.ceil(position);
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}

function distributionPlot(observations: ProfileObservation[], id: string): string {
  const sorted = observations.map(item => item.value).filter(finite).sort((a, b) => a - b);
  if (!sorted.length) return '';
  const minimum = sorted[0]; const maximum = sorted[sorted.length - 1];
  const q1 = quantile(sorted, .25); const median = quantile(sorted, .5); const q3 = quantile(sorted, .75);
  const width = 700; const height = 100; const padding = 18;
  const x = (value: number) => maximum === minimum ? width / 2 : padding + (value - minimum) * (width - padding * 2) / (maximum - minimum);
  const sampled = sorted.length <= 320 ? sorted : sorted.filter((_, index) => index % Math.ceil(sorted.length / 320) === 0);
  const unit = observations[0].unit;
  const points = sampled.map((value, index) => {
    const label = `${formatValue(value, '', unit)} · sample ${index + 1}/${sorted.length}`;
    return `<circle class="sample hover-value" tabindex="0" data-detail="${html(label)}" data-target="${html(id)}" cx="${x(value)}" cy="${62 + (index % 5) * 5}" r="2.7"><title>${html(label)}</title></circle>`;
  }).join('');
  const stats = `min ${formatValue(minimum, '', unit)} · Q1 ${formatValue(q1, '', unit)} · median ${formatValue(median, '', unit)} · Q3 ${formatValue(q3, '', unit)} · max ${formatValue(maximum, '', unit)}`;
  return `<svg class="distribution" viewBox="0 0 ${width} ${height}" role="img" aria-label="Sample distribution"><line class="whisker" x1="${x(minimum)}" x2="${x(maximum)}" y1="42" y2="42"></line><rect class="box" x="${x(q1)}" y="28" width="${Math.max(x(q3) - x(q1), 1)}" height="28"></rect><line class="median" x1="${x(median)}" x2="${x(median)}" y1="26" y2="58"></line>${points}</svg><pre class="plot-detail" id="${html(id)}">${html(stats)}</pre>`;
}

function allocationPlot(observations: ProfileObservation[], id: string): string {
  const values = new Map<string, number>();
  for (const observation of observations) {
    const file = observation.attributes.source_file ?? observation.attributes.stack?.at(-1) ?? 'unknown';
    const label = observation.attributes.source_line ? `${file}:${observation.attributes.source_line}` : file;
    values.set(label, (values.get(label) ?? 0) + observation.value);
  }
  let entries = [...values.entries()].sort((a, b) => b[1] - a[1]);
  if (!entries.length) return '';
  if (entries.length > 14) {
    const other = entries.slice(13).reduce((sum, entry) => sum + entry[1], 0);
    entries = [...entries.slice(0, 13), ['Other lines', other]];
  }
  const total = entries.reduce((sum, entry) => sum + entry[1], 0);
  const palette = ['#4f8cff', '#9b6cff', '#e85d75', '#f39c44', '#35b779', '#42a5b3', '#c9a227'];
  let angle = -Math.PI / 2;
  const wedges = entries.map(([label, value], index) => {
    const next = angle + 2 * Math.PI * value / total;
    const large = next - angle > Math.PI ? 1 : 0;
    const x1 = 100 + 82 * Math.cos(angle); const y1 = 100 + 82 * Math.sin(angle);
    const x2 = 100 + 82 * Math.cos(next); const y2 = 100 + 82 * Math.sin(next);
    const detail = `${label}\n${formatBytes(value)} · ${(100 * value / total).toFixed(2)}%`;
    const wedge = `<path class="pie-slice hover-value" tabindex="0" style="fill:${palette[index % palette.length]}" data-detail="${html(detail)}" data-target="${html(id)}" d="M100 100 L${x1} ${y1} A82 82 0 ${large} 1 ${x2} ${y2} Z"><title>${html(detail)}</title></path>`;
    angle = next; return wedge;
  }).join('');
  const legend = entries.map(([label, value], index) => `<li><i style="background:${palette[index % palette.length]}"></i><span title="${html(label)}">${html(path.basename(label))}</span><b>${(100 * value / total).toFixed(1)}%</b></li>`).join('');
  return `<div class="allocation-layout"><svg class="pie" viewBox="0 0 200 200" role="img" aria-label="Allocation share">${wedges}</svg><ol class="allocation-legend">${legend}</ol></div><pre class="plot-detail" id="${html(id)}">Hover or focus a slice to inspect its source line.</pre>`;
}

interface FlameNode {
  name: string;
  value: number;
  children: Map<string, FlameNode>;
  dynamic: boolean;
  unstable: boolean;
  gc: boolean;
  inferredTypes: Set<string>;
}

function flameGraph(observations: ProfileObservation[], id: string): string {
  if (!observations.length) return '';
  const root: FlameNode = {name: 'root', value: 0, children: new Map(), dynamic: false,
    unstable: false, gc: false, inferredTypes: new Set()};
  for (const observation of observations) {
    if (!finite(observation.value) || observation.value <= 0) continue;
    root.value += observation.value;
    let parent = root;
    const stack = observation.attributes.stack ?? [];
    for (let index = 0; index < stack.length; index += 1) {
      const name = stack[index];
      let node = parent.children.get(name);
      if (!node) {
        node = {name, value: 0, children: new Map(), dynamic: false, unstable: false,
          gc: false, inferredTypes: new Set()};
        parent.children.set(name, node);
      }
      node.value += observation.value;
      node.dynamic ||= observation.attributes.runtime_dispatch?.[index] === true;
      const inference = observation.attributes.inference_status?.[index];
      node.unstable ||= Boolean(inference && inference !== 'concrete');
      node.gc ||= observation.attributes.gc_event?.[index] === true;
      const inferred = observation.attributes.inferred_return_type?.[index];
      if (inferred) node.inferredTypes.add(inferred);
      parent = node;
    }
  }
  if (!root.value) return '';
  const rows: string[] = [];
  let maximumDepth = 0; let rendered = 0;
  const width = 1000; const rowHeight = 25;
  const visit = (node: FlameNode, left: number, span: number, depth: number) => {
    if (rendered >= 1800 || span < 0.12) return;
    maximumDepth = Math.max(maximumDepth, depth); rendered += 1;
    const state = node.gc ? 'gc' : node.dynamic ? 'dynamic' : node.unstable ? 'unstable' : 'normal';
    const percent = 100 * node.value / root.value;
    const inferred = [...node.inferredTypes].slice(0, 4).join(' | ');
    const detail = `${node.name}\n${formatValue(node.value, '', observations[0].unit)} · ${percent.toFixed(2)}%` +
      `${node.dynamic ? '\nRuntime dispatch detected' : ''}${node.unstable ? '\nNon-concrete inferred return' : ''}` +
      `${node.gc ? '\nGC frame' : ''}${inferred ? `\nInferred: ${inferred}` : ''}`;
    rows.push(`<g class="flame-node ${state}" tabindex="0" data-detail="${html(detail)}" data-target="${html(id)}"><rect x="${left}" y="${depth * rowHeight}" width="${Math.max(span - 0.7, 0.2)}" height="${rowHeight - 1}"></rect>${span > 70 ? `<text x="${left + 4}" y="${depth * rowHeight + 17}">${html(node.name)}</text>` : ''}<title>${html(detail)}</title></g>`);
    let cursor = left;
    const children = [...node.children.values()].sort((a, b) => b.value - a.value);
    for (const child of children) {
      const childSpan = span * child.value / node.value;
      visit(child, cursor, childSpan, depth + 1);
      cursor += childSpan;
    }
  };
  let cursor = 0;
  for (const child of [...root.children.values()].sort((a, b) => b.value - a.value)) {
    const span = width * child.value / root.value;
    visit(child, cursor, span, 0); cursor += span;
  }
  const truncated = rendered >= 1800 ? '<p class="notice">View limited to 1,800 frames. Open a single test for full detail.</p>' : '';
  return `<div class="flame-wrap"><svg class="flame" viewBox="0 0 ${width} ${(maximumDepth + 1) * rowHeight}" role="img">${rows.join('')}</svg></div><pre class="flame-detail" id="${html(id)}">Hover or focus a frame to inspect it.</pre>${truncated}`;
}

class PerfNode {
  constructor(
    readonly kind: NodeKind,
    readonly label: string,
    readonly runs: PlanRun[],
    readonly parent?: PerfNode,
  ) {}
}

class PlanTree implements vscode.TreeDataProvider<PerfNode>, vscode.TreeDragAndDropController<PerfNode> {
  readonly dragMimeTypes = ['application/vnd.code.tree.perfchecker.runs'];
  readonly dropMimeTypes = this.dragMimeTypes;
  private readonly changed = new vscode.EventEmitter<PerfNode | undefined>();
  readonly onDidChangeTreeData = this.changed.event;
  plan?: SuitePlan;
  selected = new Set<string>();
  order: string[] = [];

  refresh(plan?: SuitePlan): void {
    if (plan) {
      this.plan = plan;
      this.order = plan.runs.map(run => run.id);
      this.selected = new Set(this.order);
    }
    this.changed.fire(undefined);
  }

  getTreeItem(node: PerfNode): vscode.TreeItem {
    const item = new vscode.TreeItem(node.label,
      node.kind === 'run' ? vscode.TreeItemCollapsibleState.None : vscode.TreeItemCollapsibleState.Collapsed);
    item.contextValue = `perfchecker.${node.kind}`;
    item.description = node.kind === 'run' ? `${node.runs[0].version} · ${node.runs[0].backend}` : `${node.runs.length}`;
    item.tooltip = node.kind === 'run' ? `${node.runs[0].description}\n${node.runs[0].entrypoint}` : undefined;
    item.iconPath = new vscode.ThemeIcon(node.kind === 'run' ?
      (node.runs[0].status === 'ready' ? 'beaker' : 'circle-slash') :
      node.kind === 'package' ? 'package' : node.kind === 'check' ? 'pulse' : 'symbol-method');
    if (node.kind === 'run') {
      item.checkboxState = this.selected.has(node.runs[0].id) ?
        vscode.TreeItemCheckboxState.Checked : vscode.TreeItemCheckboxState.Unchecked;
      item.command = {command: 'perfchecker.openEntrypoint', title: 'Open check script', arguments: [node]};
    }
    return item;
  }

  getChildren(node?: PerfNode): PerfNode[] {
    const runs = node?.runs ?? this.plan?.runs ?? [];
    if (!node) {
      return [...new Set(runs.map(run => run.package))].map(name =>
        new PerfNode('package', name, runs.filter(run => run.package === name)));
    }
    if (node.kind === 'package') {
      return [...new Set(runs.map(logicalFeature))].map(name =>
        new PerfNode('feature', name, runs.filter(run => logicalFeature(run) === name), node));
    }
    if (node.kind === 'feature') {
      return [...new Set(runs.map(run => run.backend))].map(backend =>
        new PerfNode('check', checkLabel(backend), runs.filter(run => run.backend === backend), node));
    }
    if (node.kind === 'check') {
      const rank = new Map(this.order.map((id, index) => [id, index]));
      return [...runs].sort((a, b) => (rank.get(a.id) ?? 0) - (rank.get(b.id) ?? 0))
        .map(run => new PerfNode('run', run.version, [run], node));
    }
    return [];
  }

  handleDrag(source: readonly PerfNode[], data: vscode.DataTransfer): void {
    const ids = source.flatMap(node => node.runs.map(run => run.id));
    data.set(this.dragMimeTypes[0], new vscode.DataTransferItem(JSON.stringify(ids)));
  }

  async handleDrop(target: PerfNode | undefined, data: vscode.DataTransfer): Promise<void> {
    const item = data.get(this.dragMimeTypes[0]);
    const ids = item ? JSON.parse(await item.asString()) as string[] : [];
    const targetId = target?.runs[0]?.id;
    if (!targetId) return;
    for (const id of ids) this.order = moveRun(this.order, id, targetId);
    this.changed.fire(undefined);
  }
}

class Controller {
  private readonly output = vscode.window.createOutputChannel('PerfChecker');
  private designer?: vscode.WebviewPanel;
  private resultsPanel?: vscode.WebviewPanel;
  private plan?: SuitePlan;
  private uiConfiguration?: any;

  constructor(private readonly context: vscode.ExtensionContext, readonly tree: PlanTree,
    private readonly tests: vscode.TestController) {}

  reportError(error: unknown): void { this.output.appendLine(String(error)); }
  showLog(): void { this.output.show(true); }

  private root(): string {
    const folder = vscode.workspace.workspaceFolders?.[0];
    if (!folder) throw new Error('Open a package workspace first.');
    return folder.uri.fsPath;
  }

  private setting(name: string): string {
    return vscode.workspace.getConfiguration('perfchecker').get<string>(name)!;
  }

  private gitTargets(): GitTarget[] {
    return vscode.workspace.getConfiguration('perfchecker').get<GitTarget[]>('gitTargets', []);
  }

  private effectiveGitTargets(): GitTarget[] {
    const inspected = vscode.workspace.getConfiguration('perfchecker').inspect<GitTarget[]>('gitTargets');
    const explicitlyConfigured = inspected?.workspaceFolderValue !== undefined ||
      inspected?.workspaceValue !== undefined || inspected?.globalValue !== undefined;
    return explicitlyConfigured ? this.gitTargets() : (this.uiConfiguration?.targets ?? this.gitTargets());
  }

  private candidateArguments(targets = this.effectiveGitTargets()): string[] {
    return targets.map(target => `--candidate=${JSON.stringify(target)}`);
  }

  private comparisonPolicies(): ComparisonPolicyConfig[] {
    return vscode.workspace.getConfiguration('perfchecker').get<ComparisonPolicyConfig[]>('comparisonPolicies', []);
  }

  private effectiveComparisonPolicies(): ComparisonPolicyConfig[] {
    const inspected = vscode.workspace.getConfiguration('perfchecker').inspect<ComparisonPolicyConfig[]>('comparisonPolicies');
    const explicitlyConfigured = inspected?.workspaceFolderValue !== undefined ||
      inspected?.workspaceValue !== undefined || inspected?.globalValue !== undefined;
    return explicitlyConfigured ? this.comparisonPolicies() :
      (this.uiConfiguration?.comparisons ?? this.comparisonPolicies());
  }

  private comparisonArguments(policies = this.effectiveComparisonPolicies()): string[] {
    return policies.map(policy => `--comparison=${JSON.stringify(policy)}`);
  }

  private absolute(setting: string): string {
    return path.resolve(this.root(), this.setting(setting));
  }

  private async invoke(command: string, args: string[], progress?: (value: any) => void,
    emitted?: (value: string) => void): Promise<number> {
    const executable = this.setting('juliaExecutable');
    const project = this.absolute('runnerProject');
    const juliaArgs = [
      '--startup-file=no', `--project=${project}`,
      '-e', 'using PerfChecker; exit(perfchecker_main(ARGS))', '--', command, ...args,
    ];
    this.output.show(true);
    this.output.appendLine(`> ${executable} ${juliaArgs.map(value => JSON.stringify(value)).join(' ')}`);
    return await new Promise<number>((resolve, reject) => {
      const child = spawn(executable, juliaArgs, {cwd: this.root(), windowsHide: true});
      child.stdout.setEncoding('utf8');
      child.stderr.setEncoding('utf8');
      let pending = '';
      const publish = (line: string) => {
        if (!line) return;
        if (line.startsWith('PERFCHECKER_PROGRESS ')) {
          try { progress?.(JSON.parse(line.slice(21))); return; } catch { /* preserve malformed progress as output */ }
        }
        this.output.appendLine(line); emitted?.(`${line}\r\n`);
      };
      const consume = (text: string) => {
        pending += text;
        const lines = pending.split(/\r?\n/); pending = lines.pop() ?? '';
        lines.forEach(publish);
      };
      child.stdout.on('data', consume);
      child.stdout.on('end', () => { if (pending) publish(pending); pending = ''; });
      child.stderr.on('data', text => { this.output.append(text); emitted?.(String(text).replace(/(?<!\r)\n/g, '\r\n')); });
      child.on('error', reject);
      child.on('close', code => resolve(code ?? 2));
    });
  }

  async refresh(): Promise<void> {
    await vscode.window.withProgress({location: vscode.ProgressLocation.Window, title: 'PerfChecker: planning'}, async () => {
      await fs.mkdir(this.context.globalStorageUri.fsPath, {recursive: true});
      try { this.uiConfiguration = JSON.parse(await fs.readFile(this.absolute('uiConfiguration'), 'utf8')); }
      catch { this.uiConfiguration = undefined; }
      const output = path.join(this.context.globalStorageUri.fsPath, 'suite-plan.json');
      const code = await this.invoke('plan', [
        `--suite=${this.absolute('suite')}`, `--factory=${this.setting('factory')}`,
        `--profile=${this.setting('profile')}`, `--output=${output}`,
        ...this.candidateArguments(),
        ...this.comparisonArguments(),
      ]);
      if (code !== 0) throw new Error(`PerfChecker plan failed with code ${code}.`);
      const plan = JSON.parse(await fs.readFile(output, 'utf8')) as SuitePlan;
      if (plan.schema_version !== 'perfchecker-suite-plan/1') throw new Error('Unsupported suite plan.');
      this.plan = plan;
      this.tree.refresh(plan);
      try {
        if (!this.uiConfiguration) throw new Error('No saved UI configuration');
        const saved = (this.uiConfiguration.selection?.run_ids ?? []) as string[];
        const known = new Set(plan.runs.map(run => run.id));
        this.tree.selected = new Set(saved.filter(id => known.has(id)));
        this.tree.order = [...saved.filter(id => known.has(id)),
          ...plan.runs.map(run => run.id).filter(id => !saved.includes(id))];
        this.tree.refresh();
      } catch { this.uiConfiguration = undefined; }
      this.syncTests();
      this.postPlan();
    });
  }

  private syncTests(): void {
    this.tests.items.replace([]);
    if (!this.plan) return;
    for (const packageName of [...new Set(this.plan.runs.map(run => run.package))]) {
      const packageItem = this.tests.createTestItem(`package:${packageName}`, packageName);
      this.tests.items.add(packageItem);
      const packageRuns = this.plan.runs.filter(run => run.package === packageName);
      for (const featureName of [...new Set(packageRuns.map(logicalFeature))]) {
        const featureItem = this.tests.createTestItem(`feature:${packageName}:${featureName}`, featureName);
        packageItem.children.add(featureItem);
        const featureRuns = packageRuns.filter(item => logicalFeature(item) === featureName);
        for (const backend of [...new Set(featureRuns.map(run => run.backend))]) {
          const checkItem = this.tests.createTestItem(`check:${packageName}:${featureName}:${backend}`, checkLabel(backend));
          featureItem.children.add(checkItem);
          for (const run of featureRuns.filter(item => item.backend === backend)) {
            const item = this.tests.createTestItem(run.id, run.version, vscode.Uri.file(run.entrypoint));
            item.description = run.description;
            item.tags = [new vscode.TestTag(`perfchecker.${run.backend}`)];
            checkItem.children.add(item);
          }
        }
      }
    }
  }

  private collectTestIds(items: readonly vscode.TestItem[] | undefined): string[] {
    const known = new Set(this.plan?.runs.map(run => run.id) ?? []);
    const collected: string[] = [];
    const visit = (item: vscode.TestItem) => {
      if (known.has(item.id)) collected.push(item.id);
      else item.children.forEach(visit);
    };
    if (items) items.forEach(visit);
    else this.tests.items.forEach(visit);
    return collected;
  }

  async runTests(request: vscode.TestRunRequest): Promise<void> {
    if (!this.plan) await this.refresh();
    const excluded = new Set(this.collectTestIds(request.exclude));
    const ids = this.collectTestIds(request.include).filter(id => !excluded.has(id));
    const items = new Map<string, vscode.TestItem>();
    const index = (item: vscode.TestItem) => {
      items.set(item.id, item); item.children.forEach(index);
    };
    this.tests.items.forEach(index);
    const run = this.tests.createTestRun(request);
    ids.forEach(id => { const item = items.get(id); if (item) run.enqueued(item); });
    const started = new Set<string>();
    let currentItem: vscode.TestItem | undefined;
    try {
      const args = [
        `--suite=${this.absolute('suite')}`, `--factory=${this.setting('factory')}`,
        `--profile=${this.setting('profile')}`,
        `--reports=${this.absolute('reports')}`, '--progress=jsonl',
        ...this.candidateArguments(),
        ...this.comparisonArguments(),
        ...ids.flatMap(id => [`--run-id=${id}`]),
      ];
      const code = await this.invoke('run', args, value => {
        const current = value.current_run?.id as string | undefined;
        if (current && !started.has(current)) {
          const item = items.get(current); if (item) run.started(item);
          started.add(current);
        }
        currentItem = current ? items.get(current) : currentItem;
      }, text => run.appendOutput(text, undefined, currentItem));
      for (const id of ids) {
        const item = items.get(id); if (!item) continue;
        const planned = this.plan?.runs.find(candidate => candidate.id === id);
        if (planned?.status !== 'ready') run.skipped(item);
        else if (code === 0) run.passed(item);
        else run.failed(item, new vscode.TestMessage(`Inspect the PerfChecker report; the suite exited with code ${code}.`));
      }
    } catch (error) {
      for (const id of ids) {
        const item = items.get(id); if (item) run.errored(item, new vscode.TestMessage(String(error)));
      }
    } finally { run.end(); }
  }

  async initialize(): Promise<void> {
    const code = await this.invoke('init', [`--root=${this.root()}`]);
    if (code !== 0) throw new Error(`PerfChecker initialization failed with code ${code}.`);
    await this.refresh();
  }

  private ids(node?: PerfNode): string[] {
    return node ? node.runs.map(run => run.id) : [...this.tree.selected];
  }

  async run(node?: PerfNode, explicitIds?: string[], revealOutput = false): Promise<void> {
    if (!this.plan) await this.refresh();
    const ids = explicitIds ?? this.ids(node);
    if (!ids.length) throw new Error('Select at least one run.');
    await vscode.window.withProgress({
      location: vscode.ProgressLocation.Notification,
      title: `PerfChecker · ${ids.length} run(s)`, cancellable: false,
    }, async report => {
      let previous = 0;
      const args = [
        `--suite=${this.absolute('suite')}`, `--factory=${this.setting('factory')}`,
        `--profile=${this.setting('profile')}`,
        `--reports=${this.absolute('reports')}`, '--progress=jsonl',
        ...this.candidateArguments(),
        ...this.comparisonArguments(),
        ...ids.flatMap(id => [`--run-id=${id}`]),
      ];
      const code = await this.invoke('run', args, value => {
        const percent = Number(value.percent ?? 0);
        report.report({increment: Math.max(percent - previous, 0),
          message: value.current_run ? `${value.current_run.package} · ${value.current_run.feature} · ${value.current_run.version}` : value.state});
        previous = percent;
        this.designer?.webview.postMessage({type: 'progress', value});
      });
      if (revealOutput) {
        const selectedRuns = this.plan?.runs.filter(run => ids.includes(run.id)) ?? [];
        await this.openOutput(undefined, selectedRuns);
      }
      if (code !== 0) throw new Error(`PerfChecker run failed with code ${code}.`);
    });
    void vscode.window.showInformationMessage('PerfChecker run completed.');
  }

  async open(nodeOrRun: PerfNode | PlanRun): Promise<void> {
    const run = nodeOrRun instanceof PerfNode ? nodeOrRun.runs[0] : nodeOrRun;
    const document = await vscode.workspace.openTextDocument(vscode.Uri.file(run.entrypoint));
    await vscode.window.showTextDocument(document, {preview: true});
  }

  private async readReport<T>(name: string): Promise<T | undefined> {
    try { return JSON.parse(await fs.readFile(path.join(this.absolute('reports'), name), 'utf8')) as T; }
    catch (error: any) {
      if (error?.code === 'ENOENT') return undefined;
      throw error;
    }
  }

  private async bundleDirectory(runId?: string): Promise<string | undefined> {
    const root = path.join(this.absolute('reports'), 'bundles');
    if (runId) {
      const expected = path.join(root, `run-${runId}`);
      try { if ((await fs.stat(expected)).isDirectory()) return expected; } catch { /* fall back to newest */ }
    }
    try {
      const entries = (await fs.readdir(root, {withFileTypes: true})).filter(entry => entry.isDirectory());
      const candidates = await Promise.all(entries.map(async entry => ({
        path: path.join(root, entry.name), modified: (await fs.stat(path.join(root, entry.name))).mtimeMs,
      })));
      return candidates.sort((a, b) => b.modified - a.modified)[0]?.path;
    } catch { return undefined; }
  }

  private async reportObservations(runs: PlanRun[], runId?: string): Promise<ProfileObservation[]> {
    const bundle = await this.bundleDirectory(runId);
    if (!bundle) return [];
    const source = path.join(bundle, 'observations.jsonl');
    try { await fs.access(source); } catch { return []; }
    const result: ProfileObservation[] = [];
    const stream = createReadStream(source, {encoding: 'utf8'});
    const lines = readline.createInterface({input: stream, crlfDelay: Infinity});
    for await (const line of lines) {
      if (!line.includes('"record_type":"observation"')) continue;
      try {
        const observation = JSON.parse(line) as ProfileObservation;
        const attributes = observation.attributes ?? {};
        const matched = runs.some(run => run.package === attributes.package && run.feature === attributes.feature &&
          (run.version === observation.target_id || run.version === attributes.version));
        if (matched) result.push(observation);
        if (result.length >= 250_000) { lines.close(); stream.destroy(); break; }
      } catch { /* diagnostics remain available in the raw report */ }
    }
    return result;
  }

  private async openReportFile(name: string): Promise<void> {
    const allowed = new Set(['suite-result.json', 'suite-report.md', 'suite-junit.xml',
      'version-series.json', 'version-comparison.json', 'version-comparison.md', 'compatibility.json']);
    if (!allowed.has(name)) return;
    const uri = vscode.Uri.file(path.join(this.absolute('reports'), name));
    try {
      await fs.access(uri.fsPath);
      if (name.endsWith('.md')) await vscode.commands.executeCommand('markdown.showPreview', uri);
      else await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(uri), {preview: true});
    } catch { void vscode.window.showWarningMessage(`PerfChecker has not produced ${name} yet.`); }
  }

  private resultPage(title: string, runs: PlanRun[], suite?: SuiteResultFile,
    versionFile?: VersionSeriesFile, comparisonFile?: VersionComparisonFile,
    observations: ProfileObservation[] = []): string {
    const nonce = this.nonce();
    const outputs = outputsForRuns(suite?.runs ?? [], runs);
    const selectedVersions = new Set(runs.map(run => run.version));
    const series = seriesForRuns(versionFile?.series ?? [], runs);
    let comparisons = comparisonsForRuns(comparisonFile?.records ?? [], runs);
    if (runs.length === 1) comparisons = comparisons.filter(record => selectedVersions.has(record.baseline_version) || selectedVersions.has(record.candidate_version));
    const definitionBackend = (definition: string): string => definition.includes('chairmarks') ? 'chairmark' :
      definition.includes('profile-allocs') || definition.includes('line-tracking') ? 'profile_alloc' :
      definition.includes('walltime') ? 'wall_profile' : definition.includes('profile-v1') ? 'profile' : 'benchmark';
    const filterAttributes = (kind: string, packageName: string, workload: string,
      backend: string, version: string, status: string, search: string): string =>
      `data-result-item data-kind="${html(kind)}" data-package="${html(packageName)}" ` +
      `data-workload="${html(workload)}" data-backend="${html(backend)}" ` +
      `data-version="${html(version)}" data-status="${html(status)}" ` +
      `data-search="${html(search.toLowerCase())}"`;
    const counts = new Map<string, number>();
    outputs.forEach(output => counts.set(output.status, (counts.get(output.status) ?? 0) + 1));
    const countCards = [...counts.entries()].map(([status, count]) =>
      `<div class="stat ${html(status)}"><strong>${count}</strong><span>${html(status)}</span></div>`).join('');
    const runCards = outputs.map(output => {
      const metrics = Object.entries(output.summary ?? {}).filter(([key]) => !['package', 'version'].includes(key));
      const values = metrics.map(([key, value]) => `<div><span>${html(key.replaceAll('_', ' '))}</span><strong>${html(formatValue(value, key))}</strong></div>`).join('');
      const workload = output.workload ?? logicalFeature({feature: output.feature, backend: runs.find(run => run.feature === output.feature)?.backend ?? 'benchmark'});
      const backend = runs.find(run => run.package === output.package && run.feature === output.feature && run.version === output.version)?.backend ?? 'benchmark';
      const attributes = filterAttributes('run', output.package, workload, backend, output.version,
        output.status, `${output.package} ${workload} ${checkLabel(backend)} ${output.version} ${output.status}`);
      return `<article class="result-card" ${attributes}><header><span class="status ${html(output.status)}">${html(output.status)}</span><div><strong>${html(output.package)} · ${html(workload)}</strong><small>${html(checkLabel(backend))} · ${html(output.version)} · ${html(output.target_kind)}</small></div><time>${html(formatSeconds(output.elapsed_seconds))}</time></header>${output.message ? `<p class="message">${html(output.message)}</p>` : ''}<div class="metrics">${values || '<span class="muted">No numeric summary for this run.</span>'}</div></article>`;
    }).join('');
    const seriesCards = series.map((item, index) => {
      const backend = definitionBackend(item.measurement_definition);
      const collector = item.measurement_definition.includes('chairmarks') ? 'Chairmarks' :
        item.measurement_definition.includes('benchmarktools') ? 'BenchmarkTools' : item.measurement_definition;
      const workload = item.workload ?? logicalFeature({feature: item.feature, backend});
      const attributes = filterAttributes('series', item.package, workload, backend,
        item.points.map(point => point.version).join(' '), '', `${item.package} ${workload} ${collector} ${item.metric}`);
      return `<article class="chart-card" ${attributes}><header><div><strong>${html(item.metric)}</strong><small>${html(item.package)} · ${html(workload)} · ${html(collector)}</small></div><span>${html(item.unit)}</span></header>${sparkline(item, selectedVersions, `series-${index}`)}<div class="version-values">${item.points.map(point => `<span class="${selectedVersions.has(point.version) ? 'current' : ''}" title="${html(`${point.samples} samples · ${point.aggregation}`)}"><b>${html(point.version)}</b> ${html(formatValue(point.median, '', item.unit))}</span>`).join('')}</div></article>`;
    }).join('');
    const visibleComparisons = comparisons.slice(0, 200);
    const comparisonRows = visibleComparisons.map(record => {
      const delta = finite(record.relative_delta) ? `${record.relative_delta >= 0 ? '+' : ''}${(record.relative_delta * 100).toFixed(1)}%` : '—';
      const workload = record.workload ?? record.feature;
      const backend = definitionBackend(record.measurement_definition ?? '');
      const attributes = filterAttributes('comparison', record.package, workload, backend,
        `${record.baseline_version} ${record.candidate_version}`, record.status,
        `${record.package} ${workload} ${record.metric} ${record.baseline_version} ${record.candidate_version} ${record.status}`);
      return `<tr ${attributes}><td>${html(record.package)} · ${html(workload)}</td><td>${html(record.metric)}</td><td>${html(record.baseline_version)} → ${html(record.candidate_version)}</td><td>${html(formatValue(record.baseline_median, '', record.unit))}</td><td>${html(formatValue(record.candidate_median, '', record.unit))}</td><td class="delta ${record.relative_delta !== null && record.relative_delta > 0 ? 'worse' : 'better'}">${html(delta)}</td><td><span class="status ${html(record.status)}">${html(record.status)}</span></td></tr>`;
    }).join('');
    const groups = new Map<string, ProfileObservation[]>();
    for (const observation of observations.filter(item => Array.isArray(item.attributes.stack))) {
      const key = `${observation.case_id}|${observation.target_id}|${observation.measurement_definition}`;
      const group = groups.get(key) ?? []; group.push(observation); groups.set(key, group);
    }
    const flames = [...groups.entries()].slice(0, 24).map(([key, group], index) => {
      const [caseId, version, definition] = key.split('|');
      const label = definition.includes('profile-allocs') ? 'Allocation flame graph' :
        definition.includes('walltime') ? 'Wall-time flame graph' : 'CPU flame graph';
      const packageName = group[0].attributes.package ?? '';
      const backend = definitionBackend(definition);
      const workload = group[0].attributes.workload ?? logicalFeature({feature: group[0].attributes.feature ?? caseId, backend});
      const attributes = filterAttributes('flame', packageName, workload, backend, version, '', `${caseId} ${version} ${label}`);
      return `<article class="flame-card" ${attributes}><header><div><strong>${label}</strong><small>${html(packageName)} · ${html(workload)} · ${html(version)}</small></div><span>${html(group[0].metric)}</span></header>${flameGraph(group, `flame-${index}`)}</article>`;
    }).join('');
    const distributions = new Map<string, ProfileObservation[]>();
    for (const observation of observations.filter(item => !item.measurement_definition.includes('profile-') && !item.measurement_definition.includes('line-tracking'))) {
      const key = `${observation.case_id}|${observation.target_id}|${observation.measurement_definition}`;
      const group = distributions.get(key) ?? []; group.push(observation); distributions.set(key, group);
    }
    const distributionCards = [...distributions.entries()].slice(0, 48).map(([key, group], index) => {
      const [caseId, version, definition] = key.split('|');
      const collector = definition.includes('chairmarks') ? 'Chairmarks' : definition.includes('benchmarktools') ? 'BenchmarkTools' : 'Samples';
      const packageName = group[0].attributes.package ?? '';
      const backend = definitionBackend(definition);
      const workload = group[0].attributes.workload ?? logicalFeature({feature: group[0].attributes.feature ?? caseId, backend});
      const attributes = filterAttributes('distribution', packageName, workload, backend, version, '', `${caseId} ${version} ${collector} ${group[0].metric}`);
      return `<article class="chart-card" ${attributes}><header><div><strong>${html(group[0].metric)} distribution</strong><small>${html(packageName)} · ${html(workload)} · ${html(version)} · ${collector}</small></div><span>${html(group[0].unit)}</span></header>${distributionPlot(group, `distribution-${index}`)}</article>`;
    }).join('');
    const allocationGroups = new Map<string, ProfileObservation[]>();
    for (const observation of observations.filter(item => item.metric === 'julia.alloc.bytes' && (item.measurement_definition.includes('profile-allocs') || item.measurement_definition.includes('line-tracking')))) {
      const key = `${observation.case_id}|${observation.target_id}|${observation.measurement_definition}`;
      const group = allocationGroups.get(key) ?? []; group.push(observation); allocationGroups.set(key, group);
    }
    const allocations = [...allocationGroups.entries()].slice(0, 24).map(([key, group], index) => {
      const [caseId, version, definition] = key.split('|');
      const packageName = group[0].attributes.package ?? '';
      const backend = definitionBackend(definition);
      const workload = group[0].attributes.workload ?? logicalFeature({feature: group[0].attributes.feature ?? caseId, backend});
      const attributes = filterAttributes('allocation', packageName, workload, backend, version, '', `${caseId} ${version} allocations`);
      return `<article class="chart-card" ${attributes}><header><div><strong>Allocation share by source line</strong><small>${html(packageName)} · ${html(workload)} · ${html(version)}</small></div><span>100%</span></header>${allocationPlot(group, `allocation-${index}`)}</article>`;
    }).join('');
    const optionList = (values: string[]): string => [...new Set(values.filter(Boolean))].sort()
      .map(value => `<option value="${html(value)}">${html(value)}</option>`).join('');
    const checkOptions = [...new Set(runs.map(run => run.backend))].sort()
      .map(value => `<option value="${html(value)}">${html(checkLabel(value))}</option>`).join('');
    const filters = `<section class="result-filters"><label>Search<input id="result-search" type="search" placeholder="Feature, metric, version…"></label><label>Package<select id="result-package"><option value="">All packages</option>${optionList(runs.map(run => run.package))}</select></label><label>Feature<select id="result-workload"><option value="">All features</option>${optionList(runs.map(logicalFeature))}</select></label><label>Check<select id="result-backend"><option value="">All checks</option>${checkOptions}</select></label><label>View<select id="result-kind"><option value="">All views</option><option value="run">Run summaries</option><option value="distribution">Distributions</option><option value="allocation">Allocations</option><option value="flame">Flame graphs</option><option value="series">Version series</option><option value="comparison">Comparisons</option></select></label><label>Status<select id="result-status"><option value="">All statuses</option><option value="pass">Pass</option><option value="error">Error</option><option value="unavailable">Unavailable</option><option value="regression">Regression</option><option value="diagnostic">Diagnostic</option></select></label><label>Sort<select id="result-sort"><option value="name">Name</option><option value="version">Version</option><option value="status">Status</option></select></label><strong id="visible-count"></strong></section>`;
    const empty = !suite ? `<section class="empty"><h2>No persisted output yet</h2><p>Run this selection first. PerfChecker will write results to <code>${html(this.absolute('reports'))}</code>.</p></section>` :
      !outputs.length ? `<section class="empty"><h2>No matching output</h2><p>The report exists, but it does not contain this package, feature or version. Run this node to refresh it.</p></section>` : '';
    return `<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'"><style nonce="${nonce}">
      :root{color-scheme:light dark;font-family:var(--vscode-font-family);color:var(--vscode-foreground);background:var(--vscode-editor-background)}body{margin:0;padding:24px}.top,.toolbar,.summary,.result-card header,.chart-card header,.flame-card header{display:flex;align-items:center}.top{justify-content:space-between;gap:20px}.top h1{margin:.2rem 0}.eyebrow{letter-spacing:.15em;color:var(--vscode-descriptionForeground);font-size:11px}.toolbar{gap:8px;flex-wrap:wrap}button{cursor:pointer;color:var(--vscode-button-foreground);background:var(--vscode-button-background);border:0;border-radius:4px;padding:7px 10px}.meta,.muted,small{color:var(--vscode-descriptionForeground)}.summary{gap:10px;margin:20px 0;flex-wrap:wrap}.stat{min-width:72px;padding:10px 14px;border:1px solid var(--vscode-panel-border);border-radius:6px;display:grid}.stat strong{font-size:20px}.result-filters{position:sticky;top:0;z-index:5;display:grid;grid-template-columns:minmax(190px,2fr) repeat(6,minmax(110px,1fr));gap:8px;align-items:end;margin:18px 0;padding:12px;border:1px solid var(--vscode-panel-border);border-radius:7px;background:var(--vscode-editor-background)}.result-filters label{display:grid;gap:4px;font-size:11px;color:var(--vscode-descriptionForeground)}.result-filters input,.result-filters select{min-width:0;padding:6px;color:var(--vscode-input-foreground);background:var(--vscode-input-background);border:1px solid var(--vscode-input-border)}#visible-count{padding:7px;white-space:nowrap}.result-list,.chart-grid,.flame-grid{display:grid;gap:12px}.chart-grid{grid-template-columns:repeat(auto-fit,minmax(350px,1fr))}.result-card,.chart-card,.flame-card,.empty{border:1px solid var(--vscode-panel-border);border-radius:7px;padding:14px;background:var(--vscode-sideBar-background)}.result-card header,.chart-card header,.flame-card header{justify-content:space-between;gap:12px}.result-card header>div,.chart-card header>div,.flame-card header>div{display:grid;gap:3px}.status{font-size:11px;padding:3px 7px;border-radius:999px;background:var(--vscode-badge-background);color:var(--vscode-badge-foreground)}.status.pass,.stat.pass{border-color:var(--vscode-testing-iconPassed)}.status.error,.status.fail,.stat.error{border-color:var(--vscode-testing-iconFailed)}.metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(125px,1fr));gap:8px;margin-top:12px}.metrics>div{display:grid;border-left:2px solid var(--vscode-focusBorder);padding-left:8px}.metrics span{color:var(--vscode-descriptionForeground);font-size:11px;text-transform:capitalize}.message,.notice{padding:8px;background:var(--vscode-textBlockQuote-background);border-left:3px solid var(--vscode-textBlockQuote-border)}section h2{margin-top:28px}.spark,.distribution{width:100%;height:110px;overflow:visible}.spark polyline{fill:none;stroke:var(--vscode-charts-blue);stroke-width:2}.spark .point,.sample{fill:var(--vscode-charts-blue)}.spark .point.current{fill:var(--vscode-charts-orange);stroke:var(--vscode-editor-background);stroke-width:2}.hover-value{outline:none;cursor:crosshair}.hover-value:hover,.hover-value:focus{stroke:var(--vscode-focusBorder);stroke-width:3;filter:brightness(1.18)}.distribution .whisker,.distribution .median{stroke:var(--vscode-foreground);stroke-width:2}.distribution .box{fill:var(--vscode-charts-blue);fill-opacity:.28;stroke:var(--vscode-charts-blue)}.plot-detail,.flame-detail{white-space:pre-wrap;min-height:34px;padding:7px;background:var(--vscode-textCodeBlock-background);border-radius:4px}.version-values{display:flex;gap:6px;flex-wrap:wrap}.version-values span{font-size:11px;padding:3px 6px;background:var(--vscode-badge-background);border-radius:4px}.version-values .current{outline:2px solid var(--vscode-focusBorder)}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:7px;border-bottom:1px solid var(--vscode-panel-border)}.table-wrap,.flame-wrap{overflow:auto}.delta.worse{color:var(--vscode-testing-iconFailed)}.delta.better{color:var(--vscode-testing-iconPassed)}.flame-card{margin-bottom:12px}.flame{min-width:800px;width:100%;height:auto}.flame-node{outline:none}.flame-node rect{fill:var(--vscode-charts-blue);stroke:var(--vscode-editor-background);stroke-width:.6}.flame-node.dynamic rect{fill:var(--vscode-charts-red)}.flame-node.unstable rect{fill:var(--vscode-charts-purple)}.flame-node.gc rect{fill:var(--vscode-charts-orange)}.flame-node:hover rect,.flame-node:focus rect{stroke:var(--vscode-focusBorder);stroke-width:2;filter:brightness(1.2)}.flame-node text{font-size:11px;fill:var(--vscode-editor-foreground);pointer-events:none}.legend{display:flex;gap:14px;flex-wrap:wrap;margin:8px 0 16px}.legend i,.allocation-legend i{display:inline-block;width:12px;height:12px;margin-right:5px;vertical-align:-2px}.legend .normal{background:var(--vscode-charts-blue)}.legend .dynamic{background:var(--vscode-charts-red)}.legend .unstable{background:var(--vscode-charts-purple)}.legend .gc{background:var(--vscode-charts-orange)}.allocation-layout{display:grid;grid-template-columns:190px 1fr;gap:12px;align-items:center}.pie{width:190px;height:190px}.allocation-legend{list-style:none;margin:0;padding:0;display:grid;gap:5px}.allocation-legend li{display:grid;grid-template-columns:auto minmax(0,1fr) auto;gap:5px;align-items:center}.allocation-legend span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}[hidden]{display:none!important}code{user-select:all}@media(max-width:1100px){.result-filters{grid-template-columns:repeat(4,minmax(120px,1fr))}}@media(max-width:700px){body{padding:14px}.top{align-items:flex-start;flex-direction:column}.result-filters{position:static;grid-template-columns:1fr 1fr}.chart-grid{grid-template-columns:1fr}.allocation-layout{grid-template-columns:1fr}}
    </style></head><body><header class="top"><div><div class="eyebrow">PERFCHECKER OUTPUT</div><h1>${html(title)}</h1><div class="meta">${suite ? `${html(suite.suite)} · ${html(suite.profile)} · ${html(suite.finished_at)}` : html(this.absolute('reports'))}</div></div><div class="toolbar"><button data-report="suite-report.md">Summary</button><button data-report="suite-result.json">JSON</button><button data-report="version-comparison.md">Comparisons</button><button data-report="version-series.json">Series JSON</button></div></header>${empty}${suite ? filters : ''}${suite ? `<div class="summary">${countCards}<div class="stat"><strong>${outputs.length}</strong><span>runs</span></div></div>` : ''}${distributionCards ? `<section><h2>Benchmark and measurement distributions</h2><div class="chart-grid">${distributionCards}</div></section>` : ''}${allocations ? `<section><h2>Allocation views</h2><div class="chart-grid">${allocations}</div></section>` : ''}${flames ? `<section><h2>Flame graphs</h2><div class="legend"><span><i class="normal"></i>Normal</span><span><i class="dynamic"></i>Runtime dispatch</span><span><i class="unstable"></i>Non-concrete inference</span><span><i class="gc"></i>GC</span></div><div class="flame-grid">${flames}</div></section>` : ''}${runCards ? `<section><h2>Run output</h2><div class="result-list">${runCards}</div></section>` : ''}${seriesCards ? `<section><h2>Version series</h2><div class="chart-grid">${seriesCards}</div></section>` : ''}${comparisonRows ? `<section><h2>Version comparisons</h2>${comparisons.length > visibleComparisons.length ? `<p class="notice">Showing ${visibleComparisons.length} of ${comparisons.length} comparisons. Open the Markdown report for all records.</p>` : ''}<div class="table-wrap"><table><thead><tr><th>Check</th><th>Metric</th><th>Versions</th><th>Baseline</th><th>Candidate</th><th>Delta</th><th>Status</th></tr></thead><tbody>${comparisonRows}</tbody></table></div></section>` : ''}<script nonce="${nonce}">const vscode=acquireVsCodeApi();document.querySelectorAll('[data-report]').forEach(button=>button.addEventListener('click',()=>vscode.postMessage({type:'report',name:button.dataset.report})));document.querySelectorAll('.flame-node,.hover-value').forEach(node=>{const show=()=>{const target=document.getElementById(node.dataset.target);if(target)target.textContent=node.dataset.detail};node.addEventListener('mouseenter',show);node.addEventListener('focus',show)});const controls=['result-search','result-package','result-workload','result-backend','result-kind','result-status','result-sort'].map(id=>document.getElementById(id)).filter(Boolean);const apply=()=>{const value=id=>document.getElementById(id)?.value||'';const query=value('result-search').trim().toLowerCase();const fields={package:value('result-package'),workload:value('result-workload'),backend:value('result-backend'),kind:value('result-kind'),status:value('result-status')};const items=[...document.querySelectorAll('[data-result-item]')];for(const item of items){const matches=(!query||item.dataset.search.includes(query))&&Object.entries(fields).every(([key,expected])=>!expected||item.dataset[key]===expected);item.hidden=!matches}const mode=value('result-sort');for(const container of document.querySelectorAll('.result-list,.chart-grid,.flame-grid,tbody')){[...container.children].sort((a,b)=>{const key=mode==='version'?'version':mode==='status'?'status':'search';return(a.dataset[key]||'').localeCompare(b.dataset[key]||'',undefined,{numeric:true})}).forEach(item=>container.appendChild(item))}const sections=new Set(items.map(item=>item.closest('section')).filter(Boolean));for(const section of sections)section.hidden=![...section.querySelectorAll('[data-result-item]')].some(item=>!item.hidden);const visible=items.filter(item=>!item.hidden).length;const counter=document.getElementById('visible-count');if(counter)counter.textContent=visible+' / '+items.length};controls.forEach(control=>control.addEventListener('input',apply));apply();</script></body></html>`;
  }

  async openOutput(nodeOrRun?: PerfNode | PlanRun, explicitRuns?: PlanRun[]): Promise<void> {
    if (!this.plan) await this.refresh();
    const runs = explicitRuns ?? (nodeOrRun instanceof PerfNode ? nodeOrRun.runs : nodeOrRun ? [nodeOrRun] : this.plan?.runs ?? []);
    const title = nodeOrRun instanceof PerfNode ? `${nodeOrRun.label} output` : nodeOrRun ?
      `${nodeOrRun.package} · ${nodeOrRun.feature} · ${nodeOrRun.version}` :
      explicitRuns ? `${runs.length} selected run${runs.length === 1 ? '' : 's'}` : `${this.plan?.suite ?? 'Suite'} output`;
    const [suite, versionFile, comparisonFile] = await Promise.all([
      this.readReport<SuiteResultFile>('suite-result.json'),
      this.readReport<VersionSeriesFile>('version-series.json'),
      this.readReport<VersionComparisonFile>('version-comparison.json'),
    ]);
    const observations = await this.reportObservations(runs, versionFile?.run_id);
    if (!this.resultsPanel) {
      this.resultsPanel = vscode.window.createWebviewPanel('perfchecker.output', 'PerfChecker output', vscode.ViewColumn.One,
        {enableScripts: true, retainContextWhenHidden: true});
      this.resultsPanel.onDidDispose(() => { this.resultsPanel = undefined; });
      this.resultsPanel.webview.onDidReceiveMessage(async message => {
        if (message.type === 'report') await this.openReportFile(String(message.name));
      });
    } else this.resultsPanel.reveal(vscode.ViewColumn.One);
    this.resultsPanel.title = title;
    this.resultsPanel.webview.html = this.resultPage(title, runs, suite, versionFile, comparisonFile, observations);
  }

  private nonce(): string { return Math.random().toString(36).slice(2) + Date.now().toString(36); }

  async openDesigner(): Promise<void> {
    if (!this.plan) await this.refresh();
    if (this.designer) { this.designer.reveal(); this.postPlan(); return; }
    this.designer = vscode.window.createWebviewPanel('perfchecker.designer', 'PerfChecker suite', vscode.ViewColumn.One,
      {enableScripts: true, retainContextWhenHidden: true});
    const nonce = this.nonce();
    const script = this.designer.webview.asWebviewUri(vscode.Uri.joinPath(this.context.extensionUri, 'media', 'designer.js'));
    const style = this.designer.webview.asWebviewUri(vscode.Uri.joinPath(this.context.extensionUri, 'media', 'designer.css'));
    this.designer.webview.html = `<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${this.designer.webview.cspSource}; script-src 'nonce-${nonce}'"><link rel="stylesheet" href="${style}"></head><body>
      <header><div><small>PERFCHECKER</small><h1>Suite editor</h1></div><div class="actions"><button id="refresh">Refresh</button><button id="results">Results</button><button id="save">Save configuration</button><button id="run" class="primary">Run selection</button></div></header>
      <section class="filters"><input id="search" placeholder="Filter package, feature or check…"><select id="package"><option value="">All packages</option></select><select id="sort"><option value="suite">Suite order</option><option value="package">Package</option><option value="feature">Feature</option><option value="version">Version</option></select><input id="from" list="versions" placeholder="From version"><input id="to" list="versions" placeholder="To version"><datalist id="versions"></datalist></section>
      <section class="check-filter"><strong>Check types</strong><div id="check-types"></div></section>
      <section class="selection-actions"><button id="select-visible">Select visible</button><button id="clear-visible">Clear visible</button><label><input id="open-after-run" type="checkbox" checked> Open visual results after the run</label></section>
      <div id="progress" hidden><div></div><span></span></div><main><section><h2>Workload runs <span id="count"></span></h2><p class="hint">A feature is the workload. BenchmarkTools, Chairmarks, allocations and profiles are selectable check types. Use ▥ for visual output and ↗ for the check script.</p><div id="cards"></div></section>
      <aside><section class="aside-panel"><h2>Comparison targets</h2><p class="hint">Measure several branches, tags, or commits beside releases and the working tree.</p><div id="target-list"></div><label>Package<select id="target-package"></select></label><label>Display label<input id="target-label" placeholder="parser-candidate-a"></label><label>Branch, tag, or commit<input id="target-revision" placeholder="feature/faster-parser or abc123"></label><label>Git source (optional)<input id="target-source" placeholder="Use the suite package source"></label><label>Compatibility version (optional)<input id="target-compatibility" placeholder="0.4.0"></label><button id="add-target">Add comparison target</button></section><section class="aside-panel"><h2>Comparison matrix</h2><p class="hint">One checked reference is an exact comparison. Several references form an aggregated reference group.</p><div id="comparison-list"></div><label>Package<select id="comparison-package"></select></label><label>Feature<select id="comparison-feature"></select></label><label>Reference aggregation<select id="comparison-aggregation"><option value="median">Median</option><option value="mean">Mean</option><option value="minimum">Minimum</option><option value="maximum">Maximum</option></select></label><h3>Reference targets</h3><div id="baseline-targets" class="target-options"></div><h3>Candidate targets</h3><div id="candidate-targets" class="target-options"></div><button id="add-comparison">Add comparison</button></section><section class="aside-panel"><h2>Documentation block</h2><label>Identifier<input id="doc-id" value="performance"></label><label>Title<input id="doc-title" value="Performance"></label><label>Interactive URL<input id="doc-url" placeholder="https://…"></label><fieldset><legend>Views</legend><label><input type="checkbox" name="view" value="summary" checked> Summary</label><label><input type="checkbox" name="view" value="comparison" checked> Comparisons</label><label><input type="checkbox" name="view" value="plots" checked> Plots</label><label><input type="checkbox" name="view" value="observations"> Observations</label><label><input type="checkbox" name="view" value="diagnostics"> Diagnostics</label><label><input type="checkbox" name="view" value="artifacts"> Artifacts</label></fieldset><p class="hint">The saved JSON is consumed by VS Code, Oxygen-compatible tooling and Documenter via <code>read_document_blocks</code>.</p></section></aside></main><script nonce="${nonce}" src="${script}"></script></body></html>`;
    this.designer.onDidDispose(() => { this.designer = undefined; });
    this.designer.webview.onDidReceiveMessage(async message => {
      if (message.type === 'open') await this.open(message.run as PlanRun);
      if (message.type === 'run') await this.run(undefined, message.ids as string[], Boolean(message.reveal));
      if (message.type === 'output') await this.openOutput(message.run as PlanRun | undefined,
        message.runs as PlanRun[] | undefined);
      if (message.type === 'refresh') await this.refresh();
      if (message.type === 'save') await this.saveConfiguration(message.configuration);
      if (message.type === 'targets') await this.updateGitTargets(message.targets as GitTarget[]);
      if (message.type === 'comparisons') await this.updateComparisonPolicies(message.comparisons as ComparisonPolicyConfig[]);
    });
    this.postPlan();
  }

  private postPlan(): void {
    if (this.plan && this.designer) void this.designer.webview.postMessage({type: 'plan', plan: this.plan,
      configuration: this.uiConfiguration, targets: this.effectiveGitTargets(),
      comparisons: this.effectiveComparisonPolicies()});
  }

  private async updateGitTargets(targets: GitTarget[]): Promise<void> {
    const normalized = targets.map(target => ({
      package: String(target.package ?? '').trim(), label: String(target.label ?? '').trim(),
      revision: String(target.revision ?? '').trim(),
      ...(String(target.source ?? '').trim() ? {source: String(target.source).trim()} : {}),
      ...(String(target.compatibility_version ?? '').trim() ?
        {compatibility_version: String(target.compatibility_version).trim()} : {}),
    }));
    if (normalized.some(target => !target.package || !target.label || !target.revision)) {
      throw new Error('Every Git target requires a package, label, and branch/tag/commit.');
    }
    const identities = normalized.map(target => `${target.package}\0${target.label}`);
    if (new Set(identities).size !== identities.length) throw new Error('Git target labels must be unique per package.');
    await vscode.workspace.getConfiguration('perfchecker').update('gitTargets', normalized,
      vscode.ConfigurationTarget.WorkspaceFolder);
    await this.refresh();
  }

  private async updateComparisonPolicies(policies: ComparisonPolicyConfig[]): Promise<void> {
    const normalized = policies.map(policy => ({
      id: String(policy.id ?? '').trim(), package: String(policy.package ?? '').trim(),
      feature: String(policy.feature ?? '').trim(), comparison_key: String(policy.comparison_key ?? '').trim(),
      baselines: [...new Set((policy.baselines ?? []).map(String).filter(Boolean))],
      candidates: [...new Set((policy.candidates ?? []).map(String).filter(Boolean))],
      aggregation: policy.aggregation ?? 'median',
    }));
    if (normalized.some(policy => !policy.id || !policy.package || !policy.comparison_key ||
      !policy.baselines.length || !policy.candidates.length)) {
      throw new Error('Each comparison needs a package, feature, reference target, and candidate target.');
    }
    if (new Set(normalized.map(policy => policy.id)).size !== normalized.length) {
      throw new Error('Comparison policy identifiers must be unique.');
    }
    await vscode.workspace.getConfiguration('perfchecker').update('comparisonPolicies', normalized,
      vscode.ConfigurationTarget.WorkspaceFolder);
    await this.refresh();
  }

  async saveConfiguration(configuration?: unknown): Promise<void> {
    if (!configuration) throw new Error('Open the visual suite editor first.');
    const destination = this.absolute('uiConfiguration');
    await fs.mkdir(path.dirname(destination), {recursive: true});
    await fs.writeFile(destination, JSON.stringify(configuration, null, 2) + '\n', 'utf8');
    this.uiConfiguration = configuration;
    void vscode.window.showInformationMessage(`Saved ${vscode.workspace.asRelativePath(destination)}`);
  }
}

export function activate(context: vscode.ExtensionContext): void {
  const tree = new PlanTree();
  const tests = vscode.tests.createTestController('perfchecker', 'PerfChecker');
  const controller = new Controller(context, tree, tests);
  tests.createRunProfile('Run', vscode.TestRunProfileKind.Run,
    request => controller.runTests(request), true);
  const view = vscode.window.createTreeView('perfchecker.runs', {treeDataProvider: tree,
    dragAndDropController: tree, manageCheckboxStateManually: true, showCollapseAll: true});
  context.subscriptions.push(view, tests, vscode.commands.registerCommand('perfchecker.refresh', () => controller.refresh()),
    vscode.commands.registerCommand('perfchecker.initialize', () => controller.initialize()),
    vscode.commands.registerCommand('perfchecker.runAll', () => controller.run(undefined, tree.plan?.runs.map(run => run.id))),
    vscode.commands.registerCommand('perfchecker.runNode', (node?: PerfNode) => controller.run(node)),
    vscode.commands.registerCommand('perfchecker.openEntrypoint', (node: PerfNode) => controller.open(node)),
    vscode.commands.registerCommand('perfchecker.openOutput', (node?: PerfNode) => controller.openOutput(node)),
    vscode.commands.registerCommand('perfchecker.showLog', () => controller.showLog()),
    vscode.commands.registerCommand('perfchecker.openDesigner', () => controller.openDesigner()),
    vscode.commands.registerCommand('perfchecker.saveConfiguration', () => controller.saveConfiguration()),
    view.onDidChangeCheckboxState(event => {
      for (const [node, state] of event.items) {
        for (const run of node.runs) state === vscode.TreeItemCheckboxState.Checked ? tree.selected.add(run.id) : tree.selected.delete(run.id);
      }
    }));
  void controller.refresh().catch(error => controller.reportError(error));
}

export function deactivate(): void {}
