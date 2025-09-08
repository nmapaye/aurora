// Starry Night (van Gogh) inspired 7x52 pixel grid for GitHub contributions
// - Outputs a 7 (rows, Sun→Sat) x 52 (columns, weeks) matrix of levels 0–4
// - Also can emit a commit plan JSON for a given year mapping dates → commit counts
// Usage:
//   node scripts/starry-night-grid.js                # prints grid
//   YEAR=2025 node scripts/starry-night-grid.js plan # prints commit plan JSON

function clamp(v, a, b) { return Math.min(b, Math.max(a, v)); }
function lerp(a, b, t) { return a + (b - a) * t; }

const ROWS = 7;   // Sun..Sat (GitHub default)
const COLS = 52;  // weeks

// Style parameters (tweak to taste)
const params = {
  bg: 0.35,               // base sky brightness
  cypressDark: 0.0,       // foreground silhouette level
  moon: { x: 0.86, y: 0.22, r: 0.12, glow: 0.22, amp: 1.4 },
  swirl1: { x: 0.52, y: 0.33, scale: 1.1, amp: 0.9 },
  swirl2: { x: 0.24, y: 0.45, scale: 1.3, amp: 0.7 },
  stars: [
    { x: 0.12, y: 0.18, r: 0.04, amp: 1.1 },
    { x: 0.34, y: 0.12, r: 0.035, amp: 0.9 },
    { x: 0.62, y: 0.16, r: 0.04, amp: 0.95 },
    { x: 0.73, y: 0.28, r: 0.03, amp: 0.9 },
  ],
};

// Field helpers
function radial(x, y, cx, cy, r, glow) {
  const dx = x - cx, dy = y - cy;
  const d = Math.sqrt(dx*dx + dy*dy);
  const core = Math.exp(- (d*d) / (r*r*0.5));
  const halo = Math.exp(- (d*d) / (glow*glow*0.5));
  return core * 0.7 + halo * 0.3;
}

function swirl(x, y, cx, cy, scale, amp) {
  const dx = x - cx, dy = y - cy;
  const r = Math.sqrt(dx*dx + dy*dy) * scale + 1e-6;
  const theta = Math.atan2(dy, dx);
  // spiral bands with decay; tuned to evoke van Gogh’s turbulence
  const bands = Math.sin(3.2*theta + 5.0*r);
  const decay = Math.exp(-2.4 * r);
  return amp * bands * decay;
}

function cypressMask(x, y) {
  // Left foreground silhouette approximated by bezier-like envelope
  // Tall spire ~x<0.16 with bulges; heavier near lower rows
  const base = 1.0 - clamp((x - 0.02) / 0.14, 0, 1);
  const bulge = Math.max(0, 0.5 - Math.abs(y - 0.65)) * 1.3;
  const taper = lerp(1.1, 0.2, y); // thinner near top
  let m = (base * taper) + bulge * (1 - x*6);
  m = clamp(m, 0, 1);
  return m;
}

function computeLevel(x, y) {
  // Base sky
  let v = params.bg;

  // Swirls
  v += swirl(x, y, params.swirl1.x, params.swirl1.y, params.swirl1.scale, params.swirl1.amp) * 0.5;
  v += swirl(x, y, params.swirl2.x, params.swirl2.y, params.swirl2.scale, params.swirl2.amp) * 0.45;

  // Moon and glow
  v += radial(x, y, params.moon.x, params.moon.y, params.moon.r, params.moon.glow) * params.moon.amp;

  // Stars
  for (const s of params.stars) v += radial(x, y, s.x, s.y, s.r, s.r*2.2) * s.amp * 0.8;

  // Cypress silhouette subtracts brightness
  const cy = cypressMask(x, y);
  v = v * (1 - 0.95*cy) + params.cypressDark * cy;

  // Normalize and quantize to 0..4 (GitHub contribution intensity)
  // Map: darker sky -> lower, bright moon/stars -> higher
  const t = clamp((v - 0.05) / 1.6, 0, 1);
  const level = Math.round(t * 4);
  return clamp(level, 0, 4);
}

function generateGrid() {
  const grid = Array.from({ length: ROWS }, () => Array(COLS).fill(0));
  for (let c = 0; c < COLS; c++) {
    for (let r = 0; r < ROWS; r++) {
      // Normalize x right→left so moon is near the right side of the grid
      const x = (c + 0.5) / COLS;
      const y = (r + 0.5) / ROWS;
      grid[r][c] = computeLevel(x, y);
    }
  }
  return grid;
}

function printGrid(grid) {
  // Rows: Sun (0) → Sat (6)
  const legend = '0=none 1=low 2=med 3=high 4=peak';
  console.log(`# 7x52 Starry Night grid (rows=Sun→Sat, cols=weeks)`);
  console.log(`# Legend: ${legend}`);
  for (let r = 0; r < ROWS; r++) {
    console.log(grid[r].join(''));
  }
}

function buildPlan(grid, year) {
  // Map grid[r][c] → commit counts for the date = week c, weekday r, in given year
  // Choose a start on first Sunday of the year to align rows (GitHub uses Sun-start)
  const start = new Date(Date.UTC(year, 0, 1));
  // Move back to previous Sunday
  const day = start.getUTCDay(); // 0=Sun
  start.setUTCDate(start.getUTCDate() - day);

  const levelToCommits = { 0: 0, 1: 1, 2: 3, 3: 6, 4: 10 };
  const plan = [];
  for (let c = 0; c < COLS; c++) {
    for (let r = 0; r < ROWS; r++) {
      const d = new Date(start);
      d.setUTCDate(d.getUTCDate() + c*7 + r);
      if (d.getUTCFullYear() !== year) continue; // keep inside target year
      const level = grid[r][c];
      const commits = levelToCommits[level];
      if (commits > 0) {
        plan.push({ date: d.toISOString().slice(0, 10), commits });
      }
    }
  }
  return plan;
}

const mode = process.argv[2] || 'grid';
const grid = generateGrid();
if (mode === 'plan') {
  const year = parseInt(process.env.YEAR || `${new Date().getUTCFullYear()}`, 10);
  const plan = buildPlan(grid, year);
  console.log(JSON.stringify({ year, rows: ROWS, cols: COLS, plan }, null, 2));
} else {
  printGrid(grid);
}

