#!/bin/zsh
# dotenv-secret-prompt.zsh — interactively write secrets into a .env file
# without ever putting them in your shell history, on the screen, or in a
# git commit. See README.md for the full rationale behind each safety check
# below; the short version is in each comment.
#
# Usage:
#   ./dotenv-secret-prompt.zsh              # writes ./.env
#   ./dotenv-secret-prompt.zsh -f path/.env  # writes an explicit file
#
# Key names to prompt for come from a sibling .env.example next to the
# target file (KEY=... lines, comments and blanks ignored). If no
# .env.example is found, or it defines no keys, you're prompted to type
# key names instead.

set -euo pipefail

usage() {
  print -u2 -- "Usage: $0 [-f path/to/.env]"
  print -u2 -- ""
  print -u2 -- "  -f FILE   .env file to write (default: ./.env)"
  print -u2 -- "  -h        show this help"
  exit 1
}

env_file="./.env"

while getopts ":f:h" opt; do
  case "$opt" in
    f) env_file="$OPTARG" ;;
    h) usage ;;
    \?) usage ;;
    :) print -u2 -- "Option -$OPTARG requires a value."; usage ;;
  esac
done

env_dir="$(dirname -- "$env_file")"
example_file="${env_dir}/.env.example"

# --- Safety 1: refuse unless the target file is git-ignored -----------------
# A .env is guaranteed to hold real secrets the moment this script writes to
# it. If it isn't in .gitignore (or an ignore pattern doesn't match it for
# some other reason), the very next `git add .` would stage live credentials.
# This check makes that specific mistake impossible rather than just
# discouraged: no write happens until Git itself confirms the file is ignored.
if ! git check-ignore -q -- "$env_file"; then
  print -u2 -- "Refusing to write: ${env_file} is not ignored by Git."
  print -u2 -- "Add a matching pattern to .gitignore, then run this again."
  exit 1
fi

touch -- "$env_file"
chmod 600 "$env_file"

# upsert_secret NAME
#
# Prompts for one secret and writes it into $env_file, replacing any
# existing NAME=... line and leaving every other line untouched.
upsert_secret() {
  local name="$1"
  local value
  local temporary_file

  # --- Safety 2: hidden input -----------------------------------------------
  # `read -s` disables terminal echo, so the secret never appears on screen,
  # in a screen-share, or in terminal scrollback. Just as important: it's
  # typed at a prompt, never passed as a command-line argument — arguments
  # land in shell history (~/.zsh_history) and in `ps` output for the
  # duration of the process, and a pasted secret is exactly the kind of
  # thing you don't want sitting in either place.
  print -n -- "Paste ${name} (hidden; blank leaves it unchanged): "
  IFS= read -r -s value
  print

  # --- Safety 3: blank input is a no-op, not an empty value -----------------
  # If you don't have a value for this key yet, pressing Enter should leave
  # whatever is already in the file alone — not overwrite it with NAME= and
  # silently break whatever reads that variable. Skipping keys you don't
  # have right now is also how this script lets you fill in a handful of
  # secrets across several runs instead of requiring every value at once.
  if [[ -z "$value" ]]; then
    print "Left ${name} unchanged."
    return
  fi

  # --- Safety 4: atomic write via temp file + chmod 600 ----------------------
  # Writing straight into $env_file with a redirect (`>`) truncates it
  # first — a crash or Ctrl-C mid-write leaves a corrupt or empty .env, and
  # the whole file is briefly world-default-permission before anything
  # re-tightens it. Building the new contents in a temp file, chmod-ing
  # *that* file to 600, and then `mv`-ing it over the target instead means
  # the visible file is always either the complete old version or the
  # complete new version — never a partial write — and it never exists on
  # disk with looser-than-600 permissions along the way. `mktemp` creates
  # the temp file next to $env_file so the final `mv` is a same-filesystem
  # rename (atomic), not a cross-filesystem copy.
  temporary_file="$(mktemp "${env_file}.XXXXXX")"
  /usr/bin/grep -v "^${name}=" -- "$env_file" > "$temporary_file" || true
  print -r -- "${name}=${value}" >> "$temporary_file"
  chmod 600 "$temporary_file"
  mv -- "$temporary_file" "$env_file"
  unset value
}

# --- Determine which keys to prompt for -------------------------------------
# Prefer the sibling .env.example's own KEY=... lines over any hardcoded
# list, so this script stays correct as a project's required secrets change
# — the project's .env.example is already the place that list is supposed
# to live and stay in sync.
typeset -a key_names
typeset -A seen_keys
key_names=()
seen_keys=()

if [[ -f "$example_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"        # drop inline/whole-line comments
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    key="${key//[[:space:]]/}"
    [[ -n "$key" ]] || continue
    # Only accept things that actually look like env var names, so a
    # malformed or unexpected line in .env.example is skipped rather than
    # turned into a bogus prompt.
    if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && [[ -z "${seen_keys[$key]:-}" ]]; then
      key_names+=("$key")
      seen_keys[$key]=1
    fi
  done < "$example_file"
fi

if [[ ${#key_names[@]} -eq 0 ]]; then
  if [[ -f "$example_file" ]]; then
    print "${example_file} exists but defines no KEY=... lines."
  else
    print "No ${example_file} found."
  fi
  print -n -- "Enter key names to set, space-separated (blank to quit): "
  IFS= read -r reply
  key_names=(${=reply})
fi

if [[ ${#key_names[@]} -eq 0 ]]; then
  print "No key names given. Nothing to do."
  exit 0
fi

for name in "${key_names[@]}"; do
  upsert_secret "$name"
done

print "Saved secrets in ignored ${env_file}."
