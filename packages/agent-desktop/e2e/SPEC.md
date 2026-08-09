# Agent Desktop — Activated-System Behavior Acceptance

The executable suite and its fixtures live beside this file. From the package
root, run it explicitly with `./e2e/run`; normal pytest, package builds, NixOS
builds, and switches do not execute it.

## 1. Authority and purpose

This is the black-box acceptance procedure for the behaviors in
`~/Dev/my.pi/reports/agent-desktop-accepted-behaviors.md`.

The suite judges observable outcomes. It must continue to pass if internals are
reorganized or replaced. In particular, it does **not** require a specific:

- Python module, class, or state-file layout;
- process count or service-start sequence;
- systemd unit type, property set, or cleanup-unit design;
- copy-on-write, reflink, full-copy, or mount implementation for browser clones;
- log filename, private helper protocol, or compositor implementation.

An implementation-specific probe may be retained as diagnostic evidence, but it
cannot determine acceptance unless the corresponding detail is part of the
accepted behavior or public Nix/CLI contract.

## 2. Safety and preconditions

Run against an activated candidate NixOS generation as the interactive Unix
user. A package-only build is insufficient for graphical acceptance.

Before creating a desktop, the harness must:

1. choose unique session and fixture names prefixed with `e2e-`;
2. create a mode-0700 evidence directory outside all session runtime trees;
3. install unconditional cleanup traps;
4. record the primary compositor's windows, focus, and relevant environment;
5. confirm that no session from this test run already exists;
6. create only temporary files, browser data, and Secret Service entries;
7. avoid writing to the live or golden Vivaldi profile;
8. redact secrets and viewer tokens from retained evidence.

A pre-existing non-test desktop is not automatically a failure. The harness
must leave it untouched and distinguish it by stable identity.

Suggested identifiers:

```bash
RUN_ID="$(date +%Y%m%d-%H%M%S)"
PRIMARY="e2e-primary-$RUN_ID"
SECONDARY="e2e-secondary-$RUN_ID"
EVIDENCE="/tmp/agent-desktop-e2e-$RUN_ID"
install -d -m 0700 "$EVIDENCE"
```

## 3. Public test surface

The suite may use:

- `agent-desktop create|status|list|exec|browser|view|destroy`;
- JSON emitted by those commands;
- the configured private CUA and VNC endpoints;
- the loopback viewer and its documented authorization flow;
- ordinary application, accessibility, portal, PipeWire, and D-Bus clients;
- generated Nix configuration and boot/service history to establish startup
  ordering;
- process and resource inspection only to establish ownership, isolation, or
  cleanup outcomes.

The suite must not import package internals or mutate session state records.

## 4. Behavior scenarios

### B-001 — Installed public contract

**Covers:** AD-001, AD-003, UI-001, UI-008, BR-009.

Given the candidate generation is active, when the harness resolves
`agent-desktop` and runs `agent-desktop --help`, then:

- `create`, `status`, `list`, `exec`, `browser`, `view`, and `destroy` exist;
- generated configuration refers to executable package and CUA commands;
- the configured CUA implementation is the same patched package selected by the
  computer-use aspect;
- every project-started CUA process receives telemetry-disabled configuration.

### B-010 — Safe golden browser snapshot

**Covers:** BR-001, BR-002, BR-007, BR-008.

Given a completed boot, when the harness examines the configured golden profile
and boot history, then:

- the snapshot was successfully completed before graphical login was allowed;
- it is a private, internally consistent copy of startup browser state;
- unsafe singleton endpoints, DevTools endpoints, and crash artifacts are absent;
- no browser process has the golden profile open;
- a failed refresh cannot expose a partially replaced snapshot as ready.

Record a content manifest before later browser scenarios. Do not require a
particular service name or copying command.

### B-020 — On-demand lifecycle and readiness

**Covers:** AD-001, AD-003, AD-004, CON-003, CON-004.

When the harness runs:

```bash
agent-desktop create e2e-owner --session-id "$PRIMARY" --json
```

then creation completes within the configured timeout, returns the requested
stable identity, and reports `ready` only after the desktop is usable.

While startup is deliberately delayed, `status` must report `starting`. The
default configuration imposes no arbitrary session-count ceiling: creation
continues until the operating system or a required service reports real resource
exhaustion. Operators may configure an explicit limit; requests beyond that limit
must fail explicitly and must never reuse another agent's desktop. `list --json`
and `status --json` must agree about identity and lifecycle state.

### B-030 — Private desktop and environment

**Covers:** ID-001, ID-002, ID-004, ID-005, ISO-001–ISO-004, CON-001.

Given `$PRIMARY` is ready, launch an environment/window probe with
`agent-desktop exec`. Then:

- the process has the interactive user's Unix identity and ordinary file access;
- its Wayland, compositor, D-Bus, AT-SPI, portal, PipeWire, CUA, and VNC resources
  belong to `$PRIMARY`;
- primary `WAYLAND_DISPLAY`, compositor sockets, `DISPLAY`, `SSH_AUTH_SOCK`, and
  unrelated credential variables were not inherited;
- its uniquely titled window appears only in the private desktop;
- foreground focus, typing, and pointer actions do not alter primary-desktop
  focus, windows, pointer targets, or keyboard targets;
- an unavailable private target fails rather than falling back to the host.

### B-040 — Exact application launch and ownership

**Covers:** AD-006–AD-008, CON-005, CON-006.

Launch a command whose argument contains spaces and shell metacharacters:

```bash
VALUE='exact value ; $(not-executed)'
agent-desktop exec --json "$PRIMARY" -- \
  bash -c 'printf %s "$1" > "$2"; printf stdout; printf stderr >&2; sleep 600' \
  _ "$VALUE" "$ORACLE"
```

Then:

- the oracle contains the literal value and no shell reconstruction occurred;
- the JSON result contains a positive process ID and the exact argument array;
- stdout and stderr are attributable to this session/application;
- the process belongs to `$PRIMARY`'s lifecycle and resource ownership;
- `status` reports `active` while an owned application is running;
- after all applications exit normally, the desktop returns to `ready`;
- a missing executable reports an application failure and leaves the desktop
  ready;
- stopped, failed, missing, or mismatched sessions reject launch requests.

Retain the sleeping process ID for teardown verification.

### B-050 — Independent disposable Vivaldi state

**Covers:** BR-003–BR-006, BR-009–BR-011, ID-003, CU-003.

Create a local HTML fixture containing a unique title, a labelled input, and a
button that changes the title. Run:

```bash
agent-desktop browser --json "$PRIMARY" "file://$FIXTURE"
```

Then:

- Vivaldi opens in `$PRIMARY`, using a writable profile assigned only to it;
- startup bookmarks, extensions, preferences, cookies, and authenticated state
  match the golden snapshot subject to browser policy;
- no first-run or stale crash-recovery prompt blocks use;
- accessibility is enabled for browser chrome and web content;
- profile changes, history, and cookies do not alter the live profile, golden
  profile, or another session;
- default downloads remain inside temporary session storage unless an explicit
  persistent destination is selected;
- destroying the session never merges changes back;
- no-URL launch opens `about:blank`;
- HTTP, HTTPS, `about:`, and absolute `file://` destinations work;
- invalid, oversized, and option-like destinations fail before browser launch.

The public behavior accepts a private full copy, reflink clone, or copy-on-write
view. This NixOS integration currently uses FUSE copy-on-write so configured
concurrency cannot exhaust the user runtime tmpfs with complete profile copies.

### B-060 — Perception, accessibility, and action

**Covers:** CU-001–CU-008, CU-010.

Using `$PRIMARY`'s CUA endpoint:

1. obtain health and the native output dimensions;
2. capture a screenshot and desktop state;
3. inspect the fixture application's accessibility tree;
4. type into and activate its labelled controls semantically;
5. repeat the operation using screen coordinates, keyboard, and pointer input.

Then:

- health is successful and telemetry remains disabled;
- reported dimensions equal captured image dimensions;
- accessibility contains real application/browser controls, not mixed host data;
- semantic and visual actions produce application-owned oracle changes;
- click evidence includes button press/release activation, not cursor movement;
- every action remains confined to `$PRIMARY`.

### B-070 — Real private portal capture

**Covers:** CU-009.

Through the desktop's private portal bus, request a screenshot and a monitor
ScreenCast session. Open the returned portal-scoped PipeWire remote and consume
at least one frame. Use a direct raw consumer
(`pipewiresrc ! video/x-raw ! filesink` or an equivalent native PipeWire
client); conversion-heavy pipelines are not the portal contract.

Then the screenshot is a non-empty image of the private desktop, the stream
returns a non-zero node and consumable non-uniform frame, and dimensions agree
with CUA. Interface introspection without actual pixels is a failure.

### B-080 — Deliberately shared Secret Service

**Covers:** ID-003, ID-004.

Store a uniquely attributed temporary secret through `$PRIMARY`'s bus, read it
through the host bus and private bus, and repeat with two concurrent private
clients using distinct values. Then:

- values and Secret Service session semantics remain correct per client;
- disconnecting one client releases its bridge-side ownership without affecting
  another client;
- portals, accessibility, notifications, focus, and activation remain private;
- all temporary entries can be removed and none remain after cleanup.

### B-090 — On-demand observation and intervention

**Covers:** UI-001–UI-010.

Run `agent-desktop view "$PRIMARY" --print`, and also exercise the default form.
Then:

- observation starts on demand rather than with desktop creation;
- the printed URL selects `$PRIMARY` without requiring endpoint discovery;
- the default form opens the user's browser;
- the shared viewer listens only on loopback and requires its private token;
- the token is carried in the URL fragment, not the HTTP request URL;
- unauthorized API and WebSocket requests fail;
- the selector lists lifecycle/owner information for available desktops;
- pointer buttons and keyboard events reach `$PRIMARY`'s persistent seat; use
  an application-owned control and pace RFB events rather than inferring
  delivery from cursor movement or compositor device listings;
- closing the viewer does not stop `$PRIMARY`;
- explicit termination from the viewer stops only the selected desktop.

### B-100 — Concurrent independence

**Covers:** AD-002, CON-001–CON-005, BR-003, BR-005.

Create `$SECONDARY` while `$PRIMARY` remains ready. Launch uniquely titled apps
and Vivaldi in both. Then:

- both are simultaneously usable;
- windows, focus, input, clipboard, application processes, graphical/service
  endpoints, CUA results, VNC views, browser clones, and temporary artifacts are
  attributable to exactly one stable session identity;
- input and browser writes in one are absent from the other;
- stopping or crashing one leaves the other ready and usable.

Do not require particular socket names, process counts, or unit topology to prove
this separation.

### B-110 — Cancellation, crash, lease expiry, and cleanup

**Covers:** AD-004, AD-005, AD-007, CON-005.

Exercise all of the following independently:

1. destroy during startup;
2. ordinary `destroy` after applications and Vivaldi are running;
3. abrupt termination of the owning session supervisor/resource group;
4. configured runtime/lease expiry.

Within the configured stop timeout plus scheduling tolerance:

- every owned application and service process is gone;
- private display, bus, accessibility, CUA, VNC, portal, and control endpoints are
  gone;
- disposable browser state and other temporary session artifacts are gone;
- ordinary destroy reports `stopped`; unexpected loss reconciles to `failed` with
  a useful message;
- retained artifacts exist only at explicitly persistent destinations;
- another running desktop remains healthy.

### B-120 — Soak and final host isolation

**Covers:** ISO-001–ISO-004, UI-005, CU-005, acceptance summary.

Keep one fully exercised desktop alive for at least one health interval. It must
remain ready and all major operations must still work.

After final teardown, compare host state and enumerate resources by test identity.
Acceptance requires:

- no test-owned process, endpoint, viewer token, browser clone, secret, or
  temporary artifact remains;
- no fixture window ever appeared on the primary compositor;
- the host focus sentinel was unchanged except for independent user activity;
- the golden profile manifest is unchanged;
- non-test host CUA/compositor processes and pre-existing desktops remain intact.

## 5. Evidence

Retain machine-readable CLI results, before/after host state, screenshots,
captured portal frame metadata, application oracles, relevant logs, browser
manifests, viewer authorization results, and final resource enumeration. Name
evidence by behavior scenario rather than internal component.

## 6. Pass criteria

The activated-system suite passes only when every applicable behavior scenario
passes and unconditional cleanup succeeds. Degraded accessibility, metadata-only
portal tests, cursor movement without click activation, shared writable browser
state, fallback to the primary desktop, or residual session-owned resources are
failures regardless of implementation architecture.
