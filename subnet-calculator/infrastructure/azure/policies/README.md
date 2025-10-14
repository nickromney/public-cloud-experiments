# Azure API Management Policies

APIM policy XML files for different authentication modes.

## Policy Files

### inbound-none.xml

#### Open Access - No Authentication

- No authentication required
- Rate limiting: 100 requests/minute per IP address
- CORS: Allow all origins
- Use case: Development, public APIs

### inbound-subscription.xml

#### Subscription Key Authentication

- Requires `Ocp-Apim-Subscription-Key` header
- Rate limiting: 100 requests/minute per subscription
- Injects `X-User-ID` and `X-User-Name` headers for Function App
- CORS: Allow all origins
- Use case: Controlled access with API keys (works in Pluralsight sandbox)

### inbound-jwt.xml

#### JWT Token Validation (Azure Entra ID)

- Validates JWT tokens against Azure AD/Entra ID
- Extracts user claims (email, subject)
- Injects `X-User-Email` and `X-User-ID` headers for Function App
- Rate limiting: 100 requests/minute per user
- CORS: Specific origin only (enhanced security)
- Use case: Production SSO with Entra ID

**Note:** JWT policy requires Azure Entra ID, which is **NOT SUPPORTED in Pluralsight sandbox**. This policy is provided for reference and future use in full Azure environments.

## Policy Structure

All policies follow the standard APIM structure:

```xml
<policies>
 <inbound>
 <!-- Pre-processing: auth, rate limiting, CORS, header injection -->
 </inbound>
 <backend>
 <!-- Backend communication -->
 </backend>
 <outbound>
 <!-- Post-processing: response headers, cleanup -->
 </outbound>
 <on-error>
 <!-- Error handling -->
 </on-error>
</policies>
```

## Function App Integration

When `AUTH_METHOD=apim` is set in the Function App, it expects these headers:

- **X-User-Email**: User's email address (preferred)
- **X-User-ID**: User's unique identifier (fallback)

APIM policies inject these headers based on the authentication method:

- **Subscription mode**: Uses subscription ID and name
- **JWT mode**: Extracts from token claims

## Rate Limiting

All policies include rate limiting to prevent abuse:

- **None mode**: 100 requests/minute per IP
- **Subscription mode**: 100 requests/minute per subscription
- **JWT mode**: 100 requests/minute per user

Adjust the `calls` and `renewal-period` values as needed.

## CORS Configuration

**Development (None/Subscription modes):**

```xml
<origin>*</origin>
```

**Production (JWT mode):**

```xml
<origin>https://your-specific-domain.azurestaticapps.net</origin>
```

## Applying Policies

Use the `32-apim-policies.sh` script to apply policies:

```bash
# No authentication (open access)
AUTH_MODE=none ./32-apim-policies.sh

# Subscription key authentication
AUTH_MODE=subscription ./32-apim-policies.sh

# JWT authentication (requires Entra ID configuration)
AUTH_MODE=jwt ./32-apim-policies.sh
```

## Customization

### Change Rate Limits

Edit the `rate-limit-by-key` element:

```xml
<rate-limit-by-key calls="200"
 renewal-period="60"
 counter-key="@(context.Subscription.Id)" />
```

### Add Custom Headers

```xml
<set-header name="X-Custom-Header" exists-action="override">
 <value>custom-value</value>
</set-header>
```

### Modify CORS Origins

```xml
<allowed-origins>
 <origin>https://app1.example.com</origin>
 <origin>https://app2.example.com</origin>
</allowed-origins>
```

## Testing Policies

### Test with curl

**No auth:**

```bash
curl https://apim-name.azure-api.net/subnet-calc/api/v1/health
```

**Subscription key:**

```bash
curl -H "Ocp-Apim-Subscription-Key: your-key" \
 https://apim-name.azure-api.net/subnet-calc/api/v1/health
```

**JWT token:**

```bash
curl -H "Authorization: Bearer your-jwt-token" \
 https://apim-name.azure-api.net/subnet-calc/api/v1/health
```

## References

- [APIM Policy Reference](https://learn.microsoft.com/en-us/azure/api-management/api-management-policies)
- [APIM Policy Expressions](https://learn.microsoft.com/en-us/azure/api-management/api-management-policy-expressions)
- [validate-jwt Policy](https://learn.microsoft.com/en-us/azure/api-management/validate-jwt-policy)
- [rate-limit-by-key Policy](https://learn.microsoft.com/en-us/azure/api-management/rate-limit-by-key-policy)
