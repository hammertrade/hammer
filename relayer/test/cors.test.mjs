import test from "node:test";
import assert from "node:assert/strict";
import { corsFor } from "../src/server.mjs";
test("both Hammer domains get one valid CORS origin, with cache variation", () => {
  const allowed = "https://hammertrade.xyz, https://www.hammertrade.xyz";
  for (const origin of allowed.split(", ")) assert.deepEqual(corsFor(allowed, origin), { vary: "Origin", "access-control-allow-origin": origin });
  for (const origin of [undefined, "null", "https://hammertrade.xyz.evil.test", "http://hammertrade.xyz", "https://evil.test"]) assert.deepEqual(corsFor(allowed, origin), { vary: "Origin" });
});
test("single-origin and public CORS configurations remain supported", () => {
  assert.equal(corsFor("https://hammertrade.xyz", "https://hammertrade.xyz")["access-control-allow-origin"], "https://hammertrade.xyz");
  assert.deepEqual(corsFor("*", "https://any.test"), { "access-control-allow-origin": "*" });
});
