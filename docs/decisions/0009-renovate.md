# 0009. Dependencies are updated by Renovate

- Status: accepted
- Date: 2026-11-28
- Issue: #161

## Context

The gems and npm packages were updated only when an advisory stopped `bin/ci`. Between the CI run of 2026-10-24 and 2026-11-27, 59 advisories in 14 gems built up, and were found only when `bin/ci` was run by hand (#152).

## Options

- An update by hand at a fixed time (`bundle update`, `npm update`): it depends on someone remembering it.
- Dependabot version updates, built into GitHub and set in `.github/dependabot.yml`, one block per kind of package.
- Renovate, a GitHub app: one file for every kind of package; the updates that are not major grouped in one pull request a week, each major update on its own, the fixes of advisories at once, and an issue that lists what is pending.

## Decision

Renovate with `config:recommended`, `group:allNonMajor` and `schedule:weekly` in Riga time (`renovate.json`). The fixes of advisories come from the Dependabot alerts of the repository.

## Consequences

Every update comes as a pull request that `bin/ci` checks before it is merged. Renovate does not read `config/importmap.rb`; `bin/importmap audit` in `bin/ci` covers its pins. An update of Ruby changes `.ruby-version` and the Dockerfile together, or `spec/kamal/image_sources_spec.rb` stops it.
