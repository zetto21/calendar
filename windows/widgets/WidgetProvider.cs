using Microsoft.Windows.Widgets.Providers;
using System.Runtime.InteropServices;

namespace IlsangWidgets;

[Guid(Program.ClassId)]
[ComVisible(true), ComDefaultInterface(typeof(IWidgetProvider))]
public sealed class WidgetProvider : IWidgetProvider
{
    private sealed record Widget(string Id, string Definition, string Size, bool Active);
    private readonly Dictionary<string, Widget> widgets = new();
    private readonly object gate = new();
    private readonly Timer timer;
    private DateTime lastWrite;
    private DateTime lastDay;
    public WidgetProvider()
    {
        try
        {
            var manager = WidgetManager.GetDefault();
            var existing = manager.GetWidgetInfos();
            if (existing is not null)
                foreach (var info in existing) Remember(info.WidgetContext, false);
        }
        catch (Exception error) { Program.Log(error); }
        timer = new Timer(_ => RefreshChanged(), null, TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(3));
    }
    private Widget Remember(WidgetContext context, bool active)
    {
        var value = new Widget(context.Id, context.DefinitionId, context.Size.ToString(), active);
        lock (gate) widgets[value.Id] = value;
        return value;
    }
    public void CreateWidget(WidgetContext context) => Update(Remember(context, true));
    public void DeleteWidget(string id, string customState)
    {
        lock (gate)
        {
            widgets.Remove(id);
            if (widgets.Count == 0) { timer.Dispose(); Program.Stop.Set(); }
        }
    }
    public void Activate(WidgetContext context) => Update(Remember(context, true));
    public void Deactivate(string id) { lock (gate) if (widgets.TryGetValue(id, out var widget)) widgets[id] = widget with { Active = false }; }
    public void OnWidgetContextChanged(WidgetContextChangedArgs args)
    {
        var context = args.WidgetContext;
        bool active;
        lock (gate) active = widgets.TryGetValue(context.Id, out var widget) && widget.Active;
        Update(Remember(context, active));
    }
    public void OnActionInvoked(WidgetActionInvokedArgs args)
    {
        if (args.Verb == "open") Program.OpenCalendar();
        if (args.Verb == "refresh") Update(Remember(args.WidgetContext, true));
    }
    private void RefreshChanged()
    {
        try
        {
            var write = File.GetLastWriteTimeUtc(WidgetCards.SnapshotPath);
            var day = DateTime.Today;
            if (write == lastWrite && day == lastDay) return;
            lastWrite = write; lastDay = day;
            // Account changes and logout also erase cached cards while inactive.
            lock (gate) foreach (var widget in widgets.Values) Update(widget);
        }
        catch (Exception error) { Program.Log(error); }
    }
    private void Update(Widget widget)
    {
        try
        {
            lock (gate)
            {
                if (!widgets.ContainsKey(widget.Id)) return;
                WidgetManager.GetDefault().UpdateWidget(new WidgetUpdateRequestOptions(widget.Id) {
                    Template = WidgetCards.Build(widget.Definition, widget.Size, WidgetCards.ReadSnapshot(), DateTime.Today),
                    Data = "{}", CustomState = ""
                });
            }
        }
        catch (Exception error) { Program.Log(error); }
    }
}
