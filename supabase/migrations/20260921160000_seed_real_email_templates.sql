-- ===========================================================================
-- seed the templates with the format that is actually in use
-- ===========================================================================
-- Every row shipped holding the single string "{{content}}". That is a correct
-- passthrough wrapper and a useless starting point: an administrator opening the
-- Email templates tab saw an editor containing one placeholder, with no way to
-- tell what editing it would change. "Listed but not visible", accurately.
--
-- These rows now hold the real current wrapper, generated from
-- web-portal/lib/email-template-defaults.ts so the database seed and the
-- "Restore default" button in the panel cannot drift apart.
--
-- Only rows still at the untouched default are replaced. A wrapper an
-- administrator has already edited is left exactly as it is -- this migration
-- must not silently overwrite somebody's work.

update public.notification_templates
   set html_template = '<!-- HYN-view email wrapper. {{content}} is replaced by the generated message
     body; everything around it is yours. Placeholders: {{subject}} {{hostname}}
     {{severity}} {{version}}. Inline styles only - no <style> block, no scripts. -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse">
  <tr>
    <td style="padding:0 0 18px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;background:#f7f8fa;border:1px solid #e2e6ea;border-radius:6px">
        <tr>
          <td style="padding:12px 16px;font:600 11px -apple-system,Segoe UI,Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;color:#0f6dd6">{{severity}}</td>
          <td align="right" style="padding:12px 16px;font:12px -apple-system,Segoe UI,Arial,sans-serif;color:#6b7684">{{hostname}}</td>
        </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td>{{content}}</td>
  </tr>
  <tr>
    <td style="padding:22px 0 0;border-top:1px solid #e2e6ea;font:12px -apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;color:#6b7684">
      Sent from the HYN-view portal when an administrator or maintainer requested it.<br>HYN-view &middot; agent {{version}}
    </td>
  </tr>
</table>',
       updated_at = now()
 where template_key = 'alert'
   and btrim(html_template) in ('{{content}}', '');

update public.notification_templates
   set html_template = '<!-- HYN-view email wrapper. {{content}} is replaced by the generated message
     body; everything around it is yours. Placeholders: {{subject}} {{hostname}}
     {{severity}} {{version}}. Inline styles only - no <style> block, no scripts. -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse">
  <tr>
    <td style="padding:0 0 18px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;background:#f7f8fa;border:1px solid #e2e6ea;border-radius:6px">
        <tr>
          <td style="padding:12px 16px;font:600 11px -apple-system,Segoe UI,Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;color:#0f6dd6">{{severity}}</td>
          <td align="right" style="padding:12px 16px;font:12px -apple-system,Segoe UI,Arial,sans-serif;color:#6b7684">{{hostname}}</td>
        </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td>{{content}}</td>
  </tr>
  <tr>
    <td style="padding:22px 0 0;border-top:1px solid #e2e6ea;font:12px -apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;color:#6b7684">
      Sent from the HYN-view portal when an administrator or maintainer requested it.<br>HYN-view &middot; agent {{version}}
    </td>
  </tr>
</table>',
       updated_at = now()
 where template_key = 'report'
   and btrim(html_template) in ('{{content}}', '');

update public.notification_templates
   set html_template = '<!-- HYN-view email wrapper. {{content}} is replaced by the generated message
     body; everything around it is yours. Placeholders: {{subject}} {{hostname}}
     {{severity}} {{version}}. Inline styles only - no <style> block, no scripts. -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse">
  <tr>
    <td style="padding:0 0 18px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;background:#f7f8fa;border:1px solid #e2e6ea;border-radius:6px">
        <tr>
          <td style="padding:12px 16px;font:600 11px -apple-system,Segoe UI,Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;color:#0f6dd6">{{severity}}</td>
          <td align="right" style="padding:12px 16px;font:12px -apple-system,Segoe UI,Arial,sans-serif;color:#6b7684">{{hostname}}</td>
        </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td>{{content}}</td>
  </tr>
  <tr>
    <td style="padding:22px 0 0;border-top:1px solid #e2e6ea;font:12px -apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;color:#6b7684">
      Sent from the HYN-view portal when an administrator or maintainer requested it.<br>HYN-view &middot; agent {{version}}
    </td>
  </tr>
</table>',
       updated_at = now()
 where template_key = 'system'
   and btrim(html_template) in ('{{content}}', '');

update public.notification_templates
   set html_template = '<!-- HYN-view email wrapper. {{content}} is replaced by the generated message
     body; everything around it is yours. Placeholders: {{subject}} {{hostname}}
     {{severity}} {{version}}. Inline styles only - no <style> block, no scripts. -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse">
  <tr>
    <td style="padding:0 0 18px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;background:#f7f8fa;border:1px solid #e2e6ea;border-radius:6px">
        <tr>
          <td style="padding:12px 16px;font:600 11px -apple-system,Segoe UI,Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;color:#0f6dd6">{{severity}}</td>
          <td align="right" style="padding:12px 16px;font:12px -apple-system,Segoe UI,Arial,sans-serif;color:#6b7684">{{hostname}}</td>
        </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td>{{content}}</td>
  </tr>
  <tr>
    <td style="padding:22px 0 0;border-top:1px solid #e2e6ea;font:12px -apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;color:#6b7684">
      Automatic security notice. If this sign-in was not you, secure the account immediately.<br>HYN-view &middot; agent {{version}}
    </td>
  </tr>
</table>',
       updated_at = now()
 where template_key = 'signin'
   and btrim(html_template) in ('{{content}}', '');

update public.notification_templates
   set html_template = '<!-- HYN-view email wrapper. {{content}} is replaced by the generated message
     body; everything around it is yours. Placeholders: {{subject}} {{hostname}}
     {{severity}} {{version}}. Inline styles only - no <style> block, no scripts. -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse">
  <tr>
    <td style="padding:0 0 18px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;background:#f7f8fa;border:1px solid #e2e6ea;border-radius:6px">
        <tr>
          <td style="padding:12px 16px;font:600 11px -apple-system,Segoe UI,Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;color:#0f6dd6">{{severity}}</td>
          <td align="right" style="padding:12px 16px;font:12px -apple-system,Segoe UI,Arial,sans-serif;color:#6b7684">{{hostname}}</td>
        </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td>{{content}}</td>
  </tr>
  <tr>
    <td style="padding:22px 0 0;border-top:1px solid #e2e6ea;font:12px -apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;color:#6b7684">
      Sent once when a machine finishes pairing with your account.<br>HYN-view &middot; agent {{version}}
    </td>
  </tr>
</table>',
       updated_at = now()
 where template_key = 'device'
   and btrim(html_template) in ('{{content}}', '');

update public.notification_templates
   set html_template = '<!-- HYN-view email wrapper. {{content}} is replaced by the generated message
     body; everything around it is yours. Placeholders: {{subject}} {{hostname}}
     {{severity}} {{version}}. Inline styles only - no <style> block, no scripts. -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse">
  <tr>
    <td style="padding:0 0 18px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;background:#f7f8fa;border:1px solid #e2e6ea;border-radius:6px">
        <tr>
          <td style="padding:12px 16px;font:600 11px -apple-system,Segoe UI,Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;color:#0f6dd6">{{severity}}</td>
          <td align="right" style="padding:12px 16px;font:12px -apple-system,Segoe UI,Arial,sans-serif;color:#6b7684">{{hostname}}</td>
        </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td>{{content}}</td>
  </tr>
  <tr>
    <td style="padding:22px 0 0;border-top:1px solid #e2e6ea;font:12px -apple-system,Segoe UI,Arial,sans-serif;line-height:1.6;color:#6b7684">
      Sent once, after a newly linked machine uploads its first complete reading.<br>HYN-view &middot; agent {{version}}
    </td>
  </tr>
</table>',
       updated_at = now()
 where template_key = 'first_report'
   and btrim(html_template) in ('{{content}}', '');
