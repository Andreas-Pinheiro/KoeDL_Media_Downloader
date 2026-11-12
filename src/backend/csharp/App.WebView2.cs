using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("KoeDL")]
[assembly: AssemblyProduct("KoeDL")]
[assembly: AssemblyCompany("Andreas-Pinheiro")]
[assembly: AssemblyCopyright("by Andreas-Pinheiro")]
[assembly: AssemblyVersion("3.9.0.0")]

namespace MediaDownloaderLauncher
{
    static class Program
    {
        static NotifyIcon tray;
        static Process ps;
        static string dir;
        static string bin;
        static string portFile;
        static string logPath;
        static StreamWriter logw;
        static bool pt;
        static volatile bool everUp;
        static volatile bool failShown;
        static readonly object logLock = new object();
        static Form wvForm;
        static volatile bool wvFailed;
        static volatile bool wvStarted;
        static bool askedInstall;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool SetDllDirectory(string path);

        static string Tx(string p, string e) { return pt ? p : e; }

        [STAThread]
        static void Main(string[] args)
        {
            if (Setup.IsSetupMode(args)) { Setup.Run(args); return; }
            bool created;
            Mutex mutex = new Mutex(true, "MediaDownloader_SingleInstance", out created);
            dir = Path.GetDirectoryName(Application.ExecutablePath);
            bin = Path.Combine(dir, "bin");
            Directory.CreateDirectory(bin);
            portFile = Path.Combine(bin, "port.txt");
            logPath = Path.Combine(bin, "app.log");
            try { string sj = File.ReadAllText(Path.Combine(bin, "settings.json")); pt = sj.Replace(" ", "").Contains("\"lang\":\"pt\""); } catch (Exception) { pt = false; }

            if (!created)
            {
                // Outra copia ja esta rodando: so abre a janela (se ela realmente estiver respondendo).
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
                MessageBox.Show(Tx("Não consegui preparar o programa:\n", "Could not prepare the program:\n") + ex.Message, "KoeDL");
                return;
            }

            try { File.Delete(portFile); } catch (Exception) { }
            try
            {
                if (File.Exists(logPath) && new FileInfo(logPath).Length > 1000000) File.Delete(logPath);
                logw = new StreamWriter(new FileStream(logPath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite), new UTF8Encoding(false));
                logw.AutoFlush = true;
                logw.WriteLine("---- " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " start ----");
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
            if (File.Exists(Path.Combine(bin, "installed.txt"))) psi.EnvironmentVariables["YTDL_INSTALLED"] = "1";
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
                MessageBox.Show(Tx("Não consegui iniciar o PowerShell:\n", "Could not start PowerShell:\n") + ex.Message, "KoeDL");
                return;
            }

            Application.EnableVisualStyles();
            tray = new NotifyIcon();
            try { tray.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch (Exception) { tray.Icon = SystemIcons.Application; }
            tray.Text = "KoeDL - by Andreas-Pinheiro";
            ContextMenu menu = new ContextMenu();
            menu.MenuItems.Add(Tx("Abrir KoeDL", "Open KoeDL"), delegate { StartOpenUi(); });
            menu.MenuItems.Add(Tx("Abrir pasta de downloads", "Open downloads folder"), delegate { OpenDownloads(); });
            menu.MenuItems.Add("-");
            menu.MenuItems.Add(Tx("Sair", "Quit"), delegate { Quit(); });
            tray.ContextMenu = menu;
            tray.DoubleClick += delegate { StartOpenUi(); };
            tray.Visible = true;

            // abre a janela so depois que o servidor responder; se nao responder, mostra o motivo
            StartOpenUi();

            System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
            t.Interval = 1000;
            t.Tick += delegate
            {
                if (ps == null || ps.HasExited)
                {
                    t.Stop();
                    if (!everUp) ShowFail();
                    Quit();
                }
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

        static void StartOpenUi()
        {
            Thread th = new Thread(OpenUi);
            th.IsBackground = true;
            th.Start();
        }

        static bool PortUp(string port)
        {
            int p;
            if (!int.TryParse(port, out p)) return false;
            try
            {
                using (TcpClient c = new TcpClient())
                {
                    IAsyncResult r = c.BeginConnect("127.0.0.1", p, null, null);
                    bool ok = r.AsyncWaitHandle.WaitOne(700);
                    if (ok && c.Connected) { c.EndConnect(r); return true; }
                }
            }
            catch (Exception) { }
            return false;
        }

        static void OpenUi()
        {
            string port = null;
            for (int i = 0; i < 80 && port == null; i++)
            {
                try
                {
                    if (File.Exists(portFile))
                    {
                        string p = File.ReadAllText(portFile).Trim();
                        if (p.Length > 0 && PortUp(p)) port = p;
                    }
                }
                catch (Exception) { }
                if (port == null)
                {
                    if (ps != null && ps.HasExited) return; // o aviso de falha vem do timer
                    Thread.Sleep(250);
                }
            }
            if (port == null) { ShowFail(); return; }
            everUp = true;
            string url = "http://127.0.0.1:" + port + "/";
            bool app = true;
            try { string sj = File.ReadAllText(Path.Combine(bin, "settings.json")); if (sj.Replace(" ", "").Contains("\"openMode\":\"browser\"")) app = false; } catch (Exception) { }
            if (app)
            {
                bool ok = false;
                try { ok = TryWebView(url); } catch (Exception ex) { Log("webview: " + ex.Message); }
                if (ok) return;
            }
            OpenEdgeOrBrowser(url, app);
        }

        static void OpenEdgeOrBrowser(string url, bool app)
        {
            if (app)
            {
                string b = FindBrowser();
                if (b != null)
                {
                    try
                    {
                        Process.Start(b, "--app=" + url + WinArgs() + " --no-first-run --user-data-dir=\"" + Path.Combine(bin, "appwin") + "\"");
                        return;
                    }
                    catch (Exception) { }
                }
            }
            try { Process.Start(url); } catch (Exception) { }
        }

        static void Log(string m)
        {
            if (logw == null) return;
            lock (logLock) { try { logw.WriteLine(DateTime.Now.ToString("HH:mm:ss") + " [launcher] " + m); } catch (Exception) { } }
        }

        // ---------------- WebView2 (janela propria, sem navegador) ----------------
        static bool WvRuntimeInstalled()
        {
            string[] keys = {
                @"SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
                @"SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" };
            RegistryKey[] hives = { Registry.LocalMachine, Registry.CurrentUser };
            foreach (RegistryKey h in hives)
            {
                foreach (string k in keys)
                {
                    try
                    {
                        using (RegistryKey rk = h.OpenSubKey(k))
                        {
                            if (rk == null) continue;
                            string pv = rk.GetValue("pv") as string;
                            if (!string.IsNullOrEmpty(pv) && pv != "0.0.0.0") return true;
                        }
                    }
                    catch (Exception) { }
                }
            }
            return false;
        }

        static bool OfferInstallRuntime()
        {
            string declined = Path.Combine(bin, "wv2", "declined.txt");
            try
            {
                if (File.Exists(declined) && (DateTime.Now - File.GetLastWriteTime(declined)).TotalDays < 30) return false;
            }
            catch (Exception) { }
            if (askedInstall) return false;
            askedInstall = true;
            DialogResult r = MessageBox.Show(
                Tx("O KoeDL usa o Microsoft WebView2 para mostrar a janela, mas ele não está instalado neste computador.\n\nInstalar a versão mais recente agora? É gratuito e oficial da Microsoft (o Windows pode pedir permissão).\n\nSe escolher Não, o programa abre no Edge/Chrome.",
                   "KoeDL uses Microsoft WebView2 to show its window, but it is not installed on this computer.\n\nInstall the latest version now? It is free and official from Microsoft (Windows may ask for permission).\n\nIf you choose No, the program opens in Edge/Chrome."),
                "KoeDL", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes)
            {
                try { Directory.CreateDirectory(Path.Combine(bin, "wv2")); File.WriteAllText(declined, DateTime.Now.ToString("s")); } catch (Exception) { }
                return false;
            }
            try
            {
                string f = Path.Combine(Path.GetTempPath(), "MicrosoftEdgeWebview2Setup.exe");
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
                using (WebClient w = new WebClient())
                {
                    w.DownloadFile("https://go.microsoft.com/fwlink/p/?LinkId=2124703", f);
                }
                Process p = Process.Start(f, "/silent /install");
                p.WaitForExit();
                return WvRuntimeInstalled();
            }
            catch (Exception ex)
            {
                Log("install webview2: " + ex.Message);
                MessageBox.Show(Tx("Não consegui instalar o WebView2 automaticamente. Você pode instalar manualmente em: https://developer.microsoft.com/microsoft-edge/webview2/", "Could not install WebView2 automatically. You can install it manually from: https://developer.microsoft.com/microsoft-edge/webview2/"), "KoeDL");
                return false;
            }
        }

        static bool TryWebView(string url)
        {
            if (wvFailed) return false;
            if (wvForm != null)
            {
                try
                {
                    wvForm.BeginInvoke((MethodInvoker)delegate { wvForm.Show(); wvForm.WindowState = FormWindowState.Normal; wvForm.Activate(); });
                    return true;
                }
                catch (Exception) { }
            }
            string d = Path.Combine(bin, "wv2");
            string winforms = Path.Combine(d, "Microsoft.Web.WebView2.WinForms.dll");
            string core = Path.Combine(d, "Microsoft.Web.WebView2.Core.dll");
            for (int i = 0; i < 240; i++)
            {
                if (File.Exists(winforms) && File.Exists(core)) break;
                if (File.Exists(Path.Combine(d, "fail.txt"))) break;
                if (ps != null && ps.HasExited) break;
                Thread.Sleep(250);
            }
            if (!File.Exists(winforms) || !File.Exists(core)) { Log("webview2 files not available, using Edge/Chrome"); return false; }
            if (!WvRuntimeInstalled())
            {
                if (!OfferInstallRuntime()) return false;
                if (!WvRuntimeInstalled()) return false;
            }
            if (wvStarted) return true;
            wvStarted = true;
            Thread th = new Thread(delegate() { ShowWv(url, d, winforms, core); });
            th.SetApartmentState(ApartmentState.STA);
            th.IsBackground = true;
            th.Start();
            for (int i = 0; i < 80 && wvForm == null && !wvFailed; i++) Thread.Sleep(250);
            return wvForm != null && !wvFailed;
        }


        static bool LoadWin(out int x, out int y, out int w, out int h, out bool max)
        {
            x = y = w = h = 0; max = false;
            try
            {
                string[] a = File.ReadAllText(Path.Combine(bin, "win.txt")).Trim().Split(',');
                if (a.Length < 4) return false;
                x = int.Parse(a[0]); y = int.Parse(a[1]); w = int.Parse(a[2]); h = int.Parse(a[3]);
                max = a.Length >= 5 && a[4] == "1";
                return w >= 600 && h >= 500;
            }
            catch (Exception) { return false; }
        }

        static string WinArgs()
        {
            int x, y, w, h; bool m;
            if (LoadWin(out x, out y, out w, out h, out m)) return " --window-size=" + w + "," + h + " --window-position=" + x + "," + y;
            return " --window-size=1040,940";
        }

        static void SaveWin(Form f)
        {
            try
            {
                Rectangle b = f.WindowState == FormWindowState.Normal ? f.Bounds : f.RestoreBounds;
                File.WriteAllText(Path.Combine(bin, "win.txt"), b.X + "," + b.Y + "," + b.Width + "," + b.Height + "," + (f.WindowState == FormWindowState.Maximized ? "1" : "0"));
            }
            catch (Exception) { }
        }

        static void ShowWv(string url, string d, string winforms, string core)
        {
            try
            {
                SetDllDirectory(Path.Combine(d, Environment.Is64BitProcess ? "x64" : "x86"));
                Assembly.LoadFrom(core);
                Assembly asm = Assembly.LoadFrom(winforms);
                Type tWv = asm.GetType("Microsoft.Web.WebView2.WinForms.WebView2", true);
                Type tCp = asm.GetType("Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties", true);
                object cp = Activator.CreateInstance(tCp);
                tCp.GetProperty("UserDataFolder").SetValue(cp, Path.Combine(bin, "wv2data"), null);
                Control wv = (Control)Activator.CreateInstance(tWv);
                tWv.GetProperty("CreationProperties").SetValue(wv, cp, null);
                wv.Dock = DockStyle.Fill;

                Form f = new Form();
                f.Text = "KoeDL";
                f.Width = 1080;
                f.Height = 980;
                f.StartPosition = FormStartPosition.CenterScreen;
                int sx, sy, sw, sh; bool smax;
                if (LoadWin(out sx, out sy, out sw, out sh, out smax))
                {
                    bool vis = false;
                    foreach (Screen sc in Screen.AllScreens) { if (sc.WorkingArea.IntersectsWith(new Rectangle(sx, sy, sw, sh))) vis = true; }
                    if (vis)
                    {
                        f.StartPosition = FormStartPosition.Manual;
                        f.SetBounds(sx, sy, sw, sh);
                        if (smax) f.WindowState = FormWindowState.Maximized;
                    }
                }
                f.ResizeEnd += delegate { SaveWin(f); };
                try { f.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }
                f.FormClosing += delegate(object s, FormClosingEventArgs e)
                {
                    SaveWin(f);
                    if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; f.Hide(); }
                };
                f.Controls.Add(wv);
                tWv.GetProperty("Source").SetValue(wv, new Uri(url), null);

                // vigia: se o WebView2 nao inicializar em 30 s, cai para o Edge/Chrome
                System.Windows.Forms.Timer wd = new System.Windows.Forms.Timer();
                wd.Interval = 1000;
                int ticks = 0;
                wd.Tick += delegate
                {
                    ticks++;
                    object core2 = null;
                    try { core2 = tWv.GetProperty("CoreWebView2").GetValue(wv, null); } catch (Exception) { }
                    if (core2 != null) { wd.Stop(); return; }
                    if (ticks >= 30)
                    {
                        wd.Stop();
                        Log("webview2 did not initialize; falling back to Edge/Chrome");
                        wvFailed = true;
                        wvForm = null;
                        OpenEdgeOrBrowser(url, true);
                        Application.ExitThread();
                    }
                };
                wd.Start();
                wvForm = f;
                Application.Run(f);
            }
            catch (Exception ex)
            {
                Log("webview2 error: " + ex.Message);
                wvFailed = true;
            }
        }

        static void ShowFail()
        {
            if (failShown) return;
            failShown = true;
            string tail = "";
            try
            {
                string[] lines;
                using (FileStream fs = new FileStream(logPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (StreamReader r = new StreamReader(fs, Encoding.UTF8))
                {
                    lines = r.ReadToEnd().Split('\n');
                }
                int first = Math.Max(0, lines.Length - 14);
                StringBuilder sb = new StringBuilder();
                for (int i = first; i < lines.Length; i++) sb.AppendLine(lines[i].TrimEnd('\r'));
                tail = sb.ToString();
            }
            catch (Exception) { }
            MessageBox.Show(
                Tx("O KoeDL não conseguiu iniciar.\n\nÚltimas linhas do registro (bin\\app.log):\n\n", "KoeDL could not start.\n\nLast lines of the log (bin\\app.log):\n\n") + tail,
                "KoeDL");
        }

        static string FindBrowser()
        {
            string[] rels = { @"Microsoft\Edge\Application\msedge.exe", @"Google\Chrome\Application\chrome.exe" };
            string[] roots = { Environment.GetEnvironmentVariable("ProgramFiles"), Environment.GetEnvironmentVariable("ProgramFiles(x86)"), Environment.GetEnvironmentVariable("LocalAppData") };
            foreach (string rel in rels)
            {
                foreach (string root in roots)
                {
                    if (string.IsNullOrEmpty(root)) continue;
                    string c = Path.Combine(root, rel);
                    if (File.Exists(c)) return c;
                }
            }
            return null;
        }

        static void OpenDownloads()
        {
            try
            {
                string d = null;
                try
                {
                    string sj = File.ReadAllText(Path.Combine(bin, "settings.json"));
                    Match m = Regex.Match(sj, "\"dlDir\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
                    if (m.Success) d = m.Groups[1].Value.Replace("\\\\", "\\").Trim();
                }
                catch (Exception) { }
                if (string.IsNullOrEmpty(d))
                {
                    if (File.Exists(Path.Combine(bin, "installed.txt"))) { string up = Environment.GetEnvironmentVariable("USERPROFILE"); if (up == null) up = dir; d = Path.Combine(up, (Directory.Exists(Path.Combine(up, @"Downloads\KoeDL")) || !Directory.Exists(Path.Combine(up, @"Downloads\Media Downloader")) ? @"Downloads\KoeDL" : @"Downloads\Media Downloader")); }
                    else d = Path.Combine(dir, "Downloads");
                }
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
