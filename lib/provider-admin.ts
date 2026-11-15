import { randomUUID } from "node:crypto";
import { type SupabaseClient } from "@supabase/supabase-js";
import { authAdmin } from "./password-auth";
import { ApiError } from "./errors";
import {
  normalizeUsername,
  validUsername,
  validPassword,
  reservedUsernames,
} from "./username.mjs";
export async function saveManagedProvider(supabase: SupabaseClient, body: any) {
  // Fail before creating an Auth account if the provider migration has not been applied.
  const readiness = await supabase
    .from("provider_offerings")
    .select("provider_id")
    .limit(0);
  if (readiness.error) throw readiness.error;
  let newId: string | undefined;
  const admin = body.user_id ? null : await authAdmin();
  if (admin) {
    const username = normalizeUsername(body.username);
    if (
      !validUsername(username) ||
      reservedUsernames.has(username) ||
      !validPassword(body.password, 12)
    )
      throw new ApiError(
        "Enter a valid username and a temporary password of at least 12 characters.",
      );
    const { data: existing, error: lookupError } = await admin.rpc(
      "service_resolve_username",
      { p_username: username },
    );
    if (lookupError) throw lookupError;
    if (existing) throw new ApiError("This username is already in use.", 409);
    const { data, error } = await admin.auth.admin.createUser({
      email: "u." + randomUUID() + "@localmate.invalid",
      password: body.password,
      email_confirm: true,
      user_metadata: { full_name: String(body.name || "").slice(0, 100) },
    });
    if (error || !data.user)
      throw new ApiError(
        "The provider account could not be created. Check the account service configuration.",
        503,
      );
    newId = data.user.id;
    try {
      const { error } = await admin.rpc("service_set_login", {
        p_user: newId,
        p_username: username,
        p_change_password: true,
      });
      if (error) throw error;
    } catch (error) {
      await admin.auth.admin.deleteUser(newId);
      throw error;
    }
  }
  try {
    const { error } = await supabase.rpc("save_provider", {
      p_user: body.user_id || newId,
      p_data: body,
    });
    if (error) throw error;
  } catch (error) {
    if (newId && admin) {
      const cleanup = await admin.auth.admin.deleteUser(newId);
      if (cleanup.error)
        console.error("Provider creation cleanup failed", cleanup.error.code);
    }
    throw error;
  }
  return {
    ok: true,
    user_id: body.user_id || newId,
    must_change_password: !!newId,
  };
}
export function placeCoordinates(body: any) {
  const values: Record<string, number | null> = {};
  for (const field of ["latitude", "longitude"]) {
    const raw = body[field];
    values[field] =
      raw === null || raw === undefined || raw === "" ? null : Number(raw);
    if (
      values[field] !== null &&
      (!Number.isFinite(values[field]) ||
        Math.abs(values[field]!) > (field === "latitude" ? 90 : 180))
    )
      throw new ApiError("Choose a valid map position.");
  }
  if ((values.latitude === null) !== (values.longitude === null))
    throw new ApiError("Choose both latitude and longitude.");
  return values;
}
