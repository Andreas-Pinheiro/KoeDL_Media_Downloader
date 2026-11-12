param($Url,$Bin)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$pt=$false; try{ $pt=((Get-Content (Join-Path $Bin 'settings.json') -Raw) -replace '\s','') -match '"lang":"pt"' }catch{}
function T($p,$e){ if($pt){ $p }else{ $e } }
$winf=Join-Path $Bin 'win.txt'
function GetWin{ try{ $a=(Get-Content $winf -Raw).Trim().Split(','); if($a.Count -ge 4){ $r=@{x=[int]$a[0];y=[int]$a[1];w=[int]$a[2];h=[int]$a[3];m=($a.Count -ge 5 -and $a[4] -eq '1')}; if($r.w -ge 600 -and $r.h -ge 500){ return $r } } }catch{}; return $null }
function Fallback{
 $w=GetWin; $ar=@("--app=$Url",'--no-first-run',"--user-data-dir=`"$(Join-Path $Bin 'appwin')`"")
 if($w){ $ar+="--window-size=$($w.w),$($w.h)"; $ar+="--window-position=$($w.x),$($w.y)" }else{ $ar+='--window-size=1040,940' }
 foreach($rel in 'Microsoft\Edge\Application\msedge.exe','Google\Chrome\Application\chrome.exe'){ foreach($root in $env:ProgramFiles,${env:ProgramFiles(x86)},$env:LocalAppData){ if($root){ $c=Join-Path $root $rel; if(Test-Path $c){ Start-Process $c -ArgumentList $ar; return } } } }
 Start-Process $Url }
function RtOk{ foreach($k in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}','HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}','HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'){ try{ $v=(Get-ItemProperty $k -ea Stop).pv; if($v -and $v -ne '0.0.0.0'){ return $true } }catch{} }; return $false }
try{
 $d=Join-Path $Bin 'wv2'; $core=Join-Path $d 'Microsoft.Web.WebView2.Core.dll'; $wf=Join-Path $d 'Microsoft.Web.WebView2.WinForms.dll'
 for($i=0;$i -lt 240 -and -not ((Test-Path $core) -and (Test-Path $wf)) -and -not (Test-Path (Join-Path $d 'fail.txt'));$i++){ Start-Sleep -Milliseconds 250 }
 if(-not ((Test-Path $core) -and (Test-Path $wf))){ Fallback; return }
 if(-not (RtOk)){
  $dec=Join-Path $d 'declined.txt'
  if((Test-Path $dec) -and ((Get-Date)-(Get-Item $dec).LastWriteTime).TotalDays -lt 30){ Fallback; return }
  $r=[Windows.Forms.MessageBox]::Show((T "Para abrir o KoeDL em uma janela propria e preciso o Microsoft Edge WebView2 Runtime (gratuito, da Microsoft).`n`nInstalar a ultima versao agora?" "To open KoeDL in its own window it needs the Microsoft Edge WebView2 Runtime (free, from Microsoft).`n`nInstall the latest version now?"),'KoeDL','YesNo','Question')
  if($r -ne 'Yes'){ Set-Content $dec (Get-Date -Format s); Fallback; return }
  $tmp=Join-Path ([IO.Path]::GetTempPath()) 'MicrosoftEdgeWebview2Setup.exe'
  try{ [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 }catch{}
  try{ (New-Object Net.WebClient).DownloadFile('https://go.microsoft.com/fwlink/p/?LinkId=2124703',$tmp); Start-Process $tmp -ArgumentList '/silent','/install' -Wait }catch{}
  if(-not (RtOk)){ [void][Windows.Forms.MessageBox]::Show((T 'Nao consegui instalar o WebView2. Vou abrir no Edge/Chrome.' 'Could not install WebView2. Opening in Edge/Chrome instead.'),'KoeDL'); Fallback; return }
 }
 Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class Nat{ [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern bool SetDllDirectory(string p); }'
 $arch=$(if([Environment]::Is64BitProcess){ 'x64' }else{ 'x86' })
 [void][Nat]::SetDllDirectory((Join-Path $d $arch))
 [void][Reflection.Assembly]::LoadFrom($core); $asm=[Reflection.Assembly]::LoadFrom($wf)
 $tWv=$asm.GetType('Microsoft.Web.WebView2.WinForms.WebView2',$true); $tCp=$asm.GetType('Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties',$true)
 $cp=[Activator]::CreateInstance($tCp); $tCp.GetProperty('UserDataFolder').SetValue($cp,(Join-Path $Bin 'wv2data'),$null)
 $wv=[Activator]::CreateInstance($tWv); $tWv.GetProperty('CreationProperties').SetValue($wv,$cp,$null); $wv.Dock='Fill'
 $f=New-Object Windows.Forms.Form; $f.Text='KoeDL'
 try{ $f.Icon=[Drawing.Icon]::ExtractAssociatedIcon((Join-Path $Bin 'app.ico')) }catch{}
 $w=GetWin; $f.StartPosition='CenterScreen'; $f.Width=1080; $f.Height=980
 if($w){ $vis=$false; foreach($sc in [Windows.Forms.Screen]::AllScreens){ if($sc.WorkingArea.IntersectsWith((New-Object Drawing.Rectangle $w.x,$w.y,$w.w,$w.h))){ $vis=$true } }
  if($vis){ $f.StartPosition='Manual'; $f.Left=$w.x; $f.Top=$w.y; $f.Width=$w.w; $f.Height=$w.h; if($w.m){ $f.WindowState='Maximized' } } }
 $f.Controls.Add($wv)
 $save={ try{ $b=$(if($f.WindowState -eq 'Normal'){ $f.Bounds }else{ $f.RestoreBounds }); $m=$(if($f.WindowState -eq 'Maximized'){ 1 }else{ 0 }); Set-Content $winf "$($b.X),$($b.Y),$($b.Width),$($b.Height),$m" }catch{} }
 $f.add_FormClosing($save); $f.add_ResizeEnd($save)
 $tWv.GetProperty('Source').SetValue($wv,[Uri]$Url,$null)
 $script:ticks=0; $tm=New-Object Windows.Forms.Timer; $tm.Interval=1000
 $tm.add_Tick({ $script:ticks++; $c=$null; try{ $c=$tWv.GetProperty('CoreWebView2').GetValue($wv,$null) }catch{}
  if($c){ $tm.Stop() } elseif($script:ticks -ge 30){ $tm.Stop(); Fallback; $f.Close() } })
 $tm.Start()
 [Windows.Forms.Application]::Run($f)
}catch{ try{ Add-Content (Join-Path $Bin 'app.log') ("wvwin: "+$_.Exception.Message) }catch{}; Fallback }
