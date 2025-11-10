# Password Hash Escaping Guide

## Problem

Argon2 password hashes contain `$` characters which are special characters in different contexts:

```text
$argon2id$v=19$m=65536,t=3,p=4$TklhcmEkyMzqJaH3KHQQDA$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo
```

## Escaping Rules by Environment

### 1. Terraform `.tfvars` Files

**Use single `$` - no escaping needed**

```hcl
JWT_TEST_USERS = "{\"demo\":\"$argon2id$v=19$m=65536,t=3,p=4$TklhcmEkyMzqJaH3KHQQDA$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo\"}"
```

### 2. Docker Compose YAML

**Use double `$$` - Docker interprets `$$` as literal `$`**

```yaml
environment:
  - JWT_TEST_USERS={"demo":"$$argon2id$$v=19$$m=65536,t=3,p=4$$TklhcmEkyMzqJaH3KHQQDA$$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo"}
```

### 3. Azure App Settings (Portal/CLI/Terraform)

**Use single `$` - no interpretation layer**

Via Azure Portal:

```text
$argon2id$v=19$m=65536,t=3,p=4$TklhcmEkyMzqJaH3KHQQDA$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo
```

Via Azure CLI:

```bash
az functionapp config appsettings set \
  --name func-app \
  --resource-group rg \
  --settings JWT_TEST_USERS='{"demo":"$argon2id$v=19$m=65536,t=3,p=4$TklhcmEkyMzqJaH3KHQQDA$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo"}'
```

### 4. Shell Environment Variables

#### Depends on shell and quoting

Bash with single quotes (no interpolation):

```bash
export JWT_TEST_USERS='{"demo":"$argon2id$v=19$m=65536,t=3,p=4$TklhcmEkyMzqJaH3KHQQDA$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo"}'
```

## Test Credentials

The example uses these test credentials:

| Username | Password | Argon2 Hash |
|----------|----------|-------------|
| demo | password123 | `$argon2id$v=19$m=65536,t=3,p=4$TklhcmEkyMzqJaH3KHQQDA$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo` |
| admin | securepass | `$argon2id$v=19$m=65536,t=3,p=4$JiTJZlTwD/1jJLlMQMOwCA$HbubnE11kzEfcszqKtMOmjvxj14vjooqbdZtgc1NYCs` |

## Verification

To verify the hash is correct in your environment:

```bash
# Check what the application actually receives
podman exec <container> printenv JWT_TEST_USERS

# Should show SINGLE $ in the hash:
# {"demo":"$argon2id$v=19$m=65536,t=3,p=4$TklhcmEkyMzqJaH3KHQQDA$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo",...}
```

## Best Practice: Azure Key Vault

For production, store JWT_TEST_USERS in Azure Key Vault and reference it:

```hcl
# Reference from Key Vault
JWT_TEST_USERS = "@Microsoft.KeyVault(SecretUri=https://vault.vault.azure.net/secrets/jwt-test-users/)"
```

This avoids escaping issues entirely and provides better security.
