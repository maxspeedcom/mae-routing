# Exit 1 (and print the adapter) when another VPN client holds an address in 100.64.0.0/10
$hit = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
  $o = $_.IPAddress.Split('.')
  $_.InterfaceAlias -ne 'MAE Routing' -and $o[0] -eq '100' -and [int]$o[1] -ge 64 -and [int]$o[1] -le 127
} | Select-Object -First 1
if ($hit) { Write-Output "$($hit.InterfaceAlias) $($hit.IPAddress)"; exit 1 }
exit 0
