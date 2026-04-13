# Installing and Setting Up Docker Sandbox (sbx) on Claude Code on the Web

Guide for installing the `sbx` CLI in a Claude Code web session (claude.ai/code) for development and testing.

## Prerequisites

- A Claude Code web session (Ubuntu 24.04 x86_64 environment)
- Docker is pre-installed in the environment (`/usr/bin/docker`)
- A Docker account for authentication

## Step 1: Download the sbx CLI Package

Fetch the latest release `.deb` package from the [docker/sbx-releases](https://github.com/docker/sbx-releases) GitHub repository.

First, identify the latest version and get the Ubuntu 24.04 `.deb` URL:

```bash
curl -sL "https://api.github.com/repos/docker/sbx-releases/releases/latest" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
print('Latest version:', data['tag_name'])
for asset in data['assets']:
    if 'ubuntu2404' in asset['name']:
        print('Download URL:', asset['browser_download_url'])
"
```

Then download it:

```bash
curl -fsSL -o /tmp/docker-sbx.deb \
  "https://github.com/docker/sbx-releases/releases/download/v0.24.2/DockerSandboxes-linux-amd64-ubuntu2404.deb"
```

> **Note**: Replace `v0.24.2` with the latest version from the API query above.

## Step 2: Install the Package

Install using `apt-get` without recommended packages (the `apparmor` recommended dependency cannot be fetched in the web environment due to network restrictions, but it is not required):

```bash
sudo apt-get install -y --no-install-recommends /tmp/docker-sbx.deb
```

## Step 3: Verify Installation

```bash
sbx version
```

Expected output:

```
Client Version:  v0.24.2 ...
Server Version:  Unavailable
```

The server version shows "Unavailable" until the daemon is started (happens automatically during login).

## Step 4: Authenticate with Docker

Run the login command:

```bash
sbx login
```

This starts a device-code authentication flow:

```
Your one-time device confirmation code is: XXXX-XXXX
Open this URL to sign in: https://login.docker.com/activate?user_code=XXXX-XXXX

Waiting for authentication...
```

1. Open the URL shown in your browser
2. Enter the device confirmation code (or it may be pre-filled)
3. Sign in with your Docker account
4. Return to the Claude Code session — it will detect the authentication automatically

On success you will see:

```
Signed in as <your-username>.
Daemon started (PID: XXXX, socket: /root/.local/state/sandboxes/sandboxes/sandboxd/sandboxd.sock)
Logs: /root/.local/state/sandboxes/sandboxes/sandboxd/daemon.log

Note: default network policy has not been configured
```

## Step 5: Configure Network Policy (Optional)

Set a default network policy for sandboxes:

```bash
# Allow all outbound network access (most permissive)
sbx policy set-default allow-all

# Balanced — blocks known-dangerous destinations
sbx policy set-default balanced

# Deny all outbound network access (most restrictive)
sbx policy set-default deny-all
```

You can also manage fine-grained policies:

```bash
sbx policy allow <resource>    # Allow specific domains/IPs
sbx policy deny <resource>     # Block specific domains/IPs
sbx policy ls                  # List current policies
sbx policy log                 # Show policy enforcement logs
```

## Step 6: Create a Sandbox

```bash
# Create a sandbox for Claude in the current directory
sbx create claude .

# Create with a custom name
sbx create --name my-project claude /path/to/project

# Create with a Git worktree for isolated changes
sbx create --branch=feature/login claude .

# Create with additional read-only workspaces
sbx create claude . /path/to/docs:ro
```

Supported agents: `claude`, `codex`, `copilot`, `docker-agent`, `gemini`, `kiro`, `opencode`, `shell`.

## Step 7: Run an Agent in a Sandbox

```bash
sbx run <sandbox-name>
```

## Common Commands Reference

| Command | Description |
|---------|-------------|
| `sbx ls` | List all sandboxes |
| `sbx ls --json` | List sandboxes in JSON format |
| `sbx create claude .` | Create a Claude sandbox in current dir |
| `sbx run <name>` | Attach to a sandbox agent |
| `sbx exec <name> <cmd>` | Execute a command inside a sandbox |
| `sbx stop <name>` | Stop a sandbox without removing it |
| `sbx rm <name>` | Remove a sandbox |
| `sbx ports ls <name>` | List published ports |
| `sbx policy ls` | List network policies |
| `sbx reset` | Reset all sandboxes and clean up state |
| `sbx version` | Show version information |
| `sbx logout` | Sign out of Docker |

## Troubleshooting

### "Not authenticated to Docker"
Run `sbx login` and complete the browser-based authentication flow.

### apparmor dependency warning during install
This is expected in the Claude Code web environment. The `apparmor` package is a "Recommends" dependency, not required. Using `--no-install-recommends` skips it safely.

### Server Version shows "Unavailable"
The sbx daemon starts automatically during `sbx login`. If you see this after login, the daemon may have stopped. Run `sbx login` again or check the daemon log:

```bash
cat /root/.local/state/sandboxes/sandboxes/sandboxd/daemon.log
```

### Token refresh warnings
You may see `WARN: failed to refresh token` messages if the session has been idle. Run `sbx login` again to re-authenticate.

### Session persistence
The sbx installation and authentication persist for the duration of the Claude Code web session. If the session is reset or a new session starts, you will need to reinstall and re-authenticate.
