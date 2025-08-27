# Changelog

All notable changes to the Power Platform Migration Toolkit will be documented in this file.

## [v2.3.0] - 2025-01-27

### ✨ Added
- **Master runbook orchestrator** (`MigrationRunbook.ps1`)
- **Centralized configuration** (`Config.ps1`)
- **Checkpoint and resume functionality**
- **Comprehensive logging** with `Write-MigrationLog`
- **Visual process diagrams** in documentation
- **User validation with Microsoft Graph**
- **Automated report generation**
- **Error handling and recovery**

### 🔧 Enhanced
- **All individual scripts** optimized with centralized config
- **Environment validation** (Production/Sandbox only)
- **User mapping validation** with detailed feedback
- **Post-migration flow enablement** with bulk operations
- **Documentation** with flow diagrams and best practices

### 🐛 Fixed
- **PowerShell 5.1 compatibility** (removed null coalescing operator)
- **Parameter validation** across all scripts
- **Error handling** with proper exception management
- **File path handling** with absolute paths

### 📋 Changed
- **Unified logging approach** across all scripts
- **Consistent parameter handling** via Config.ps1
- **Improved output organization** in migration-output/
- **Enhanced validation** for environment types

## [v1.0.0] - Initial Release

### ✨ Added
- Basic migration scripts (00-07)
- Individual PowerShell cmdlet wrappers
- Basic error handling
- CSV export functionality