// WMO weather interpretation codes used by Open-Meteo.
const CODES: Array<[number[], string, string]> = [
  [[0], "Clear sky", "☀️"],
  [[1, 2], "Partly cloudy", "⛅"],
  [[3], "Overcast", "☁️"],
  [[45, 48], "Fog", "🌫️"],
  [[51, 53, 55, 56, 57], "Drizzle", "🌦️"],
  [[61, 63, 65, 66, 67, 80, 81, 82], "Rain", "🌧️"],
  [[71, 73, 75, 77, 85, 86], "Snow", "❄️"],
  [[95, 96, 99], "Thunderstorm", "⛈️"],
];

export function describe(code: number | null): { label: string; icon: string } {
  const match = CODES.find(([codes]) => code !== null && codes.includes(code));
  return match ? { label: match[1], icon: match[2] } : { label: "Unknown", icon: "❔" };
}
