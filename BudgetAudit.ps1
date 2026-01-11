#Requires -Modules Az.Accounts, Az.Billing, Az.ResourceGraph

<#
.SYNOPSIS
    Audits all Azure subscriptions to identify those without defined budgets.

.DESCRIPTION
    This script retrieves all subscriptions the user has access to and checks
    whether each subscription has at least one budget defined. Outputs a report
    of subscriptions without budgets.

.EXAMPLE
    .\Audit-AzureBudgets.ps1 -OutputPath "C:\Reports\BudgetAudit.csv"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\BudgetAuditReport.csv"
)

# Connect to Azure
Connect-AzAccount

# Get all subscriptions
Write-Host "Retrieving all subscriptions..." -ForegroundColor Cyan
$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
Write-Host "Found $($subscriptions.Count) enabled subscriptions." -ForegroundColor Green

# Initialize results array
$results = @()

foreach ($sub in $subscriptions) {
    Write-Host "Checking subscription: $($sub.Name) ($($sub.Id))" -ForegroundColor Yellow
    
    # Set subscription context
    Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue | Out-Null
    
    try {
        # Get budgets for subscription
        $budgets = Get-AzConsumptionBudget -ErrorAction SilentlyContinue
        
        $budgetCount = if ($budgets) { $budgets.Count } else { 0 }
        $hasBudget = $budgetCount -gt 0
        
        $results += [PSCustomObject]@{
            SubscriptionName = $sub.Name
            SubscriptionId   = $sub.Id
            State            = $sub.State
            HasBudget        = $hasBudget
            BudgetCount      = $budgetCount
            BudgetNames      = if ($budgets) { ($budgets.Name -join "; ") } else { "None" }
        }
        
        if (-not $hasBudget) {
            Write-Host "  [!] No budgets defined" -ForegroundColor Red
        } else {
            Write-Host "  [✓] $budgetCount budget(s) found" -ForegroundColor Green
        }
        
    } catch {
        Write-Warning "Failed to retrieve budgets for subscription $($sub.Name): $_"
        $results += [PSCustomObject]@{
            SubscriptionName = $sub.Name
            SubscriptionId   = $sub.Id
            State            = $sub.State
            HasBudget        = "Error"
            BudgetCount      = 0
            BudgetNames      = "Error: $_"
        }
    }
}

# Export results
$results | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "`nAudit complete. Report saved to: $OutputPath" -ForegroundColor Green

# Display summary
$subsWithoutBudgets = $results | Where-Object { $_.HasBudget -eq $false }
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Subscriptions: $($results.Count)" -ForegroundColor White
Write-Host "Subscriptions with Budgets: $($results.Count - $subsWithoutBudgets.Count)" -ForegroundColor Green
Write-Host "Subscriptions WITHOUT Budgets: $($subsWithoutBudgets.Count)" -ForegroundColor Red

if ($subsWithoutBudgets.Count -gt 0) {
    Write-Host "`nSubscriptions WITHOUT Budgets:" -ForegroundColor Yellow
    $subsWithoutBudgets | Format-Table SubscriptionName, SubscriptionId -AutoSize
}
