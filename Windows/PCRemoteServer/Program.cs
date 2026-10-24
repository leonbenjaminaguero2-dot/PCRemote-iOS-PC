using System.Drawing;
using System.Drawing.Imaging;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Windows.Forms;

// PC Remote local companion server. Keep it on your trusted LAN; do not port-forward it.
internal static class Program
{
    private const int Port = 8765;
    private static readonly string Pin = Environment.GetEnvironmentVariable("PCREMOTE_PIN") ?? ReadOrCreatePin();
    private static readonly HttpListener Listener = new();

    [STAThread]
    private static async Task Main()
    {
        Listener.Prefixes.Add($"http://+:{Port}/");
        try { Listener.Start(); }
        catch (HttpListenerException ex)
        {
            Console.Error.WriteLine($"No se pudo iniciar el servidor: {ex.Message}\nProbá ejecutar como administrador una vez o revisar la reserva de URL de Windows.");
            return;
        }
        Console.WriteLine("PC Remote Server iniciado.");
        Console.WriteLine($"PIN de emparejamiento: {Pin}");
        Console.WriteLine($"Puerto: {Port}. Usalo solo en tu red local y no abras este puerto a Internet.");
        Console.WriteLine("Dejá esta ventana abierta mientras usás PC Remote. Ctrl+C para salir.");
        while (Listener.IsListening)
        {
            HttpListenerContext context;
            try { context = await Listener.GetContextAsync(); }
            catch (HttpListenerException) { break; }
            _ = Task.Run(() => Handle(context));
        }
    }

    private static async Task Handle(HttpListenerContext c)
    {
        try
        {
            c.Response.Headers["Cache-Control"] = "no-store";
            c.Response.Headers["X-Content-Type-Options"] = "nosniff";
            if (!string.Equals(c.Request.Headers["X-PCRemote-Pin"], Pin, StringComparison.Ordinal))
            { await Respond(c, 401, "application/json", "{\"error\":\"PIN incorrecto\"}"); return; }

            var path = c.Request.Url?.AbsolutePath ?? "/";
            if (path == "/api/status" && c.Request.HttpMethod == "GET")
            {
                var payload = JsonSerializer.Serialize(new { computer = Environment.MachineName, os = Environment.OSVersion.VersionString, screen = "ready" });
                await Respond(c, 200, "application/json", payload); return;
            }
            if (path == "/api/screen.jpg" && c.Request.HttpMethod == "GET")
            {
                using var bmp = new Bitmap(Screen.PrimaryScreen?.Bounds.Width ?? 1280, Screen.PrimaryScreen?.Bounds.Height ?? 720);
                using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(Screen.PrimaryScreen?.Bounds.Location ?? Point.Empty, Point.Empty, bmp.Size);
                using var ms = new MemoryStream(); bmp.Save(ms, ImageFormat.Jpeg);
                var bytes = ms.ToArray(); c.Response.StatusCode = 200; c.Response.ContentType = "image/jpeg"; c.Response.ContentLength64 = bytes.Length;
                await c.Response.OutputStream.WriteAsync(bytes); c.Response.Close(); return;
            }
            if (path == "/api/power" && c.Request.HttpMethod == "POST")
            {
                var body = await ReadBody(c); var action = body.RootElement.TryGetProperty("action", out var a) ? a.GetString() : "";
                switch (action)
                {
                    case "shutdown": ProcessStart("shutdown", "/s /t 5"); break;
                    case "restart": ProcessStart("shutdown", "/r /t 5"); break;
                    case "sleep": SetSuspendState(false, false, false); break;
                    case "lock": LockWorkStation(); break;
                    default: await Respond(c, 400, "application/json", "{\"error\":\"Acción no permitida\"}"); return;
                }
                await Respond(c, 200, "application/json", "{\"ok\":true}"); return;
            }
            if (path == "/api/input" && c.Request.HttpMethod == "POST")
            {
                var body = await ReadBody(c); var type = body.RootElement.TryGetProperty("type", out var t) ? t.GetString() : "";
                if (type == "key" && body.RootElement.TryGetProperty("key", out var keyValue))
                {
                    var key = keyValue.GetString() ?? "";
                    if (!TryKey(key, out var vk)) { await Respond(c, 400, "application/json", "{\"error\":\"Tecla no permitida\"}"); return; }
                    Key(vk); await Respond(c, 200, "application/json", "{\"ok\":true}"); return;
                }
                if (type == "mouse")
                {
                    var x = body.RootElement.TryGetProperty("x", out var xv) ? Math.Clamp(xv.GetDouble(), 0, 1) : 0.5;
                    var y = body.RootElement.TryGetProperty("y", out var yv) ? Math.Clamp(yv.GetDouble(), 0, 1) : 0.5;
                    var button = body.RootElement.TryGetProperty("button", out var bv) ? bv.GetString() : "move";
                    var bounds = Screen.PrimaryScreen?.Bounds ?? new Rectangle(0, 0, 1920, 1080);
                    SetCursorPos(bounds.Left + (int)(x * (bounds.Width - 1)), bounds.Top + (int)(y * (bounds.Height - 1)));
                    if (button == "left") MouseClick(0x0002, 0x0004); else if (button == "right") MouseClick(0x0008, 0x0010);
                    await Respond(c, 200, "application/json", "{\"ok\":true}"); return;
                }
                await Respond(c, 400, "application/json", "{\"error\":\"Entrada no válida\"}"); return;
            }
            await Respond(c, 404, "application/json", "{\"error\":\"No encontrado\"}");
        }
        catch (Exception ex) { try { await Respond(c, 500, "application/json", JsonSerializer.Serialize(new { error = ex.Message })); } catch { } }
    }

    private static async Task<JsonDocument> ReadBody(HttpListenerContext c)
    { using var reader = new StreamReader(c.Request.InputStream, c.Request.ContentEncoding); return JsonDocument.Parse(await reader.ReadToEndAsync()); }
    private static async Task Respond(HttpListenerContext c, int status, string contentType, string text)
    { var bytes = Encoding.UTF8.GetBytes(text); c.Response.StatusCode = status; c.Response.ContentType = contentType; c.Response.ContentLength64 = bytes.Length; await c.Response.OutputStream.WriteAsync(bytes); c.Response.Close(); }
    private static void ProcessStart(string file, string args) => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(file, args) { CreateNoWindow = true, UseShellExecute = false });
    private static string ReadOrCreatePin()
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PCRemote", "pin.txt");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        if (File.Exists(path)) return File.ReadAllText(path).Trim();
        var pin = Random.Shared.Next(100000, 999999).ToString(); File.WriteAllText(path, pin); return pin;
    }
    private static bool TryKey(string key, out ushort vk)
    {
        vk = key.ToUpperInvariant() switch { "SPACE" => 0x20, "ENTER" => 0x0D, "SHIFT" => 0x10, "CTRL" => 0x11, "ALT" => 0x12, "TAB" => 0x09, "ESC" => 0x1B, "UP" => 0x26, "DOWN" => 0x28, "LEFT" => 0x25, "RIGHT" => 0x27, "BACKSPACE" => 0x08, "VOLUME_UP" => 0xAF, "VOLUME_DOWN" => 0xAE, "VOLUME_MUTE" => 0xAD, _ when key.Length == 1 && char.IsLetterOrDigit(key[0]) => (ushort)char.ToUpperInvariant(key[0]), _ => 0 };
        return vk != 0;
    }
    private static void Key(ushort vk) { keybd_event((byte)vk, 0, 0, UIntPtr.Zero); keybd_event((byte)vk, 0, 2, UIntPtr.Zero); }
    private static void MouseClick(uint down, uint up) { mouse_event(down, 0, 0, 0, UIntPtr.Zero); mouse_event(up, 0, 0, 0, UIntPtr.Zero); }
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] private static extern bool LockWorkStation();
    [DllImport("powrprof.dll", SetLastError = true)] private static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);
}
