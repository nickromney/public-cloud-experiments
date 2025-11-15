# Application Insights KQL Queries

## Overview

This document contains useful Kusto Query Language (KQL) queries for monitoring the Subnet Calculator React Web App stack deployed in Azure.

**Resources:**

- Log Analytics Workspace: `log-subnetcalc-dev`
- Application Insights: `appi-subnetcalc-dev`
- Function App: `func-subnet-calc-react-api`
- Web App: `web-subnet-calc-react`

## Quick Reference Commands

```bash
# Get Application Insights resource ID
az monitor app-insights component show \
  --app appi-subnetcalc-dev \
  --resource-group rg-subnet-calc \
  --query id -o tsv

# Run a query
az monitor app-insights query \
  --app appi-subnetcalc-dev \
  --resource-group rg-subnet-calc \
  --analytics-query "requests | take 10"
```

## Common Queries

### 1. Request Overview (Last 24 Hours)

**Purpose:** Get overall request statistics

```kql
requests
| where timestamp > ago(24h)
| summarize
    TotalRequests = count(),
    SuccessfulRequests = countif(success == true),
    FailedRequests = countif(success == false),
    AvgDuration = avg(duration),
    P95Duration = percentile(duration, 95)
| extend SuccessRate = round(100.0 * SuccessfulRequests / TotalRequests, 2)
```

### 2. Failed Requests Details

**Purpose:** Investigate failed requests

```kql
requests
| where timestamp > ago(24h)
| where success == false
| project
    timestamp,
    name,
    url,
    resultCode,
    duration,
    cloud_RoleName,
    operation_Id
| order by timestamp desc
| take 50
```

### 3. Response Time Analysis

**Purpose:** Identify slow endpoints

```kql
requests
| where timestamp > ago(24h)
| summarize
    Count = count(),
    AvgDuration = avg(duration),
    P50 = percentile(duration, 50),
    P95 = percentile(duration, 95),
    P99 = percentile(duration, 99)
    by name
| order by P95 desc
```

### 4. Request Volume by Endpoint

**Purpose:** See which endpoints are most used

```kql
requests
| where timestamp > ago(24h)
| summarize RequestCount = count() by name
| order by RequestCount desc
```

### 5. Exceptions and Errors

**Purpose:** Find application errors

```kql
exceptions
| where timestamp > ago(24h)
| project
    timestamp,
    type,
    outerMessage,
    innermostMessage,
    problemId,
    cloud_RoleName,
    operation_Name
| order by timestamp desc
| take 50
```

### 6. Function App Specific - Invocations

**Purpose:** Monitor Azure Function invocations

```kql
requests
| where timestamp > ago(24h)
| where cloud_RoleName == "func-subnet-calc-react-api"
| summarize
    Invocations = count(),
    Successful = countif(success == true),
    Failed = countif(success == false),
    AvgDuration = avg(duration)
    by bin(timestamp, 5m)
| order by timestamp desc
```

### 7. Web App Specific - Page Views

**Purpose:** Monitor frontend usage

```kql
pageViews
| where timestamp > ago(24h)
| where cloud_RoleName == "web-subnet-calc-react"
| summarize PageViews = count() by name
| order by PageViews desc
```

### 8. Dependencies (External Calls)

**Purpose:** Monitor calls from Function App to external services

```kql
dependencies
| where timestamp > ago(24h)
| where cloud_RoleName == "func-subnet-calc-react-api"
| summarize
    CallCount = count(),
    AvgDuration = avg(duration),
    SuccessRate = round(100.0 * countif(success == true) / count(), 2)
    by name, type
| order by CallCount desc
```

### 9. HTTP 404 Errors

**Purpose:** Track 404 Not Found errors

```kql
requests
| where timestamp > ago(24h)
| where resultCode == "404"
| project
    timestamp,
    name,
    url,
    cloud_RoleName,
    client_IP,
    session_Id
| order by timestamp desc
| take 100
```

### 10. Authentication Failures (JWT)

**Purpose:** Monitor JWT authentication issues

```kql
requests
| where timestamp > ago(24h)
| where name contains "login" or url contains "/auth/"
| where resultCode in ("401", "403")
| project
    timestamp,
    name,
    url,
    resultCode,
    cloud_RoleName,
    client_IP
| order by timestamp desc
```

### 11. Performance Degradation

**Purpose:** Compare current performance to baseline

```kql
let baseline = requests
    | where timestamp between (ago(7d) .. ago(1d))
    | summarize BaselineP95 = percentile(duration, 95) by name;
let current = requests
    | where timestamp > ago(1h)
    | summarize CurrentP95 = percentile(duration, 95) by name;
baseline
| join kind=inner current on name
| extend PerformanceChange = round(100.0 * (CurrentP95 - BaselineP95) / BaselineP95, 2)
| where PerformanceChange > 20  // Alert if >20% slower
| project name, BaselineP95, CurrentP95, PerformanceChange
| order by PerformanceChange desc
```

### 12. Availability Monitoring

**Purpose:** Track service uptime

```kql
requests
| where timestamp > ago(24h)
| summarize
    TotalRequests = count(),
    SuccessfulRequests = countif(success == true)
    by bin(timestamp, 5m), cloud_RoleName
| extend Availability = round(100.0 * SuccessfulRequests / TotalRequests, 2)
| order by timestamp desc
```

### 13. Custom Events (Application Logs)

**Purpose:** View custom application logging

```kql
traces
| where timestamp > ago(24h)
| where cloud_RoleName in ("func-subnet-calc-react-api", "web-subnet-calc-react")
| project
    timestamp,
    message,
    severityLevel,
    cloud_RoleName,
    operation_Name
| order by timestamp desc
| take 100
```

### 14. Client-Side Errors (Browser)

**Purpose:** Monitor frontend JavaScript errors

```kql
exceptions
| where timestamp > ago(24h)
| where cloud_RoleName == "web-subnet-calc-react"
| project
    timestamp,
    type,
    outerMessage,
    problemId,
    client_Browser,
    client_OS
| order by timestamp desc
```

### 15. Correlated Requests (End-to-End)

**Purpose:** Track requests across Web App → Function App

```kql
requests
| where timestamp > ago(1h)
| where operation_Id != ""
| join kind=inner (
    dependencies
    | where timestamp > ago(1h)
) on operation_Id
| project
    timestamp,
    FrontendRequest = name,
    BackendCall = name1,
    FrontendDuration = duration,
    BackendDuration = duration1,
    success,
    cloud_RoleName
| order by timestamp desc
```

## Alert Recommendations

### High Error Rate

```kql
requests
| where timestamp > ago(5m)
| summarize
    ErrorRate = 100.0 * countif(success == false) / count()
| where ErrorRate > 5  // Alert if >5% errors
```

### Slow Response Times

```kql
requests
| where timestamp > ago(5m)
| summarize P95 = percentile(duration, 95)
| where P95 > 1000  // Alert if P95 > 1 second
```

### High Exception Rate

```kql
exceptions
| where timestamp > ago(5m)
| summarize ExceptionCount = count()
| where ExceptionCount > 10  // Alert if >10 exceptions in 5 min
```

## Running Queries via Azure CLI

```bash
# Set variables
RESOURCE_GROUP="rg-subnet-calc"
APP_INSIGHTS="appi-subnetcalc-dev"

# Run a query
az monitor app-insights query \
  --app $APP_INSIGHTS \
  --resource-group $RESOURCE_GROUP \
  --analytics-query "requests | where timestamp > ago(1h) | summarize count() by name" \
  --output table

# Export query results to JSON
az monitor app-insights query \
  --app $APP_INSIGHTS \
  --resource-group $RESOURCE_GROUP \
  --analytics-query "requests | where timestamp > ago(24h) | where success == false" \
  --output json > failed-requests.json
```

## Useful Filters

```kql
// Filter by time range
| where timestamp between (datetime(2025-01-01) .. datetime(2025-01-31))

// Filter by specific app
| where cloud_RoleName == "func-subnet-calc-react-api"

// Filter by success/failure
| where success == true  // or false

// Filter by HTTP status code
| where resultCode startswith "5"  // All 5xx errors
| where resultCode == "200"        // Successful requests

// Filter by operation
| where operation_Name contains "calculate"

// Exclude health checks
| where name !contains "health"
```

## Performance Tips

1. **Always specify time range** - Use `where timestamp > ago(24h)` to limit data scanned
2. **Use summarize early** - Aggregate data before projecting/filtering when possible
3. **Limit results** - Use `take` or `top` to limit output size
4. **Use bins for time series** - `bin(timestamp, 5m)` for time-based aggregations
