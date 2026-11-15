"use client";
import React, { useState, useEffect, useRef } from "react";
import dynamic from "next/dynamic";
import {
  Phone,
  MapPin,
  Navigation,
  Star,
  MessageSquare,
  Plus,
  LoaderCircle,
} from "lucide-react";
const PlaceMap = dynamic(() => import("./place-map"), {
  ssr: false,
  loading: () => <p>Loading map…</p>,
});
export const array = (value) =>
  Array.isArray(value)
    ? value
    : (() => {
        try {
          return JSON.parse(value || "[]");
        } catch {
          return [];
        }
      })();
const money = (n) => "₹" + Number(n || 0).toLocaleString("en-IN");
function Field({ label, children }) {
  return (
    <label className="field">
      <span>{label}</span>
      {React.Children.map(children, (child) =>
        React.isValidElement(child) &&
        ["input", "select", "textarea"].includes(child.type)
          ? React.cloneElement(child, {
              "aria-label": child.props["aria-label"] || label,
            })
          : child,
      )}
    </label>
  );
}
function SaveForm({ children, onSubmit, label = "Save changes" }) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const pending = useRef(false);
  return (
    <form
      onSubmit={async (e) => {
        e.preventDefault();
        if (pending.current) return;
        pending.current = true;
        setBusy(true);
        setError("");
        try {
          await onSubmit(Object.fromEntries(new FormData(e.currentTarget)));
        } catch (e) {
          setError(e.message);
        } finally {
          pending.current = false;
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
        {busy ? <LoaderCircle className="spin" size={17} /> : null}
        {label}
      </button>
    </form>
  );
}
export function Rating({ provider: p }) {
  return (
    <div className="provider-ratings">
      {Number(p.review_count) > 0 ? (
        <span className="rating">
          <Star size={14} />
          {Number(p.rating).toFixed(1)}/5 · {p.review_count} verified booking
          reviews
        </span>
      ) : (
        <small>No completed-booking reviews yet</small>
      )}
      {p.assessment_rating !== null && p.assessment_rating !== undefined && (
        <small className="assessment-rating">
          Listed assessment: {Number(p.assessment_rating).toFixed(1)}/5 ·{" "}
          {p.rating_source}
        </small>
      )}
    </div>
  );
}
export function ProviderRates({ provider: p, catalog = [] }) {
  return (
    <div className="offer-list">
      <Rating provider={p} />
      {array(p.offerings).map((o) => (
        <div className="offer-row" key={o.service_id}>
          <span>
            {catalog.find((s) => s.id === o.service_id)?.name || o.service_id}
          </span>
          <strong>
            {o.pricing_unit === "quote"
              ? "Request quote"
              : money(o.price) + " / " + o.pricing_unit}
          </strong>
        </div>
      ))}
      {p.phone && (
        <a className="text-link" href={"tel:" + p.phone}>
          <Phone size={15} />
          {p.phone}
        </a>
      )}
    </div>
  );
}
export function ServiceProviders({
  providers,
  service,
  location,
  selected,
  onSelect,
  me,
}) {
  const shown = providers.filter(
    (p) =>
      array(p.service_ids).includes(service.id) &&
      array(p.locations).includes(location),
  );
  return (
    <div className="service-provider-list">
      <h3>
        {shown.length} service provider{shown.length === 1 ? "" : "s"} in{" "}
        {location}
      </h3>
      <p className="muted-copy">
        Choose a professional to request their listed rate. Availability is
        confirmed when they respond.
      </p>
      {shown.length === 0 && (
        <p>No approved providers for this service and town yet.</p>
      )}
      {shown.map((p) => {
        const offer = array(p.offerings).find(
          (o) => o.service_id === service.id,
        );
        return (
          <div
            className={
              "service-provider-option " +
              (selected === p.user_id ? "chosen" : "")
            }
            key={p.user_id}
          >
            <div className="panel-heading">
              <strong>{p.business_name || p.name}</strong>
              <span className={"status " + (p.online ? "active" : "inactive")}>
                {p.online ? "Online" : "Offline"}
              </span>
            </div>
            <Rating provider={p} />
            <p className="offer-price">
              {offer && offer.pricing_unit !== "quote"
                ? money(offer.price) + " / " + offer.pricing_unit
                : "Quotation required"}
            </p>
            {p.phone ? (
              <a className="text-link" href={"tel:" + p.phone}>
                <Phone size={14} />
                {p.phone}
              </a>
            ) : (
              <small>Phone shared with the customer after assignment.</small>
            )}
            <button
              type="button"
              className={
                "button " + (selected === p.user_id ? "" : "secondary")
              }
              disabled={!p.online || p.user_id === me?.id}
              onClick={() => onSelect(p.user_id)}
            >
              {selected === p.user_id ? "Selected" : "Choose provider"}
            </button>
          </div>
        );
      })}
    </div>
  );
}
export function ProviderEditor({
  provider,
  me,
  catalog,
  locations,
  api,
  notify,
  reload,
  close,
  admin = false,
}) {
  const p = provider || me?.provider || {};
  const [offers, setOffers] = useState(() =>
    array(p.offerings).length
      ? array(p.offerings)
      : array(p.service_ids).map((service_id) => ({
          service_id,
          price: null,
          pricing_unit: "quote",
        })),
  );
  const [areas, setAreas] = useState(() => array(p.locations));
  const [users, setUsers] = useState([]),
    [existing, setExisting] = useState("");
  useEffect(() => {
    if (admin && !provider)
      api("/admin/users")
        .then(setUsers)
        .catch(() => {});
  }, [admin, provider]);
  const user =
    provider || (!admin ? me : users.find((u) => u.id === existing)) || {};
  const updateOffer = (id, key, value) =>
    setOffers(
      offers.map((o) => (o.service_id === id ? { ...o, [key]: value } : o)),
    );
  return (
    <>
      <p>
        {admin
          ? "Add or edit a provider, set their services, prices and coverage."
          : "Manage your services, prices, areas and public contact preference."}
      </p>
      <SaveForm
        label={admin ? "Save provider" : "Save services & profile"}
        onSubmit={async (data) => {
          if (!offers.length || !areas.length)
            throw new Error("Choose at least one service and service area.");
          await api(admin ? "/admin/providers" : "/provider/profile", {
            ...data,
            user_id: admin
              ? provider?.user_id || existing || undefined
              : undefined,
            offerings: offers.map((o) => ({
              ...o,
              price: o.pricing_unit === "quote" ? null : Number(o.price),
            })),
            locations: areas,
            experience: Number(data.experience),
            publish_phone: data.publish_phone === "on",
            online: data.online === "on",
          });
          reload();
          notify(
            admin
              ? "Provider saved. New accounts must change their temporary password at sign-in."
              : "Your provider profile and rates have been saved.",
          );
          close?.();
        }}
      >
        {admin && !provider && (
          <>
            <Field label="Provider account">
              <select
                value={existing}
                onChange={(e) => setExisting(e.target.value)}
              >
                <option value="">Create a new username account</option>
                {users.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.name} · {u.username || "No username"}
                  </option>
                ))}
              </select>
            </Field>
            {!existing && (
              <div className="form-grid">
                <Field label="Username">
                  <input
                    name="username"
                    required
                    minLength={3}
                    maxLength={32}
                    autoComplete="off"
                    pattern="[A-Za-z0-9._-]{3,32}"
                  />
                </Field>
                <Field label="Temporary password (12+ characters)">
                  <input
                    type="password"
                    name="password"
                    required
                    minLength={12}
                    maxLength={128}
                    autoComplete="new-password"
                  />
                </Field>
              </div>
            )}
          </>
        )}
        <div className="form-grid" key={user.user_id || user.id || "new"}>
          <Field label="Full name">
            <input
              name="name"
              defaultValue={user.name || ""}
              required
              maxLength={100}
            />
          </Field>
          <Field label="Mobile number">
            <input
              name="phone"
              type="tel"
              defaultValue={user.phone || ""}
              pattern="(\+91)?[6-9][0-9]{9}"
              placeholder="+919876543210"
              required
            />
          </Field>
        </div>
        <div className="form-grid">
          <Field label="Business name">
            <input
              name="business_name"
              defaultValue={p.business_name || ""}
              maxLength={100}
            />
          </Field>
          <Field label="Category">
            <input
              name="category"
              defaultValue={p.category || "Home care"}
              required
              maxLength={100}
            />
          </Field>
          <Field label="Experience (years)">
            <input
              name="experience"
              type="number"
              min="0"
              max="70"
              defaultValue={p.experience || 0}
              required
            />
          </Field>
        </div>
        <Field label="Skills & description">
          <textarea
            name="description"
            defaultValue={p.description || ""}
            required
            maxLength={2000}
            rows={3}
          />
        </Field>
        <fieldset>
          <legend>Services & provider rates</legend>
          <p className="muted-copy">
            Prices are in INR. Hourly, daily and quote services require customer
            approval of a total quotation.
          </p>
          {catalog.map((s) => {
            const o = offers.find((o) => o.service_id === s.id);
            return (
              <div className="offering-editor" key={s.id}>
                <label className="checkbox-row">
                  <input
                    type="checkbox"
                    checked={!!o}
                    onChange={(e) =>
                      setOffers(
                        e.target.checked
                          ? [
                              ...offers,
                              {
                                service_id: s.id,
                                price: null,
                                pricing_unit: "quote",
                              },
                            ]
                          : offers.filter((o) => o.service_id !== s.id),
                      )
                    }
                  />
                  {s.name}
                </label>
                {o && (
                  <div className="form-grid">
                    <Field label={s.name + " pricing"}>
                      <select
                        value={o.pricing_unit}
                        onChange={(e) =>
                          updateOffer(s.id, "pricing_unit", e.target.value)
                        }
                      >
                        {["quote", "visit", "hour", "day"].map((v) => (
                          <option key={v} value={v}>
                            {v === "quote" ? "Request a quote" : "Per " + v}
                          </option>
                        ))}
                      </select>
                    </Field>
                    {o.pricing_unit !== "quote" && (
                      <Field label={s.name + " rate (₹)"}>
                        <input
                          type="number"
                          min="0"
                          max="10000000"
                          step="1"
                          value={o.price ?? ""}
                          required
                          onChange={(e) =>
                            updateOffer(s.id, "price", e.target.value)
                          }
                        />
                      </Field>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </fieldset>
        <fieldset>
          <legend>Service areas</legend>
          <div className="checkbox-grid">
            {locations.map((l) => (
              <label key={l}>
                <input
                  type="checkbox"
                  checked={areas.includes(l)}
                  onChange={(e) =>
                    setAreas(
                      e.target.checked
                        ? [...areas, l]
                        : areas.filter((a) => a !== l),
                    )
                  }
                />
                {l}
              </label>
            ))}
          </div>
        </fieldset>
        <label className="checkbox-row">
          <input
            name="publish_phone"
            type="checkbox"
            defaultChecked={!!p.publish_phone}
          />
          Publish this contact number in the provider directory{" "}
          {admin ? "(provider consent obtained)" : "(optional)"}
        </label>
        {admin && (
          <>
            <div className="form-grid">
              <Field label="Approval status">
                <select name="status" defaultValue={p.status || "pending"}>
                  {["pending", "approved", "rejected", "suspended"].map((s) => (
                    <option key={s}>{s}</option>
                  ))}
                </select>
              </Field>
              <Field label="Assessment rating (optional, 0–5)">
                <input
                  name="assessment_rating"
                  type="number"
                  min="0"
                  max="5"
                  step="0.1"
                  defaultValue={p.assessment_rating ?? ""}
                />
              </Field>
            </div>
            <Field label="Rating source / assessment basis">
              <input
                name="rating_source"
                maxLength={200}
                defaultValue={p.rating_source || ""}
                placeholder="For example: verified external directory and date"
              />
            </Field>
            <p className="muted-copy">
              This is labelled as a listed assessment. Customer reviews are
              calculated from completed bookings.
            </p>
            <label className="checkbox-row">
              <input
                type="checkbox"
                name="online"
                defaultChecked={!!p.online}
              />
              Online and accepting requests
            </label>
          </>
        )}
      </SaveForm>
    </>
  );
}
export function PlacePicker({
  initial,
  prefix = "",
  label = "Exact place",
  value,
  onChange,
}) {
  const [internal, setInternal] = useState(
    initial?.latitude != null && initial?.longitude != null
      ? { latitude: initial.latitude, longitude: initial.longitude }
      : null,
  );
  const point = value === undefined ? internal : value;
  const [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  const change = (p) => {
    setInternal(p);
    onChange?.(p);
  };
  return (
    <fieldset className="place-picker">
      <legend>{label}</legend>
      <p className="muted-copy">
        Click the map or drag the marker. Keep the written address accurate.
      </p>
      <PlaceMap point={point} onChange={change} />
      <input
        type="hidden"
        name={prefix + "latitude"}
        value={point?.latitude ?? ""}
      />
      <input
        type="hidden"
        name={prefix + "longitude"}
        value={point?.longitude ?? ""}
      />
      <div className="actions">
        <button
          className="button secondary"
          type="button"
          disabled={busy}
          onClick={() => {
            if (!navigator.geolocation) {
              setError(
                "This browser does not support GPS. Choose the place on the map.",
              );
              return;
            }
            setBusy(true);
            setError("");
            navigator.geolocation.getCurrentPosition(
              (pos) => {
                change({
                  latitude: pos.coords.latitude,
                  longitude: pos.coords.longitude,
                });
                setBusy(false);
              },
              () => {
                setError(
                  "Location permission was denied or GPS is unavailable. Choose the place on the map.",
                );
                setBusy(false);
              },
              { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
            );
          }}
        >
          <Navigation size={15} />
          {busy ? "Finding your location…" : "Use my current location"}
        </button>
        {point && (
          <button
            type="button"
            className="text-link"
            onClick={() => change(null)}
          >
            Clear pin
          </button>
        )}
      </div>
      {point && (
        <small>
          {Number(point.latitude).toFixed(6)},{" "}
          {Number(point.longitude).toFixed(6)} · chosen map pin
        </small>
      )}
      {error && <p className="form-error">{error}</p>}
    </fieldset>
  );
}
export function SavedPlaceForm({
  address,
  location,
  locations,
  api,
  reload,
  notify,
  close,
}) {
  return (
    <SaveForm
      onSubmit={async (d) => {
        await api("/addresses", { ...d, id: address?.id });
        reload();
        notify("Your place has been saved.");
        close();
      }}
    >
      <Field label="Address label">
        <input
          name="label"
          required
          maxLength={100}
          defaultValue={address?.label}
          placeholder="Home or work"
        />
      </Field>
      <Field label="Full address, landmark & PIN code">
        <textarea
          name="address"
          required
          maxLength={1000}
          rows={3}
          defaultValue={address?.address}
        />
      </Field>
      <Field label="Town">
        <select name="location" defaultValue={address?.location || location}>
          {locations.map((l) => (
            <option key={l}>{l}</option>
          ))}
        </select>
      </Field>
      <PlacePicker
        initial={address}
        label="Exact service location (optional)"
      />
    </SaveForm>
  );
}
export function BookingContact({ booking: b, me, api, open }) {
  const [contacts, setContacts] = useState(null),
    [error, setError] = useState("");
  useEffect(() => {
    api("/bookings/" + b.id + "/contacts")
      .then(setContacts)
      .catch((e) => setError(e.message));
  }, [b.id, b.provider_id]);
  const other =
    me.id === b.provider_id ? contacts?.customer : contacts?.provider;
  return (
    <div className="booking-contact">
      <h3>Contact for this booking</h3>
      {error && <p className="form-error">{error}</p>}
      {other ? (
        <>
          <strong>{other.name}</strong>
          <div className="actions">
            {other.phone ? (
              <a className="button secondary" href={"tel:" + other.phone}>
                <Phone size={16} />
                {other.phone}
              </a>
            ) : (
              <small>No phone number added.</small>
            )}
            <button
              className="button secondary"
              onClick={() => open({ type: "chat", id: b.id })}
            >
              <MessageSquare size={16} />
              Send message
            </button>
          </div>
        </>
      ) : (
        <p>Contact details appear after a provider is assigned.</p>
      )}
    </div>
  );
}
const activeStatuses = [
  "confirmed",
  "on_the_way",
  "arrived",
  "work_started",
  "work_paused",
];
export function BookingTracking({ booking: b, me, api }) {
  const [live, setLive] = useState(null),
    [sharing, setSharing] = useState(false),
    [error, setError] = useState("");
  const watch = useRef(null),
    sent = useRef(0),
    inflight = useRef(false),
    started = useRef(false),
    session = useRef(null);
  const point =
      b.latitude != null
        ? { latitude: b.latitude, longitude: b.longitude }
        : null,
    destination =
      b.destination_latitude != null
        ? {
            latitude: b.destination_latitude,
            longitude: b.destination_longitude,
          }
        : null;
  const isProvider = b.provider_id === me.id,
    active = activeStatuses.includes(b.status);
  const stop = () => {
    if (watch.current !== null)
      navigator.geolocation?.clearWatch(watch.current);
    watch.current = null;
    if (started.current) {
      started.current = false;
      fetch("/api/bookings/" + b.id + "/tracking", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ stop: true, session_id: session.current }),
        keepalive: true,
      }).catch(() => {});
    }
    setSharing(false);
    setLive(null);
  };
  useEffect(() => {
    let cancelled = false;
    const load = () =>
      api("/bookings/" + b.id + "/tracking")
        .then((p) => {
          if (!cancelled) setLive(p);
        })
        .catch((e) => {
          if (!cancelled) setError(e.message);
        });
    load();
    const t = setInterval(load, 5000);
    const hide = () => {
      if (document.hidden) stop();
    };
    document.addEventListener("visibilitychange", hide);
    return () => {
      cancelled = true;
      clearInterval(t);
      document.removeEventListener("visibilitychange", hide);
      stop();
    };
  }, [b.id, b.status]);
  const start = async () => {
    setError("");
    if (!navigator.geolocation) {
      setError("GPS is unavailable in this browser.");
      return;
    }
    started.current = true;
    session.current = crypto.randomUUID();
    const sessionId = session.current;
    sent.current = 0;
    setSharing(true);
    try {
      await api("/bookings/" + b.id + "/tracking", {
        start: true,
        consent: true,
        session_id: sessionId,
      });
    } catch (e) {
      setError(e.message);
      stop();
      return;
    }
    if (!started.current || session.current !== sessionId) {
      fetch("/api/bookings/" + b.id + "/tracking", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ stop: true, session_id: sessionId }),
        keepalive: true,
      }).catch(() => {});
      return;
    }
    watch.current = navigator.geolocation.watchPosition(
      async (pos) => {
        if (
          !started.current ||
          session.current !== sessionId ||
          inflight.current ||
          Date.now() - sent.current < 10000
        )
          return;
        inflight.current = true;
        try {
          await api("/bookings/" + b.id + "/tracking", {
            consent: true,
            session_id: sessionId,
            latitude: pos.coords.latitude,
            longitude: pos.coords.longitude,
            accuracy: pos.coords.accuracy,
          });
          sent.current = Date.now();
          if (started.current && session.current === sessionId)
            setLive({
              ...pos.coords,
              latitude: pos.coords.latitude,
              longitude: pos.coords.longitude,
              accuracy: pos.coords.accuracy,
              recorded_at: new Date().toISOString(),
            });
        } catch (e) {
          setError(e.message);
          stop();
        } finally {
          inflight.current = false;
        }
      },
      (e) => {
        setError(
          e.code === 1
            ? "Location permission was denied. Enable it in your browser to share GPS."
            : "GPS position unavailable. Please try again outdoors.",
        );
        stop();
      },
      { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 },
    );
  };
  return (
    <div className="tracking-panel">
      <h3>
        <Navigation size={18} />
        Service location & provider GPS
      </h3>
      <PlaceMap point={point} destination={destination} live={live} />
      {point && (
        <a
          className="text-link"
          href={
            "https://www.google.com/maps/dir/?api=1&destination=" +
            point.latitude +
            "," +
            point.longitude
          }
          target="_blank"
          rel="noreferrer"
        >
          Directions to the service / pickup place
        </a>
      )}
      {destination && (
        <a
          className="text-link"
          href={
            "https://www.google.com/maps/dir/?api=1&destination=" +
            destination.latitude +
            "," +
            destination.longitude
          }
          target="_blank"
          rel="noreferrer"
        >
          Directions to destination
        </a>
      )}
      {live ? (
        <p className="gps-status">
          <span className="live-dot" />
          Provider position updated{" "}
          {new Date(live.recorded_at).toLocaleTimeString()} · GPS accuracy ±
          {Math.round(live.accuracy)} m
        </p>
      ) : (
        <p className="muted-copy">
          {active
            ? "No recent provider GPS update. The provider must choose to share."
            : "GPS sharing is available during an active assigned job."}
        </p>
      )}
      {isProvider && active && (
        <>
          <p className="muted-copy">
            Share your real GPS position with this customer for this job.
            Sharing stops when you leave this booking, hide the page, stop
            sharing or finish the job. Keep this page open; updates older than 2
            minutes are hidden.
          </p>
          <button
            className={"button " + (sharing ? "secondary" : "")}
            onClick={sharing ? stop : start}
          >
            {sharing ? "Stop sharing GPS" : "Share my live GPS for this job"}
          </button>
        </>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
export function MessagesInbox({ bookings, me, api, open }) {
  const [items, setItems] = useState([]),
    [error, setError] = useState("");
  useEffect(() => {
    api("/notifications")
      .then(setItems)
      .catch((e) => setError(e.message));
  }, [bookings]);
  return (
    <>
      <h2>Messages & updates</h2>
      <p className="muted-copy">
        Conversations are private to the customer and assigned provider. Open a
        conversation to read and reply.
      </p>
      {error && <p className="form-error">{error}</p>}
      {bookings
        .filter(
          (b) =>
            b.provider_id &&
            (b.provider_id === me.id || b.customer_id === me.id),
        )
        .map((b) => (
          <button
            key={b.id}
            className="booking-row"
            onClick={() => open({ type: "chat", id: b.id })}
          >
            <MessageSquare size={20} />
            <span className="booking-info">
              <strong>{b.service_name}</strong>
              <small>
                {b.customer_id === me.id ? b.provider_name : b.customer_name} ·{" "}
                {b.id.slice(0, 8)}
              </small>
            </span>
            <span>Open chat</span>
          </button>
        ))}
      {!bookings.some((b) => b.provider_id) && (
        <p>No assigned booking conversations yet.</p>
      )}
      <h3 className="mt">Recent updates</h3>
      {items.slice(0, 20).map((n) => (
        <div className="notification" key={n.id}>
          <div>
            <strong>{n.title}</strong>
            <small>{new Date(n.created_at).toLocaleString()}</small>
            {n.booking_id && (
              <button
                className="text-link"
                onClick={() =>
                  open({
                    type: "booking",
                    id: n.booking_id,
                    role: me.provider ? "provider" : undefined,
                  })
                }
              >
                Open booking
              </button>
            )}
          </div>
        </div>
      ))}
    </>
  );
}
export function ServiceRoster({ service, api, reload, notify }) {
  const [providers, setProviders] = useState([]),
    [chosen, setChosen] = useState("");
  const [error, setError] = useState("");
  useEffect(() => {
    api("/admin/providers")
      .then(setProviders)
      .catch((e) => setError(e.message));
  }, [service.id]);
  const refresh = async () => {
    setProviders(await api("/admin/providers"));
    reload();
  };
  return (
    <>
      {error && <p className="form-error">{error}</p>}
      <p>
        {
          providers.filter((p) => array(p.service_ids).includes(service.id))
            .length
        }{" "}
        providers assigned to this service. Counts are calculated from provider
        records.
      </p>
      <SaveForm
        label="Add / update service provider"
        onSubmit={async (d) => {
          await api("/admin/service-provider", {
            provider_id: chosen,
            service_id: service.id,
            enabled: true,
            price: d.price === "" ? null : Number(d.price),
            pricing_unit: d.pricing_unit,
          });
          await refresh();
          notify("Service provider updated.");
        }}
      >
        <Field label="Provider">
          <select
            value={chosen}
            required
            onChange={(e) => setChosen(e.target.value)}
          >
            <option value="">Choose a provider</option>
            {providers.map((p) => (
              <option key={p.user_id} value={p.user_id}>
                {p.business_name || p.name} · {p.status}
              </option>
            ))}
          </select>
        </Field>
        <div className="form-grid">
          <Field label="Pricing unit">
            <select name="pricing_unit">
              {["quote", "visit", "hour", "day"].map((u) => (
                <option key={u}>{u}</option>
              ))}
            </select>
          </Field>
          <Field label="Rate (₹, leave blank for quote)">
            <input name="price" type="number" min="0" step="1" />
          </Field>
        </div>
      </SaveForm>
      {providers
        .filter((p) => array(p.service_ids).includes(service.id))
        .map((p) => (
          <div className="table-row" key={p.user_id}>
            <div>
              <strong>{p.business_name || p.name}</strong>
              <small>{array(p.locations).join(", ")}</small>
            </div>
            <button
              className="danger-link"
              onClick={async () => {
                try {
                  await api("/admin/service-provider", {
                    provider_id: p.user_id,
                    service_id: service.id,
                    enabled: false,
                  });
                  await refresh();
                } catch (e) {
                  setError(e.message);
                }
              }}
            >
              Remove
            </button>
          </div>
        ))}
    </>
  );
}
export function AreaProviders({ location, api, refresh, reload, notify }) {
  const [providers, setProviders] = useState([]),
    [error, setError] = useState(""),
    [chosen, setChosen] = useState("");
  useEffect(() => {
    api("/admin/providers")
      .then(setProviders)
      .catch((e) => setError(e.message));
  }, [refresh]);
  const save = async (id, enabled) => {
    await api("/admin/provider-area", {
      provider_id: id,
      location: location.name,
      enabled,
    });
    setProviders(await api("/admin/providers"));
    reload();
    notify("Provider service area updated.");
  };
  const assigned = providers.filter((p) =>
    array(p.locations).includes(location.name),
  );
  return (
    <details className="area-provider-manager">
      <summary>{assigned.length} providers · manage coverage</summary>
      {error && <p className="form-error">{error}</p>}
      {assigned.map((p) => (
        <div className="table-row" key={p.user_id}>
          <span>
            {p.business_name || p.name} · {p.status}
          </span>
          <button
            type="button"
            className="text-link"
            onClick={() =>
              save(p.user_id, false).catch((e) => setError(e.message))
            }
          >
            Remove from area
          </button>
        </div>
      ))}
      {location.active && (
        <SaveForm
          label="Add provider to area"
          onSubmit={() => save(chosen, true)}
        >
          <Field label="Existing provider">
            <select
              required
              value={chosen}
              onChange={(e) => setChosen(e.target.value)}
            >
              <option value="">Choose a provider</option>
              {providers
                .filter((p) => !array(p.locations).includes(location.name))
                .map((p) => (
                  <option key={p.user_id} value={p.user_id}>
                    {p.business_name || p.name}
                  </option>
                ))}
            </select>
          </Field>
        </SaveForm>
      )}
    </details>
  );
}
