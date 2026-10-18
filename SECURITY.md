# Security

Warble reads what's playing on your Mac and can control playback in other apps. It runs a small helper Apple ships (`/usr/bin/perl`) to read now-playing information, updates itself, and takes `warble://` URLs. If you find a way to misuse any of that, please tell me privately first.

## Reporting a vulnerability

Use GitHub's private reporting: open the repository's [Security tab](https://github.com/LorcanChinnock/warble/security) and choose **Report a vulnerability**. Please don't open a public issue or pull request for it.

Include what you found, the Warble version, your macOS version, and the steps to reproduce it. A short proof of concept helps.

Please give me reasonable time to fix it before you share it more widely. I'll credit you in the release notes if you want.

## Supported versions

Only the latest release gets security fixes. Warble updates itself, and `brew upgrade --cask warble` installs the same release.

## What counts

- What's playing, or control of another app, reaching something you didn't ask for.
- A `warble://` URL, the bundled now-playing helper or a file Warble opens doing more than it should.
- The update path installing something that wasn't signed by the project.
- A file or setting being overwritten or deleted without you asking.

Bugs without a security impact belong in a [regular issue](https://github.com/LorcanChinnock/warble/issues/new/choose).
