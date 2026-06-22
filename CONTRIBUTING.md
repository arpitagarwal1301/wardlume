# Contributing to Wardlume

Contributions are welcome. Before your contribution can be accepted, please read and agree to the contribution terms below.

## Development setup

After cloning, enable the project git hooks once:

```sh
git config core.hooksPath .githooks
```

This installs a **pre-push hook** that runs [`scripts/check-docs.sh`](scripts/check-docs.sh) — a fast guard that the docs stay in sync: version references match `MARKETING_VERSION`, internal links resolve, and CI badges point at real workflows. The same script runs in CI (`.github/workflows/docs-check.yml`) on every push and PR, so drift is caught either way. Run it anytime with `./scripts/check-docs.sh`; bypass the hook in an emergency with `git push --no-verify`.

## Contribution License

By submitting a contribution (a pull request, patch, or any code, documentation, or other material) to this project, you agree that:

1. You are the original author of the contribution, or you have the right to submit it.
2. You grant Arpit Agarwal (the project maintainer and licensor) a perpetual, worldwide, non-exclusive, royalty-free, irrevocable license — with the right to sublicense and relicense — to use, reproduce, modify, adapt, publish, distribute, and **commercially exploit** your contribution, in whole or in part, in any form and through any channel, including in proprietary and commercial versions of Wardlume (such as paid App Store distributions).
3. This grant is in addition to, and broader than, the public license under which the project is distributed. The project is offered to the public under the PolyForm Noncommercial License 1.0.0; your grant to the maintainer above is not limited to noncommercial use.
4. You retain all other rights to your contribution, including the right to use it elsewhere.

If you do not agree to these terms, please do not submit a contribution.
