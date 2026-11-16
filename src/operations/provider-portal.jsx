"use client";
import React, { useEffect, useRef, useState } from "react";
import { getBrowserClient } from "../../lib/supabase/browser";
import { ProviderEditor, ProviderAvailability } from "../marketplace-tools";
import { CredentialsPanel } from "../admin-tools";
import { InvoiceHistory } from "./booking";
import { CommissionPanel } from "./commission";
import { CallHistory } from "../voice/provider";
import { title } from "./shared";
export function useBookingFeed({ me, api, refresh, role, notify }) {
  const [items, setItems] = useState([]),
    [error, setError] = useState("");
  const previous = useRef([]);
  useEffect(() => {
    if (!me?.id) return;
    let alive = true;
    const load = () =>
      api("/bookings" + (role === "provider" ? "?role=provider" : ""))
        .then((next) => {
          if (!alive) return;
          if (role === "provider") {
            for (const old of previous.current.filter((b) => !b.provider_id)) {
              if (
                !next.some((b) => b.id === old.id) &&
                old.status === "requested"
              )
                notify(
                  "This booking has already been accepted by another provider.",
                );
            }
          }
          previous.current = next;
          setItems(next);
          setError("");
        })
        .catch((e) => {
          if (alive) setError(e.message);
        });
    load();
    const timer = setInterval(load, 3000);
    const client = getBrowserClient();
    const channel = client
      ?.channel("booking-feed-" + me.id + "-" + role)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "booking_events" },
        load,
      )
      .subscribe();
    return () => {
      alive = false;
      clearInterval(timer);
      if (channel) void client.removeChannel(channel).catch(() => {});
    };
  }, [me?.id, refresh, role]);
  return { items, error };
}
export function ProviderOperationsPortal(props) {
  const {
    me,
    api,
    refresh,
    open,
    reload,
    notify,
    catalog,
    locations,
    renderMessages,
    renderSupport,
  } = props;
  const [account, setAccount] = useState(null);
  const [tab, setTab] = useState("requests"),
    [history, setHistory] = useState({ offers: [], jobs: [] });
  const { items: jobs, error } = useBookingFeed({
    me,
    api,
    refresh,
    role: "provider",
    notify,
  });
  useEffect(() => {
    api("/commissions").then(setAccount).catch(()=>{});
    api("/provider/history")
      .then(setHistory)
      .catch(() => {});
  }, [refresh, jobs.length]);
  const own = jobs.filter((b) => b.provider_id === me.id),
    requests = jobs.filter(
      (b) => !b.provider_id || (b.provider_id === me.id && !b.accepted_at),
    ),
    active = own.filter(
      (b) =>
        b.accepted_at &&
        !["work_completed", "cancelled", "disputed"].includes(b.status),
    ),
    completed = own.filter((b) => b.status === "work_completed");
  const tabs = [
    ["requests", "New Requests"],
    ["accepted", "Accepted Jobs"],
    ["active", "Active Jobs"],
    ["completed", "Completed Jobs"],
    ["rejected", "Rejected Requests"],
    ["history", "Job History"],
    ["messages", "Customer Messages"],
    ["verification", "Work Start OTP"],
    ["billing", "Final Bills"],
    ["invoices", "Invoice History"],
    ["earnings", "Weekly Earnings"],
    ["commission", "Weekly Commission"],
    ["payments", "Submit Commission Payment"],
    ["payment_history", "Commission Payment History"],
    ["account", "Account Status"],
    ["availability", "Availability"],
    ["profile", "Profile"],
    ["calls", "Call History"],
    ["notifications", "Notifications"],
    ["support", "Support"],
  ];
  const row = (b) => (
    <button
      className="booking-row"
      key={b.id}
      onClick={() => open({ type: "booking", id: b.id, role: "provider" })}
    >
      <span className="booking-info">
        <strong>{b.service_name}</strong>
        <small>
          {new Date(b.scheduled_at).toLocaleString()} · {b.location} ·{" "}
          {b.booking_reference}
        </small>
      </span>
      <span className={"status " + b.status}>
        {b.provider_id && !b.accepted_at
          ? "Awaiting your acceptance"
          : title(b.status)}
      </span>
    </button>
  );
  let shown =
    tab === "requests"
      ? requests
      : tab === "accepted"
        ? active.filter((b) =>
            [
              "requested",
              "quote_sent",
              "confirmed",
              "on_the_way",
              "arrived",
            ].includes(b.status),
          )
        : tab === "active"
          ? active
          : tab === "completed"
            ? completed
            : tab === "verification"
              ? own.filter((b) => b.status === "arrived")
              : tab === "billing"
                ? own.filter((b) =>
                    ["work_started", "work_completed", "disputed"].includes(
                      b.status,
                    ),
                  )
                : own;
  return (
    <section className="section-shell portal">
      <div className="portal-heading">
        <div>
          <div className="eyebrow muted">YOUR LOCAL MATE PROVIDER PORTAL</div>
          <h1>Your work. Your way.</h1>
          <p>{me.provider.business_name || me.name}</p>
        </div>
        <span className={"status " + me.provider.status}>
          {title(me.provider.status)}
        </span>
      </div>
      {me.provider.status !== "approved" && (
        <div className="notice">
          Provider verification: {title(me.provider.status)}. Approval and
          online availability are required for new requests.
        </div>
      )}
      {account?.current_commission_blocked && (
        <div className="notice">
          SUSPENDED — COMMISSION PAYMENT PENDING. Existing jobs, support,
          invoices and payment submission remain available.
        </div>
      )}
      {error && <p className="form-error">{error}</p>}
      <div className="stats-grid">
        {[
          ["New requests", requests.length],
          ["Active jobs", active.length],
          ["Completed", completed.length],
        ].map(([label, value]) => (
          <div className="stat" key={label}>
            <span>{label}</span>
            <strong>{value}</strong>
          </div>
        ))}
      </div>
      <div className="portal-tabs">
        {tabs.map(([key, label]) => (
          <button
            key={key}
            className={tab === key ? "selected" : ""}
            onClick={() => setTab(key)}
          >
            {label}
          </button>
        ))}
      </div>
      {[
        "commission",
        "earnings",
        "payments",
        "payment_history",
        "account",
      ].includes(tab) ? (
        <CommissionPanel
          api={api}
          refresh={refresh}
          reload={reload}
          notify={notify}
        />
      ) : tab === "invoices" ? (
        <InvoiceHistory api={api} />
      ) : tab === "calls" ? (
        <CallHistory api={api} />
      ) : tab === "profile" ? (
        <div className="panel">
          <CredentialsPanel me={me} api={api} notify={notify} reload={reload} />
          <ProviderEditor
            key={JSON.stringify(me.provider)}
            me={me}
            catalog={catalog}
            locations={locations}
            api={api}
            reload={reload}
            notify={notify}
          />
        </div>
      ) : tab === "availability" ? (
        <div className="panel">
          <ProviderAvailability
            provider={me.provider}
            api={api}
            reload={reload}
            notify={notify}
          />
        </div>
      ) : tab === "messages" ? (
        <div className="panel">{renderMessages(jobs)}</div>
      ) : tab === "notifications" ? (
        <div className="panel">
          <h2>Notifications</h2>
          <button
            className="button secondary"
            onClick={() => open({ type: "notifications" })}
          >
            Open booking and account notifications
          </button>
        </div>
      ) : tab === "support" ? (
        renderSupport()
      ) : tab === "rejected" ? (
        <div className="panel">
          <h2>Rejected & unavailable requests</h2>
          {history.offers
            .filter((o) => ["rejected", "lost", "expired"].includes(o.status))
            .map((o) => (
              <div className="table-row" key={o.booking_id}>
                <div>
                  <strong>
                    {o.service_name} · {o.location}
                  </strong>
                  <small>{o.booking_id}</small>
                </div>
                <span>
                  {o.status === "lost"
                    ? "Accepted by another provider"
                    : title(o.status)}
                </span>
              </div>
            ))}
        </div>
      ) : (
        <div className="panel">
          <h2>{tabs.find(([key]) => key === tab)?.[1]}</h2>
          {tab === "requests" && (
            <p>
              Requests are shared with all eligible providers. The first
              successful server-side acceptance gets the job.
            </p>
          )}
          {tab === "verification" && (
            <p>
              Open an arrived job and verify the customer's OTP before starting
              work.
            </p>
          )}
          {tab === "billing" && (
            <p>
              Open a job to enter the final bill. Only customer-approved extra
              charges can be billed.
            </p>
          )}
          {shown.length ? shown.map(row) : <p>No jobs in this section yet.</p>}
        </div>
      )}
    </section>
  );
}
