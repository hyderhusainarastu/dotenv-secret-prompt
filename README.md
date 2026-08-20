# dotenv-secret-prompt

A small zsh script that interactively writes API keys and other secrets into
a `.env` file, without ever putting them in your shell history, on screen, or
in a git commit.

## The problem

Getting secrets into a local `.env` file usually means one of:

- Pasting them straight into the file in an editor — fine, until you `git add
  -A` on a repo where `.env` isn't actually ignored, or a screen-share
  catches the file open.
- `export FOO=bar >> .env` or similar one-liners — the value sits in your
  shell history (`~/.zsh_history`) indefinitely, and briefly in `ps` output.
- Some project-specific script that hardcodes the list of secrets it expects
  and the path to `.env`, so it only works for that one project and silently
  goes stale when the list of required keys changes.

`dotenv-secret-prompt.zsh` is a generic version of a script written to solve
this for one project's own `.env` setup: it refuses to run unless the target
file is actually git-ignored, reads each value with terminal echo off, writes
atomically so an interrupted run can't corrupt the file, and treats a blank
answer as "leave this one alone" so you can fill in secrets incrementally.

## Quick start

Say you're setting up a project with this `.env.example`:

```sh
# .env.example
ACME_API_KEY=
ACME_WEBHOOK_SECRET=
```

Copy `dotenv-secret-prompt.zsh` into the project (or reference it from
wherever you keep shared scripts) and run it from the directory that holds
`.env.example`:

```console
$ ./dotenv-secret-prompt.zsh
Paste ACME_API_KEY (hidden; blank leaves it unchanged): [nothing shown as you type]
Paste ACME_WEBHOOK_SECRET (hidden; blank leaves it unchanged): [nothing shown as you type]
Saved secrets in ignored ./.env.
```

**Before:** no `.env` file, or one you've been hand-editing.
**After:** `./.env` exists, mode `600`, containing exactly:

```
ACME_API_KEY=sk-live-...
ACME_WEBHOOK_SECRET=whsec-...
```

Run it again later and press Enter on `ACME_API_KEY` to leave it as-is while
rotating just `ACME_WEBHOOK_SECRET` — only the line you typed a value for
changes.

By default the script writes `./.env` and looks for `./.env.example` right
next to it. To target a different file (and its sibling `.env.example`), use
`-f`:

```console
$ ./dotenv-secret-prompt.zsh -f apps/worker/.env
```

If no `.env.example` exists next to the target — or it exists but defines no
`KEY=...` lines — the script instead prompts once for a space-separated list
of key names to set.

You can try this against the fictional fixture in `examples/`: copy
`examples/.env.example` into a scratch directory that's a git repo (with
`.env` covered by `.gitignore`), and run the script there with `-f`.

## What each safety check is for

The script refuses to skip any of these, on purpose:

1. **Refuses to write unless the target file is git-ignored** (`git
   check-ignore`). A `.env` is guaranteed to hold real secrets the moment
   this script touches it. If it isn't actually covered by `.gitignore`, the
   next `git add .` stages live credentials. This turns "did you remember to
   ignore it?" from a discipline problem into a hard stop.
2. **Reads input with echo off** (`read -s`), and only from an interactive
   prompt, never a command-line argument. Terminal echo would put the secret
   on screen and in scrollback/screen-share; a command-line argument would
   put it in `~/.zsh_history` and in `ps` output for other users on the same
   machine.
3. **Writes atomically**: builds the new file in a `mktemp` temp file next to
   the target, `chmod 600`s *that* file, then `mv`s it into place. A plain
   `>` redirect truncates the target immediately, so a crash or Ctrl-C
   mid-write can leave a corrupt or empty `.env`; this way the file on disk
   is always either the complete old version or the complete new one, and it
   never briefly exists with looser-than-owner-only permissions.
4. **Blank input is a no-op, not an empty value.** Pressing Enter for a key
   you don't have yet leaves any existing value in the file untouched,
   instead of overwriting it with `KEY=` and quietly breaking whatever reads
   that variable. This is also what lets you fill in secrets across several
   runs instead of needing all of them at once.

## How key names are chosen

The script looks for `.env.example` in the same directory as the target
`.env` file, parses its `KEY=...` lines (comments and blank lines ignored,
duplicate keys de-duplicated, order preserved), and prompts for exactly those
keys. This means the list of prompts tracks whatever a project's own
`.env.example` says it needs — there's no separate hardcoded key list to
forget to update. If no usable `.env.example` is found, the script falls
back to asking you to type key names directly.

## Limitations

- **zsh only.** It uses zsh-specific syntax (`print`, `${=reply}` word
  splitting, associative arrays) and won't run under `bash` or `sh` as-is.
- **No secret manager integration.** This only writes plain text to a local
  file with restrictive permissions — it is not a substitute for a real
  secrets manager (Vault, 1Password, cloud KMS, etc.) in any environment
  where that's warranted.
- **`.env.example` parsing is intentionally simple.** It reads `KEY=` at the
  start of a line and treats `#` as starting a comment; it does not handle
  multi-line values, `export KEY=` prefixes, or values containing an
  unescaped `#`. For files that use those forms, fall back to typing key
  names manually.
- **The git-ignore check only verifies the target file itself**, at the path
  you gave it. It doesn't check whether some other copy of the same secrets
  (a backup, a `.env.bak`, a value pasted into a different tracked file)
  exists elsewhere in the repo.
- **`chmod 600` is a Unix permission model.** On filesystems or platforms
  that don't support POSIX permissions the same way (some network mounts,
  Windows filesystems without WSL), the permission-tightening step may be a
  no-op even though the file still gets written.
- Not tested outside macOS/Linux zsh; it should work under any reasonably
  current zsh with standard `git`, `grep`, `mktemp`, and `chmod` available.
