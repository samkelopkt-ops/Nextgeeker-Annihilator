# Nextgeeker-Annihilator
### Digital Sovereignty & Browser Hijacker Eradication Utility

**Nextgeeker-Annihilator** is a robust, security-focused PowerShell utility designed to detect and purge sophisticated browser hijackers that exploit local Group Policies, registry persistence, and orphaned extension profiles. 

In an era of aggressive software overreach, this tool restores the user's right to define their browser environment by systematically dismantling unauthorized configuration locks.

---

## 🚀 Mission Statement
Software should empower the user, not imprison their configuration. When "imperialist" persistence vectors—like forced extensions and locked browser policies—interfere with your autonomy, this utility serves as the definitive remediation agent. **Liberate your browser.**

## 🛡️ Key Features
* **Behavioral Anomaly Detection:** Identifies malicious persistence by scanning for orphaned extension IDs, unauthorized policy nodes, and hijacked shortcuts.
* **Safety-First Remediation:** Includes a mandatory pre-removal backup module and triggers native Windows System Restore Point creation.
* **Policy Neutralization:** Purges unauthorized `HKLM/HKCU` policy trees that lock search engines and homepages.
* **Cross-Browser Support:** Cleans Chrome, Edge, and Brave profiles simultaneously.
* **Read-Only Audit Mode:** Allows for thorough scanning and reporting before any modifications are committed.

## 📋 Quick Start
1.  **Launch PowerShell as Administrator.**
2.  **Execute Audit:**
    ```powershell
    .\NextgeekerAnnihilator.ps1 -ScanOnly
    ```
3.  **Perform Eradication:**
    ```powershell
    .\NextgeekerAnnihilator.ps1
    ```

## ⚠️ Disclaimer
This tool makes modifications to system-level registry keys and file directories. Always review the scan report before proceeding with automated removal. While this utility includes comprehensive backup mechanisms, the user assumes responsibility for all system modifications.

## 🤝 Contributing
Open-source collaboration is the foundation of digital freedom. Pull requests, optimization suggestions, and new detection signatures are welcomed. Let us continue to sharpen this tool against the forces of intrusive software.

## ⚙️ Technology Stack
*   **Language:** PowerShell 5.1
*   **Platform:** Windows 11 (tested, compatible with Windows 10)
*   **Dependencies:** Native Windows PowerShell cmdlets and executables (e.g., `reg.exe`, `schtasks.exe`, `gpupdate.exe`)

## 🛠️ Setup Instructions

1.  **Download:** Clone this repository or download the `NextgeekerAnnihilator.ps1` script to your local machine.
2.  **Execution Policy:** Ensure your PowerShell execution policy allows script execution. You may need to run the script with the `-ExecutionPolicy Bypass` flag.
    ```powershell
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```
    Or, run directly:
    ```powershell
    powershell -ExecutionPolicy Bypass -File .\NextgeekerAnnihilator.ps1
    ```
3.  **Administrator Privileges:** The script requires administrator privileges to modify system-level settings. It will attempt to self-elevate via UAC if run as a standard user.

## 📊 Visual Badges
[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/scripting/powershell-scripting-language-reference)
[![Platform](https://img.shields.io/badge/Platform-Windows-informational.svg)](https://www.microsoft.com/en-us/windows)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://img.shields.io/badge/Build-Stable-brightgreen.svg)](https://github.com/samkelopkt-ops/Nextgeeker-Annihilator/actions)
[![Security](https://img.shields.io/badge/Security-Audit-orange.svg)](https://github.com/samkelopkt-ops/Nextgeeker-Annihilator/security)