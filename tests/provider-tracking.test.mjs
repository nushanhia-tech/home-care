import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "@electric-sql/pglite";
import { readFile, readdir } from "node:fs/promises";
let db;
const ids = {
  admin: "20000000-0000-4000-8000-000000000001",
  customer: "20000000-0000-4000-8000-000000000002",
  pro: "20000000-0000-4000-8000-000000000003",
  other: "20000000-0000-4000-8000-000000000004",
  second: "20000000-0000-4000-8000-000000000005",
};
before(async () => {
  db = new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;grant usage on schema auth,public to anon,authenticated,service_role;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',email_confirmed_at timestamptz default now());
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;`);
  const root = new URL("../supabase/", import.meta.url);
  for (const file of (await readdir(new URL("migrations/", root)))
    .filter((f) => f.endsWith(".sql"))
    .sort())
    await db.exec(await readFile(new URL("migrations/" + file, root), "utf8"));
  await db.exec(await readFile(new URL("seed.sql", root), "utf8"));
  await db.exec(
    "insert into private.admin_emails(email) values('admin@qa.example')",
  );
  for (const [name, id] of Object.entries(ids))
    await db.query("insert into auth.users(id,email) values($1,$2)", [
      id,
      name + "@qa.example",
    ]);
  await rpc("customer", "update_profile", ["Test customer", "+919876543212"]);
  for (const who of ["pro", "second"])
    await rpc("admin", "save_provider", [profile(who), ids[who]]);
});
after(async () => {
  await db?.close();
});
async function as(who, fn) {
  return db.transaction(async (tx) => {
    await tx.exec("set local role " + (who ? "authenticated" : "anon"));
    await tx.query(
      "select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)",
      [ids[who] || "", who ? "authenticated" : "anon"],
    );
    return fn(tx);
  });
}
async function rpc(who, name, values = []) {
  return as(who, async (tx) =>
    (
      await tx.query(
        `select public.${name}(${values.map((_, i) => "$" + (i + 1)).join(",")}) result`,
        values,
      )
    ).rows.map((r) => r.result),
  ).then((rows) =>
    [
      "provider_directory",
      "admin_provider_directory",
      "list_bookings",
    ].includes(name)
      ? rows
      : rows[0],
  );
}
function profile(who = "pro") {
  return {
    name: "Test " + who,
    phone: "+919876543210",
    business_name: "Test-only business",
    category: "Home care",
    description: "Test fixture, never sent to production.",
    experience: 4,
    locations: ["Pattambi"],
    offerings: [
      { service_id: "plumbing", price: 725, pricing_unit: "visit" },
      { service_id: "painting", price: 300, pricing_unit: "hour" },
    ],
    status: "approved",
    online: true,
    publish_phone: false,
    assessment_rating: 4.2,
    rating_source: "Test assessment source",
  };
}
function booking(extra = {}) {
  return {
    service_id: "plumbing",
    provider_id: ids.pro,
    location: "Pattambi",
    address: "Test house, test landmark",
    scheduled_at: new Date(Date.now() + 86400000).toISOString(),
    description: "Test-only job.",
    payment_method: "cash",
    idempotency_key: crypto.randomUUID(),
    latitude: 10.805,
    longitude: 76.186,
    ...extra,
  };
}
async function assigned() {
  const id = await rpc("customer", "create_booking", [booking()]);
  await rpc("pro", "booking_action", [id, "accept", {}]);
  return id;
}
async function start(id, who = "pro") {
  const session_id = crypto.randomUUID();
  await rpc(who, "share_booking_location", [
    id,
    { start: true, consent: true, session_id },
  ]);
  return session_id;
}
const position = (session_id) => ({
  consent: true,
  session_id,
  latitude: 10.81,
  longitude: 76.19,
  accuracy: 12,
});
test("public rates use real offerings and ratings distinguish assessment from completed reviews", async () => {
  const p = (await rpc(null, "provider_directory")).find(
    (p) => p.user_id === ids.pro,
  );
  assert.equal(p.phone, undefined);
  assert.equal(p.rating, null);
  assert.equal(p.review_count, 0);
  assert.equal(p.assessment_rating, 4.2);
  assert.equal(p.rating_source, "Test assessment source");
  assert.equal(p.offerings.find((o) => o.service_id === "plumbing").price, 725);
  assert.equal(p.email, undefined);
  assert.equal(p.username, undefined);
  await assert.rejects(
    rpc("customer", "admin_provider_directory"),
    /Administrator/,
  );
  assert.equal((await rpc("admin", "admin_provider_directory")).length, 2);
  await assert.rejects(
    as("pro", (tx) => tx.exec("update public.provider_offerings set price=1")),
    /permission denied/,
  );
});
test("phone numbers never publish, even after acceptance or an old consent flag", async () => {
  const id = await rpc("customer", "create_booking", [booking()]);
  await assert.rejects(rpc("pro", "booking_contacts", [id]), /private/);
  await rpc("pro", "booking_action", [id, "accept", {}]);
  assert.equal(
    (await rpc("customer", "booking_contacts", [id])).provider.phone,
    undefined,
  );
  await assert.rejects(rpc("second", "booking_contacts", [id]), /private/);
  await rpc("pro", "save_provider", [
    {
      ...profile(),
      publish_phone: true,
      assessment_rating: 1,
      rating_source: "untrusted",
    },
  ]);
  let p = (await rpc(null, "provider_directory")).find(
    (p) => p.user_id === ids.pro,
  );
  assert.equal(p.phone, undefined);
  assert.equal(
    p.assessment_rating,
    4.2,
    "Providers cannot rewrite administrator assessments",
  );
  await rpc("pro", "save_provider", [profile()]);
});
test("provider prices, service membership and area counts are validated and edited by admin", async () => {
  await assert.rejects(
    rpc("other", "save_provider", [profile(), ids.pro]),
    /Administrator/,
  );
  await assert.rejects(
    rpc("admin", "save_provider", [
      { ...profile(), rating_source: "" },
      ids.pro,
    ]),
    /source/,
  );
  await assert.rejects(
    rpc("admin", "save_provider", [
      {
        ...profile(),
        offerings: [
          { service_id: "plumbing", price: -1, pricing_unit: "visit" },
        ],
      },
      ids.pro,
    ]),
    /check constraint/,
  );
  await rpc("admin", "admin_service_provider", [
    ids.pro,
    "cleaning",
    true,
    950,
    "visit",
  ]);
  assert.equal(
    (await rpc(null, "provider_directory"))
      .find((p) => p.user_id === ids.pro)
      .offerings.find((o) => o.service_id === "cleaning").price,
    950,
  );
  await rpc("admin", "admin_provider_area", [ids.pro, "Ottapalam", true]);
  assert.ok(
    (await rpc(null, "provider_directory"))
      .find((p) => p.user_id === ids.pro)
      .locations.includes("Ottapalam"),
  );
  await rpc("admin", "admin_provider_area", [ids.pro, "Ottapalam", false]);
  await rpc("admin", "admin_service_provider", [
    ids.pro,
    "cleaning",
    false,
    null,
    "quote",
  ]);
  await assert.rejects(
    rpc("pro", "admin_service_provider", [
      ids.pro,
      "cleaning",
      true,
      0,
      "visit",
    ]),
    /Administrator/,
  );
});
test("all eligible providers receive requests and the accepting provider rate becomes the estimate",async()=>{
 const id=await rpc('customer','create_booking',[booking()]);
 assert.ok((await rpc('second','list_bookings',['provider'])).some(b=>b.id===id));
 assert.ok((await rpc('pro','list_bookings',['provider'])).some(b=>b.id===id));
 await rpc('pro','booking_action',[id,'accept',{}]);
 assert.equal((await db.query('select estimated_price from public.bookings where id=$1',[id])).rows[0].estimated_price,725);
 assert.equal((await rpc('second','booking_action',[id,'accept',{}])).code,'ALREADY_ASSIGNED');
});
test("hourly/daily and quote offerings require customer approval before confirmation", async () => {
  const id = await rpc("customer", "create_booking", [
    booking({ service_id: "painting" }),
  ]);
  await rpc("pro", "booking_action", [id, "accept", {}]);
  assert.equal((await db.query('select status from public.bookings where id=$1',[id])).rows[0].status,'requested');
  const q = await rpc("pro", "booking_action", [
    id,
    "quote",
    { labour: 900, materials: 100, additional: 0, terms: "Test job total" },
  ]);
  await rpc("customer", "booking_action", [
    id,
    "quote-response",
    { quote_id: q.id, accept: true },
  ]);
  assert.equal(
    (
      await db.query(
        "select status,estimated_price from public.bookings where id=$1",
        [id],
      )
    ).rows[0].estimated_price,
    1000,
  );
});
test("place validation rejects partial or out-of-range coordinates and retains exact destinations", async () => {
  await assert.rejects(
    rpc("customer", "create_booking", [booking({ latitude: 91 })]),
    /check constraint/,
  );
  await assert.rejects(
    rpc("customer", "create_booking", [booking({ longitude: null })]),
    /latitude and longitude/,
  );
  const id = await rpc("customer", "create_booking", [
    booking({
      destination_latitude: 10.9,
      destination_longitude: 76.2,
      details: { destination: "Test destination" },
    }),
  ]);
  assert.equal(
    (
      await db.query(
        "select destination_latitude from public.bookings where id=$1",
        [id],
      )
    ).rows[0].destination_latitude,
    10.9,
  );
  await assert.rejects(
    as("customer", (tx) =>
      tx.query(
        "insert into public.addresses(user_id,label,address,location,latitude) values($1,'Test','Test','Pattambi',10)",
        [ids.customer],
      ),
    ),
    /coordinate_pair/,
  );
});
test("GPS requires assigned provider consent, hides stale points, and cannot be read publicly", async () => {
  const id = await assigned();
  await assert.rejects(
    rpc("customer", "share_booking_location", [
      id,
      position(crypto.randomUUID()),
    ]),
    /assigned provider/,
  );
  await assert.rejects(
    rpc("pro", "share_booking_location", [
      id,
      { ...position(crypto.randomUUID()), consent: false },
    ]),
    /share your location/,
  );
  const token = await start(id);
  await rpc("pro", "share_booking_location", [id, position(token)]);
  assert.equal((await rpc("customer", "booking_tracking", [id])).accuracy, 12);
  assert.ok(await rpc("admin", "booking_tracking", [id]));
  await assert.rejects(rpc("other", "booking_tracking", [id]), /private/);
  await assert.rejects(
    rpc(null, "booking_tracking", [id]),
    /permission denied/,
  );
  await assert.rejects(
    as("customer", (tx) => tx.exec("select * from public.booking_locations")),
    /permission denied/,
  );
  await db.query(
    "update public.booking_locations set recorded_at=now()-interval '3 minutes' where booking_id=$1",
    [id],
  );
  assert.equal(await rpc("customer", "booking_tracking", [id]), null);
});
test("Stop GPS invalidates the session so delayed updates cannot restart sharing", async () => {
  const id = await assigned(),
    token = await start(id);
  await rpc("pro", "share_booking_location", [id, position(token)]);
  await rpc("pro", "share_booking_location", [
    id,
    { stop: true, session_id: token },
  ]);
  assert.equal(await rpc("customer", "booking_tracking", [id]), null);
  await assert.rejects(
    rpc("pro", "share_booking_location", [id, position(token)]),
    /stopped/,
  );
  const newToken = await start(id);
  await rpc("pro", "share_booking_location", [id, position(newToken)]);
  await rpc("pro", "share_booking_location", [
    id,
    { stop: true, session_id: token },
  ]);
  assert.ok(
    await rpc("customer", "booking_tracking", [id]),
    "An old tab must not stop a new sharing session",
  );
  await rpc("pro", "booking_action", [id, "status", { status: "cancelled" }]);
  assert.equal(
    (
      await db.query(
        "select count(*) n from public.booking_locations where booking_id=$1",
        [id],
      )
    ).rows[0].n,
    0,
  );
  assert.equal(
    (
      await db.query(
        "select count(*) n from private.booking_gps_sessions where booking_id=$1",
        [id],
      )
    ).rows[0].n,
    0,
  );
  await assert.rejects(
    rpc("pro", "share_booking_location", [id, position(newToken)]),
    /active assigned job/,
  );
});
test("application backup includes rates while excluding live GPS and session tokens", async () => {
  const backup = await rpc("admin", "export_marketplace");
  assert.ok(backup.tables.provider_offerings.length);
  assert.equal(backup.tables.booking_locations, undefined);
  assert.equal(backup.tables.booking_gps_sessions, undefined);
});

test("providers can request other providers but cannot accept or be assigned themselves",async()=>{
 const id=await rpc('pro','create_booking',[booking()]);
 await assert.rejects(rpc('pro','booking_action',[id,'accept',{}]),/access|own booking/);
 await assert.rejects(rpc('admin','admin_reassign_booking',[id,ids.pro,'Test assignment exception']),/eligible/);
});
test("suspension and website pauses revoke GPS sessions and erase the current point", async () => {
  const id = await assigned(),
    token = await start(id);
  await rpc("pro", "share_booking_location", [id, position(token)]);
  await rpc("admin", "admin_account_status", [ids.pro, false]);
  assert.equal(
    (
      await db.query(
        "select count(*) n from public.booking_locations where booking_id=$1",
        [id],
      )
    ).rows[0].n,
    0,
  );
  await rpc("admin", "admin_account_status", [ids.pro, true]);
  await assert.rejects(
    rpc("pro", "share_booking_location", [id, position(token)]),
    /stopped/,
  );
  const next = await start(id);
  await rpc("pro", "share_booking_location", [id, position(next)]);
  const config = (await db.query("select * from public.website_configuration"))
    .rows[0];
  await rpc("admin", "admin_save_website", [
    { ...config, maintenance_mode: true },
  ]);
  assert.equal(
    (
      await db.query(
        "select count(*) n from private.booking_gps_sessions where booking_id=$1",
        [id],
      )
    ).rows[0].n,
    0,
  );
  assert.equal(await rpc("customer", "booking_tracking", [id]), null);
  await rpc("admin", "admin_save_website", [config]);
});
