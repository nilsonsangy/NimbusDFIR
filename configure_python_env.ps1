# PowerShell Script: configure_python_env.ps1
# Purpose: Set up Python virtual environment, activate it, upgrade pip, and install dependencies.

# Path to the virtual environment
$venvPath = Join-Path $PSScriptRoot 'venv'

# Step 1: Create virtual environment if it doesn't exist
if (-not (Test-Path $venvPath)) {
    Write-Host 'Creating virtual environment in "venv"...'
    python -m venv $venvPath
} else {
    Write-Host 'Virtual environment "venv" already exists.'
}

# Step 2: Activate the virtual environment
$activateScript = Join-Path $venvPath 'Scripts\Activate.ps1'
Write-Host 'Activating virtual environment...'
. $activateScript

# Step 3: Upgrade pip to the latest version
Write-Host 'Upgrading pip...'
python -m pip install --upgrade pip
Write-Host 'pip successfully upgraded.'

# Step 4: Install dependencies from requirements.txt
$requirementsPath = Join-Path $PSScriptRoot 'requirements.txt'
if (Test-Path $requirementsPath) {
    Write-Host 'Installing dependencies from requirements.txt...'
    pip install -r $requirementsPath
    Write-Host 'Dependencies installed successfully.'
} else {
    Write-Warning 'requirements.txt not found in the current directory.'
}

Write-Host 'Python environment setup complete.'
