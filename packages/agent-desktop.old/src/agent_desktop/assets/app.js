import RFB from "/novnc/core/rfb.js";

const elements = {
  sessions: document.querySelector("#sessions"),
  state: document.querySelector("#state"),
  refresh: document.querySelector("#refresh"),
  fullscreen: document.querySelector("#fullscreen"),
  destroy: document.querySelector("#destroy"),
  screen: document.querySelector("#screen"),
  empty: document.querySelector("#empty"),
};

const fragment = new URLSearchParams(location.hash.slice(1));
const token = fragment.get("token") || "";
let selected = fragment.get("session");
let sessions = [];
let rfb = null;
let connectedSession = null;
let reconnectTimer = null;

function setStatus(text, state = "idle") {
  elements.state.textContent = text;
  elements.state.dataset.state = state;
}

function selectedSession() {
  return sessions.find((session) => session.id === selected) || null;
}

function updateLocation() {
  const next = new URLSearchParams({ token });
  if (selected) next.set("session", selected);
  history.replaceState(null, "", `#${next}`);
}

function chooseSession() {
  if (selected && sessions.some((session) => session.id === selected)) return;
  const remembered = localStorage.getItem("agent-desktop.last-session");
  if (remembered && sessions.some((session) => session.id === remembered)) {
    selected = remembered;
    return;
  }
  const ready = sessions.filter((session) => session.viewer_available);
  if (ready.length === 1) {
    selected = ready[0].id;
    return;
  }
  if (ready.length > 1) {
    ready.sort((a, b) => (b.ready_at || 0) - (a.ready_at || 0));
    selected = ready[0].id;
    return;
  }
  selected = sessions[0]?.id || null;
}

function renderSelector() {
  elements.sessions.replaceChildren();
  const placeholder = new Option(
    sessions.length ? "Select an agent desktop" : "No agent desktops",
    "",
  );
  elements.sessions.add(placeholder);
  for (const session of sessions) {
    const label = `${session.agent_id} — ${session.id} (${session.state})`;
    elements.sessions.add(new Option(label, session.id));
  }
  elements.sessions.value = selected || "";
}

function disconnect() {
  clearTimeout(reconnectTimer);
  reconnectTimer = null;
  if (rfb) {
    rfb.disconnect();
    rfb = null;
  }
  connectedSession = null;
  elements.screen.replaceChildren();
}

function connect() {
  const session = selectedSession();
  elements.destroy.disabled = !session || session.state === "stopped";
  if (!session) {
    disconnect();
    elements.empty.hidden = false;
    setStatus(sessions.length ? "Select" : "Empty");
    return;
  }

  localStorage.setItem("agent-desktop.last-session", session.id);
  elements.empty.hidden = session.viewer_available;
  if (!session.viewer_available) {
    disconnect();
    setStatus(session.message || session.state, session.state);
    return;
  }
  if (connectedSession === session.id && rfb) return;

  disconnect();
  elements.empty.hidden = true;
  setStatus("Connecting", "starting");
  const scheme = location.protocol === "https:" ? "wss" : "ws";
  const url = `${scheme}://${location.host}/ws/${encodeURIComponent(session.id)}?token=${encodeURIComponent(token)}`;
  rfb = new RFB(elements.screen, url, { shared: true });
  connectedSession = session.id;
  rfb.scaleViewport = true;
  rfb.resizeSession = false;
  rfb.viewOnly = false;
  rfb.addEventListener("connect", () => setStatus("Ready", "ready"));
  rfb.addEventListener("disconnect", (event) => {
    rfb = null;
    connectedSession = null;
    if (!event.detail.clean && selected === session.id) {
      setStatus("Reconnecting", "reconnecting");
      reconnectTimer = setTimeout(() => void refresh(), 1500);
    }
  });
  rfb.addEventListener("securityfailure", () => setStatus("VNC denied", "failed"));
}

async function refresh() {
  if (!token) {
    setStatus("Unauthorized", "failed");
    elements.empty.hidden = false;
    elements.empty.querySelector("h1").textContent = "Open this viewer with agent-desktop view";
    return;
  }
  try {
    const response = await fetch(`/api/sessions?token=${encodeURIComponent(token)}`, {
      cache: "no-store",
    });
    if (!response.ok) throw new Error(await response.text());
    sessions = await response.json();
    chooseSession();
    updateLocation();
    renderSelector();
    connect();
  } catch (error) {
    setStatus("Unavailable", "failed");
    console.error(error);
  }
}

elements.sessions.addEventListener("change", () => {
  selected = elements.sessions.value || null;
  updateLocation();
  connect();
});
elements.refresh.addEventListener("click", () => void refresh());
elements.fullscreen.addEventListener("click", () => {
  void document.documentElement.requestFullscreen();
});
elements.destroy.addEventListener("click", async () => {
  const session = selectedSession();
  if (!session || !confirm(`Destroy ${session.id}?`)) return;
  const response = await fetch(
    `/api/sessions/${encodeURIComponent(session.id)}/destroy?token=${encodeURIComponent(token)}`,
    { method: "POST" },
  );
  if (!response.ok) alert(await response.text());
  await refresh();
});

await refresh();
setInterval(() => void refresh(), 2000);
