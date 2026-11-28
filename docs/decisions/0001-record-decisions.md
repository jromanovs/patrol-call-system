# 0001. Decisions are recorded here

- Status: accepted
- Date: 2026-11-28
- Issue: #158

## Context

The reasons for the database, the sign-in, the queue, the hosting and the external data are needed by whoever changes them later. They are spread over closed issues, pull requests and commit messages, and take long to find.

## Options

- Issues and pull requests only: the discussion is kept, the result is lost among comments.
- A section of the README: one file grows without limit and keeps no history of what replaced what.
- A folder of decision records in the MADR form (<https://adr.github.io/madr/>): one file per decision, with its status and the record that replaced it.

## Decision

Every decision that is costly to undo is a file `docs/decisions/NNNN-name.md`: context, options, decision, consequences, status, and the issue or pull request where it was made. An accepted record is not edited: a new decision is a new record with the line "Replaces NNNN", and the old one gets the status `superseded`.

## Consequences

A pull request that changes a dependency, a store, an external service or the way of deploying brings its record in the same pull request. Plans, progress and small changes stay in the issues.
