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

## Deploy

```sh
bin/kamal deploy
```

Production secrets live in `config/credentials/production.yml.enc`; edit them with `bin/rails credentials:edit --environment production`. Kamal reads the key from `config/credentials/production.key` and the database password from the macOS keychain (`.kamal/secrets`). Neither is in the repository.

### Server preparation

The application must see the address of a sender that comes over IPv6. With Docker's defaults it sees an address of the container network instead, and every such sender is logged, and counted by the sign-in limit, as one. Before the first `bin/kamal setup` on a new server:

1. Docker Engine older than 27 only: create `/etc/docker/daemon.json` and restart Docker.

   ```json
   { "experimental": true, "ip6tables": true }
   ```

2. Create the network Kamal uses, with IPv6. An engine older than 27 needs the range named: a `/64` of your own under `fd00::/8` (RFC 4193).

   ```sh
   docker network create --ipv6 --subnet fdxx:xxxx:xxxx::/64 kamal
   ```

`.kamal/hooks/pre-deploy` reads both on the server before every deploy and stops the deploy when either is missing; `bin/kamal deploy --skip-hooks` deploys without the check.

An existing network cannot be given IPv6. On a server that already runs, the network is made again; the volumes stay, and the site is down for about a minute:

```sh
bin/kamal app stop
bin/kamal proxy stop && bin/kamal proxy remove_container
bin/kamal accessory stop db && bin/kamal accessory remove_container db
bin/kamal server exec "docker network rm kamal && docker network create --ipv6 --subnet fdxx:xxxx:xxxx::/64 kamal"
bin/kamal accessory boot db
bin/kamal deploy
```
