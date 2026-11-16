"use client";
import React, { useEffect, useState } from "react";
import { Field, Form, upload, PrivateImage, title } from "./shared";
import { toPaise, inr } from "../../lib/operations/money.mjs";
export function CommissionPanel({
  api,
  admin = false,
  refresh,
  reload,
  notify,
}) {
  const [week, setWeek] = useState(null);
  const [data, setData] = useState(null),
    [error, setError] = useState(""),
    [filter, setFilter] = useState("all"),
    [providers, setProviders] = useState([]),
    [ruleType, setRuleType] = useState("provider");
  const load = () =>
    api("/commissions")
      .then(setData)
      .catch((e) => setError(e.message));
  useEffect(() => {
    load();
    if (!admin)
      api("/provider/weekly-summary")
        .then(setWeek)
        .catch(() => {});
    if (admin)
      api("/admin/providers")
        .then(setProviders)
        .catch(() => {});
  }, [refresh, admin]);
  if (!data)
    return (
      <div className="panel">
        {error ? (
          <p className="form-error" role="alert">
            {error}
          </p>
        ) : (
          <p>Loading commission records…</p>
        )}
      </div>
    );
  const totals = data.statements.reduce(
    (sum, s) => ({
      ...sum,
      due: sum.due + Number(s.outstanding_paise),
      paid: sum.paid + Number(s.paid_paise),
      billable: sum.billable + Number(s.billable_paise),
      jobs: sum.jobs + Number(s.jobs),
    }),
    { due: 0, paid: 0, billable: 0, jobs: 0 },
  );
  const shown = data.statements.filter(
      (s) => filter === "all" || s.status === filter,
    ),
    unpaid = data.statements.filter((s) => Number(s.outstanding_paise) > 0);
  return (
    <>
      <div className="panel">
        <h2>
          {admin
            ? "Weekly Commission Management"
            : "Weekly earnings & commission"}
        </h2>
        {error && <p className="form-error">{error}</p>}
        {!admin && (
          <div className="notice">
            <strong>
              {data.current_commission_blocked
                ? "SUSPENDED — COMMISSION PAYMENT PENDING"
                : "No commission restriction on new requests"}
            </strong>
            <p>
              {data.current_commission_blocked
                ? "Existing jobs, invoices, support and payment submission remain accessible."
                : "No commission-generating work means ₹0 due and no commission suspension. Other verification or account restrictions still apply."}
            </p>
          </div>
        )}
        {week && (
          <div className="stats-grid">
            <div className="stat">
              <span>Jobs completed this week</span>
              <strong>{week.jobs_completed}</strong>
            </div>
            <div className="stat">
              <span>Billable this week</span>
              <strong>{inr(week.billable_paise)}</strong>
            </div>
            <div className="stat">
              <span>This week commission</span>
              <strong>{inr(week.commission_paise)}</strong>
            </div>
          </div>
        )}
        <div className="stats-grid">
          <div className="stat">
            <span>Billable jobs</span>
            <strong>{totals.jobs}</strong>
          </div>
          <div className="stat">
            <span>Billable amount</span>
            <strong>{inr(totals.billable)}</strong>
          </div>
          <div className="stat">
            <span>Outstanding commission</span>
            <strong>{inr(totals.due)}</strong>
          </div>
          <div className="stat">
            <span>Verified payments</span>
            <strong>{inr(totals.paid)}</strong>
          </div>
        </div>
        <Field label="Filter commission statements">
          <select value={filter} onChange={(e) => setFilter(e.target.value)}>
            {[
              "all",
              "paid",
              "unpaid",
              "awaiting_verification",
              "rejected",
              "overdue",
              "no_commission_due",
              "disputed",
            ].map((s) => (
              <option value={s} key={s}>
                {title(s)}
              </option>
            ))}
          </select>
        </Field>
        {shown.length ? (
          shown.map((s) => (
            <article
              className="commission-statement"
              key={s.provider_id + s.period_id}
            >
              <h3>{s.provider_name}</h3>
              <small>
                {new Date(s.starts_at).toLocaleDateString()} –{" "}
                {new Date(s.ends_at).toLocaleDateString()} · {s.provider_id}
              </small>
              <div className="offer-row">
                <span>
                  {s.jobs} jobs · {inr(s.billable_paise)} billable
                </span>
                <strong>{inr(s.outstanding_paise)} due</strong>
              </div>
              <p>
                {title(s.status)} · deadline{" "}
                {new Date(s.deadline_at).toLocaleString()} · grace until{" "}
                {new Date(s.grace_until).toLocaleString()}
              </p>
              {Number(s.held_paise) > 0 && (
                <p>Disputed commission held: {inr(s.held_paise)}</p>
              )}
              <details>
                <summary>Job and commission calculation details</summary>
                {s.entries.map((e) => (
                  <div className="table-row" key={e.booking_id}>
                    <small>{e.booking_id}</small>
                    <span>
                      {e.rate_percent}% + {inr(e.fixed_paise)} ·{" "}
                      {inr(e.commission_paise)} · {title(e.status)}
                    </span>
                  </div>
                ))}
              </details>
            </article>
          ))
        ) : (
          <p>
            No commission statements match this filter. Providers with no
            commission-generating jobs owe ₹0.
          </p>
        )}
      </div>
      {!admin && unpaid.length > 0 && (
        <div className="panel">
          <h2>Submit commission payment</h2>
          <p>
            Transfer to the actual Local Mate business account shown below, then
            submit the transaction evidence. Uploading a screenshot does not
            mark commission as paid.
          </p>
          {data.config.payment_instructions ? (
            <pre className="payment-instructions">
              {data.config.payment_instructions}
            </pre>
          ) : (
            <p className="form-error">
              The administrator must configure the business payment details
              before you can submit a payment.
            </p>
          )}
          <Form
            label="Submit for admin verification"
            onSubmit={async (d) => {
              const file = document.getElementById("commission-proof").files[0];
              const proof_id = await upload(file, "commission");
              await api("/commissions/payments", {
                period_id: d.period,
                amount_paise: toPaise(d.amount),
                method: d.method,
                reference: d.reference,
                paid_at: new Date(d.paid_at).toISOString(),
                proof_id,
              });
              reload();
              notify(
                "Payment proof submitted. Awaiting administrator verification.",
              );
            }}
          >
            <Field label="Weekly statement">
              <select name="period" required>
                {unpaid.map((s) => (
                  <option key={s.period_id} value={s.period_id}>
                    {new Date(s.starts_at).toLocaleDateString()} ·{" "}
                    {inr(s.outstanding_paise)} outstanding
                  </option>
                ))}
              </select>
            </Field>
            <div className="form-grid">
              <Field label="Amount transferred (INR)">
                <input
                  name="amount"
                  type="number"
                  min="0.01"
                  step="0.01"
                  required
                />
              </Field>
              <Field label="Payment method">
                <select name="method">
                  {data.config.payment_methods.map((m) => (
                    <option key={m}>{m}</option>
                  ))}
                </select>
              </Field>
              <Field label="Actual transaction date / time">
                <input name="paid_at" type="datetime-local" required />
              </Field>
              <Field label="Transaction reference">
                <input
                  name="reference"
                  required
                  minLength={3}
                  maxLength={200}
                />
              </Field>
            </div>
            <Field label="Private payment receipt / screenshot">
              <input
                id="commission-proof"
                type="file"
                accept="image/jpeg,image/png,image/webp"
                required
              />
            </Field>
          </Form>
        </div>
      )}
      <div className="panel">
        <h2>Commission payment history</h2>
        {data.payments.length ? (
          data.payments.map((p) => (
            <article className="commission-payment" key={p.id}>
              <div className="panel-heading">
                <strong>
                  {inr(p.amount_paise)} · {p.method}
                </strong>
                <span className={"status " + p.status}>{title(p.status)}</span>
              </div>
              <small>
                {p.provider_id} · {p.reference} · submitted{" "}
                {new Date(p.submitted_at).toLocaleString()}
              </small>
              <PrivateImage id={p.proof_id} caption="Private payment proof" />
              {p.review_note && <p>Review: {p.review_note}</p>}
              {admin && p.status === "awaiting_verification" && (
                <Form
                  label="Record payment verification"
                  onSubmit={async (d) => {
                    await api("/commissions/payments/" + p.id + "/review", {
                      approve: d.decision === "approve",
                      reason: d.reason,
                    });
                    reload();
                    notify("Payment review saved in the audit log.");
                  }}
                >
                  <p>
                    Verify the actual business-account credit before approving.
                    A screenshot alone is not sufficient verification.
                  </p>
                  <Field label="Verification decision">
                    <select name="decision">
                      <option value="reject">
                        Reject / request corrected proof
                      </option>
                      <option value="approve">Approve verified payment</option>
                    </select>
                  </Field>
                  <Field label="Verification evidence or rejection reason">
                    <textarea
                      name="reason"
                      required
                      minLength={5}
                      maxLength={2000}
                    />
                  </Field>
                </Form>
              )}
            </article>
          ))
        ) : (
          <p>No commission payment submissions yet.</p>
        )}
      </div>
      {admin && (
        <div className="panel">
          <h2>Provider / category commission rules</h2>
          <Field label="Rule applies to">
            <select
              value={ruleType}
              onChange={(e) => setRuleType(e.target.value)}
            >
              <option value="provider">Individual provider</option>
              <option value="category">Service category</option>
            </select>
          </Field>
          <Form
            label="Save commission rule"
            onSubmit={async (d) => {
              await api("/commissions/rule", {
                ...(ruleType === "provider"
                  ? { provider_id: d.provider_id }
                  : { category: d.category }),
                percent: Number(d.percent),
                fixed_paise: toPaise(d.fixed),
                active: d.active === "on",
              });
              reload();
              notify(
                "Commission rule saved. Existing job snapshots are preserved.",
              );
            }}
          >
            {ruleType === "provider" ? (
              <Field label="Provider">
                <select name="provider_id" required>
                  {providers.map((p) => (
                    <option key={p.user_id} value={p.user_id}>
                      {p.business_name || p.name}
                    </option>
                  ))}
                </select>
              </Field>
            ) : (
              <Field label="Service category">
                <input name="category" required maxLength={100} />
              </Field>
            )}
            <div className="form-grid">
              <Field label="Commission percentage">
                <input
                  name="percent"
                  type="number"
                  min="0"
                  max="100"
                  step="0.01"
                  required
                />
              </Field>
              <Field label="Fixed fee per billable job (INR)">
                <input
                  name="fixed"
                  type="number"
                  min="0"
                  step="0.01"
                  defaultValue="0"
                  required
                />
              </Field>
            </div>
            <label className="checkbox-row">
              <input name="active" type="checkbox" defaultChecked />
              Rule active
            </label>
          </Form>
          {data.rules.map((r) => (
            <div className="table-row" key={r.id}>
              <span>
                {r.provider_id || r.category} · {r.percent}% +{" "}
                {inr(r.fixed_paise)}
              </span>
              <span>{r.active ? "Active" : "Inactive"}</span>
            </div>
          ))}
        </div>
      )}
    </>
  );
}
