# ⚙️ devops-ci-scripts

> A curated collection of PowerShell scripts for CI/CD pipeline automation.

![PowerShell](https://img.shields.io/badge/PowerShell-7.4+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge&logo=opensourceinitiative&logoColor=white)
[![GitGuardian](https://img.shields.io/badge/GitGuardian-protected-purple?style=for-the-badge&logo=gitguardian&logoColor=white)](https://www.gitguardian.com)
[![Mergify](https://img.shields.io/endpoint.svg?url=https://dashboard.mergify.com/badges/YOUR_ORG/gurdip-devops-ci&style=for-the-badge)](https://mergify.com)
[![CodeRabbit](https://img.shields.io/badge/CodeRabbit-reviewed-orange?style=for-the-badge&logo=ai&logoColor=white)](https://coderabbit.ai)

---

## 📋 Overview

**gurdip-devops-ci** contains PowerShell scripts for managing and automating CI/CD pipelines — covering build orchestration, deployment, environment provisioning, and pipeline utilities.

---

## 📁 Repository Structure

```
gurdip-devops-ci/
├── 📂 build/           # Build and compilation scripts
├── 📂 deploy/          # Deployment and release scripts
├── 📂 env/             # Environment setup and provisioning
├── 📂 utils/           # Shared utility functions and helpers
├── 📂 tests/           # Pester unit tests
├── .gitguardian.yaml   # GitGuardian secret scanning config
├── .mergify.yml        # Mergify auto-merge rules
├── .coderabbit.yaml    # CodeRabbit AI review config
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- [PowerShell 7.4+](https://github.com/PowerShell/PowerShell/releases)
- Appropriate permissions for your target environment

### Usage

Clone the repository and run scripts directly:

```powershell
git clone https://github.com/YOUR_ORG/gurdip-devops-ci.git
cd gurdip-devops-ci

# Example: run a deployment script
./deploy/Deploy-Service.ps1 -Environment staging -WhatIf
```

All scripts support `-WhatIf` for dry runs and `-Verbose` for detailed output.

---

## 🛡️ Tooling

| Tool | Purpose |
|---|---|
| 🔐 [GitGuardian](https://www.gitguardian.com) | Secret detection and leak prevention |
| 🔀 [Mergify](https://mergify.com) | Automated PR merging and queue management |
| 🐇 [CodeRabbit](https://coderabbit.ai) | AI-powered code review on every PR |

---

## 🤝 Contributing

1. Fork the repo and create a feature branch
2. Follow [approved PowerShell verbs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)
3. Include comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`) on all functions
4. Add or update Pester tests under `tests/`
5. Open a PR — CodeRabbit and Mergify will handle the rest

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
