# Fresh-Machine Setup (from zero)

Use this when the template is going onto a **brand-new Windows PC** that has none of the tools yet.
If your machine already has Godot/git/Claude Code/Antigravity, skip this and go straight to
[../NEW_PROJECT.md](../NEW_PROJECT.md).

Everything here is Windows 10/11 + PowerShell.

---

## Step 0 — Install the two AI apps (do these by hand first)

These aren't command-line packages, so install them yourself:

1. **Claude Code CLI** — follow the official installer at <https://code.claude.com/docs>.
   (After install it lives at `C:\Users\<you>\.local\bin\claude.exe`.)
2. **Google Antigravity** — download and install from <https://antigravity.google>.
3. Sign in to both at least once.

## Step 1 — Install every command-line tool with ONE script

The template ships a script that installs Git, Git LFS, GitHub CLI, Node.js, Python, uv, Godot,
and gdtoolkit, then sets `GODOT_BIN` and your PATH. It's safe to run more than once.

1. Get the template onto the machine (pick one):
   - **Clone** (if it's already on GitHub): open PowerShell and run
     ```
     git clone https://github.com/<your-username>/godot-agent-template.git
     cd godot-agent-template
     ```
     ...but on a truly bare machine you won't have `git` yet — in that case use **Download ZIP**
     from the GitHub page (green **Code** button → **Download ZIP**), unzip it, and open PowerShell
     in that folder.
2. Run the setup script:
   ```
   powershell -ExecutionPolicy Bypass -File scripts\setup-machine.ps1
   ```
3. Read its output. If it prints any **[WARN]** about Python/pip "not on PATH yet", that's normal on
   a bare machine — **close the shell, open a new one, and run the same command again.** The second
   pass finishes gdtoolkit. (The script is built to be re-run safely.)
4. When it finishes, **close the shell and open a fresh one** so every new command works.

> What the script can't do: install Claude Code / Antigravity (Step 0), and enable the Godot plugins
> (that's a click in the Godot UI — Step 3 below).

> The script also installs the **machine-global agent config** at the end (the `/new-godot-project` and
> `/adopt-godot-setup` Claude skills, plus Antigravity's global rules/MCP) by calling
> `scripts\install-global-config.ps1`. You can re-run that installer on its own any time. Full reference:
> [MACHINE_AGENT_SETUP.md](MACHINE_AGENT_SETUP.md).

## Step 2 — Pull the big files & fetch project addons

1. If you **cloned** with Git, the plugin folders and binary assets come down automatically as long as
   Git LFS is installed (the script installed it). If anything looks like a text stub instead of a real
   file, run:
   ```
   git lfs pull
   ```
2. Verify the environment and (re)fetch addons if needed:
   ```
   powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1
   ```
   It should report `[OK]` for GODOT_BIN, git, git-lfs, uv, and gdlint, and confirm the
   `gdUnit4` + `godot_ai` addons are present.

## Step 3 — First run

Now follow **[FIRST_RUN.md](FIRST_RUN.md)** — it walks you (per app) through:
enabling the two Godot plugins, approving the MCP servers in Claude Code, opening the repo in
Antigravity, and verifying MCP there.

---

## Manual fallback (if you'd rather not run the script)

Run these one at a time in PowerShell, opening a **new shell** before the `pip` line:

```powershell
winget install --id Git.Git                 --accept-source-agreements --accept-package-agreements
winget install --id GitHub.GitLFS           --accept-source-agreements --accept-package-agreements
winget install --id GitHub.cli              --accept-source-agreements --accept-package-agreements
winget install --id OpenJS.NodeJS           --accept-source-agreements --accept-package-agreements
winget install --id Python.Python.3.12      --accept-source-agreements --accept-package-agreements
winget install --id astral-sh.uv            --accept-source-agreements --accept-package-agreements
winget install --id GodotEngine.GodotEngine --accept-source-agreements --accept-package-agreements
git lfs install
# open a NEW shell here so python/pip are on PATH, then:
pip install "gdtoolkit==4.*"
```

Then set `GODOT_BIN` (point it at the Godot **console** exe winget installed — the path contains a
long package id, so let PowerShell find it):

```powershell
$godot = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter 'Godot_v*_console.exe' | Select-Object -First 1 -ExpandProperty FullName
[Environment]::SetEnvironmentVariable('GODOT_BIN', $godot, 'User')
```

And add Claude Code's folder to PATH (only if `claude` isn't already found):

```powershell
$lb = "$env:USERPROFILE\.local\bin"
[Environment]::SetEnvironmentVariable('Path', ([Environment]::GetEnvironmentVariable('Path','User') + ";$lb"), 'User')
```

Open a fresh shell, then continue at **Step 2** above.

---

## The golden rule on Windows

Almost every "command not recognized" problem is the same thing: **the shell was opened before the
tool was installed / before PATH changed.** The fix is always: **close the shell, open a new one.**
When in doubt, do that first.
