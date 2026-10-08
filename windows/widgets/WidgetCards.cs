using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace IlsangWidgets;

internal static class WidgetCards
{
    internal static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "IlsangCalendar", "widgets");
    internal static readonly string SnapshotPath = Path.Combine(DirectoryPath, "snapshot.json");
    internal static JsonObject ReadSnapshot()
    {
        try
        {
            // Share delete permits atomic replacement by the main application.
            using var input = new FileStream(SnapshotPath, FileMode.Open, FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            if (input.Length > 1024 * 1024) return Empty();
            return JsonNode.Parse(input) as JsonObject ?? Empty();
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException)
        { return Empty(); }
    }
    private static JsonObject Empty() => new() { ["signedIn"] = false, ["events"] = new JsonArray() };
    private static JsonObject Text(string text, string size = "Default", bool bold = false) => new()
    {
        // Event titles are literal text, never Adaptive Card template expressions.
        ["type"] = "TextBlock", ["text"] = text.Replace("${", "$\u200b{"), ["wrap"] = true,
        ["size"] = size, ["weight"] = bold ? "Bolder" : "Default"
    };
    private static string Value(JsonNode? node, string key) => node?[key]?.GetValue<string>() ?? "";
    internal static string Build(string definition, string size, JsonObject snapshot, DateTime today)
    {
        var signedIn = snapshot["signedIn"]?.GetValue<bool>() == true;
        var body = new JsonArray();
        var title = definition switch { "month" => $"{today:yyyy}년 {today.Month}월", "upcoming" => "다가오는 일정", _ => "오늘 일정" };
        body.Add(Text(title, "Large", true));
        if (definition != "month") body.Add(Text(today.ToString("M월 d일 dddd", CultureInfo.GetCultureInfo("ko-KR")), "Small"));
        var events = signedIn ? (snapshot["events"] as JsonArray ?? new JsonArray()).OfType<JsonObject>()
            .Where(e => DateTime.TryParseExact(Value(e, "date"), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _))
            .OrderBy(e => Value(e, "date")).ThenBy(e => Value(e, "time")).ToArray() : [];
        if (definition == "month")
        {
            var first = new DateTime(today.Year, today.Month, 1);
            var offset = (int)first.DayOfWeek;
            var count = DateTime.DaysInMonth(today.Year, today.Month);
            body.Add(WeekRow(["일", "월", "화", "수", "목", "금", "토"]));
            var occupied = events.Select(e => Value(e, "date")).ToHashSet();
            for (var row = 0; row < (offset + count + 6) / 7; row++)
            {
                var labels = Enumerable.Range(0, 7).Select(column => {
                    var day = row * 7 + column - offset + 1;
                    if (day < 1 || day > count) return " ";
                    var date = first.AddDays(day - 1).ToString("yyyy-MM-dd");
                    return (day == today.Day ? $"[{day}]" : day.ToString()) + (occupied.Contains(date) ? "·" : "");
                }).ToArray();
                body.Add(WeekRow(labels));
            }
            if (size == "Small") return Serialize(body);
        }
        if (!signedIn) body.Add(Text("캘린더 앱에서 로그인하면 일정이 표시됩니다.", "Small"));
        else
        {
            var dateKey = today.ToString("yyyy-MM-dd");
            var selected = events.Where(e => definition == "upcoming" ? string.CompareOrdinal(Value(e, "date"), dateKey) >= 0 : Value(e, "date") == dateKey).ToArray();
            if (selected.Length == 0) body.Add(Text("등록된 일정이 없습니다.", "Small"));
            var limit = size == "Small" ? 1 : size == "Medium" ? (definition == "month" ? 1 : 3) : 7;
            foreach (var e in selected.Take(limit))
            {
                var time = Value(e, "time");
                var label = (definition == "upcoming" ? Value(e, "date")[5..] + " · " : "") + (time.Length == 0 ? "하루 종일" : time);
                body.Add(Text(label + "  " + Value(e, "title"), "Small"));
            }
            if (selected.Length > limit) body.Add(Text($"외 {selected.Length - limit}개 일정", "Small"));
        }
        if (size == "Large") body.Add(Text("앱에서 마지막으로 동기화한 일정", "Small"));
        return Serialize(body);
    }
    private static JsonObject WeekRow(string[] labels) => new()
    {
        ["type"] = "ColumnSet", ["spacing"] = "Small",
        ["columns"] = new JsonArray(labels.Select(label => (JsonNode)new JsonObject {
            ["type"] = "Column", ["width"] = "stretch",
            ["items"] = new JsonArray(new JsonObject {
                ["type"] = "TextBlock", ["text"] = label, ["size"] = "Small",
                ["horizontalAlignment"] = "Center", ["spacing"] = "None"
            })
        }).ToArray())
    };
    private static string Serialize(JsonArray body) => new JsonObject {
        ["$schema"] = "http://adaptivecards.io/schemas/adaptive-card.json", ["type"] = "AdaptiveCard",
        ["version"] = "1.5", ["body"] = body,
        ["actions"] = new JsonArray(
            new JsonObject { ["type"] = "Action.Execute", ["title"] = "캘린더 열기", ["verb"] = "open" },
            new JsonObject { ["type"] = "Action.Execute", ["title"] = "새로고침", ["verb"] = "refresh" })
    }.ToJsonString();
}
