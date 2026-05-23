# Deploying to Cloudflare Pages

This is the exact configuration the documentation site uses on
Cloudflare Pages. It is reproduced here so a future deployer can
rebuild the project from scratch without guessing at settings.

## Project settings

In the Cloudflare dashboard under Pages > Create a project > Connect
to Git, point at the `vyrox-security/vyrox-docs` repository and set
the following build configuration.

| Field | Value |
|---|---|
| Production branch | `main` |
| Build command | `bash scripts/build.sh` |
| Build output directory | `book` |
| Root directory | `/` |
| Environment variable | `MDBOOK_VERSION=v0.4.40` |

The build command downloads a pinned mdBook release into
`.mdbook-bin/` if the binary is not already on PATH, syncs the
top-level Markdown into `src/`, and runs `mdbook build`. Output goes
to `book/`, which is what Cloudflare Pages publishes.

You can change the pinned mdBook version by updating
`MDBOOK_VERSION` either in the Cloudflare environment variables or
inline in `scripts/build.sh`. We keep one source of truth so a
release bump is one edit.

## Custom domain

Cloudflare Pages serves the project at `<project>.pages.dev` by
default. The production deployment maps to `docs.vyrox.dev` via a
CNAME under the `vyrox.dev` zone. Configure that under Pages > the
project > Custom domains.

## Headers and redirects

Both files live at the repo root and are copied into `book/` by the
build script:

- `_headers` carries the security headers (CSP, HSTS, frame-ancestors,
  referrer policy, permissions policy) plus aggressive caching for
  hashed assets and short revalidation for HTML.
- `_redirects` maps the friendly path aliases (`/architecture`,
  `/api`, etc) to the mdBook-generated chapter URLs.

The header CSP allows Google Fonts because the site loads Fraunces,
Geist, and JetBrains Mono from `fonts.googleapis.com` and
`fonts.gstatic.com`. Removing those allowances breaks typography.

## Preview deployments

Cloudflare Pages builds every branch automatically. A pull request
gets a preview URL of the form
`<commit-sha>.<project>.pages.dev`. The default behaviour is fine
for our use case; we do not gate previews behind authentication
because the docs are public anyway.

If a contributor adds private documentation in the future, gate the
preview environments via Cloudflare Access. The setting lives under
Pages > the project > Settings > Access policy.

## Local reproduction

Run the exact build that Cloudflare Pages runs:

```bash
bash scripts/build.sh
```

That fetches mdBook into `.mdbook-bin/` (so your global install is
not touched), syncs the top-level Markdown into `src/`, and writes
the site into `book/`. Serve it with anything that serves static
files:

```bash
python -m http.server -d book 8080
```

Or use `mdbook serve` for the watch loop while editing.

## Troubleshooting

**Build fails with "mdbook not found".** The script tries to fetch a
binary from GitHub Releases. Cloudflare Pages build hosts have
outbound HTTPS so this works by default. If you see a download
failure, check the GitHub Releases page for the pinned tag and
verify the URL pattern. Newer mdBook releases sometimes change the
archive naming.

**Build succeeds but the deploy 404s.** The output directory is
`book`, not `dist` or `public`. Double-check the Cloudflare project
settings.

**Headers are not applied.** Cloudflare Pages reads `_headers` from
the root of the published directory. If you do not see your CSP on
production, confirm that `_headers` ended up inside `book/` after the
build. The build script copies it; if you ran `mdbook build`
directly without the script, the copy will not have happened.

**Fonts render as the system default.** Either the CSP is blocking
the Google Fonts CDN, or the build is missing the Google Fonts link
tag. The link tag is injected by `theme/head.hbs`. Confirm with
`grep fonts.googleapis.com book/index.html` that the link is present.

## Cross-references

- [`README.md`](README.md) for the project overview.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) for the docs contribution
  workflow.
