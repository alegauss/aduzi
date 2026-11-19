using System.Windows;
using System.Windows.Media;

namespace Quickshell.App;

/// <summary>
/// The one mapping from the theme a user chose to the one WPF paints with (QS83).
///
/// <para><b>Set on each window, in code, from here.</b> The two clients this one borrows its design
/// from keep <c>ThemeMode="System"</c> in each window's markup, because freewilly measured the
/// Application-wide setting and a value set from code rendering differently from that attribute.
/// Every window here is built in code, with no markup to carry the attribute, so what is kept is the
/// other half of their rule: the mode is decided in one place, set on every window this client
/// opens, never on the Application, and the chrome paints no colour of its own.</para>
/// </summary>
public static class Theme
{
    /// <summary>What WPF is told for a chosen theme: following the system is its own mode, not a reading taken once.</summary>
    public static ThemeMode Mode(ChromeTheme theme) => theme switch
    {
        ChromeTheme.Light => ThemeMode.Light,
        ChromeTheme.Dark => ThemeMode.Dark,
        _ => ThemeMode.System,
    };

    /// <summary>
    /// Gives a window the theme's own solid ground (QS403), which every window this client opens takes
    /// in its constructor, and the strong edge for its buttons and combo boxes once it is up (QS406).
    ///
    /// <para><b>Not Mica.</b> A window with no background of its own is drawn over the backdrop WPF's
    /// Fluent theme asks for, which is the wallpaper seen through a tint: a settings window on a warm
    /// wallpaper came out brown, and its fields and boxes, whose fills are a few per cent of white or
    /// black over whatever is behind them, nearly vanished. A contrast measured against a picture
    /// somebody else chose is not one this client can promise, so the ground is the base fill Home
    /// already used, light or dark with the theme, and every ratio in the contrast audit is against
    /// it.</para>
    /// </summary>
    public static void Ground(Window window)
    {
        ArgumentNullException.ThrowIfNull(window);

        window.SetResourceReference(Window.BackgroundProperty, "SolidBackgroundFillColorBaseBrush");

        // Once the theme's dictionaries are in the window, which is by the time it has loaded.
        window.Loaded += (_, _) => Stroke(window);
    }

    /// <summary>The keys Fluent's button and combo box templates draw their edge from, at rest, hovered and pressed.</summary>
    private static readonly string[] Edges =
    [
        "ButtonBorderBrush", "ButtonBorderBrushPointerOver", "ButtonBorderBrushPressed",
        "ComboBoxBorderBrush", "ComboBoxBorderBrushPointerOver", "ComboBoxBorderBrushPressed",
    ];

    /// <summary>
    /// Gives a window's buttons and combo boxes Fluent's strong stroke for their edge (QS406), in the
    /// theme the window has now. Called when it loads and again by whoever changes its theme.
    ///
    /// <para><b>Why a stroke.</b> Fluent draws them with a fill a few per cent off the ground and an
    /// elevation border at 1.3:1 on the dark ground and 1.5:1 on the light, and in the owner's
    /// settings window two buttons and a combo box read as lines of text. WCAG excuses a component its
    /// words identify; a person looking for the button does not. The strong stroke is what Fluent
    /// already gives a check box and a field's underline, so it is the theme's own colour for an edge
    /// that must be found, and it reads 3:1 or better on either ground.</para>
    ///
    /// <para><b>Why not an accent on the default button instead.</b> It would leave every other button
    /// a label, and the default here is often the act a question asks about — Delete it — which an
    /// accent would push at the reader.</para>
    ///
    /// <para><b>Why the window's resources.</b> The templates paint their border from these keys in
    /// their own triggers and never read a control's BorderBrush, and a window's own entries outrank
    /// the theme dictionaries merged into it. The value is the brush the theme has now, so a change of
    /// theme calls this again. A button the client draws itself, with its own template, reads none of
    /// these keys and keeps its look.</para>
    /// </summary>
    public static void Stroke(Window window)
    {
        ArgumentNullException.ThrowIfNull(window);

        foreach (string key in Edges)
        {
            window.Resources.Remove(key);
        }

        if (window.TryFindResource("ControlStrongStrokeColorDefaultBrush") is not Brush strong)
        {
            return;
        }

        foreach (string key in Edges)
        {
            window.Resources[key] = strong;
        }
    }

    /// <summary>
    /// Makes a piece of text the quieter kind, in the theme's own secondary colour, and hands it back
    /// (QS404). Not the primary at an opacity: that is a grey the theme never chose, a shade off what
    /// every other window says the same kind of text in.
    /// </summary>
    public static System.Windows.Controls.TextBlock Quiet(System.Windows.Controls.TextBlock text)
    {
        ArgumentNullException.ThrowIfNull(text);

        text.SetResourceReference(System.Windows.Controls.TextBlock.ForegroundProperty, "TextFillColorSecondaryBrush");

        return text;
    }
}
