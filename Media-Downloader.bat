@echo off
rem Media Downloader - by Bibinho1999 - github.com/Bibinho1999/Media-Downloader
chcp 65001 >nul
title Media Downloader - nao feche esta janela
set "SELF=%~f0"
powershell -NoProfile -Command "$f=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8);$c=$f.Substring($f.LastIndexOf('###'+'PS###')+8);& ([scriptblock]::Create($c))"
echo.
echo Encerrado. Pressione uma tecla para fechar.
pause >nul
exit /b
###PS###
$ErrorActionPreference='Continue'
try{ [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 }catch{}
try{ [Console]::OutputEncoding=[Text.Encoding]::UTF8 }catch{}
$WIN = -not ($IsLinux -or $IsMacOS)
$TEST = [bool]$env:YTDL_TEST
$self=$env:SELF
$dir=$(if($env:YTDL_DIR){ $env:YTDL_DIR }else{ Split-Path $self })
$bin=[IO.Path]::Combine($dir,'bin'); $arc=[IO.Path]::Combine($bin,'archives')
New-Item -ItemType Directory -Force $bin,$arc | Out-Null
$sep=[IO.Path]::PathSeparator
$env:PATH="$bin$sep$env:PATH"; $env:PYTHONUTF8='1'
$yt=$(if($env:YTDL_BIN){ $env:YTDL_BIN }elseif($WIN){ [IO.Path]::Combine($bin,'yt-dlp.exe') }else{ [IO.Path]::Combine($bin,'yt-dlp') })
$settingsFile=[IO.Path]::Combine($bin,'settings.json')
$APPVER='2.0'

# ------------------------------------------------------------------ estado compartilhado
$S=[hashtable]::Synchronized(@{running=$false;status='Parado';pct=0;speed='';eta='';item='';cur='';browser='';done=0;total=0;pid=0;lpid=0;ipid=0;stop=$false;
 ready=$false;prep='Iniciando...';ver=@{};win=$WIN;test=$TEST;yt=$yt;bin=$bin;dir=$dir;rc=$false;jsr=$false;payload='';exeok=$false;
 info=@{busy=$false};lastBrowser=-1})
$S.log=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$S.fails=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$S.alts=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
$PL=[hashtable]::Synchronized(@{busy=$false;title='';err='';stop=$false})
$PL.items=[Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))

# ------------------------------------------------------------------ funcoes comuns (reusadas nos runspaces)
$lib=@'
function J{ [IO.Path]::Combine([string[]]$args) }
function L($m){ [void]$S.log.Add([string]$m); if($S.log.Count -gt 600){ $S.log.RemoveRange(0,100) } }
function IntOf($v){ $i=0; if([int]::TryParse("$v",[ref]$i)){ return $i } ; return 0 }
function Sanit($s){ $r=(("$s" -replace '[\\/:*?"<>|]','_') -replace '%','%%').Trim().TrimEnd('.'); if(-not $r){ $r='Playlist' }; return $r }
function Md5($t){ ([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($t))) -replace '-','') }
function Cfg($a){
 $p=J ([IO.Path]::GetTempPath()) ('ytcfg_'+[guid]::NewGuid().ToString('N')+'.txt')
 $t='# coding: utf-8'+"`n"+(($a|ForEach-Object{ '"'+((([string]$_) -replace '\\','/') -replace '"','\"')+'"' }) -join "`n")
 [IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding $false)); return $p }
function KillTree($id){ if(-not $id){ return }
 if($S.win){ & taskkill /PID $id /T /F *>$null } else { try{ & pkill -P $id *>$null; & kill $id *>$null }catch{} } }
function Spawn($cfg,$key){
 $psi=New-Object Diagnostics.ProcessStartInfo
 if($S.win){ $psi.FileName=$env:ComSpec; $psi.Arguments='/c "chcp 65001>nul & "'+$S.yt+'" --ignore-config --config-locations "'+$cfg+'" 2>&1"' }
 else{ $psi.FileName='/bin/sh'; [void]$psi.ArgumentList.Add('-c'); [void]$psi.ArgumentList.Add('"'+$S.yt+'" --ignore-config --config-locations "'+$cfg+'" 2>&1') }
 $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.CreateNoWindow=$true; $psi.StandardOutputEncoding=[Text.Encoding]::UTF8
 $p=[Diagnostics.Process]::Start($psi); $S[$key]=$p.Id; return $p }
function Cap($a,$key){ $cfg=Cfg $a; $p=Spawn $cfg $key; $t=$p.StandardOutput.ReadToEnd(); $p.WaitForExit(); $S[$key]=0; Remove-Item $cfg -ea 0; return ($t -split "`r?`n") }
function Why($m){ switch -regex ($m){
  'country|geo' {return 'Bloqueado no seu pais (tente VPN)'}
  'claimed|copyright|UMG|SME|WMG|Sony|Warner' {return 'Bloqueado por direitos autorais'}
  'terminated' {return 'Canal encerrado'}
  'Private video|is private|private' {return 'Video privado'}
  'removed by the uploader|has been removed|was deleted' {return 'Removido pelo autor'}
  'confirm your age|age-restricted|\bage\b' {return 'Restrito por idade (use cookies de conta logada)'}
  'members|Join this channel' {return 'Exclusivo para membros'}
  'live event|premiere|will begin' {return 'Live/estreia ainda indisponivel'}
  'DRM' {return 'Protegido por DRM (nao e possivel baixar)'}
  'Unsupported URL' {return 'Link/site nao suportado'}
  'HTTP Error 404|not found|Not Found' {return 'Nao encontrado (404)'}
  'HTTP Error 403|Forbidden' {return 'Acesso negado (403)'}
  '[Ll]ogin|[Ss]ign in|authenticat' {return 'Exige login (marque um navegador com a conta logada)'}
  'unavailable|not available' {return 'Indisponivel'}
  default {return $m} } }
function UpdYt{ $ch=$S.chan; if(-not $ch){ $ch='stable' }
 L "Atualizando yt-dlp ($ch)..."
 try{ foreach($x in (& $S.yt --update-to $ch 2>&1)){ L "$x" } }catch{ L "(falha ao atualizar: $($_.Exception.Message))" } }
function Run($u,$c,$base,$o,$fl){
 $cfg=Cfg ($base+$c+@($u))
 $p=Spawn $cfg 'pid'; $S.status='Baixando'
 $bot=0; $fatal=$false; $n=0; $stale=$false
 while(($ln=$p.StandardOutput.ReadLine()) -ne $null){
  if($ln -match '^YTLP\|([^|]*)\|([^|]*)\|(.*)$'){
   $pc=($matches[1] -replace '[^\d.]',''); if($pc){ try{ $S.pct=[double]::Parse($pc,[Globalization.CultureInfo]::InvariantCulture) }catch{} }
   $sp=$matches[2].Trim(); if($sp -and $sp -ne 'NA' -and $sp -ne 'Unknown'){ $S.speed=$sp }
   $et=$matches[3].Trim(); if($et -and $et -ne 'NA' -and $et -ne 'Unknown'){ $S.eta=$et }
   continue }
  if($ln -match '^\[download\]\s+[\d.]+%'){ continue }
  if($ln -match '^YTLOK:\s*"?(.+?)"?\s*$'){ $S.cur=Split-Path $matches[1] -Leaf; $n++; L ('[ok] '+$S.cur); continue }
  L $ln
  if($ln -match 'Downloading item (\d+) of (\d+)'){ if(-not $S.fixedItem){ $S.item="$($matches[1])/$($matches[2])" }; $S.pct=0 }
  if($ln -match '(Destination|Merging formats into):?\s+"?(.+?)"?$'){ $S.cur=Split-Path $matches[2] -Leaf }
  if($ln -match 'has already been (downloaded|recorded)'){ $n++ }
  if($ln -match 'ERROR'){
   if($ln -match 'Unable to extract|nsig extraction failed|Failed to extract'){ $stale=$true }
   if($ln -match 'Sign in to confirm|not a bot|HTTP Error 429|Too Many Requests|rate-limited|rate-limit|cookies are no longer valid|Please sign in|[Ll]ogin required|requires? (login|authentication)|[Yy]ou need to log in|Use --cookies|cookies .* for the authentication'){ $bot++ }
   elseif($ln -match 'Could not copy|Failed to decrypt|cookie database|cookies database|DPAPI|database is locked|could not find .* cookies|Permission denied.*[Cc]ookies'){ $fatal=$true; L '(dica: feche o navegador ou use outro; o Firefox e o mais estavel)' }
   elseif($ln -match 'ERROR: \[([^\]]+)\] ([^:\s]+): (.*)'){
    $ex=$matches[1]; $id=$matches[2]; $msg=$matches[3]
    if($ex -match '^youtube' -and $id -match '^[\w-]{11}$'){ [void]$fl.Add(@{id=$id;msg=$msg}) }
    else{ [void]$S.fails.Add("[$ex] $id - $(Why $msg)") } }
   else{ [void]$S.fails.Add($ln) }
  }
  if($bot -ge 2 -or $fatal){ KillTree $p.Id; break }
 }
 $p.WaitForExit(); $S['pid']=0; Remove-Item $cfg -ea 0
 $blocked=($bot -ge 2) -or ($bot -ge 1 -and $n -eq 0)
 return [pscustomobject]@{fatal=$fatal;bot=$bot;n=$n;stale=$stale;blocked=$blocked} }
function GetFile($url,$out){ $ProgressPreference='SilentlyContinue'
 for($i=1;$i -le 3;$i++){ try{ $t="$out.part"; Invoke-WebRequest $url -OutFile $t -UseBasicParsing; Move-Item $t $out -Force; return $true }
  catch{ L "  falha ($i/3): $($_.Exception.Message)"; Start-Sleep 2 } }; return $false }
function GetZip($url,$pat){ $z=J ([IO.Path]::GetTempPath()) ('dl_'+[guid]::NewGuid().ToString('N')+'.zip'); $x="$z.d"
 if(GetFile $url $z){ try{ Expand-Archive $z $x -Force; Get-ChildItem $x -Recurse -Include $pat | Copy-Item -Destination $S.bin -Force }catch{ L "falha ao extrair: $($_.Exception.Message)" } }
 Remove-Item $z,$x -Recurse -Force -ea 0 }
'@

# ------------------------------------------------------------------ preparo de dependencias
$prepSb={ param($S,$lib,$force)
 . ([scriptblock]::Create($lib))
 $bin=$S.bin; $yt=$S.yt
 function Ver{ $v=''; try{ $v=((& $yt --version 2>$null)|Select-Object -First 1) }catch{}; $h=''; try{ $h=(& $yt --help 2>&1|Out-String) }catch{}
  $S.rc=($h -match '--remote-components'); $S.jsr=($h -match '--js-runtimes')
  $S.ver=@{ytdlp="$v";ffmpeg=[bool](Get-Command ffmpeg -ea 0);deno=[bool](Get-Command deno -ea 0)} }
 try{
  $S.ready=$false; $S.prep='Verificando dependencias...'
  if($S.test){ Ver; $S.prep=''; $S.ready=$true; return }
  $ch=$S.chan; if(-not $ch){ $ch='stable' }
  $ytUrl=$(if($ch -eq 'nightly'){ 'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp.exe' }else{ 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' })
  if(-not(Test-Path $yt)){ $S.prep='Baixando yt-dlp...'; if(-not(GetFile $ytUrl $yt)){ $S.prep='ERRO: sem internet ou GitHub bloqueado. Verifique a conexao e reabra o programa.'; return } }
  else{ $S.prep='Atualizando yt-dlp...'; UpdYt }
  $stF=J $bin 'ffmpeg.stamp'
  $old=(Test-Path (J $bin 'ffmpeg.exe')) -and (-not(Test-Path $stF) -or ((Get-Date)-(Get-Item $stF).LastWriteTime).TotalDays -gt 7)
  if($force -and (Test-Path (J $bin 'ffmpeg.exe'))){ $old=$true }
  if(-not(Get-Command ffmpeg -ea 0) -or $old){ $S.prep='Baixando/atualizando o ffmpeg (~100 MB, so de vez em quando)...'
   GetZip 'https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' @('ffmpeg.exe','ffprobe.exe')
   if(Test-Path (J $bin 'ffmpeg.exe')){ Set-Content $stF (Get-Date -Format s) } }
  $stD=J $bin 'deno.stamp'
  if(-not(Get-Command deno -ea 0)){ $S.prep='Baixando o deno (necessario para o YouTube atual)...'; GetZip 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip' @('deno.exe'); if(Test-Path (J $bin 'deno.exe')){ Set-Content $stD (Get-Date -Format s) } }
  elseif((Test-Path (J $bin 'deno.exe')) -and ($force -or -not(Test-Path $stD) -or ((Get-Date)-(Get-Item $stD).LastWriteTime).TotalDays -gt 3)){ $S.prep='Atualizando o deno...'; try{ & (J $bin 'deno.exe') upgrade 2>&1 | ForEach-Object{ L "$_" }; Set-Content $stD (Get-Date -Format s) }catch{} }
  foreach($t in 'ffmpeg','deno'){ if(-not(Get-Command $t -ea 0)){ L "AVISO: $t nao instalado. Alguns formatos/videos podem falhar." } }
  Ver; $S.prep=''; $S.ready=$true
 }catch{ L "ERRO no preparo: $($_.Exception.Message)"; $S.prep="ERRO no preparo: $($_.Exception.Message)" }
}

# ------------------------------------------------------------------ gerar o .exe (so quando rodando como .bat/.ps1)
$cs=@'
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Media Downloader")]
[assembly: AssemblyProduct("Media Downloader")]
[assembly: AssemblyCompany("Bibinho1999")]
[assembly: AssemblyCopyright("by Bibinho1999")]
[assembly: AssemblyVersion("2.0.0.0")]

namespace MediaDownloaderLauncher
{
    static class Program
    {
        static NotifyIcon tray;
        static Process ps;
        static string dir;
        static string bin;
        static string portFile;
        static StreamWriter logw;
        static readonly object logLock = new object();

        [STAThread]
        static void Main(string[] args)
        {
            bool created;
            Mutex mutex = new Mutex(true, "MediaDownloader_SingleInstance", out created);
            dir = Path.GetDirectoryName(Application.ExecutablePath);
            bin = Path.Combine(dir, "bin");
            Directory.CreateDirectory(bin);
            portFile = Path.Combine(bin, "port.txt");

            if (!created)
            {
                OpenUi();
                return;
            }

            string script = Path.Combine(bin, "app.ps1");
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.ps1"))
                using (StreamReader r = new StreamReader(s, Encoding.UTF8))
                {
                    File.WriteAllText(script, r.ReadToEnd(), new UTF8Encoding(false));
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Não consegui preparar o programa:\n" + ex.Message, "Media Downloader");
                return;
            }

            try { File.Delete(portFile); } catch (Exception) { }
            try
            {
                string logPath = Path.Combine(bin, "app.log");
                if (File.Exists(logPath) && new FileInfo(logPath).Length > 1000000) File.Delete(logPath);
                logw = new StreamWriter(logPath, true, new UTF8Encoding(false));
                logw.AutoFlush = true;
            }
            catch (Exception) { logw = null; }

            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe");
            psi.Arguments = "-NoProfile -Command \"& ([scriptblock]::Create([IO.File]::ReadAllText('" +
                script.Replace("'", "''") + "',[Text.Encoding]::UTF8)))\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.EnvironmentVariables["SELF"] = Application.ExecutablePath;
            psi.EnvironmentVariables["YTDL_EXE"] = "1";
            try
            {
                ps = new Process();
                ps.StartInfo = psi;
                ps.OutputDataReceived += OnLine;
                ps.ErrorDataReceived += OnLine;
                ps.Start();
                ps.BeginOutputReadLine();
                ps.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Não consegui iniciar o PowerShell:\n" + ex.Message, "Media Downloader");
                return;
            }

            Application.EnableVisualStyles();
            tray = new NotifyIcon();
            try { tray.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch (Exception) { tray.Icon = SystemIcons.Application; }
            tray.Text = "Media Downloader - by Bibinho1999";
            ContextMenu menu = new ContextMenu();
            menu.MenuItems.Add("Abrir Media Downloader", delegate { OpenUi(); });
            menu.MenuItems.Add("Abrir pasta de downloads", delegate { OpenDownloads(); });
            menu.MenuItems.Add("-");
            menu.MenuItems.Add("Sair", delegate { Quit(); });
            tray.ContextMenu = menu;
            tray.DoubleClick += delegate { OpenUi(); };
            tray.Visible = true;
            tray.ShowBalloonTip(4000, "Media Downloader", "Rodando em segundo plano. Clique no ícone para abrir.", ToolTipIcon.Info);

            System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
            t.Interval = 1000;
            t.Tick += delegate
            {
                if (ps == null || ps.HasExited) Quit();
            };
            t.Start();

            Application.Run();
            GC.KeepAlive(mutex);
        }

        static void OnLine(object sender, DataReceivedEventArgs e)
        {
            if (e.Data == null || logw == null) return;
            lock (logLock)
            {
                try { logw.WriteLine(DateTime.Now.ToString("HH:mm:ss") + " " + e.Data); } catch (Exception) { }
            }
        }

        static void OpenUi()
        {
            string port = null;
            for (int i = 0; i < 60 && port == null; i++)
            {
                try
                {
                    if (File.Exists(portFile))
                    {
                        string p = File.ReadAllText(portFile).Trim();
                        if (p.Length > 0) port = p;
                    }
                }
                catch (Exception) { }
                if (port == null) Thread.Sleep(250);
            }
            if (port == null) return;
            try { Process.Start("http://127.0.0.1:" + port + "/"); } catch (Exception) { }
        }

        static void OpenDownloads()
        {
            try
            {
                string d = Path.Combine(dir, "Downloads");
                Directory.CreateDirectory(d);
                Process.Start("explorer.exe", "\"" + d + "\"");
            }
            catch (Exception) { }
        }

        static void Quit()
        {
            try
            {
                if (ps != null && !ps.HasExited)
                {
                    ProcessStartInfo k = new ProcessStartInfo("taskkill", "/PID " + ps.Id + " /T /F");
                    k.CreateNoWindow = true;
                    k.UseShellExecute = false;
                    Process.Start(k);
                }
            }
            catch (Exception) { }
            try { if (tray != null) { tray.Visible = false; tray.Dispose(); } } catch (Exception) { }
            try { File.Delete(portFile); } catch (Exception) { }
            Environment.Exit(0);
        }
    }
}
'@
$exeSb={ param($S,$lib,$cs)
 . ([scriptblock]::Create($lib))
 try{
  $dir=$S.dir; $exe=J $dir 'Media-Downloader.exe'; $stamp=J $S.bin 'exe.stamp'
  $hash=Md5 ($S.payload+$cs)
  if((Test-Path $exe) -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $hash)){ $S.exeok=$true; return }
  $tmp=J ([IO.Path]::GetTempPath()) ('ytb_'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $tmp | Out-Null
  $pf=J $tmp 'payload.ps1'; [IO.File]::WriteAllText($pf,$S.payload,(New-Object Text.UTF8Encoding $false))
  Add-Type -AssemblyName System.Drawing
  $ico=J $tmp 'app.ico'
  $bmp=New-Object Drawing.Bitmap 48,48; $g=[Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode='AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
  $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(214,40,47))),1,1,46,46)
  $pts=@((New-Object Drawing.Point 19,13),(New-Object Drawing.Point 19,35),(New-Object Drawing.Point 36,24))
  $g.FillPolygon([Drawing.Brushes]::White,[Drawing.Point[]]$pts); $g.Dispose()
  $ic=[Drawing.Icon]::FromHandle($bmp.GetHicon()); $fs=[IO.File]::Create($ico); $ic.Save($fs); $fs.Close()
  $prov=New-Object Microsoft.CSharp.CSharpCodeProvider
  $cp=New-Object CodeDom.Compiler.CompilerParameters
  $cp.GenerateExecutable=$true; $out=J $tmp 'out.exe'; $cp.OutputAssembly=$out
  $cp.CompilerOptions='/target:winexe /optimize /win32icon:"'+$ico+'"'
  foreach($r in 'System.dll','System.Windows.Forms.dll','System.Drawing.dll'){ [void]$cp.ReferencedAssemblies.Add($r) }
  [void]$cp.EmbeddedResources.Add($pf)
  $res=$prov.CompileAssemblyFromSource($cp,$cs)
  if($res.Errors.HasErrors){ foreach($e in $res.Errors){ L "(exe) $e" }; return }
  try{ Copy-Item $out $exe -Force; Set-Content $stamp $hash; $S.exeok=$true; L "Gerei/atualizei o Media-Downloader.exe ao lado deste arquivo." }
  catch{ L "(exe em uso - sera atualizado na proxima vez que o programa abrir sem o .exe rodando)" }
  Remove-Item $tmp -Recurse -Force -ea 0
 }catch{ L "(nao consegui gerar o .exe: $($_.Exception.Message))" }
}

# ------------------------------------------------------------------ download
$worker={ param($S,$lib,$o,$dl,$arc)
 . ([scriptblock]::Create($lib))
 function Cands($o,$dir){ $c=@(); if($o.nock){ $c+=,@() }
  $ck=J $dir 'cookies.txt'; if(Test-Path $ck){ $c+=,@('--cookies',$ck) }
  foreach($b in @($o.browsers)){ if($b){ $c+=,@('--cookies-from-browser',"$b") } }
  if($c.Count -eq 0){ $c+=,@() }; return ,$c }
 function FmtArgs($kind,$o){ $a=@()
  if($kind -eq 'v'){
   $h="$($o.vq)"; $mp4=("$($o.vcont)" -ne 'mkv')
   if($mp4){ if($h -eq 'best'){ $a+=@('-S','vcodec:h264,res,acodec:m4a') }else{ $a+=@('-S',"res:$h,vcodec:h264,acodec:m4a") }; $a+=@('--merge-output-format','mp4') }
   else{ if($h -ne 'best'){ $a+=@('-S',"res:$h") }; $a+=@('--merge-output-format','mkv') }
   if($o.meta){ $a+='--embed-metadata'; if($mp4){ $a+=@('--embed-thumbnail','--convert-thumbnails','jpg') } }
  } else {
   $f="$($o.afmt)"; $q="$($o.aq)"; $a+=@('-x','--audio-format',$f,'-f','bestaudio/best')
   if(($f -in 'mp3','m4a','opus') -and $q -and -not($q -eq '0' -and $f -ne 'mp3')){ $a+=@('--audio-quality',$q) }
   if($o.meta){ $a+='--embed-metadata'; if($f -in 'mp3','m4a'){ $a+=@('--embed-thumbnail','--convert-thumbnails','jpg') } } }
  return ,$a }
 try{
  $S.running=$true; $S.stop=$false; $S.fails.Clear(); $S.alts.Clear(); $S.log.Clear(); $S.done=0; $S.pct=0; $S.item=''; $S.fixedItem=$false
  $stamp=(Get-Date).ToString('yyyy-MM-dd HH-mm')
  $FL=New-Object Collections.ArrayList
  function FolderFor($plTitle){ switch("$($o.plmode)"){ 'none'{ return '' } 'new'{ return (Sanit $plTitle)+" [$stamp]/" } default{ return (Sanit $plTitle)+'/' } } }
  $useArc=("$($o.plmode)" -ne 'new')
  $base=@('--ignore-errors','--no-colors','--newline','--windows-filenames','--trim-filenames','120','--retries','10','--fragment-retries','10','--extractor-retries','5','--concurrent-fragments','4','--no-mtime','--socket-timeout','30',
   '--progress-template','download:YTLP|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s','--exec','echo YTLOK:{}','-P',$dl)
  if($o.safe){ $base+=@('--sleep-interval','2','--max-sleep-interval','6') }
  if($S.rc){ $base+=@('--remote-components','ejs:github') }
  if($S.jsr -and -not(Get-Command deno -ea 0) -and (Get-Command node -ea 0)){ $base+=@('--js-runtimes','node') }
  # ---- montar a lista de tarefas
  $jobs=@(); $idp=$(if($o.addId){' [%(id)s]'}else{''})
  if("$($o.mode)" -eq 'pick'){
   $maxIdx=IntOf $o.maxIdx; $w=([string]$maxIdx).Length
   $folder=FolderFor $o.plTitle; $its=@($o.items); $k=0
   foreach($it in $its){ $k++
    $sub=''; if($o.splitType){ $sub=$(if($it.type -eq 'v'){'Videos/'}else{'Musicas/'}) }
    $pre=''; if($o.num){ $pre=([string](IntOf $it.idx)).PadLeft($w,'0')+' - ' }
    $jobs+=,@{url="$($it.url)";kind="$($it.type)";label="$($it.title)";tpl=($folder+$sub+$pre+'%(title)s'+$idp+'.%(ext)s');altpre=($folder+$sub+$pre);title="$($it.title)";extra=@('--no-playlist');arcKey="$($o.plUrl)";itemLabel="$k/$($its.Count)"} }
  } else {
   $urls=@($o.urls|Where-Object{ $_ -and "$_".Trim() }); $kind=$(if($o.kind -eq 'v'){'v'}else{'a'})
   $bd=''; if($o.batch -and $urls.Count -gt 1){ $bd="Lote $stamp/" }
   $num=$(if($o.num){'%(playlist_index&{} - |)s'}else{''})
   $ex=@(); if($o.noPl){ $ex+='--no-playlist' }else{ $ex+='--yes-playlist' }
   $st=IntOf $o.st; $en=IntOf $o.en
   if($st -gt 0){ $ex+=@('--playlist-start',"$st") }; if($en -gt 0){ $ex+=@('--playlist-end',"$en") }
   foreach($u in $urls){ $jobs+=,@{url="$u";kind=$kind;label="$u";tpl='';num=$num;idp=$idp;bd=$bd;title='';extra=$ex;arcKey="$u";itemLabel=''} }
  }
  $S.total=$jobs.Count; $cands=Cands $o $S.dir; $start=0
  if($S.lastBrowser -ge 0 -and $S.lastBrowser -lt $cands.Count){ $start=$S.lastBrowser }
  foreach($j in $jobs){
   if($S.stop){ break }
   $fmt=FmtArgs $j.kind $o
   $fk=$(if($j.kind -eq 'v'){ "v|$($o.vcont)|$($o.vq)" }else{ "a|$($o.afmt)|$($o.aq)" })
   if(-not $j.tpl){
    # pasta da playlist: o yt-dlp troca '/' por outro caractere dentro de campos, entao o nome da pasta e resolvido aqui
    $fold=''; $fb=''
    if(-not $o.noPl -and "$($o.plmode)" -ne 'none'){
     $S.status='Lendo o link'
     $pr=@(Cap (@('--ignore-config','--no-warnings','--ignore-errors','--flat-playlist','--playlist-items','1','--socket-timeout','30','--print','%(playlist_title,playlist_id)s')+$cands[$start]+@($j.url)) 'pid')
     $pt=@($pr|Where-Object{ $_ -and $_ -notmatch '^(ERROR|WARNING|\[)' }|Select-Object -First 1)
     if($pt.Count -and "$($pt[0])".Trim() -ne 'NA'){ $fold=FolderFor "$($pt[0])" }
     elseif(-not $pt.Count){ $fb='%(playlist_title,playlist_id&{} - |)s' } }
    $j.tpl=$j.bd+$fold+$fb+$j.num+'%(title)s'+$j.idp+'.%(ext)s'
    if($fold){ L "Pasta: $($fold.TrimEnd('/'))" } }
   $args2=$base+$fmt+@('-o',$j.tpl)+$j.extra
   if($useArc){ $ar=J $arc ((Md5 ($j.arcKey+'|'+$fk))+'.txt'); if($o.reset){ Remove-Item $ar -ea 0 }; $args2+=@('--download-archive',$ar) } else { $ar='' }
   $S.cur=''; $S.pct=0; $S.item=$j.itemLabel; $S.fixedItem=[bool]$j.itemLabel; $FL.Clear(); L "=== $($j.label)"
   $cycle=0; $fin=$false; $updated=$false; $lastC=@(); $nocookTried=$false
   while(-not $fin -and -not $S.stop){
    $anyBot=$false
    for($k=0;$k -lt $cands.Count;$k++){
     if($S.stop){ break }
     $ci=($start+$k)%$cands.Count; $c=$cands[$ci]
     $S.browser=$(if($c.Count){ Split-Path $c[1] -Leaf }else{ 'sem cookies' })
     if($cands.Count -gt 1 -or $c.Count){ L ">>> Cookies: $($S.browser)" }
     $r=Run $j.url $c $args2 $o $FL
     if($r.stale -and -not $updated){ $updated=$true; L '!!! Extrator desatualizado: atualizando o yt-dlp e tentando de novo...'; UpdYt; $FL.Clear(); $r=Run $j.url $c $args2 $o $FL }
     if(-not $r.fatal -and -not $r.blocked){ $fin=$true; $lastC=$c; $start=$ci; $S.lastBrowser=$ci; break }
     if($r.blocked){ $anyBot=$true }
     L "!!! $($S.browser) falhou ($(if($r.fatal){'cookies ilegiveis'}else{'bloqueio/limite/login'})). Proximo..."
    }
    if($fin -or $S.stop){ break }
    if(-not $anyBot -and -not $nocookTried){ $nocookTried=$true; L '>>> Tentando sem cookies...'; $S.browser='sem cookies'
     $r=Run $j.url @() $args2 $o $FL; if(-not $r.blocked){ $fin=$true; $lastC=@(); break } }
    $cycle++
    if($o.wait -le 0 -or $cycle -ge 3 -or -not $anyBot){ L 'Todas as fontes de cookies falharam.'; [void]$S.fails.Add("BLOQUEADO (rode de novo depois, retoma de onde parou): $($j.url)"); break }
    for($t=(IntOf $o.wait)*60; $t -gt 0 -and -not $S.stop; $t--){ $S.status="Aguardando $([math]::Ceiling($t/60)) min p/ recomecar"; Start-Sleep 1 }
   }
   # ---- itens do YouTube bloqueados/removidos: procurar versao alternativa
   if($fin -and -not $S.stop -and $FL.Count){
    $seen=@{}; $items=@($FL|Where-Object{ if($seen[$_.id]){$false}else{$seen[$_.id]=$true;$true} }); $FL.Clear()
    $info=@{}; $mx=0
    if($o.alt -and -not $j.title){ L 'Lendo titulos da playlist p/ buscar alternativas...'
     foreach($row in (Cap (@('--ignore-errors','--no-colors','--flat-playlist','--print','%(id)s<|>%(playlist_index)s<|>%(playlist_title)s<|>%(title)s')+$lastC+@($j.url)) 'pid')){
      $q=$row -split '<\|>',4
      if($q.Count -eq 4 -and $q[0] -match '^[\w-]{11}$'){ $info[$q[0]]=@{idx=$q[1];pl=$q[2];title=$q[3]}; $ii=0; if([int]::TryParse($q[1],[ref]$ii) -and $ii -gt $mx){ $mx=$ii } } } }
    foreach($it in $items){
     if($S.stop){ break }
     $id=$it.id; $link="https://youtu.be/$id"; $why=Why $it.msg; $t=$info[$id]; $ttl="$($j.title)"; $pre=''
     if($j.title){ $pre=$j.altpre }
     elseif($t){ $ttl=$t.title
      $pre=$j.bd
      if($t.pl -and $t.pl -ne 'NA'){ $pre+=(FolderFor $t.pl); $ii=0; if($o.num -and [int]::TryParse($t.idx,[ref]$ii)){ $pre+=([string]$ii).PadLeft(([string]$mx).Length,'0')+' - ' } } }
     if($o.alt -and $ttl -and $ttl -ne 'NA' -and $ttl -notmatch '^\[(Deleted|Private) video\]$'){
      L "ALT: buscando versao alternativa de '$ttl'..."
      $qs=$(if($j.kind -eq 'v'){ "ytsearch5:$ttl" }else{ "ytsearch5:$ttl audio" })
      $fa=$base+$fmt+@('-o',($pre+'%(title)s.%(ext)s'),'--max-downloads','1','--match-filter',"id!=$id")
      if($useArc){ $fa+=@('--download-archive',$ar) }
      $r=Run $qs $lastC $fa $o $FL
      if($r.n -gt 0){ [void]$S.alts.Add("$ttl  <-  $link ($why)"); continue }
     }
     [void]$S.fails.Add($(if($ttl -and $ttl -ne 'NA'){"$ttl - "}else{''})+"$why - $link")
    }
    $FL.Clear()
   }
   $S.done++
  }
  $S.status=$(if($S.stop){'Parado pelo usuario'}else{'Concluido'})
 }catch{ L "ERRO interno: $($_.Exception.Message)"; $S.status='Erro' }
 finally{ $S.running=$false; $S.speed=''; $S.eta=''; $S.pct=$(if($S.status -eq 'Concluido'){100}else{$S.pct}) }
}

# ------------------------------------------------------------------ leitura de playlist (aba "escolher faixas")
$plSb={ param($S,$PL,$lib,$url,$browsers,$nock,$dir)
 . ([scriptblock]::Create($lib))
 try{
  $PL.busy=$true; $PL.err=''; $PL.title=''; $PL.stop=$false; $PL.items.Clear()
  $cands=@(,@()); $ck=J $dir 'cookies.txt'; if(Test-Path $ck){ $cands+=,@('--cookies',$ck) }
  foreach($b in @($browsers)){ if($b){ $cands+=,@('--cookies-from-browser',"$b") } }
  $pr='YTPL<|>%(id)s<|>%(playlist_index)s<|>%(duration)s<|>%(uploader,channel)s<|>%(playlist_title)s<|>%(webpage_url,url)s<|>%(title)s'
  foreach($c in $cands){
   if($PL.stop){ break }
   $cfg=Cfg (@('--ignore-errors','--no-colors','--flat-playlist','--yes-playlist','--socket-timeout','30','--print',$pr)+$c+@($url))
   $p=Spawn $cfg 'lpid'; $bad=$false; $errs=@()
   while(($ln=$p.StandardOutput.ReadLine()) -ne $null){
    if($PL.stop){ KillTree $p.Id; break }
    if($ln.StartsWith('YTPL<|>')){
     $q=$ln -split '<\|>',8
     if($q.Count -eq 8){
      $d=''; $dv=0.0; if([double]::TryParse($q[3],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$dv)){ $ts=[TimeSpan]::FromSeconds($dv); $d=$(if($ts.TotalHours -ge 1){ '{0}:{1:00}:{2:00}' -f [int][math]::Floor($ts.TotalHours),$ts.Minutes,$ts.Seconds }else{ '{0}:{1:00}' -f $ts.Minutes,$ts.Seconds }) }
      $up=$q[4]; if($up -eq 'NA'){ $up='' }
      $ix=IntOf $q[2]; if($ix -le 0){ $ix=$PL.items.Count+1 }
      $ti=$q[7]; $un=($ti -match '^\[(Deleted|Private) video\]$')
      if($q[5] -and $q[5] -ne 'NA' -and -not $PL.title){ $PL.title=$q[5] }
      [void]$PL.items.Add(@{idx=$ix;id=$q[1];dur=$d;uploader=$up;url=$q[6];title=$ti;unavail=$un}) }
    } elseif($ln -match 'ERROR'){ $errs+=$ln; if($ln -match 'Sign in|login|Login|cookies|429|private'){ $bad=$true } }
   }
   $p.WaitForExit(); $S['lpid']=0; Remove-Item $cfg -ea 0
   if($PL.items.Count -gt 0){ break }
   if($errs.Count){ $PL.err=($errs|Select-Object -First 1) -replace '^ERROR:\s*','' }
   if(-not $bad -and $c.Count -eq 0){ break }
  }
  if($PL.items.Count -gt 0){ $PL.err='' } elseif(-not $PL.err){ $PL.err='Nenhuma faixa encontrada neste link.' }
 }catch{ $PL.err=$_.Exception.Message }
 finally{ $PL.busy=$false }
}

# ------------------------------------------------------------------ verificar link
$infoSb={ param($S,$lib,$url,$browsers,$dir)
 . ([scriptblock]::Create($lib))
 try{
  $S.info=@{busy=$true}
  $txt=(Cap @('--ignore-config','--flat-playlist','--dump-single-json','--no-warnings','--ignore-errors','--socket-timeout','30',$url) 'ipid') -join "`n"
  $js=$null; try{ $js=$txt.Substring($txt.IndexOf('{'))|ConvertFrom-Json }catch{}
  if($js){ $cnt=1; if($js.entries){ $cnt=@($js.entries).Count }
   $S.info=@{busy=$false;title="$($js.title)";count=$cnt;ex="$($js.extractor_key)";error=''} }
  else{ $m=($txt -split "`n"|Where-Object{ $_ -match 'ERROR' }|Select-Object -First 1); if(-not $m){ $m='sem resposta' }; $S.info=@{busy=$false;title='';count=0;ex='';error=(Why (($m -replace '^.*ERROR:\s*','')))} }
 }catch{ $S.info=@{busy=$false;title='';count=0;ex='';error=$_.Exception.Message} }
}

# ------------------------------------------------------------------ pagina
$tok=[guid]::NewGuid().ToString('N')
$html=@'
<!doctype html><html lang="pt-br"><head><meta charset="utf-8"><title>Media Downloader</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:#fff;--fg:#1c1c1e;--card:#f2f2f5;--ac:#d6282f;--mu:#777;--ln:#8883}
@media(prefers-color-scheme:dark){:root{--bg:#161618;--fg:#eee;--card:#232327;--mu:#999}}
*{box-sizing:border-box}
body{font:15px system-ui,sans-serif;background:var(--bg);color:var(--fg);max-width:960px;margin:0 auto;padding:16px}
h1{font-size:21px;margin:0}.by{font-size:12px;font-weight:400;color:var(--mu);margin-left:6px}footer{margin:18px 0 6px;text-align:center;color:var(--mu);font-size:12px}footer a{color:inherit}.sub{color:var(--mu);font-size:13px;margin:2px 0 10px}
textarea,select,input[type=number],input[type=text]{width:100%;background:var(--card);color:var(--fg);border:1px solid #8884;border-radius:8px;padding:8px;font:inherit}
textarea{height:96px}.card{background:var(--card);border-radius:12px;padding:12px;margin:10px 0}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end}.row>*{flex:1;min-width:120px}.row>.nf{flex:none;min-width:0}
label{display:block;margin:4px 0}label.i{display:inline-flex;gap:6px;align-items:center;margin-right:14px}
button{background:var(--ac);color:#fff;border:0;border-radius:8px;padding:9px 15px;font:inherit;cursor:pointer}
button.s{background:#8885;color:var(--fg)}button:disabled{opacity:.4;cursor:default}
progress{width:100%;height:16px}
pre{background:#000;color:#9f9;padding:8px;border-radius:8px;height:200px;overflow:auto;font-size:12px;white-space:pre-wrap}
.mu{color:var(--mu);font-size:13px}#fails{color:#e55;white-space:pre-wrap;font-size:13px}#alts{color:#3a3;white-space:pre-wrap;font-size:13px}
.tabs{display:flex;gap:4px;margin-top:10px}.tabs button{background:transparent;color:var(--fg);border-radius:8px 8px 0 0;border-bottom:3px solid transparent}
.tabs button.on{border-bottom-color:var(--ac);font-weight:600}
.pane{display:none}.pane.on{display:block}
#banner{background:#d6a02a33;border:1px solid #d6a02a;border-radius:8px;padding:8px;margin:8px 0;display:none}
table{width:100%;border-collapse:collapse;font-size:14px}th,td{padding:5px 6px;text-align:left;border-bottom:1px solid var(--ln)}
th{position:sticky;top:0;background:var(--card)}.tw{max-height:380px;overflow:auto;border-radius:8px;background:var(--bg)}
tr.na{opacity:.45}td select{padding:3px;width:auto}.num{text-align:right;color:var(--mu)}
hr{border:0;border-top:1px solid var(--ln);margin:10px 0}
</style></head><body>
<h1>Media Downloader <small class="by">by Bibinho1999</small></h1>
<div class="sub">Baixe áudio e vídeo de YouTube, Instagram, TikTok, X, Vimeo, SoundCloud, Facebook, Twitch e mais de mil sites. <span id="ver"></span></div>
<div id="banner"></div>

<div class="card"><b>O que baixar</b>
<div class="row" style="margin-top:6px">
<div>Música: formato<select id="afmt"><option>mp3</option><option>m4a</option><option>opus</option><option>flac</option><option>wav</option></select></div>
<div>Qualidade do áudio<select id="aq"><option value="0">Melhor</option><option value="320K">320 kbps</option><option value="192K">192 kbps</option><option value="128K">128 kbps</option></select></div>
<div>Vídeo: qualidade<select id="vq"><option value="best">Melhor</option><option value="1080">1080p</option><option value="720">720p</option><option value="480">480p</option><option value="360">360p</option></select></div>
<div>Vídeo: formato<select id="vcont"><option value="mp4">MP4 (compatível com tudo)</option><option value="mkv">MKV (original, sem converter)</option></select></div></div>
<div class="mu">O áudio do YouTube tem ~128–160 kbps: bitrates maiores não melhoram o som. O MP4 sai em H.264 + AAC.</div></div>

<div class="card"><b>Playlists e pastas</b>
<div class="row" style="margin-top:6px"><div>Pasta para playlists/canais<select id="plmode">
<option value="name">Uma pasta com o nome da playlist (retoma se já existir)</option>
<option value="new">Sempre uma pasta nova (nome + data e hora)</option>
<option value="none">Sem pasta (tudo solto)</option></select></div></div>
<label class="i"><input type="checkbox" id="num"> Numerar pela ordem da playlist</label>
<label class="i"><input type="checkbox" id="batch"> Vários links de uma vez: guardar numa pasta "Lote data-hora"</label>
<label class="i"><input type="checkbox" id="splitType"> Aba Playlist: separar em subpastas Músicas / Vídeos</label></div>

<div class="tabs"><button id="t_links" class="on" onclick="tab('links')">Baixar links</button><button id="t_pick" onclick="tab('pick')">Playlist: escolher faixas</button><button id="t_cfg" onclick="tab('cfg')">Configurações</button></div>

<div id="p_links" class="pane on card">
<textarea id="urls" placeholder="Cole links de vídeos, músicas ou playlists de qualquer site (um por linha)"></textarea>
<div class="row" style="margin-top:8px"><button class="s nf" onclick="chk()">Verificar link</button><span id="ck" class="mu"></span></div>
<div style="margin-top:8px"><b>Baixar como:</b>
<label class="i"><input type="radio" name="kind" value="a" checked> Música (áudio)</label>
<label class="i"><input type="radio" name="kind" value="v"> Vídeo</label></div>
<div class="row"><div>Do item<input type="number" id="st" min="0" placeholder="1"></div><div>Até o item<input type="number" id="en" min="0" placeholder="todos"></div></div>
<label><input type="checkbox" id="noPl"> Só o vídeo (ignorar a playlist do link)</label>
</div>

<div id="p_pick" class="pane card">
<div class="row"><div style="flex:4"><input type="text" id="plurl" placeholder="Link da playlist, álbum ou canal"></div>
<button class="s nf" id="plbtn" onclick="plLoad()">Carregar lista</button><button class="s nf" onclick="api('pl/stop',{})">Parar</button></div>
<div id="plinfo" class="mu" style="margin:6px 0">Cole o link e clique em Carregar lista. Depois marque o que quer e escolha áudio ou vídeo em cada faixa.</div>
<div class="row" style="align-items:center">
<span class="nf"><button class="s" onclick="mark(1)">Marcar todos</button> <button class="s" onclick="mark(0)">Desmarcar</button> <button class="s" onclick="mark(2)">Inverter</button></span>
<input type="text" id="plfilter" placeholder="Filtrar por título ou canal" oninput="render()"></div>
<div style="margin:6px 0"><b>Baixar como:</b>
<label class="i"><input type="radio" name="pm" value="a" checked> Tudo em áudio</label>
<label class="i"><input type="radio" name="pm" value="v"> Tudo em vídeo</label>
<label class="i"><input type="radio" name="pm" value="m"> Misturado (escolho em cada faixa)</label></div>
<div class="tw"><table><thead><tr><th></th><th class="num">#</th><th>Título</th><th>Canal</th><th>Duração</th><th>Tipo</th></tr></thead><tbody id="tb"></tbody></table></div>
</div>

<div id="p_cfg" class="pane card">
<b>Cookies (rodízio nesta ordem quando um falhar ou for bloqueado)</b>
<div class="row" style="margin-top:6px">
<label class="i"><input type="checkbox" class="br" value="firefox" checked> Firefox</label>
<label class="i"><input type="checkbox" class="br" value="edge" checked> Edge</label>
<label class="i"><input type="checkbox" class="br" value="chrome" checked> Chrome</label>
<label class="i"><input type="checkbox" class="br" value="brave"> Brave</label>
<label class="i"><input type="checkbox" class="br" value="opera"> Opera</label>
<label class="i"><input type="checkbox" class="br" value="vivaldi"> Vivaldi</label></div>
<label><input type="checkbox" id="nock"> Tentar sem cookies primeiro</label>
<div class="row"><div>Se todos falharem, esperar (min) e recomeçar (0 = parar)<input type="number" id="wait" value="15" min="0"></div></div>
<div class="mu">Se existir um cookies.txt ao lado do programa, ele é usado primeiro. Navegadores baseados em Chrome podem exigir que estejam fechados; o Firefox é o mais estável.</div>
<hr>
<label><input type="checkbox" id="meta" checked> Capa e metadados no arquivo</label>
<label><input type="checkbox" id="safe" checked> Modo cuidadoso (pausas entre downloads, evita bloqueio)</label>
<label><input type="checkbox" id="reset"> Recomeçar do zero (ignorar o histórico de já baixados)</label>
<label><input type="checkbox" id="alt" checked> Buscar versão alternativa quando um vídeo do YouTube estiver bloqueado ou removido</label>
<label><input type="checkbox" id="addId"> Colocar o ID do vídeo no nome do arquivo</label>
<hr>
<div class="row"><div>Pasta de downloads (vazio = a pasta Downloads ao lado do programa)<input type="text" id="dlDir" placeholder="C:\Users\voce\Music"></div>
<div>Atualizações do yt-dlp<select id="chan"><option value="stable">Estável</option><option value="nightly">Nightly (recebe correções do YouTube mais rápido)</option></select></div></div>
<div class="row" style="margin-top:8px"><button class="s nf" onclick="upd()">Atualizar tudo agora</button><button class="s nf" onclick="shortcuts()">Criar atalhos (Área de Trabalho e Menu Iniciar)</button><button class="s nf" onclick="api('open',{what:'bin'})">Abrir pasta do programa</button></div>
<div class="mu">O yt-dlp, o ffmpeg e o deno são verificados e atualizados toda vez que o programa abre. Se um download falhar por extrator desatualizado, o yt-dlp é atualizado e o link é tentado de novo automaticamente.</div>
</div>

<div class="row" style="margin-top:6px"><button id="go" onclick="go()">Baixar</button><button class="s" onclick="api('stop',{})">Parar</button>
<button class="s" onclick="api('open',{what:'dl'})">Abrir pasta</button><button class="s" onclick="if(confirm('Encerrar o programa?'))api('quit',{})">Encerrar</button></div>
<div class="card"><progress id="bar" max="100" value="0"></progress>
<div id="info" class="mu"></div><div id="cur"></div></div>
<pre id="log"></pre><div id="alts"></div><div id="fails"></div>

<footer>Media Downloader · by <a href="https://github.com/Bibinho1999" target="_blank" rel="noopener">Bibinho1999</a></footer>
<script>
const T='__TOK__',$=i=>document.getElementById(i);
const api=(p,b)=>fetch('/api/'+p+(p.indexOf('?')<0?'?':'&')+'t='+T,b?{method:'POST',body:JSON.stringify(b)}:{}).then(r=>r.json());
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
let cur='links',P={items:[],from:0,busy:false,title:'',url:''},ready=false,running=false;
const IDS=['afmt','aq','vq','vcont','plmode','num','batch','splitType','st','en','noPl','nock','wait','meta','safe','reset','alt','addId','dlDir','chan'];
function tab(t){cur=t;for(const k of['links','pick','cfg']){$('p_'+k).classList.toggle('on',k===t);$('t_'+k).classList.toggle('on',k===t)}
$('go').textContent=t==='pick'?'Baixar selecionados':'Baixar'}
function radio(n){const e=document.querySelector('input[name='+n+']:checked');return e?e.value:''}
function setRadio(n,v){document.querySelectorAll('input[name='+n+']').forEach(e=>e.checked=e.value===v)}
function common(){const o={};for(const i of IDS){const e=$(i);o[i]=e.type==='checkbox'?e.checked:e.value}
o.browsers=[...document.querySelectorAll('.br:checked')].map(e=>e.value);o.kind=radio('kind');o.pm=radio('pm');o.plurl=$('plurl').value;return o}
let sv=null;function save(){clearTimeout(sv);sv=setTimeout(()=>api('settings',common()),500)}
async function load(){try{const s=await api('settings');for(const i of IDS){if(!(i in s))continue;const e=$(i);if(e.type==='checkbox')e.checked=!!s[i];else e.value=s[i]}
if(s.browsers)document.querySelectorAll('.br').forEach(e=>e.checked=s.browsers.indexOf(e.value)>=0);if(s.kind)setRadio('kind',s.kind);if(s.pm)setRadio('pm',s.pm);if(s.plurl)$('plurl').value=s.plurl}catch(e){}
document.querySelectorAll('input,select').forEach(e=>e.addEventListener('change',save))}
function opts(){const o=common();o.urls=$('urls').value.split('\n').map(s=>s.trim()).filter(s=>s&&s[0]!=='#');return o}
async function go(){if(running)return;let o;
if(cur==='pick'){const sel=P.items.filter(x=>x.checked&&!x.unavail);if(!sel.length)return alert('Carregue uma playlist e marque pelo menos uma faixa.');
o=common();o.mode='pick';o.plUrl=P.url||$('plurl').value;o.plTitle=P.title;o.maxIdx=Math.max.apply(null,P.items.map(x=>x.idx||0).concat([P.items.length]));
o.items=sel.map(x=>({idx:x.idx,title:x.title,url:x.url,type:x.type}))}
else{o=opts();o.mode='links';if(!o.urls.length)return alert('Cole ao menos um link.')}
const r=await api('start',o);if(r.error)alert(r.error)}
async function chk(){const u=opts().urls[0];if(!u)return;$('ck').textContent='Verificando...';await api('info',{url:u});
for(let i=0;i<90;i++){await new Promise(r=>setTimeout(r,700));const r=await api('infostate');if(!r.busy){$('ck').textContent=r.error?('Não consegui ler o link: '+r.error):(r.title+' · '+r.count+' item(ns)'+(r.ex?' · '+r.ex:''));return}}$('ck').textContent='Demorou demais.'}
async function upd(){const r=await api('update',{});if(r.error)alert(r.error)}
async function shortcuts(){const r=await api('shortcut',{});alert(r.msg||r.error||'ok')}
/* ---- aba Playlist ---- */
async function plLoad(){const u=$('plurl').value.trim();if(!u)return alert('Cole o link da playlist.');P={items:[],from:0,busy:true,title:'',url:u};render();$('plinfo').textContent='Carregando a lista...';await api('pl/load',{url:u,browsers:common().browsers,nock:$('nock').checked});plPoll()}
async function plPoll(){try{const r=await api('pl?from='+P.from);const pm=radio('pm');
for(const it of r.items){it.checked=!it.unavail;it.type=pm==='v'?'v':'a';P.items.push(it)}P.from=r.total;P.title=r.title||P.title;P.busy=r.busy;P.err=r.err;render()
if(r.busy)setTimeout(plPoll,700);else if(!P.items.length&&r.err)$('plinfo').textContent='Não consegui carregar: '+r.err}catch(e){}}
function vis(){const q=$('plfilter').value.trim().toLowerCase();return P.items.map((x,i)=>[x,i]).filter(p=>!q||(p[0].title+' '+p[0].uploader).toLowerCase().indexOf(q)>=0)}
function render(){const v=vis();$('tb').innerHTML=v.map(p=>{const x=p[0],i=p[1];return`<tr class="${x.unavail?'na':''}"><td><input type="checkbox" data-i="${i}" ${x.checked?'checked':''} ${x.unavail?'disabled':''}></td><td class="num">${esc(x.idx)}</td><td>${esc(x.title)}</td><td>${esc(x.uploader)}</td><td>${esc(x.dur)}</td><td>${x.unavail?'indisponível':`<select data-t="${i}"><option value="a" ${x.type==='a'?'selected':''}>Áudio</option><option value="v" ${x.type==='v'?'selected':''}>Vídeo</option></select>`}</td></tr>`}).join('');sum()}
function sum(){const s=P.items.filter(x=>x.checked&&!x.unavail),a=s.filter(x=>x.type==='a').length;
if(P.items.length)$('plinfo').textContent=(P.busy?'Carregando... ':'')+(P.title?'“'+P.title+'” · ':'')+P.items.length+' faixa(s) · '+s.length+' marcada(s) ('+a+' áudio, '+(s.length-a)+' vídeo)'}
function mark(m){for(const p of vis()){const x=p[0];if(x.unavail)continue;x.checked=m===2?!x.checked:!!m}render()}
$('tb').addEventListener('change',e=>{const t=e.target;if(t.dataset.i!==undefined){P.items[+t.dataset.i].checked=t.checked;sum()}
else if(t.dataset.t!==undefined){P.items[+t.dataset.t].type=t.value;setRadio('pm','m');save();sum()}});
document.querySelectorAll('input[name=pm]').forEach(e=>e.addEventListener('change',()=>{const m=radio('pm');if(m!=='m'){P.items.forEach(x=>x.type=m);render()}}));
/* ---- status ---- */
async function poll(){try{const s=await api('status');running=s.running;ready=s.ready;$('bar').value=s.pct;
$('banner').style.display=s.prep?'block':'none';$('banner').textContent=s.prep||'';
$('ver').textContent=s.ver&&s.ver.ytdlp?('· yt-dlp '+s.ver.ytdlp+' · ffmpeg '+(s.ver.ffmpeg?'ok':'falta')+' · deno '+(s.ver.deno?'ok':'falta')):'';
$('info').textContent=`${s.status} | ${s.browser?'cookies: '+s.browser+' | ':''}item ${s.item||'-'} | link ${s.done}/${s.total} | ${s.speed} ${s.eta?'ETA '+s.eta:''}`;
$('cur').textContent=s.cur;if(s.running||!$('log').dataset.k){$('log').textContent=s.log.join('\n');$('log').scrollTop=1e9}
$('fails').textContent=s.fails.length?'Sem solução:\n'+s.fails.join('\n'):'';$('alts').textContent=s.alts.length?'Alternativas baixadas:\n'+s.alts.join('\n'):'';
$('go').disabled=s.running||!s.ready}catch(e){$('info').textContent='Programa encerrado.'}}
load();setInterval(poll,1000);poll();
</script></body></html>
'@
function Bg($sb,$a){ $rsp=[runspacefactory]::CreateRunspace(); $rsp.Open(); $p=[powershell]::Create(); $p.Runspace=$rsp
 [void]$p.AddScript($sb.ToString()); foreach($x in $a){ [void]$p.AddArgument($x) }; [void]$p.BeginInvoke() }
function ReadSettings{ if(Test-Path $settingsFile){ try{ return (Get-Content $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json) }catch{} }; return $null }
function GetDl{ $s=ReadSettings; $d=$null; if($s -and $s.dlDir){ $d="$($s.dlDir)".Trim() }
 if(-not $d){ $d=[IO.Path]::Combine($dir,'Downloads') }
 try{ New-Item -ItemType Directory -Force $d | Out-Null }catch{ $d=[IO.Path]::Combine($dir,'Downloads'); New-Item -ItemType Directory -Force $d | Out-Null }
 return $d }
function Open-Folder($p){ if($TEST){ return }; if($WIN){ Start-Process explorer.exe "`"$p`"" } }
function Make-Shortcuts{
 if(-not $WIN){ return 'So funciona no Windows.' }
 $exe=[IO.Path]::Combine($dir,'Media-Downloader.exe'); $target=$self; $icon=''
 if(Test-Path $exe){ $target=$exe; $icon=$exe }
 $ws=New-Object -ComObject WScript.Shell; $made=@()
 foreach($loc in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))){
  try{ $lnk=$ws.CreateShortcut([IO.Path]::Combine($loc,'Media Downloader.lnk')); $lnk.TargetPath=$target; $lnk.WorkingDirectory=$dir; if($icon){ $lnk.IconLocation=$icon }; $lnk.Save(); $made+=$loc }catch{}
 }
 if($made.Count){ return "Atalhos criados em:`n"+($made -join "`n") } else { return 'Nao consegui criar os atalhos.' } }

# ------------------------------------------------------------------ inicio
Write-Host "== Media Downloader $APPVER - by Bibinho1999 =="
$S.chan=$(if($(ReadSettings).chan){ "$((ReadSettings).chan)" }else{ 'stable' })
if($self -and $self -match '\.(bat|ps1|cmd)$' -and (Test-Path $self) -and -not $env:YTDL_EXE){
 $raw=[IO.File]::ReadAllText($self,[Text.Encoding]::UTF8); $ix=$raw.LastIndexOf('###'+'PS###')
 $S.payload=$(if($ix -ge 0){ $raw.Substring($ix+8) }else{ $raw }) }
Bg $prepSb @($S,$lib,$false)
$lst=$null; $port=8765
while($port -lt 8790){ $l=New-Object Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$port/"); try{ $l.Start(); $lst=$l; break }catch{ $port++ } }
if(-not $lst){ Write-Host 'ERRO: nenhuma porta livre (8765-8789).'; return }
[IO.File]::WriteAllText([IO.Path]::Combine($bin,'port.txt'),"$port")
Write-Host "Pronto! Abrindo http://127.0.0.1:$port/"
if($S.payload -and -not $TEST -and $WIN){ Bg $exeSb @($S,$lib,$cs); Write-Host '(gerando/atualizando o Media-Downloader.exe em segundo plano)' }
if(-not $TEST){ if($WIN){ Start-Process "http://127.0.0.1:$port/" } }

$first=$true
while($lst.IsListening){
 $ctx=$lst.GetContext(); $rq=$ctx.Request; $rs=$ctx.Response
 try{
  $path=$rq.Url.AbsolutePath; $body=''
  if($rq.HasEntityBody){ $body=(New-Object IO.StreamReader($rq.InputStream,[Text.Encoding]::UTF8)).ReadToEnd() }
  $out='{}'; $ct='application/json; charset=utf-8'
  $hostOk=("$($rq.Headers['Host'])" -match '^(127\.0\.0\.1|localhost)(:\d+)?$')
  if(-not $hostOk){ $rs.StatusCode=403; $out='' }
  elseif($path -eq '/'){ $out=$html.Replace('__TOK__',$tok); $ct='text/html; charset=utf-8' }
  elseif($rq.QueryString['t'] -ne $tok){ $rs.StatusCode=403 }
  else{
   switch($path){
    '/api/status'{ $out=@{running=$S.running;ready=$S.ready;prep=$S.prep;ver=$S.ver;status=$S.status;pct=$S.pct;speed=$S.speed;eta=$S.eta;item=$S.item;cur=$S.cur;browser=$S.browser;done=$S.done;total=$S.total;
       log=@($S.log.ToArray()|Select-Object -Last 90);fails=@($S.fails.ToArray());alts=@($S.alts.ToArray())}|ConvertTo-Json -Depth 4 -Compress }
    '/api/settings'{ if($rq.HttpMethod -eq 'POST'){ try{ $null=$body|ConvertFrom-Json; [IO.File]::WriteAllText($settingsFile,$body,(New-Object Text.UTF8Encoding $false)); $c=($body|ConvertFrom-Json).chan; if($c){ $S.chan="$c" } }catch{} }
       else{ if(Test-Path $settingsFile){ $out=[IO.File]::ReadAllText($settingsFile,[Text.Encoding]::UTF8) } } }
    '/api/start'{
     if($S.running){ $out='{"error":"Ja existe um download em andamento."}' }
     elseif(-not $S.ready){ $out='{"error":"Ainda preparando o yt-dlp/ffmpeg. Aguarde alguns instantes."}' }
     else{ $o=$body|ConvertFrom-Json; $S.running=$true; $S.status='Iniciando'; Bg $worker @($S,$lib,$o,(GetDl),$arc); $out='{"ok":true}' } }
    '/api/stop'{ $S.stop=$true; $PL.stop=$true; KillTree $S.pid; KillTree $S.lpid }
    '/api/open'{ $w=($body|ConvertFrom-Json).what; if($w -eq 'bin'){ Open-Folder $bin }else{ Open-Folder (GetDl) } }
    '/api/info'{ $u=($body|ConvertFrom-Json).url; if(-not $S.info.busy){ $S.info=@{busy=$true}; Bg $infoSb @($S,$lib,$u,@(),$dir) } }
    '/api/infostate'{ $out=$S.info|ConvertTo-Json -Compress }
    '/api/pl/load'{ $b=$body|ConvertFrom-Json; if(-not $PL.busy){ $PL.busy=$true; Bg $plSb @($S,$PL,$lib,$b.url,@($b.browsers),[bool]$b.nock,$dir) } }
    '/api/pl'{ $f=0; [void][int]::TryParse($rq.QueryString['from'],[ref]$f); $all=@($PL.items.ToArray()); $sl=@(); if($f -lt $all.Count){ $sl=@($all[$f..($all.Count-1)]) }
       $out=@{items=$sl;total=$all.Count;title="$($PL.title)";busy=[bool]$PL.busy;err="$($PL.err)"}|ConvertTo-Json -Depth 4 -Compress }
    '/api/pl/stop'{ $PL.stop=$true; KillTree $S.lpid }
    '/api/update'{ if($S.running){ $out='{"error":"Espere o download terminar para atualizar."}' }else{ Bg $prepSb @($S,$lib,$true) } }
    '/api/shortcut'{ $out=@{msg=(Make-Shortcuts)}|ConvertTo-Json -Compress }
    '/api/quit'{ $S.stop=$true; $PL.stop=$true; KillTree $S.pid; KillTree $S.lpid; KillTree $S.ipid; $lst.Stop() }
   }
  }
  if($lst.IsListening -and $out){ $b=[Text.Encoding]::UTF8.GetBytes($out); $rs.ContentType=$ct; $rs.OutputStream.Write($b,0,$b.Length) }
 }catch{ try{ $rs.StatusCode=500 }catch{} }
 finally{ try{ $rs.Close() }catch{} }
}
try{ Remove-Item ([IO.Path]::Combine($bin,'port.txt')) -ea 0 }catch{}
