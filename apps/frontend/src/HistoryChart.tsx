import type { HistoryPoint } from "./api";

const W = 640;
const H = 200;
const PAD = 32;

export function HistoryChart({ points }: { points: HistoryPoint[] }) {
  const data = points.filter((p) => p.temperature_c !== null);
  if (data.length < 2) return <p className="muted">Not enough history yet - the collector runs every 15 minutes.</p>;

  const xs = data.map((p) => new Date(p.observed_at).getTime());
  const ys = data.map((p) => p.temperature_c as number);
  const [xMin, xMax] = [Math.min(...xs), Math.max(...xs)];
  const [yMin, yMax] = [Math.floor(Math.min(...ys)) - 1, Math.ceil(Math.max(...ys)) + 1];
  const x = (v: number) => PAD + ((v - xMin) / (xMax - xMin || 1)) * (W - 2 * PAD);
  const y = (v: number) => H - PAD - ((v - yMin) / (yMax - yMin || 1)) * (H - 2 * PAD);
  const path = data.map((_, i) => `${i ? "L" : "M"}${x(xs[i]).toFixed(1)},${y(ys[i]).toFixed(1)}`).join(" ");
  const fmt = (t: number) => new Date(t).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit" });

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="chart" role="img" aria-label="Temperature history">
      <line x1={PAD} y1={H - PAD} x2={W - PAD} y2={H - PAD} className="axis" />
      <text x={4} y={y(yMax) + 4}>{yMax}°</text>
      <text x={4} y={y(yMin) + 4}>{yMin}°</text>
      <text x={PAD} y={H - 8}>{fmt(xMin)}</text>
      <text x={W - PAD} y={H - 8} textAnchor="end">{fmt(xMax)}</text>
      <path d={path} className="line" />
    </svg>
  );
}
