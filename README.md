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