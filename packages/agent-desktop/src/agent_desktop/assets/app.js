import RFB from "/novnc/core/rfb.js";

const element = Object.fromEntries(
  ["sessions", "state", "refresh", "fullscreen", "destroy", "screen", "empty"].map(
    (id) => [id, document.querySelector(`#${id}`)],
  ),
);
const fragment = new URLSearchParams(location.hash.slice(1));
const token = fragment.get("token") || "";
let selected = fragment.get("session");
let sessions = [];
let rfb;
let connected;
let reconnect;

function status(text, state = "idle") {
  element.state.textContent = text;
  element.state.dataset.state = state;
}

function current() {
  return sessions.find((session) => session.id === selected);
}

function remember() {
  const next = new URLSearchParams({ token });
  if (selected) next.set("session", selected);
  history.replaceState(null, "", `#${next}`);
}

function choose() {
  if (current()) return;
  const previous = localStorage.getItem("agent-desktop.last-session");
  selected = sessions.find((session) => session.id === previous)?.id;
  if (!selected) {
    selected = sessions
      .filter((session) => session.viewer_available)
      .sort((a, b) => (b.ready_at || 0) - (a.ready_at || 0))[0]?.id;
  }
  selected ||= sessions[0]?.id;
}

function render() {
  element.sessions.replaceChildren();
  element.sessions.add(new Option(sessions.length ? "Select a desktop" : "No desktops", ""));
  for (const session of sessions) {
    element.sessions.add(
      new Option(`${session.agent_id} — ${session.id} (${session.state})`, session.id),
    );
  }
  element.sessions.value = selected || "";
}

function disconnect() {
  clearTimeout(reconnect);
  reconnect = undefined;
  rfb?.disconnect();
  rfb = undefined;
  connected = undefined;
  element.screen.replaceChildren();
}

function connect() {
  const session = current();
  element.destroy.disabled = !session || session.state === "stopped";
  if (!session) {
    disconnect();
    element.empty.hidden = false;
    status(sessions.length ? "Select" : "Empty");
    return;
  }
  localStorage.setItem("agent-desktop.last-session", session.id);
  if (!session.viewer_available) {
    disconnect();
    element.empty.hidden = false;
    status(session.message || session.state, session.state);
    return;
  }
  if (connected === session.id && rfb) return;
  disconnect();
  element.empty.hidden = true;
  status("Connecting", "starting");
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  const url = `${scheme}://${location.host}/ws/${encodeURIComponent(session.id)}?token=${encodeURIComponent(token)}`;
  rfb = new RFB(element.screen, url, { shared: true });
  connected = session.id;
  rfb.scaleViewport = true;
  rfb.resizeSession = false;
  rfb.viewOnly = false;
  rfb.addEventListener("connect", () => status("Ready", "ready"));
  rfb.addEventListener("disconnect", ({ detail }) => {
    rfb = undefined;
    connected = undefined;
    if (!detail.clean && selected === session.id) {
      status("Reconnecting", "reconnecting");
      reconnect = setTimeout(refresh, 1500);
    }
  });
  rfb.addEventListener("securityfailure", () => status("VNC denied", "failed"));
}

async function refresh() {
  if (!token) {
    status("Unauthorized", "failed");
    element.empty.hidden = false;
    element.empty.querySelector("h1").textContent = "Open with agent-desktop view";
    return;
  }
  try {
    const response = await fetch(`/api/sessions?token=${encodeURIComponent(token)}`, {
      cache: "no-store",
    });
    if (!response.ok) throw new Error(await response.text());
    sessions = await response.json();
    choose();
    remember();
    render();
    connect();
  } catch (error) {
    status("Unavailable", "failed");
    console.error(error);
  }
}

element.sessions.addEventListener("change", () => {
  selected = element.sessions.value || undefined;
  remember();
  connect();
});
element.refresh.addEventListener("click", refresh);
element.fullscreen.addEventListener("click", () => document.documentElement.requestFullscreen());
element.destroy.addEventListener("click", async () => {
  const session = current();
  if (!session || !confirm(`Destroy ${session.id}?`)) return;
  const response = await fetch(
    `/api/sessions/${encodeURIComponent(session.id)}/destroy?token=${encodeURIComponent(token)}`,
    { method: "POST" },
  );
  if (!response.ok) alert(await response.text());
  await refresh();
});

await refresh();
setInterval(refresh, 2000);
