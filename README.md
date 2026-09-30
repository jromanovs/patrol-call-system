# Patrol Car Call Management System

Web application for the monitoring centre of a private security company: guarded sites, patrol cars, alarm and client calls, dispatching and statistics. What the system does is described in [SPECIFICATION.md](SPECIFICATION.md).

## Requirements

- Ruby 3.4.10
- PostgreSQL

## Setup

```sh
bin/setup --skip-server
git config core.hooksPath .githooks
```

## Run

```sh
bin/dev
```

## Checks

```sh
bin/ci
```
