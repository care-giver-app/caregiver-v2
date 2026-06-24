const root = document.documentElement;
let tokens = null;

// Palette-dependent token hosts that render literal hex (re-rendered on palette change).
let colorHost = null;
let gradientHost = null;

async function loadTokens() {
  const res = await fetch('tokens.json');
  if (!res.ok) throw new Error(`Failed to load tokens.json: ${res.status}`);
  return res.json();
}

function applyScales(scales) {
  for (const [key, px] of Object.entries(scales.spacing)) {
    root.style.setProperty(`--space-${key}`, `${px}px`);
  }
  for (const [key, px] of Object.entries(scales.radius)) {
    root.style.setProperty(`--radius-${key}`, `${px}px`);
  }
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
  // CSS-variable-driven content re-themes automatically; only literal-hex token
  // displays need an explicit re-render.
  if (colorHost) renderColors(colorHost, palette);
  if (gradientHost) renderGradient(gradientHost, palette);
}

// ---- token renderers (write into a passed host element) ----

function renderColors(host, palette) {
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

function renderScaleRows(host, scale, unit) {
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

function renderType(host, type) {
  host.innerHTML = '';
  for (const [key, spec] of Object.entries(type)) {
    const row = document.createElement('div');
    row.style.fontSize = `${spec.size}px`;
    row.style.fontWeight = String(spec.weight);
    row.style.color = 'var(--color-textPrimary)';
    row.textContent = `${key} — ${spec.size}px / ${spec.weight}`;
    host.appendChild(row);
  }
}

function renderGradient(host, palette) {
  host.innerHTML = '';
  const [from, to] = tokens.gradients.earth;
  const sample = document.createElement('div');
  sample.className = 'gradient-sample';
  sample.style.background = `linear-gradient(to bottom, ${palette[from]}, ${palette[to]})`;
  host.appendChild(sample);
}

// ---- slide builders ----

function makeSlide(title) {
  const slide = document.createElement('section');
  slide.className = 'slide';
  const header = document.createElement('header');
  header.className = 'slide__header';
  const h = document.createElement('h2');
  h.className = 'slide__title';
  h.textContent = title;
  header.appendChild(h);
  slide.appendChild(header);
  return { slide, header };
}

// Token slide: header + scrolling body. Returns the body host element.
function addTokenSlide(title, bodyClass) {
  const { slide } = makeSlide(title);
  const body = document.createElement('div');
  body.className = bodyClass ? `slide__body ${bodyClass}` : 'slide__body';
  slide.appendChild(body);
  document.getElementById('slides').appendChild(slide);
  return body;
}

// Component slide: header (+ toggle if >1 variation), earthy stage, code line.
function addComponentSlide(component) {
  const { slide, header } = makeSlide(component.name);
  const stage = document.createElement('div');
  stage.className = 'slide__stage earth-bg';
  const code = document.createElement('pre');
  code.className = 'slide__code';

  function show(variation) {
    stage.innerHTML = variation.html;
    code.textContent = variation.code;
  }

  if (component.variations.length > 1) {
    const toggle = document.createElement('div');
    toggle.className = 'slide__toggle';
    toggle.setAttribute('role', 'group');
    component.variations.forEach((variation, i) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.textContent = variation.label;
      btn.setAttribute('aria-pressed', i === 0 ? 'true' : 'false');
      btn.addEventListener('click', () => {
        toggle.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', 'false'));
        btn.setAttribute('aria-pressed', 'true');
        show(variation);
      });
      toggle.appendChild(btn);
    });
    header.appendChild(toggle);
  }

  slide.appendChild(stage);
  slide.appendChild(code);
  document.getElementById('slides').appendChild(slide);
  show(component.variations[0]);
}

// ---- component manifest ----

const COMPONENTS = [
  {
    name: 'Button',
    variations: [
      {
        label: 'Primary',
        html: `<button class="btn-primary">Save</button>`,
        code: `StrideButton(title: "Save") { }`,
      },
      {
        label: 'Pri · Pressed',
        html: `<button class="btn-primary is-pressed">Save</button>`,
        code: `// pressed state`,
      },
      {
        label: 'Pri · Disabled',
        html: `<button class="btn-primary is-disabled">Save</button>`,
        code: `StrideButton(title: "Save") { }.disabled(true)`,
      },
      {
        label: 'Pri · Loading',
        html: `<button class="btn-primary">⏳ Loading…</button>`,
        code: `StrideButton(title: "Save", isLoading: true) { }`,
      },
      {
        label: 'Secondary',
        html: `<button class="btn-secondary">Cancel</button>`,
        code: `StrideButton(title: "Cancel", style: .secondary) { }`,
      },
      {
        label: 'Sec · Disabled',
        html: `<button class="btn-secondary is-disabled">Cancel</button>`,
        code: `StrideButton(title: "Cancel", style: .secondary) { }.disabled(true)`,
      },
    ],
  },
  {
    name: 'Field',
    variations: [
      {
        label: 'Plain',
        html: `<div class="glass-field"><span class="glass-field__placeholder">Email</span></div>`,
        code: `StrideField(placeholder: "Email", text: $email)`,
      },
      {
        label: 'With icon',
        html: `<div class="glass-field"><span class="glass-field__icon">✉</span><span class="glass-field__placeholder">Email</span></div>`,
        code: `StrideField(placeholder: "Email", icon: "envelope", text: $email)`,
      },
      {
        label: 'Secure',
        html: `<div class="glass-field"><span class="glass-field__icon">🔒</span><span class="glass-field__placeholder">••••••••</span></div>`,
        code: `StrideField(placeholder: "Password", isSecure: true, text: $pw)`,
      },
    ],
  },
  {
    name: 'Card',
    variations: [
      {
        label: 'Default',
        html: `<div class="glass-card">A card surface.</div>`,
        code: `SomeView().strideCard()`,
      },
    ],
  },
  {
    name: 'Empty State',
    variations: [
      {
        label: 'Default',
        html: `<div class="empty-state">No activity yet.</div>`,
        code: `StrideEmptyState(message: "No activity yet.")`,
      },
    ],
  },
  {
    name: 'Error State',
    variations: [
      {
        label: 'Default',
        html: `<div class="error-state"><span>Something went wrong.</span><button class="btn-secondary" style="max-width:200px">Try again</button></div>`,
        code: `StrideErrorState(message: "…") { retry() }`,
      },
    ],
  },
  {
    name: 'Loading',
    variations: [
      {
        label: 'Default',
        html: `<div class="loading-state">Loading…</div>`,
        code: `StrideLoadingView()`,
      },
    ],
  },
  {
    name: 'Timeline',
    variations: [
      {
        label: 'Read-only',
        html: `<div class="timeline">
  <div class="tl-row">
    <div class="tl-gutter"><span class="tl-gutter__icon" style="color: var(--color-tertiary)">☀</span><span class="tl-gutter__text">8:15 AM</span></div>
    <div class="tl-rail"><span class="tl-rail__line tl-rail__top"></span><span class="tl-dot" style="background: var(--color-accent)"></span><span class="tl-rail__line tl-rail__bottom"></span></div>
    <div class="tl-content"><div class="tl-title">Morning meds</div><div class="tl-desc">Lisinopril 10mg</div></div>
  </div>
  <div class="tl-row">
    <div class="tl-gutter"><span class="tl-gutter__icon" style="color: var(--color-tertiary)">☀</span><span class="tl-gutter__text">1:30 PM</span></div>
    <div class="tl-rail"><span class="tl-rail__line tl-rail__top"></span><span class="tl-dot" style="background: var(--color-tertiary)"></span><span class="tl-rail__line tl-rail__bottom"></span></div>
    <div class="tl-content"><div class="tl-title">Blood pressure</div><div class="tl-desc">128/82</div></div>
  </div>
  <div class="tl-row">
    <div class="tl-gutter"><span class="tl-gutter__icon" style="color: var(--color-textSecondary)">☾</span><span class="tl-gutter__text">9:45 PM</span></div>
    <div class="tl-rail"><span class="tl-rail__line tl-rail__top"></span><span class="tl-dot" style="background: var(--color-highlight)"></span><span class="tl-rail__line tl-rail__bottom"></span></div>
    <div class="tl-content"><div class="tl-title">Walk</div><div class="tl-desc">20 min around the block</div></div>
  </div>
</div>`,
        code: `Timeline(nodes: nodes)`,
      },
      {
        label: 'Tappable',
        html: `<div class="timeline">
  <div class="tl-row tl-row--tappable">
    <div class="tl-gutter"><span class="tl-gutter__icon" style="color: var(--color-tertiary)">☀</span><span class="tl-gutter__text">8:15 AM</span></div>
    <div class="tl-rail"><span class="tl-rail__line tl-rail__top"></span><span class="tl-dot" style="background: var(--color-accent)"></span><span class="tl-rail__line tl-rail__bottom"></span></div>
    <div class="tl-content"><div class="tl-title">Morning meds</div><div class="tl-desc">Lisinopril 10mg</div></div>
    <span class="tl-chevron">›</span>
  </div>
  <div class="tl-row tl-row--tappable">
    <div class="tl-gutter"><span class="tl-gutter__icon" style="color: var(--color-tertiary)">☀</span><span class="tl-gutter__text">1:30 PM</span></div>
    <div class="tl-rail"><span class="tl-rail__line tl-rail__top"></span><span class="tl-dot" style="background: var(--color-tertiary)"></span><span class="tl-rail__line tl-rail__bottom"></span></div>
    <div class="tl-content"><div class="tl-title">Blood pressure</div><div class="tl-desc">128/82</div></div>
    <span class="tl-chevron">›</span>
  </div>
  <div class="tl-row tl-row--tappable">
    <div class="tl-gutter"><span class="tl-gutter__icon" style="color: var(--color-textSecondary)">☾</span><span class="tl-gutter__text">9:45 PM</span></div>
    <div class="tl-rail"><span class="tl-rail__line tl-rail__top"></span><span class="tl-dot" style="background: var(--color-highlight)"></span><span class="tl-rail__line tl-rail__bottom"></span></div>
    <div class="tl-content"><div class="tl-title">Walk</div><div class="tl-desc">20 min around the block</div></div>
    <span class="tl-chevron">›</span>
  </div>
</div>`,
        code: `Timeline(nodes: nodes) // each node carries a tap action`,
      },
      {
        label: 'Minimal',
        html: `<div class="timeline">
  <div class="tl-row">
    <div class="tl-gutter"></div>
    <div class="tl-rail"><span class="tl-rail__line tl-rail__top"></span><span class="tl-dot" style="background: var(--color-accent)"></span><span class="tl-rail__line tl-rail__bottom"></span></div>
    <div class="tl-content"><div class="tl-title">Step one</div></div>
  </div>
  <div class="tl-row">
    <div class="tl-gutter"></div>
    <div class="tl-rail"><span class="tl-rail__line tl-rail__top"></span><span class="tl-dot" style="background: var(--color-highlight)"></span><span class="tl-rail__line tl-rail__bottom"></span></div>
    <div class="tl-content"><div class="tl-title">Step two</div></div>
  </div>
  <div class="tl-row">
    <div class="tl-gutter"></div>
    <div class="tl-rail"><span class="tl-rail__line tl-rail__top"></span><span class="tl-dot" style="background: var(--color-tertiary)"></span><span class="tl-rail__line tl-rail__bottom"></span></div>
    <div class="tl-content"><div class="tl-title">Step three</div></div>
  </div>
</div>`,
        code: `Timeline(nodes: [.init(title: "Step one"), .init(title: "Step two")])`,
      },
    ],
  },
];

// ---- build ----

function buildSlides() {
  const host = document.getElementById('slides');
  host.innerHTML = '';
  colorHost = null;
  gradientHost = null;

  // Token slides.
  colorHost = addTokenSlide('Colors', 'swatch-grid');
  renderScaleRows(addTokenSlide('Spacing', 'scale-list'), tokens.scales.spacing, 'spacing');
  renderScaleRows(addTokenSlide('Radius', 'scale-list'), tokens.scales.radius, 'radius');
  renderType(addTokenSlide('Type', 'type-list'), tokens.scales.type);
  gradientHost = addTokenSlide('Gradient', 'gradient-list');

  // Component slides.
  for (const component of COMPONENTS) addComponentSlide(component);
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
  select.addEventListener('change', () => applyPalette(select.value));
  document.getElementById('toggle-light').addEventListener('click', () => applyPalette('light'));
  document.getElementById('toggle-dark').addEventListener('click', () => applyPalette('dark'));
}

async function init() {
  tokens = await loadTokens();
  applyScales(tokens.scales);
  buildSlides();
  populatePaletteSelect();
  applyPalette('light');
}

init();
