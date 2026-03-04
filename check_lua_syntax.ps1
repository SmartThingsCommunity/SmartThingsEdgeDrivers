# Lua Syntax Checker for simple-metering-config
$files = @(
    "drivers\SmartThings\zigbee-switch\src\simple-metering-config\init.lua",
    "drivers\SmartThings\zigbee-switch\src\simple-metering-config\can_handle.lua",
    "drivers\SmartThings\zigbee-switch\src\simple-metering-config\fingerprints.lua"
)

Write-Host "Checking Lua syntax for simple-metering-config files..." -ForegroundColor Cyan
Write-Host ""

$allOk = $true

foreach ($file in $files) {
    Write-Host "Checking: $file" -ForegroundColor Yellow
    
    if (-not (Test-Path $file)) {
        Write-Host "  ERROR: File not found!" -ForegroundColor Red
        $allOk = $false
        continue
    }
    
    $content = Get-Content $file -Raw -ErrorAction Stop
    
    # Basic syntax checks
    $errors = @()
    
    # Check for balanced parentheses
    $openParens = ([regex]::Matches($content, '\(')).Count
    $closeParens = ([regex]::Matches($content, '\)')).Count
    if ($openParens -ne $closeParens) {
        $errors += "Unbalanced parentheses (open: $openParens, close: $closeParens)"
    }
    
    # Check for balanced braces
    $openBraces = ([regex]::Matches($content, '\{')).Count
    $closeBraces = ([regex]::Matches($content, '\}')).Count
    if ($openBraces -ne $closeBraces) {
        $errors += "Unbalanced braces (open: $openBraces, close: $closeBraces)"
    }
    
    # Check for balanced brackets
    $openBrackets = ([regex]::Matches($content, '\[')).Count
    $closeBrackets = ([regex]::Matches($content, '\]')).Count
    if ($openBrackets -ne $closeBrackets) {
        $errors += "Unbalanced brackets (open: $openBrackets, close: $closeBrackets)"
    }
    
    # Check for proper 'end' statements
    $functions = ([regex]::Matches($content, '\bfunction\b')).Count
    $ends = ([regex]::Matches($content, '\bend\b')).Count
    if ($functions -ne $ends) {
        $errors += "Unbalanced function/end (functions: $functions, ends: $ends)"
    }
    
    # Check for proper 'local' usage (warning only)
    $globals = ([regex]::Matches($content, '^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*=')).Count
    if ($globals -gt 0) {
        Write-Host "  WARNING: Found $globals potential global variable assignments" -ForegroundColor Yellow
    }
    
    if ($errors.Count -eq 0) {
        Write-Host "  OK: Syntax looks good" -ForegroundColor Green
    } else {
        Write-Host "  ERRORS FOUND:" -ForegroundColor Red
        foreach ($error in $errors) {
            Write-Host "    - $error" -ForegroundColor Red
        }
        $allOk = $false
    }
    
    Write-Host ""
}

Write-Host "Summary:" -ForegroundColor Cyan
if ($allOk) {
    Write-Host "  All files passed syntax check!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  Some files have syntax errors!" -ForegroundColor Red
    exit 1
}
