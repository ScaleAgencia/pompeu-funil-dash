# ============================================================================
#  Webinario Pompeu - Funil  |  build.ps1  (PowerShell 5.1 safe, ANSI-friendly)
#  Reads Google Sheets via gviz CSV (read-only) and writes ./data.js
#  Two weekly webinar funnels: SEGUNDA (WBN-2026-S*) and TERCA (WBN-2026-L*)
#  Tax x1.1385 on META spend only (Google raw). Leadscore 8-dim 0..15.
#  NOTE: keep this file ASCII-only. Match accented survey answers by de-accent.
# ============================================================================
param([string]$Mode = 'all')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- rules --------------------------------------------------------------
$TAX        = 1.1385      # imposto Meta
$QUENTE_MIN = 11          # score >= 11 => Quente (Qualificado)
$MORNO_MIN  = 5           # 5..10 => Morno ; 0..4 => Frio
$SURVEY_START = '2026-07-10'

$LID = '1uRdsI3QhyvbRT7Q0sZa8y9DiFWOt8yaY68F134zrO20'   # leads + pesquisa
$QID = '1RlFtbOJq4LUS8nc3MrR6C9-dvYA5-mSVpVQsHcPGNEE'   # queries

# tab gids
$G_LEADS_TERCA = 0
$G_LEADS_SEG   = 986552728
$G_PESQ_TERCA  = 674160845
$G_PESQ_SEG    = 272892171
$G_META_TERCA  = 0
$G_GOOG_TERCA  = 837001685
$G_META_SEG    = 1484394087
$G_GOOG_SEG    = 968000625

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataDir = Join-Path $root 'data'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

# ---- helpers ------------------------------------------------------------
function Get-Csv($id, $gid, $name) {
  $url = "https://docs.google.com/spreadsheets/d/$id/gviz/tq?tqx=out:csv&gid=$gid"
  $out = Join-Path $dataDir "$name.csv"
  if ($env:POMPEU_REUSE -eq '1' -and (Test-Path $out)) { return $out }
  for ($try = 1; $try -le 4; $try++) {
    try {
      # WebClient streams to disk (Invoke-WebRequest is ~50x slower on large files in PS5.1)
      $wc = New-Object System.Net.WebClient
      $wc.Encoding = [Text.Encoding]::UTF8
      $wc.Headers.Add('User-Agent', 'Mozilla/5.0 pompeu-dash')
      $wc.DownloadFile($url, $out)
      $wc.Dispose()
      break
    } catch { if ($try -eq 4) { throw }; Start-Sleep -Seconds ([Math]::Pow(2, $try)) }
  }
  return $out
}

# fast CSV reader: gviz quotes every field. Split on the literal  ","  boundary.
function Read-Rows($file) {
  $lines = [System.IO.File]::ReadAllLines($file, [Text.Encoding]::UTF8)
  $rows = New-Object System.Collections.ArrayList
  for ($i = 1; $i -lt $lines.Length; $i++) {
    $ln = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    if ($ln.Length -ge 2 -and $ln[0] -eq '"' -and $ln[$ln.Length - 1] -eq '"') {
      $f = $ln.Substring(1, $ln.Length - 2) -split '","', -1
    } else {
      $f = $ln -split ',', -1
      for ($k = 0; $k -lt $f.Length; $k++) { $f[$k] = $f[$k].Trim('"') }
    }
    [void]$rows.Add($f)
  }
  return $rows
}

function PNum($s) {
  if ($null -eq $s) { return 0.0 }
  $s = ([string]$s).Trim()
  if ($s -eq '') { return 0.0 }
  $s = $s -replace '\.', ''      # drop thousands dots (decimals use comma here)
  $s = $s -replace ',', '.'
  $d = 0.0
  [void][double]::TryParse($s, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)
  return $d
}

function DKey($s) {              # -> yyyy-mm-dd or ''
  if ($null -eq $s) { return '' }
  $s = ([string]$s).Trim()
  if ($s -match '^(\d{4})-(\d{2})-(\d{2})') { return "$($matches[1])-$($matches[2])-$($matches[3])" }
  if ($s -match '^(\d{1,2})/(\d{1,2})/(\d{4})') {
    return ('{0}-{1:D2}-{2:D2}' -f $matches[3], [int]$matches[2], [int]$matches[1])
  }
  return ''
}

function Iif($c, $a, $b) { if ($c) { return $a } else { return $b } }
function EmKey($s) { if ($null -eq $s) { return '' }; return (([string]$s) -replace '\s', '').ToLowerInvariant() }
function PhKey($s) {
  if ($null -eq $s) { return '' }
  $d = ([string]$s) -replace '\D', ''
  if ($d.Length -ge 12 -and $d.StartsWith('55')) { $d = $d.Substring(2) }
  if ($d.Length -gt 11) { $d = $d.Substring($d.Length - 11) }
  return $d
}

function Deacc($s) {
  if ($null -eq $s -or $s -eq '') { return '' }
  $n = ([string]$s).Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach ($c in $n.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$sb.Append($c)
    }
  }
  return $sb.ToString().ToLowerInvariant()
}

# ---- leadscore: one function per dimension (de-accented -like matching) --
function PtIdade($a) {
  $t = Deacc $a; if ($t -eq '') { return 1 }
  if ($t -like '*51 a 60*' -or $t -like '*61 anos*' -or $t -like '*50 anos ou mais*') { return 3 }
  if ($t -like '*31 a 50*' -or $t -like '*31 a 49*') { return 2 }
  if ($t -like '*20 a 30*' -or $t -like '*25 a 30*' -or $t -like '*menos de 20*' -or $t -like '*ate 24*') { return 0 }
  return 1
}
function PtRenda($a) {
  $t = Deacc $a; if ($t -eq '') { return 1 }
  if ($t -like '*possuo*') { return 0 }
  if ($t -like '*acima*10.000*' -or $t -like '*acima de r10.000*') { return 3 }
  if ($t -like '*5.000*10.000*') { return 2 }
  if ($t -like '*2.000*5.000*') { return 2 }
  if ($t -like '*ate*2.000*' -or $t -like '*r2.000*') { return 1 }
  return 1
}
function PtMotiv($a) {
  $t = Deacc $a; if ($t -eq '') { return 1 }
  if ($t -like '*futuro*' -or $t -like '*aposentadoria*' -or $t -like '*perdendo tempo*') { return 2 }
  if ($t -like '*seguranca*' -or $t -like '*renda extra*') { return 1 }
  if ($t -like '*poupanca*') { return 0 }
  return 1
}
function PtTrava($a) {
  $t = Deacc $a; if ($t -eq '') { return 1 }
  if ($t -like '*confianca*' -or $t -like '*onde investir*') { return 2 }
  if ($t -like '*falta de tempo*') { return 1 }
  if ($t -like '*medo de perder*' -or $t -like '*falta de dinheiro*' -or $t -like '*tarde demais*') { return 0 }
  return 1
}
function PtValor($a) {
  $t = Deacc $a; if ($t -eq '') { return 1 }
  if ($t -like '*acima*100.000*') { return 2 }
  if ($t -like '*ainda nao investi*' -or $t -like '*nao investi*') { return 0 }
  return 1
}
function PtNivel($a) {
  $t = Deacc $a; if ($t -eq '') { return 0 }
  if ($t -like '*nunca investi*') { return 0 }
  return 1
}
function PtCap($a) {
  $t = Deacc $a; if ($t -eq '') { return 0 }
  if ($t -like '*nao consigo*') { return 0 }
  return 1
}
function PtResult($a) {
  $t = Deacc $a; if ($t -eq '') { return 0 }
  if ($t -like '*por onde comecar*') { return 0 }
  return 1
}
function ScoreOf($idade, $nivel, $valor, $trava, $result, $renda, $cap, $motiv) {
  return (PtIdade $idade) + (PtRenda $renda) + (PtMotiv $motiv) + (PtTrava $trava) +
         (PtValor $valor) + (PtNivel $nivel) + (PtCap $cap) + (PtResult $result)
}
function TierOf($score) {
  if ($score -ge $QUENTE_MIN) { return 'q' }
  if ($score -ge $MORNO_MIN) { return 'm' }
  return 'f'
}

# ---- attribution key cleaners ------------------------------------------
function CleanUtm($s) {
  if ($null -eq $s) { return '' }
  $s = ([string]$s).Trim()
  if ($s -eq '' -or $s -match '{{.*}}' -or $s -match '\{\{') { return '' }
  return $s
}

# ---- name interning -----------------------------------------------------
$CampArr = New-Object System.Collections.ArrayList; $CampMap = @{}
$SetArr  = New-Object System.Collections.ArrayList; $SetMap  = @{}
$AdArr   = New-Object System.Collections.ArrayList; $AdMap   = @{}
function Intern($arr, $map, $val) {
  if ($val -eq '') { $val = '(sem)' }
  if ($map.ContainsKey($val)) { return $map[$val] }
  $i = $arr.Add($val); $map[$val] = $i; return $i
}

# ---- grain store: key -> node ------------------------------------------
# node = @{ d;p;c;s;a; sp;im;ck;lp;rc;px; ld; rs; f;m;q }
function NewGrain() { return @{} }
function GNode($grain, $d, $p, $ci, $si, $ai) {
  $k = "$d|$p|$ci|$si|$ai"
  if ($grain.ContainsKey($k)) { return $grain[$k] }
  $n = @{ d = $d; p = $p; c = $ci; s = $si; a = $ai;
         sp = 0.0; im = 0.0; ck = 0.0; lp = 0.0; rc = 0.0; px = 0.0;
         ld = 0; rs = 0; f = 0; m = 0; q = 0; rev = 0.0; sales = 0 }
  $grain[$k] = $n; return $n
}

# ========================================================================
#  Build one funnel
# ========================================================================
function Build-Funnel($key, $tagPfx, $gMeta, $gGoog, $gLeads, $gPesq) {
  Write-Host "== Funnel $key : downloading =="
  $T = [Diagnostics.Stopwatch]::StartNew()
  $fMeta = Get-Csv $QID $gMeta "$key`_meta"
  $fGoog = Get-Csv $QID $gGoog "$key`_goog"
  $fLead = Get-Csv $LID $gLeads "$key`_leads"
  $fPesq = Get-Csv $LID $gPesq "$key`_pesq"
  Write-Host ("   [{0:n1}s] downloaded" -f $T.Elapsed.TotalSeconds)

  $grain = NewGrain

  # ---- META queries : Day,Campaign,AdSet,Ad,Spent,Impr,Reach,Clicks,Leads,LPV
  $rows = Read-Rows $fMeta
  foreach ($r in $rows) {
    if ($r.Count -lt 6) { continue }
    $d = DKey $r[0]; if ($d -eq '') { continue }
    $ci = Intern $CampArr $CampMap ($r[1].Trim())
    $si = Intern $SetArr  $SetMap  ($r[2].Trim())
    $ai = Intern $AdArr   $AdMap   ($r[3].Trim())
    $n = GNode $grain $d 'm' $ci $si $ai
    $n.sp += (PNum $r[4]) * $TAX
    $n.im += (PNum $r[5])
    if ($r.Count -gt 6) { $n.rc += (PNum $r[6]) }
    if ($r.Count -gt 7) { $n.ck += (PNum $r[7]) }
    if ($r.Count -gt 8) { $n.px += (PNum $r[8]) }
    if ($r.Count -gt 9) { $n.lp += (PNum $r[9]) }
  }
  # ---- GOOGLE queries : Day,Campaign,AdGroup,Ad,Cost,Impr,Clicks,Conversions
  $rows = Read-Rows $fGoog
  foreach ($r in $rows) {
    if ($r.Count -lt 5) { continue }
    $d = DKey $r[0]; if ($d -eq '') { continue }
    $ci = Intern $CampArr $CampMap ($r[1].Trim())
    $si = Intern $SetArr  $SetMap  ($r[2].Trim())
    $ai = Intern $AdArr   $AdMap   ($r[3].Trim())
    $n = GNode $grain $d 'g' $ci $si $ai
    $n.sp += (PNum $r[4])          # google: no tax
    $n.im += (PNum $r[5])
    if ($r.Count -gt 6) { $n.ck += (PNum $r[6]) }
    if ($r.Count -gt 7) { $n.px += (PNum $r[7]) }
  }
  Write-Host ("   [{0:n1}s] queries parsed" -f $T.Elapsed.TotalSeconds)

  # ---- LEADS : Nome,Email,WhatsApp,Tag,src,medium,campaign,term,content,Timestamp
  # INLINED hot loop (no per-lead function calls) -> processes ~130k rows fast.
  $rows = Read-Rows $fLead
  $emIndex = @{}   # emailKey -> ArrayList of leadObj (this funnel)
  $phIndex = @{}
  $totalLeads = 0
  $pfxLen = $tagPfx.Length
  $semC = Intern $CampArr $CampMap '(sem rastreio)'
  $semS = Intern $SetArr  $SetMap  '(sem rastreio)'
  $semA = Intern $AdArr   $AdMap   '(sem rastreio)'
  foreach ($r in $rows) {
    if ($r.Count -lt 10) { continue }
    $tag = $r[3]
    if (-not $tag.StartsWith($tagPfx)) { continue }
    if ($tag.Length -le $pfxLen) { continue }
    $c0 = $tag[$pfxLen]; if ($c0 -lt '0' -or $c0 -gt '9') { continue }
    $em = $r[1]; if ($em.IndexOf('@') -lt 0) { continue }
    $ts = $r[9]
    $ok = ($ts.Length -ge 10 -and $ts[2] -eq '/' -and $ts[5] -eq '/')
    if (-not $ok -and $r.Count -gt 10) { $ts = $r[10]; $ok = ($ts.Length -ge 10 -and $ts[2] -eq '/' -and $ts[5] -eq '/') }  # fallback: 'Data Ajustada' (segunda)
    if (-not $ok) { continue }
    $d = $ts.Substring(6, 4) + '-' + $ts.Substring(3, 2) + '-' + $ts.Substring(0, 2)
    $srcl = $r[4].ToLowerInvariant()
    if ($srcl.IndexOf('google') -ge 0) { $p = 'g' }
    elseif ($srcl.IndexOf('face') -ge 0 -or $srcl.IndexOf('meta') -ge 0 -or $srcl.IndexOf('insta') -ge 0 -or $srcl -eq 'ig') { $p = 'm' }
    else { $p = 'o' }
    if ($p -eq 'o') {
      $ci = $semC; $si = $semS; $ai = $semA
    } else {
      $cv = $r[6]; if ($cv.IndexOf('{{') -ge 0 -or $cv.Trim() -eq '') { $ci = $semC } else { $cv = $cv.Trim(); if ($CampMap.ContainsKey($cv)) { $ci = $CampMap[$cv] } else { $ci = $CampArr.Add($cv); $CampMap[$cv] = $ci } }
      $sv = $r[7]; if ($sv.IndexOf('{{') -ge 0 -or $sv.Trim() -eq '') { $si = $semS } else { $sv = $sv.Trim(); if ($SetMap.ContainsKey($sv)) { $si = $SetMap[$sv] } else { $si = $SetArr.Add($sv); $SetMap[$sv] = $si } }
      $av = $r[8]; if ($av.IndexOf('{{') -ge 0 -or $av.Trim() -eq '') { $ai = $semA } else { $av = $av.Trim(); if ($AdMap.ContainsKey($av)) { $ai = $AdMap[$av] } else { $ai = $AdArr.Add($av); $AdMap[$av] = $ai } }
    }
    $gk = "$d|$p|$ci|$si|$ai"
    $n = $grain[$gk]
    if ($null -eq $n) { $n = @{ d = $d; p = $p; c = $ci; s = $si; a = $ai; sp = 0.0; im = 0.0; ck = 0.0; lp = 0.0; rc = 0.0; px = 0.0; ld = 0; rs = 0; f = 0; m = 0; q = 0; rev = 0.0; sales = 0 }; $grain[$gk] = $n }
    $n.ld += 1
    $totalLeads++
    $lead = @{ d = $d; node = $n; resp = $false }
    $ek = $em.Trim().ToLowerInvariant()
    $ea = $emIndex[$ek]; if ($null -eq $ea) { $ea = New-Object System.Collections.ArrayList; $emIndex[$ek] = $ea }; [void]$ea.Add($lead)
    $pk = $r[2] -replace '\D', ''
    if ($pk.Length -ge 12 -and $pk.StartsWith('55')) { $pk = $pk.Substring(2) }
    if ($pk.Length -gt 11) { $pk = $pk.Substring($pk.Length - 11) }
    if ($pk.Length -ge 8) { $pa = $phIndex[$pk]; if ($null -eq $pa) { $pa = New-Object System.Collections.ArrayList; $phIndex[$pk] = $pa }; [void]$pa.Add($lead) }
  }
  Write-Host ("   [{0:n1}s] leads(tagged) $key = $totalLeads" -f $T.Elapsed.TotalSeconds)

  # ---- PESQUISA : score each, match to a lead, attribute to its grain node
  # cols: Nome,Email,WhatsApp,Idade,Nivel,Valor,Trava,Result,Renda,Cap,Motiv,utm...(12-16),Status,Data
  $rows = Read-Rows $fPesq
  $respTot = 0; $respMatch = 0
  $tierTot = @{ f = 0; m = 0; q = 0 }
  # per-dimension distributions (this funnel) : dimKey -> (answerLabel -> count)
  $dist = @{}
  foreach ($dk in @('idade', 'renda', 'motiv', 'trava', 'valor', 'nivel', 'cap', 'result')) { $dist[$dk] = @{} }
  # profile of Quente leads (this funnel) : dimKey -> (answerLabel -> count)
  $prof = @{}
  foreach ($dk in @('idade', 'renda', 'motiv', 'trava', 'valor', 'nivel', 'cap', 'result')) { $prof[$dk] = @{} }

  function BumpDist($h, $k, $lab) { if ($lab -eq '') { $lab = '(sem resposta)' }; if (-not $h[$k].ContainsKey($lab)) { $h[$k][$lab] = 0 }; $h[$k][$lab]++ }

  foreach ($r in $rows) {
    if ($r.Count -lt 11) { continue }
    $status = if ($r.Count -gt 16) { $r[16].Trim().ToLowerInvariant() } else { '' }
    $idade = $r[3]; $nivel = $r[4]; $valor = $r[5]; $trava = $r[6]; $result = $r[7]; $renda = $r[8]; $cap = $r[9]; $motiv = $r[10]
    $score = ScoreOf $idade $nivel $valor $trava $result $renda $cap $motiv
    $tier = TierOf $score
    $respTot++
    $tierTot[$tier]++
    BumpDist $dist 'idade' $idade.Trim(); BumpDist $dist 'renda' $renda.Trim(); BumpDist $dist 'motiv' $motiv.Trim(); BumpDist $dist 'trava' $trava.Trim()
    BumpDist $dist 'valor' $valor.Trim(); BumpDist $dist 'nivel' $nivel.Trim(); BumpDist $dist 'cap' $cap.Trim(); BumpDist $dist 'result' $result.Trim()
    if ($tier -eq 'q') {
      BumpDist $prof 'idade' $idade.Trim(); BumpDist $prof 'renda' $renda.Trim(); BumpDist $prof 'motiv' $motiv.Trim(); BumpDist $prof 'trava' $trava.Trim()
      BumpDist $prof 'valor' $valor.Trim(); BumpDist $prof 'nivel' $nivel.Trim(); BumpDist $prof 'cap' $cap.Trim(); BumpDist $prof 'result' $result.Trim()
    }
    # match to a lead (email then phone), pick registration closest <= survey date
    $sd = DKey $r[17]
    $cands = $null
    $ek = EmKey $r[1]
    if ($ek -ne '' -and $emIndex.ContainsKey($ek)) { $cands = $emIndex[$ek] }
    if ($null -eq $cands) { $pk = PhKey $r[2]; if ($pk.Length -ge 8 -and $phIndex.ContainsKey($pk)) { $cands = $phIndex[$pk] } }
    if ($null -ne $cands -and $cands.Count -gt 0) {
      $pick = $null
      foreach ($c in $cands) {
        if ($sd -eq '' -or $c.d -le $sd) { if ($null -eq $pick -or $c.d -gt $pick.d) { $pick = $c } }
      }
      if ($null -eq $pick) { foreach ($c in $cands) { if ($null -eq $pick -or $c.d -lt $pick.d) { $pick = $c } } }
      if (-not $pick.resp) {
        $pick.resp = $true
        $pick.node.rs += 1
        $pick.node[$tier] += 1
        $respMatch++
      } else {
        # already responded once: still attribute the tier to the node (extra response)
        $pick.node[$tier] += 1
      }
    }
  }
  Write-Host ("   [{0:n1}s] pesquisa $key : responses=$respTot matched=$respMatch  tiers f=$($tierTot.f) m=$($tierTot.m) q=$($tierTot.q)" -f $T.Elapsed.TotalSeconds)

  # Return INTERMEDIATE state (rollup happens in Finalize-Funnel, AFTER sales attribution).
  return @{
    key = $key; grain = $grain; emIndex = $emIndex; phIndex = $phIndex;
    totalLeads = $totalLeads; respTot = $respTot; respMatch = $respMatch;
    tierTot = $tierTot; dist = $dist; prof = $prof
  }
}

# ---- money parser for sales ("R$ 1.997,00" -> 1997.0) -------------------
function MoneyBR($s) {
  if ($null -eq $s) { return 0.0 }
  $s = ([string]$s) -replace '[^\d,\.]', ''
  $s = $s -replace '\.', ''
  $s = $s -replace ',', '.'
  $d = 0.0
  [void][double]::TryParse($s, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)
  return $d
}

# ========================================================================
#  Sales attribution (GLOBAL across both funnels, to dedup buyers in both)
#  Cross buyer email x lead email; credit revenue to the lead registration
#  closest BEFORE the purchase (causal). Product = Formula dos Investimentos.
# ========================================================================
$SALES_ID = '1BJ-T_Aj5oeMge667xWtX_SfGCSiibcFo7l0yLWTt_BQ'
function Attribute-Sales($funnels) {
  Write-Host "== sales : Formula dos Investimentos =="
  $Ts = [Diagnostics.Stopwatch]::StartNew()
  $file = Get-Csv $SALES_ID 0 'sales'
  $rows = Read-Rows $file
  # cols: Produto,Nome,Email,Data,Valor,Taxas,Faturamento,Pagamento,utm...
  $tot = 0; $totV = 0.0; $attr = 0; $attrV = 0.0
  $unSrc = @{}   # utm_source -> @{sales;rev} for UNATTRIBUTED sales
  $byYear = @{}  # year -> @{sales;rev} for ALL FDI sales
  foreach ($r in $rows) {
    if ($r.Count -lt 5) { continue }
    if ((Deacc $r[0]) -notlike '*formula dos investimentos*') { continue }
    $sd = DKey $r[3]; if ($sd -eq '') { continue }
    $val = MoneyBR $r[4]
    $tot++; $totV += $val
    $yr = $sd.Substring(0, 4)
    if (-not $byYear.ContainsKey($yr)) { $byYear[$yr] = @{ sales = 0; rev = 0.0 } }
    $byYear[$yr].sales += 1; $byYear[$yr].rev += $val
    # best lead across both funnels with capture date <= sale date (closest)
    $best = $null
    $ek = $r[2].Trim().ToLowerInvariant()
    if ($ek -ne '' -and $ek.IndexOf('@') -ge 0) {
      foreach ($fn in $funnels) {
        $cands = $fn.emIndex[$ek]
        if ($null -eq $cands) { continue }
        foreach ($c in $cands) {
          if ($c.d -le $sd) { if ($null -eq $best -or $c.d -gt $best.d) { $best = $c } }
        }
      }
    }
    if ($null -ne $best) {
      $best.node.rev += $val; $best.node.sales += 1; $attr++; $attrV += $val
    } else {
      # UNATTRIBUTED (nao rastreada): tally by utm_source (col idx 8)
      $src = if ($r.Count -gt 8) { $r[8].Trim().ToLowerInvariant() } else { '' }
      if ($src -eq '') { $src = '(sem utm_source)' }
      if (-not $unSrc.ContainsKey($src)) { $unSrc[$src] = @{ sales = 0; rev = 0.0 } }
      $unSrc[$src].sales += 1; $unSrc[$src].rev += $val
    }
  }
  Write-Host ("   [{0:n1}s] FDI sales={1} R$ {2:n2} | attribuidas={3} R$ {4:n2}" -f $Ts.Elapsed.TotalSeconds, $tot, $totV, $attr, $attrV)
  $unArr = New-Object System.Collections.ArrayList
  foreach ($k in $unSrc.Keys) { [void]$unArr.Add(@{ src = $k; sales = $unSrc[$k].sales; rev = [Math]::Round($unSrc[$k].rev, 2) }) }
  $unArr = @($unArr | Sort-Object { - $_.rev })
  $yrArr = New-Object System.Collections.ArrayList
  foreach ($k in ($byYear.Keys | Sort-Object)) { [void]$yrArr.Add(@{ year = $k; sales = $byYear[$k].sales; rev = [Math]::Round($byYear[$k].rev, 2) }) }
  return @{ totalSales = $tot; totalRev = [Math]::Round($totV, 2); attrSales = $attr; attrRev = [Math]::Round($attrV, 2); unSrc = @($unArr); byYear = @($yrArr) }
}

# ---- Finalize: roll grain -> daily + grain array (after sales attributed) -
function Finalize-Funnel($fn) {
  $grain = $fn.grain
  $dayMap = @{}
  foreach ($n in $grain.Values) {
    $k = "$($n.d)|$($n.p)"
    if (-not $dayMap.ContainsKey($k)) { $dayMap[$k] = @{ date = $n.d; p = $n.p; sp = 0.0; im = 0.0; ck = 0.0; lp = 0.0; rc = 0.0; px = 0.0; ld = 0; rs = 0; f = 0; m = 0; q = 0; rev = 0.0; sales = 0 } }
    $x = $dayMap[$k]
    $x.sp += $n.sp; $x.im += $n.im; $x.ck += $n.ck; $x.lp += $n.lp; $x.rc += $n.rc; $x.px += $n.px
    $x.ld += $n.ld; $x.rs += $n.rs; $x.f += $n.f; $x.m += $n.m; $x.q += $n.q; $x.rev += $n.rev; $x.sales += $n.sales
  }
  $daily = @($dayMap.Values | Sort-Object { $_.date }, { $_.p })

  $grArr = New-Object System.Collections.ArrayList
  foreach ($n in $grain.Values) {
    if ($n.sp -eq 0 -and $n.ld -eq 0 -and $n.rs -eq 0 -and $n.sales -eq 0) { continue }
    [void]$grArr.Add(@{ d = $n.d; p = $n.p; c = $n.c; s = $n.s; a = $n.a;
      sp = [Math]::Round($n.sp, 2); im = [int]$n.im; ck = [int]$n.ck; lp = [int]$n.lp; rc = [int]$n.rc; px = [int]$n.px;
      ld = $n.ld; rs = $n.rs; f = $n.f; m = $n.m; q = $n.q; rev = [Math]::Round($n.rev, 2); sales = $n.sales })
  }

  $ds = @($daily | Where-Object { $_.ld -gt 0 } | ForEach-Object { $_.date } | Sort-Object)
  $lmin = if ($ds.Count) { $ds[0] } else { '' }
  $lmax = if ($ds.Count) { $ds[$ds.Count - 1] } else { '' }
  $leadsEra = 0; $totRev = 0.0; $totSales = 0
  foreach ($x in $daily) { if ($x.date -ge $SURVEY_START) { $leadsEra += $x.ld }; $totRev += $x.rev; $totSales += $x.sales }
  Write-Host ("   finalize $($fn.key): grainNodes=$($grArr.Count) rev=R$ {0:n2} vendas={1}" -f $totRev, $totSales)

  return @{
    key = $fn.key; leadMin = $lmin; leadMax = $lmax
    totalLeads = $fn.totalLeads; leadsEra = $leadsEra
    respTot = $fn.respTot; respMatch = $fn.respMatch; tierTot = $fn.tierTot
    totalRev = [Math]::Round($totRev, 2); totalSales = $totSales
    daily = $daily; grain = @($grArr); dist = $fn.dist; prof = $fn.prof
  }
}

# ========================================================================
$segI = Build-Funnel 'segunda' 'WBN-2026-S' $G_META_SEG  $G_GOOG_SEG  $G_LEADS_SEG   $G_PESQ_SEG
$terI = Build-Funnel 'terca'   'WBN-2026-L' $G_META_TERCA $G_GOOG_TERCA $G_LEADS_TERCA $G_PESQ_TERCA
$salesInfo = Attribute-Sales @($segI, $terI)
$seg = Finalize-Funnel $segI
$ter = Finalize-Funnel $terI

# ---- dimension metadata (labels + peso) ---------------------------------
$DIMS = @(
  @{ key = 'idade';  label = 'Idade';                              peso = 3 },
  @{ key = 'renda';  label = 'Renda mensal';                       peso = 3 },
  @{ key = 'motiv';  label = 'Motivacao';                          peso = 2 },
  @{ key = 'trava';  label = 'O que mais trava';                   peso = 2 },
  @{ key = 'valor';  label = 'Valor ja investido';                 peso = 2 },
  @{ key = 'nivel';  label = 'Nivel de investidor';                peso = 1 },
  @{ key = 'cap';    label = 'Capacidade mensal de investimento';  peso = 1 },
  @{ key = 'result'; label = 'Resultado esperado da aula';         peso = 1 }
)
# map dimKey -> point function name for option scoring in the survey tab
function PtFor($dk, $ans) {
  switch ($dk) {
    'idade'  { return (PtIdade $ans) }
    'renda'  { return (PtRenda $ans) }
    'motiv'  { return (PtMotiv $ans) }
    'trava'  { return (PtTrava $ans) }
    'valor'  { return (PtValor $ans) }
    'nivel'  { return (PtNivel $ans) }
    'cap'    { return (PtCap $ans) }
    'result' { return (PtResult $ans) }
  }
  return 0
}

# ---- build pesquisa dims (options w/ seg,ter counts + points) -----------
$pesqDims = New-Object System.Collections.ArrayList
foreach ($dm in $DIMS) {
  $dk = $dm.key
  $labels = @{}
  foreach ($lab in $seg.dist[$dk].Keys) { $labels[$lab] = $true }
  foreach ($lab in $ter.dist[$dk].Keys) { $labels[$lab] = $true }
  $opts = New-Object System.Collections.ArrayList
  foreach ($lab in $labels.Keys) {
    $s = if ($seg.dist[$dk].ContainsKey($lab)) { $seg.dist[$dk][$lab] } else { 0 }
    $t = if ($ter.dist[$dk].ContainsKey($lab)) { $ter.dist[$dk][$lab] } else { 0 }
    $pt = if ($lab -eq '(sem resposta)') { PtFor $dk '' } else { PtFor $dk $lab }
    [void]$opts.Add(@{ label = $lab; pts = $pt; seg = $s; ter = $t })
  }
  $opts = @($opts | Sort-Object { -($_.seg + $_.ter) })
  [void]$pesqDims.Add(@{ key = $dk; label = $dm.label; peso = $dm.peso; options = @($opts) })
}

# ---- qualified profile (soma seg+ter among Quente) ----------------------
$pesqProfile = New-Object System.Collections.ArrayList
foreach ($dm in $DIMS) {
  $dk = $dm.key
  $labels = @{}
  foreach ($lab in $seg.prof[$dk].Keys) { $labels[$lab] = $true }
  foreach ($lab in $ter.prof[$dk].Keys) { $labels[$lab] = $true }
  $opts = New-Object System.Collections.ArrayList
  foreach ($lab in $labels.Keys) {
    $c = 0
    if ($seg.prof[$dk].ContainsKey($lab)) { $c += $seg.prof[$dk][$lab] }
    if ($ter.prof[$dk].ContainsKey($lab)) { $c += $ter.prof[$dk][$lab] }
    [void]$opts.Add(@{ label = $lab; cnt = $c })
  }
  $opts = @($opts | Sort-Object { -$_.cnt })
  [void]$pesqProfile.Add(@{ key = $dk; label = $dm.label; peso = $dm.peso; options = @($opts) })
}

# ---- assemble funnel payload (strip dist/prof from funnel object) -------
function FunnelPayload($f) {
  return @{
    key = $f.key; leadMin = $f.leadMin; leadMax = $f.leadMax
    totalLeads = $f.totalLeads; leadsEra = $f.leadsEra
    respTot = $f.respTot; respMatch = $f.respMatch
    tierTot = $f.tierTot
    totalRev = $f.totalRev; totalSales = $f.totalSales
    daily = @($f.daily); grain = @($f.grain)
  }
}

$nowBR = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'E. South America Standard Time')
$payload = @{
  generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
  generatedAtBR = $nowBR.ToString('dd/MM/yyyy HH:mm')
  taxMultiplier = $TAX
  quenteMin     = $QUENTE_MIN
  mornoMin      = $MORNO_MIN
  surveyStart   = $SURVEY_START
  product       = 'Formula dos Investimentos'
  sales         = $salesInfo
  names         = @{ c = @($CampArr.ToArray()); s = @($SetArr.ToArray()); a = @($AdArr.ToArray()) }
  segunda       = FunnelPayload $seg
  terca         = FunnelPayload $ter
  pesquisa      = @{
    surveyStart = $SURVEY_START
    dims        = @($pesqDims)
    profile     = @($pesqProfile)
    seg         = @{ respTot = $seg.respTot; respMatch = $seg.respMatch; tierTot = $seg.tierTot; leadsEra = $seg.leadsEra }
    ter         = @{ respTot = $ter.respTot; respMatch = $ter.respMatch; tierTot = $ter.tierTot; leadsEra = $ter.leadsEra }
  }
}

$json = $payload | ConvertTo-Json -Depth 20 -Compress
$js = "window.POMPEU = $json;`nwindow.POMPEU_OK = true;"
$outFile = Join-Path $root 'data.js'
[System.IO.File]::WriteAllText($outFile, $js, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $outFile ($([Math]::Round((Get-Item $outFile).Length/1kb,1)) KB)"
Write-Host "DONE $($payload.generatedAtBR)"
