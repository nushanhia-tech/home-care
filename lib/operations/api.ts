import { NextRequest, NextResponse } from "next/server";
import { type SupabaseClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { randomUUID, timingSafeEqual } from "node:crypto";
import { createServiceAdmin } from "../supabase/admin";
import { ApiError } from "../errors";
import { makeOTP, otpHash, decryptOTP, iceConfiguration } from "./crypto.mjs";
import { invoicePDF } from "./pdf";
const json = (data: any, status = 200) =>
  NextResponse.json(data, {
    status,
    headers: { "Cache-Control": "private, no-store" },
  });
async function checked(p: PromiseLike<any>) {
  const { data, error } = await p;
  if (error) throw error;
  return data;
}
const text = (v: any, max = 2000) => {
  if (typeof v !== "string" || !v.trim() || v.length > max)
    throw new ApiError("Please check the required fields.");
  return v.trim();
};
function otpSecret() {
  return (
    process.env.OTP_HMAC_SECRET ||
    process.env.SUPABASE_SECRET_KEY ||
    process.env.SUPABASE_SERVICE_ROLE_KEY ||
    ""
  );
}
export async function operationsAPI(
  req: NextRequest,
  path: string,
  body: any,
  client: SupabaseClient,
  user: any,
  admin: boolean,
) {
  const method = req.method;
  if (path === "/operations/config") {
    if (method === "GET") {
      const cfg = await checked(client.rpc("operations_config"));
      return json({
        ...cfg,
        turnConfigured: !!(
          process.env.TURN_URLS && process.env.TURN_SHARED_SECRET
        ),
        uploadsConfigured: true,
      });
    }
    if (method === "POST") {
      await checked(client.rpc("admin_operations_config", { p_data: body }));
      return json({ ok: true });
    }
  }
  if (path === "/operations/bills")
    return json(await checked(client.rpc("admin_financial_overview")));
  if (path === "/operations/logs")
    return json(await checked(client.rpc("admin_operations_logs")));
  if (path === "/provider/weekly-summary")
    return json(await checked(client.rpc("weekly_summary")));
  if (path === "/provider/history")
    return json(await checked(client.rpc("provider_job_history")));
  if (path === "/commissions" && method === "GET")
    return json(await checked(client.rpc("commission_dashboard")));
  if (path === "/commissions/rule" && method === "POST") {
    await checked(client.rpc("admin_commission_rule", { p_data: body }));
    return json({ ok: true });
  }
  if (path === "/commissions/payments" && method === "POST")
    return json({
      id: await checked(
        client.rpc("submit_commission_payment", { p_data: body }),
      ),
    });
  const payment = path.match(/^\/commissions\/payments\/([^/]+)\/review$/);
  if (payment && method === "POST") {
    await checked(
      client.rpc("admin_review_commission", {
        p_payment: payment[1],
        p_approve: body.approve === true,
        p_reason: text(body.reason),
      }),
    );
    return json({ ok: true });
  }
  if (path === "/invoices" && method === "GET")
    return json(await checked(client.rpc("invoice_history")));
  const invoice = path.match(/^\/invoices\/([^/]+)(\/pdf)?$/);
  if (invoice && method === "GET") {
    const record = await checked(
      client.rpc("invoice_record", { p_invoice: invoice[1] }),
    );
    if (!invoice[2]) return json(record);
    const bytes = await invoicePDF(record);
    return new NextResponse(bytes, {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition":
          (req.nextUrl.searchParams.get("view") === "1"
            ? "inline"
            : "attachment") +
          '; filename="' +
          record.number.replace(/[^a-zA-Z0-9-]/g, "") +
          '.pdf"',
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
      },
    });
  }
  const bill = path.match(/^\/bills\/([^/]+)\/(respond|resolve)$/);
  if (bill && method === "POST") {
    if (bill[2] === "respond")
      return json(
        await checked(
          client.rpc("respond_final_bill", {
            p_bill: bill[1],
            p_action: body.action,
            p_reason: body.reason || "",
          }),
        ),
      );
    await checked(
      client.rpc("admin_resolve_bill", {
        p_bill: bill[1],
        p_action: body.action,
        p_reason: text(body.reason),
      }),
    );
    return json({ ok: true });
  }
  const charge = path.match(/^\/charges\/([^/]+)\/respond$/);
  if (charge && method === "POST") {
    await checked(
      client.rpc("respond_additional_charge", {
        p_charge: charge[1],
        p_action: body.action,
      }),
    );
    return json({ ok: true });
  }
  const booking = path.match(
    /^\/bookings\/([^/]+)\/(finances|charges|bill|start-otp|verify-otp|otp-exception|retry|cash|refund|attachment)$/,
  );
  if (booking) {
    const id = booking[1],
      action = booking[2];
    if (action === "finances" && method === "GET")
      return json(
        await checked(client.rpc("booking_finances", { p_booking: id })),
      );
    if (action === "charges" && method === "POST")
      return json({
        id: await checked(
          client.rpc("request_additional_charge", {
            p_booking: id,
            p_amount: body.amount_paise,
            p_description: text(body.description, 1000),
          }),
        ),
      });
    if (action === "bill" && method === "POST")
      return json({
        id: await checked(
          client.rpc("submit_final_bill", { p_booking: id, p_data: body }),
        ),
      });
    if (action === "retry" && method === "POST") {
      await checked(client.rpc("retry_booking", { p_booking: id }));
      return json({ ok: true });
    }
    if (action === "refund" && method === "POST") {
      await checked(
        client.rpc("admin_verify_refund", {
          p_booking: id,
          p_amount: body.amount_paise,
          p_reference: text(body.reference),
          p_reason: text(body.reason),
        }),
      );
      return json({ ok: true });
    }
    if (action === "cash" && method === "POST") {
      await checked(
        client.rpc("admin_verify_cash", {
          p_booking: id,
          p_amount: body.amount_paise,
          p_reference: text(body.reference),
        }),
      );
      return json({ ok: true });
    }
    if (action === "attachment" && method === "POST")
      return json({
        id: await checked(
          client.rpc("send_attachment", {
            p_booking: id,
            p_asset: body.asset_id,
            p_body: body.body || "Image attachment",
          }),
        ),
      });
    if (action === "otp-exception" && method === "POST") {
      await checked(
        client.rpc("admin_start_exception", {
          p_booking: id,
          p_reason: text(body.reason),
        }),
      );
      return json({ ok: true });
    }
    if (action === "start-otp") {
      // Check participant access before constructing the privileged client.
      await checked(client.rpc("safe_booking", { p_booking: id }));
      const service = await createServiceAdmin();
      if (method === "POST") {
        const otp = makeOTP(id, otpSecret());
        const result = await checked(
          service.rpc("service_issue_job_otp", {
            p_actor: user.id,
            p_booking: id,
            p_hash: otp.hash,
            p_cipher: otp.cipher,
          }),
        );
        return json({ ok: true, expires_at: result.expires_at });
      }
      if (method === "GET") {
        const record = await checked(
          service.rpc("service_customer_job_otp", {
            p_actor: user.id,
            p_booking: id,
          }),
        );
        return json(
          record
            ? {
                code: record.locked
                  ? null
                  : decryptOTP(record.ciphertext, otpSecret()),
                expires_at: record.expires_at,
                locked: record.locked,
              }
            : null,
        );
      }
    }
    if (action === "verify-otp" && method === "POST") {
      if (typeof body.code !== "string" || !/^\d{6}$/.test(body.code))
        throw new ApiError("Enter the six-digit customer OTP.");
      await checked(client.rpc("safe_booking", { p_booking: id }));
      const service = await createServiceAdmin();
      const result = await checked(
        service.rpc("service_verify_job_otp", {
          p_actor: user.id,
          p_booking: id,
          p_hash: otpHash(body.code, id, otpSecret()),
        }),
      );
      return json(result, result.ok ? 200 : 400);
    }
  }
  if (path === "/voice/incoming")
    return json(await checked(client.rpc("voice_incoming")));
  if (path === "/voice/history")
    return json(
      await checked(
        client.rpc("voice_call_history", {
          p_booking: req.nextUrl.searchParams.get("booking") || null,
        }),
      ),
    );
  if (path === "/voice/start" && method === "POST") {
    const cfg = await checked(client.rpc("operations_config"));
    let ice;
    try {
      ice = iceConfiguration(process.env, user.id, cfg);
    } catch (e: any) {
      throw new ApiError(e.message, 503);
    }
    return json({
      call: await checked(
        client.rpc("start_voice_call", { p_booking: body.booking_id }),
      ),
      ice,
    });
  }
  const voice = path.match(
    /^\/voice\/([^/]+)(?:\/(config|action|signals|signal|heartbeat))?$/,
  );
  if (voice) {
    const id = voice[1],
      action = voice[2];
    if (!action && method === "GET")
      return json(
        await checked(client.rpc("voice_call_state", { p_call: id })),
      );
    if (action === "signals" && method === "GET")
      return json(
        await checked(
          client.rpc("receive_voice_signals", {
            p_call: id,
            p_after: Number(req.nextUrl.searchParams.get("after") || 0),
          }),
        ),
      );
    if (action === "signal" && method === "POST")
      return json({
        id: await checked(
          client.rpc("send_voice_signal", {
            p_call: id,
            p_kind: body.kind,
            p_payload: body.payload,
          }),
        ),
      });
    if (action === "heartbeat" && method === "POST")
      return json(
        await checked(
          client.rpc("voice_call_action", {
            p_call: id,
            p_action: "heartbeat",
          }),
        ),
      );
    if (action === "config" && method === "GET") {
      const call = await checked(
        client.rpc("voice_call_state", { p_call: id }),
      );
      if (!["ringing", "accepted", "active"].includes(call.status))
        throw new ApiError("This call ended.", 409);
      try {
        return json(
          iceConfiguration(
            process.env,
            user.id,
            await checked(client.rpc("operations_config")),
          ),
        );
      } catch (e: any) {
        throw new ApiError(e.message, 503);
      }
    }
    if (action === "action" && method === "POST") {
      let ice;
      if (body.action === "accept")
        try {
          ice = iceConfiguration(
            process.env,
            user.id,
            await checked(client.rpc("operations_config")),
          );
        } catch (e: any) {
          throw new ApiError(e.message, 503);
        }
      return json({
        call: await checked(
          client.rpc("voice_call_action", {
            p_call: id,
            p_action: body.action,
            p_reason: body.reason || "",
          }),
        ),
        ...(ice ? { ice } : {}),
      });
    }
  }
  if (path === "/media" && method === "GET")
    return json(
      await checked(
        client.rpc("media_list", {
          p_booking: req.nextUrl.searchParams.get("booking") || null,
        }),
      ),
    );
  const media = path.match(/^\/media\/([^/]+)(\/review)?$/);
  if (media) {
    if (media[2] && method === "POST") {
      await checked(
        client.rpc("admin_review_media", {
          p_asset: media[1],
          p_approve: body.approve === true,
          p_note: text(body.note),
        }),
      );
      return json({ ok: true });
    }
    if (method === "GET") {
      const asset = await checked(
        client.rpc("read_media", { p_asset: media[1] }),
      );
      const service = await createServiceAdmin();
      const { data, error } = await service.storage
        .from("local-mate-private")
        .download(asset.object_path);
      if (error || !data)
        throw new ApiError("This private image is unavailable.", 404);
      return new NextResponse(await data.arrayBuffer(), {
        headers: {
          "Content-Type": "image/jpeg",
          "Cache-Control": "private, no-store",
          "X-Content-Type-Options": "nosniff",
          "Content-Disposition": 'inline; filename="local-mate-image.jpg"',
        },
      });
    }
  }
  if (path === "/uploads" && method === "POST") {
    let length = 0;
    const chunks: Uint8Array[] = [];
    const reader = req.body?.getReader();
    if (!reader) throw new ApiError("Choose an image.");
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 4 * 1024 * 1024) {
        await reader.cancel();
        throw new ApiError("Choose an image smaller than 3 MB.", 413);
      }
      chunks.push(value);
    }
    const form = await new Response(Buffer.concat(chunks), {
      headers: { "Content-Type": req.headers.get("content-type") || "" },
    }).formData();
    const file = form.get("file");
    if (!(file instanceof File) || file.size > 3 * 1024 * 1024)
      throw new ApiError("Choose an image smaller than 3 MB.");
    const kind = String(form.get("kind") || ""),
      bookingId = String(form.get("booking_id") || "");
    if (bookingId)
      await checked(client.rpc("safe_booking", { p_booking: bookingId }));
    else if (!["commission", "logo"].includes(kind))
      throw new ApiError("Choose a booking for this image.");
    await checked(
      client.rpc("authorize_upload", {
        p_kind: kind,
        p_booking: bookingId || null,
      }),
    );
    let bytes: Buffer;
    try {
      bytes = await sharp(Buffer.from(await file.arrayBuffer()), {
        limitInputPixels: 20000000,
      })
        .rotate()
        .resize({
          width: 2000,
          height: 2000,
          fit: "inside",
          withoutEnlargement: true,
        })
        .jpeg({ quality: 82 })
        .toBuffer();
    } catch {
      throw new ApiError("Upload a valid JPEG, PNG or WebP image.");
    }
    const objectPath = user.id + "/" + randomUUID() + ".jpg";
    const service = await createServiceAdmin();
    const upload = await service.storage
      .from("local-mate-private")
      .upload(objectPath, bytes, { contentType: "image/jpeg", upsert: false });
    if (upload.error)
      throw new ApiError(
        "Private storage needs setup. Run the latest SQL and check the Supabase Storage bucket.",
        503,
      );
    try {
      const id = await checked(
        service.rpc("service_register_media", {
          p_actor: user.id,
          p_data: {
            kind,
            booking_id: bookingId || null,
            object_path: objectPath,
            byte_size: bytes.length,
          },
        }),
      );
      return json({ id, review_status: "pending" });
    } catch (e) {
      await service.storage.from("local-mate-private").remove([objectPath]);
      throw e;
    }
  }
  return null;
}
export async function maintenanceAPI(req: NextRequest) {
  const expected = process.env.CRON_SECRET || "",
    actual = req.headers.get("authorization")?.replace(/^Bearer /, "") || "";
  if (
    !expected ||
    expected.length !== actual.length ||
    !timingSafeEqual(Buffer.from(expected), Buffer.from(actual))
  )
    throw new ApiError("Not permitted.", 401);
  const service = await createServiceAdmin();
  return json(await checked(service.rpc("service_maintenance")));
}
