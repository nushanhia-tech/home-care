import { test } from "node:test";
import assert from "node:assert/strict";
import {
  readArray,
  readRecord,
  readStringArray,
  providerOffers,
  providerSchedule,
} from "../lib/provider-data.mjs";

test("provider settings accept native JSONB and legacy JSON text without changing valid values", () => {
  const schedule = {
    days: "Friday",
    hours: "10:00–14:00",
    max_daily: 7,
    leave: "2026-12-25",
  };
  for (const value of [
    schedule,
    JSON.stringify(schedule),
    JSON.stringify(JSON.stringify(schedule)),
  ]) {
    assert.deepEqual(providerSchedule(value), schedule);
  }
  for (const value of [["plumbing"], '["plumbing"]', '"[\\"plumbing\\"]"'])
    assert.deepEqual(readStringArray(value), ["plumbing"]);
  const offers = [
    { service_id: "plumbing", price: 750, pricing_unit: "visit" },
  ];
  assert.deepEqual(providerOffers(offers), offers);
  assert.deepEqual(providerOffers(JSON.stringify(offers)), offers);
});

test("null, malformed and unexpected provider JSON shapes cannot crash settings forms", () => {
  const defaults = providerSchedule(undefined);
  for (const value of [
    undefined,
    null,
    "null",
    '"null"',
    "{broken",
    "",
    true,
    42,
    "[]",
    [],
    "true",
  ])
    assert.deepEqual(providerSchedule(value), defaults);
  for (const value of [
    undefined,
    null,
    "null",
    "{}",
    {},
    "false",
    "not-json",
    3,
  ])
    assert.deepEqual(readArray(value), []);
  for (const value of [undefined, null, "null", "[]", [], false, "invalid"])
    assert.deepEqual(readRecord(value), {});
  assert.deepEqual(readStringArray('[null,"Pattambi",{},42,""]'), ["Pattambi"]);
  assert.deepEqual(
    providerOffers('[null,false,{},[],{"service_id":"plumbing","price":750}]'),
    [{ service_id: "plumbing", price: 750 }],
  );
  assert.deepEqual(providerOffers("null"), []);
});

test("availability fields have scalar defaults and bounded capacity while preserving valid empty text", () => {
  for (const max_daily of [null, undefined, {}, [], 0, 31, 2.5, "NaN", ""])
    assert.equal(providerSchedule({ max_daily }).max_daily, 5);
  assert.equal(providerSchedule({ max_daily: "8" }).max_daily, 8);
  assert.equal(providerSchedule({ max_daily: 30 }).max_daily, 30);
  assert.deepEqual(
    providerSchedule({ days: "", hours: "", leave: "", max_daily: 1 }),
    { days: "", hours: "", leave: "", max_daily: 1 },
  );
  assert.deepEqual(
    providerSchedule({
      days: { text: "Friday" },
      hours: [],
      leave: false,
      max_daily: 5,
    }),
    providerSchedule(undefined),
  );
});
