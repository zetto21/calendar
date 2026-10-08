using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.Windows.Widgets.Providers;
using WinRT;

namespace IlsangWidgets;

internal static class Program
{
    internal const string ClassId = "3CB28C80-3472-4CD0-B418-8D059DA85B96";
    internal static readonly ManualResetEvent Stop = new(false);
    [DllImport("ole32.dll")] private static extern int CoInitializeEx(IntPtr reserved, uint mode);
    [DllImport("ole32.dll")] private static extern void CoUninitialize();
    [DllImport("ole32.dll")] private static extern int CoRegisterClassObject(
        [MarshalAs(UnmanagedType.LPStruct)] Guid clsid, [MarshalAs(UnmanagedType.Interface)] IClassFactory factory,
        uint context, uint flags, out uint cookie);
    [DllImport("ole32.dll")] private static extern int CoRevokeClassObject(uint cookie);
    [DllImport("ole32.dll")] private static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint context, ref Guid iid, out IntPtr instance);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string? className, string title);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);
    internal static int Main(string[] args)
    {
        try
        {
            if (args.Contains("--self-test")) { SelfTest(); return 0; }
            if (args.Contains("--probe")) { Probe(); return 0; }
            if (!args.Any(a => a.Equals("-Embedding", StringComparison.OrdinalIgnoreCase) || a == "--provider"))
            { OpenCalendar(); return 0; }
            Marshal.ThrowExceptionForHR(CoInitializeEx(IntPtr.Zero, 0)); // MTA: COM calls are not blocked by WaitOne.
            var factory = new ProviderFactory();
            Marshal.ThrowExceptionForHR(CoRegisterClassObject(new Guid(ClassId), factory, 4, 1, out var cookie));
            Stop.WaitOne();
            CoRevokeClassObject(cookie);
            GC.KeepAlive(factory);
            CoUninitialize();
            return 0;
        }
        catch (Exception error) { Log(error); return 1; }
    }
    internal static void OpenCalendar()
    {
        try
        {
            var window = FindWindow(null, "일상 캘린더");
            if (window != IntPtr.Zero) { ShowWindow(window, 9); SetForegroundWindow(window); return; }
            var path = File.ReadAllText(Path.Combine(WidgetCards.DirectoryPath, "launcher.txt"), Encoding.Unicode);
            if (!Path.IsPathFullyQualified(path) || !File.Exists(path) || Path.GetFileName(path) != "calendar_app_flutter.exe") return;
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(path)! });
        }
        catch (Exception error) { Log(error); }
    }
    internal static void Log(Exception error)
    {
        try
        {
            Directory.CreateDirectory(WidgetCards.DirectoryPath);
            var path = Path.Combine(WidgetCards.DirectoryPath, "provider.log");
            if (File.Exists(path) && new FileInfo(path).Length > 128 * 1024) File.WriteAllText(path, "");
            // No event titles, tokens or snapshot content in logs.
            File.AppendAllText(path, $"{DateTime.UtcNow:O} {error.GetType().Name} 0x{error.HResult:X8}\n{error.StackTrace}\n");
        }
        catch { }
    }
    private static void SelfTest()
    {
        var now = new DateTime(2026, 2, 28);
        var snapshot = JsonNode.Parse("""{"signedIn":true,"events":[{"date":"2026-02-28","title":"회의 ${x} \"안녕\"","time":"09:00"},{"date":"2026-03-01","title":"내일 일정","time":null}]}""")!.AsObject();
        foreach (var mode in new[] { "today", "month", "upcoming" })
        foreach (var size in new[] { "Small", "Medium", "Large" })
        {
            var card = JsonNode.Parse(WidgetCards.Build(mode, size, snapshot, now))!;
            if (card["type"]!.GetValue<string>() != "AdaptiveCard") throw new Exception("Invalid card");
            var actions = card["actions"]!.AsArray();
            if (actions.Count != 1 || actions[0]?["verb"]?.GetValue<string>() != "open")
                throw new Exception("Widget must only show the open-calendar action");
            if (mode == "upcoming" && size != "Small" && !card.ToJsonString().Contains("\\uB0B4\\uC77C"))
                throw new Exception("Upcoming event missing");
            if (mode == "month" && card["body"]!.AsArray().Count(n => n?["type"]?.GetValue<string>() == "ColumnSet") != 5)
                throw new Exception("February calendar alignment incorrect");
        }
        snapshot["signedIn"] = false;
        var cleared = WidgetCards.Build("today", "Large", snapshot, now);
        if (cleared.Contains("09:00")) throw new Exception("Logout exposes events");
        Directory.CreateDirectory(WidgetCards.DirectoryPath);
        File.WriteAllText(Path.Combine(WidgetCards.DirectoryPath, "self-test.txt"), "WIDGET_CARDS_PASS");
    }
    private static void Probe()
    {
        Marshal.ThrowExceptionForHR(CoInitializeEx(IntPtr.Zero, 0));
        var clsid = new Guid(ClassId);
        var iid = GuidGenerator.GetIID(typeof(IWidgetProvider));
        Marshal.ThrowExceptionForHR(CoCreateInstance(ref clsid, IntPtr.Zero, 4, ref iid, out var instance));
        Marshal.Release(instance);
        CoUninitialize();
        Directory.CreateDirectory(WidgetCards.DirectoryPath);
        File.WriteAllText(Path.Combine(WidgetCards.DirectoryPath, "probe.txt"), "WIDGET_COM_ACTIVATION_PASS");
    }
}

[ComImport, Guid("00000001-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IClassFactory
{
    [PreserveSig] int CreateInstance(IntPtr outer, ref Guid iid, out IntPtr instance);
    [PreserveSig] int LockServer([MarshalAs(UnmanagedType.Bool)] bool locked);
}
[ComVisible(true), ClassInterface(ClassInterfaceType.None)]
internal sealed class ProviderFactory : IClassFactory
{
    private WidgetProvider? provider;
    public int CreateInstance(IntPtr outer, ref Guid iid, out IntPtr instance)
    {
        instance = IntPtr.Zero;
        if (outer != IntPtr.Zero) return unchecked((int)0x80040110);
        try
        {
            provider ??= new WidgetProvider();
            var inspectable = MarshalInspectable<IWidgetProvider>.FromManaged(provider);
            try { return Marshal.QueryInterface(inspectable, ref iid, out instance); }
            finally { Marshal.Release(inspectable); }
        }
        catch (Exception error) { Program.Log(error); return error.HResult; }
    }
    public int LockServer(bool locked) => 0;
}
