{ vivaldi }:
vivaldi.override {
  # CDP has no authentication. Keep it loopback-only while making the primary
  # Vivaldi instance discoverable by local browser agents.
  commandLineArgs = "--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222";
}
