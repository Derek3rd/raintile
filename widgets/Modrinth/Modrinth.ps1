# Modrinth widget for Raintile: the instances of Modrinth App, written to the
# widget's list (one per line: "<name>|<last played>|<icon>|<address>"), the
# last played first. Modrinth App keeps them in %APPDATA%\ModrinthApp\app.db
# (SQLite): it is read with the SQLite of Windows (winsqlite3.dll), read only,
# also while Modrinth App is open. The list is written again only when the
# database changed since the last time.

param([Parameter(Mandatory = $true)][string]$Out)

$ErrorActionPreference = 'Stop'
$db = Join-Path $env:APPDATA 'ModrinthApp\app.db'
if (-not (Test-Path -LiteralPath $db)) {
    [IO.File]::WriteAllText($Out, "Modrinth App not found|||`r`n", (New-Object System.Text.UTF8Encoding $false))
    exit 0
}

# Nothing new: the list is newer than the database (and its -wal)
$changed = (Get-Item -LiteralPath $db).LastWriteTimeUtc
$wal = "$db-wal"
if (Test-Path -LiteralPath $wal) {
    $w = (Get-Item -LiteralPath $wal).LastWriteTimeUtc
    if ($w -gt $changed) { $changed = $w }
}
if ((Test-Path -LiteralPath $Out) -and (Get-Item -LiteralPath $Out).LastWriteTimeUtc -gt $changed) { exit 0 }

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class ModrinthDb
{
    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_open_v2", CallingConvention = CallingConvention.StdCall)]
    static extern int Open(byte[] file, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_prepare_v2", CallingConvention = CallingConvention.StdCall)]
    static extern int Prepare(IntPtr db, byte[] sql, int bytes, out IntPtr stmt, IntPtr tail);
    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_step", CallingConvention = CallingConvention.StdCall)]
    static extern int Step(IntPtr stmt);
    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_text", CallingConvention = CallingConvention.StdCall)]
    static extern IntPtr Text(IntPtr stmt, int col);
    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_finalize", CallingConvention = CallingConvention.StdCall)]
    static extern int Done(IntPtr stmt);
    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_close_v2", CallingConvention = CallingConvention.StdCall)]
    static extern int Close(IntPtr db);

    static byte[] Z(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }

    static string Str(IntPtr stmt, int col)
    {
        IntPtr p = Text(stmt, col);
        if (p == IntPtr.Zero) return "";
        var bytes = new List<byte>();
        for (int i = 0; ; i++) { byte b = Marshal.ReadByte(p, i); if (b == 0) break; bytes.Add(b); }
        return Encoding.UTF8.GetString(bytes.ToArray());
    }

    // The rows of the first query that works (newer and older Modrinth App),
    // or null if the database cannot be opened
    public static List<string[]> Query(string file, string[] queries, int columns)
    {
        IntPtr db;
        // read only (mode=ro), as a URI (0x40)
        if (Open(Z("file:" + file.Replace('\\', '/') + "?mode=ro"), out db, 0x01 | 0x40, IntPtr.Zero) != 0)
        {
            if (db != IntPtr.Zero) Close(db);
            return null;
        }
        try
        {
            foreach (string sql in queries)
            {
                IntPtr stmt;
                if (Prepare(db, Z(sql), -1, out stmt, IntPtr.Zero) != 0 || stmt == IntPtr.Zero) continue;
                var rows = new List<string[]>();
                try
                {
                    while (Step(stmt) == 100)
                    {
                        var row = new string[columns];
                        for (int c = 0; c < columns; c++) row[c] = Str(stmt, c);
                        rows.Add(row);
                    }
                }
                finally { Done(stmt); }
                return rows;
            }
            return null;
        }
        finally { Close(db); }
    }
}
'@

$rows = [ModrinthDb]::Query($db, @(
        "SELECT id, name, icon_path, IFNULL(last_played, 0) FROM instances WHERE install_stage IS NULL OR install_stage = 'installed' ORDER BY IFNULL(last_played, 0) DESC, name COLLATE NOCASE",
        "SELECT id, name, '', 0 FROM instances ORDER BY name COLLATE NOCASE"), 4)
if ($null -eq $rows) { exit 1 } # not readable now: the old list stays

function Clean([string]$s) { return ($s -replace '[|\r\n]', ' ').Trim() }

# "today", "yesterday", "3 days ago", or the date
function Ago([long]$unix) {
    if ($unix -le 0) { return 'Not played yet' }
    $when = [DateTimeOffset]::FromUnixTimeSeconds($unix).LocalDateTime
    $days = ((Get-Date).Date - $when.Date).Days
    if ($days -le 0) { return 'Played today' }
    if ($days -eq 1) { return 'Played yesterday' }
    if ($days -lt 7) { return "Played $days days ago" }
    return 'Played ' + $when.ToString('d MMM yyyy', [Globalization.CultureInfo]::InvariantCulture)
}

$lines = foreach ($r in $rows) {
    $id = Clean $r[0]
    if ($id -eq '') { continue }
    $name = Clean $r[1]
    if ($name -eq '') { $name = $id }
    $icon = Clean $r[2]
    if ($icon -ne '' -and -not (Test-Path -LiteralPath $icon)) { $icon = '' }
    # the id in the address: encoded (spaces and brackets of the older ones),
    # the colon kept
    $address = 'modrinth://launch/instance/' + ([Uri]::EscapeDataString($id) -replace '%3A', ':')
    '{0}|{1}|{2}|{3}' -f $name, (Ago ([long]$r[3])), $icon, $address
}
$text = if ($lines) { ($lines -join "`r`n") + "`r`n" } else { "No instances in Modrinth App|||`r`n" }
[IO.File]::WriteAllText("$Out.tmp", $text, (New-Object System.Text.UTF8Encoding $false))
Move-Item -LiteralPath "$Out.tmp" -Destination $Out -Force
