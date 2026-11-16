"use client";
import React, { useRef, useState } from "react";
export function Field({ label, children, hint }) {
  return (
    <label className="field">
      <span>{label}</span>
      {React.Children.map(children, (c) =>
        React.isValidElement(c) &&
        ["input", "select", "textarea"].includes(c.type)
          ? React.cloneElement(c, {
              "aria-label": c.props["aria-label"] || label,
            })
          : c,
      )}
      {hint && <small>{hint}</small>}
    </label>
  );
}
export function Form({ children, onSubmit, label = "Save changes" }) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const active = useRef(false);
  return (
    <form
      onSubmit={async (e) => {
        e.preventDefault();
        if (active.current) return;
        active.current = true;
        setBusy(true);
        setError("");
        try {
          await onSubmit(Object.fromEntries(new FormData(e.currentTarget)));
        } catch (e) {
          setError(e.message);
        } finally {
          active.current = false;
          setBusy(false);
        }
      }}
    >
      {children}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      <button className="button form-submit" disabled={busy}>
        {busy ? "Please wait…" : label}
      </button>
    </form>
  );
}
export async function upload(file, kind, booking) {
  if (!file || !file.size) throw new Error("Choose an image to upload.");
  const data = new FormData();
  data.set("file", file);
  data.set("kind", kind);
  if (booking) data.set("booking_id", booking);
  const response = await fetch("/api/uploads", { method: "POST", body: data });
  const result = await response.json();
  if (!response.ok)
    throw new Error(result.error || "The image could not be uploaded.");
  return result.id;
}
export function PrivateImage({ id, caption = "Private image" }) {
  const [error, setError] = useState(false);
  return error ? (
    <small>{caption} — unavailable or awaiting privacy review</small>
  ) : (
    <a href={"/api/media/" + id} target="_blank" rel="noreferrer">
      <img
        className="private-image"
        src={"/api/media/" + id}
        alt={caption}
        onError={() => setError(true)}
      />
    </a>
  );
}
export const title = (value) =>
  String(value || "")
    .replaceAll("_", " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
