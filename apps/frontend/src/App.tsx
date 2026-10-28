import { useEffect, useState } from "react";
import { fetchCurrent, fetchHistory, type CurrentWeather, type HistoryPoint } from "./api";
import { describe } from "./weatherCodes";
import { HistoryChart } from "./HistoryChart";

const REFRESH_MS = 60_000;
const RANGES = [24, 72, 168];

export default function App() {
  const [current, setCurrent] = useState<CurrentWeather[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<CurrentWeather | null>(null);
  const [hours, setHours] = useState(24);
  const [history, setHistory] = useState<HistoryPoint[]>([]);

  useEffect(() => {
    const load = () =>
      fetchCurrent()
        .then((d) => { setCurrent(d); setError(null); })
        .catch((e: Error) => setError(e.message));
    load();
    const id = setInterval(load, REFRESH_MS);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (!selected) return;
    fetchHistory(selected.location_id, hours).then(setHistory).catch((e: Error) => setError(e.message));
  }, [selected, hours]);

  return (
    <main>
      <header>
        <h1>World Weather</h1>
        <span className="muted">Live data · refreshes every minute</span>
      </header>
      {error && <div className="error">Could not load weather: {error}</div>}
      <section className="grid">
        {current.map((w) => {
          const { label, icon } = describe(w.weather_code);
          return (
            <button
              key={w.location_id}
              className={`card ${selected?.location_id === w.location_id ? "active" : ""}`}
              onClick={() => setSelected(w)}
            >
              <div className="city">{w.name}<span className="muted"> {w.country}</span></div>
              <div className="temp">{icon} {w.temperature_c?.toFixed(1)}°C</div>
              <div className="muted">{label} · feels {w.apparent_temperature_c?.toFixed(0)}°</div>
              <div className="muted">💧 {w.humidity_pct}% · 💨 {w.wind_speed_kmh} km/h</div>
              <div className="stamp">as of {new Date(w.observed_at).toLocaleTimeString()}</div>
            </button>
          );
        })}
      </section>
      {selected && (
        <section className="history">
          <div className="history-head">
            <h2>{selected.name} - temperature history</h2>
            <div>
              {RANGES.map((h) => (
                <button key={h} className={h === hours ? "pill active" : "pill"} onClick={() => setHours(h)}>
                  {h < 48 ? `${h}h` : `${h / 24}d`}
                </button>
              ))}
            </div>
          </div>
          <HistoryChart points={history} />
        </section>
      )}
    </main>
  );
}
