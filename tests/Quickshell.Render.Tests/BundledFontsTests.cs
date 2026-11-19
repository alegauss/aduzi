using Quickshell.Render;
using Vortice.DirectWrite;
using Xunit;

namespace Quickshell.Render.Tests;

/// <summary>
/// The face the client carries (QS402): found by name on a machine that never installed it, drawn
/// from its own Bold rather than a smeared Regular, and the width the choice rested on.
/// </summary>
public sealed class BundledFontsTests
{
    /// <summary>Its family is in the client's own collection, whatever Windows has installed.</summary>
    [Fact]
    public void TheBundledFamilyIsFoundByNameInTheClientsOwnCollection()
    {
        Assert.True(BundledFonts.Collection.FindFamilyName(BundledFonts.Family, out _),
                    $"{BundledFonts.Family} is not in the bundled collection");
    }

    /// <summary>
    /// The rasteriser answers the bundled family as it answers an installed one, Regular and Bold
    /// each from their own file: a Bold made by simulation would mean the Bold file never loaded.
    /// </summary>
    [Fact]
    public void TheRasteriserDrawsTheBundledRegularAndBoldFromTheirOwnFiles()
    {
        using GlyphRasteriser rasteriser = new();

        IDWriteFontFace regular = rasteriser.FaceFor(BundledFonts.Family, FontWeight.Normal, FontStyle.Normal);
        IDWriteFontFace bold = rasteriser.FaceFor(BundledFonts.Family, FontWeight.Bold, FontStyle.Normal);

        Assert.Equal(FontSimulations.None, regular.Simulations);
        Assert.Equal(FontSimulations.None, bold.Simulations);
        Assert.NotEqual(regular.NativePointer, bold.NativePointer);
    }

    /// <summary>
    /// Monospaced at 0.6 em, which is Vera Sans Mono's 0.602 to the hundredth: the reason it was the
    /// nearest face to MobaFont is that a line of it is as long as a line there.
    /// </summary>
    [Fact]
    public void ItsAdvanceIsVerasWidth()
    {
        using GlyphRasteriser rasteriser = new();

        IDWriteFontFace face = rasteriser.FaceFor(BundledFonts.Family, FontWeight.Normal, FontStyle.Normal);

        ushort[] glyphs = face.GetGlyphIndices([(uint)'M', (uint)'i', (uint)'0']);
        GlyphMetrics[] metrics = new GlyphMetrics[glyphs.Length];

        face.GetDesignGlyphMetrics(glyphs, metrics, false);

        double em = face.Metrics.DesignUnitsPerEm;

        Assert.All(metrics, metric => Assert.Equal(0.60, metric.AdvanceWidth / em, 2));
    }
}
