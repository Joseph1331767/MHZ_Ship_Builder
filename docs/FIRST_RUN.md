# First-Run Checklist (the 4 manual steps)

Do these top to bottom, once. Each step says exactly which app you're in.
If you get stuck, note the step number — that's all I need to help.

---

## ✅ STEP 1 — In GODOT: enable the two plugins

You may have already done this.

1. Open **Godot 4.7**.
2. Project Manager → **Import** → Browse to `D:\soft\claude_adventures\project.godot` → **Open** → **Import & Edit**.
3. Top menu: **Project → Project Settings…**
4. Click the **Plugins** tab (row of tabs across the top).
5. Tick **Enabled** for both **gdUnit4** and **Godot AI**.
6. Click **Close**.
7. A **Godot AI** panel appears (bottom or right). It runs a server on port 8000.

**How to know Step 1 worked:** the Godot AI panel is visible and doesn't show an error.
👉 **Leave Godot open** for Step 2.

---

## ✅ STEP 2 — In a POWERSHELL WINDOW: run Claude Code

⚠️ The trust/approval questions in this step happen **here, in the black PowerShell/Claude window** — NOT in Antigravity. Don't mix this up with Step 3.

1. Open a **brand-new** PowerShell window (Start menu → type `PowerShell` → Enter).
   (New window matters — it's what makes the `claude` command work.)
2. Type this, press Enter:
   ```
   cd D:\soft\claude_adventures
   ```
3. Type this, press Enter:
   ```
   claude
   ```
4. **Only if** it says *"claude is not recognized"* → close this window, open another new PowerShell, try again. To double-check it's installed, run: `where.exe claude` (should print a file path).
5. The first time, Claude may ask **one or two** questions. Answer them like this:
   - *"Do you trust the files in this folder?"* → pick **Yes / proceed**.
   - *"This project defines MCP servers… enable them?"* → pick **Yes / approve**.
   - (If it asks nothing and just shows a prompt, that's fine too — move on.)
6. At the Claude prompt, type this and press Enter:
   ```
   /mcp
   ```
7. Read the list:
   - **context7** should say **connected**.
   - **godot-ai** should say **connected** (because Godot is still open from Step 1).
   - If godot-ai says *failed/not connected* → Godot isn't open or the Godot AI plugin isn't enabled. Redo Step 1, then `/mcp` again.
8. To leave Claude: type `/exit` and Enter (or press `Ctrl+C` twice).

**How to know Step 2 worked:** `/mcp` showed context7 connected (and godot-ai connected while Godot is open).

---

## ✅ STEP 3 — In ANTIGRAVITY: open the folder

This step has **no MCP approval prompts** — that was Step 2. Here you just open the folder.

1. Open **Antigravity**.
2. Menu **File → Open Folder…**
3. Select the folder **`D:\soft\claude_adventures`** → **Select Folder**.
4. If asked *"Do you trust the authors of the files?"* → **Yes, I trust the authors**.
5. That's it — Antigravity reads `AGENTS.md` and `GEMINI.md` on its own.
6. (Optional) To see the MCP servers in **Antigravity 2.0**, either:
   - **Agent panel** → click the **`...`** dropdown at the top → **MCP Servers** → **Manage MCP Servers** (→ **View raw config** to see the JSON), OR
   - **Settings** (bottom-left) → **Customizations** → **Installed MCP Servers** → **Refresh**.
   - You're looking for **godot-ai** and **context7**. If they don't appear, Antigravity may only be reading the *global* config (`~/.gemini/config/mcp_config.json`) — ask Claude to copy the servers there.

**How to know Step 3 worked:** the folder's files show in Antigravity's left sidebar and it opened without errors.

---

## ✅ STEP 4 — Push to GitHub (do this last)

Ask Claude (me) to help with this one when you're ready — there's a small choice to make first
(whether to include the downloaded plugin folders). We'll do it together in one go.

---

### Cheat sheet: which window am I supposed to be in?
| Step | App / window |
|---|---|
| 1 | **Godot** editor |
| 2 | **PowerShell** (black window running `claude`) — *all approval questions happen here* |
| 3 | **Antigravity** (just Open Folder) |
| 4 | **PowerShell** again (git) — ask Claude to guide you |
