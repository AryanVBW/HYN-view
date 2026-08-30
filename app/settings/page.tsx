import { redirect } from "next/navigation";

// Settings live on /account, next to the machine they belong to: a threshold or a
// push interval means nothing without knowing which server it applies to, so a
// separate page would only be a list of links back here.
//
// /settings exists because it is the URL people type. Permanent, so a bookmark
// resolves once and stops asking.
export default function SettingsPage() {
  redirect("/account");
}
