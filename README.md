# Patrol Car Call Management System

Web application for the monitoring centre of a private security company: guarded sites, patrol cars, alarm and client calls, dispatching and statistics. What the system does is described in [SPECIFICATION.md](SPECIFICATION.md).

## Requirements

- Ruby 3.4.10
- Node.js 24 with npm
- PostgreSQL
- prettier 3.8.3 (Markdown check)

## Setup

```sh
bin/setup --skip-server
```

`bin/setup` installs the gems and npm packages, enables the checks before every commit (`.githooks`) and prepares the database.

## First user

There is no self-registration: the administrator creates accounts.

```sh
bin/rails users:create EMAIL=who@example.com NAME="Full Name" ROLE=administrator
```

The password is asked twice without echo. On the server: `bin/kamal app exec --interactive --reuse "bin/rails users:create ..."`.

## Run

```sh
bin/dev
```

## Checks

```sh
bin/ci
```
