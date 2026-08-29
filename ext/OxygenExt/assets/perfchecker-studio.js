(() => {
  'use strict';
  const body = document.body;
  const base = body.dataset.apiBase || '';
  const writable = body.dataset.mode === 'workspace';
  const authRequired = body.dataset.authRequired === 'true';
  const $ = selector => document.querySelector(selector);
  const $$ = selector => Array.from(document.querySelectorAll(selector));
  const state = { plan: null, selected: [], dragged: null, series: [], comparison: null,
    plots: [], currentRun: null,
    token: window.sessionStorage.getItem('perfchecker-token') || '', started: false };

  async function api(path, options = {}) {
    const headers = new Headers(options.headers || {});
    if (state.token) headers.set('Authorization', `Bearer ${state.token}`);
    const response = await fetch(base + path, { ...options, headers });
    const payload = await response.json();
    if (response.status === 401 && authRequired) $('#login-dialog').showModal();
    if (!response.ok) throw new Error(payload.error || `Request failed (${response.status})`);
    return payload;
  }
  function announce(message) { $('#announcer').textContent = message; }
  function toast(message) {
    const node = $('#toast'); node.textContent = message; node.hidden = false;
    window.clearTimeout(toast.timer); toast.timer = window.setTimeout(() => node.hidden = true, 4200);
  }
  function showView(name) {
    $$('.view').forEach(view => view.hidden = view.dataset.view !== name);
    $$('[data-view-target]').forEach(button => {
      const active = button.dataset.viewTarget === name;
      if (active) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current');
    });
    if (name === 'jobs' && writable) loadJobs();
    if (name === 'results') loadResults();
  }
  $$('[data-view-target]').forEach(button => button.addEventListener('click', () => showView(button.dataset.viewTarget)));

  function runText(run) { return `${run.package} ${run.feature} ${run.version} ${run.backend}`.toLowerCase(); }
  function moveSelected(id, offset) {
    const index = state.selected.indexOf(id); if (index < 0) return;
    const target = Math.max(0, Math.min(state.selected.length - 1, index + offset));
    state.selected.splice(index, 1); state.selected.splice(target, 0, id);
    renderPlan(id); announce(`Moved run to position ${target + 1}`);
  }
  function selectRun(id, selected, beforeId = null) {
    state.selected = state.selected.filter(item => item !== id);
    if (selected) {
      const before = beforeId ? state.selected.indexOf(beforeId) : -1;
      if (before >= 0) state.selected.splice(before, 0, id); else state.selected.push(id);
    }
    renderPlan(id); announce(selected ? 'Run added to execution order' : 'Run removed from execution order');
  }
  function runCard(run, selected) {
    const item = document.createElement(selected ? 'li' : 'div');
    item.className = `run-card${run.status === 'unavailable' ? ' unavailable' : ''}`;
    item.dataset.runId = run.id; item.draggable = true; item.tabIndex = 0;
    const handle = document.createElement('span'); handle.className = 'drag-handle'; handle.textContent = '⠿'; handle.setAttribute('aria-hidden', 'true');
    const copy = document.createElement('div'); copy.className = 'run-copy';
    const title = document.createElement('strong'); title.textContent = `${run.package} · ${run.feature}`;
    const detail = document.createElement('small'); detail.textContent = `${run.version} · ${run.backend}${run.status === 'unavailable' ? ' · unavailable' : ''}`;
    copy.append(title, detail);
    const actions = document.createElement('div'); actions.className = 'run-actions';
    if (selected) {
      [['↑', -1, 'Move up'], ['↓', 1, 'Move down']].forEach(([label, offset, titleText]) => {
        const button = document.createElement('button'); button.type = 'button'; button.textContent = label; button.title = titleText;
        button.addEventListener('click', () => moveSelected(run.id, offset)); actions.append(button);
      });
    }
    const toggle = document.createElement('button'); toggle.type = 'button'; toggle.textContent = selected ? '−' : '+';
    toggle.title = selected ? 'Remove' : 'Add'; toggle.addEventListener('click', () => selectRun(run.id, !selected)); actions.append(toggle);
    item.append(handle, copy, actions);
    item.addEventListener('dragstart', event => { state.dragged = run.id; item.classList.add('dragging'); event.dataTransfer.effectAllowed = 'move'; event.dataTransfer.setData('text/plain', run.id); });
    item.addEventListener('dragend', () => { state.dragged = null; item.classList.remove('dragging'); $$('.drop-zone').forEach(zone => zone.classList.remove('drag-over')); });
    item.addEventListener('keydown', event => {
      if (!selected && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); selectRun(run.id, true); }
      if (selected && event.key === 'Delete') { event.preventDefault(); selectRun(run.id, false); }
      if (selected && event.altKey && event.key === 'ArrowUp') { event.preventDefault(); moveSelected(run.id, -1); }
      if (selected && event.altKey && event.key === 'ArrowDown') { event.preventDefault(); moveSelected(run.id, 1); }
    });
    return item;
  }
  function renderPlan(focusId = null) {
    if (!state.plan) return;
    const query = ($('#plan-filter')?.value || '').trim().toLowerCase();
    const selectedSet = new Set(state.selected);
    const available = state.plan.runs.filter(run => !selectedSet.has(run.id) && (!query || runText(run).includes(query)));
    const ordered = state.selected.map(id => state.plan.runs.find(run => run.id === id)).filter(Boolean).filter(run => !query || runText(run).includes(query));
    $('#available-runs').replaceChildren(...available.map(run => runCard(run, false)));
    $('#selected-runs').replaceChildren(...ordered.map(run => runCard(run, true)));
    $('#plan-summary').textContent = `${state.selected.length}/${state.plan.runs.length} selected`;
    $('#plan-revision').textContent = `Plan ${state.plan.plan_revision.slice(0, 12)} · ${state.plan.profile}`;
    $('#launch-job').disabled = state.selected.length === 0;
    if (focusId) document.querySelector(`[data-run-id="${CSS.escape(focusId)}"]`)?.focus();
  }
  function installDropZones() {
    $$('.drop-zone').forEach(zone => {
      zone.addEventListener('dragover', event => { event.preventDefault(); zone.classList.add('drag-over'); event.dataTransfer.dropEffect = 'move'; });
      zone.addEventListener('dragleave', event => { if (!zone.contains(event.relatedTarget)) zone.classList.remove('drag-over'); });
      zone.addEventListener('drop', event => {
        event.preventDefault(); zone.classList.remove('drag-over');
        const id = state.dragged || event.dataTransfer.getData('text/plain'); if (!id) return;
        const target = event.target.closest('.run-card');
        selectRun(id, zone.dataset.zone === 'selected', target?.dataset.runId || null);
      });
    });
  }
  async function loadPlan() {
    try {
      const profile = $('#profile').value;
      state.plan = await api(`/suite-plan?profile=${encodeURIComponent(profile)}`);
      state.selected = state.plan.runs.map(run => run.id);
      renderPlan(); announce(`Loaded ${state.plan.runs.length} planned runs`);
    } catch (error) { toast(error.message); }
  }
  async function loadAgents() {
    try {
      const agents = await api('/agents');
      const picker = $('#execution-target');
      picker.querySelectorAll('option[data-agent]').forEach(option => option.remove());
      agents.forEach(agent => {
        const option = document.createElement('option'); option.dataset.agent = 'true';
        option.value = `agent:${agent.agent_id}`;
        option.textContent = `${agent.agent_id} · ${agent.state}`; picker.append(option);
      });
    } catch (error) { toast(error.message); }
  }
  async function launchJob() {
    const number = id => Number($(id).value);
    const payload = {
      profile: state.plan.profile, plan_revision: state.plan.plan_revision,
      execution_target: $('#execution-target').value,
      selected_run_ids: state.selected,
      overrides: { samples: number('#samples'), seconds: number('#seconds'), evals: number('#evals'), threads: number('#threads') },
      relative_limits: { 'julia.wall.time': number('#limit-time') / 100, 'julia.alloc.bytes': number('#limit-bytes') / 100 },
      min_samples: 1
    };
    try {
      const job = await api('/jobs', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      toast(`Job ${job.job_id.slice(0, 8)} queued`); showView('jobs');
    } catch (error) { toast(error.message); if (error.message.includes('stale')) loadPlan(); }
  }
  async function loadJobs() {
    if (!writable) return;
    try {
      const jobs = await api('/jobs');
      $('#jobs').replaceChildren(...jobs.map(job => {
        const card = document.createElement('article'); card.className = 'panel job-card';
        const header = document.createElement('header'); const title = document.createElement('strong'); title.textContent = `Job ${job.job_id.slice(0, 8)}`;
        const status = document.createElement('span'); status.className = `status ${job.state}`; status.textContent = job.state; header.append(title, status);
        const detail = document.createElement('p'); detail.textContent = `${job.profile} · ${job.run_count} runs · ${job.execution_target}`;
        const message = document.createElement('small'); message.textContent = job.message || job.started_at || job.created_at;
        card.append(header, detail, message); return card;
      }));
    } catch (error) { toast(error.message); }
  }

  function resultButton(run) {
    const button = document.createElement('button'); button.type = 'button';
    const title = document.createElement('strong'); title.textContent = run.suite || 'Performance run';
    const detail = document.createElement('small'); detail.textContent = `${run.profile || ''} · ${run.state} · ${String(run.run_id).slice(0, 8)}`;
    button.append(title, detail); button.addEventListener('click', () => loadComparison(run.run_id)); return button;
  }
  async function loadResults() {
    try {
      const results = await api('/results');
      results.sort((a, b) => String(b.finished_at || '').localeCompare(String(a.finished_at || '')));
      $('#results').replaceChildren(...results.map(resultButton));
      if (!results.length) $('#results').textContent = 'No completed bundles yet.';
    } catch (error) { toast(error.message); }
  }
  function formatValue(value) {
    if (!Number.isFinite(Number(value))) return '—';
    const number = Number(value); return Math.abs(number) >= 1000 ? number.toExponential(3) : number.toPrecision(4);
  }
  function renderChart(series) {
    const host = $('#series-chart'); host.replaceChildren();
    const points = series?.points || []; if (!points.length) return;
    const width = Math.max(720, points.length * 72), height = 280, left = 68, right = 28, top = 24, bottom = 52;
    const values = points.map(point => Number(point.median)); const min = Math.min(...values), max = Math.max(...values); const span = max - min || 1;
    const x = index => left + (points.length === 1 ? (width - left - right) / 2 : index * (width - left - right) / (points.length - 1));
    const y = value => top + (max - value) * (height - top - bottom) / span;
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); svg.setAttribute('viewBox', `0 0 ${width} ${height}`); svg.setAttribute('width', width); svg.setAttribute('aria-label', `${series.package} ${series.feature} ${series.metric} over versions`);
    const axis = document.createElementNS(svg.namespaceURI, 'path'); axis.setAttribute('d', `M${left},${top}V${height-bottom}H${width-right}`); axis.setAttribute('class', 'axis'); axis.setAttribute('fill', 'none'); svg.append(axis);
    const line = document.createElementNS(svg.namespaceURI, 'polyline'); line.setAttribute('points', points.map((point, index) => `${x(index)},${y(point.median)}`).join(' ')); line.setAttribute('class', 'series-line'); line.setAttribute('fill', 'none'); svg.append(line);
    points.forEach((point, index) => {
      const circle = document.createElementNS(svg.namespaceURI, 'circle'); circle.setAttribute('cx', x(index)); circle.setAttribute('cy', y(point.median)); circle.setAttribute('r', 5); circle.setAttribute('class', 'series-point'); svg.append(circle);
      const label = document.createElementNS(svg.namespaceURI, 'text'); label.setAttribute('x', x(index)); label.setAttribute('y', height - 24); label.setAttribute('text-anchor', 'middle'); label.textContent = point.version; svg.append(label);
      const value = document.createElementNS(svg.namespaceURI, 'text'); value.setAttribute('x', x(index)); value.setAttribute('y', Math.max(14, y(point.median) - 10)); value.setAttribute('text-anchor', 'middle'); value.textContent = formatValue(point.median); svg.append(value);
    });
    host.append(svg);
  }
  function renderComparisonTable(series) {
    const records = (state.comparison?.records || []).filter(record => record.series_id === series.series_id);
    const table = document.createElement('table'); const head = document.createElement('thead'); const row = document.createElement('tr');
    ['Relation', 'Baseline', 'Candidate', 'Delta', 'Status'].forEach(label => { const th = document.createElement('th'); th.textContent = label; row.append(th); }); head.append(row); table.append(head);
    const bodyNode = document.createElement('tbody'); records.forEach(record => {
      const tr = document.createElement('tr'); const delta = record.relative_delta == null ? '—' : `${(record.relative_delta * 100).toFixed(2)}%`;
      [record.relation, record.baseline_version, record.candidate_version, delta, record.status].forEach((value, index) => { const td = document.createElement('td'); td.textContent = value; if (index === 4) td.className = `status ${record.status}`; tr.append(td); }); bodyNode.append(tr);
    }); table.append(bodyNode); $('#comparison-table').replaceChildren(table);
  }
  function plotLabel(plot) {
    return `${plot.label} — ${plot.package || ''} · ${plot.feature || ''} · ${plot.metric || ''}`;
  }
  async function showPlot(resetVersion = false) {
    const picker = $('#plot-picker'); const plot = state.plots[Number(picker.value)];
    if (!plot || !state.currentRun) return;
    const versionPicker = $('#plot-version');
    if (resetVersion) versionPicker.value = '';
    let query = `id=${encodeURIComponent(state.currentRun)}&plot=${encodeURIComponent(plot.id)}&top=40`;
    if (versionPicker.value) query += `&version=${encodeURIComponent(versionPicker.value)}`;
    try {
      const payload = await api(`/plot-data?${query}`);
      const versions = payload.options?.versions || [];
      if (versions.length) {
        const selected = payload.options.selected_version || versionPicker.value || versions[versions.length - 1];
        versionPicker.replaceChildren(...versions.map(version => {
          const option = document.createElement('option'); option.value = version; option.textContent = version;
          option.selected = version === selected; return option;
        }));
        $('#plot-version-label').hidden = false;
        query = `id=${encodeURIComponent(state.currentRun)}&plot=${encodeURIComponent(plot.id)}&top=40&version=${encodeURIComponent(selected)}`;
      } else {
        $('#plot-version-label').hidden = true; versionPicker.replaceChildren();
      }
      const frame = $('#makie-frame'); frame.hidden = false;
      frame.src = `${base}/plot?${query}`;
      $('#series-chart').hidden = true;
      const series = state.series.find(item => item.series_id === plot.series_id);
      if (series) renderComparisonTable(series); else $('#comparison-table').replaceChildren();
      announce(`Showing ${plot.label}`);
    } catch (error) { toast(error.message); }
  }
  async function loadComparison(id) {
    try {
      const [bundle, comparison, catalog] = await Promise.all([api(`/results?id=${encodeURIComponent(id)}`), api(`/version-comparison?id=${encodeURIComponent(id)}`), api(`/plots?id=${encodeURIComponent(id)}`)]);
      state.currentRun = id; state.comparison = comparison; state.series = comparison.series || []; state.plots = catalog.plots || [];
      const summary = document.createElement('div'); summary.className = 'result-summary';
      [`${bundle.manifest.suite}`, `${state.series.length} series`, `${comparison.records.length} comparisons`, `${state.plots.length} Makie plots`, `${bundle.observations.length} observations`].forEach(text => { const strong = document.createElement('strong'); strong.textContent = text; summary.append(strong); }); $('#result-summary').replaceWith(summary); summary.id = 'result-summary';
      const picker = $('#plot-picker'); picker.replaceChildren(...state.plots.map((plot, index) => { const option = document.createElement('option'); option.value = index; option.textContent = plotLabel(plot); return option; }));
      const preferred = state.plots.findIndex(plot => plot.kind === 'version_series' && plot.metric === 'julia.wall.time');
      picker.value = String(preferred >= 0 ? preferred : 0);
      $('#plot-picker-label').hidden = !state.plots.length;
      picker.onchange = () => showPlot(true);
      $('#plot-version').onchange = () => showPlot(false);
      if (state.plots.length) showPlot(true); else {
        $('#makie-frame').hidden = true; $('#comparison-table').replaceChildren();
      }
    } catch (error) { toast(error.message); }
  }

  function startStudio() {
    if (state.started) return;
    state.started = true;
    if (writable) {
    $('#profile').addEventListener('change', loadPlan); $('#plan-filter').addEventListener('input', () => renderPlan());
    $('#select-all').addEventListener('click', () => { state.selected = state.plan.runs.map(run => run.id); renderPlan(); });
    $('#clear-selection').addEventListener('click', () => { state.selected = []; renderPlan(); });
    $('#launch-job').addEventListener('click', launchJob); installDropZones(); loadPlan(); loadAgents();
    window.setInterval(() => { if (!$('[data-view="jobs"]').hidden) loadJobs(); }, 2000);
      showView('configure');
    } else showView('results');
    $('#refresh-results').addEventListener('click', loadResults);
  }

  async function authenticate() {
    try {
      const account = await api('/me');
      if (authRequired) await api('/session', { method: 'POST' });
      const identity = account.identity || {};
      $('#current-user').textContent = identity.name || identity.id || 'Authenticated';
      $('#login-error').textContent = '';
      $('#login-dialog').open && $('#login-dialog').close();
      return true;
    } catch (error) {
      $('#login-error').textContent = error.message;
      return false;
    }
  }

  $('#login-form').addEventListener('submit', async event => {
    event.preventDefault();
    state.token = $('#access-token').value.trim();
    window.sessionStorage.setItem('perfchecker-token', state.token);
    if (await authenticate()) startStudio();
  });

  if (authRequired) {
    if (state.token) authenticate().then(ok => ok ? startStudio() : $('#login-dialog').showModal());
    else $('#login-dialog').showModal();
  } else startStudio();
})();
