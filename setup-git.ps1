# Git Setup Script for KTG Project
# Run this script after Git is installed and added to your PATH

Write-Host "Setting up Git repository for KTG project..." -ForegroundColor Cyan

# Check if git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Git is not installed or not in your PATH." -ForegroundColor Red
    Write-Host "Please install Git from https://git-scm.com/download/win" -ForegroundColor Yellow
    Write-Host "Or add Git to your PATH if it's already installed." -ForegroundColor Yellow
    exit 1
}

# Initialize git repository if not already initialized
if (-not (Test-Path .git)) {
    Write-Host "Initializing Git repository..." -ForegroundColor Green
    git init
} else {
    Write-Host "Git repository already initialized." -ForegroundColor Yellow
}

# Add remote repository
Write-Host "Adding remote repository..." -ForegroundColor Green
git remote remove origin 2>$null
git remote add origin https://github.com/sorensenj00/KTG.git

# Add all files
Write-Host "Staging all files..." -ForegroundColor Green
git add .

# Commit files
Write-Host "Creating initial commit..." -ForegroundColor Green
git commit -m "Initial commit: KillToGrow project"

# Push to remote
Write-Host "Pushing to remote repository..." -ForegroundColor Green
Write-Host "Note: You may need to authenticate with GitHub." -ForegroundColor Yellow
git push -u origin main

Write-Host "`nDone! Your project has been uploaded to GitHub." -ForegroundColor Green
Write-Host "Repository: https://github.com/sorensenj00/KTG.git" -ForegroundColor Cyan

