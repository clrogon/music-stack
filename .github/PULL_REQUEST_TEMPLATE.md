## What does this change?

<!-- One or two sentences. If it fixes an issue, write "Fixes #123". -->

## Which script(s)?

<!-- e.g. windows/setup.ps1, macos/setup.sh, raspberry-pi/setup.sh, scripts/common/lib.sh,
     scripts/common/configure-lidarr.py -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation only
- [ ] Refactor (no functional change)

## Checklist

- [ ] **Parity rule respected**: any change to one platform script is mirrored in the other two
      (see `ARCHITECTURE.md` §2), or is documented as a deliberate platform exception
- [ ] Config files are written BOM-less (never `Set-Content -Encoding UTF8` for configs —
      see `MAINTENANCE.md`)
- [ ] Re-running the script is idempotent / safe
- [ ] No hardcoded paths, credentials, tokens, or machine-specific values introduced
- [ ] Secrets are not logged or echoed (password redacted from any pasted output)
- [ ] `ASCII` only in script output — no smart quotes, em-dashes, box-drawing characters, or emoji
- [ ] Validation passed (see `CONTRIBUTING.md`): `bash -n`, PSScriptAnalyzer, `py_compile`
- [ ] Docs updated if behavior, parameters, or run order changed (README / ARCHITECTURE /
      TROUBLESHOOTING / MAINTENANCE / CHANGELOG / ROADMAP as relevant)

## Testing performed

<!-- What did you actually run this against? Platform, OS version, fresh install vs existing. -->

## Anything reviewers should look at closely?

<!-- Optional. Flag anything you're unsure about. -->
