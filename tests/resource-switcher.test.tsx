import assert from "node:assert/strict";
import test from "node:test";
import { act } from "react";
import { JSDOM } from "jsdom";

test("pill switcher filters by name or ID, exposes selection and preserves resource links", async () => {
  const dom = new JSDOM('<div id="root"></div>',{url:"https://portal.example/dashboard?owner=all&node=one&relayer=42"});
  Object.assign(globalThis,{window:dom.window,self:dom.window,document:dom.window.document,IS_REACT_ACT_ENVIRONMENT:true});
  const {createRoot}=await import("react-dom/client");
  const {ResourceSwitcher}=await import("../components/dashboard/resource-switcher");
  const root=createRoot(document.getElementById("root")!);
  try {
    await act(async()=>root.render(<ResourceSwitcher label="Servers" current="one" items={[
      {id:"one",name:"Server",detail:"Mine",href:"/dashboard?owner=all&node=one&relayer=42"},
      {id:"two",name:"Server",detail:"Team",searchText:"wan-02",href:"/dashboard?owner=all&node=two&relayer=42"},
    ]}/>));
    assert.equal(document.querySelector('[aria-current="page"]')?.textContent,"ServerMine");
    assert.equal(document.querySelectorAll('nav a').length,2);
    assert.equal(document.querySelectorAll('nav a')[1].getAttribute('href'),'/dashboard?owner=all&node=two&relayer=42');
    const input=document.querySelector('input')!;
    const setter=Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype,'value')!.set!;
    const type=async(value:string)=>act(async()=>{setter.call(input,value);input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});
    await type('wan-02');
    assert.equal(document.querySelectorAll('nav a').length,1);
    assert.match(document.querySelector('nav')!.textContent!,/Team/);
    await type('missing');
    assert.match(document.querySelector('[role="status"]')!.textContent!,/No servers match/);
    await type('');
    assert.equal(document.querySelectorAll('nav a').length,2);
  } finally {await act(async()=>root.unmount());dom.window.close();}
});
