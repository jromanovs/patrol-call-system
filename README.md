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

On GitHub two workflows run for every pull request and for every record on `main`. `CI` runs `bin/ci`. `Image` builds the image of the application for the server; the image of a record on `main` is kept in the container registry of GitHub under the name of the record, and a pull request only shows that the image still builds.

## Deploy

```sh
bin/kamal deploy
```

Production secrets live in `config/credentials/production.yml.enc`; edit them with `bin/rails credentials:edit --environment production`. Kamal reads the key from `config/credentials/production.key` and the database password from the macOS keychain (`.kamal/secrets`). Neither is in the repository.

### Server preparation

The application must see the address of a sender that comes over IPv6. With Docker's defaults it sees an address of the container network instead, and every such sender is logged, and counted by the sign-in limit, as one. Two things on the server prevent that. Docker has to be installed already; `docker version --format '{{.Server.Version}}'` prints its version.

1. Docker adds its IPv6 rules. From Engine 27 on it does, unless `/etc/docker/daemon.json` says `"ip6tables": false`. An older engine needs both keys below in that file, beside any it already has, and a restart of Docker. Without `experimental` such an engine does not start, although `dockerd --validate` accepts the file.

   ```json
   { "experimental": true, "ip6tables": true }
   ```

2. The network Kamal uses has IPv6. On a new server create it before the first `bin/kamal setup`, which otherwise creates it without. An engine older than 27 needs the range named: a `/64` of your own under `fd00::/8` (RFC 4193).

   ```sh
   docker network create --ipv6 --subnet fdxx:xxxx:xxxx::/64 kamal
   ```

`.kamal/hooks/pre-deploy` checks both before every deploy and rollback: after the image is built and pulled, before the network or a container is touched. It reads the network, the engine's version and mode and the settings file on each server through `bin/kamal server exec`, which adds a line to Kamal's audit log there, and stops with the server and the reason. `--skip-hooks` deploys without the check.

An existing network cannot be given IPv6; on a server that already runs it is made again. Do step 1 first. The site is down from the first command below until the deploy ends; the volumes stay. The chain stops at the first command that fails: correct it and run the rest from that command on.

```sh
range=fdxx:xxxx:xxxx::/64
bin/kamal app stop &&
  bin/kamal proxy stop && bin/kamal proxy remove_container &&
  bin/kamal accessory stop db && bin/kamal accessory remove_container db &&
  bin/kamal server exec "docker network rm kamal && docker network create --ipv6 --subnet $range kamal" &&
  bin/kamal accessory boot db &&
  bin/kamal deploy
```
