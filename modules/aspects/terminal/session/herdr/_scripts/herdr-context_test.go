//nolint:errcheck // Test socket cleanup is best effort.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestFocusTargetRole(t *testing.T) {
	tests := []struct {
		mode    string
		current tabRole
		want    tabRole
	}{
		{mode: "editor", current: roleShell, want: roleEditor},
		{mode: "editor", current: roleAgent, want: roleEditor},
		{mode: "editor", current: roleEditor, want: roleShell},
		{mode: "agent", current: roleShell, want: roleAgent},
		{mode: "agent", current: roleEditor, want: roleAgent},
		{mode: "agent", current: roleAgent, want: roleShell},
	}
	for _, test := range tests {
		got, err := focusTargetRole(test.mode, test.current)
		if err != nil {
			t.Fatal(err)
		}
		if got != test.want {
			t.Fatalf("focusTargetRole(%q, %q) = %q, want %q", test.mode, test.current, got, test.want)
		}
	}
	if _, err := focusTargetRole("unknown", roleShell); err == nil {
		t.Fatal("unknown focus mode was accepted")
	}
}

func TestClosestTabKeepsEveryRoleDirectoryLocal(t *testing.T) {
	tabs := []*tabState{
		{ID: "far", Role: roleEditor, Cwd: "/other"},
		{ID: "previous", Role: roleEditor, Cwd: "/other"},
		{ID: "current", Role: roleShell, Cwd: "/repo"},
		{ID: "next", Role: roleEditor, Cwd: "/other"},
		{ID: "same-cwd", Role: roleEditor, Cwd: "/repo"},
	}
	if got := closestTab(tabs, 2, roleEditor); got == nil || got.ID != "same-cwd" {
		t.Fatalf("closest editor = %#v, want same-cwd", got)
	}
	tabs[4].Cwd = "/other"
	if got := closestTab(tabs, 2, roleEditor); got != nil {
		t.Fatalf("editor outside current cwd = %#v, want nil", got)
	}
	if got := closestTab(tabs, 2, roleAgent); got != nil {
		t.Fatalf("missing agent = %#v, want nil", got)
	}

	tabs[1].Role = roleShell
	tabs[3].Role = roleShell
	if got := closestTab(tabs, 2, roleShell); got != nil {
		t.Fatalf("shell outside current cwd = %#v, want nil", got)
	}
	tabs[3].Cwd = "/repo"
	if got := closestTab(tabs, 2, roleShell); got == nil || got.ID != "next" {
		t.Fatalf("shell in current cwd = %#v, want next", got)
	}
}

func TestClassifyTab(t *testing.T) {
	tests := []struct {
		name string
		tab  tabState
		want tabRole
	}{
		{name: "shell", tab: tabState{Command: "btop"}, want: roleShell},
		{name: "editor command", tab: tabState{Command: "nvim"}, want: roleEditor},
		{name: "editor process", tab: tabState{ProcessCommand: "nvim"}, want: roleEditor},
		{name: "agent command", tab: tabState{Command: "pi"}, want: roleAgent},
		{name: "agent authority", tab: tabState{Agent: "pi", ProcessCommand: "nvim"}, want: roleAgent},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := classifyTab(&test.tab); got != test.want {
				t.Fatalf("role = %q, want %q", got, test.want)
			}
		})
	}
}

func TestCreateTargetTab(t *testing.T) {
	for _, test := range []struct {
		role        tabRole
		wantMethods []string
		wantCommand string
	}{
		{role: roleShell, wantMethods: []string{"tab.create"}},
		{role: roleEditor, wantMethods: []string{"tab.create", "pane.send_input"}, wantCommand: "nvim"},
		{role: roleAgent, wantMethods: []string{"tab.create", "pane.send_input"}, wantCommand: "pi"},
	} {
		t.Run(string(test.role), func(t *testing.T) {
			socketPath := filepath.Join(t.TempDir(), "herdr.sock")
			listener, err := net.Listen("unix", socketPath)
			if err != nil {
				t.Fatal(err)
			}
			defer closeIgnoringError(listener)
			var methods []string
			var command, createdWorkspace, createdCwd string
			var createdFocused bool
			serverDone := make(chan error, 1)
			go func() {
				for range test.wantMethods {
					connection, acceptErr := listener.Accept()
					if acceptErr != nil {
						serverDone <- acceptErr
						return
					}
					var got request
					if decodeErr := json.NewDecoder(connection).Decode(&got); decodeErr != nil {
						closeIgnoringError(connection)
						serverDone <- decodeErr
						return
					}
					methods = append(methods, got.Method)
					result := map[string]any{"type": "ok"}
					switch got.Method {
					case "tab.create":
						params := got.Params.(map[string]any)
						createdWorkspace = params["workspace_id"].(string)
						createdCwd = params["cwd"].(string)
						createdFocused = params["focus"].(bool)
						result = map[string]any{
							"type":      "tab_created",
							"tab":       map[string]any{"tab_id": "w1:t2", "workspace_id": "w1"},
							"root_pane": map[string]any{"pane_id": "w1:p2", "tab_id": "w1:t2"},
						}
					case "pane.send_input":
						command = got.Params.(map[string]any)["text"].(string)
					}
					encodeErr := json.NewEncoder(connection).Encode(map[string]any{"id": got.ID, "result": result})
					closeIgnoringError(connection)
					if encodeErr != nil {
						serverDone <- encodeErr
						return
					}
				}
				serverDone <- nil
			}()

			current := &tabState{WorkspaceID: "w1", Cwd: "/repo"}
			if err := createTargetTab(socketPath, current, test.role); err != nil {
				t.Fatal(err)
			}
			if err := <-serverDone; err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(methods, test.wantMethods) || command != test.wantCommand ||
				createdWorkspace != "w1" || createdCwd != "/repo" || !createdFocused {
				t.Fatalf(
					"methods = %#v, command = %q, workspace = %q, cwd = %q, focused = %t",
					methods, command, createdWorkspace, createdCwd, createdFocused,
				)
			}
		})
	}
}

func TestFocusCLIUsesSemanticContextAndCwd(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("HERDR_ACTIVE_TAB_ID", "w1:t2")
	socketPath := filepath.Join(t.TempDir(), "herdr.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	defer closeIgnoringError(listener)

	var methods []string
	var focusedTab string
	serverDone := make(chan error, 1)
	go func() {
		for range 5 {
			connection, acceptErr := listener.Accept()
			if acceptErr != nil {
				serverDone <- acceptErr
				return
			}
			var got request
			if decodeErr := json.NewDecoder(connection).Decode(&got); decodeErr != nil {
				closeIgnoringError(connection)
				serverDone <- decodeErr
				return
			}
			methods = append(methods, got.Method)
			var result any
			switch got.Method {
			case "session.snapshot":
				result = map[string]any{
					"type": "session_snapshot",
					"snapshot": map[string]any{
						"focused_tab_id": "w1:t2",
						"tabs": []any{
							map[string]any{"tab_id": "w1:t1", "workspace_id": "w1"},
							map[string]any{"tab_id": "w1:t2", "workspace_id": "w1"},
							map[string]any{"tab_id": "w1:t3", "workspace_id": "w1"},
						},
						"panes": []any{
							map[string]any{"pane_id": "w1:p1", "terminal_id": "term-1", "tab_id": "w1:t1", "cwd": "/other", "foreground_cwd": "/other"},
							map[string]any{"pane_id": "w1:p2", "terminal_id": "term-2", "tab_id": "w1:t2", "cwd": "/repo", "foreground_cwd": "/repo"},
							map[string]any{"pane_id": "w1:p3", "terminal_id": "term-3", "tab_id": "w1:t3", "cwd": "/repo", "foreground_cwd": "/repo"},
						},
						"layouts": []any{
							map[string]any{"tab_id": "w1:t1", "focused_pane_id": "w1:p1"},
							map[string]any{"tab_id": "w1:t2", "focused_pane_id": "w1:p2"},
							map[string]any{"tab_id": "w1:t3", "focused_pane_id": "w1:p3"},
						},
					},
				}
			case "pane.process_info":
				paneID := got.Params.(map[string]any)["pane_id"].(string)
				processes := []any{}
				if paneID != "w1:p2" {
					processes = []any{map[string]any{
						"pid": 20, "name": "nvim", "argv": []string{"nvim"},
						"cwd": map[string]string{"w1:p1": "/other", "w1:p3": "/repo"}[paneID],
					}}
				}
				result = map[string]any{
					"type":         "pane_process_info",
					"process_info": map[string]any{"shell_pid": 10, "foreground_processes": processes},
				}
			case "tab.focus":
				focusedTab = got.Params.(map[string]any)["tab_id"].(string)
				result = map[string]any{"type": "tab_info"}
			default:
				closeIgnoringError(connection)
				serverDone <- &apiError{Code: "unexpected_method", Message: got.Method}
				return
			}
			encodeErr := json.NewEncoder(connection).Encode(map[string]any{"id": got.ID, "result": result})
			closeIgnoringError(connection)
			if encodeErr != nil {
				serverDone <- encodeErr
				return
			}
		}
		serverDone <- nil
	}()

	if err := runFocus(socketPath, "editor"); err != nil {
		t.Fatal(err)
	}
	if err := <-serverDone; err != nil {
		t.Fatal(err)
	}
	wantMethods := []string{"session.snapshot", "pane.process_info", "pane.process_info", "pane.process_info", "tab.focus"}
	if !reflect.DeepEqual(methods, wantMethods) || focusedTab != "w1:t3" {
		t.Fatalf("methods = %#v, focused tab = %q; want %#v and w1:t3", methods, focusedTab, wantMethods)
	}
}

func TestComputeLabels(t *testing.T) {
	home := "/home/raptor"
	tests := []struct {
		name   string
		states []*tabState
		want   []string
	}{
		{
			name: "idle cwd",
			states: []*tabState{
				{WorkspaceID: "w1", Cwd: "/home/raptor/Dev/insights"},
			},
			want: []string{"insights"},
		},
		{
			name: "idle duplicates",
			states: []*tabState{
				{WorkspaceID: "w1", Cwd: "/home/raptor/Dev/insights"},
				{WorkspaceID: "w1", Cwd: "/home/raptor/Dev/insights"},
			},
			want: []string{"insights (1)", "insights (2)"},
		},
		{
			name: "shortest differentiating cwd suffix",
			states: []*tabState{
				{WorkspaceID: "w1", Cwd: "/home/raptor/Dev/insights"},
				{WorkspaceID: "w1", Cwd: "/home/raptor/Dev/clones/insights"},
			},
			want: []string{"insights", "clones/insights"},
		},
		{
			name: "active singleton",
			states: []*tabState{
				{WorkspaceID: "w1", Active: true, Command: "pi", Cwd: "/home/raptor/Dev/insights"},
			},
			want: []string{"pi"},
		},
		{
			name: "same command and cwd",
			states: []*tabState{
				{WorkspaceID: "w1", Active: true, Command: "pi", Cwd: "/home/raptor/Dev/insights"},
				{WorkspaceID: "w1", Active: true, Command: "pi", Cwd: "/home/raptor/Dev/insights"},
			},
			want: []string{"pi (1)", "pi (2)"},
		},
		{
			name: "same command in different cwd",
			states: []*tabState{
				{WorkspaceID: "w1", Active: true, Command: "pi", Cwd: "/home/raptor/Dev/insights"},
				{WorkspaceID: "w1", Active: true, Command: "pi", Cwd: "/home/raptor/Dev/clones/insights"},
			},
			want: []string{"pi [insights]", "pi [clones/insights]"},
		},
		{
			name: "path and index",
			states: []*tabState{
				{WorkspaceID: "w1", Active: true, Command: "pi", Cwd: "/home/raptor/Dev/insights"},
				{WorkspaceID: "w1", Active: true, Command: "pi", Cwd: "/home/raptor/Dev/insights"},
				{WorkspaceID: "w1", Active: true, Command: "pi", Cwd: "/home/raptor/Dev/clones/insights"},
			},
			want: []string{"pi [insights] (1)", "pi [insights] (2)", "pi [clones/insights]"},
		},
		{
			name: "home and root",
			states: []*tabState{
				{WorkspaceID: "w1", Cwd: "/home/raptor"},
				{WorkspaceID: "w1", Cwd: "/"},
			},
			want: []string{"~", "/"},
		},
		{
			name: "workspace scope",
			states: []*tabState{
				{WorkspaceID: "w1", Active: true, Command: "nvim", Cwd: "/one"},
				{WorkspaceID: "w2", Active: true, Command: "nvim", Cwd: "/two"},
			},
			want: []string{"nvim", "nvim"},
		},
		{
			name: "unknown cwd",
			states: []*tabState{
				{WorkspaceID: "w1"},
			},
			want: []string{"shell"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			computeLabels(test.states, home)
			got := make([]string, len(test.states))
			for index, state := range test.states {
				got[index] = state.DesiredLabel
			}
			if !reflect.DeepEqual(got, test.want) {
				t.Fatalf("labels = %#v, want %#v", got, test.want)
			}
		})
	}
}

func TestActiveCLIStoresCandidatesInSessionFile(t *testing.T) {
	runtimeDirectory := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", runtimeDirectory)
	t.Setenv("HERDR_PANE_ID", "w1:p1")
	socketPath := filepath.Join(t.TempDir(), "herdr.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	defer closeIgnoringError(listener)

	var methods []string
	serverDone := make(chan error, 1)
	go func() {
		for range 4 {
			connection, acceptErr := listener.Accept()
			if acceptErr != nil {
				serverDone <- acceptErr
				return
			}
			var got request
			if decodeErr := json.NewDecoder(connection).Decode(&got); decodeErr != nil {
				connection.Close()
				serverDone <- decodeErr
				return
			}
			methods = append(methods, got.Method)
			var result any
			switch got.Method {
			case "pane.get":
				result = map[string]any{
					"type": "pane_info",
					"pane": map[string]any{"pane_id": "w1:p1", "terminal_id": "terminal-1", "tab_id": "w1:t1"},
				}
			case "session.snapshot":
				result = map[string]any{
					"type": "session_snapshot",
					"snapshot": map[string]any{
						"tabs": []any{map[string]any{"tab_id": "w1:t1", "workspace_id": "w1", "label": "1"}},
						"panes": []any{map[string]any{
							"pane_id": "w1:p1", "terminal_id": "terminal-1", "tab_id": "w1:t1", "focused": true,
							"cwd": "/repo", "foreground_cwd": "/repo",
						}},
						"layouts": []any{map[string]any{"tab_id": "w1:t1", "focused_pane_id": "w1:p1"}},
					},
				}
			case "pane.process_info":
				result = map[string]any{
					"type": "pane_process_info",
					"process_info": map[string]any{
						"shell_pid": 10,
						"foreground_processes": []any{map[string]any{
							"pid": 20, "name": "node", "argv": []string{"node", "/opaque/cli.js"}, "cwd": "/repo",
						}},
					},
				}
			case "tab.rename":
				result = map[string]any{"type": "tab_info"}
			default:
				connection.Close()
				serverDone <- &apiError{Code: "unexpected_method", Message: got.Method}
				return
			}
			encodeErr := json.NewEncoder(connection).Encode(map[string]any{"id": got.ID, "result": result})
			connection.Close()
			if encodeErr != nil {
				serverDone <- encodeErr
				return
			}
		}
		serverDone <- nil
	}()

	if err := runActive(socketPath, "fish-1", "2", bytes.NewBufferString("pi\x00README.md\x00")); err != nil {
		t.Fatal(err)
	}
	if err := <-serverDone; err != nil {
		t.Fatal(err)
	}
	wantMethods := []string{"pane.get", "session.snapshot", "pane.process_info", "tab.rename"}
	if !reflect.DeepEqual(methods, wantMethods) {
		t.Fatalf("methods = %#v, want %#v", methods, wantMethods)
	}
	store, err := stateStoreFor(socketPath)
	if err != nil {
		t.Fatal(err)
	}
	state, err := readSessionState(store.dataPath)
	if err != nil {
		t.Fatal(err)
	}
	wantLifecycle := shellLifecycle{
		Owner: "fish-1", Generation: 2, Active: true, Commands: []string{"pi"},
	}
	if got := state["terminal-1"]; !reflect.DeepEqual(got, wantLifecycle) {
		t.Fatalf("lifecycle = %#v, want %#v", got, wantLifecycle)
	}
}

func TestIdleUsesShellCwdWhenHerdrCwdLags(t *testing.T) {
	runtimeDirectory := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", runtimeDirectory)
	t.Setenv("HERDR_PANE_ID", "w1:p1")
	newCwd := filepath.Join(t.TempDir(), "new-project")
	if err := os.Mkdir(newCwd, 0o700); err != nil {
		t.Fatal(err)
	}
	t.Chdir(newCwd)

	socketPath := filepath.Join(t.TempDir(), "herdr.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	var methods []string
	var renameLabel string
	serverDone := make(chan error, 1)
	go func() {
		for {
			connection, acceptErr := listener.Accept()
			if acceptErr != nil {
				serverDone <- nil
				return
			}
			var got request
			if decodeErr := json.NewDecoder(connection).Decode(&got); decodeErr != nil {
				closeIgnoringError(connection)
				serverDone <- decodeErr
				return
			}
			methods = append(methods, got.Method)
			var result any
			switch got.Method {
			case "pane.get":
				result = map[string]any{
					"type": "pane_info",
					"pane": map[string]any{"pane_id": "w1:p1", "terminal_id": "terminal-1", "tab_id": "w1:t1"},
				}
			case "session.snapshot":
				result = map[string]any{
					"type": "session_snapshot",
					"snapshot": map[string]any{
						"tabs": []any{map[string]any{
							"tab_id": "w1:t1", "workspace_id": "w1", "label": "old-project",
						}},
						"panes": []any{map[string]any{
							"pane_id": "w1:p1", "terminal_id": "terminal-1", "tab_id": "w1:t1", "focused": true,
							"cwd": "/tmp/old-project", "foreground_cwd": "/tmp/old-project",
						}},
						"layouts": []any{map[string]any{"tab_id": "w1:t1", "focused_pane_id": "w1:p1"}},
					},
				}
			case "tab.rename":
				renameLabel = got.Params.(map[string]any)["label"].(string)
				result = map[string]any{"type": "tab_info"}
			default:
				closeIgnoringError(connection)
				serverDone <- &apiError{Code: "unexpected_method", Message: got.Method}
				return
			}
			encodeErr := json.NewEncoder(connection).Encode(map[string]any{"id": got.ID, "result": result})
			closeIgnoringError(connection)
			if encodeErr != nil {
				serverDone <- encodeErr
				return
			}
		}
	}()

	runErr := runIdle(socketPath, "fish-1", "2")
	closeIgnoringError(listener)
	if err := <-serverDone; err != nil {
		t.Fatal(err)
	}
	if runErr != nil {
		t.Fatal(runErr)
	}
	wantMethods := []string{"pane.get", "session.snapshot", "tab.rename"}
	if !reflect.DeepEqual(methods, wantMethods) || renameLabel != "new-project" {
		t.Fatalf("methods = %#v, label = %q; want %#v and new-project", methods, renameLabel, wantMethods)
	}
}

func TestIdleFromClosedPaneStillRefreshesRemainingTabs(t *testing.T) {
	runtimeDirectory := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", runtimeDirectory)
	t.Setenv("HERDR_PANE_ID", "w1:closed")
	socketPath := filepath.Join(t.TempDir(), "herdr.sock")
	store, err := stateStoreFor(socketPath)
	if err != nil {
		t.Fatal(err)
	}
	state := sessionState{
		"terminal-1": {Owner: "fish-1", Generation: 1, Active: true, Commands: []string{"pi"}},
		"terminal-2": {Owner: "fish-2", Generation: 1, Active: true, Commands: []string{"pi"}},
	}
	if err := writeSessionState(store.dataPath, state); err != nil {
		t.Fatal(err)
	}

	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	defer closeIgnoringError(listener)
	var methods []string
	serverDone := make(chan error, 1)
	go func() {
		for range 4 {
			connection, acceptErr := listener.Accept()
			if acceptErr != nil {
				serverDone <- acceptErr
				return
			}
			var got request
			if decodeErr := json.NewDecoder(connection).Decode(&got); decodeErr != nil {
				closeIgnoringError(connection)
				serverDone <- decodeErr
				return
			}
			methods = append(methods, got.Method)
			var result any
			var apiFailure *apiError
			switch got.Method {
			case "pane.get":
				apiFailure = &apiError{Code: "pane_not_found", Message: "pane not found"}
			case "session.snapshot":
				result = map[string]any{
					"type": "session_snapshot",
					"snapshot": map[string]any{
						"tabs": []any{map[string]any{
							"tab_id": "w1:t1", "workspace_id": "w1", "label": "pi (1)",
						}},
						"panes": []any{map[string]any{
							"pane_id": "w1:p1", "terminal_id": "terminal-1", "tab_id": "w1:t1", "focused": true,
							"cwd": "/repo", "foreground_cwd": "/repo",
						}},
						"layouts": []any{map[string]any{"tab_id": "w1:t1", "focused_pane_id": "w1:p1"}},
					},
				}
			case "pane.process_info":
				result = map[string]any{
					"type": "pane_process_info",
					"process_info": map[string]any{
						"shell_pid": 10,
						"foreground_processes": []any{map[string]any{
							"pid": 20, "name": "node", "argv": []string{"node", "/opaque/cli.js"}, "cwd": "/repo",
						}},
					},
				}
			case "tab.rename":
				result = map[string]any{"type": "tab_info"}
			default:
				apiFailure = &apiError{Code: "unexpected_method", Message: got.Method}
			}
			response := map[string]any{"id": got.ID, "result": result}
			if apiFailure != nil {
				response = map[string]any{"id": got.ID, "error": apiFailure}
			}
			encodeErr := json.NewEncoder(connection).Encode(response)
			closeIgnoringError(connection)
			if encodeErr != nil {
				serverDone <- encodeErr
				return
			}
		}
		serverDone <- nil
	}()

	if err := runIdle(socketPath, "fish-2", "2"); err != nil {
		t.Fatalf("idle from closed pane did not refresh remaining tabs: %v", err)
	}
	if err := <-serverDone; err != nil {
		t.Fatal(err)
	}
	wantMethods := []string{"pane.get", "session.snapshot", "pane.process_info", "tab.rename"}
	if !reflect.DeepEqual(methods, wantMethods) {
		t.Fatalf("methods = %#v, want %#v", methods, wantMethods)
	}
	state, err = readSessionState(store.dataPath)
	if err != nil {
		t.Fatal(err)
	}
	if len(state) != 1 || !state["terminal-1"].Active {
		t.Fatalf("state = %#v, want only active terminal-1", state)
	}
}

func TestRefreshUsesHerdrSocketAPI(t *testing.T) {
	socketPath := filepath.Join(t.TempDir(), "herdr.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	defer closeIgnoringError(listener)

	var requests []request
	serverDone := make(chan error, 1)
	go func() {
		for range 3 {
			connection, err := listener.Accept()
			if err != nil {
				serverDone <- err
				return
			}

			var request request
			if err := json.NewDecoder(connection).Decode(&request); err != nil {
				connection.Close()
				serverDone <- err
				return
			}
			requests = append(requests, request)

			var result any
			switch request.Method {
			case "session.snapshot":
				result = map[string]any{
					"type": "session_snapshot",
					"snapshot": map[string]any{
						"tabs": []any{map[string]any{
							"tab_id": "w1:t1", "workspace_id": "w1", "label": "1",
						}},
						"panes": []any{map[string]any{
							"pane_id": "w1:p1", "terminal_id": "terminal-1", "tab_id": "w1:t1", "focused": true,
							"cwd": "/repo", "foreground_cwd": "/repo",
						}},
						"layouts": []any{map[string]any{
							"tab_id": "w1:t1", "focused_pane_id": "w1:p1",
						}},
					},
				}
			case "pane.process_info":
				result = map[string]any{
					"type": "pane_process_info",
					"process_info": map[string]any{
						"shell_pid": 10,
						"foreground_processes": []any{map[string]any{
							"pid": 20, "name": "node", "argv": []string{"node", "/nix/store/hash/pi/cli.js"}, "cwd": "/repo",
						}},
					},
				}
			case "tab.rename":
				result = map[string]any{"type": "tab_info"}
			default:
				connection.Close()
				serverDone <- &apiError{Code: "unexpected_method", Message: request.Method}
				return
			}

			err = json.NewEncoder(connection).Encode(map[string]any{"id": request.ID, "result": result})
			connection.Close()
			if err != nil {
				serverDone <- err
				return
			}
		}
		serverDone <- nil
	}()

	state := sessionState{"terminal-1": {
		Owner: "fish-1", Generation: 2, Active: true, Commands: []string{"pi"},
	}}
	if _, err := refreshForState(socketPath, state, nil); err != nil {
		t.Fatal(err)
	}
	if err := <-serverDone; err != nil {
		t.Fatal(err)
	}

	methods := make([]string, len(requests))
	for index, request := range requests {
		methods[index] = request.Method
	}
	wantMethods := []string{"session.snapshot", "pane.process_info", "tab.rename"}
	if !reflect.DeepEqual(methods, wantMethods) {
		t.Fatalf("methods = %#v, want %#v", methods, wantMethods)
	}

	renameParams, ok := requests[2].Params.(map[string]any)
	if !ok || renameParams["label"] != "pi" {
		t.Fatalf("rename params = %#v, want pi label", requests[2].Params)
	}
}

func TestRefreshUsesCwdWhenFishReportsIdle(t *testing.T) {
	socketPath := filepath.Join(t.TempDir(), "herdr.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	defer closeIgnoringError(listener)

	var methods []string
	serverDone := make(chan error, 1)
	go func() {
		for range 2 {
			connection, acceptErr := listener.Accept()
			if acceptErr != nil {
				serverDone <- acceptErr
				return
			}
			var got request
			if decodeErr := json.NewDecoder(connection).Decode(&got); decodeErr != nil {
				connection.Close()
				serverDone <- decodeErr
				return
			}
			methods = append(methods, got.Method)
			var result any
			switch got.Method {
			case "session.snapshot":
				result = map[string]any{
					"type": "session_snapshot",
					"snapshot": map[string]any{
						"tabs": []any{map[string]any{"tab_id": "w1:t1", "workspace_id": "w1", "label": "1"}},
						"panes": []any{map[string]any{
							"pane_id": "w1:p1", "terminal_id": "terminal-1", "tab_id": "w1:t1", "focused": true,
							"cwd": "/repo", "foreground_cwd": "/repo",
						}},
						"layouts": []any{map[string]any{"tab_id": "w1:t1", "focused_pane_id": "w1:p1"}},
					},
				}
			case "tab.rename":
				result = map[string]any{"type": "tab_info"}
			default:
				connection.Close()
				serverDone <- &apiError{Code: "unexpected_method", Message: got.Method}
				return
			}
			encodeErr := json.NewEncoder(connection).Encode(map[string]any{"id": got.ID, "result": result})
			connection.Close()
			if encodeErr != nil {
				serverDone <- encodeErr
				return
			}
		}
		serverDone <- nil
	}()

	state := sessionState{"terminal-1": {Owner: "fish-1", Generation: 4}}
	if _, err := refreshForState(socketPath, state, nil); err != nil {
		t.Fatal(err)
	}
	if err := <-serverDone; err != nil {
		t.Fatal(err)
	}
	if want := []string{"session.snapshot", "tab.rename"}; !reflect.DeepEqual(methods, want) {
		t.Fatalf("methods = %#v, want %#v; idle refresh must not inspect prompt helpers", methods, want)
	}
}

func TestSessionStateUsesSeparateLockAndAtomicJSONData(t *testing.T) {
	runtimeDirectory := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", runtimeDirectory)
	store, err := stateStoreFor("/run/user/1000/herdr/example.sock")
	if err != nil {
		t.Fatal(err)
	}
	if store.lockPath == store.dataPath || filepath.Ext(store.lockPath) != ".lock" || filepath.Ext(store.dataPath) != ".json" {
		t.Fatalf("state store = %#v, want separate lock and JSON paths", store)
	}

	state := sessionState{"terminal-1": {
		Owner: "100-20-30", Generation: 7, Active: true, Compound: true,
		Commands: []string{"sleep", "nvim"},
	}}
	if err := writeSessionState(store.dataPath, state); err != nil {
		t.Fatal(err)
	}
	got, err := readSessionState(store.dataPath)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, state) {
		t.Fatalf("state = %#v, want %#v", got, state)
	}
	if mode := fileMode(t, store.dataPath); mode != 0o600 {
		t.Fatalf("state mode = %o, want 600", mode)
	}
	data, err := os.ReadFile(store.dataPath)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(data, []byte("\"version\"")) || bytes.Contains(data, []byte("\"panes\"")) {
		t.Fatalf("state file contains unnecessary schema wrappers:\n%s", data)
	}
	if !bytes.Contains(data, []byte("\"commands\": [")) {
		t.Fatalf("state file does not encode commands as a JSON array:\n%s", data)
	}
}

func TestInvalidStateFileIsDiscarded(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	if err := os.WriteFile(path, []byte(`{"version":1,"panes":{}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	state, err := readSessionState(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(state) != 0 {
		t.Fatalf("state = %#v, want discarded state", state)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("invalid state file was not deleted: %v", err)
	}
}

func fileMode(t *testing.T, path string) os.FileMode {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	return info.Mode().Perm()
}

func TestLifecycleUpdateRejectsStaleGeneration(t *testing.T) {
	state := make(sessionState)
	newer := lifecycleUpdate{TerminalID: "terminal-1", Lifecycle: shellLifecycle{
		Owner: "fish-1", Generation: 4,
	}}
	if !applyLifecycleUpdate(state, newer) {
		t.Fatal("initial lifecycle update was rejected")
	}
	stale := lifecycleUpdate{TerminalID: "terminal-1", Lifecycle: shellLifecycle{
		Owner: "fish-1", Generation: 3, Active: true, Commands: []string{"pi"},
	}}
	if applyLifecycleUpdate(state, stale) {
		t.Fatal("stale lifecycle update was accepted")
	}
	if got := state["terminal-1"]; got.Generation != 4 || got.Active {
		t.Fatalf("lifecycle = %#v, want idle generation 4", got)
	}
}

func (err *apiError) Error() string {
	return err.Code + ": " + err.Message
}

func TestForegroundProcessIgnoresShell(t *testing.T) {
	shellPID := uint32(10)
	info := processInfo{
		ShellPID: &shellPID,
		ForegroundProcesses: []process{
			{PID: shellPID, Name: "fish", Argv: []string{"fish"}},
			{PID: 20, Name: "nvim", Argv: []string{"/run/current-system/sw/bin/nvim"}},
		},
	}

	got := foregroundProcesses(info)
	if len(got) != 1 || normalizeProcessCommand(got[0]) != "nvim" {
		t.Fatalf("foreground processes = %#v, want nvim", got)
	}
}

func TestForegroundProcessIgnoresConfiguredInfrastructure(t *testing.T) {
	info := processInfo{ForegroundProcesses: []process{
		{PID: 10, Name: "herdr-context"},
		{PID: 20, Name: "oh-my-posh", Argv: []string{"oh-my-posh", "print"}},
		{PID: 30, Name: "node", Argv: []string{"node", "cli.js"}},
	}}

	got := foregroundProcesses(info)
	if len(got) != 1 || got[0].PID != 30 {
		t.Fatalf("foreground processes = %#v, want node PID 30", got)
	}
}

func TestParseCommandTokens(t *testing.T) {
	tests := []struct {
		name       string
		tokens     []string
		compound   bool
		candidates []string
	}{
		{name: "simple", tokens: []string{"nvim", "README.md"}, candidates: []string{"nvim"}},
		{name: "assignment and decorator", tokens: []string{"EDITOR=nvim", "command", "/bin/nvim", "README.md"}, candidates: []string{"nvim"}},
		{name: "sequence", tokens: []string{"sleep", "2", ";", "and", "nvim", "README.md"}, compound: true, candidates: []string{"sleep", "nvim"}},
		{name: "pipeline", tokens: []string{"rg", "needle", "|", "less"}, compound: true, candidates: []string{"rg", "less"}},
		{name: "conditional", tokens: []string{"if", "test", "-e", "README.md", ";", "nvim", ";", "end"}, compound: true, candidates: []string{"test", "nvim"}},
		{name: "leading redirection", tokens: []string{">", "/tmp/log", "nvim"}, candidates: []string{"nvim"}},
		{name: "leading fd redirection", tokens: []string{"2>", "/tmp/log", "nvim"}, candidates: []string{"nvim"}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got := parseCommandTokens(test.tokens)
			if got.Compound != test.compound || !reflect.DeepEqual(got.Commands, test.candidates) {
				t.Fatalf("parsed command = %#v, want compound=%v commands=%#v", got, test.compound, test.candidates)
			}
		})
	}
}

func TestCompoundCandidateMatchesCurrentProcess(t *testing.T) {
	candidates := []string{"sleep", "nvim"}
	processes := []process{{
		PID: 20, Name: "node", Argv: []string{"node", "/nix/store/hash/nvim/cli.js"},
	}}
	if got := matchProcessCandidate(candidates, processes); got != "nvim" {
		t.Fatalf("matched candidate = %q, want nvim", got)
	}
}

func TestCompoundCandidateFallsBackToArgvZero(t *testing.T) {
	processes := []process{{PID: 20, Name: "node", Argv: []string{"node", "/opaque/cli.js"}}}
	matched := matchProcessCandidate([]string{"sleep", "pi"}, processes)
	if matched != "" {
		t.Fatalf("matched candidate = %q, want no match", matched)
	}
	if fallback := normalizeProcessCommand(processes[0]); fallback != "node" {
		t.Fatalf("fallback = %q, want node", fallback)
	}
}

func TestLifecycleGenerationControlsWatcher(t *testing.T) {
	state := sessionState{"terminal-1": {Owner: "fish-1", Generation: 12, Active: true}}
	target := lifecycleUpdate{TerminalID: "terminal-1", Lifecycle: state["terminal-1"]}
	if !targetIsCurrent(state, target) {
		t.Fatal("current generation did not keep watcher active")
	}
	target.Lifecycle.Generation = 11
	if targetIsCurrent(state, target) {
		t.Fatal("stale generation kept watcher active")
	}
	state["terminal-1"] = shellLifecycle{Owner: "fish-1", Generation: 13}
	target.Lifecycle.Generation = 12
	if targetIsCurrent(state, target) {
		t.Fatal("idle lifecycle kept watcher active")
	}
}
