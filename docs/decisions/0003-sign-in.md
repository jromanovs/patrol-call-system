# 0003. Sign-in with a password and ALTCHA, or with Google

- Status: accepted
- Date: 2026-10-01
- Issue: #21; pull request: #28

## Context

Every page except the sign-in form is for signed-in users only, and accounts are created by the administrator; there is no self-registration (1.3, 3.8). The sign-in form is public and has to resist guessing by bots without sending the visitor to an outside service.

## Options

- Devise: many features the system does not use (registration, password reset by e-mail).
- The Rails 8 authentication generator: sessions and passwords in the application's own code.
- An outside identity service only: every user would need an account there.
- Against bots: a CAPTCHA of an outside service, which loads its scripts from that service, or ALTCHA, a proof-of-work check that runs in the browser and on the own server.

## Decision

The Rails 8 authentication generator with passwords of at least 12 characters and at most 10 attempts from one address within 3 minutes (BR-16); ALTCHA on the password form, each solved task accepted once; sign-in with Google (OAuth 2.0, OmniAuth) for an existing active user with the same verified address.

## Consequences

The sign-in code is the application's own and is tested with it. The Google client secret is kept in the encrypted production credentials. A user without a Google account signs in with the password.
