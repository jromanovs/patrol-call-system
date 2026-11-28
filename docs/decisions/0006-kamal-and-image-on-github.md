# 0006. Kamal on one server, with the image built on GitHub

- Status: accepted
- Date: 2026-10-07
- Issues: #23, #130; pull requests: #26, #131, #132, #133

## Context

The system runs on one server with HTTPS. First the image was built on the machine that ran the deploy, for another architecture than its own: a change that broke the build was found only at the deploy, and the deploy needed a running Docker engine on that machine (#130).

## Options

- Capistrano on a server with Ruby, PostgreSQL and a web server installed by hand.
- Kamal with the image built on the deploying machine.
- Kamal with the image built on GitHub after every push to `main` and kept in the container registry of GitHub under the name of its record.

## Decision

Kamal: the application, PostgreSQL and kamal-proxy with a Let's Encrypt certificate in Docker containers on one server. The workflow `Image` builds the image of every record on `main`; `bin/deploy` deploys the record `main` points at with that image and builds nothing. The way back to a build on the deploying machine is described in the README.

## Consequences

A pull request shows whether the image still builds. The server reads the registry with a key that may only read packages. The production secrets are not given to GitHub. Kamal checks `/up` before it sends traffic to a new version.
