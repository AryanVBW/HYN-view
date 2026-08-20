"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type SaveTemplateResult = { ok: true } | { ok: false; error: string };

export async function saveNotificationTemplate(
  templateKey: string,
  htmlTemplate: string
): Promise<SaveTemplateResult> {
  if (!['alert', 'report'].includes(templateKey)) {
    return { ok: false, error: "Unknown notification template." };
  }
  if (!htmlTemplate.includes("{{content}}")) {
    return { ok: false, error: "The template must include {{content}}." };
  }
  if (new TextEncoder().encode(htmlTemplate).length > 100_000) {
    return { ok: false, error: "The template must be smaller than 100 KB." };
  }
  if (/<\s*(script|iframe|object|embed|form)\b/i.test(htmlTemplate)) {
    return { ok: false, error: "Scripts, frames, objects, embeds, and forms are not allowed in email templates." };
  }
  if (/\son[a-z]+\s*=/i.test(htmlTemplate)) {
    return { ok: false, error: "Inline event handlers are not allowed in email templates." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("hyn_admin_save_template", {
    p_template_key: templateKey,
    p_html_template: htmlTemplate,
  });
  if (error) return { ok: false, error: error.message };

  revalidatePath("/admin");
  return { ok: true };
}
