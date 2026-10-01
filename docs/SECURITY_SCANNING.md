# Security scanning

Vaquita MX runs dependency, source, secret, and API image checks on every pull
request. The checks supplement review; they do not establish that a release is
free of vulnerabilities.

## Automated coverage

| Risk | Control | Blocking threshold |
| --- | --- | --- |
| Outdated Go, Flutter, Actions, or Docker dependencies | Weekly Dependabot updates | Review and merge through normal CI |
| Known reachable Go vulnerabilities | `govulncheck` | Any reachable vulnerability |
| Insecure Go patterns | Gosec | High severity with medium or high confidence |
| Committed credentials | Gitleaks over complete Git history | Any unallowlisted finding |
| API operating-system or library vulnerabilities | Trivy against the built runtime image | Fixable high or critical finding |

GitHub code scanning and native secret scanning/push protection are not
available for this private repository on its current plan. Gosec and Gitleaks
are the CI fallbacks. Re-evaluate the native features if the repository becomes
public or GitHub Code Security and GitHub Secret Protection become available.

Repository workflows have read-only `contents` permission; the security
workflow also has read-only pull-request metadata so Gitleaks can determine the
commits to scan. External actions are pinned to full commit SHAs, with the
reviewed release recorded in a comment. Dependabot proposes updates to those
pins for review.

## Triage and remediation

The person reviewing a finding must confirm the affected package, execution
path, available fix, and exposure in Vaquita MX. Do not paste credentials or
other sensitive values into issues, pull requests, or logs.

| Severity | Target response |
| --- | --- |
| Critical, reachable or exposed | Stop release; rotate exposed credentials immediately; fix or mitigate within 24 hours |
| High | Block release; fix or mitigate within 7 days |
| Medium | Add to the backlog and remediate within 30 days |
| Low | Triage and include in routine dependency maintenance |

A leaked credential is treated as compromised even if the commit is reverted:
revoke or rotate it first, remove it from current files, then decide whether Git
history must be rewritten. Never use a real credential as a scanner fixture.

## Exceptions

Suppress a finding only when it is a demonstrated false positive, unreachable,
or has no safe fix and the documented compensating control makes acceptance
reasonable. An exception must be reviewed in a pull request and record:

- scanner and finding identifier;
- affected component and version;
- evidence supporting the decision;
- compensating controls;
- owner and expiry date, no more than 90 days away.

Keep suppressions as narrow as possible. Expired exceptions must be removed or
re-reviewed. Critical credential findings cannot be excepted.

### Current baseline disposition

`GO-2026-5932` reports that `golang.org/x/crypto/openpgp` is unmaintained and
has no fixed version. Vaquita MX requires `x/crypto` for password hashing but
does not import `openpgp`; Govulncheck reports no affected package or symbol.
The compensating controls are the absence of that import and the blocking
Govulncheck job. Repository maintainers own this disposition, which expires on
2026-12-29 and must then be removed or re-reviewed.

## Local verification

Run source and dependency checks with Go 1.26.6 or newer from `services/api`:

```text
go run github.com/securego/gosec/v2/cmd/gosec@v2.29.0 -exclude-generated -severity high -confidence medium ./...
go run golang.org/x/vuln/cmd/govulncheck@v1.1.4 ./...
```

Run Gitleaks 8.30.1 against the full repository history and build then scan the
API image with Trivy 0.70.0 using the same inputs as
`.github/workflows/security.yml`. Developer machines may use the official
binaries or containers; do not commit scanner test fixtures.

For a safe smoke test, create a temporary Git repository outside this project,
add a Gitleaks documented dummy credential, confirm the scanner exits non-zero,
and delete the temporary repository. The CI workflow itself is validated with a
manual `workflow_dispatch` run after changes to scanner configuration.
