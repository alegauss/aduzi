using System.Windows;

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
    /// in its constructor.
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
