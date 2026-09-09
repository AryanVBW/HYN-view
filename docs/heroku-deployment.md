# Production deployment

The portal is maintained in `V1vekW/HYN-view-web`, separately from the HYN-view CLI repository. Every push to the portal's `main` branch automatically runs tests and lint, then deploys that commit to the existing Heroku app `hyn-view`. Pull requests run validation without deploying. Local commits must be pushed to GitHub to trigger deployment.

The workflow `.github/workflows/deploy.yml` uses the official Heroku CLI and authenticated HTTPS Git. Heroku installs the frozen pnpm dependencies and runs `heroku-postbuild`; failed builds do not replace the current release. Releases are serialized, and the workflow checks the homepage and unauthenticated API boundary afterward. A failed smoke check requires investigation; it does not automatically roll back.

GitHub's `production` environment stores `HEROKU_API_KEY`, a dedicated Heroku OAuth authorization. Rotate it by creating a replacement authorization with `heroku authorizations:create`, updating the environment secret, and revoking the previous authorization. Never commit or print tokens. Application configuration remains in Heroku config vars, including Supabase server credentials and public build-time configuration.

Production: https://hyn-view-40fdf9204819.herokuapp.com/

Inspect releases with `heroku releases -a hyn-view`; inspect runtime with `heroku logs -a hyn-view --tail`. Re-run a failed GitHub Actions run after resolving its cause, or use the manual workflow trigger on `main`. An emergency rollback is `heroku releases:rollback <release> -a hyn-view`; coordinate subsequent pushes because the next successful deployment replaces the rollback.

Database migrations remain a separate operation and must precede portal changes that require them. This workflow does not deploy the CLI repository or merge feature branches automatically.
