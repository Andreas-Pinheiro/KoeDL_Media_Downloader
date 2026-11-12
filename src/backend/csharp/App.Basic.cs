using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

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
