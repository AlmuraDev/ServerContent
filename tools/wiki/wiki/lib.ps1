Add-Type -AssemblyName System.Web.Extensions
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System; using System.Text;
public static class JsonClean {
  public static string Clean(string s) {
    var sb = new StringBuilder(s.Length);
    int n = s.Length; bool inStr = false;
    for (int i = 0; i < n; i++) {
      char c = s[i];
      if (inStr) {
        sb.Append(c);
        if (c == '\\' && i + 1 < n) { sb.Append(s[++i]); }
        else if (c == '"') inStr = false;
        continue;
      }
      if (c == '"') { inStr = true; sb.Append(c); continue; }
      if (c == '/' && i + 1 < n && s[i+1] == '/') { while (i < n && s[i] != '\n') i++; sb.Append('\n'); continue; }
      if (c == '/' && i + 1 < n && s[i+1] == '*') { i += 2; while (i + 1 < n && !(s[i]=='*' && s[i+1]=='/')) i++; i++; continue; }
      sb.Append(c);
    }
    // remove trailing commas
    var o = new StringBuilder(sb.Length); string t = sb.ToString(); inStr = false;
    for (int i = 0; i < t.Length; i++) {
      char c = t[i];
      if (inStr) { o.Append(c); if (c=='\\' && i+1<t.Length) o.Append(t[++i]); else if (c=='"') inStr=false; continue; }
      if (c == '"') { inStr = true; o.Append(c); continue; }
      if (c == ',') {
        int j = i + 1; while (j < t.Length && char.IsWhiteSpace(t[j])) j++;
        if (j < t.Length && (t[j]=='}' || t[j]==']')) continue;
      }
      o.Append(c);
    }
    return o.ToString();
  }
}
"@
$script:ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$script:ser.MaxJsonLength = [int]::MaxValue
$script:ser.RecursionLimit = 200
$script:failures = New-Object System.Collections.ArrayList
function Convert-Obj($o, [string]$path) {
  if ($o -is [System.Collections.IDictionary]) {
    $r = [ordered]@{}
    foreach ($k in $o.Keys) {
      if ($r.Contains([string]$k)) { [void]$script:failures.Add("$path :: duplicate key (case-insensitive) '$k'"); continue }
      $r[[string]$k] = Convert-Obj $o[$k] $path
    }
    return $r
  }
  if ($o -is [System.Collections.IEnumerable] -and $o -isnot [string]) {
    $l = New-Object System.Collections.ArrayList
    foreach ($x in $o) { [void]$l.Add((Convert-Obj $x $path)) }
    return ,($l.ToArray())
  }
  return $o
}
function Read-Json([string]$path) {
  try {
    $txt = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $txt = [JsonClean]::Clean($txt)
    if ($txt.Trim().Length -eq 0) { return $null }
    return (Convert-Obj ($script:ser.DeserializeObject($txt)) $path)
  } catch { [void]$script:failures.Add("$path :: $($_.Exception.Message)"); return $null }
}

