using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Quickshell.Transport;
using Xunit;

namespace Quickshell.App.Tests;

/// <summary>
/// Every window, in the light theme and the dark, read for contrast the way WCAG 2.2 reads it (QS403).
///
/// <para><b>Measured on the window as drawn, not on the palette.</b> Each window is shown, its
/// templates applied, and its visual tree walked. A piece of text is measured against what is behind
/// it there: every background above it composited down to the window's own, with each opacity on the
/// way multiplied in, because a 0.75 opacity on a help line is a colour nobody chose and the palette
/// does not list. 4.5:1 for text, 3:1 for large text (24 px, or 18.66 px bold), and 3:1 for the edge
/// of a field, a check box, a combo box or a button against what surrounds it (1.4.11) — the
/// stronger of its border and its fill, since either is how a person finds it.</para>
///
/// <para><b>A window with no background of its own is drawn over Mica</b>, which is the wallpaper
/// seen through a tint and not a colour this client controls. It is measured against the theme's
/// base fill, the colour Mica settles nearest, and the report says it was.</para>
///
/// <para>The report is written to <c>TestResults\contrast.md</c> on every run, read or not; the
/// assertion is on the failures alone.</para>
/// </summary>
public sealed class ContrastAuditTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"quickshell-contrast-{Guid.NewGuid():N}");

    public void Dispose()
    {
        Choice.Showing = null;

        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }

    /// <summary>One reading: where, what, the two colours, the ratio and the ratio it needs.</summary>
    private sealed record Reading(string Theme, string Window, string What, string Kind, Color Fore, Color Back,
                                  double Ratio, double Needs, bool OverBackdrop)
    {
        public bool Passes => Ratio + 0.005 >= Needs;
    }

    [Fact]
    public void EveryWindowIsReadableInTheLightThemeAndTheDark()
    {
        Directory.CreateDirectory(_directory);

        List<Reading> readings = [];

        foreach (ThemeMode theme in new[] { ThemeMode.Light, ThemeMode.Dark })
        {
            readings.AddRange(Sta.Run(() => Audit(theme)));
        }

        Write(readings);

        Reading[] failing = [.. readings.Where(reading => !reading.Passes)];

        Assert.True(failing.Length == 0,
                    $"{failing.Length} of {readings.Count} readings are below what WCAG asks; see TestResults\\contrast.md. First: "
                    + string.Join("; ", failing.Take(8).Select(each => $"{each.Theme} {each.Window} {each.What} {each.Ratio:0.00}:1 < {each.Needs}:1")));
    }

    private List<Reading> Audit(ThemeMode theme)
    {
        string name = theme == ThemeMode.Light ? "Light" : "Dark";
        List<Reading> readings = [];

        foreach ((string title, Func<Window> make) in Windows())
        {
            Window window = make();

            window.ThemeMode = theme;
            window.ShowActivated = false;
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            window.Left = 20;
            window.Top = 20;
            window.Show();

            try
            {
                Settle();
                readings.AddRange(Read(name, title, window, theme));
            }
            finally
            {
                window.Close();
            }
        }

        return readings;
    }

    /// <summary>The windows, each as the client opens it with something in it to read.</summary>
    private IEnumerable<(string Title, Func<Window> Make)> Windows()
    {
        string sessions = Path.Combine(_directory, "sessions.json");

        SessionTree.Of(new SessionNode
        {
            Children =
            [
                new SessionNode
                {
                    Name = "Work",
                    Settings = new SessionSettings { User = "deploy" },
                    Children = [new SessionNode { Name = "db", Host = "db1.example.com", Tags = ["prod"] }],
                },
                new SessionNode { Name = "pi", Host = "192.168.1.4" },
            ],
        }).WriteTo(sessions);

        string settings = Path.Combine(_directory, "settings.json");
        string policy = Path.Combine(_directory, "agent-policy.json");

        File.WriteAllText(policy, "{}");

        yield return ("Main window, Home", () =>
        {
            MainWindow main = new() { SessionsFile = sessions, SettingsPath = settings };

            main.RefreshSessions();
            main.ToggleFolder("Work");
            main.ShowHome();

            return main;
        });

        yield return ("Settings", () => new SettingsWindow(settings));
        yield return ("New session", () => new SessionDialog(SessionEditor.Creating(SessionTree.ReadFrom(sessions), "Work", "web")));
        yield return ("Choice", () =>
        {
            Choice? built = null;

            Choice.Showing = shown =>
            {
                built = shown;

                return null;
            };

            Choice.Ask(null, "Delete session", "Delete Work/db from your saved sessions?",
                       new ChoiceButton("Delete it", "delete"), new ChoiceButton("Keep it", "keep"));

            Choice.Showing = null;

            return built!;
        });
        yield return ("Command palette", () => new CommandPalette(
            [new Command("Open session", "Ctrl+Shift+O", new Nothing()), new Command("Split right", "Alt+Shift+Plus", new Nothing())]));
        yield return ("Quick connect", () => new QuickConnectWindow(new QuickConnect(new MainWindow { SessionsFile = sessions }, [])));
        yield return ("Sign in", () => new SignInDialog(new SignInQuestion(new SshEndpoint("db1.example.com", 22, "deploy"), "Password:", Echoed: false, MayRemember: true)));
        yield return ("Recording", () => new RecordingDialog("local-20261119", _directory, 1_000_000));
        yield return ("Vault export", () => new VaultExportDialog("sessions.kdbx", 3));
        yield return ("Vault import", () => new VaultImportDialog("sessions.kdbx"));
        yield return ("Forwards", () => new ForwardsWindow(() => []));
        yield return ("File browser", () => new FileBrowser(new LocalFiles(_directory), null));
        yield return ("Agent setup", () => new AgentSetupDialog("db1.example.com", "ssh-ed25519 AAAAC3Nza example", "Work/db", [["ls", "-l"]]));
        yield return ("Agent approval", () => new ApprovalDialog(new ApprovalRequest("1", "run-1",
            [new AskedCall("Work/db", "deploy@db1.example.com", ["prod"], "run", ["systemctl", "restart", "nginx"], null, null, "ask")])));
        yield return ("Policy change", () => new PolicyChangeDialog(policy));
    }

    private sealed class Nothing : ICommand
    {
        public event EventHandler? CanExecuteChanged { add { } remove { } }

        public bool CanExecute(object? parameter) => true;

        public void Execute(object? parameter)
        {
        }
    }

    /// <summary>Lets layout, templates and the loaded handlers run, which is when a window has its colours.</summary>
    private static void Settle()
    {
        DispatcherFrame frame = new();

        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, () => frame.Continue = false);
        Dispatcher.PushFrame(frame);
    }

    private static IEnumerable<Reading> Read(string theme, string title, Window window, ThemeMode mode)
    {
        Color floor = Opaque(window.Background) ?? Base(mode);
        bool backdrop = Opaque(window.Background) is null;

        HashSet<DependencyObject> measuredControls = [];

        foreach (DependencyObject node in Descendants(window))
        {
            // Hidden by Visibility, or by an opacity of nothing (a placeholder over typed text, a mark
            // that fades in): either way not on screen to be read.
            if (node is UIElement { IsVisible: false } || Faded(node) <= 0.01)
            {
                continue;
            }

            if (node is TextBlock text && text.Text.Trim().Length > 0 && text.Foreground is SolidColorBrush ink)
            {
                Color back = Behind(text, floor);
                Color fore = Over(ink.Color, ink.Opacity * Faded(text), back);
                double size = text.FontSize;
                bool large = size >= 24 || (size >= 18.66 && text.FontWeight.ToOpenTypeWeight() >= 700);

                // Text inside a disabled control is exempt in WCAG, as a placeholder is not.
                if (Disabled(text))
                {
                    continue;
                }

                yield return new Reading(theme, title, Quote(text.Text), "text", fore, back, Ratio(fore, back),
                                         large ? 3 : 4.5, backdrop);
            }
            // A field, a check box and a radio button are found by their edge (1.4.11). A button or a
            // combo box is found by its words, a chevron or a glyph, which are read as text above: WCAG
            // asks no boundary of a component its own text identifies.
            else if (node is TextBox or PasswordBox or CheckBox or RadioButton
                     && node is Control { IsEnabled: true } control && measuredControls.Add(control))
            {
                // A radio button or check box drawn as a segment (a toggle button's look) is found by its
                // words, as a button is; what has to show is which segment is chosen, so only the
                // checked one is measured, its fill against the ground.
                if (control is ToggleButton toggle && Segment(toggle))
                {
                    if (toggle.IsChecked == true)
                    {
                        Color ground = Behind(VisualTreeHelper.GetParent(control) ?? control, floor);
                        (double chosen, Color fill) = Boundary(control, ground);

                        yield return new Reading(theme, title, Describe(control), "chosen", fill, ground, chosen, 3, backdrop);
                    }

                    continue;
                }

                FrameworkElement framed = control;
                Color around = Behind(VisualTreeHelper.GetParent(control) ?? control, floor);
                (double ratio, Color edge) = Boundary(control, around);

                // A bare field inside a frame of its own (the sidebar's search) is found by the frame.
                if (ratio < 1.01 && Frame(control) is { } frame)
                {
                    framed = frame;
                    around = Behind(VisualTreeHelper.GetParent(frame) ?? frame, floor);
                    (ratio, edge) = Boundary(frame, around);
                }

                yield return new Reading(theme, title, Describe(control) + (ReferenceEquals(framed, control) ? string.Empty : " (its frame)"),
                                         "edge", edge, around, ratio, 3, backdrop);
            }
        }
    }

    /// <summary>Whether a radio button or check box draws no mark of its own: no ellipse, no box, a segment.</summary>
    private static bool Segment(ToggleButton toggle) =>
        !Descendants(toggle).Any(node => node is System.Windows.Shapes.Ellipse or System.Windows.Shapes.Rectangle
                                         || node is Border { Width: > 0 and < 24 });

    /// <summary>The nearest frame above a bare field: a border with a stroke, within a few levels.</summary>
    private static Border? Frame(DependencyObject field)
    {
        DependencyObject? at = VisualTreeHelper.GetParent(field);

        for (int level = 0; level < 4 && at is not null; level++, at = VisualTreeHelper.GetParent(at))
        {
            if (at is Border { BorderThickness: var thick } frame && (thick.Left + thick.Top + thick.Right + thick.Bottom) > 0)
            {
                return frame;
            }
        }

        return null;
    }

    private static bool Disabled(DependencyObject node)
    {
        for (DependencyObject? at = node; at is not null; at = VisualTreeHelper.GetParent(at))
        {
            if (at is UIElement { IsEnabled: false })
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// The strongest edge a control shows against what is around it: any border inside its template
    /// with a stroke, or any filled surface, composited over that surrounding colour.
    /// </summary>
    private static (double Ratio, Color Edge) Boundary(FrameworkElement control, Color around)
    {
        double best = 1;
        Color edge = around;

        foreach (DependencyObject node in Descendants(control).Prepend(control))
        {
            if (node is UIElement { IsVisible: false })
            {
                continue;
            }

            foreach (Brush? brush in Strokes(node))
            {
                foreach (Color stop in Colours(brush))
                {
                    Color drawn = Over(stop, Faded(node), around);
                    double ratio = Ratio(drawn, around);

                    if (ratio > best)
                    {
                        best = ratio;
                        edge = drawn;
                    }
                }
            }

            // A control's own template ends where another control starts (a combo box's toggle).
            if (!ReferenceEquals(node, control) && node is Control)
            {
                break;
            }
        }

        return (best, edge);
    }

    private static IEnumerable<Brush?> Strokes(DependencyObject node)
    {
        switch (node)
        {
            case Border border:
                if (border.BorderThickness is { } thick && (thick.Left + thick.Top + thick.Right + thick.Bottom) > 0)
                {
                    yield return border.BorderBrush;
                }

                yield return border.Background;
                break;

            case System.Windows.Shapes.Shape shape:
                if (shape.StrokeThickness > 0)
                {
                    yield return shape.Stroke;
                }

                yield return shape.Fill;
                break;
        }
    }

    private static IEnumerable<Color> Colours(Brush? brush) => brush switch
    {
        SolidColorBrush solid => [WithOpacity(solid.Color, solid.Opacity)],
        GradientBrush gradient => gradient.GradientStops.Select(stop => WithOpacity(stop.Color, gradient.Opacity)),
        _ => [],
    };

    private static Color WithOpacity(Color colour, double opacity) =>
        Color.FromArgb((byte)Math.Round(colour.A * opacity), colour.R, colour.G, colour.B);

    /// <summary>What is behind an element: every background above it, composited down to the floor.</summary>
    private static Color Behind(DependencyObject node, Color floor)
    {
        List<(Color Colour, double Opacity)> layers = [];

        for (DependencyObject? at = VisualTreeHelper.GetParent(node) ?? node; at is not null and not Window; at = VisualTreeHelper.GetParent(at))
        {
            Brush? brush = at switch
            {
                Panel panel => panel.Background,
                Border border => border.Background,
                Control control => control.Background,
                _ => null,
            };

            if (brush is SolidColorBrush { Color.A: > 0 } solid)
            {
                layers.Add((solid.Color, solid.Opacity * Faded(at)));

                if (solid.Color.A == 255 && solid.Opacity * Faded(at) >= 1)
                {
                    break;
                }
            }
        }

        Color result = floor;

        for (int index = layers.Count - 1; index >= 0; index--)
        {
            result = Over(layers[index].Colour, layers[index].Opacity, result);
        }

        return result;
    }

    /// <summary>The product of every opacity from the element up to the window.</summary>
    private static double Faded(DependencyObject node)
    {
        double opacity = 1;

        for (DependencyObject? at = node; at is not null; at = VisualTreeHelper.GetParent(at))
        {
            if (at is UIElement element)
            {
                opacity *= element.Opacity;
            }
        }

        return opacity;
    }

    private static Color? Opaque(Brush? brush) =>
        brush is SolidColorBrush { Color.A: 255 } solid && solid.Opacity >= 1 ? solid.Color : null;

    /// <summary>Fluent's base fill for a theme: where Mica settles with no wallpaper to tint it.</summary>
    private static Color Base(ThemeMode mode) =>
        mode == ThemeMode.Dark ? Color.FromRgb(0x20, 0x20, 0x20) : Color.FromRgb(0xF3, 0xF3, 0xF3);

    private static Color Over(Color top, double opacity, Color under)
    {
        double alpha = top.A / 255.0 * opacity;

        byte Mix(byte a, byte b) => (byte)Math.Round((a * alpha) + (b * (1 - alpha)));

        return Color.FromRgb(Mix(top.R, under.R), Mix(top.G, under.G), Mix(top.B, under.B));
    }

    private static double Ratio(Color one, Color two)
    {
        double a = Luminance(one);
        double b = Luminance(two);

        return (Math.Max(a, b) + 0.05) / (Math.Min(a, b) + 0.05);
    }

    private static double Luminance(Color colour)
    {
        static double Channel(byte value)
        {
            double c = value / 255.0;

            return c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);
        }

        return (0.2126 * Channel(colour.R)) + (0.7152 * Channel(colour.G)) + (0.0722 * Channel(colour.B));
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        int count = VisualTreeHelper.GetChildrenCount(root);

        for (int index = 0; index < count; index++)
        {
            DependencyObject child = VisualTreeHelper.GetChild(root, index);

            yield return child;

            foreach (DependencyObject below in Descendants(child))
            {
                yield return below;
            }
        }
    }

    private static string Describe(Control control)
    {
        string id = AutomationProperties.GetAutomationId(control);
        string name = AutomationProperties.GetName(control);
        string said = control is ContentControl { Content: string content } ? content : name;

        return $"{control.GetType().Name} {(id.Length > 0 ? id : Quote(said))}".Trim();
    }

    private static string Quote(string text)
    {
        string one = text.ReplaceLineEndings(" ").Trim();

        // An icon font's glyph is a private-use character no report can show: named by its code.
        if (one.Length is > 0 and <= 2 && one.All(each => each is >= '' and <= ''))
        {
            return string.Join(' ', one.Select(each => $"glyph U+{(int)each:X4}"));
        }

        return one.Length > 48 ? $"\"{one[..45]}…\"" : $"\"{one}\"";
    }

    private static string Hex(Color colour) => string.Create(CultureInfo.InvariantCulture, $"#{colour.R:X2}{colour.G:X2}{colour.B:X2}");

    private static void Write(IReadOnlyList<Reading> readings)
    {
        StringBuilder report = new();

        report.AppendLine("# Contrast, every window, light and dark");
        report.AppendLine();
        report.AppendLine("Text needs 4.5:1 (3:1 when large); a control's edge needs 3:1. A window marked * has no background of its own and is drawn over Mica, measured here against the theme's base fill.");
        report.AppendLine();
        report.AppendLine("| Theme | Window | Readings | Below | Worst |");
        report.AppendLine("|---|---|---:|---:|---|");

        foreach (IGrouping<(string Theme, string Window), Reading> group in readings.GroupBy(each => (each.Theme, each.Window)))
        {
            Reading worst = group.MinBy(each => each.Ratio / each.Needs)!;
            string mica = group.First().OverBackdrop ? " *" : string.Empty;

            report.AppendLine(string.Create(CultureInfo.InvariantCulture,
                $"| {group.Key.Theme} | {group.Key.Window}{mica} | {group.Count()} | {group.Count(each => !each.Passes)} | {worst.What} {worst.Ratio:0.00}:1 of {worst.Needs}:1 |"));
        }

        report.AppendLine();
        report.AppendLine("## Below what WCAG asks");
        report.AppendLine();
        report.AppendLine("| Theme | Window | What | Kind | Fore | Back | Ratio | Needs |");
        report.AppendLine("|---|---|---|---|---|---|---:|---:|");

        foreach (Reading each in readings.Where(reading => !reading.Passes).OrderBy(reading => reading.Theme).ThenBy(reading => reading.Window).ThenBy(reading => reading.Ratio))
        {
            report.AppendLine(string.Create(CultureInfo.InvariantCulture,
                $"| {each.Theme} | {each.Window} | {each.What.Replace("|", "\\|", StringComparison.Ordinal)} | {each.Kind} | {Hex(each.Fore)} | {Hex(each.Back)} | {each.Ratio:0.00} | {each.Needs} |"));
        }

        string? root = AppContext.BaseDirectory;

        while (root is not null && !Directory.Exists(Path.Combine(root, ".git")) && !File.Exists(Path.Combine(root, "AGENTS.md")))
        {
            root = Path.GetDirectoryName(root);
        }

        string folder = Path.Combine(root ?? Path.GetTempPath(), "TestResults");

        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "contrast.md"), report.ToString());
    }
}
