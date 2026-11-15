// Supabase JSON fields can be native values or JSON text in older API responses.
// Always check the decoded shape before a settings form reads its properties.
function decoded(value) {
  for (let depth = 0; typeof value === "string" && depth < 3; depth++) {
    try {
      value = JSON.parse(value);
    } catch {
      return undefined;
    }
  }
  return value;
}
export function readArray(value) {
  const result = decoded(value);
  return Array.isArray(result) ? result : [];
}
export function readRecord(value) {
  const result = decoded(value);
  return result !== null && typeof result === "object" && !Array.isArray(result)
    ? result
    : {};
}
export function readStringArray(value) {
  return readArray(value).filter(
    (item) => typeof item === "string" && item.trim().length > 0,
  );
}
export function providerOffers(value) {
  return readArray(value).filter(
    (item) =>
      item !== null &&
      typeof item === "object" &&
      !Array.isArray(item) &&
      typeof item.service_id === "string" &&
      item.service_id.length > 0,
  );
}
export function providerSchedule(value) {
  const data = readRecord(value);
  const text = (value, fallback) =>
    typeof value === "string" ? value : fallback;
  const capacity =
    typeof data.max_daily === "number" || typeof data.max_daily === "string"
      ? Number(data.max_daily)
      : NaN;
  return {
    days: text(data.days, "Monday – Saturday"),
    hours: text(data.hours, "9:00 AM – 6:00 PM"),
    max_daily:
      Number.isInteger(capacity) && capacity >= 1 && capacity <= 30
        ? capacity
        : 5,
    leave: text(data.leave, ""),
  };
}
