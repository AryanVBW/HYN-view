# Automatic deployment to Heroku

The workflow [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)
deploys the portal from **`V1vekW/HYN-view-web`** to Heroku. Every push to `main`
starts validation, then deploys that push's commit when the checks pass. Pull
requests run validation. Local commits trigger the workflow after being pushed
to GitHub; changes to the separate `AryanVBW/HYN-view` CLI repository do not
deploy this portal.

## Configure GitHub

In the **HYN-view-web** repository:

1. Open **Settings → Environments → production**. Create `production` if needed.
2. Under **Environment secrets**, add **`HEROKU_API_KEY`**. Use a Heroku API token
   belonging to an account with deployment access to the target app. An unrelated
   account's valid token will still produce “You do not have access to the app.”
3. Optionally open **Settings → Secrets and variables → Actions → Variables**
   and add these repository variables if you want to change the deployment target:

   | Variable | Default when omitted |
   | --- | --- |
   | `HEROKU_APP_NAME` | `hyn-view` |
   | `HEROKU_APP_URL` | `https://hyn-view-40fdf9204819.herokuapp.com` |

   Copy the app URL from Heroku, including `https://`. The workflow uses it for
   the deployment link and production smoke test. Set both variables together
   when changing apps.

The API key must be a **secret**, not a variable. `HEROKU_EMAIL` is not required.
The workflow never needs Supabase or Resend keys in GitHub; it reads the app's
existing configuration through the Heroku CLI without printing its values.

To obtain a token, sign into the correct Heroku account and use **Account
settings → API Key → Reveal**, or create an automation authorization with
`heroku authorizations:create --description "HYN-view GitHub deployment"`.
Transfer the token directly into GitHub's secret field. Keep it out of source
files, issue comments, and chat. When rotating a token, update the secret before
revoking the old authorization. See [Heroku authentication](https://devcenter.heroku.com/articles/authentication).

Existing GitHub environment protection rules still apply. If `production`
requires a reviewer, a run waits for that approval before deployment; configure
those rules according to your intended release process.

## Configure Heroku

Open the target app's **Settings → Config Vars** and provide:

| Config var | Purpose |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | The production Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | The same project's public anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-side agent and managed email operations |
| `RESEND_API_KEY` | Managed email delivery |
| `EMAIL_FROM` | A sender address verified with the email provider |
| `CRON_SECRET` | Authentication for scheduled email requests |

Supabase public configuration must be available during the Heroku build as well
as at runtime. The repository already contains the Procfile, Node 24 requirement,
pinned pnpm version, and `heroku-postbuild` command. Keep a web dyno running in
the app's **Resources** tab.

Before the first deployment, apply pending migrations from the separate CLI
repository's `supabase/migrations/` directory to that same Supabase project in
timestamp order. The [portal roles guide](portal-roles.md) and
[server access guide](server-access-bandwidth.md) describe the dependencies.
For an existing database, use pending migrations rather than replacing it with
the full fresh-install schema.

## What happens on each push

1. GitHub installs the pinned dependencies, runs tests, TypeScript, lint, and a
   production build.
2. The deploy job checks for the Heroku secret and verifies that the required
   database functions exist and reject anonymous access.
3. It pushes the exact validated commit to Heroku using authenticated HTTPS Git.
   Heroku builds and releases the app.
4. The smoke test expects HTTP 200 from the homepage and HTTP 401 from the
   protected relayer API.

An active release is allowed to finish. If several pushes arrive while it runs,
GitHub can replace an older pending run with a newer one. The workflow therefore
targets the latest queued commit, rather than promising a release for every
intermediate commit in a burst.

Failed validation, missing migrations, or a failed Heroku build stop deployment.
A failed smoke test happens after release and requires investigation; the
workflow does not automatically roll back or apply database migrations.

## Start or retry a deployment

Push a commit to `main`, or open **Actions → Deploy portal to Heroku → Run
workflow**, choose **main**, and click **Run workflow**. After fixing a failed
run's configuration, you can also use **Re-run failed jobs**.

| Failed step or message | What to fix |
| --- | --- |
| `Check deployment configuration` | Add or replace the `production` environment's `HEROKU_API_KEY` secret. |
| `You do not have access to the app` | Use a token for the app owner or an authorized collaborator; check `HEROKU_APP_NAME`. |
| `Check production database migrations`, `PGRST202` | Apply the missing database migrations before retrying. This is also the cause of “Dashboard access unavailable” when the roles functions are absent. |
| Validation or Heroku build | Fix the reported test or build error and push another commit. |
| Smoke test | Check the configured app URL, running web dyno, and Heroku runtime logs. |

Useful commands when signed into the app's Heroku account:

```bash
heroku releases -a hyn-view
heroku logs -a hyn-view --tail
```

For an emergency rollback, use `heroku releases:rollback vNUMBER -a hyn-view`
with the intended prior release. The next successful push replaces that rollback.

References: [GitHub variables](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-variables),
[Heroku Git deployment](https://devcenter.heroku.com/articles/git).
