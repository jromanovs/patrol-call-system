# 0005. Solid Queue, Solid Cache and Solid Cable

- Status: accepted
- Date: 2026-10-01
- Pull request: #24

## Context

The system runs background jobs (the nightly map build, the pruning of car positions, the notices and reminders to crews), shares the counts of sign-in attempts between server processes, and pushes changes to open boards over WebSockets (DYN-01 and the others in 4.1). It runs on one server (0006).

## Options

- Redis with Sidekiq and the Redis adapters of the cache and of Action Cable: one more service to run, watch and back up.
- Solid Queue, Solid Cache and Solid Cable, the Rails 8 defaults: the same jobs, cache and messages kept in PostgreSQL.

## Decision

Solid Queue, Solid Cache and Solid Cable, each with its own database on the same PostgreSQL server (`config/database.yml`). Solid Queue runs inside Puma (`SOLID_QUEUE_IN_PUMA`), so the server runs one application container.

## Consequences

No service besides PostgreSQL. The recurring jobs are listed in `config/recurring.yml`.
