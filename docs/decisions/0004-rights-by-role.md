# 0004. Rights by role with Pundit

- Status: accepted
- Date: 2026-10-01
- Issue: #21; pull request: #28

## Context

Four roles see and do different things: dispatcher, shift supervisor, administrator and patrol crew (1.3, BR-14). A crew user sees only the call of its own car (CRW-03). The rule for each action has to be in one place and testable without a browser.

## Options

- Checks of the role in each controller: the rules are scattered and repeated.
- CanCanCan: one file of abilities for the whole system, which grows with every screen.
- Pundit: one plain Ruby class of rules per model or screen.

## Decision

Pundit, with one policy per model or screen in `app/policies` and a refusal handled once in `ApplicationController`.

## Consequences

A new screen brings its policy and its policy spec in `spec/policies`. A refused action gets the message "Not allowed for your role", or the status 403 for JSON.
