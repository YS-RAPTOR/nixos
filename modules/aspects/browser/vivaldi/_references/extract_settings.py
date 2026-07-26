#!/usr/bin/env python3

import json
import sys
from pathlib import Path
from copy import deepcopy

# =============================================================================
# WHITELIST CONFIGURATION
# =============================================================================

# Top-level keys to extract completely
WHITELIST_TOP_LEVEL = {
    "bookmark_bar",
    "intl",
    "spellcheck",
}

# Specific paths to extract (dot notation)
# These will be extracted even if parent isn't in WHITELIST_TOP_LEVEL
WHITELIST_PATHS = {
    # Download settings (not download history)
    "download.prompt_for_download",
    "download.directory_upgrade",
    # DevTools preferences
    "devtools.preferences",
    # Browser window settings
    "browser.window_placement",
    # Extension keyboard shortcuts (not extension data)
    "extensions.commands",
}

# Full preference paths to exclude even when a parent path is whitelisted.
SENSITIVE_PATH_BLACKLIST = {
    # DevTools state that can expose local development URLs.
    "devtools.preferences.resources-last-selected-element-path",
    # Search provider IDs/profile metadata; not needed for portable UI settings.
    "default_search_provider",
    "default_search_provider_data",
    # Local filesystem paths and saved location presets.
    "vivaldi.appearance.css_ui_mods_directory",
    "vivaldi.geolocation",
}

# Vivaldi-specific settings to extract (under "vivaldi" key)
# These are the core settings that define your browser customization
VIVALDI_WHITELIST = {
    # UI Layout
    "toolbars",
    "tabs",
    "panels",
    "address_bar",
    "status_bar",
    "windows",
    "pip_placement",
    "sidebar",
    # Appearance
    "theme",
    "themes",
    "appearance",
    # Behavior
    "actions",  # Keyboard shortcuts
    "menu",
    "quick_commands",
    "mouse_gestures",
    "rocker_gestures",
    "chained_commands",  # Command chains (filtered by COMMAND_CHAIN_FILTER)
    # Features settings
    "calendar",
    "contacts",
    "downloads",
    "history",
    "mail",
    "notes",
    "translate",
    # Browser behavior
    "homepage",
    "incognito",
    "popups",
    "privacy",
    "sessions",  # Session settings, not session data
    "settings",
    "startpage",
    "system",
    "webpages",
    "workspaces",
    # UI customization
    "context_dialogs",
    "features",
    "welcome",
    # Speed dial (layout only, not thumbnails)
    "speeddial",
    # Geolocation UI preferences (not location data)
    "geolocation",
}

# Keys to EXCLUDE from vivaldi settings even if parent is whitelisted
VIVALDI_BLACKLIST = {
    # Sensitive/personal data
    "vivaldi_account",
    "sync",
    "startup.active_days",  # Usage timestamps
    "startup.last_seen_search_engine_prompt_time",
    # Session-specific data
    "tabs.button.last_suggestion_time",
    # Dashboard widgets (may contain sensitive URLs)
    "dashboard",
    # Web panels (contain URLs)
    "panels.web",
    # Reader/RSS feeds (contain URLs)
    "reader",
    # Local filesystem paths and saved location presets
    "appearance.css_ui_mods_directory",
    "geolocation",
}

# Command chain names to filter out (case-insensitive)
COMMAND_CHAIN_FILTER = {"exh"}

# =============================================================================
# EXTRACTION FUNCTIONS
# =============================================================================


def get_nested_value(obj, path):
    """Get a value from a nested dict using dot notation."""
    keys = path.split(".")
    current = obj
    for key in keys:
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return None
    return current


def set_nested_value(obj, path, value):
    """Set a value in a nested dict using dot notation."""
    keys = path.split(".")
    current = obj
    for key in keys[:-1]:
        if key not in current:
            current[key] = {}
        current = current[key]
    current[keys[-1]] = value


def is_blacklisted(path):
    """Check if a path is blacklisted."""
    for blacklisted in VIVALDI_BLACKLIST:
        if path == blacklisted or path.startswith(blacklisted + "."):
            return True
    return False


def is_sensitive_path(path):
    """Check if a full preference path is sensitive/local-only."""
    for blacklisted in SENSITIVE_PATH_BLACKLIST:
        if path == blacklisted or path.startswith(blacklisted + "."):
            return True
    return False


def filter_sensitive_paths(obj, parent_path=""):
    """Recursively filter sensitive full preference paths from dicts."""
    if not isinstance(obj, dict):
        return deepcopy(obj)

    filtered = {}
    for key, value in obj.items():
        current_path = f"{parent_path}.{key}" if parent_path else key

        if is_sensitive_path(current_path):
            print(f"  Skipped (sensitive): {current_path}")
            continue

        if isinstance(value, dict):
            filtered_child = filter_sensitive_paths(value, current_path)
            if filtered_child:
                filtered[key] = filtered_child
        else:
            filtered[key] = deepcopy(value)

    return filtered


def filter_command_chains(chained_commands):
    """Filter out command chains by name (case-insensitive)."""
    if not isinstance(chained_commands, dict):
        return chained_commands

    result = deepcopy(chained_commands)

    if "command_list" in result and isinstance(result["command_list"], list):
        original_list = result["command_list"]
        new_list = []
        for cmd in original_list:
            label = cmd.get("label", "").lower()
            if label in COMMAND_CHAIN_FILTER:
                print(f"  Filtered command chain: {cmd.get('label')}")
            else:
                new_list.append(cmd)
        result["command_list"] = new_list

    return result


def extract_vivaldi_settings(vivaldi_data):
    """Extract whitelisted settings from the vivaldi section."""
    if not isinstance(vivaldi_data, dict):
        return {}

    extracted = {}

    for key in VIVALDI_WHITELIST:
        if key in vivaldi_data:
            # Check if this key or any of its children are blacklisted
            if is_blacklisted(key):
                continue

            value = vivaldi_data[key]

            # Special handling for chained_commands - filter by name
            if key == "chained_commands":
                filtered_value = filter_command_chains(value)
                if filtered_value:
                    extracted[key] = filtered_value
                continue

            # For nested dicts, filter out blacklisted paths
            if isinstance(value, dict):
                filtered_value = filter_blacklisted(value, key)
                if filtered_value:  # Only add if there's something left
                    extracted[key] = filtered_value
            else:
                extracted[key] = deepcopy(value)

    return extracted


def filter_blacklisted(obj, parent_path=""):
    """Recursively filter out blacklisted paths from a dict."""
    if not isinstance(obj, dict):
        return deepcopy(obj)

    filtered = {}
    for key, value in obj.items():
        current_path = f"{parent_path}.{key}" if parent_path else key

        if is_blacklisted(current_path):
            print(f"  Skipped (blacklisted): {current_path}")
            continue

        if isinstance(value, dict):
            filtered_child = filter_blacklisted(value, current_path)
            if filtered_child:  # Only add if not empty
                filtered[key] = filtered_child
        else:
            filtered[key] = deepcopy(value)

    return filtered


def extract_settings(preferences):
    """Extract all whitelisted settings from preferences."""
    extracted = {
        "_meta": {
            "version": "1.0",
            "description": "Vivaldi settings extracted for backup/portability",
        }
    }

    print("Extracting settings...")

    # Extract top-level whitelisted keys
    for key in WHITELIST_TOP_LEVEL:
        if key in preferences:
            print(f"  Extracted: {key}")
            extracted[key] = filter_sensitive_paths(preferences[key], key)

    # Extract specific paths
    for path in WHITELIST_PATHS:
        if is_sensitive_path(path):
            print(f"  Skipped (sensitive): {path}")
            continue

        value = get_nested_value(preferences, path)
        if value is not None:
            print(f"  Extracted: {path}")
            set_nested_value(extracted, path, filter_sensitive_paths(value, path))

    # Extract vivaldi settings
    if "vivaldi" in preferences:
        print("  Extracting vivaldi settings...")
        extracted["vivaldi"] = filter_sensitive_paths(
            extract_vivaldi_settings(preferences["vivaldi"]), "vivaldi"
        )

    return extracted


# =============================================================================
# MERGE FUNCTIONS
# =============================================================================


def deep_merge(base, override):
    """
    Deep merge override into base.
    Override values take precedence.
    """
    result = deepcopy(base)

    for key, value in override.items():
        if key == "_meta":
            continue  # Skip metadata

        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = deepcopy(value)

    return result


def merge_settings(settings, target_preferences):
    """Merge extracted settings into target preferences."""
    print("Merging settings...")

    merged = deep_merge(target_preferences, settings)

    return merged


# =============================================================================
# CLI
# =============================================================================


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == "extract":
        # Extract settings
        input_file = (
            Path(sys.argv[2])
            if len(sys.argv) > 2
            else Path(__file__).parent / "Preferences.json"
        )
        output_file = (
            Path(sys.argv[3])
            if len(sys.argv) > 3
            else Path(__file__).parent / "vivaldi_settings.json"
        )

        if not input_file.exists():
            print(f"Error: Input file not found: {input_file}")
            sys.exit(1)

        print(f"Reading: {input_file}")
        with open(input_file, "r", encoding="utf-8") as f:
            preferences = json.load(f)

        settings = extract_settings(preferences)

        print(f"\nWriting: {output_file}")
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)

        # Stats
        original_size = input_file.stat().st_size
        output_size = output_file.stat().st_size
        reduction = (original_size - output_size) / original_size * 100

        print(f"\nOriginal size: {original_size:,} bytes")
        print(f"Settings size: {output_size:,} bytes")
        print(f"Reduction:     {reduction:.1f}%")

    elif command == "merge":
        if len(sys.argv) < 4:
            print(
                "Usage: python extract_settings.py merge <settings_file> <target_preferences> [output]"
            )
            sys.exit(1)

        settings_file = Path(sys.argv[2])
        target_file = Path(sys.argv[3])
        output_file = (
            Path(sys.argv[4])
            if len(sys.argv) > 4
            else target_file.with_name("Preferences_merged.json")
        )

        if not settings_file.exists():
            print(f"Error: Settings file not found: {settings_file}")
            sys.exit(1)

        if not target_file.exists():
            print(f"Error: Target preferences not found: {target_file}")
            sys.exit(1)

        print(f"Reading settings: {settings_file}")
        with open(settings_file, "r", encoding="utf-8") as f:
            settings = json.load(f)

        print(f"Reading target: {target_file}")
        with open(target_file, "r", encoding="utf-8") as f:
            target = json.load(f)

        merged = merge_settings(settings, target)

        print(f"\nWriting: {output_file}")
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(merged, f, indent=4, ensure_ascii=False)

        print("Done!")

    else:
        print(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
