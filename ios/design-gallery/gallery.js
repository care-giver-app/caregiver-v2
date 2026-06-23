const root = document.documentElement;
let tokens = null;

async function loadTokens() {
  const res = await fetch('tokens.json');
  if (!res.ok) throw new Error(`Failed to load tokens.json: ${res.status}`);
  return res.json();
}

function applyPalette(name) {
  const palette = tokens.palettes[name];
  if (!palette) return;
  for (const [key, hex] of Object.entries(palette)) {
    root.style.setProperty(`--color-${key}`, hex);
  }
  root.dataset.palette = name;
  const select = document.getElementById('palette-select');
  if (select.value !== name) select.value = name;
}

function applyScales(scales) {
  for (const [key, px] of Object.entries(scales.spacing)) {
    root.style.setProperty(`--space-${key}`, `${px}px`);
  }
  for (const [key, px] of Object.entries(scales.radius)) {
    root.style.setProperty(`--radius-${key}`, `${px}px`);
  }
}

function renderColors(palette) {
  const host = document.getElementById('tokens-colors');
  host.innerHTML = '';
  for (const [key, hex] of Object.entries(palette)) {
    const cell = document.createElement('div');
    cell.className = 'swatch';
    cell.innerHTML =
      `<div class="swatch__chip" style="background:${hex}"></div>` +
      `<div class="swatch__name">${key}</div>` +
      `<div class="swatch__hex">${hex}</div>`;
    host.appendChild(cell);
  }
}

function renderScaleRows(hostId, scale, unit) {
  const host = document.getElementById(hostId);
  host.innerHTML = '';
  for (const [key, px] of Object.entries(scale)) {
    const row = document.createElement('div');
    row.className = 'scale-row';
    const bar =
      unit === 'radius'
        ? `<span class="radius-sample" style="border-radius:${px}px"></span>`
        : `<span class="scale-row__bar" style="width:${px}px"></span>`;
    row.innerHTML = `${bar}<span class="scale-row__label">${key} — ${px}px</span>`;
    host.appendChild(row);
  }
}

function renderType(type) {
  const host = document.getElementById('tokens-type');
  host.innerHTML = '';
  for (const [key, spec] of Object.entries(type)) {
    const row = document.createElement('div');
    row.style.fontSize = `${spec.size}px`;
    row.style.fontWeight = spec.weight;
    row.style.color = 'var(--color-textPrimary)';
    row.textContent = `${key} — ${spec.size}px / ${spec.weight}`;
    host.appendChild(row);
  }
}

function renderGradient(palette, gradients) {
  const host = document.getElementById('tokens-gradient');
  host.innerHTML = '';
  const [from, to] = gradients.earth;
  const sample = document.createElement('div');
  sample.className = 'gradient-sample';
  sample.style.background = `linear-gradient(to bottom, ${palette[from]}, ${palette[to]})`;
  host.appendChild(sample);
}

function renderTokens() {
  const name = root.dataset.palette;
  const palette = tokens.palettes[name];
  renderColors(palette);
  renderScaleRows('tokens-spacing', tokens.scales.spacing, 'spacing');
  renderScaleRows('tokens-radius', tokens.scales.radius, 'radius');
  renderType(tokens.scales.type);
  renderGradient(palette, tokens.gradients);
}

function populatePaletteSelect() {
  const select = document.getElementById('palette-select');
  select.innerHTML = '';
  for (const name of Object.keys(tokens.palettes)) {
    const opt = document.createElement('option');
    opt.value = name;
    opt.textContent = name;
    select.appendChild(opt);
  }
  select.addEventListener('change', () => {
    applyPalette(select.value);
    renderTokens();
  });
  document.getElementById('toggle-light').addEventListener('click', () => {
    applyPalette('light');
    renderTokens();
  });
  document.getElementById('toggle-dark').addEventListener('click', () => {
    applyPalette('dark');
    renderTokens();
  });
}

async function init() {
  tokens = await loadTokens();
  applyScales(tokens.scales);
  populatePaletteSelect();
  applyPalette('light');
  renderTokens();
}

init();
