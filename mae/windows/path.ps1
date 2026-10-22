# Add or remove the MAE Routing folder in the machine PATH (keeps REG_EXPAND_SZ entries like %SystemRoot% intact)
param([string]$Dir, [switch]$Remove)
$key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
$cur = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$parts = @($cur -split ';' | Where-Object { $_ -ne '' -and $_.TrimEnd('\') -ne $Dir.TrimEnd('\') })
if (-not $Remove) { $parts += $Dir }
$key.SetValue('Path', ($parts -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
$key.Close()
# tell Explorer and new shells that the environment changed
[Environment]::SetEnvironmentVariable('MAE_ROUTING_PATH_REFRESH', '1', 'Machine')
[Environment]::SetEnvironmentVariable('MAE_ROUTING_PATH_REFRESH', $null, 'Machine')
