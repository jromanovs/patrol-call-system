# 0002. PostgreSQL holds the data

- Status: accepted
- Date: 2026-10-01
- Pull request: #24

## Context

The system keeps addresses, sites, cars, calls with their steps, users, car positions and the records of photos (SPECIFICATION.md 4.4). Statistics count time between steps of a call in SQL (`CallStatistics`), and the address search must ignore case and Latvian diacritics (FLT-07).

## Options

- SQLite, the Rails default: no server to run, but one writer at a time.
- PostgreSQL: a server of its own, many writers, arithmetic on timestamps in SQL.

## Decision

PostgreSQL 17, in production as a Kamal accessory on the same server (`config/deploy.yml`, `accessories.db`), in CI as a service of the workflow.

## Consequences

The statistics use PostgreSQL functions such as `EXTRACT(EPOCH FROM ...)` and `LEAST`, so another database would need them rewritten. Production holds four databases: the primary one and those of the cache, the queue and Action Cable (0005).
