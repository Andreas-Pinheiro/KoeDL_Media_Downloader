using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace MediaDownloaderLauncher
{
    static class Setup
    {
        const string UKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\MediaDownloader";
        const string ExeName = "KoeDL.exe";
        const string RtGuid = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";
        static bool pt;

        [DllImport("user32.dll")]
        static extern bool SetProcessDPIAware();

        class HqPic : PictureBox
        {
            protected override void OnPaint(PaintEventArgs e)
            {
                e.Graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                base.OnPaint(e);
            }
        }

        static string T(string p, string e) { return pt ? p : e; }

        public static bool IsSetupMode(string[] args)
        {
            foreach (string a in args) { if (a == "--setup" || a == "--uninstall") return true; }
            string n = Path.GetFileNameWithoutExtension(Application.ExecutablePath);
            return n.IndexOf("setup", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        public static void Run(string[] args)
        {
            pt = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "pt";
            try { SetProcessDPIAware(); } catch (Exception) { }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            bool un = false;
            foreach (string a in args) { if (a == "--uninstall") un = true; }
            if (un) Uninstall(); else Wizard();
        }

        static bool RtOk()
        {
            string[] subs = { @"SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\" + RtGuid, @"SOFTWARE\Microsoft\EdgeUpdate\Clients\" + RtGuid };
            RegistryKey[] roots = { Registry.LocalMachine, Registry.CurrentUser };
            foreach (RegistryKey root in roots)
            {
                foreach (string s in subs)
                {
                    try
                    {
                        using (RegistryKey k = root.OpenSubKey(s))
                        {
                            if (k == null) continue;
                            object v = k.GetValue("pv");
                            if (v != null && v.ToString() != "" && v.ToString() != "0.0.0.0") return true;
                        }
                    }
                    catch (Exception) { }
                }
            }
            return false;
        }

        static void KillOthers()
        {
            int me = Process.GetCurrentProcess().Id;
            string[] names = { "KoeDL", "Media Downloader", "MediaDownloader" };
            foreach (string nm in names)
            {
                foreach (Process p in Process.GetProcessesByName(nm))
                {
                    if (p.Id == me) continue;
                    try
                    {
                        ProcessStartInfo k = new ProcessStartInfo("taskkill", "/PID " + p.Id + " /T /F");
                        k.CreateNoWindow = true;
                        k.UseShellExecute = false;
                        Process kp = Process.Start(k);
                        if (kp != null) kp.WaitForExit(5000);
                    }
                    catch (Exception) { }
                }
            }
            Thread.Sleep(600);
        }

        static string FindExisting()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(UKey))
                {
                    if (k != null)
                    {
                        object v = k.GetValue("InstallLocation");
                        if (v != null && v.ToString() != "" && Directory.Exists(v.ToString())) return v.ToString();
                    }
                }
            }
            catch (Exception) { }
            try
            {
                string d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\Media Downloader");
                if (Directory.Exists(Path.Combine(d, "bin"))) return d;
            }
            catch (Exception) { }
            return null;
        }

        static bool IsAdmin()
        {
            try { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
            catch (Exception) { return false; }
        }

        static string CheckWritable(string dir)
        {
            try
            {
                Directory.CreateDirectory(dir);
                string t = Path.Combine(dir, ".koedl_write_test");
                File.WriteAllText(t, "1");
                File.Delete(t);
                return null;
            }
            catch (UnauthorizedAccessException) { return "admin"; }
            catch (Exception ex) { return ex.Message; }
        }

        static bool SameDir(string a, string b)
        {
            try { return string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
            catch (Exception) { return false; }
        }

        static void CopyDir(string src, string dst)
        {
            Directory.CreateDirectory(dst);
            foreach (string f in Directory.GetFiles(src))
            {
                string n = Path.GetFileName(f);
                if (n == "installed.txt" || n == "port.txt" || n == "portable.txt") continue;
                string to = Path.Combine(dst, n);
                if (!File.Exists(to)) File.Copy(f, to);
            }
            foreach (string d in Directory.GetDirectories(src))
            {
                CopyDir(d, Path.Combine(dst, Path.GetFileName(d)));
            }
        }

        // Traz configuracoes, historico, fila e ferramentas da instalacao antiga para a nova pasta e remove so os arquivos do proprio programa na antiga.
        static void MigrateOld(string oldDir, string target)
        {
            try
            {
                if (SameDir(oldDir, target)) return;
                string ob = Path.Combine(oldDir, "bin");
                string nb = Path.Combine(target, "bin");
                bool ok = true;
                if (Directory.Exists(ob))
                {
                    try { CopyDir(ob, nb); } catch (Exception) { ok = false; }
                }
                string[] names = { "KoeDL.exe", "KoeDL-Setup.exe", "Media Downloader.exe", "MediaDownloader.exe", "Media-Downloader.exe" };
                foreach (string n in names) { try { File.Delete(Path.Combine(oldDir, n)); } catch (Exception) { } }
                if (ok) { try { Directory.Delete(ob, true); } catch (Exception) { } }
                try { Directory.Delete(oldDir); } catch (Exception) { }
            }
            catch (Exception) { }
        }

        static void MakeLnk(string path, string exe, string wd)
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            object sh = Activator.CreateInstance(t);
            object l = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, sh, new object[] { path });
            Type lt = l.GetType();
            lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, l, new object[] { exe });
            lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, l, new object[] { wd });
            lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, l, new object[] { exe + ",0" });
            lt.InvokeMember("Description", BindingFlags.SetProperty, null, l, new object[] { "KoeDL - by Andreas-Pinheiro" });
            lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, l, null);
        }

        static string Desktop() { return Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory); }
        static string StartMenu() { return Environment.GetFolderPath(Environment.SpecialFolder.Programs); }

        static string DoInstall(string target, bool portable, bool desk, bool menu, string existing, Action<string> say)
        {
            try
            {
                say(T("Verificando o WebView2...", "Checking WebView2..."));
                if (!RtOk())
                {
                    DialogResult r = MessageBox.Show(
                        T("O KoeDL precisa do Microsoft Edge WebView2 Runtime (gratuito, da Microsoft) para abrir em janela própria.\n\nInstalar a última versão agora?",
                          "KoeDL needs the Microsoft Edge WebView2 Runtime (free, from Microsoft) to open in its own window.\n\nInstall the latest version now?"),
                        "KoeDL", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                    if (r == DialogResult.Yes)
                    {
                        say(T("Baixando e instalando o WebView2...", "Downloading and installing WebView2..."));
                        try
                        {
                            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
                            string tmp = Path.Combine(Path.GetTempPath(), "MicrosoftEdgeWebview2Setup.exe");
                            using (WebClient wc = new WebClient()) { wc.DownloadFile("https://go.microsoft.com/fwlink/p/?LinkId=2124703", tmp); }
                            Process p = Process.Start(tmp, "/silent /install");
                            if (p != null) p.WaitForExit();
                        }
                        catch (Exception) { }
                    }
                }

                say(T("Fechando o programa, se estiver aberto...", "Closing the program if it is open..."));
                KillOthers();

                say(T("Copiando arquivos...", "Copying files..."));
                string bin = Path.Combine(target, "bin");
                Directory.CreateDirectory(target);
                Directory.CreateDirectory(bin);
                string self = Application.ExecutablePath;
                string dst = Path.Combine(target, ExeName);
                if (!SameDir(Path.GetDirectoryName(self), target) || !string.Equals(Path.GetFileName(self), ExeName, StringComparison.OrdinalIgnoreCase)) File.Copy(self, dst, true);
                if (existing != null && !portable)
                {
                    say(T("Trazendo suas configurações da instalação anterior...", "Bringing your settings from the previous install..."));
                    MigrateOld(existing, target);
                }
                if (portable)
                {
                    try { File.Delete(Path.Combine(bin, "installed.txt")); } catch (Exception) { }
                    File.WriteAllText(Path.Combine(bin, "portable.txt"), "1");
                }
                else
                {
                    try { File.Delete(Path.Combine(bin, "portable.txt")); } catch (Exception) { }
                    File.WriteAllText(Path.Combine(bin, "installed.txt"), "1");
                }
                File.WriteAllText(Path.Combine(bin, "shortcuts2.done"), "1");

                if (!portable)
                {
                    say(T("Criando atalhos...", "Creating shortcuts..."));
                    string d1 = Path.Combine(Desktop(), "KoeDL.lnk");
                    string d2 = Path.Combine(StartMenu(), "KoeDL.lnk");
                    try { File.Delete(Path.Combine(Desktop(), "Media Downloader.lnk")); } catch (Exception) { }
                    try { File.Delete(Path.Combine(StartMenu(), "Media Downloader.lnk")); } catch (Exception) { }
                    if (desk) MakeLnk(d1, dst, target); else { try { File.Delete(d1); } catch (Exception) { } }
                    if (menu) MakeLnk(d2, dst, target); else { try { File.Delete(d2); } catch (Exception) { } }

                    say(T("Registrando em Aplicativos do Windows...", "Registering in Windows Apps..."));
                    using (RegistryKey k = Registry.CurrentUser.CreateSubKey(UKey))
                    {
                        k.SetValue("DisplayName", "KoeDL");
                        k.SetValue("DisplayVersion", "3.9");
                        k.SetValue("Publisher", "Andreas-Pinheiro");
                        k.SetValue("InstallLocation", target);
                        k.SetValue("DisplayIcon", dst);
                        k.SetValue("UninstallString", "\"" + dst + "\" --uninstall");
                        k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                        k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    }
                }
                return null;
            }
            catch (UnauthorizedAccessException)
            {
                return T("Sem permissão para gravar nessa pasta. Abra o instalador como administrador (botão direito > Executar como administrador) ou escolha outra pasta.",
                         "No permission to write to that folder. Open the installer as administrator (right-click > Run as administrator) or pick another folder.");
            }
            catch (Exception ex) { return ex.Message; }
        }

        static Image LoadLogo()
        {
            try
            {
                using (Stream st = Assembly.GetExecutingAssembly().GetManifestResourceStream("logo.png"))
                {
                    if (st != null)
                    {
                        using (Image im = Image.FromStream(st)) { return new Bitmap(im); }
                    }
                }
            }
            catch (Exception) { }
            return null;
        }

        static void RelaunchAsAdmin()
        {
            try
            {
                ProcessStartInfo p = new ProcessStartInfo(Application.ExecutablePath, "--setup");
                p.UseShellExecute = true;
                p.Verb = "runas";
                Process.Start(p);
            }
            catch (Exception) { }
        }

        static void Launch(string exe)
        {
            try { Process.Start(exe); } catch (Exception) { }
        }

        static Label Lbl(Form f, string text, int x, int y, int w, int h, float size, bool bold, Color c)
        {
            Label l = new Label();
            l.Text = text;
            l.SetBounds(x, y, w, h);
            l.ForeColor = c;
            l.BackColor = Color.Transparent;
            l.Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular);
            f.Controls.Add(l);
            return l;
        }

        static CheckBox Chk(Form f, string text, int y, bool on)
        {
            CheckBox c = new CheckBox();
            c.Text = text;
            c.Checked = on;
            c.SetBounds(28, y, 460, 24);
            c.ForeColor = Color.FromArgb(230, 241, 255);
            c.BackColor = Color.Transparent;
            c.Font = new Font("Segoe UI", 10f);
            f.Controls.Add(c);
            return c;
        }

        static RadioButton Rad(Form f, string text, int y, bool on)
        {
            RadioButton c = new RadioButton();
            c.Text = text;
            c.Checked = on;
            c.SetBounds(28, y, 470, 24);
            c.ForeColor = Color.FromArgb(230, 241, 255);
            c.BackColor = Color.Transparent;
            c.Font = new Font("Segoe UI", 10f);
            f.Controls.Add(c);
            return c;
        }

        static void Wizard()
        {
            string localDef = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\KoeDL");
            string existing = FindExisting();
            string defInst = existing != null ? existing : localDef;
            string selfDir = Path.GetDirectoryName(Application.ExecutablePath);
            string defPort = Path.Combine(selfDir, "KoeDL-Portable");
            Color fg = Color.FromArgb(230, 241, 255);
            Color mu = Color.FromArgb(143, 160, 201);

            Form f = new Form();
            f.AutoScaleDimensions = new SizeF(96F, 96F);
            f.AutoScaleMode = AutoScaleMode.Dpi;
            f.Text = T("Instalar KoeDL", "Install KoeDL");
            f.FormBorderStyle = FormBorderStyle.FixedDialog;
            f.MaximizeBox = false;
            f.MinimizeBox = false;
            f.StartPosition = FormStartPosition.CenterScreen;
            f.ClientSize = new Size(520, 480);
            f.BackColor = Color.FromArgb(14, 20, 40);
            f.ForeColor = fg;
            try { f.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }

            HqPic pb = new HqPic();
            pb.SetBounds(26, 22, 72, 72);
            pb.SizeMode = PictureBoxSizeMode.Zoom;
            pb.BackColor = Color.Transparent;
            Image logo = LoadLogo();
            if (logo != null) pb.Image = logo;
            else { try { if (f.Icon != null) { using (Icon ic = new Icon(f.Icon, 64, 64)) { pb.Image = ic.ToBitmap(); } } } catch (Exception) { } }
            f.Controls.Add(pb);

            Lbl(f, "KoeDL", 108, 26, 390, 36, 18f, true, fg);
            Lbl(f, "by Andreas-Pinheiro", 110, 64, 390, 22, 9f, false, mu);
            Lbl(f, T("Escolha como quer usar o KoeDL:", "Choose how you want to use KoeDL:"), 28, 108, 470, 22, 10f, false, fg);

            RadioButton rbInst = Rad(f, T("Instalar no sistema (atalhos e Aplicativos do Windows)", "Install on this PC (shortcuts and Windows Apps)"), 134, true);
            RadioButton rbPort = Rad(f, T("Versão portátil (só copia os arquivos para a pasta)", "Portable version (just copies the files to the folder)"), 160, false);

            Lbl(f, T("Pasta:", "Folder:"), 28, 196, 470, 20, 9f, false, mu);
            TextBox tb = new TextBox();
            tb.SetBounds(28, 218, 372, 26);
            tb.Font = new Font("Segoe UI", 9.5f);
            tb.BackColor = Color.FromArgb(24, 32, 60);
            tb.ForeColor = fg;
            tb.BorderStyle = BorderStyle.FixedSingle;
            tb.Text = defInst;
            f.Controls.Add(tb);
            Button browse = new Button();
            browse.Text = T("Procurar...", "Browse...");
            browse.SetBounds(408, 217, 84, 28);
            f.Controls.Add(browse);

            Label hint = Lbl(f, "", 28, 250, 470, 54, 9f, false, mu);

            CheckBox cbDesk = Chk(f, T("Criar atalho na Área de Trabalho", "Create a Desktop shortcut"), 312, true);
            CheckBox cbMenu = Chk(f, T("Criar atalho no Menu Iniciar", "Create a Start Menu shortcut"), 340, true);
            CheckBox cbRun = Chk(f, T("Abrir o KoeDL ao terminar", "Open KoeDL when finished"), 368, true);

            Label status = Lbl(f, "", 28, 402, 470, 22, 9.5f, false, mu);
            ProgressBar bar = new ProgressBar();
            bar.SetBounds(28, 428, 464, 12);
            bar.Style = ProgressBarStyle.Continuous;
            f.Controls.Add(bar);

            Button btn = new Button();
            btn.Text = existing != null ? T("Atualizar", "Update") : T("Instalar", "Install");
            btn.SetBounds(392, 444, 100, 30);
            f.Controls.Add(btn);
            Button cancel = new Button();
            cancel.Text = T("Cancelar", "Cancel");
            cancel.SetBounds(286, 444, 100, 30);
            cancel.Click += delegate { f.Close(); };
            f.Controls.Add(cancel);

            Action refresh = delegate
            {
                bool port = rbPort.Checked;
                cbDesk.Enabled = !port;
                cbMenu.Enabled = !port;
                string path = tb.Text.Trim();
                string h;
                if (port)
                {
                    btn.Text = T("Copiar", "Copy");
                    h = T("Portátil: nada é registrado no Windows. Tudo fica nessa pasta, então dá para levar em um pendrive. Para remover, é só apagar a pasta.",
                          "Portable: nothing is registered in Windows. Everything stays in that folder, so you can carry it on a USB stick. To remove it, just delete the folder.");
                }
                else if (existing != null && path.Length > 0 && SameDir(existing, path))
                {
                    btn.Text = T("Atualizar", "Update");
                    h = T("O KoeDL já está instalado aqui. Ele será substituído pela versão nova e suas configurações, histórico e fila são mantidos.",
                          "KoeDL is already installed here. It will be replaced by the new version, and your settings, history and queue are kept.");
                }
                else if (existing != null)
                {
                    btn.Text = T("Instalar", "Install");
                    h = T("Já existe uma instalação em " + existing + ". Ela será movida para a pasta escolhida (configurações e histórico vêm junto).",
                          "There is already an install at " + existing + ". It will be moved to the chosen folder (settings and history come along).");
                }
                else
                {
                    btn.Text = T("Instalar", "Install");
                    h = T("Instalação só para o seu usuário (não precisa de administrador).", "Install for your user only (no administrator needed).");
                }
                string pf = Environment.GetEnvironmentVariable("ProgramFiles");
                string pf86 = Environment.GetEnvironmentVariable("ProgramFiles(x86)");
                string pw = Environment.GetEnvironmentVariable("SystemRoot");
                bool prot = false;
                if (path.Length > 0)
                {
                    if (pf != null && path.StartsWith(pf, StringComparison.OrdinalIgnoreCase)) prot = true;
                    if (pf86 != null && path.StartsWith(pf86, StringComparison.OrdinalIgnoreCase)) prot = true;
                    if (pw != null && path.StartsWith(pw, StringComparison.OrdinalIgnoreCase)) prot = true;
                    if (path.Length <= 3) prot = true;
                }
                if (prot && !IsAdmin())
                {
                    h = h + "\n" + T("Atenção: essa pasta precisa de administrador. Abra o instalador com botão direito > Executar como administrador.",
                                      "Note: this folder needs administrator rights. Open the installer with right-click > Run as administrator.");
                }
                hint.Text = h;
            };

            rbInst.CheckedChanged += delegate
            {
                string cur = tb.Text.Trim();
                if (rbInst.Checked && (cur.Length == 0 || SameDir(cur, defPort))) tb.Text = defInst;
                refresh();
            };
            rbPort.CheckedChanged += delegate
            {
                string cur = tb.Text.Trim();
                if (rbPort.Checked && (cur.Length == 0 || SameDir(cur, defInst))) tb.Text = defPort;
                refresh();
            };
            tb.TextChanged += delegate { refresh(); };
            browse.Click += delegate
            {
                using (FolderBrowserDialog fb = new FolderBrowserDialog())
                {
                    fb.Description = T("Escolha a pasta do KoeDL", "Choose the KoeDL folder");
                    try { if (Directory.Exists(tb.Text.Trim())) fb.SelectedPath = tb.Text.Trim(); } catch (Exception) { }
                    if (fb.ShowDialog(f) == DialogResult.OK) tb.Text = fb.SelectedPath;
                }
            };
            refresh();

            bool done = false;
            bool running = false;
            string exeTarget = "";
            btn.Click += delegate
            {
                if (done)
                {
                    if (cbRun.Checked && exeTarget.Length > 0) Launch(exeTarget);
                    f.Close();
                    return;
                }
                if (running) return;
                string target = tb.Text.Trim();
                if (target.Length < 4 || !Path.IsPathRooted(target))
                {
                    MessageBox.Show(T("Escolha uma pasta válida (por exemplo, C:\\KoeDL).", "Pick a valid folder (for example, C:\\KoeDL)."), "KoeDL");
                    return;
                }
                bool port = rbPort.Checked;
                string chk = CheckWritable(target);
                if (chk != null)
                {
                    if (chk == "admin" && !IsAdmin())
                    {
                        DialogResult ar = MessageBox.Show(
                            T("Essa pasta precisa de permissão de administrador.\n\nReabrir o instalador como administrador agora?\n\n(Se preferir, clique em Não e escolha outra pasta, como a padrão.)",
                              "This folder needs administrator permission.\n\nReopen the installer as administrator now?\n\n(Or click No and pick another folder, like the default one.)"),
                            "KoeDL", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                        if (ar == DialogResult.Yes) { RelaunchAsAdmin(); f.Close(); }
                    }
                    else
                    {
                        MessageBox.Show(T("Não consegui usar essa pasta: ", "Could not use that folder: ") + (chk == "admin" ? T("sem permissão.", "no permission.") : chk), "KoeDL");
                    }
                    return;
                }
                exeTarget = Path.Combine(target, ExeName);
                running = true;
                btn.Enabled = false;
                cancel.Enabled = false;
                cbDesk.Enabled = false; cbMenu.Enabled = false; cbRun.Enabled = false;
                rbInst.Enabled = false; rbPort.Enabled = false; tb.Enabled = false; browse.Enabled = false;
                bar.Style = ProgressBarStyle.Marquee;
                bool dsk = cbDesk.Checked, mn = cbMenu.Checked;
                string ex = port ? null : existing;
                Thread th = new Thread(delegate()
                {
                    string err = DoInstall(target, port, dsk, mn, ex, delegate(string s2)
                    {
                        try { f.BeginInvoke(new MethodInvoker(delegate { status.Text = s2; })); } catch (Exception) { }
                    });
                    try
                    {
                        f.BeginInvoke(new MethodInvoker(delegate
                        {
                            bar.Style = ProgressBarStyle.Continuous;
                            running = false;
                            btn.Enabled = true;
                            if (err == null)
                            {
                                bar.Value = 100;
                                status.ForeColor = Color.FromArgb(94, 234, 212);
                                status.Text = port ? T("Pronto! O KoeDL portátil está em: ", "Done! Portable KoeDL is in: ") + target
                                    : (ex != null ? T("Pronto! O KoeDL foi atualizado.", "Done! KoeDL was updated.") : T("Pronto! O KoeDL foi instalado.", "Done! KoeDL is installed."));
                                btn.Text = T("Concluir", "Finish");
                                done = true;
                            }
                            else
                            {
                                bar.Value = 0;
                                status.ForeColor = Color.FromArgb(251, 113, 133);
                                status.Text = T("Não deu certo: ", "Failed: ") + err;
                                btn.Text = T("Fechar", "Close");
                                cbRun.Checked = false;
                                done = true;
                            }
                        }));
                    }
                    catch (Exception) { }
                });
                th.IsBackground = true;
                th.Start();
            };
            Application.Run(f);
        }

        static void Uninstall()
        {
            string exe = Application.ExecutablePath;
            string dir = Path.GetDirectoryName(exe);
            if (MessageBox.Show(
                T("Remover o KoeDL deste computador?\n\nSeus downloads não serão apagados.",
                  "Remove KoeDL from this computer?\n\nYour downloads will not be deleted."),
                "KoeDL", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            KillOthers();
            try { File.Delete(Path.Combine(Desktop(), "KoeDL.lnk")); } catch (Exception) { }
            try { File.Delete(Path.Combine(StartMenu(), "KoeDL.lnk")); } catch (Exception) { }
            try { Registry.CurrentUser.DeleteSubKeyTree(UKey, false); } catch (Exception) { }
            try
            {
                // so apaga os arquivos do proprio programa (nunca a pasta inteira) depois que este processo terminar
                ProcessStartInfo p = new ProcessStartInfo("cmd.exe",
                    "/c ping 127.0.0.1 -n 3 >nul & rmdir /s /q \"" + Path.Combine(dir, "bin") + "\" & del /f /q \"" + exe + "\" & rmdir \"" + dir + "\"");
                p.CreateNoWindow = true;
                p.UseShellExecute = false;
                Process.Start(p);
            }
            catch (Exception) { }
            MessageBox.Show(T("Removido.", "Removed."), "KoeDL");
        }
    }
}
