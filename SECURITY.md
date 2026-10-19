# Security policy

## Reporting a vulnerability

Please report security problems privately, not in a public issue: use
[**Report a vulnerability**](https://github.com/alphaexposure/splash-launcher/security/advisories/new)
on this repository's Security tab. Include what you found, how to reproduce it, and which
version you used. You'll get a reply as soon as possible; this is a small, single-maintainer
project.

## Scope

This policy covers Splash Launcher itself, for example:

- how it stores and passes the API key (Keychain, environment, log redaction);
- how it starts and stops Splash (it launches the executable directly with an explicit
  argument list, and stops only processes it started);
- anything that could expose data from your Mac.

Problems in Splash or Splash-M1 themselves belong with those projects:
[incoai/splash](https://github.com/incoai/splash) and
[paperniuk/splash](https://github.com/paperniuk/splash).

## Supported versions

Fixes go into the latest release. Please check that the problem still happens there.
