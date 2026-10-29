# <img src="docs/icon.png" width="44" align="absmiddle" alt=""> Courier

Drop a file on Courier and it lands on your dev box, with its path pasted into your coding agent.

When Claude Code runs on another machine, dragging a screenshot into it does nothing, because the file is on your Mac. Courier copies it over and gives the agent the path.

<table>
  <tr>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/home-dark.png">
        <img src="docs/screenshots/home-light.png" alt="The Courier window: a drop area, your devices with their folders, and recently sent files">
      </picture>
    </td>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/settings-dark.png">
        <img src="docs/screenshots/settings-light.png" alt="Courier settings">
      </picture>
    </td>
  </tr>
</table>

- Send any file or folder, or what's on your clipboard, like a screenshot.
- Pick a folder for each machine.
- See progress, and a list of what you've sent.
- If the machine runs [Rex](https://docs.superlogical.com), the path is pasted straight into Claude Code, Codex, Cursor, and other agents. Otherwise it's on your clipboard.

## What you need

- A Mac on macOS 14 or later, with Apple's command line tools (`xcode-select --install`).
- [Tailscale](https://tailscale.com) on your Mac and the machines you send to.
- SSH to those machines without a password. The easy way: run `sudo tailscale set --ssh` on each one. To check, `ssh <machine> true` should work without asking anything.

## Install

```sh
git clone https://github.com/abhi-reducto/courier.git
cd courier
./install.sh
```

Courier shows up in your menu bar. Run `./install.sh` again after pulling updates.

**Or ask a coding agent to do it.** Paste this into Claude Code or Codex:

> Clone github.com/abhi-reducto/courier, read AGENTS.md, and run ./install.sh. If something fails, fix it and tell me what you changed. Then check that `ssh <my machine> true` works.

## Using it

- **Send:** drag files onto the menu bar icon, the Courier window, or a machine in the window's list. Or use **Send Clipboard** after copying a screenshot or files.
- **Choose where it goes:** click a machine to select it. Click its folder to change it.
- **After sending:** the path is on your clipboard, or already pasted if you use Rex.
- **Settings** (the gear, or ⌘,): show Courier in the Dock or menu bar, open at login, and auto-paste.

## With Rex

Courier can paste the path into the terminal where your agent is running.

1. Add the machine as a Rex host on your Mac, using the same name as in Tailscale.
2. In Rex.app → Settings → Rex Server, turn on **Remote Control**. That lets Courier paste into the pane you're looking at.
3. In Courier's settings, tick the agents you use.

Courier only pastes. It never presses Return.

## If something goes wrong

| Courier says | Try |
|---|---|
| Couldn't reach *machine* | Make sure it's online in Tailscale and `ssh <machine> true` works. |
| *machine* turned down the SSH login | Turn on Tailscale SSH there, or add your SSH key. |
| SSH doesn't trust *machine* yet | Run `ssh <machine>` once in Terminal and say yes. |
| Nothing to send | Copy a file or an image first. |

Logs are in `~/Library/Logs/Courier.log`.

## More

- **Command line:** `RIMG_HOST=<machine> rimg file.png` sends files without the app.
- **Changing Courier:** see [`AGENTS.md`](AGENTS.md).
- **Icons:** [Lucide](https://lucide.dev) (ISC) and Apple's SF Symbols.
