# win-ssh

One command to set up a Windows PC for **remote access and Wake-on-LAN** — including waking it from a full shutdown so it acts like a remote power button.

The script installs **OpenSSH Server** + **Tailscale**, enables **Wake-on-LAN** on the wired adapter, and disables **Fast Startup** (which otherwise blocks wake from a full shutdown).

## Use

Run in **PowerShell as Administrator**:

```powershell
irm https://raw.githubusercontent.com/razas32/win-ssh/main/enable-ssh.ps1 | iex
```

When it finishes:

1. Open the **Tailscale sign-in link** it prints and approve the machine on your account.
2. It prints the machine's **Wake MAC address** — note it for waking the PC later (e.g. from the ASUS Router app).

## Wake-from-full-shutdown also needs BIOS settings

Software can't change these — set them once in the BIOS/UEFI:

- **Wake on LAN** / **Power On By PCI-E** / **Resume By PCI-E Device** → **Enabled**
- **ErP / EuP Ready** → **Disabled** (if Enabled, it cuts standby power to the network card and WoL won't work)

Keep the PC on **Ethernet** and **plugged into power** for reliable wake-on-LAN.
