package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	debounceDelay         = 100 * time.Millisecond
	compoundPollDelay     = 500 * time.Millisecond
	requestTimeout        = 2 * time.Second
	commandCandidateLimit = 64
	maximumStateFileSize  = 1024 * 1024
)

var (
	ignoredCommands   = []string{"herdr-context", "oh-my-posh"}
	commandSeparators = map[string]bool{
		";": true, "&": true, "&&": true, "||": true, "|": true, "|&": true, "\n": true,
	}
	controlKeywords = map[string]bool{
		"and": true, "or": true, "if": true, "else": true, "while": true, "for": true,
		"switch": true, "case": true, "function": true, "begin": true, "end": true,
	}
	skipUntilSeparatorKeywords = map[string]bool{
		"for": true, "switch": true, "function": true, "case": true,
	}
	commandDecorators = map[string]bool{
		"command": true, "builtin": true, "exec": true, "not": true, "time": true,
	}
)

type request struct {
	ID     string `json:"id"`
	Method string `json:"method"`
	Params any    `json:"params"`
}

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type response struct {
	ID     string          `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  *apiError       `json:"error"`
}

type snapshotResult struct {
	Type     string   `json:"type"`
	Snapshot snapshot `json:"snapshot"`
}

type snapshot struct {
	FocusedWorkspaceID string       `json:"focused_workspace_id"`
	FocusedTabID       string       `json:"focused_tab_id"`
	FocusedPaneID      string       `json:"focused_pane_id"`
	Tabs               []tabInfo    `json:"tabs"`
	Panes              []paneInfo   `json:"panes"`
	Layouts            []paneLayout `json:"layouts"`
}

type tabInfo struct {
	ID          string `json:"tab_id"`
	WorkspaceID string `json:"workspace_id"`
	Label       string `json:"label"`
}

type paneInfo struct {
	ID            string `json:"pane_id"`
	TerminalID    string `json:"terminal_id"`
	TabID         string `json:"tab_id"`
	Focused       bool   `json:"focused"`
	Cwd           string `json:"cwd"`
	ForegroundCwd string `json:"foreground_cwd"`
	Agent         string `json:"agent"`
}

type paneLayout struct {
	TabID         string `json:"tab_id"`
	FocusedPaneID string `json:"focused_pane_id"`
}

type processResult struct {
	Type        string      `json:"type"`
	ProcessInfo processInfo `json:"process_info"`
}

type paneResult struct {
	Type string   `json:"type"`
	Pane paneInfo `json:"pane"`
}

type tabCreatedResult struct {
	Type     string   `json:"type"`
	Tab      tabInfo  `json:"tab"`
	RootPane paneInfo `json:"root_pane"`
}

type processInfo struct {
	ShellPID            *uint32   `json:"shell_pid"`
	ForegroundProcesses []process `json:"foreground_processes"`
}

type process struct {
	PID   uint32   `json:"pid"`
	Name  string   `json:"name"`
	Argv0 string   `json:"argv0"`
	Argv  []string `json:"argv"`
	Cwd   string   `json:"cwd"`
}

type tabRole string

const (
	roleShell  tabRole = "shell"
	roleEditor tabRole = "editor"
	roleAgent  tabRole = "agent"
)

type tabState struct {
	ID             string
	WorkspaceID    string
	CurrentLabel   string
	Command        string
	ProcessCommand string
	Agent          string
	Cwd            string
	Role           tabRole
	Active         bool
	DesiredLabel   string
}

type shellLifecycle struct {
	Owner      string   `json:"owner"`
	Generation uint64   `json:"generation"`
	Active     bool     `json:"active,omitempty"`
	Compound   bool     `json:"compound,omitempty"`
	Commands   []string `json:"commands,omitempty"`
	Cwd        string   `json:"cwd,omitempty"`
}

type sessionState map[string]shellLifecycle

type stateStore struct {
	lockPath string
	dataPath string
}

type lifecycleUpdate struct {
	TerminalID string
	Lifecycle  shellLifecycle
}

type parsedCommand struct {
	Compound bool
	Commands []string
}

type refreshResult struct {
	watcherCurrent bool
	stateChanged   bool
}

func main() {
	if len(os.Args) < 2 {
		printUsageAndExit()
	}

	socketPath := os.Getenv("HERDR_SOCKET_PATH")
	if socketPath == "" {
		fmt.Fprintln(os.Stderr, "HERDR_SOCKET_PATH is not set")
		os.Exit(1)
	}

	var err error
	switch os.Args[1] {
	case "refresh":
		if len(os.Args) != 2 {
			printUsageAndExit()
		}
		time.Sleep(debounceDelay)
		_, err = refreshLocked(socketPath, nil)
	case "active":
		if len(os.Args) != 4 {
			printUsageAndExit()
		}
		err = runActive(socketPath, os.Args[2], os.Args[3], os.Stdin)
	case "idle":
		if len(os.Args) != 4 {
			printUsageAndExit()
		}
		err = runIdle(socketPath, os.Args[2], os.Args[3])
	case "focus":
		if len(os.Args) != 3 {
			printUsageAndExit()
		}
		err = runFocus(socketPath, os.Args[2])
	default:
		printUsageAndExit()
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "update Herdr context: %v\n", err)
		os.Exit(1)
	}
}

func printUsageAndExit() {
	fmt.Fprintln(os.Stderr, "usage: herdr-context refresh | active OWNER GENERATION | idle OWNER GENERATION | focus editor|agent")
	os.Exit(2)
}

func runActive(socketPath, owner, generationText string, input io.Reader) error {
	generation, err := parseGeneration(generationText)
	if err != nil {
		return err
	}
	tokens, err := readNullTokens(input)
	if err != nil {
		return err
	}
	parsed := parseCommandTokens(tokens)
	lifecycle := shellLifecycle{
		Owner: owner, Generation: generation, Active: true,
		Compound: parsed.Compound, Commands: parsed.Commands,
	}
	time.Sleep(debounceDelay)
	terminalID, err := resolveCurrentTerminalID(socketPath)
	if err != nil {
		return err
	}
	update := &lifecycleUpdate{TerminalID: terminalID, Lifecycle: lifecycle}
	target := update
	for {
		current, err := updateAndRefreshLocked(socketPath, update, target)
		if err != nil || !current || !parsed.Compound {
			return err
		}
		update = nil
		time.Sleep(compoundPollDelay)
	}
}

func runIdle(socketPath, owner, generationText string) error {
	generation, err := parseGeneration(generationText)
	if err != nil {
		return err
	}
	cwd, _ := os.Getwd()
	lifecycle := shellLifecycle{Owner: owner, Generation: generation, Cwd: normalizePath(cwd)}
	terminalID, resolveErr := resolveCurrentTerminalID(socketPath)
	if resolveErr == nil {
		if err := updateLifecycleLocked(socketPath, lifecycleUpdate{
			TerminalID: terminalID, Lifecycle: lifecycle,
		}); err != nil {
			return err
		}
	}
	time.Sleep(debounceDelay)
	_, refreshErr := refreshLocked(socketPath, nil)
	if refreshErr != nil {
		return errors.Join(resolveErr, refreshErr)
	}
	return nil
}

func runFocus(socketPath, mode string) error {
	return editSessionState(socketPath, func(state sessionState) (bool, error) {
		current, err := sessionSnapshot(socketPath)
		if err != nil {
			return false, err
		}
		stateChanged := pruneSessionState(state, current)
		tabs, err := inspectTabs(socketPath, current, state, true)
		if err != nil {
			return stateChanged, err
		}

		currentTabID := firstNonEmpty(os.Getenv("HERDR_ACTIVE_TAB_ID"), os.Getenv("HERDR_TAB_ID"), current.FocusedTabID)
		currentIndex := slices.IndexFunc(tabs, func(tab *tabState) bool { return tab.ID == currentTabID })
		if currentIndex < 0 {
			return stateChanged, fmt.Errorf("current tab %q is not in the session snapshot", currentTabID)
		}
		targetRole, err := focusTargetRole(mode, tabs[currentIndex].Role)
		if err != nil {
			return stateChanged, err
		}
		if target := closestTab(tabs, currentIndex, targetRole); target != nil {
			err := call(socketPath, "tab.focus", map[string]any{"tab_id": target.ID}, nil)
			return stateChanged, err
		}
		return stateChanged, createTargetTab(socketPath, tabs[currentIndex], targetRole)
	})
}

func focusTargetRole(mode string, current tabRole) (tabRole, error) {
	switch mode {
	case "editor":
		if current == roleEditor {
			return roleShell, nil
		}
		return roleEditor, nil
	case "agent":
		if current == roleAgent {
			return roleShell, nil
		}
		return roleAgent, nil
	default:
		return "", fmt.Errorf("unknown focus target %q", mode)
	}
}

func closestTab(tabs []*tabState, currentIndex int, targetRole tabRole) *tabState {
	if currentIndex < 0 || currentIndex >= len(tabs) {
		return nil
	}
	current := tabs[currentIndex]
	bestIndex := -1
	bestDistance := 0
	for index, candidate := range tabs {
		if index == currentIndex || candidate.Role != targetRole ||
			current.Cwd == "" || candidate.Cwd != current.Cwd {
			continue
		}
		distance := abs(index - currentIndex)
		if bestIndex < 0 || distance < bestDistance ||
			(distance == bestDistance && index > currentIndex && bestIndex < currentIndex) {
			bestIndex = index
			bestDistance = distance
		}
	}
	if bestIndex < 0 {
		return nil
	}
	return tabs[bestIndex]
}

func createTargetTab(socketPath string, current *tabState, targetRole tabRole) error {
	params := map[string]any{"focus": true}
	if current.WorkspaceID != "" {
		params["workspace_id"] = current.WorkspaceID
	}
	if current.Cwd != "" {
		params["cwd"] = current.Cwd
	}
	var created tabCreatedResult
	if err := call(socketPath, "tab.create", params, &created); err != nil {
		return err
	}
	if created.Type != "tab_created" {
		return fmt.Errorf("unexpected tab.create response type %q", created.Type)
	}
	command := map[tabRole]string{roleEditor: "nvim", roleAgent: "pi"}[targetRole]
	if command == "" {
		return nil
	}
	if created.RootPane.ID == "" {
		return errors.New("tab.create returned no root pane")
	}
	return call(socketPath, "pane.send_input", map[string]any{
		"pane_id": created.RootPane.ID,
		"text":    command,
		"keys":    []string{"enter"},
	}, nil)
}

func abs(value int) int {
	if value < 0 {
		return -value
	}
	return value
}

func resolveCurrentTerminalID(socketPath string) (string, error) {
	paneID := os.Getenv("HERDR_PANE_ID")
	if paneID == "" {
		return "", errors.New("HERDR_PANE_ID is not set")
	}
	var paneResponse paneResult
	if err := call(socketPath, "pane.get", map[string]any{"pane_id": paneID}, &paneResponse); err != nil {
		return "", err
	}
	if paneResponse.Type != "pane_info" {
		return "", fmt.Errorf("unexpected pane.get response type %q", paneResponse.Type)
	}
	terminalID := paneStateKey(paneResponse.Pane)
	if terminalID == "" {
		return "", errors.New("pane.get returned no terminal identity")
	}
	return terminalID, nil
}

func parseGeneration(value string) (uint64, error) {
	generation, err := strconv.ParseUint(value, 10, 64)
	if err != nil || generation == 0 {
		return 0, fmt.Errorf("invalid generation %q", value)
	}
	return generation, nil
}

func readNullTokens(input io.Reader) ([]string, error) {
	const maximumInput = 1024 * 1024
	data, err := io.ReadAll(io.LimitReader(input, maximumInput+1))
	if err != nil {
		return nil, fmt.Errorf("read Fish tokens: %w", err)
	}
	if len(data) > maximumInput {
		return nil, errors.New("fish token input exceeds 1 MiB")
	}
	parts := bytes.Split(data, []byte{0})
	tokens := make([]string, 0, len(parts))
	for _, part := range parts {
		if len(part) != 0 {
			tokens = append(tokens, string(part))
		}
	}
	return tokens, nil
}

func stateStoreFor(socketPath string) (stateStore, error) {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	directoryName := "herdr-context"
	if runtimeDir == "" {
		runtimeDir = os.TempDir()
		directoryName = fmt.Sprintf("herdr-context-%d", os.Getuid())
	}
	directory := filepath.Join(runtimeDir, directoryName)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return stateStore{}, fmt.Errorf("create state directory: %w", err)
	}
	if err := os.Chmod(directory, 0o700); err != nil {
		return stateStore{}, fmt.Errorf("secure state directory: %w", err)
	}

	digest := sha256.Sum256([]byte(socketPath))
	key := fmt.Sprintf("%x", digest[:8])
	return stateStore{
		lockPath: filepath.Join(directory, key+".lock"),
		dataPath: filepath.Join(directory, key+".json"),
	}, nil
}

func editSessionState(socketPath string, edit func(sessionState) (bool, error)) error {
	store, err := stateStoreFor(socketPath)
	if err != nil {
		return err
	}
	lock, err := os.OpenFile(store.lockPath, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return fmt.Errorf("open state lock: %w", err)
	}
	defer closeIgnoringError(lock)
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		return fmt.Errorf("lock state: %w", err)
	}

	state, err := readSessionState(store.dataPath)
	if err != nil {
		return err
	}
	changed, err := edit(state)
	if err != nil || !changed {
		return err
	}
	return writeSessionState(store.dataPath, state)
}

func readSessionState(path string) (sessionState, error) {
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return make(sessionState), nil
	}
	if err != nil {
		return nil, fmt.Errorf("open state file: %w", err)
	}
	defer closeIgnoringError(file)

	data, err := io.ReadAll(io.LimitReader(file, maximumStateFileSize+1))
	if err != nil {
		return nil, fmt.Errorf("read state file: %w", err)
	}
	state := make(sessionState)
	if len(data) > maximumStateFileSize || json.Unmarshal(data, &state) != nil || state == nil {
		_ = os.Remove(path)
		return make(sessionState), nil
	}
	return state, nil
}

func writeSessionState(path string, state sessionState) error {
	directory := filepath.Dir(path)
	temporary, err := os.CreateTemp(directory, ".state-*.tmp")
	if err != nil {
		return fmt.Errorf("create temporary state file: %w", err)
	}
	temporaryPath := temporary.Name()
	defer func() { _ = os.Remove(temporaryPath) }()
	defer closeIgnoringError(temporary)

	encoder := json.NewEncoder(temporary)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(state); err != nil {
		return fmt.Errorf("encode state file: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		return fmt.Errorf("sync state file: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close state file: %w", err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("replace state file: %w", err)
	}
	directoryHandle, err := os.Open(directory)
	if err != nil {
		return fmt.Errorf("open state directory: %w", err)
	}
	defer closeIgnoringError(directoryHandle)
	if err := directoryHandle.Sync(); err != nil {
		return fmt.Errorf("sync state directory: %w", err)
	}
	return nil
}

func applyLifecycleUpdate(state sessionState, update lifecycleUpdate) bool {
	current, exists := state[update.TerminalID]
	if exists && current.Owner == update.Lifecycle.Owner && current.Generation >= update.Lifecycle.Generation {
		return false
	}
	state[update.TerminalID] = update.Lifecycle
	return true
}

func updateLifecycleLocked(socketPath string, update lifecycleUpdate) error {
	return editSessionState(socketPath, func(state sessionState) (bool, error) {
		return applyLifecycleUpdate(state, update), nil
	})
}

func refreshLocked(socketPath string, target *lifecycleUpdate) (bool, error) {
	return updateAndRefreshLocked(socketPath, nil, target)
}

func updateAndRefreshLocked(socketPath string, update, target *lifecycleUpdate) (bool, error) {
	var current bool
	err := editSessionState(socketPath, func(state sessionState) (bool, error) {
		changed := update != nil && applyLifecycleUpdate(state, *update)
		result, err := refreshForState(socketPath, state, target)
		current = result.watcherCurrent
		return changed || result.stateChanged, err
	})
	return current, err
}

func sessionSnapshot(socketPath string) (snapshot, error) {
	var result snapshotResult
	if err := call(socketPath, "session.snapshot", map[string]any{}, &result); err != nil {
		return snapshot{}, err
	}
	if result.Type != "session_snapshot" {
		return snapshot{}, fmt.Errorf("unexpected session.snapshot response type %q", result.Type)
	}
	return result.Snapshot, nil
}

func refreshForState(socketPath string, state sessionState, target *lifecycleUpdate) (refreshResult, error) {
	current, err := sessionSnapshot(socketPath)
	if err != nil {
		return refreshResult{}, err
	}
	stateChanged := pruneSessionState(state, current)
	result := refreshResult{
		watcherCurrent: target == nil || targetIsCurrent(state, *target),
		stateChanged:   stateChanged,
	}

	states, err := inspectTabs(socketPath, current, state, false)
	if err != nil {
		return result, err
	}
	computeLabels(states, homeDirectory())

	var renameErrors []error
	for _, tab := range states {
		if tab.DesiredLabel == "" || tab.DesiredLabel == tab.CurrentLabel {
			continue
		}
		params := map[string]any{"tab_id": tab.ID, "label": tab.DesiredLabel}
		if err := call(socketPath, "tab.rename", params, nil); err != nil {
			renameErrors = append(renameErrors, err)
		}
	}
	return result, errors.Join(renameErrors...)
}

func targetIsCurrent(state sessionState, target lifecycleUpdate) bool {
	current, ok := state[target.TerminalID]
	return ok && current.Owner == target.Lifecycle.Owner &&
		current.Generation == target.Lifecycle.Generation && current.Active
}

func pruneSessionState(state sessionState, current snapshot) bool {
	present := make(map[string]bool, len(current.Panes))
	for _, pane := range current.Panes {
		if key := paneStateKey(pane); key != "" {
			present[key] = true
		}
	}
	changed := false
	for key := range state {
		if !present[key] {
			delete(state, key)
			changed = true
		}
	}
	return changed
}

func paneStateKey(pane paneInfo) string {
	return firstNonEmpty(pane.TerminalID, pane.ID)
}

func inspectTabs(socketPath string, current snapshot, lifecycleState sessionState, inspectIdleProcesses bool) ([]*tabState, error) {
	panesByID := make(map[string]paneInfo, len(current.Panes))
	panesByTab := make(map[string][]paneInfo)
	for _, pane := range current.Panes {
		panesByID[pane.ID] = pane
		panesByTab[pane.TabID] = append(panesByTab[pane.TabID], pane)
	}

	focusedPaneByTab := make(map[string]string, len(current.Layouts))
	for _, layout := range current.Layouts {
		focusedPaneByTab[layout.TabID] = layout.FocusedPaneID
	}

	states := make([]*tabState, 0, len(current.Tabs))
	for _, tab := range current.Tabs {
		pane, ok := representativePane(tab.ID, focusedPaneByTab, panesByID, panesByTab)
		if !ok {
			return nil, fmt.Errorf("tab %s has no representative pane", tab.ID)
		}

		state := &tabState{
			ID:           tab.ID,
			WorkspaceID:  tab.WorkspaceID,
			CurrentLabel: tab.Label,
			Agent:        normalizeCommand(pane.Agent),
		}
		lifecycle, hasLifecycle := lifecycleState[paneStateKey(pane)]
		lifecycleIdle := hasLifecycle && !lifecycle.Active
		if lifecycleIdle {
			state.Cwd = normalizePath(firstNonEmpty(lifecycle.Cwd, pane.ForegroundCwd, pane.Cwd))
			if !inspectIdleProcesses {
				state.Role = classifyTab(state)
				states = append(states, state)
				continue
			}
		}

		var processResponse processResult
		params := map[string]any{"pane_id": pane.ID}
		if err := call(socketPath, "pane.process_info", params, &processResponse); err != nil {
			return nil, err
		}
		if processResponse.Type != "pane_process_info" {
			return nil, fmt.Errorf("unexpected pane.process_info response type %q", processResponse.Type)
		}

		processes := foregroundProcesses(processResponse.ProcessInfo)
		if len(processes) != 0 {
			state.ProcessCommand = matchProcessCandidate([]string{"pi", "nvim"}, processes)
			if state.ProcessCommand == "" {
				state.ProcessCommand = normalizeProcessCommand(processes[0])
			}
			if !lifecycleIdle {
				state.Cwd = processes[0].Cwd
			}
		}
		state.Cwd = normalizePath(firstNonEmpty(state.Cwd, pane.ForegroundCwd, pane.Cwd))

		if hasLifecycle && lifecycle.Active {
			state.Command = state.Agent
			if state.Command == "" && !lifecycle.Compound && len(lifecycle.Commands) != 0 {
				state.Command = lifecycle.Commands[0]
			}
			if state.Command == "" && lifecycle.Compound {
				state.Command = matchProcessCandidate(lifecycle.Commands, processes)
			}
		} else if len(processes) != 0 {
			state.Command = state.Agent
		}
		if state.Command == "" && len(processes) != 0 {
			state.Command = normalizeProcessCommand(processes[0])
		}
		state.Role = classifyTab(state)
		state.Active = state.Command != ""
		states = append(states, state)
	}
	return states, nil
}

func classifyTab(tab *tabState) tabRole {
	commands := []string{tab.Agent, tab.Command, tab.ProcessCommand}
	if slices.Contains(commands, "pi") {
		return roleAgent
	}
	if slices.Contains(commands, "nvim") {
		return roleEditor
	}
	return roleShell
}

func representativePane(
	tabID string,
	focusedPaneByTab map[string]string,
	panesByID map[string]paneInfo,
	panesByTab map[string][]paneInfo,
) (paneInfo, bool) {
	if paneID := focusedPaneByTab[tabID]; paneID != "" {
		if pane, ok := panesByID[paneID]; ok {
			return pane, true
		}
	}
	for _, pane := range panesByTab[tabID] {
		if pane.Focused {
			return pane, true
		}
	}
	panes := panesByTab[tabID]
	if len(panes) == 0 {
		return paneInfo{}, false
	}
	sort.Slice(panes, func(i, j int) bool { return panes[i].ID < panes[j].ID })
	return panes[0], true
}

func foregroundProcesses(info processInfo) []process {
	processes := append([]process(nil), info.ForegroundProcesses...)
	sort.Slice(processes, func(i, j int) bool { return processes[i].PID < processes[j].PID })
	filtered := processes[:0]
	for _, candidate := range processes {
		if info.ShellPID != nil && candidate.PID == *info.ShellPID {
			continue
		}
		if candidate.PID == uint32(os.Getpid()) || processIsIgnored(candidate) {
			continue
		}
		filtered = append(filtered, candidate)
	}
	return filtered
}

func processIsIgnored(candidate process) bool {
	identities := []string{candidate.Name, candidate.Argv0}
	if len(candidate.Argv) != 0 {
		identities = append(identities, candidate.Argv[0])
	}
	for _, identity := range identities {
		command := normalizeCommand(identity)
		for _, ignored := range ignoredCommands {
			if command == ignored || (len(command) == 15 && strings.HasPrefix(ignored, command)) {
				return true
			}
		}
	}
	return false
}

func matchProcessCandidate(candidates []string, processes []process) string {
	for _, current := range processes {
		for _, candidate := range candidates {
			if processMatchesCommand(current, candidate) {
				return candidate
			}
		}
	}
	return ""
}

func processMatchesCommand(current process, candidate string) bool {
	candidate = normalizeCandidate(candidate)
	if candidate == "" {
		return false
	}
	values := []string{current.Name, current.Argv0}
	values = append(values, current.Argv...)
	for _, value := range values {
		if commandPathMatches(value, candidate) {
			return true
		}
	}
	return false
}

func commandPathMatches(value, candidate string) bool {
	value = strings.TrimSpace(strings.TrimPrefix(value, "-"))
	for part := range strings.SplitSeq(filepath.ToSlash(value), "/") {
		if part == "" {
			continue
		}
		if part == candidate || strings.TrimSuffix(part, filepath.Ext(part)) == candidate {
			return true
		}
	}
	return false
}

func parseCommandTokens(tokens []string) parsedCommand {
	parsed := parsedCommand{}
	expectCommand := true
	skipRedirectionTarget := false
	skipUntilSeparator := false

	for _, token := range tokens {
		if commandSeparators[token] {
			parsed.Compound = true
			expectCommand = true
			skipRedirectionTarget = false
			skipUntilSeparator = false
			continue
		}
		if skipUntilSeparator {
			continue
		}
		if !expectCommand {
			continue
		}
		if skipRedirectionTarget {
			skipRedirectionTarget = false
			continue
		}
		if isRedirectionToken(token) {
			skipRedirectionTarget = redirectionNeedsTarget(token)
			continue
		}
		if controlKeywords[token] {
			parsed.Compound = true
			skipUntilSeparator = skipUntilSeparatorKeywords[token]
			continue
		}
		if commandDecorators[token] || isVariableAssignment(token) {
			continue
		}
		if command := normalizeCandidate(token); command != "" && !slices.Contains(parsed.Commands, command) {
			parsed.Commands = append(parsed.Commands, command)
		}
		expectCommand = false
	}
	if len(parsed.Commands) > commandCandidateLimit {
		parsed.Commands = parsed.Commands[:commandCandidateLimit]
	}
	return parsed
}

func isVariableAssignment(token string) bool {
	separator := strings.IndexByte(token, '=')
	if separator <= 0 {
		return false
	}
	for index, character := range token[:separator] {
		letter := (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z')
		digit := character >= '0' && character <= '9'
		if !letter && character != '_' && (index == 0 || !digit) {
			return false
		}
	}
	return true
}

func isRedirectionToken(token string) bool {
	return strings.ContainsAny(token, "<>")
}

func redirectionNeedsTarget(token string) bool {
	operator := strings.LastIndexAny(token, "<>")
	if operator == -1 {
		return token == "^" || token == "^^"
	}
	suffix := token[operator+1:]
	return suffix == "" || suffix == "|"
}

func normalizeCandidate(command string) string {
	command = normalizeCommand(command)
	if command == "" || strings.ContainsAny(command, "$(){}*?[]") || len([]rune(command)) > 255 {
		return ""
	}
	return command
}

func normalizeProcessCommand(process process) string {
	if len(process.Argv) > 0 {
		if command := normalizeCommand(process.Argv[0]); command != "" {
			return command
		}
	}
	if command := normalizeCommand(process.Argv0); command != "" {
		return command
	}
	return normalizeCommand(process.Name)
}

func normalizeCommand(command string) string {
	command = strings.TrimSpace(command)
	command = strings.TrimPrefix(command, "-")
	if command == "" {
		return ""
	}
	return filepath.Base(command)
}

func normalizePath(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return ""
	}
	return filepath.Clean(path)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func homeDirectory() string {
	if home := normalizePath(os.Getenv("HOME")); home != "" {
		return home
	}
	home, _ := os.UserHomeDir()
	return normalizePath(home)
}

func computeLabels(states []*tabState, home string) {
	byWorkspace := make(map[string][]*tabState)
	var workspaceOrder []string
	for _, state := range states {
		if _, exists := byWorkspace[state.WorkspaceID]; !exists {
			workspaceOrder = append(workspaceOrder, state.WorkspaceID)
		}
		byWorkspace[state.WorkspaceID] = append(byWorkspace[state.WorkspaceID], state)
	}
	for _, workspaceID := range workspaceOrder {
		computeWorkspaceLabels(byWorkspace[workspaceID], home)
	}
}

func computeWorkspaceLabels(states []*tabState, home string) {
	activeGroups := make(map[string][]*tabState)
	var commandOrder []string
	var idle []*tabState

	for _, state := range states {
		state.DesiredLabel = ""
		if !state.Active || state.Command == "" {
			idle = append(idle, state)
			continue
		}
		if _, exists := activeGroups[state.Command]; !exists {
			commandOrder = append(commandOrder, state.Command)
		}
		activeGroups[state.Command] = append(activeGroups[state.Command], state)
	}

	for _, command := range commandOrder {
		assignGroupLabels(activeGroups[command], home, command)
	}
	assignGroupLabels(idle, home, "")
}

func assignGroupLabels(states []*tabState, home, command string) {
	if len(states) == 1 && command != "" {
		states[0].DesiredLabel = command
		return
	}

	countsByPath := countPaths(states)
	pathLabels := assignPathLabels(states, home)
	seenByPath := make(map[string]int)
	for _, state := range states {
		path := pathKey(state.Cwd)
		label := pathLabels[path]
		if command != "" {
			label = command
			if len(countsByPath) > 1 {
				label = fmt.Sprintf("%s [%s]", command, pathLabels[path])
			}
		}
		if countsByPath[path] > 1 {
			seenByPath[path]++
			label = withIndex(label, seenByPath[path])
		}
		state.DesiredLabel = label
	}
}

func countPaths(states []*tabState) map[string]int {
	counts := make(map[string]int)
	for _, state := range states {
		counts[pathKey(state.Cwd)]++
	}
	return counts
}

func pathKey(path string) string {
	if path == "" {
		return "\x00unknown"
	}
	return path
}

func assignPathLabels(states []*tabState, home string) map[string]string {
	labels := make(map[string]string)
	used := make(map[string]bool)
	for _, state := range states {
		path := pathKey(state.Cwd)
		if _, exists := labels[path]; exists {
			continue
		}
		for _, candidate := range pathCandidates(state.Cwd, home) {
			if !used[candidate] {
				labels[path] = candidate
				used[candidate] = true
				break
			}
		}
		if labels[path] == "" {
			candidate := fmt.Sprintf("path-%d", len(labels)+1)
			labels[path] = candidate
			used[candidate] = true
		}
	}
	return labels
}

func pathCandidates(path, home string) []string {
	path = normalizePath(path)
	home = normalizePath(home)
	if path == "" {
		return []string{"shell"}
	}
	if path == string(filepath.Separator) {
		return []string{"/"}
	}
	if home != "" && path == home {
		return []string{"~"}
	}

	var parts []string
	var final string
	if home != "" {
		if relative, err := filepath.Rel(home, path); err == nil && relative != "." &&
			relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			parts = splitPath(relative)
			final = "~/" + filepath.ToSlash(relative)
		}
	}
	if len(parts) == 0 {
		parts = splitPath(path)
		final = filepath.ToSlash(path)
	}

	var candidates []string
	for depth := 1; depth <= len(parts); depth++ {
		candidate := strings.Join(parts[len(parts)-depth:], "/")
		candidates = appendUnique(candidates, candidate)
	}
	candidates = appendUnique(candidates, final)
	if len(candidates) == 0 {
		return []string{"shell"}
	}
	return candidates
}

func splitPath(path string) []string {
	path = filepath.ToSlash(filepath.Clean(path))
	path = strings.Trim(path, "/")
	if path == "" || path == "." {
		return nil
	}
	return strings.Split(path, "/")
}

func appendUnique(values []string, value string) []string {
	if value == "" || slices.Contains(values, value) {
		return values
	}
	return append(values, value)
}

func withIndex(label string, index int) string {
	return fmt.Sprintf("%s (%d)", label, index)
}

func closeIgnoringError(closer io.Closer) {
	_ = closer.Close()
}

func call(socketPath, method string, params any, result any) error {
	connection, err := net.DialTimeout("unix", socketPath, requestTimeout)
	if err != nil {
		return fmt.Errorf("connect for %s: %w", method, err)
	}
	defer closeIgnoringError(connection)
	if err := connection.SetDeadline(time.Now().Add(requestTimeout)); err != nil {
		return fmt.Errorf("set %s deadline: %w", method, err)
	}

	if err := json.NewEncoder(connection).Encode(request{ID: method, Method: method, Params: params}); err != nil {
		return fmt.Errorf("send %s: %w", method, err)
	}

	var response response
	if err := json.NewDecoder(connection).Decode(&response); err != nil {
		return fmt.Errorf("receive %s: %w", method, err)
	}
	if response.Error != nil {
		return fmt.Errorf("%s: %s (%s)", method, response.Error.Message, response.Error.Code)
	}
	if result != nil {
		if err := json.Unmarshal(response.Result, result); err != nil {
			return fmt.Errorf("decode %s result: %w", method, err)
		}
	}
	return nil
}
