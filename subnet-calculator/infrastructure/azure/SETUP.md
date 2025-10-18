# Azure Deployment Setup Guide

## Quick Start

### 1. Install direnv

```bash
brew install direnv
```

### 2. Setup your shell

Add direnv hook to your shell configuration:

**Bash** (`~/.bashrc`):

```bash
eval "$(direnv hook bash)"
```

**Zsh** (`~/.zshrc`):

```bash
eval "$(direnv hook zsh)"
```

**Nushell** (0.66+) - add to `~/.config/nushell/config.nu`:

Option 1 - Load on directory change (recommended):

```nushell
$env.config.hooks.env_change.PWD = [
  { || if (which direnv | is-empty) { return }; direnv export json | from json | default {} | load-env }
]
```

Option 2 - Load on every prompt:

```nushell
$env.config.hooks.pre_prompt = [
  { || if (which direnv | is-empty) { return }; direnv export json | from json | default {} | load-env }
]
```

Then reload your shell:

```bash
exec $SHELL
```

### 3. Create your `.env` file

```bash
cd subnet-calculator/infrastructure/azure
cp .env.example .env
```

Edit `.env` with your Azure subscription details (use simple `KEY=VALUE` format - no `export` needed):

```bash
RESOURCE_GROUP=rg-subnet-calc
LOCATION=uksouth
PUBLISHER_EMAIL=your-email@example.com
```

**Important:** The `.env` file format is shell-agnostic (`KEY=VALUE`). The `.envrc` file handles loading it correctly for all shells (bash, zsh, nushell, etc.).

### 4. Allow direnv

```bash
direnv allow
```

You'll see:

```text
direnv: loading .envrc
direnv: export +RESOURCE_GROUP +LOCATION +PUBLISHER_EMAIL
```

## Verification

Check that variables are loaded:

```bash
cd subnet-calculator/infrastructure/azure
echo $RESOURCE_GROUP  # Should print: rg-subnet-calc
```

Or see all loaded variables:

```bash
direnv export bash
```

## Manual Override

You can still manually set variables without direnv:

```bash
# This will override any direnv variables
export RESOURCE_GROUP="rg-custom"
./40-link-backend-to-swa.sh
```

## Troubleshooting

### Variables not loading

```bash
# Check if direnv is working
direnv status

# Explicitly allow the directory
direnv allow

# Check the .envrc file
cat .envrc
```

### Variables still not set after `direnv allow`

Reload your shell:

```bash
exec $SHELL
```

Or manually source:

```bash
source .env
```

## Security Notes

- `.env` is in `.gitignore` - never accidentally committed
- `.envrc` is committed (safe, just direnv config)
- Use `.env.local` for machine-specific overrides (also in `.gitignore`)
- Never put secrets directly in scripts - always use environment variables

## See Also

- [direnv Documentation](https://direnv.net/)
- [Azure CLI Authentication](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli)
- [.env.example](.env.example) - Configuration template
