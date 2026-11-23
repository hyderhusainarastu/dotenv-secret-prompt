# AGENTS.md

## Using this in your project

`dotenv-secret-prompt.zsh` writes secrets into a git-ignored `.env` file. The user types the values at a hidden prompt, so they never enter chat, shell history or your context.

Rules for an agent:
- Never ask for, read, print or paste secret values. Do not open `.env`.
- When a project needs a secret, ask the user to run: `./dotenv-secret-prompt.zsh` (or `-f path/.env`) in their own terminal. Wait for them to confirm.
- Do not run the script yourself in a non-interactive shell. It needs a TTY and will not accept values from arguments or pipes.
- Key names come from `.env.example` next to the target. Add new keys there (empty values only), then ask the user to re-run the script.
- Blank answers keep existing values, so re-running is safe.
- Do not weaken the git-ignore check, and never commit `.env`.

Call contract:
- Command: `./dotenv-secret-prompt.zsh [-f FILE]`
- Exit 0: saved (or nothing to change). Non-zero: refused or failed, for example the target is not git-ignored. Report the message to the user and do not work around it.
- Requires zsh, git, mktemp and chmod. On Linux, install zsh first (see README).

Rule snippet for your own AGENTS.md:

    Never ask for or read secret values; ask the user to run dotenv-secret-prompt.

No PROMPT.md: CLI.

## Working on this repo

- Single script: `dotenv-secret-prompt.zsh`. Fixtures are in `examples/` and use fictional values only.
- There is no test suite. Check changes by hand in a scratch git repo with `.env` ignored: `zsh -n dotenv-secret-prompt.zsh` for syntax, then run with `-f`.
- Never commit a real `.env` or real secret values.
