# win-ssh

One command to install and enable OpenSSH Server on Windows, using Microsoft's official MSI from [PowerShell/Win32-OpenSSH](https://github.com/PowerShell/Win32-OpenSSH) (skips the slow Windows Update / Optional Features install).

Run in **PowerShell as Administrator**:

```powershell
irm https://raw.githubusercontent.com/razas32/win-ssh/main/enable-ssh.ps1 | iex
```

It installs OpenSSH Server, sets `sshd` to start automatically, opens TCP port 22 in the firewall, and prints the `ssh` command to connect.
