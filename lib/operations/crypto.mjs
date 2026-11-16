import {
  randomInt,
  randomBytes,
  createCipheriv,
  createDecipheriv,
  createHmac,
} from "node:crypto";
export function otpKeys(secret) {
  if (!secret || secret.length < 24)
    throw new Error("Configure the server OTP key.");
  return {
    hash: createHmac("sha256", secret)
      .update("local-mate-otp-hash-v1")
      .digest(),
    cipher: createHmac("sha256", secret)
      .update("local-mate-otp-encryption-v1")
      .digest(),
  };
}
export function otpHash(code, booking, secret) {
  return createHmac("sha256", otpKeys(secret).hash)
    .update(booking + ":" + code)
    .digest("hex");
}
export function makeOTP(booking, secret) {
  const code = String(randomInt(100000, 1000000));
  const iv = randomBytes(12),
    enc = createCipheriv("aes-256-gcm", otpKeys(secret).cipher, iv);
  const data = Buffer.concat([enc.update(code, "utf8"), enc.final()]);
  return {
    hash: otpHash(code, booking, secret),
    cipher: [
      iv.toString("base64url"),
      enc.getAuthTag().toString("base64url"),
      data.toString("base64url"),
    ].join("."),
  };
}
export function decryptOTP(cipher, secret) {
  const [iv, tag, data] = cipher
    .split(".")
    .map((v) => Buffer.from(v, "base64url"));
  const dec = createDecipheriv("aes-256-gcm", otpKeys(secret).cipher, iv);
  dec.setAuthTag(tag);
  return Buffer.concat([dec.update(data), dec.final()]).toString("utf8");
}
export function iceConfiguration(env, userId, config = {}, now = Date.now()) {
  const stun = (env.STUN_URLS || "stun:stun.l.google.com:19302")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const urls = (env.TURN_URLS || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const secret = (env.TURN_SHARED_SECRET || "").trim();
  if (
    stun.some((s) => !/^stuns?:[^\s]+$/.test(s)) ||
    urls.some((s) => !/^turns?:[^\s]+$/.test(s))
  )
    throw new Error("The STUN or TURN server configuration is invalid.");
  const servers = stun.length ? [{ urls: stun }] : [];
  if (urls.length && secret.length >= 24) {
    const expires =
      Math.floor(now / 1000) + Number(config.call_max_seconds || 3600) + 300;
    const username = expires + ":" + userId;
    servers.push({
      urls,
      username,
      credential: createHmac("sha1", secret).update(username).digest("base64"),
    });
  }
  const turnConfigured = urls.length > 0 && secret.length >= 24;
  if (config.relay_only && !turnConfigured)
    throw new Error(
      "Relay-only calling requires a configured TURN server. Use in-app chat until it is ready.",
    );
  return {
    iceServers: servers,
    iceTransportPolicy: config.relay_only ? "relay" : "all",
    turnConfigured,
  };
}
export function paise(value) {
  const s = String(value ?? "");
  if (!/^\d{1,8}(\.\d{1,2})?$/.test(s))
    throw new Error("Enter an INR amount with at most two decimal places.");
  const [whole, fraction = ""] = s.split(".");
  const amount = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  if (!Number.isSafeInteger(amount) || amount > 1000000000)
    throw new Error("Amount is too large.");
  return amount;
}
