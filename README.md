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

On GitHub two workflows run for every pull request and after every push to `main`. `CI` runs `bin/ci`. `Image` builds the image of the application for the server. After a push to `main` the image of the record `main` then points at is kept in the container registry of GitHub under the name of that record; two merges one after the other each get their image. A pull request only shows that the image still builds.

## Deploy

```sh
bin/deploy
```

`bin/deploy` deploys the record `main` points at on GitHub with the image the workflow `Image` built for it. Nothing is built on the deploying machine, which needs no Docker engine. Through the GitHub CLI (`gh`, installed and signed in) it asks GitHub where `main` points and how that build ended, both in the repository the image is named after. It stops before the server is touched, and says why, when the folder holds changes that are in no record, when the folder is not at that record, or when the image is not built yet. Of Kamal's options it takes `--verbose` and `--skip-hooks` and hands them on; any other word stops it, since it could name another record or start a build.

The server reads the image from the container registry of GitHub with a key that may read packages and nothing else: a personal access token (classic) with the scope `read:packages` alone. The registry accepts only this kind of key, and it reads every package its account may read. Kamal takes it from the macOS keychain (`.kamal/secrets`); the command below asks for it without echo and stores it, or replaces the one already there. A deploy hands the key to the server, which keeps it in the Docker settings of the deploy user. With a key that has expired or is revoked a deploy stops at the sign-in, before the image is pulled, and the site stays as it was.

```sh
security add-generic-password -U -s patrol-call-system -a KAMAL_REGISTRY_PASSWORD -w
```

Production secrets live in `config/credentials/production.yml.enc`; edit them with `bin/rails credentials:edit --environment production`. Kamal reads the key from `config/credentials/production.key` and the database password from the same keychain. None of the three is in the repository, and none is given to the workflows on GitHub.

### Server preparation

The application must see the address of a sender that comes over IPv6. With Docker's defaults it sees an address of the container network instead, and every such sender is logged, and counted by the sign-in limit, as one. Two things on the server prevent that. Docker has to be installed already; `docker version --format '{{.Server.Version}}'` prints its version.

1. Docker adds its IPv6 rules. From Engine 27 on it does, unless `/etc/docker/daemon.json` says `"ip6tables": false`. An older engine needs both keys below in that file, beside any it already has, and a restart of Docker. Without `experimental` such an engine does not start, although `dockerd --validate` accepts the file.

   ```json
   { "experimental": true, "ip6tables": true }
   ```

2. The network Kamal uses has IPv6. On a new server create it before the first `bin/kamal setup --skip-push`, which otherwise creates it without. An engine older than 27 needs the range named: a `/64` of your own under `fd00::/8` (RFC 4193).

   ```sh
   docker network create --ipv6 --subnet fdxx:xxxx:xxxx::/64 kamal
   ```

`.kamal/hooks/pre-deploy` checks both before every deploy and rollback: after the image is pulled, before the network or a container is touched. It reads the network, the engine's version and mode and the settings file on each server through `bin/kamal server exec`, which adds a line to Kamal's audit log there, and stops with the server and the reason. `--skip-hooks` deploys without the check.

An existing network cannot be given IPv6; on a server that already runs it is made again. Do step 1 first. The site is down from the first command below until the deploy ends; the volumes stay. The chain stops at the first command that fails: correct it and run the rest from that command on.

```sh
range=fdxx:xxxx:xxxx::/64
bin/kamal app stop &&
  bin/kamal proxy stop && bin/kamal proxy remove_container &&
  bin/kamal accessory stop db && bin/kamal accessory remove_container db &&
  bin/kamal server exec "docker network rm kamal && docker network create --ipv6 --subnet $range kamal" &&
  bin/kamal accessory boot db &&
  bin/deploy
```
