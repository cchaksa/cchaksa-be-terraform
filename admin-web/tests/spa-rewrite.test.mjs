import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../spa-rewrite.js", import.meta.url), "utf8");
const context = vm.createContext({});
vm.runInContext(source, context);

function rewrite(method, uri) {
  return context.handler({ request: { method, uri } }).uri;
}

assert.equal(rewrite("GET", "/"), "/index.html");
assert.equal(rewrite("GET", "/reports/123"), "/index.html");
assert.equal(rewrite("HEAD", "/login/callback"), "/index.html");
assert.equal(rewrite("GET", "/assets/index-abcd.js"), "/assets/index-abcd.js");
assert.equal(rewrite("GET", "/api/admin/reports"), "/api/admin/reports");
assert.equal(rewrite("POST", "/api/admin/auth/signin"), "/api/admin/auth/signin");
assert.equal(rewrite("POST", "/reports/123"), "/reports/123");

console.log("SPA rewrite tests passed.");
