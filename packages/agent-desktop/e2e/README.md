# Agent Desktop activated-system E2E suite

This directory contains the executable black-box suite for the behaviors in
[`SPEC.md`](./SPEC.md). It tests the **activated graphical system**, not Python
implementation details.

The suite is intentionally excluded from:

- `pytest` (`pyproject.toml` collects only `tests/`);
- the Nix package source and `pytestCheckHook` (`package.nix` includes only
  production sources and `tests/*.py`);
- ordinary NixOS builds and switches.

## Run

Activate the candidate NixOS/Home Manager generation, then run as the
interactive graphical user:

```bash
cd ~/NixOS/packages/agent-desktop
./e2e/run
```

Useful options:

```bash
./e2e/run --list
./e2e/run --scenario B-001 --scenario B-020
./e2e/run --keep-evidence
./e2e/run --evidence /tmp/my-agent-desktop-evidence
```

The default run executes every scenario. It creates uniquely named `e2e-*`
sessions, installs unconditional cleanup, redacts viewer tokens and test
secrets, and writes a summary to the mode-0700 evidence directory. Terminal
`stopped`/`failed` state records remain as normal CLI history; runtime resources
are reclaimed.

## Dependencies

`./e2e/run` enters [`shell.nix`](./shell.nix) ephemerally unless it is already
inside that shell. This provides the fixture applications, libportal/GStreamer
compiler inputs, Secret Service client, and Python dependencies without adding
them to the product package or user profile.

The activated configuration must provide `agent-desktop`, its generated config,
the private desktop services, and the host compositor CLI (`hyprctl` on this
computer).

## Safety

- Existing non-E2E sessions are never destroyed.
- The live and golden browser profiles are read-only test inputs.
- Temporary Secret Service entries use a unique run attribute and are always
  removed.
- Viewer tokens and secret values are never retained.
- A failed scenario does not stop later scenarios; final cleanup always runs.
