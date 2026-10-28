import { describe as suite, expect, it } from "vitest";
import { describe } from "./weatherCodes";

suite("weather code mapping", () => {
  it("maps known codes", () => {
    expect(describe(0).label).toBe("Clear sky");
    expect(describe(63).label).toBe("Rain");
  });
  it("handles unknown and null", () => {
    expect(describe(null).label).toBe("Unknown");
    expect(describe(1234).label).toBe("Unknown");
  });
});
