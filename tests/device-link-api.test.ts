import assert from "node:assert/strict";
import {mock,test} from "node:test";
import {act,createElement} from "react";
import {JSDOM} from "jsdom";
mock.module('../lib/supabase/client.ts',{namedExports:{createClient:()=>({rpc:async(name:string)=>({data:name==='hyn_device_lookup'?{status:'pending',hostname:'New server'}:{status:'approved',node_id:'new-device',node_name:'New server'},error:null})})}});
test('linked server opens directly even while confirmation email is still pending',async()=>{
 const dom=new JSDOM('<div id="root"></div>',{url:'https://portal.example/link'});
 Object.assign(globalThis,{window:dom.window,self:dom.window,document:dom.window.document,IS_REACT_ACT_ENVIRONMENT:true});
 const {createRoot}=await import('react-dom/client');
 const {LinkForm}=await import('../components/link-form.tsx');
 const root=createRoot(document.getElementById('root')!);
 const originalFetch=globalThis.fetch;
 let completeEmail!:(response:Response)=>void;
 globalThis.fetch=async(url)=>{assert.equal(url,'/api/email/device-linked');return new Promise<Response>(resolve=>{completeEmail=resolve;});};
 try {
  await act(async()=>root.render(createElement(LinkForm,{nodeCount:2})));
  const input=document.querySelector('input')!;
  const setter=Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype,'value')!.set!;
  await act(async()=>{setter.call(input,'ABCD1234');input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});
  await act(async()=>{document.querySelector('form')!.dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));});
  const approve=Array.from(document.querySelectorAll('button')).find(button=>button.textContent?.includes('Approve'))!;
  assert.ok(approve);
  await act(async()=>approve.click());
  assert.match(document.body.textContent!,/New server is linked/);
  assert.equal(document.querySelector('a')?.getAttribute('href'),'/dashboard?node=new-device');
  await act(async()=>completeEmail(new Response('',{status:503})));
  assert.match(document.body.textContent!,/confirmation email could not be delivered/);
  assert.equal(document.querySelector('a')?.getAttribute('href'),'/dashboard?node=new-device');
 } finally {globalThis.fetch=originalFetch;await act(async()=>root.unmount());dom.window.close();}
});
