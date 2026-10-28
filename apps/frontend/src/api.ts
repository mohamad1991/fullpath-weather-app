export interface CurrentWeather {
  location_id: number;
  name: string;
  country: string;
  observed_at: string;
  temperature_c: number | null;
  apparent_temperature_c: number | null;
  humidity_pct: number | null;
  precipitation_mm: number | null;
  wind_speed_kmh: number | null;
  weather_code: number | null;
}

export interface HistoryPoint {
  observed_at: string;
  temperature_c: number | null;
}

async function getJson<T>(path: string): Promise<T> {
  const res = await fetch(path);
  if (!res.ok) throw new Error(`${path} -> HTTP ${res.status}`);
  return res.json() as Promise<T>;
}

export const fetchCurrent = () => getJson<CurrentWeather[]>("/api/weather/current");
export const fetchHistory = (id: number, hours: number) =>
  getJson<HistoryPoint[]>(`/api/weather/${id}/history?hours=${hours}`);
