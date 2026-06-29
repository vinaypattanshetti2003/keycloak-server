# Step 1: validate Render Postgres settings and optionally test connectivity.
param(
    [switch]$CheckConfigOnly
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$envFile = Join-Path $repoRoot ".env"
$exampleFile = Join-Path $repoRoot ".env.example"

function Write-Check {
    param([string]$Label, [bool]$Passed, [string]$Detail)
    $icon = if ($Passed) { "[OK]" } else { "[FAIL]" }
    Write-Host "$icon $Label" -ForegroundColor $(if ($Passed) { "Green" } else { "Red" })
    if ($Detail) { Write-Host "     $Detail" }
}

function Get-EnvMap {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path $Path)) { return $map }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { return }
        $key = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim()
        $map[$key] = $value
    }
    return $map
}

function Test-JdbcUrl {
    param([string]$JdbcUrl)
    if ($JdbcUrl -notmatch "^jdbc:postgresql://([^:/]+):(\d+)/([^?]+)$") {
        return $null
    }
    return @{
        Host     = $Matches[1]
        Port     = [int]$Matches[2]
        Database = $Matches[3]
    }
}

Write-Host "`n=== Step 1: Postgres verification ===`n" -ForegroundColor Cyan

$sourceFile = if (Test-Path $envFile) { $envFile } else { $exampleFile }
$envMap = Get-EnvMap -Path $sourceFile
$usingExample = $sourceFile -eq $exampleFile

Write-Check "Config file found" $true $(if ($usingExample) { "Using .env.example (.env not created yet)" } else { "Using .env" })

$required = @("KC_DB", "KC_DB_URL", "KC_DB_USERNAME")
$missing = $required | Where-Object { -not $envMap.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($envMap[$_]) }
Write-Check "Required variables present" ($missing.Count -eq 0) $(if ($missing.Count -gt 0) { "Missing: $($missing -join ', ')" } else { "KC_DB, KC_DB_URL, KC_DB_USERNAME" })

$dbTypeOk = $envMap["KC_DB"] -eq "postgres"
Write-Check "KC_DB is postgres" $dbTypeOk $(if (-not $dbTypeOk) { "Expected 'postgres', got '$($envMap['KC_DB'])'" })

$parsed = Test-JdbcUrl -JdbcUrl $envMap["KC_DB_URL"]
$jdbcOk = $null -ne $parsed
Write-Check "KC_DB_URL format" $jdbcOk $(if ($jdbcOk) { "$($parsed.Host):$($parsed.Port)/$($parsed.Database)" } else { "Expected jdbc:postgresql://host:port/database" })

$expected = @{
    Host     = "dpg-d9l5osb7u1mc739tm94g-a"
    Port     = 5432
    Database = "keycloak_v39s"
    Username = "keycloak"
}

if ($jdbcOk) {
    Write-Check "Internal hostname" ($parsed.Host -eq $expected.Host) "Expected $($expected.Host)"
    Write-Check "Port" ($parsed.Port -eq $expected.Port) "Expected $($expected.Port)"
    Write-Check "Database name" ($parsed.Database -eq $expected.Database) "Expected $($expected.Database)"
}

$userOk = $envMap["KC_DB_USERNAME"] -eq $expected.Username
Write-Check "Username" $userOk "Expected $($expected.Username)"

$hasPassword = $envMap.ContainsKey("KC_DB_PASSWORD") -and -not [string]::IsNullOrWhiteSpace($envMap["KC_DB_PASSWORD"])
Write-Check "Password configured" $hasPassword $(if (-not $hasPassword) { "Set KC_DB_PASSWORD in .env for live connection test" })

$configOk = $dbTypeOk -and $jdbcOk -and $userOk -and ($missing.Count -eq 0) -and
    ($parsed.Host -eq $expected.Host) -and ($parsed.Port -eq $expected.Port) -and ($parsed.Database -eq $expected.Database)

if ($CheckConfigOnly) {
    Write-Host ""
    if ($configOk) {
        Write-Host "Config validation passed." -ForegroundColor Green
    } else {
        Write-Host "Config validation failed." -ForegroundColor Red
        exit 1
    }
    exit 0
}

if (-not $configOk) {
    Write-Host "`nFix config issues before testing connectivity." -ForegroundColor Red
    exit 1
}

if (-not $hasPassword -and -not $envMap.ContainsKey("DATABASE_URL")) {
    Write-Host "`nCopy .env.example to .env and add KC_DB_PASSWORD (or DATABASE_URL) to run a live test." -ForegroundColor Yellow
    Write-Host "Config structure is correct for Render internal networking.`n" -ForegroundColor Green
    exit 0
}

$databaseUrl = $envMap["DATABASE_URL"]
if ([string]::IsNullOrWhiteSpace($databaseUrl)) {
    $hostExternal = "$($expected.Host).oregon-postgres.render.com"
    $password = $envMap["KC_DB_PASSWORD"]
    $databaseUrl = "postgresql://$($expected.Username):$password@${hostExternal}:$($expected.Port)/$($expected.Database)"
}

Write-Host "`nTesting live database connection (external host)...`n" -ForegroundColor Cyan

$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Check "Docker available" $false "Install Docker to run connection test from this machine"
    exit 1
}
Write-Check "Docker available" $true $docker.Source

$testQuery = "SELECT version();"
docker run --rm postgres:16-alpine psql "$databaseUrl" -c $testQuery
if ($LASTEXITCODE -eq 0) {
    Write-Host "`nLive connection test passed." -ForegroundColor Green
    exit 0
}

Write-Host "`nLive connection test failed. Verify password and External Database URL in Render." -ForegroundColor Red
exit 1
