# 0010. The errors of production are kept by solid_errors

- Status: accepted
- Date: 2026-11-28
- Issue: #162

## Context

An exception on the server was seen only in the log of the container (`bin/kamal app logs`), with no count of repeats and no list, and the log is lost when the container is removed.

## Options

- The log of the container only: nothing to run, nothing kept.
- A service of another party (Sentry, Honeybadger, AppSignal): an account, a key, and the errors with their context sent out of the server.
- GlitchTip on a server of its own with `sentry-ruby`: one more server to run.
- solid_errors: a subscriber of `Rails.error` that keeps the errors in tables of the application's own database, with a page of its own.

## Decision

solid_errors 0.9.1, its two tables in the primary database through a migration, as its README describes for an application without a database of errors of its own. Its pages open at `/errors` and are built on `ErrorPagesController`, so the sign-in and the role of the application decide who sees them: the administrator only (BR-14). No e-mail; the occurrences of a resolved error older than 30 days are removed (`destroy_after`).

## Consequences

No service and no database besides those of 0005. The parameters of a request are not kept (`record_params` is off by default). The pages of the gem are in English only. A shared controller names the routes of the application through `main_app`, since inside the gem's pages the names of routes are the gem's.
