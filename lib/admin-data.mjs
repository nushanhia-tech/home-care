import { readStringArray, providerOffers } from "./provider-data.mjs";

// Keep an unexpected directory response inside the administrator panel instead of
// allowing invalid records or React child values to crash the whole dashboard.
export function adminRows(tab, value) {
  const invalid = () =>
    new Error(
      tab === "providers"
        ? "The provider list could not be read. Please reload it."
        : "This list could not be read. Please reload it.",
    );
  if (
    !Array.isArray(value) ||
    value.some(
      (row) => row === null || typeof row !== "object" || Array.isArray(row),
    )
  )
    throw invalid();
  if (tab !== "providers") return value;
  if (
    value.some((row) => typeof row.user_id !== "string" || !row.user_id.trim())
  )
    throw invalid();
  return value.map((row) => {
    const text = {};
    const experience =
      typeof row.experience === "number" ||
      (typeof row.experience === "string" && row.experience.trim())
        ? Number(row.experience)
        : NaN;
    for (const key of [
      "name",
      "business_name",
      "category",
      "phone",
      "description",
      "username",
      "rating_source",
    ])
      text[key] = typeof row[key] === "string" ? row[key] : "";
    return {
      ...row,
      ...text,
      locations: readStringArray(row.locations),
      service_ids: readStringArray(row.service_ids),
      offerings: providerOffers(row.offerings),
      status: ["pending", "approved", "rejected", "suspended"].includes(
        row.status,
      )
        ? row.status
        : "unknown",
      experience:
        Number.isInteger(experience) && experience >= 0 && experience <= 70
          ? experience
          : null,
    };
  });
}
