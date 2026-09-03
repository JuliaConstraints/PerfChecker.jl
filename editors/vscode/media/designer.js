const vscode = acquireVsCodeApi();
let plan;
let order = [];
let selected = new Set();
let selectedChecks = new Set();
let labels = {};
let targets = [];
let comparisons = [];
const byId = id => document.getElementById(id);
const unique = values => [...new Set(values)];

const suffixes = {
  profile_alloc: ['_allocations', '_profile_alloc'], wall_profile: ['_wall_profile'],
  profile: ['_profile'], chairmark: ['_chairmark'], alloc: ['_alloc'],
  network_isolated: ['_network_isolated'], network_interface: ['_network_interface'],
  network: ['_network'],
};
const checkLabels = {
  benchmark: 'BenchmarkTools', chairmark: 'Chairmarks', alloc: 'Line allocations',
  profile_alloc: 'Allocation profile', profile: 'CPU profile',
  wall_profile: 'Wall-time profile', network: 'Network workload',
  network_interface: 'Network interface', network_isolated: 'Isolated network',
};
function logicalFeature(run) {
  if (run.workload) return run.workload;
  for (const suffix of suffixes[run.backend] || []) {
    if (run.feature.endsWith(suffix) && run.feature.length > suffix.length) return run.feature.slice(0, -suffix.length);
  }
  return run.feature;
}
function checkLabel(backend) { return checkLabels[backend] || backend.replaceAll('_', ' '); }

function compareVersion(a, b) {
  if (a === b) return 0;
  if (a === 'dev') return 1;
  if (b === 'dev') return -1;
  const parse = value => ((value.startsWith('dev@') ? value.slice(4) : value)
    .match(/^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?/) || []).slice(1).map(x => Number(x || 0));
  const x = parse(a), y = parse(b);
  if (!x.length || !y.length) return a.localeCompare(b);
  for (let i = 0; i < 3; i += 1) if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) - (y[i] || 0);
  if (a.startsWith('dev@') !== b.startsWith('dev@')) return a.startsWith('dev@') ? 1 : -1;
  return a.localeCompare(b);
}

function visibleRuns() {
  const search = byId('search').value.trim().toLowerCase();
  const packageName = byId('package').value;
  const from = byId('from').value.trim(), to = byId('to').value.trim();
  let runs = plan.runs.filter(run => selectedChecks.has(run.backend) && (!packageName || run.package === packageName) &&
    (!search || [run.package, logicalFeature(run), run.feature, checkLabel(run.backend), run.backend, run.version, run.description].some(value => value.toLowerCase().includes(search))) &&
    (run.target_kind !== 'release' || !from || compareVersion(run.version, from) >= 0) &&
    (run.target_kind !== 'release' || !to || compareVersion(run.version, to) <= 0));
  const sort = byId('sort').value;
  if (sort === 'suite') {
    const rank = new Map(order.map((id, index) => [id, index]));
    runs.sort((a, b) => rank.get(a.id) - rank.get(b.id));
  } else runs.sort((a, b) => sort === 'version' ? compareVersion(a.version, b.version) :
    a[sort].localeCompare(b[sort]) || compareVersion(a.version, b.version));
  return runs;
}

function render() {
  if (!plan) return;
  const runs = visibleRuns();
  byId('count').textContent = `${selected.size} selected · ${runs.length}/${plan.runs.length} visible`;
  const groups = [];
  const grouped = new Map();
  for (const run of runs) {
    const key = `${run.package}\u0000${logicalFeature(run)}\u0000${run.version}`;
    if (!grouped.has(key)) { const group = {key, runs: []}; grouped.set(key, group); groups.push(group); }
    grouped.get(key).runs.push(run);
  }
  const cards = byId('cards');
  cards.replaceChildren(...groups.map(group => {
    const first = group.runs[0];
    const chosen = group.runs.filter(run => selected.has(run.id)).length;
    const card = document.createElement('article');
    card.className = `card ${chosen === group.runs.length ? 'selected' : chosen ? 'partial' : ''}`;
    card.draggable = true;
    card.dataset.id = first.id;
    card.innerHTML = `<div class="feature-heading"><input class="pick" type="checkbox" aria-label="Select all checks for this feature"><div><span class="package"></span><strong></strong><span class="version"></span></div><button class="output feature-output" title="Open visual output for this feature" aria-label="Open visual output">▥</button><input class="label" type="color" title="Colour label"></div><p class="feature-description"></p><div class="check-grid"></div>`;
    const groupPick = card.querySelector('.pick');
    groupPick.checked = chosen === group.runs.length;
    groupPick.indeterminate = chosen > 0 && chosen < group.runs.length;
    card.querySelector('.package').textContent = first.package;
    card.querySelector('strong').textContent = logicalFeature(first);
    card.querySelector('.version').textContent = first.version;
    const workloadRun = group.runs.find(run => ['benchmark', 'chairmark'].includes(run.backend)) || first;
    card.querySelector('.feature-description').textContent = workloadRun.description || workloadRun.entrypoint;
    const colour = group.runs.map(run => labels[run.id]).find(Boolean) || '#6c8cff';
    card.querySelector('.label').value = colour;
    card.style.setProperty('--label', colour);
    groupPick.addEventListener('change', event => {
      group.runs.forEach(run => event.target.checked ? selected.add(run.id) : selected.delete(run.id)); render();
    });
    card.querySelector('.feature-output').addEventListener('click', () => vscode.postMessage({type: 'output', runs: group.runs}));
    card.querySelector('.label').addEventListener('input', event => {
      group.runs.forEach(run => { labels[run.id] = event.target.value; });
      card.style.setProperty('--label', event.target.value);
    });
    card.querySelector('.check-grid').replaceChildren(...group.runs.map(run => {
      const check = document.createElement('div');
      check.className = `check-option ${selected.has(run.id) ? 'selected' : ''} ${run.status}`;
      check.innerHTML = `<label><input type="checkbox"><span class="check-name"></span></label><span class="check-status"></span><button class="output" title="Open this check's visual output" aria-label="Open visual output">▥</button><button class="open" title="Open this check's script" aria-label="Open check script">↗</button>`;
      check.querySelector('input').checked = selected.has(run.id);
      check.querySelector('.check-name').textContent = checkLabel(run.backend);
      check.querySelector('.check-status').textContent = run.status;
      check.querySelector('.check-status').title = run.reason || '';
      check.querySelector('input').addEventListener('change', event => {
        event.target.checked ? selected.add(run.id) : selected.delete(run.id); render();
      });
      check.querySelector('.open').addEventListener('click', () => vscode.postMessage({type: 'open', run}));
      check.querySelector('.output').addEventListener('click', () => vscode.postMessage({type: 'output', run}));
      return check;
    }));
    card.addEventListener('dragstart', event => event.dataTransfer.setData('text/plain', JSON.stringify(group.runs.map(run => run.id))));
    card.addEventListener('dragover', event => event.preventDefault());
    card.addEventListener('drop', event => {
      event.preventDefault();
      let sources;
      try { sources = JSON.parse(event.dataTransfer.getData('text/plain')); } catch { return; }
      order = order.filter(id => !sources.includes(id));
      const target = order.indexOf(first.id);
      target < 0 ? order.push(...sources) : order.splice(target, 0, ...sources);
      render();
    });
    return card;
  }));
}

function renderTargets() {
  byId('target-list').replaceChildren(...targets.map((target, index) => {
    const item = document.createElement('div');
    item.className = 'target';
    item.innerHTML = '<span><strong></strong><small></small></span><button title="Remove comparison target" aria-label="Remove comparison target">×</button>';
    item.querySelector('strong').textContent = `${target.package} · ${target.label}`;
    item.querySelector('small').textContent = `${target.revision}${target.source ? ` · ${target.source}` : ''}`;
    item.querySelector('button').addEventListener('click', () => {
      const next = targets.filter((_, candidateIndex) => candidateIndex !== index);
      vscode.postMessage({type: 'targets', targets: next});
    });
    return item;
  }));
}

function renderComparisonList() {
  byId('comparison-list').replaceChildren(...comparisons.map((comparison, index) => {
    const item = document.createElement('div');
    item.className = 'target';
    item.innerHTML = '<span><strong></strong><small></small></span><button title="Remove comparison" aria-label="Remove comparison">×</button>';
    item.querySelector('strong').textContent = `${comparison.package} · ${comparison.feature || comparison.comparison_key}`;
    item.querySelector('small').textContent = `${comparison.baselines.join(' + ')} → ${comparison.candidates.join(', ')} · ${comparison.aggregation}`;
    item.querySelector('button').addEventListener('click', () => {
      vscode.postMessage({type: 'comparisons', comparisons: comparisons.filter((_, candidateIndex) => candidateIndex !== index)});
    });
    return item;
  }));
}

function renderComparisonOptions(resetFeature = false) {
  if (!plan) return;
  const packageName = byId('comparison-package').value;
  const featureSelect = byId('comparison-feature');
  const previous = resetFeature ? '' : featureSelect.value;
  const packageRuns = plan.runs.filter(run => run.package === packageName);
  const features = unique(packageRuns.map(logicalFeature));
  featureSelect.replaceChildren(...features.map(value => new Option(value, value)));
  if (features.includes(previous)) featureSelect.value = previous;
  const targets = unique(packageRuns.filter(run => logicalFeature(run) === featureSelect.value).map(run => run.version));
  const createOptions = (container, candidateDefaults) => {
    container.replaceChildren(...targets.map(value => {
      const run = packageRuns.find(item => item.version === value);
      const label = document.createElement('label');
      label.innerHTML = '<input type="checkbox"><span></span>';
      label.querySelector('span').textContent = value;
      label.querySelector('input').value = value;
      label.querySelector('input').checked = candidateDefaults ? run?.target_kind !== 'release' : false;
      return label;
    }));
  };
  createOptions(byId('baseline-targets'), false);
  createOptions(byId('candidate-targets'), true);
}

function configuration() {
  const runs = plan.runs.filter(run => selected.has(run.id));
  const features = unique(runs.map(run => run.feature));
  const versions = unique(runs.map(run => run.version));
  return {
    schema_version: 'perfchecker-ui-config/1', suite: plan.suite, profile: plan.profile,
    targets, comparisons,
    selection: {run_ids: order.filter(id => selected.has(id)), labels, sort: byId('sort').value},
    presentation: {open_after_run: byId('open-after-run').checked},
    documentation: {blocks: [{
      schema_version: 'perfchecker-document-block/1', id: byId('doc-id').value,
      title: byId('doc-title').value,
      query: {schema_version: 'perfchecker-query/1', id: `${byId('doc-id').value}-query`,
        resources: ['observations', 'diagnostics', 'artifacts', 'plots', 'comparison'],
        where: [
          {field: 'feature', operator: 'one_of', value: features},
          {field: 'target_id', operator: 'one_of', value: versions},
        ], order_by: [{field: 'case_id', direction: 'asc'}], limit: 0},
      views: [...document.querySelectorAll('input[name="view"]:checked')].map(input => input.value),
      interactive_url: byId('doc-url').value || null,
    }]},
  };
}

for (const id of ['search', 'package', 'sort', 'from', 'to']) byId(id).addEventListener(id === 'sort' || id === 'package' ? 'change' : 'input', render);
byId('refresh').addEventListener('click', () => vscode.postMessage({type: 'refresh'}));
byId('results').addEventListener('click', () => vscode.postMessage({type: 'output'}));
byId('select-visible').addEventListener('click', () => { visibleRuns().forEach(run => selected.add(run.id)); render(); });
byId('clear-visible').addEventListener('click', () => { visibleRuns().forEach(run => selected.delete(run.id)); render(); });
byId('run').addEventListener('click', () => vscode.postMessage({type: 'run', ids: order.filter(id => selected.has(id)), reveal: byId('open-after-run').checked}));
byId('save').addEventListener('click', () => vscode.postMessage({type: 'save', configuration: configuration()}));
byId('add-target').addEventListener('click', () => {
  const target = {
    package: byId('target-package').value,
    label: byId('target-label').value.trim(),
    revision: byId('target-revision').value.trim(),
    source: byId('target-source').value.trim(),
    compatibility_version: byId('target-compatibility').value.trim(),
  };
  if (!target.package || !target.label || !target.revision) return;
  vscode.postMessage({type: 'targets', targets: [...targets, target]});
});
byId('comparison-package').addEventListener('change', () => renderComparisonOptions(true));
byId('comparison-feature').addEventListener('change', () => renderComparisonOptions());
byId('add-comparison').addEventListener('click', () => {
  const packageName = byId('comparison-package').value;
  const feature = byId('comparison-feature').value;
  const runs = plan.runs.filter(run => run.package === packageName && logicalFeature(run) === feature);
  const comparisonKey = runs.map(run => run.comparison_key).find(Boolean) || '';
  const baselines = [...byId('baseline-targets').querySelectorAll('input:checked')].map(input => input.value);
  const candidates = [...byId('candidate-targets').querySelectorAll('input:checked')].map(input => input.value);
  if (!packageName || !feature || !comparisonKey || !baselines.length || !candidates.length) return;
  const id = `${packageName}-${feature}-${comparisons.length + 1}`.toLowerCase().replace(/[^a-z0-9_-]+/g, '-');
  vscode.postMessage({type: 'comparisons', comparisons: [...comparisons, {
    id, package: packageName, feature, comparison_key: comparisonKey, baselines, candidates,
    aggregation: byId('comparison-aggregation').value,
  }]});
});
window.addEventListener('message', event => {
  if (event.data.type === 'plan') {
    plan = event.data.plan;
    targets = event.data.targets || [];
    comparisons = event.data.comparisons || [];
    const saved = event.data.configuration;
    const known = new Set(plan.runs.map(run => run.id));
    const savedOrder = (saved?.selection?.run_ids || []).filter(id => known.has(id));
    order = [...savedOrder, ...plan.runs.map(run => run.id).filter(id => !savedOrder.includes(id))];
    selected = new Set(saved ? savedOrder : order);
    labels = saved?.selection?.labels || {};
    byId('open-after-run').checked = saved?.presentation?.open_after_run ?? true;
    if (saved?.selection?.sort) byId('sort').value = saved.selection.sort;
    const block = saved?.documentation?.blocks?.[0];
    if (block) {
      byId('doc-id').value = block.id; byId('doc-title').value = block.title;
      byId('doc-url').value = block.interactive_url || '';
      document.querySelectorAll('input[name="view"]').forEach(input => { input.checked = block.views.includes(input.value); });
    }
    const select = byId('package');
    select.replaceChildren(new Option('All packages', ''), ...unique(plan.runs.map(run => run.package)).map(value => new Option(value, value)));
    byId('target-package').replaceChildren(...unique(plan.runs.map(run => run.package)).map(value => new Option(value, value)));
    byId('comparison-package').replaceChildren(...unique(plan.runs.map(run => run.package)).map(value => new Option(value, value)));
    byId('versions').replaceChildren(...unique(plan.runs.map(run => run.version))
      .sort(compareVersion).map(value => new Option(value, value)));
    const checks = unique(plan.runs.map(run => run.backend));
    selectedChecks = new Set(checks.filter(backend =>
      plan.runs.some(run => run.backend === backend && selected.has(run.id))));
    byId('check-types').replaceChildren(...checks.map(backend => {
      const label = document.createElement('label');
      label.className = 'check-type';
      label.innerHTML = '<input type="checkbox"><span></span>';
      label.querySelector('input').checked = selectedChecks.has(backend);
      label.querySelector('span').textContent = checkLabel(backend);
      label.querySelector('input').addEventListener('change', event => {
        const matching = plan.runs.filter(run => run.backend === backend);
        if (event.target.checked) {
          selectedChecks.add(backend);
          matching.forEach(run => selected.add(run.id));
        } else {
          selectedChecks.delete(backend);
          matching.forEach(run => selected.delete(run.id));
        }
        render();
      });
      return label;
    }));
    renderTargets();
    renderComparisonList();
    renderComparisonOptions(true);
    for (const id of ['target-label', 'target-revision', 'target-source', 'target-compatibility']) byId(id).value = '';
    render();
  }
  if (event.data.type === 'progress') {
    const value = event.data.value, progress = byId('progress'); progress.hidden = false;
    progress.querySelector('div').style.width = `${value.percent || 0}%`;
    progress.querySelector('span').textContent = `${Math.round(value.percent || 0)}% · ${value.state}`;
  }
});
