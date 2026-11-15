import { test } from "node:test";
import assert from "node:assert/strict";
import { adminRows } from "../lib/admin-data.mjs";

test("administrator provider rows preserve identity, status and legacy area formats", () => {
  const source = {
    user_id: "provider-1",
    name: "Example Provider",
    business_name: "Example Business",
    status: "approved",
    description: "Example",
    phone: "+919876543210",
    experience: 4,
    service_ids: '["plumbing"]',
    locations: '["Pattambi"]',
    offerings: [{ service_id: "plumbing", price: 750, pricing_unit: "visit" }],
  };
  for (const locations of [
    '["Pattambi"]',
    ["Pattambi"],
    JSON.stringify('["Pattambi"]'),
  ]) {
    const p = adminRows("providers", [{ ...source, locations }])[0];
    assert.equal(p.user_id, source.user_id);
    assert.equal(p.status, "approved");
    assert.equal(p.phone, source.phone);
    assert.equal(p.experience, 4);
    assert.deepEqual(p.locations, ["Pattambi"]);
    assert.equal(p.offerings[0].price, 750);
  }
  assert.equal(
    adminRows("providers", [{ ...source, experience: "4" }])[0].experience,
    4,
  );
  assert.deepEqual(adminRows("providers", []), []);
});
test("incomplete provider metadata cannot become an invalid React child", () => {
  const p = adminRows("providers", [
    {
      user_id: "provider-1",
      name: { text: "Invalid" },
      business_name: {},
      phone: [],
      description: {},
      status: {},
      experience: {},
      locations: "null",
      service_ids: null,
      offerings: "null",
    },
  ])[0];
  assert.equal(p.user_id, "provider-1");
  assert.equal(p.business_name, "");
  assert.equal(p.description, "");
  assert.equal(p.status, "unknown");
  assert.equal(p.experience, null);
  assert.deepEqual(p.locations, []);
  assert.deepEqual(p.offerings, []);
});
test("unexpected directory shapes and records from other admin tabs are rejected before rendering", () => {
  for (const value of [
    null,
    {},
    "not an array",
    [null],
    [[1]],
    [{ id: "customer-1", name: "Customer row" }],
    [{ user_id: "" }],
  ])
    assert.throws(
      () => adminRows("providers", value),
      /provider list could not be read/,
    );
  const services = [{ id: "plumbing", name: "Plumbing" }];
  assert.equal(adminRows("services", services), services);
});
