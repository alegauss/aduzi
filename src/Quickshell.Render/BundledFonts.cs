using System.Reflection;
using System.Runtime.InteropServices;
using Vortice.DirectWrite;

namespace Quickshell.Render;

/// <summary>
/// The faces the client carries, so its default draws the same on every machine (QS402).
///
/// <para><b>Noto Sans Mono, hinted Regular and Bold, unmodified.</b> The owner wanted the look of
/// MobaXterm's MobaFont, which is Bitstream Vera Sans Mono; Vera and DejaVu are under a licence OSI has
/// not approved, and every component the client ships is kept under one it has (QS378). Noto Sans Mono
/// is the nearest OSI-licensed face, under OFL-1.1, and Windows does not have it, so it travels inside
/// this assembly as the shader does. Its licence is in THIRD-PARTY-NOTICES.md.</para>
///
/// <para><b>A collection of its own, beside the system's.</b> The rasteriser asks this one by name
/// first and the installed collection after, so a bundled family is found exactly as an installed one
/// is, and the system's collection is still the one DirectWrite keeps cached. Merging the two into one
/// set would rebuild every installed family at every start to add two files.</para>
///
/// <para><b>Built once per process and never released.</b> The files are copied into DirectWrite's
/// in-memory loader, registered on the shared factory, and every rasteriser the process makes reads the
/// same collection.</para>
/// </summary>
public static class BundledFonts
{
    /// <summary>The family the bundled faces answer to, which is the default <c>fontFamily</c>.</summary>
    public const string Family = "Noto Sans Mono";

    private static readonly string[] Resources =
    [
        "Quickshell.Render.Fonts.NotoSansMono-Regular.ttf",
        "Quickshell.Render.Fonts.NotoSansMono-Bold.ttf",
    ];

    private static readonly Lazy<IDWriteFontCollection1> Built = new(Build, LazyThreadSafetyMode.ExecutionAndPublication);

    /// <summary>The bundled faces as a collection, made the first time anything asks.</summary>
    public static IDWriteFontCollection1 Collection => Built.Value;

    private static IDWriteFontCollection1 Build()
    {
        // The shared factory, as the rasteriser's is: a loader is registered on a factory, and a font
        // file made through one factory's loader is read through that factory.
        IDWriteFactory5 factory = DWrite.DWriteCreateFactory<IDWriteFactory5>(FactoryType.Shared);
        IDWriteInMemoryFontFileLoader loader = factory.CreateInMemoryFontFileLoader();

        factory.RegisterFontFileLoader(loader);

        using IDWriteFontSetBuilder1 builder = factory.CreateFontSetBuilder();
        Assembly assembly = typeof(BundledFonts).Assembly;

        foreach (string name in Resources)
        {
            using Stream stream = assembly.GetManifestResourceStream(name)
                                  ?? throw new InvalidOperationException($"the bundled font {name} is not in {assembly.GetName().Name}");

            byte[] data = new byte[stream.Length];

            stream.ReadExactly(data);

            GCHandle pinned = GCHandle.Alloc(data, GCHandleType.Pinned);

            try
            {
                // No owner object, so DirectWrite copies the bytes and the array can go.
                using IDWriteFontFile file = loader.CreateInMemoryFontFileReference(factory, pinned.AddrOfPinnedObject(), (uint)data.Length, null);

                builder.AddFontFile(file);
            }
            finally
            {
                pinned.Free();
            }
        }

        using IDWriteFontSet set = builder.CreateFontSet();

        return factory.CreateFontCollectionFromFontSet(set);
    }
}
