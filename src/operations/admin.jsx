"use client";
import React, { useEffect, useState } from "react";
import { Field, Form, PrivateImage, title } from "./shared";
import { toPaise, inr } from "../../lib/operations/money.mjs";
import { CommissionPanel } from "./commission";
import { InvoiceHistory } from "./booking";
import { CallHistory } from "../voice/provider";
export function OperationsAdmin({ tab, api, refresh, reload, notify, open }) {
  if (tab === "commissions")
    return (
      <CommissionPanel
        api={api}
        admin
        refresh={refresh}
        reload={reload}
        notify={notify}
      />
    );
  if (tab === "invoices") return <InvoiceHistory api={api} />;
  if (tab === "voice") return <CallHistory api={api} />;
  if (tab === "media")
    return (
      <MediaReview
        api={api}
        refresh={refresh}
        reload={reload}
        notify={notify}
      />
    );
  if (tab === "workflow") return <AuditPanel api={api} refresh={refresh} />;
  if (tab === "disputes")
    return <BillingReview api={api} refresh={refresh} open={open} />;
  return (
    <OperationsSettings
      api={api}
      refresh={refresh}
      reload={reload}
      notify={notify}
    />
  );
}
export function OperationsSettings({ api, refresh, reload, notify }) {
  const [cfg, setConfig] = useState(null),
    [error, setError] = useState(""),
    [statuses, setStatuses] = useState([]),
    [methods, setMethods] = useState([]);
  useEffect(() => {
    api("/operations/config")
      .then((c) => {
        setConfig(c);
        setStatuses(c.call_statuses);
        setMethods(c.payment_methods);
      })
      .catch((e) => setError(e.message));
  }, [refresh]);
  if (!cfg)
    return (
      <div className="panel">
        {error ? (
          <p className="form-error">{error}</p>
        ) : (
          <p>Loading operational rules…</p>
        )}
      </div>
    );
  const numeric = [
    [
      "request_timeout_minutes",
      "Request acceptance timeout (minutes; 0 means no deadline)",
      0,
      10080,
    ],
    ["otp_ttl_seconds", "Work-start OTP lifetime (seconds)", 60, 1800],
    ["otp_max_attempts", "Maximum incorrect OTP attempts", 1, 10],
    ["commission_percent", "Default commission (%)", 0, 100],
    [
      "deadline_days",
      "Commission payment deadline after week end (days)",
      0,
      60,
    ],
    ["grace_hours", "Commission grace period (hours)", 0, 720],
    ["ring_seconds", "Incoming call ring duration (seconds)", 10, 120],
    ["call_max_seconds", "Maximum call duration (seconds)", 60, 14400],
  ];
  const switches = [
    ["calling_enabled", "Enable in-app WebRTC voice calls"],
    ["relay_only", "Require TURN relay for all voice calls"],
    [
      "commission_enabled",
      "Accrue commission on confirmed billable completed work",
    ],
    ["auto_suspend", "Restrict NEW jobs for overdue earned commission"],
    ["auto_reactivate", "Clear commission restriction after verified payment"],
    ["tax_enabled", "Enable configured, legally applicable tax"],
  ];
  return (
    <div className="panel">
      <h2>Booking, OTP, calling & commission rules</h2>
      <p>
        TURN relay:{" "}
        <strong>
          {cfg.turnConfigured
            ? "Configured"
            : "Not configured — direct connections may fail on some networks"}
        </strong>
        . Microphone audio is not recorded or uploaded.
      </p>
      <Form
        key={refresh}
        label="Save operational rules"
        onSubmit={async (d) => {
          const data = {
            request_expiry_mode: d.request_expiry_mode,
            timezone: d.timezone,
            week_start_day: Number(d.week_start_day),
            call_statuses: statuses,
            payment_methods: methods,
            commission_fixed_paise: toPaise(d.fixed),
            minimum_commission_paise: toPaise(d.minimum),
            tax_percent: Number(d.tax_percent),
            payment_instructions: d.payment_instructions,
            supplier_name: d.supplier_name,
            supplier_address: d.supplier_address,
            tax_registration: d.tax_registration,
            invoice_terms: d.invoice_terms,
          };
          for (const [key] of numeric) data[key] = Number(d[key]);
          for (const [key] of switches) data[key] = d[key] === "on";
          await api("/operations/config", data);
          reload();
          notify("Operational rules saved and audited.");
        }}
      >
        <fieldset>
          <legend>Request distribution & work verification</legend>
          <p>
            Each request is sent to all eligible approved providers. The first
            successful server-side acceptance gets the job.
          </p>
          <div className="form-grid">
            {numeric.slice(0, 3).map(([key, label, min, max]) => (
              <Field key={key} label={label}>
                <input
                  name={key}
                  type="number"
                  min={min}
                  max={max}
                  required
                  defaultValue={cfg[key]}
                />
              </Field>
            ))}
            <Field label="If nobody accepts before the deadline">
              <select
                name="request_expiry_mode"
                defaultValue={cfg.request_expiry_mode}
              >
                <option value="pending">Keep pending</option>
                <option value="expire">Mark expired; customer can retry</option>
              </select>
            </Field>
          </div>
        </fieldset>
        <fieldset>
          <legend>Weekly commission cycle</legend>
          <div className="form-grid">
            {numeric.slice(3, 6).map(([key, label, min, max]) => (
              <Field key={key} label={label}>
                <input
                  name={key}
                  type="number"
                  min={min}
                  max={max}
                  step={key === "commission_percent" ? "0.01" : "1"}
                  required
                  defaultValue={cfg[key]}
                />
              </Field>
            ))}
            <Field label="Fixed commission per billable job (INR)">
              <input
                name="fixed"
                type="number"
                min="0"
                step="0.01"
                required
                defaultValue={(cfg.commission_fixed_paise / 100).toFixed(2)}
              />
            </Field>
            <Field label="Minimum payable commission (INR)">
              <input
                name="minimum"
                type="number"
                min="0"
                step="0.01"
                required
                defaultValue={(cfg.minimum_commission_paise / 100).toFixed(2)}
              />
            </Field>
            <Field label="Week start day">
              <select name="week_start_day" defaultValue={cfg.week_start_day}>
                {[
                  "Sunday",
                  "Monday",
                  "Tuesday",
                  "Wednesday",
                  "Thursday",
                  "Friday",
                  "Saturday",
                ].map((s, i) => (
                  <option key={s} value={i}>
                    {s}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Business timezone">
              <input
                name="timezone"
                defaultValue={cfg.timezone}
                required
                placeholder="Asia/Kolkata"
              />
            </Field>
          </div>
          <p>
            Periods are seven days long. No billable work means ₹0 commission;
            disputed amounts are held. Existing jobs, invoice history, payment
            submission and support remain accessible under a commission
            restriction.
          </p>
          <Field label="Business commission payment instructions">
            <textarea
              name="payment_instructions"
              rows={5}
              maxLength={4000}
              defaultValue={cfg.payment_instructions}
              placeholder="Business account/UPI details and payment instructions"
            />
          </Field>
          <div className="checkbox-grid">
            {["bank_transfer", "upi", "cash"].map((method) => (
              <label key={method}>
                <input
                  type="checkbox"
                  checked={methods.includes(method)}
                  onChange={(e) =>
                    setMethods(
                      e.target.checked
                        ? [...methods, method]
                        : methods.filter((m) => m !== method),
                    )
                  }
                />
                {title(method)}
              </label>
            ))}
          </div>
        </fieldset>
        <fieldset>
          <legend>Internet voice calling</legend>
          <div className="form-grid">
            {numeric.slice(6).map(([key, label, min, max]) => (
              <Field key={key} label={label}>
                <input
                  name={key}
                  type="number"
                  min={min}
                  max={max}
                  required
                  defaultValue={cfg[key]}
                />
              </Field>
            ))}
          </div>
          <p>
            Calls require actual provider acceptance and an authorized booking
            status.
          </p>
          <div className="checkbox-grid">
            {[
              "requested",
              "quote_sent",
              "confirmed",
              "on_the_way",
              "arrived",
              "work_started",
              "work_paused",
            ].map((status) => (
              <label key={status}>
                <input
                  type="checkbox"
                  checked={statuses.includes(status)}
                  onChange={(e) =>
                    setStatuses(
                      e.target.checked
                        ? [...statuses, status]
                        : statuses.filter((s) => s !== status),
                    )
                  }
                />
                {title(status)}
              </label>
            ))}
          </div>
        </fieldset>
        <fieldset>
          <legend>Invoice identity & optional tax</legend>
          <div className="form-grid">
            <Field label="Platform / supplier identity">
              <input
                name="supplier_name"
                defaultValue={cfg.supplier_name}
                maxLength={200}
              />
            </Field>
            <Field label="Tax registration, if legally applicable">
              <input
                name="tax_registration"
                defaultValue={cfg.tax_registration}
                maxLength={100}
              />
            </Field>
            <Field label="Tax percentage">
              <input
                name="tax_percent"
                type="number"
                min="0"
                max="100"
                step="0.01"
                defaultValue={cfg.tax_percent}
              />
            </Field>
          </div>
          <Field label="Platform business address">
            <textarea
              name="supplier_address"
              defaultValue={cfg.supplier_address}
              maxLength={1000}
            />
          </Field>
          <Field label="Invoice terms">
            <textarea
              name="invoice_terms"
              defaultValue={cfg.invoice_terms}
              maxLength={2000}
            />
          </Field>
        </fieldset>
        <fieldset>
          <legend>Policy switches</legend>
          {switches.map(([key, label]) => (
            <label className="checkbox-row" key={key}>
              <input name={key} type="checkbox" defaultChecked={cfg[key]} />
              {label}
            </label>
          ))}
        </fieldset>
      </Form>
    </div>
  );
}
function MediaReview({ api, refresh, reload, notify }) {
  const [items, setItems] = useState([]),
    [error, setError] = useState("");
  useEffect(() => {
    api("/media")
      .then(setItems)
      .catch((e) => setError(e.message));
  }, [refresh]);
  return (
    <div className="panel">
      <h2>Image privacy review</h2>
      <p>
        Review photos for phone numbers, unnecessary private information and
        unsuitable content before sharing them with another participant.
        Commission receipts remain private to their provider and administrators.
      </p>
      {error && <p className="form-error">{error}</p>}
      {items.length ? (
        items.map((a) => (
          <article className="media-review" key={a.id}>
            <PrivateImage id={a.id} />
            <small>
              {title(a.kind)} · {title(a.review_status)} ·{" "}
              {a.booking_id || a.owner_id}
            </small>
            {a.kind !== "commission" && (
              <Form
                label="Record privacy review"
                onSubmit={async (d) => {
                  await api("/media/" + a.id + "/review", {
                    approve: d.decision === "approved",
                    note: d.note,
                  });
                  reload();
                  notify("Image privacy decision saved.");
                }}
              >
                <Field label="Privacy decision">
                  <select name="decision">
                    <option value="rejected">
                      Reject: not suitable for sharing
                    </option>
                    <option value="approved">
                      Approve: checked for private contact details
                    </option>
                  </select>
                </Field>
                <Field label="Privacy review note">
                  <input name="note" required minLength={5} />
                </Field>
              </Form>
            )}
          </article>
        ))
      ) : (
        <p>No private image uploads yet.</p>
      )}
    </div>
  );
}
function AuditPanel({ api, refresh }) {
  const [data, setData] = useState(null),
    [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    const load = () =>
      api("/operations/logs")
        .then((value) => {
          if (!active) return;
          setData(value);
          setError("");
        })
        .catch((e) => active && setError(e.message));
    load();
    const timer = setInterval(load, 5000);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [refresh]);
  return (
    <div className="panel">
      <h2>Booking acceptance, OTP & financial audit</h2>
      <p className="muted-copy">
        This live view shows only activity from the latest 30 minutes. Generic
        administrator activity logs older than 30 minutes are deleted
        automatically.
      </p>
      {error && <p className="form-error">{error}</p>}
      {data &&
        Object.entries(data).map(([kind, items]) => (
          <details key={kind}>
            <summary>
              {title(kind)} · {items.length}
            </summary>
            {items.map((row, i) => (
              <div className="audit-record" key={row.id || i}>
                <strong>{row.event || row.status || row.reason}</strong>
                <small>
                  {row.booking_id || row.provider_id} ·{" "}
                  {row.created_at || row.offered_at || row.accepted_at}
                </small>
                {row.details && (
                  <pre>{JSON.stringify(row.details, null, 2)}</pre>
                )}
              </div>
            ))}
          </details>
        ))}
      <p>
        OTP digits/hashes, call signalling and microphone audio are never
        included in this view.
      </p>
    </div>
  );
}
function BillingReview({ api, refresh, open }) {
  const [items, setItems] = useState([]),
    [error, setError] = useState("");
  useEffect(() => {
    api("/operations/bills")
      .then(setItems)
      .catch((e) => setError(e.message));
  }, [refresh]);
  return (
    <div className="panel">
      <h2>Final bills & disputes</h2>
      {error && <p className="form-error">{error}</p>}
      {items.length ? (
        items.map((b) => (
          <div className="table-row" key={b.id}>
            <div>
              <strong>
                {b.provider_name} · {inr(b.total_paise)}
              </strong>
              <small>
                {b.booking_id} · {title(b.status)} ·{" "}
                {b.dispute_reason || b.description}
              </small>
            </div>
            <button
              className="text-link"
              onClick={() =>
                open({ type: "booking", id: b.booking_id, role: "admin" })
              }
            >
              Review booking & bill
            </button>
          </div>
        ))
      ) : (
        <p>No submitted bills yet.</p>
      )}
    </div>
  );
}
