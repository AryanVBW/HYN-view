import assert from "node:assert/strict";
import test from "node:test";
import { selectDashboard } from "./dashboard-selection.ts";
const accounts = [{id:"me",name:"Me",own:true},{id:"shared",name:"Team",own:false}];
const nodes = [{id:"older",owner:"me"},{id:"new",owner:"me"},{id:"team",owner:"shared"}];
const base = {selfId:"me",canViewFleet:false,accounts,nodes};
test("users without owned devices land on their assigned server", () => {
  const selected = selectDashboard({...base,nodes:[nodes[2]]});
  assert.equal(selected?.owner,"shared");
  assert.equal(selected?.node?.id,"team");
  assert.equal(selectDashboard(base)?.owner,"me");
  assert.equal(selectDashboard({...base,nodes:[nodes[2]],requestedOwner:"me"})?.node,undefined);
  assert.equal(selectDashboard({...base,nodes:[]})?.owner,"me");
});
test("newly linked device deep links select that device without an assignment", () => {
  const selected=selectDashboard({...base,requestedNode:"new"});
  assert.equal(selected?.node?.id,"new");
  assert.equal(selected?.owner,"me");
});
test("shared server deep links infer the accessible owner", () => {
  const selected=selectDashboard({...base,requestedNode:"team"});
  assert.equal(selected?.owner,"shared");
  assert.deepEqual(selected?.nodes,[nodes[2]]);
});
test("invalid or mismatched links never silently show a different device", () => {
  assert.equal(selectDashboard({...base,requestedNode:"private"}),null);
  assert.equal(selectDashboard({...base,requestedOwner:"me",requestedNode:"team"}),null);
  assert.equal(selectDashboard({...base,requestedOwner:"private"}),null);
  assert.equal(selectDashboard({...base,requestedOwner:"all"}),null);
});
test("admins see all accessible servers and can switch to an account with no devices", () => {
  assert.deepEqual(selectDashboard({...base,canViewFleet:true})?.nodes,nodes);
  assert.equal(selectDashboard({...base,canViewFleet:true})?.owner,"all");
  assert.equal(selectDashboard({...base,nodes:[],requestedOwner:"me"})?.node,undefined);
});
