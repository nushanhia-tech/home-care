"use client";
import React, { useEffect, useState } from "react";
import { Field, Form, upload, PrivateImage, title } from "./shared";
import { useVoiceState } from "../voice/provider";
import { toPaise, inr } from "../../lib/operations/money.mjs";
export function BookingOperations({
  booking: b,
  me,
  api,
  reload,
  notify,
  refresh,
}) {
  const policy = useVoiceState()?.policy;
  const [billDraft, setBillDraft] = useState({
    labour: "",
    materials: "0",
    discount: "0",
  });
  const [data, setData] = useState(null),
    [error, setError] = useState(""),
    [otp, setOTP] = useState(null),
    [media, setMedia] = useState([]);
  const customer = b.customer_id === me.id,
    provider = b.provider_id === me.id;
  const load = () =>
    api("/bookings/" + b.id + "/finances")
      .then(setData)
      .catch((e) => setError(e.message));
  useEffect(() => {
    let active = true;
    const update = () => {
      load();
      api("/media?booking=" + b.id)
        .then((v) => {
          if (active) setMedia(v);
        })
        .catch(() => {});
    };
    update();
    const timer = setInterval(update, 5000);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [b.id, refresh]);
  const run = async (path, body) => {
    await api(path, body);
    await load();
    reload();
  };
  const bill = data?.bills.find((x) => x.status !== "void");
  const previewAmount = (value) => {
    try {
      return toPaise(value);
    } catch {
      return 0;
    }
  };
  const extraPreview =
    (data?.charges || [])
      .filter((c) => c.status === "approved")
      .reduce((sum, c) => sum + Number(c.amount_paise), 0) +
    Number(b.quotes?.find((q) => q.status === "approved")?.additional || 0) *
      100;
  const subPreview =
    previewAmount(billDraft.labour) +
    previewAmount(billDraft.materials) +
    extraPreview -
    previewAmount(billDraft.discount);
  const totalPreview =
    subPreview +
    Math.round(
      (Math.max(0, subPreview) *
        Number(policy?.tax_enabled ? policy.tax_percent : 0)) /
        100,
    );
  return (
    <section className="booking-operations">
      <h3>Work verification & final bill</h3>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {b.status === "arrived" && customer && (
        <div className="otp-card">
          <h3>Your private work-start OTP</h3>
          <p>
            Share this code only with your assigned provider when they have
            arrived and you are ready for work to start.
          </p>
          <button
            className="button secondary"
            onClick={async () => {
              try {
                let value = await api("/bookings/" + b.id + "/start-otp");
                if (!value) {
                  await api("/bookings/" + b.id + "/start-otp", {});
                  value = await api("/bookings/" + b.id + "/start-otp");
                }
                setOTP(value);
              } catch (e) {
                setError(e.message);
              }
            }}
          >
            View work-start OTP
          </button>
          {otp &&
            (otp.locked ? (
              <p className="form-error">
                Verification is locked. Contact Local Mate support.
              </p>
            ) : (
              <>
                <strong className="otp-code">{otp.code}</strong>
                <small>
                  Expires {new Date(otp.expires_at).toLocaleTimeString()}
                </small>
              </>
            ))}
        </div>
      )}
      {b.status === "arrived" && provider && (
        <div className="otp-card">
          <h3>Verify the customer before starting work</h3>
          <button
            className="button secondary"
            onClick={async () => {
              try {
                await api("/bookings/" + b.id + "/start-otp", {});
                notify("The customer can view their OTP in this booking.");
              } catch (e) {
                setError(e.message);
              }
            }}
          >
            Request customer OTP
          </button>
          <Form
            label="Verify OTP & start work"
            onSubmit={async (d) => {
              await run("/bookings/" + b.id + "/verify-otp", { code: d.code });
              notify("Customer verified. Work has started.");
            }}
          >
            <Field label="Customer's six-digit OTP">
              <input
                name="code"
                inputMode="numeric"
                autoComplete="one-time-code"
                required
                pattern="[0-9]{6}"
                maxLength={6}
              />
            </Field>
          </Form>
        </div>
      )}
      {me.admin && b.status === "arrived" && (
        <details>
          <summary>Audited OTP exception</summary>
          <Form
            label="Approve work-start exception"
            onSubmit={async (d) => {
              await run("/bookings/" + b.id + "/otp-exception", {
                reason: d.reason,
              });
              notify("The verification exception was recorded.");
            }}
          >
            <Field label="Verified reason for exception">
              <textarea
                name="reason"
                required
                minLength={10}
                maxLength={1000}
              />
            </Field>
          </Form>
        </details>
      )}
      {provider && b.status === "work_paused" && (
        <button
          className="button"
          onClick={() =>
            run("/bookings/" + b.id + "/status", {
              status: "work_started",
            }).catch((e) => setError(e.message))
          }
        >
          Resume verified work
        </button>
      )}
      {data && (
        <>
          <h3>Additional charges</h3>
          {data.charges.length ? (
            data.charges.map((c) => (
              <div className="charge-row" key={c.id}>
                <strong>{inr(c.amount_paise)}</strong>
                <p>{c.description}</p>
                <span className={"status " + c.status}>{title(c.status)}</span>
                {customer && c.status === "pending" && (
                  <div className="actions">
                    {["approved", "rejected", "disputed"].map((action) => (
                      <button
                        className="button secondary"
                        key={action}
                        onClick={() =>
                          run("/charges/" + c.id + "/respond", {
                            action,
                          }).catch((e) => setError(e.message))
                        }
                      >
                        {title(action)}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            ))
          ) : (
            <p>No additional charges have been requested.</p>
          )}
          {provider &&
            [
              "confirmed",
              "on_the_way",
              "arrived",
              "work_started",
              "work_paused",
            ].includes(b.status) && (
              <details>
                <summary>Request approval for extra work / cost</summary>
                <Form
                  label="Request customer approval"
                  onSubmit={async (d) => {
                    await run("/bookings/" + b.id + "/charges", {
                      amount_paise: toPaise(d.amount),
                      description: d.description,
                    });
                    notify("Charge sent for customer approval.");
                  }}
                >
                  <Field label="Additional amount (INR)">
                    <input
                      type="number"
                      name="amount"
                      min="0.01"
                      step="0.01"
                      required
                    />
                  </Field>
                  <Field label="Extra work and cost explanation">
                    <textarea name="description" required maxLength={1000} />
                  </Field>
                </Form>
              </details>
            )}
          {provider &&
            ["work_started", "work_completed", "disputed"].includes(b.status) &&
            !bill && (
              <div className="final-bill">
                <h3>Complete work & submit final bill</h3>
                <p>
                  Only approved extra charges are included. The base amount must
                  stay within the agreed estimate or quote.
                </p>
                <Form
                  label="Mark work completed & send bill"
                  onSubmit={async (d) => {
                    await run("/bookings/" + b.id + "/bill", {
                      labour_paise: toPaise(d.labour),
                      materials_paise: toPaise(d.materials),
                      discount_paise: toPaise(d.discount),
                      description: d.description,
                    });
                    notify(
                      "Work completed. The final bill is awaiting customer confirmation.",
                    );
                  }}
                >
                  <div className="form-grid">
                    <Field label="Labour charge (INR)">
                      <input
                        type="number"
                        name="labour"
                        value={billDraft.labour}
                        onChange={(e) =>
                          setBillDraft({ ...billDraft, labour: e.target.value })
                        }
                        min="0"
                        step="0.01"
                        required
                      />
                    </Field>
                    <Field label="Material cost (INR)">
                      <input
                        type="number"
                        name="materials"
                        value={billDraft.materials}
                        onChange={(e) =>
                          setBillDraft({
                            ...billDraft,
                            materials: e.target.value,
                          })
                        }
                        min="0"
                        step="0.01"
                        required
                      />
                    </Field>
                    <Field label="Discount (INR)">
                      <input
                        type="number"
                        name="discount"
                        value={billDraft.discount}
                        onChange={(e) =>
                          setBillDraft({
                            ...billDraft,
                            discount: e.target.value,
                          })
                        }
                        min="0"
                        step="0.01"
                        required
                      />
                    </Field>
                  </div>
                  <p>
                    Approved additional charges:{" "}
                    <strong>
                      {inr(
                        data.charges
                          .filter((c) => c.status === "approved")
                          .reduce((a, c) => a + Number(c.amount_paise), 0),
                      )}
                    </strong>
                    . Tax and the final total are calculated by the server.
                  </p>
                  <Field label="Completed work description">
                    <textarea name="description" required maxLength={2000} />
                  </Field>
                </Form>
              </div>
            )}
          {bill && (
            <div className="bill-card">
              <h3>Final bill · {title(bill.status)}</h3>
              {[
                ["Labour", bill.labour_paise],
                ["Materials", bill.materials_paise],
                ["Approved additional charges", bill.additional_paise],
                ["Discount", -Number(bill.discount_paise)],
                ["Tax", bill.tax_paise],
              ].map(([label, value]) => (
                <div className="offer-row" key={label}>
                  <span>{label}</span>
                  <strong>{inr(value)}</strong>
                </div>
              ))}
              <div className="offer-row">
                <strong>Total payable</strong>
                <strong>{inr(bill.total_paise)}</strong>
              </div>
              <p>{bill.description}</p>
              {bill.dispute_reason && (
                <p className="form-error">Dispute: {bill.dispute_reason}</p>
              )}
              {customer && bill.status === "submitted" && (
                <button
                  className="button"
                  onClick={() =>
                    run("/bills/" + bill.id + "/respond", { action: "confirm" })
                      .then(() =>
                        notify("Bill confirmed. Your PDF invoice is ready."),
                      )
                      .catch((e) => setError(e.message))
                  }
                >
                  Confirm final bill
                </button>
              )}
              {customer && ["submitted", "confirmed"].includes(bill.status) && (
                <details>
                  <summary>Dispute this bill</summary>
                  <Form
                    label="Submit bill dispute"
                    onSubmit={async (d) => {
                      await run("/bills/" + bill.id + "/respond", {
                        action: "dispute",
                        reason: d.reason,
                      });
                      notify(
                        "Bill disputed. Commission is held while it is reviewed.",
                      );
                    }}
                  >
                    <Field label="What needs review?">
                      <textarea
                        name="reason"
                        required
                        minLength={5}
                        maxLength={2000}
                      />
                    </Field>
                  </Form>
                </details>
              )}
              {me.admin && (
                <details>
                  <summary>
                    Administrator bill resolution / verified cash payment
                  </summary>
                  {["successful", "partially_refunded"].includes(
                    b.payment_status,
                  ) && (
                    <Form
                      label="Record verified refund"
                      onSubmit={async (d) => {
                        await run("/bookings/" + b.id + "/refund", {
                          amount_paise: toPaise(d.amount),
                          reference: d.reference,
                          reason: d.reason,
                        });
                        notify(
                          "Verified refund recorded; commission is held for review.",
                        );
                      }}
                    >
                      <p>
                        Record only an actual, reconciled bank/cash refund. This
                        does not initiate a transfer.
                      </p>
                      <Field label="Verified refund amount (INR)">
                        <input
                          name="amount"
                          type="number"
                          step="0.01"
                          min="0.01"
                          required
                        />
                      </Field>
                      <Field label="Refund transaction reference">
                        <input name="reference" required minLength={5} />
                      </Field>
                      <Field label="Refund verification reason">
                        <textarea name="reason" required minLength={10} />
                      </Field>
                    </Form>
                  )}
                  <Form
                    label="Record bill resolution"
                    onSubmit={async (d) => {
                      await run("/bills/" + bill.id + "/resolve", {
                        action: d.action,
                        reason: d.reason,
                      });
                      notify("Audited bill resolution saved.");
                    }}
                  >
                    <Field label="Resolution">
                      <select name="action">
                        <option value="confirm">Confirm verified bill</option>
                        <option value="void">
                          Void bill for correction / reconciliation
                        </option>
                      </select>
                    </Field>
                    <Field label="Evidence and resolution reason">
                      <textarea name="reason" minLength={10} required />
                    </Field>
                  </Form>
                  {bill.status === "confirmed" &&
                    b.payment_status !== "successful" && (
                      <Form
                        label="Record verified cash payment"
                        onSubmit={async (d) => {
                          await run("/bookings/" + b.id + "/cash", {
                            amount_paise: bill.total_paise,
                            reference: d.reference,
                          });
                          notify("Verified cash receipt recorded.");
                        }}
                      >
                        <p>
                          Record this only after verifying the actual cash
                          payment of {inr(bill.total_paise)}.
                        </p>
                        <Field label="Verified cash receipt reference">
                          <input name="reference" required minLength={5} />
                        </Field>
                      </Form>
                    )}
                </details>
              )}
            </div>
          )}
          {data.invoices.length > 0 && (
            <>
              <h3>Invoices</h3>
              {data.invoices.map((i) => (
                <div className="table-row" key={i.id}>
                  <div>
                    <strong>{i.number}</strong>
                    <small>
                      {inr(i.total_paise)} · {title(i.status)}
                    </small>
                  </div>
                  <a
                    className="text-link"
                    href={"/api/invoices/" + i.id + "/pdf?view=1"}
                    target="_blank"
                    rel="noreferrer"
                  >
                    View invoice
                  </a>
                  <a
                    className="text-link"
                    href={"/api/invoices/" + i.id + "/pdf"}
                  >
                    Download PDF
                  </a>
                </div>
              ))}
            </>
          )}
        </>
      )}
      <h3>Job photos & attachments</h3>
      <p>
        Images remain private until an administrator approves them for sharing.
        Avoid phone numbers and unnecessary personal details.
      </p>
      <div className="media-grid">
        {media.map((a) => (
          <div key={a.id}>
            <PrivateImage id={a.id} />
            <small>
              {title(a.kind)} · {title(a.review_status)}
            </small>
          </div>
        ))}
      </div>
      <Form
        label="Upload private job photo"
        onSubmit={async (d) => {
          const file = document.getElementById("job-photo-" + b.id).files[0];
          await upload(file, d.kind, b.id);
          reload();
          notify("Image uploaded for privacy review.");
        }}
      >
        <Field label="Photo purpose">
          <select name="kind">
            {(customer ? ["booking"] : ["before", "after"]).map((k) => (
              <option key={k}>{k}</option>
            ))}
          </select>
        </Field>
        <Field label="Job photo">
          <input
            id={"job-photo-" + b.id}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            required
          />
        </Field>
      </Form>
    </section>
  );
}
export function InvoiceHistory({ api }) {
  const [items, setItems] = useState([]),
    [error, setError] = useState("");
  useEffect(() => {
    api("/invoices")
      .then(setItems)
      .catch((e) => setError(e.message));
  }, []);
  return (
    <div className="panel">
      <h2>Invoice history</h2>
      {error && <p className="form-error">{error}</p>}
      {items.length ? (
        items.map((i) => (
          <div className="table-row" key={i.id}>
            <div>
              <strong>{i.number}</strong>
              <small>
                {i.provider_name} · {inr(i.total_paise)} ·{" "}
                {title(i.payment_status)}
              </small>
            </div>
            <a
              className="text-link"
              href={"/api/invoices/" + i.id + "/pdf?view=1"}
              target="_blank"
              rel="noreferrer"
            >
              View
            </a>
            <a className="text-link" href={"/api/invoices/" + i.id + "/pdf"}>
              Download PDF
            </a>
          </div>
        ))
      ) : (
        <p>
          Confirmed bills generate invoices here. A pending invoice is not proof
          of payment.
        </p>
      )}
    </div>
  );
}
