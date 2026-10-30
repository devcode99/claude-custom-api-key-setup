# Claude Code API Key Setup

Sets up [Claude Code](https://claude.com/claude-code) (the terminal CLI **and** the VS Code extension) to use your own API key. You can use an Anthropic key, or point it at your own Anthropic-compatible AI service with a custom base URL.

What the scripts do:

1. Add the key (and base URL, if you give one) to your shell startup files (`~/.bashrc` / `~/.zshrc`), or to user environment variables on Windows.
2. Add the same values to the `env` block of `~/.claude/settings.json`. The VS Code extension reads this file even when VS Code was opened from the desktop and never loaded `.bashrc`.
3. **Pre-approve the key** in `~/.claude.json`. This means Claude Code won't ask *"Detected a custom API key in your environment… Do you want to use this API key?"*, and it skips first-run onboarding.
4. Optionally start `claude` so you can check that it works.

Before changing a config file, the script copies it to `<file>.bak.<timestamp>`. You can run the script again at any time: the old values are replaced, not duplicated.

---

## Quick start

### Linux / macOS

```bash
chmod +x setup-claude-key.sh

# Interactive (asks for the key with hidden input, then the optional URL)
./setup-claude-key.sh

# Anthropic key
./setup-claude-key.sh -k sk-ant-xxxxxxxx

# Your own AI service / proxy / gateway
./setup-claude-key.sh -k YOUR_KEY -u https://your-service.example.com

# Your service expects "Authorization: Bearer <key>" instead of "x-api-key"
./setup-claude-key.sh -k YOUR_KEY -u https://your-service.example.com --bearer

# Load the new values into your current terminal
source ~/.bashrc
```

Needs `python3` or `node` to edit JSON. One of them is almost always already installed.

### Windows (PowerShell)

```powershell
# Interactive
powershell -ExecutionPolicy Bypass -File .\setup-claude-key.ps1

# Anthropic key
powershell -ExecutionPolicy Bypass -File .\setup-claude-key.ps1 -Key sk-ant-xxxxxxxx

# Your own AI service
powershell -ExecutionPolicy Bypass -File .\setup-claude-key.ps1 -Key YOUR_KEY -Url https://your-service.example.com -Bearer
```

After running it, open a **new** terminal. Terminals that were already open keep the old environment.

### Options

| bash              | PowerShell   | Meaning                                                                 |
|-------------------|--------------|-------------------------------------------------------------------------|
| `-k, --key`       | `-Key`       | API key/token (asked for if left out)                                   |
| `-u, --url`       | `-Url`       | Custom base URL (leave out to use `api.anthropic.com`)                  |
| `--bearer`        | `-Bearer`    | Use `ANTHROPIC_AUTH_TOKEN` (Bearer) instead of `ANTHROPIC_API_KEY`      |
| `--no-shell-rc`   | `-NoUserEnv` | Only write the Claude config files, not the shell/OS environment        |
| `--launch`        | `-Launch`    | Start `claude` at the end without asking                                |
| `--no-launch`     | `-NoLaunch`  | Don't start `claude` at the end                                         |
| `--uninstall`     | `-Uninstall` | Remove everything the script added                                      |

### After running: VS Code

1. **Quit VS Code completely and reopen it.** Reloading the window isn't enough, because environment variables are only read when VS Code starts.
2. Open the Claude Code panel. It should use your key straight away.
3. If it still shows a login screen, open VS Code Settings, search for **"Claude Code: Disable Login Prompt"** and turn it on. This setting is meant for API-key and third-party provider setups.

---

## Which auth mode do I need?

| Your setup                                          | Variable to set          | Header sent                  |
|-----------------------------------------------------|--------------------------|------------------------------|
| Anthropic API key (`sk-ant-...`)                    | `ANTHROPIC_API_KEY`      | `x-api-key: <key>`           |
| Proxy/gateway that forwards `x-api-key`             | `ANTHROPIC_API_KEY`      | `x-api-key: <key>`           |
| Proxy/gateway/LLM router that wants a Bearer token  | `ANTHROPIC_AUTH_TOKEN`   | `Authorization: Bearer <key>`|

Set **one** of the two, not both. If you aren't sure, check your service's docs for "Claude Code" or "Anthropic-compatible" setup instructions. Your service must provide the Anthropic **Messages API** (`POST {BASE_URL}/v1/messages`). An OpenAI-style API alone won't work.

---

## Manual setup

Use this if you'd rather not run the script, or if you want to see exactly what it changes.

### Linux / macOS

**1. Shell environment.** Add this to `~/.bashrc` (and `~/.zshrc` if you use zsh):

```bash
export ANTHROPIC_API_KEY='sk-ant-xxxxxxxx'
# Only if you use your own service:
# export ANTHROPIC_BASE_URL='https://your-service.example.com'
# If your service wants Bearer auth, use this INSTEAD of ANTHROPIC_API_KEY:
# export ANTHROPIC_AUTH_TOKEN='your-key'
```

Then reload: `source ~/.bashrc`

**2. Claude settings file.** Edit `~/.claude/settings.json`, or create it if it doesn't exist. Keep any keys that are already there and add or merge the `env` block:

```json
{
  "env": {
    "ANTHROPIC_API_KEY": "sk-ant-xxxxxxxx",
    "ANTHROPIC_BASE_URL": "https://your-service.example.com"
  }
}
```

Leave out `ANTHROPIC_BASE_URL` if you use Anthropic directly. Lock the file down: `chmod 600 ~/.claude/settings.json`

**3. Pre-approve the key** so Claude Code doesn't ask about it. Edit `~/.claude.json`. This file is large and holds a lot of other state, so **only add or merge these two keys**:

```json
{
  "customApiKeyResponses": {
    "approved": ["<LAST 20 CHARACTERS OF YOUR KEY>"],
    "rejected": []
  },
  "hasCompletedOnboarding": true
}
```

To print the last 20 characters of your key:

```bash
echo -n "$ANTHROPIC_API_KEY" | tail -c 20; echo
```

Instead of editing this file, you can just run `claude` once and answer **Yes** when it asks whether to use the detected API key. Claude Code then writes the same entry itself.

**4. Restart** your terminal and VS Code (quit completely, then reopen).

### Windows

**1. User environment variables** (the Windows equivalent of `.bashrc`). Run in PowerShell:

```powershell
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-xxxxxxxx", "User")
# Only if you use your own service:
# [Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "https://your-service.example.com", "User")
# Bearer-auth services: use ANTHROPIC_AUTH_TOKEN instead of ANTHROPIC_API_KEY
```

You can also use the GUI: Start → "Edit environment variables for your account" → New.

**2. Claude settings file.** Edit `%USERPROFILE%\.claude\settings.json` and add the same `env` block as in the Linux step 2.

**3. Pre-approve the key.** Edit `%USERPROFILE%\.claude.json` and add the same entries as in the Linux step 3. To get the last 20 characters:

```powershell
$k = $env:ANTHROPIC_API_KEY; $k.Substring($k.Length - 20)
```

> If you edit JSON files in Windows PowerShell 5.1, don't use `Set-Content -Encoding UTF8`, because it adds a BOM. Use a text editor such as VS Code or Notepad and save as "UTF-8" (not "UTF-8 with BOM").

**4. Open a new terminal** and fully restart VS Code.

---

## Check that it works

```bash
claude            # then type /status, which shows the auth method and base URL
claude -p "say hi" # one-off request, no interactive UI
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Still asks *"Do you want to use this API key?"* | The entry in `customApiKeyResponses.approved` doesn't match the last 20 characters of the key that is actually in use. Run the script again, or answer **Yes**. |
| Key works in the terminal but not in VS Code | Quit VS Code completely and reopen it. Check that `~/.claude/settings.json` has the `env` block. |
| VS Code still shows a login screen | Turn on the VS Code setting **Claude Code: Disable Login Prompt**. |
| `401` / `invalid x-api-key` against your own service | Your service probably wants Bearer auth. Run the script again with `--bearer` / `-Bearer`. |
| `404` against your own service | The base URL must be the root that `/v1/messages` is added to. Don't include `/v1` yourself unless your provider tells you to. |
| A different key is being used | Run `env \| grep ANTHROPIC` (or `gci env:ANTHROPIC*` on Windows). An older value may be set somewhere else, such as `~/.profile` or the system environment variables. |
| You were logged in with a Claude.ai subscription before | Environment variables and API keys take priority over a subscription login. Run `/logout` inside `claude` if you want to remove the old login. |

## Uninstall

```bash
./setup-claude-key.sh --uninstall
```
```powershell
powershell -ExecutionPolicy Bypass -File .\setup-claude-key.ps1 -Uninstall
```

This removes the shell/OS environment variables and the `env` entries in `settings.json`. The approval entry in `~/.claude.json` is harmless and stays. Your `.bak.*` backups are never deleted automatically.

## Security notes

- The key is stored **in plain text** in your shell rc file, `~/.claude/settings.json`, and the backup copies. The script sets both JSON files to permission `600` (only you can read them). Don't commit these files or share them.
- The script never puts the key on a command line where other users could see it in `ps`. Interactive input is hidden.
- For team or shared machines, consider the `apiKeyHelper` setting in `settings.json`. It runs a script that fetches the key from a secret manager instead of storing it in a file.
