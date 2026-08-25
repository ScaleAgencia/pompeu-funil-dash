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
$QID = '1RlFtbOJq4LUS8nc3MrR6C9-dvYA5-mSVpVQsHcPGNEE'   # queries (segunda/terca)
$QID_DIARIO = '1OehemfZnZRYAs2l2XyzGORU1CExXAs7OIutn98ZdCd0'  # queries WBN DIARIO (Meta only)

# tab gids
$G_LEADS_TERCA = 0
$G_LEADS_SEG   = 986552728
$G_PESQ_TERCA  = 674160845
$G_PESQ_SEG    = 272892171
$G_META_TERCA  = 0
$G_GOOG_TERCA  = 837001685
$G_META_SEG    = 1484394087
$G_GOOG_SEG    = 968000625
# --- Webinar DIARIO (funil novo, Meta + Google) ---
$G_META_DIARIO  = 0            # aba "Queries | WBN DIARIO" (col order: Day,Campaign,Ad,AdSet,...)
$G_GOOG_DIARIO  = 1609119011  # aba "Queries Google WBN DIARIO" (col order PADRAO: Day,Campaign,AdGroup,Ad,Cost,...)
$G_LEADS_DIARIO = 1529016880  # aba v5 (filtrar Tag = WBN-2026-DIARIO; src google-ads = Google, facebook-ads = Meta)
$G_PESQ_DIARIO  = 323578863   # aba "pesquisa diario"
# --- Webinar 2 DIAS (funil novo 21/08/2026; leads na aba v6; MESMAS queries do diario, campanha termina em "WBN-2DIAS") ---
$G_LEADS_2DIAS  = 'v6'        # aba v6 (todos os leads sao do 2-dias; Tag = WBN-2026-DIARIO-DOMINGO-2-DIAS)
$TAG_2DIAS      = 'WBN-2026-DIARIO-DOMINGO-2-DIAS'
$CAMP_2DIAS     = 'WBN2DIAS'  # forma NORMALIZADA (sem separador) do sufixo que separa 2-dias do diario; pega "WBN-2DIAS" (Meta) e "WBN_2DIAS" (Google/YT)
$G_PESQ_2DIAS   = 1342965621 # aba "PESQUISA DIARIO 2 DIAS" (mesmas colunas/params do diario)

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataDir = Join-Path $root 'data'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

# ---- helpers ------------------------------------------------------------
function Get-Csv($id, $gid, $name) {
  # &_cb=<ticks> = cache-buster: o gviz do Google as vezes serve CSV cacheado (dias atrasado);
  # sem isso o build pega query velha (ex: Google diario parado num dia antigo). Ticks unico por build.
  # $gid numerico -> gid=; senao (ex: 'v6') -> sheet=<nome> (gviz aceita os dois)
  $sel = if ("$gid" -match '^\d+$') { "gid=$gid" } else { "sheet=$([Uri]::EscapeDataString([string]$gid))" }
  $url = "https://docs.google.com/spreadsheets/d/$id/gviz/tq?tqx=out:csv&$sel&_cb=$([DateTime]::UtcNow.Ticks)"
  $out = Join-Path $dataDir "$name.csv"
  if ($env:POMPEU_REUSE -eq '1' -and (Test-Path $out)) { return $out }
  for ($try = 1; $try -le 4; $try++) {
    try {
      # WebClient streams to disk (Invoke-WebRequest is ~50x slower on large files in PS5.1)
      $wc = New-Object System.Net.WebClient
      $wc.Encoding = [Text.Encoding]::UTF8
      $wc.Headers.Add('User-Agent', 'Mozilla/5.0 pompeu-dash')
      $wc.Headers.Add('Cache-Control', 'no-cache')
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
function MidDate($a, $b) { $da = [DateTime]::ParseExact($a, 'yyyy-MM-dd', $null); $db = [DateTime]::ParseExact($b, 'yyyy-MM-dd', $null); return $da.AddDays([Math]::Floor(($db - $da).TotalDays / 2)).ToString('yyyy-MM-dd') }
function AddDaysS($a, $n) { return ([DateTime]::ParseExact($a, 'yyyy-MM-dd', $null)).AddDays($n).ToString('yyyy-MM-dd') }
function EdNum($t) { if ($t -match '(\d+)$') { return [int]$matches[1] } return 0 }
# Inicio do ciclo semanal: recua ate o dia do webinario (dow: 1=segunda, 2=terca).
# O dia do evento ja capta para a proxima edicao -> ciclo = [dia do evento .. vespera do proximo].
function CycleStart($d, $dow) {
  $dt = [DateTime]::ParseExact($d, 'yyyy-MM-dd', $null)
  $back = (([int]$dt.DayOfWeek) - $dow + 7) % 7
  return $dt.AddDays(- $back).ToString('yyyy-MM-dd')
}
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
# Nome normalizado p/ cruzamento (deaccent, so a-z e espaco, colapsa espacos). '' se < 2 tokens.
function NKey($s) {
  $t = Deacc $s
  $t = ($t -replace '[^a-z ]', ' ')
  $t = ($t -replace '\s+', ' ').Trim()
  if ($t.IndexOf(' ') -lt 0) { return '' }   # exige nome + sobrenome (evita xara de 1 token)
  return $t
}
# Canoniza nome de campanha/conjunto/anuncio p/ CASAR query x lead do mesmo jeito.
# Resolve a ambiguidade do '+' no utm (espaco vira '+', e '+' literal no fim tb) — ex: query "IDADE 40+" vs lead "IDADE 40".
function Canon($s) {
  if ($null -eq $s) { return '' }
  $t = ([string]$s).Replace('+', ' ')
  try { $t = [Uri]::UnescapeDataString($t) } catch {}
  $t = ($t -replace '\s+', ' ').Trim().TrimEnd('+', ' ')
  return $t
}
# nome de query: canoniza se o funil usa utm codificado ($dec), senao so trim
function QN($s, $dec) { if ($dec) { return (Canon $s) } else { return ([string]$s).Trim() } }
# Acha o indice de uma coluna pelo NOME do cabecalho (deaccent, case-insensitive); usa $default se nao achar.
function ColOf($hdr, $names, $default) {
  foreach ($nm in $names) {
    $tn = (Deacc $nm).Trim()
    for ($i = 0; $i -lt $hdr.Length; $i++) { if ((Deacc $hdr[$i]).Trim() -eq $tn) { return $i } }
  }
  return $default
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

# ======= LEADSCORE A/B/C do DIARIO — por REGRAS (FDI Diario · Protocolo de Otimizacao) =====
#  Faixas do doc (tabela "Lookalike · Faixas A, B e C"). Prioridade: C (excluir) > A (seed) > B (miolo).
#   C = qualquer uma das 4 regras da Lista de exclusao (nivel 2 do protocolo).
#   A = SEED APERTADO (motor da campanha): 51+ E (aporte R$500-2.000 OU renda>=R$5.000). ~10%, converte 2,12%, indice 1,78x.
#       NAO e "qualquer sinal de escalar" (isso dava 63%). "acima de R$2.000" e "ate R$100" NAO contam (convertem <media).
#   B = todo o resto = o miolo ("Cuidado" no doc: parece ruim mas nao pode ser excluido). ~63%.
function ClassABC($idade, $nivel, $valor, $trava, $renda, $cap) {
  $ti = Deacc $idade; $tn = Deacc $nivel; $tv = Deacc $valor; $tt = Deacc $trava; $tr = Deacc $renda; $tc = Deacc $cap
  $semRenda    = ($tr -like '*possuo*')                                        # Nao possuo renda
  $apAte100    = ($tc -like '*ate*100*')                                       # Ate R$ 100
  $apNaoConsigo= ($tc -like '*nao consigo*')                                   # Nao consigo investir agora
  $apBaixo     = ($apAte100 -or $apNaoConsigo)                                 # aporte <= R$100
  $ap500a2000  = ($tc -like '*500*1.000*' -or $tc -like '*1.000*2.000*')       # R$500 a R$2.000 (o ponto doce; 'acima 2.000' NAO entra)
  $medoPerder  = ($tt -like '*medo de perder*')
  $faltaDin    = ($tt -like '*falta de dinheiro*')
  $naoSaber    = ($tt -like '*onde investir*')                                 # Nao saber onde investir
  $id51        = ($ti -like '*51 a 60*' -or $ti -like '*61 anos*' -or $ti -like '*50 anos ou mais*')
  $idAte50     = -not $id51
  $nunca       = ($tn -like '*nunca investi*')
  $jaInvestiu  = -not ($tv -eq '' -or $tv -like '*ainda nao investi*' -or $tv -like '*nao investi*')
  $renda5      = ($tr -like '*5.000*10.000*' -or $tr -like '*acima*10.000*')   # renda >= R$5.000
  # ---- C : LISTA DE EXCLUSAO (qualquer regra) ----
  if ( ($semRenda -and $apBaixo) `
    -or ($semRenda -and ($medoPerder -or $faltaDin)) `
    -or ($idAte50 -and $medoPerder -and $apBaixo) `
    -or ($nunca -and $apNaoConsigo -and $faltaDin) ) { return 'c' }
  # ---- A : SEED (motor da campanha) = 51+ E (aporte R$500-2.000 OU renda >= R$5.000) ----
  if ($id51 -and ($ap500a2000 -or $renda5)) { return 'a' }
  # ---- B : MIOLO / resto (nem excluir, nem seed) ----
  return 'b'
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
$SrcArr  = New-Object System.Collections.ArrayList; $SrcMap  = @{}   # utm_source (fonte: facebook/google/tiktok/youtube/organico)
$MedArr  = New-Object System.Collections.ArrayList; $MedMap  = @{}   # utm_medium (midia)
function Intern($arr, $map, $val) {
  if ($val -eq '') { $val = '(sem)' }
  if ($map.ContainsKey($val)) { return $map[$val] }
  $i = $arr.Add($val); $map[$val] = $i; return $i
}
# codigo estavel de resposta por dimensao (p/ respostas cruas filtraveis por UTM)
function OptCode($optArr, $optMap, $dk, $lab) {
  if ($lab -eq '') { $lab = '(sem resposta)' }
  if ($optMap[$dk].ContainsKey($lab)) { return $optMap[$dk][$lab] }
  $i = $optArr[$dk].Add($lab); $optMap[$dk][$lab] = $i; return $i
}

# ---- grain store: key -> node ------------------------------------------
# node = @{ d;p;c;s;a; sp;im;ck;lp;rc;px; ld; rs; f;m;q }
function NewGrain() { return @{} }
function GNode($grain, $d, $p, $ci, $si, $ai) {
  $k = "$d|$p|$ci|$si|$ai"
  if ($grain.ContainsKey($k)) { return $grain[$k] }
  $n = @{ d = $d; p = $p; c = $ci; s = $si; a = $ai;
         sp = 0.0; im = 0.0; ck = 0.0; lp = 0.0; rc = 0.0; px = 0.0;
         ld = 0; rs = 0; f = 0; m = 0; q = 0; la = 0; lb = 0; lc = 0; rev = 0.0; sales = 0 }
  $grain[$k] = $n; return $n
}

# ========================================================================
#  Build one funnel
# ========================================================================
function Build-Funnel($key, $tagPfx, $gMeta, $gGoog, $gLeads, $gPesq, $metaId = $QID, $leadsId = $LID, $tagMode = 'num', $metaAdBeforeSet = $false, $decodeUtm = $false, $metaOnly = $false, $buildNameIdx = $false, $abcScore = $false, $campMust = '', $campMustNot = '', $leadSetColM = 7, $leadSetColG = 7) {
  # $leadSetColM/$leadSetColG: coluna do lead que e o CONJUNTO (adset), POR PLATAFORMA.
  #   Diario/seg/ter = utm_term(7) nos dois. 2-DIAS: Facebook usa utm_medium(5) (la o utm_term e o
  #   POSICIONAMENTO Reels/Stories); Google usa utm_term(7)="40-ANOS" (=AdGroup da query). Anuncio = utm_content(8) sempre.
  # $campMust/$campMustNot: separam funis que COMPARTILHAM a query (ex: diario x 2-dias no mesmo gid).
  #   query so entra no grain se o utm_campaign CONTEM $campMust e NAO contem $campMustNot.
  #   NORMALIZA separadores (Meta usa "| WBN-2DIAS" hifen, Google usa "_WBN_2DIAS" underscore) ->
  #   tira -_ |espaco e compara em maiuscula, entao 'WBN2DIAS' pega os dois.
  function CampNorm($s) { return (([string]$s) -replace '[-_ |]', '').ToUpperInvariant() }
  function CampOk($nm) {
    $n = CampNorm $nm
    if ($campMust -ne '' -and ($n -notlike "*$campMust*")) { return $false }
    if ($campMustNot -ne '' -and ($n -like "*$campMustNot*")) { return $false }
    return $true
  }
  Write-Host "== Funnel $key : downloading =="
  $T = [Diagnostics.Stopwatch]::StartNew()
  $fMeta = Get-Csv $metaId $gMeta "$key`_meta"
  $fGoog = if ($null -ne $gGoog) { Get-Csv $metaId $gGoog "$key`_goog" } else { $null }   # Google na MESMA planilha do Meta do funil
  $fLead = Get-Csv $leadsId $gLeads "$key`_leads"
  $fPesq = if ($null -ne $gPesq) { Get-Csv $leadsId $gPesq "$key`_pesq" } else { $null }   # 2-dias ainda sem pesquisa
  Write-Host ("   [{0:n1}s] downloaded" -f $T.Elapsed.TotalSeconds)

  $grain = NewGrain

  # ---- META queries. Detecta AdSet/Ad pelo NOME do cabecalho (ROBUSTO a reordenacao da query).
  #   O cliente ja trocou a ordem 2x (Ad,AdSet <-> AdSet,Ad); ColOf acha a coluna certa case-insensitive.
  #   Default: AdSet=col2, Ad=col3 (ordem normal). $metaAdBeforeSet vira so fallback se nao houver header.
  $mHdr = @()
  $mLines0 = [System.IO.File]::ReadAllLines($fMeta, [Text.Encoding]::UTF8)
  if ($mLines0.Length -gt 0) { $h0 = $mLines0[0]; if ($h0.Length -ge 2 -and $h0[0] -eq '"' -and $h0[$h0.Length - 1] -eq '"') { $mHdr = $h0.Substring(1, $h0.Length - 2) -split '","', -1 } else { $mHdr = $h0 -split ',', -1 } }
  $mCamCol = ColOf $mHdr @('Campaign Name', 'Campaign', 'Campanha', 'Nome da campanha') 1
  $mSetCol = ColOf $mHdr @('Ad Set Name', 'AdSet Name', 'Ad Set', 'Conjunto', 'Nome do conjunto de anuncios') -1
  $mAdCol  = ColOf $mHdr @('Ad Name', 'AdName', 'Anuncio', 'Nome do anuncio') -1
  if ($mSetCol -lt 0 -or $mAdCol -lt 0) { if ($metaAdBeforeSet) { $mSetCol = 3; $mAdCol = 2 } else { $mSetCol = 2; $mAdCol = 3 } }   # sem header -> usa a flag
  $mSpCol = ColOf $mHdr @('Amount Spent', 'Amount spent', 'Spend', 'Valor usado', 'Valor gasto') 4
  $mImCol = ColOf $mHdr @('Impressions', 'Impressoes') 5
  $mRcCol = ColOf $mHdr @('Reach', 'Alcance') 6
  $mCkCol = ColOf $mHdr @('Link Clicks', 'Clicks', 'Cliques', 'Cliques no link') 7
  $mPxCol = ColOf $mHdr @('Leads', 'Results', 'Resultados') 8
  $mLpCol = ColOf $mHdr @('Landing Page Views', 'LPV', 'Visualizacoes da pagina de destino') 9
  Write-Host ("   [meta] camp=col$mCamCol conjunto=col$mSetCol anuncio=col$mAdCol gasto=col$mSpCol")
  $rows = Read-Rows $fMeta
  foreach ($r in $rows) {
    if ($r.Count -lt 5) { continue }
    $d = DKey $r[0]; if ($d -eq '') { continue }
    $cnm = QN $r[$mCamCol] $decodeUtm; if (-not (CampOk $cnm)) { continue }   # separa funis que compartilham a query
    $ci = Intern $CampArr $CampMap $cnm
    $si = Intern $SetArr $SetMap (QN $r[$mSetCol] $decodeUtm)
    $ai = Intern $AdArr  $AdMap  (QN $r[$mAdCol]  $decodeUtm)
    $n = GNode $grain $d 'm' $ci $si $ai
    $n.sp += (PNum $r[$mSpCol]) * $TAX
    if ($mImCol -ge 0 -and $r.Count -gt $mImCol) { $n.im += (PNum $r[$mImCol]) }
    if ($mRcCol -ge 0 -and $r.Count -gt $mRcCol) { $n.rc += (PNum $r[$mRcCol]) }
    if ($mCkCol -ge 0 -and $r.Count -gt $mCkCol) { $n.ck += (PNum $r[$mCkCol]) }
    if ($mPxCol -ge 0 -and $r.Count -gt $mPxCol) { $n.px += (PNum $r[$mPxCol]) }
    if ($mLpCol -ge 0 -and $r.Count -gt $mLpCol) { $n.lp += (PNum $r[$mLpCol]) }
  }
  # ---- GOOGLE queries : Day,Campaign,AdGroup,Ad,Cost,Impr,Clicks,Conversions (pulado se $gGoog nulo). Header-aware.
  if ($null -ne $fGoog) {
    $gHdr = @(); $gLines0 = [System.IO.File]::ReadAllLines($fGoog, [Text.Encoding]::UTF8)
    if ($gLines0.Length -gt 0) { $gh0 = $gLines0[0]; if ($gh0.Length -ge 2 -and $gh0[0] -eq '"' -and $gh0[$gh0.Length - 1] -eq '"') { $gHdr = $gh0.Substring(1, $gh0.Length - 2) -split '","', -1 } else { $gHdr = $gh0 -split ',', -1 } }
    $gCamCol = ColOf $gHdr @('Campaign Name', 'Campaign', 'Campanha') 1
    $gSetCol = ColOf $gHdr @('Ad Group Name', 'AdGroup Name', 'Ad Group', 'Grupo de anuncios', 'Grupo') 2
    $gAdCol  = ColOf $gHdr @('Ad Name', 'AdName', 'Anuncio') 3
    $gSpCol  = ColOf $gHdr @('Cost (Spend)', 'Cost', 'Spend', 'Custo') 4
    $gImCol  = ColOf $gHdr @('Impressions', 'Impressoes') 5
    $gCkCol  = ColOf $gHdr @('Clicks', 'Cliques') 6
    $gPxCol  = ColOf $gHdr @('Conversions', 'Conversoes') 7
    Write-Host ("   [google] camp=col$gCamCol grupo=col$gSetCol anuncio=col$gAdCol gasto=col$gSpCol")
    $rows = Read-Rows $fGoog
    foreach ($r in $rows) {
      if ($r.Count -lt 5) { continue }
      $d = DKey $r[0]; if ($d -eq '') { continue }
      $cnm = QN $r[$gCamCol] $decodeUtm; if (-not (CampOk $cnm)) { continue }
      $ci = Intern $CampArr $CampMap $cnm
      $si = Intern $SetArr  $SetMap  (QN $r[$gSetCol] $decodeUtm)
      $ai = Intern $AdArr   $AdMap   (QN $r[$gAdCol]  $decodeUtm)
      $n = GNode $grain $d 'g' $ci $si $ai
      $n.sp += (PNum $r[$gSpCol])          # google: no tax
      if ($gImCol -ge 0 -and $r.Count -gt $gImCol) { $n.im += (PNum $r[$gImCol]) }
      if ($gCkCol -ge 0 -and $r.Count -gt $gCkCol) { $n.ck += (PNum $r[$gCkCol]) }
      if ($gPxCol -ge 0 -and $r.Count -gt $gPxCol) { $n.px += (PNum $r[$gPxCol]) }
    }
  }
  Write-Host ("   [{0:n1}s] queries parsed" -f $T.Elapsed.TotalSeconds)

  # ---- LEADS : Nome,Email,WhatsApp,Tag,src,medium,campaign,term,content,Timestamp
  # INLINED hot loop (no per-lead function calls) -> processes ~130k rows fast.
  $rows = Read-Rows $fLead
  $emIndex = @{}   # emailKey -> ArrayList of leadObj (this funnel)
  $phIndex = @{}
  $nmIndex = @{}   # nomeKey -> ArrayList of leadObj (so quando $buildNameIdx; usado no fallback de atribuicao)
  $edLeads = @{}   # tag -> lead count (edicao/semana)
  $edDay = @{}     # "tag|date" -> count (pra achar o dia de pico)
  $totalLeads = 0
  $pfxLen = $tagPfx.Length
  $semC = Intern $CampArr $CampMap '(sem rastreio)'
  $semS = Intern $SetArr  $SetMap  '(sem rastreio)'
  $semA = Intern $AdArr   $AdMap   '(sem rastreio)'
  foreach ($r in $rows) {
    if ($r.Count -lt 10) { continue }
    $tag = $r[3]
    if (-not $tag.StartsWith($tagPfx)) { continue }
    if ($tagMode -eq 'num') {                          # tags numeradas (L1..,S1..): exige digito apos o prefixo
      if ($tag.Length -le $pfxLen) { continue }
      $c0 = $tag[$pfxLen]; if ($c0 -lt '0' -or $c0 -gt '9') { continue }
    }                                                   # tagMode 'exact' (DIARIO): basta o StartsWith
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
    if ($metaOnly -and $p -ne 'm') { continue }         # funil Meta-only (DIARIO): ignora leads Google/sem-utm (sem query p/ medir)
    if ($p -eq 'o') {
      $ci = $semC; $si = $semS; $ai = $semA
    } else {
      $cv = $r[6]; if ($cv.IndexOf('{{') -ge 0 -or $cv.Trim() -eq '') { $ci = $semC } else { $cv = if ($decodeUtm) { Canon $cv } else { $cv.Trim() }; if ($CampMap.ContainsKey($cv)) { $ci = $CampMap[$cv] } else { $ci = $CampArr.Add($cv); $CampMap[$cv] = $ci } }
      $setCol = if ($p -eq 'g') { $leadSetColG } else { $leadSetColM }   # conjunto por plataforma (2-dias: FB=medium, Google=term)
      $sv = $r[$setCol]; if ($sv.IndexOf('{{') -ge 0 -or $sv.Trim() -eq '') { $si = $semS } else { $sv = if ($decodeUtm) { Canon $sv } else { $sv.Trim() }; if ($SetMap.ContainsKey($sv)) { $si = $SetMap[$sv] } else { $si = $SetArr.Add($sv); $SetMap[$sv] = $si } }
      $av = $r[8]; if ($av.IndexOf('{{') -ge 0 -or $av.Trim() -eq '') { $ai = $semA } else { $av = if ($decodeUtm) { Canon $av } else { $av.Trim() }; if ($AdMap.ContainsKey($av)) { $ai = $AdMap[$av] } else { $ai = $AdArr.Add($av); $AdMap[$av] = $ai } }
    }
    $gk = "$d|$p|$ci|$si|$ai"
    $n = $grain[$gk]
    if ($null -eq $n) { $n = @{ d = $d; p = $p; c = $ci; s = $si; a = $ai; sp = 0.0; im = 0.0; ck = 0.0; lp = 0.0; rc = 0.0; px = 0.0; ld = 0; rs = 0; f = 0; m = 0; q = 0; la = 0; lb = 0; lc = 0; rev = 0.0; sales = 0 }; $grain[$gk] = $n }
    $n.ld += 1
    $totalLeads++
    $edLeads[$tag] = $edLeads[$tag] + 1
    $ek2 = "$tag|$d"; $edDay[$ek2] = $edDay[$ek2] + 1
    $ek = $em.Trim().ToLowerInvariant()
    $pk = $r[2] -replace '\D', ''
    if ($pk.Length -ge 12 -and $pk.StartsWith('55')) { $pk = $pk.Substring(2) }
    if ($pk.Length -gt 11) { $pk = $pk.Substring($pk.Length - 11) }
    $phk = if ($pk.Length -ge 8) { $pk } else { '' }
    $srcIx = Intern $SrcArr $SrcMap ($r[4].Trim())                        # utm_source (fonte)
    $medIx = if ($r.Count -gt 5) { Intern $MedArr $MedMap ($r[5].Trim()) } else { Intern $MedArr $MedMap '' }
    $lead = @{ d = $d; node = $n; resp = $false; em = $ek; ph = $phk; src = $srcIx; med = $medIx }   # em+ph p/ cruzamento estrito; src+med p/ filtro UTM
    $ea = $emIndex[$ek]; if ($null -eq $ea) { $ea = New-Object System.Collections.ArrayList; $emIndex[$ek] = $ea }; [void]$ea.Add($lead)
    if ($buildNameIdx) { $nk = NKey $r[0]; if ($nk -ne '') { $na = $nmIndex[$nk]; if ($null -eq $na) { $na = New-Object System.Collections.ArrayList; $nmIndex[$nk] = $na }; [void]$na.Add($lead) } }
    if ($phk -ne '') { $pa = $phIndex[$phk]; if ($null -eq $pa) { $pa = New-Object System.Collections.ArrayList; $phIndex[$phk] = $pa }; [void]$pa.Add($lead) }
  }
  Write-Host ("   [{0:n1}s] leads(tagged) $key = $totalLeads" -f $T.Elapsed.TotalSeconds)

  # ---- PESQUISA : score each, match to a lead, attribute to its grain node
  # cols: Nome,Email,WhatsApp,Idade,Nivel,Valor,Trava,Result,Renda,Cap,Motiv,utm...(12-16),Status,Data
  $rows = if ($null -ne $fPesq) { Read-Rows $fPesq } else { @() }   # 2-dias: sem pesquisa ainda -> loop vazio
  $respTot = 0; $respMatch = 0
  $tierTot = @{ f = 0; m = 0; q = 0 }
  $abcTot = @{ a = 0; b = 0; c = 0 }   # leadscore A/B/C (so quando $abcScore, ex: diario)
  $survDay = @{}   # data DA RESPOSTA (col Data) -> @{tot;mat} : bate com a planilha por dia
  # per-dimension distributions (this funnel) : dimKey -> (answerLabel -> count)
  $dist = @{}
  foreach ($dk in @('idade', 'renda', 'motiv', 'trava', 'valor', 'nivel', 'cap', 'result')) { $dist[$dk] = @{} }
  # profile of Quente leads (this funnel) : dimKey -> (answerLabel -> count)
  $prof = @{}
  foreach ($dk in @('idade', 'renda', 'motiv', 'trava', 'valor', 'nivel', 'cap', 'result')) { $prof[$dk] = @{} }
  # respostas cruas p/ FILTRO POR UTM (so quando $abcScore, ex: diario): 1 linha por resposta
  $DK8p = @('idade', 'renda', 'motiv', 'trava', 'valor', 'nivel', 'cap', 'result')
  $respRows = New-Object System.Collections.ArrayList
  $optArr = @{}; $optMap = @{}
  foreach ($dk in $DK8p) { $optArr[$dk] = New-Object System.Collections.ArrayList; $optMap[$dk] = @{} }

  function BumpDist($h, $k, $lab) { if ($lab -eq '') { $lab = '(sem resposta)' }; if (-not $h[$k].ContainsKey($lab)) { $h[$k][$lab] = 0 }; $h[$k][$lab]++ }

  foreach ($r in $rows) {
    if ($r.Count -lt 11) { continue }
    $status = if ($r.Count -gt 16) { $r[16].Trim().ToLowerInvariant() } else { '' }
    $idade = $r[3]; $nivel = $r[4]; $valor = $r[5]; $trava = $r[6]; $result = $r[7]; $renda = $r[8]; $cap = $r[9]; $motiv = $r[10]
    $score = ScoreOf $idade $nivel $valor $trava $result $renda $cap $motiv
    $tier = TierOf $score
    $band = if ($abcScore) { ClassABC $idade $nivel $valor $trava $renda $cap } else { '' }
    # match to a lead (email then phone), pick registration closest <= survey date
    $sd = DKey $r[17]
    $cands = $null
    $ek = EmKey $r[1]
    if ($ek -ne '' -and $emIndex.ContainsKey($ek)) { $cands = $emIndex[$ek] }
    if ($null -eq $cands) { $pk = PhKey $r[2]; if ($pk.Length -ge 8 -and $phIndex.ContainsKey($pk)) { $cands = $phIndex[$pk] } }
    $didMatch = $false
    $pick = $null
    if ($null -ne $cands -and $cands.Count -gt 0) {
      foreach ($c in $cands) {
        if ($sd -eq '' -or $c.d -le $sd) { if ($null -eq $pick -or $c.d -gt $pick.d) { $pick = $c } }
      }
      if ($null -eq $pick) { foreach ($c in $cands) { if ($null -eq $pick -or $c.d -lt $pick.d) { $pick = $c } } }
      if ($null -ne $pick) {
        $didMatch = $true
        $bf = if ($band -ne '') { 'l' + $band } else { '' }
        if (-not $pick.resp) { $pick.resp = $true; $pick.node.rs += 1; $pick.node[$tier] += 1; if ($bf) { $pick.node[$bf] += 1 }; $respMatch++ }
        else { $pick.node[$tier] += 1; if ($bf) { $pick.node[$bf] += 1 } }
      }
    }
    # ==== AGREGADOS DO FUNIL: contam SO respostas que sao DESTE funil (casaram c/ um lead dele). ====
    #   A aba de pesquisa pode ser COMPARTILHADA: "PESQUISA DIARIO 2 DIAS" (gid 1342965621) tem
    #   ~4135 respostas do DIARIO + ~584 do 2-dias no mesmo lugar. Sem esse gate o 2-dias contaria 5095.
    if ($didMatch) {
      $respTot++
      $tierTot[$tier]++
      if ($band -ne '') { $abcTot[$band]++ }
      BumpDist $dist 'idade' $idade.Trim(); BumpDist $dist 'renda' $renda.Trim(); BumpDist $dist 'motiv' $motiv.Trim(); BumpDist $dist 'trava' $trava.Trim()
      BumpDist $dist 'valor' $valor.Trim(); BumpDist $dist 'nivel' $nivel.Trim(); BumpDist $dist 'cap' $cap.Trim(); BumpDist $dist 'result' $result.Trim()
      if ($tier -eq 'q') {
        BumpDist $prof 'idade' $idade.Trim(); BumpDist $prof 'renda' $renda.Trim(); BumpDist $prof 'motiv' $motiv.Trim(); BumpDist $prof 'trava' $trava.Trim()
        BumpDist $prof 'valor' $valor.Trim(); BumpDist $prof 'nivel' $nivel.Trim(); BumpDist $prof 'cap' $cap.Trim(); BumpDist $prof 'result' $result.Trim()
      }
      # linha crua p/ FILTRO POR UTM (so diario/abcScore)
      if ($abcScore -and $band -ne '') {
        $bc = switch ($band) { 'a' { 0 } 'b' { 1 } 'c' { 2 } default { 1 } }
        [void]$respRows.Add(@(
          $pick.node.d, $bc, $pick.src, $pick.med, $pick.node.c, $pick.node.s, $pick.node.a,
          (OptCode $optArr $optMap 'idade'  $idade.Trim()),
          (OptCode $optArr $optMap 'renda'  $renda.Trim()),
          (OptCode $optArr $optMap 'motiv'  $motiv.Trim()),
          (OptCode $optArr $optMap 'trava'  $trava.Trim()),
          (OptCode $optArr $optMap 'valor'  $valor.Trim()),
          (OptCode $optArr $optMap 'nivel'  $nivel.Trim()),
          (OptCode $optArr $optMap 'cap'    $cap.Trim()),
          (OptCode $optArr $optMap 'result' $result.Trim())
        ))
      }
      # por DATA DA RESPOSTA (so casadas deste funil)
      if ($sd -ne '') {
        $sv = $survDay[$sd]; if ($null -eq $sv) { $sv = @{ tot = 0; mat = 0 }; $survDay[$sd] = $sv }
        $sv.tot += 1; $sv.mat += 1
      }
    }
  }
  Write-Host ("   [{0:n1}s] pesquisa $key : responses=$respTot matched=$respMatch  tiers f=$($tierTot.f) m=$($tierTot.m) q=$($tierTot.q)" -f $T.Elapsed.TotalSeconds)

  # respOpts: hashtable dimKey -> array de labels (code table das respostas cruas)
  $respOpts = @{}; foreach ($dk in $DK8p) { $respOpts[$dk] = @($optArr[$dk].ToArray()) }
  # Return INTERMEDIATE state (rollup happens in Finalize-Funnel, AFTER sales attribution).
  return @{
    key = $key; grain = $grain; emIndex = $emIndex; phIndex = $phIndex; nameIndex = $nmIndex;
    totalLeads = $totalLeads; respTot = $respTot; respMatch = $respMatch;
    tierTot = $tierTot; abcTot = $abcTot; dist = $dist; prof = $prof; edLeads = $edLeads; edDay = $edDay; survDay = $survDay;
    respRows = @($respRows); respOpts = $respOpts
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
  # --- mapeia colunas por NOME do cabecalho (robusto a insercao de colunas, ex: WhatsApp no meio) ---
  $lines = [System.IO.File]::ReadAllLines($file, [Text.Encoding]::UTF8)
  $hdr = @()
  if ($lines.Length -gt 0) { $h0 = $lines[0]; if ($h0.Length -ge 2 -and $h0[0] -eq '"' -and $h0[$h0.Length - 1] -eq '"') { $hdr = $h0.Substring(1, $h0.Length - 2) -split '","', -1 } else { $hdr = $h0 -split ',', -1 } }
  $iProd = ColOf $hdr @('Produto') 0
  $iNome = ColOf $hdr @('Nome') 1
  $iWpp  = ColOf $hdr @('WhatsApp', 'Telefone', 'Celular', 'Whatsapp') -1
  $iMail = ColOf $hdr @('Email', 'E-mail') 2
  $iData = ColOf $hdr @('Data') 3
  $iFat  = ColOf $hdr @('Faturamento') 6
  $iSrc  = ColOf $hdr @('utm_source') 8
  $need = ($iProd, $iNome, $iMail, $iData, $iFat | Measure-Object -Maximum).Maximum
  Write-Host ("   cols: prod=$iProd nome=$iNome wpp=$iWpp email=$iMail data=$iData fat=$iFat src=$iSrc")
  $rows = Read-Rows $file
  $tot = 0; $totV = 0.0; $attr = 0; $attrV = 0.0
  $mByEm = 0; $mByPh = 0; $mByNm = 0; $mByDia = 0; $mDiaPh = 0   # atribuicao: diario(email, +telefone confirmado=mDiaPh) / seg-ter email / telefone
  $unSrc = @{}   # utm_source -> @{sales;rev} for UNATTRIBUTED sales
  $byYear = @{}  # year -> @{sales;rev} for ALL FDI sales
  $script:FDI_BUYERS = @{}   # email -> 1 : TODO comprador de FDI (p/ validacao do leadscore)
  foreach ($r in $rows) {
    if ($r.Count -le $need) { continue }
    if ((Deacc $r[$iProd]) -notlike '*formula dos investimentos*') { continue }
    $sd = DKey $r[$iData]; if ($sd -eq '') { continue }
    $val = MoneyBR $r[$iFat]   # Faturamento LIQUIDO (Valor - Taxas) — bate com o relatorio do cliente
    $tot++; $totV += $val
    $yr = $sd.Substring(0, 4)
    if (-not $byYear.ContainsKey($yr)) { $byYear[$yr] = @{ sales = 0; rev = 0.0 } }
    $byYear[$yr].sales += 1; $byYear[$yr].rev += $val
    # best lead com captacao <= venda. DIARIO = ESTRITO (email E telefone no MESMO lead); Seg/Ter = email > telefone.
    $best = $null; $via = ''
    $ek = $r[$iMail].Trim().ToLowerInvariant()
    $pk = if ($iWpp -ge 0 -and $r.Count -gt $iWpp) { PhKey $r[$iWpp] } else { '' }
    if ($ek -ne '' -and $ek.IndexOf('@') -ge 0) { $script:FDI_BUYERS[$ek] = 1 }
    # 1) DIARIO — EMAIL e a chave; se a venda TIVER telefone e o lead tambem, precisam BATER (senao descarta o candidato).
    #    Venda sem telefone (99% do FDI hoje) -> email basta. Assim o telefone vira double-check automatico.
    if ($ek -ne '' -and $ek.IndexOf('@') -ge 0) {
      foreach ($fn in $funnels) {
        if ($fn.key -ne 'diario' -and $fn.key -ne 'dias2') { continue }   # diario E 2-dias: regra estrita (email + telefone confirma)
        $cands = $fn.emIndex[$ek]; if ($null -eq $cands) { continue }
        foreach ($c in $cands) {
          if ($c.d -gt $sd) { continue }
          if ($pk.Length -ge 8 -and $c.ph -ne '' -and $c.ph -ne $pk) { continue }   # ambos tem telefone e divergem -> veta
          if ($null -eq $best -or $c.d -gt $best.d) { $best = $c }
        }
      }
      if ($null -ne $best) { $via = 'dia'; if ($pk.Length -ge 8 -and $best.ph -eq $pk) { $mDiaPh++ } }
    }
    # 2) SEG/TER — email
    if ($null -eq $best -and $ek -ne '' -and $ek.IndexOf('@') -ge 0) {
      foreach ($fn in $funnels) {
        if ($fn.key -eq 'diario' -or $fn.key -eq 'dias2') { continue }
        $cands = $fn.emIndex[$ek]; if ($null -eq $cands) { continue }
        foreach ($c in $cands) { if ($c.d -le $sd) { if ($null -eq $best -or $c.d -gt $best.d) { $best = $c } } }
      }
      if ($null -ne $best) { $via = 'em' }
    }
    # 3) SEG/TER — telefone
    if ($null -eq $best -and $pk.Length -ge 8) {
      foreach ($fn in $funnels) {
        if ($fn.key -eq 'diario' -or $fn.key -eq 'dias2') { continue }
        $cands = $fn.phIndex[$pk]; if ($null -eq $cands) { continue }
        foreach ($c in $cands) { if ($c.d -le $sd) { if ($null -eq $best -or $c.d -gt $best.d) { $best = $c } } }
      }
      if ($null -ne $best) { $via = 'ph' }
    }
    if ($null -ne $best) {
      $best.node.rev += $val; $best.node.sales += 1; $attr++; $attrV += $val
      if ($via -eq 'dia') { $mByDia++ } elseif ($via -eq 'em') { $mByEm++ } elseif ($via -eq 'ph') { $mByPh++ }
    } else {
      # UNATTRIBUTED (nao rastreada): tally by utm_source
      $src = if ($iSrc -ge 0 -and $r.Count -gt $iSrc) { $r[$iSrc].Trim().ToLowerInvariant() } else { '' }
      if ($src -eq '') { $src = '(sem utm_source)' }
      if (-not $unSrc.ContainsKey($src)) { $unSrc[$src] = @{ sales = 0; rev = 0.0 } }
      $unSrc[$src].sales += 1; $unSrc[$src].rev += $val
    }
  }
  Write-Host ("   [{0:n1}s] FDI sales={1} R$ {2:n2} | attribuidas={3} R$ {4:n2} | diario={5} (telefone-confirmado={6}) seg/ter-email={7} seg/ter-tel={8}" -f $Ts.Elapsed.TotalSeconds, $tot, $totV, $attr, $attrV, $mByDia, $mDiaPh, $mByEm, $mByPh)
  $unArr = New-Object System.Collections.ArrayList
  foreach ($k in $unSrc.Keys) { [void]$unArr.Add(@{ src = $k; sales = $unSrc[$k].sales; rev = [Math]::Round($unSrc[$k].rev, 2) }) }
  $unArr = @($unArr | Sort-Object { - $_.rev })
  $yrArr = New-Object System.Collections.ArrayList
  foreach ($k in ($byYear.Keys | Sort-Object)) { [void]$yrArr.Add(@{ year = $k; sales = $byYear[$k].sales; rev = [Math]::Round($byYear[$k].rev, 2) }) }
  return @{ totalSales = $tot; totalRev = [Math]::Round($totV, 2); attrSales = $attr; attrRev = [Math]::Round($attrV, 2); unSrc = @($unArr); byYear = @($yrArr) }
}

# ---- Finalize: roll grain -> daily + grain array (after sales attributed) -
function Finalize-Funnel($fn, $dow) {
  $grain = $fn.grain
  $dayMap = @{}
  foreach ($n in $grain.Values) {
    $k = "$($n.d)|$($n.p)"
    if (-not $dayMap.ContainsKey($k)) { $dayMap[$k] = @{ date = $n.d; p = $n.p; sp = 0.0; im = 0.0; ck = 0.0; lp = 0.0; rc = 0.0; px = 0.0; ld = 0; rs = 0; f = 0; m = 0; q = 0; la = 0; lb = 0; lc = 0; rev = 0.0; sales = 0 } }
    $x = $dayMap[$k]
    $x.sp += $n.sp; $x.im += $n.im; $x.ck += $n.ck; $x.lp += $n.lp; $x.rc += $n.rc; $x.px += $n.px
    $x.ld += $n.ld; $x.rs += $n.rs; $x.f += $n.f; $x.m += $n.m; $x.q += $n.q; $x.la += $n.la; $x.lb += $n.lb; $x.lc += $n.lc; $x.rev += $n.rev; $x.sales += $n.sales
  }
  $daily = @($dayMap.Values | Sort-Object { $_.date }, { $_.p })

  $grArr = New-Object System.Collections.ArrayList
  foreach ($n in $grain.Values) {
    if ($n.sp -eq 0 -and $n.ld -eq 0 -and $n.rs -eq 0 -and $n.sales -eq 0) { continue }
    [void]$grArr.Add(@{ d = $n.d; p = $n.p; c = $n.c; s = $n.s; a = $n.a;
      sp = [Math]::Round($n.sp, 2); im = [int]$n.im; ck = [int]$n.ck; lp = [int]$n.lp; rc = [int]$n.rc; px = [int]$n.px;
      ld = $n.ld; rs = $n.rs; f = $n.f; m = $n.m; q = $n.q; la = $n.la; lb = $n.lb; lc = $n.lc; rev = [Math]::Round($n.rev, 2); sales = $n.sales })
  }

  $ds = @($daily | Where-Object { $_.ld -gt 0 } | ForEach-Object { $_.date } | Sort-Object)
  $lmin = if ($ds.Count) { $ds[0] } else { '' }
  $lmax = if ($ds.Count) { $ds[$ds.Count - 1] } else { '' }
  $leadsEra = 0; $totRev = 0.0; $totSales = 0
  foreach ($x in $daily) { if ($x.date -ge $SURVEY_START) { $leadsEra += $x.ld }; $totRev += $x.rev; $totSales += $x.sales }

  # ---- editions/weeks (so p/ funis semanais; DIARIO usa dow=0 -> sem edicoes) ----
  # Cada DIA pertence a edicao cuja tag DOMINA aquele dia (a virada acontece
  # no dia do webinario). Isso bate com a contagem manual do cliente; usar o
  # ponto medio entre picos errava a fronteira em 1 dia.
  $eds = New-Object System.Collections.ArrayList
  if ($dow -ge 1) {
    $dayTopTag = @{}; $dayTopN = @{}; $edPeak = @{}; $edPeakN = @{}
    foreach ($k in $fn.edDay.Keys) {
      $sp = $k.Split('|'); $tg = $sp[0]; $dd = $sp[1]; $c = $fn.edDay[$k]
      if (-not $dayTopN.ContainsKey($dd) -or $c -gt $dayTopN[$dd]) { $dayTopN[$dd] = $c; $dayTopTag[$dd] = $tg }
      if (-not $edPeakN.ContainsKey($tg) -or $c -gt $edPeakN[$tg]) { $edPeakN[$tg] = $c; $edPeak[$tg] = $dd }
    }
    # Janela = ciclo semanal ancorado no dia do webinario (regra do cliente):
    # o dia do evento ja capta para a proxima edicao -> [dia do evento .. vespera do proximo].
    $tags = @($edPeak.Keys | Sort-Object { EdNum $_ })
    $usedCycle = @{}
    foreach ($tg in $tags) {
      $lo = CycleStart $edPeak[$tg] $dow
      $hi = AddDaysS $lo 6
      if ($usedCycle.ContainsKey($lo)) { Write-Host "   [aviso] ciclo $lo repetido em $tg" }
      $usedCycle[$lo] = $tg
      if ($lmin -ne '' -and $lo -lt $lmin) { $lo = $lmin }
      [void]$eds.Add(@{ tag = $tg; num = (EdNum $tg); peak = $edPeak[$tg]; lo = $lo; hi = $hi; leads = $fn.edLeads[$tg] })
    }
  }
  Write-Host ("   finalize $($fn.key): grainNodes=$($grArr.Count) rev=R$ {0:n2} vendas={1} edicoes={2}" -f $totRev, $totSales, $eds.Count)

  # respostas por DATA DA RESPOSTA (bate com a planilha)
  $svArr = New-Object System.Collections.ArrayList
  foreach ($k in ($fn.survDay.Keys | Sort-Object)) { [void]$svArr.Add(@{ date = $k; tot = $fn.survDay[$k].tot; mat = $fn.survDay[$k].mat }) }

  return @{
    key = $fn.key; leadMin = $lmin; leadMax = $lmax
    totalLeads = $fn.totalLeads; leadsEra = $leadsEra
    respTot = $fn.respTot; respMatch = $fn.respMatch; tierTot = $fn.tierTot; abcTot = $fn.abcTot
    totalRev = [Math]::Round($totRev, 2); totalSales = $totSales
    editions = @($eds); survDaily = @($svArr)
    daily = $daily; grain = @($grArr); dist = $fn.dist; prof = $fn.prof
    resp = @($fn.respRows); respOpts = $fn.respOpts
  }
}

# ========================================================================
$segI = Build-Funnel 'segunda' 'WBN-2026-S' $G_META_SEG  $G_GOOG_SEG  $G_LEADS_SEG   $G_PESQ_SEG
$terI = Build-Funnel 'terca'   'WBN-2026-L' $G_META_TERCA $G_GOOG_TERCA $G_LEADS_TERCA $G_PESQ_TERCA
# DIARIO: Meta + Google (mesma planilha QID_DIARIO), tag exata WBN-2026-DIARIO; Meta com Ad<->AdSet trocados + utm URL-encoded (+->espaco); Google col padrao + utm plano
# DIARIO: query = campanhas que COMECAM com "WBN-DIARIO" (campMust) E NAO sao 2-dias (campMustNot).
#   Isso exclui campanhas orfas de OUTROS funis que vazam na query compartilhada (ex: 'WBN-2026_..._URL-Investimentos'
#   sem 'DIARIO' no nome, R$6993 gasto e 0 lead). Todas as campanhas reais do diario tem 'WBN-DIARIO'.
$diaI = Build-Funnel 'diario' 'WBN-2026-DIARIO' $G_META_DIARIO $G_GOOG_DIARIO $G_LEADS_DIARIO $G_PESQ_DIARIO $QID_DIARIO $LID 'exact' $true $true $false $true $true 'WBNDIARIO' $CAMP_2DIAS
# 2 DIAS: leads na aba v6, MESMAS queries (Meta gid0 + Google) mas SO campanhas WBN-2DIAS; sem pesquisa ainda
# conjunto: Facebook=utm_medium(5), Google=utm_term(7). abcScore=$true (leadscore ligado, mesmos params do diario)
$dois2I = Build-Funnel 'dias2' $TAG_2DIAS $G_META_DIARIO $G_GOOG_DIARIO $G_LEADS_2DIAS $G_PESQ_2DIAS $QID_DIARIO $LID 'exact' $true $true $false $true $true $CAMP_2DIAS '' 5 7
$salesInfo = Attribute-Sales @($segI, $terI, $diaI, $dois2I)
$seg = Finalize-Funnel $segI 1   # webinario na SEGUNDA -> ciclo segunda..domingo
$ter = Finalize-Funnel $terI 2   # webinario na TERCA   -> ciclo terca..segunda
$dia = Finalize-Funnel $diaI 0   # DIARIO: webinario diario -> sem edicoes semanais
$dois2 = Finalize-Funnel $dois2I 0  # 2-DIAS: captacao (sem edicoes semanais)

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
  foreach ($lab in $dia.dist[$dk].Keys) { $labels[$lab] = $true }
  $opts = New-Object System.Collections.ArrayList
  foreach ($lab in $labels.Keys) {
    $s = if ($seg.dist[$dk].ContainsKey($lab)) { $seg.dist[$dk][$lab] } else { 0 }
    $t = if ($ter.dist[$dk].ContainsKey($lab)) { $ter.dist[$dk][$lab] } else { 0 }
    $dv = if ($dia.dist[$dk].ContainsKey($lab)) { $dia.dist[$dk][$lab] } else { 0 }
    $pt = if ($lab -eq '(sem resposta)') { PtFor $dk '' } else { PtFor $dk $lab }
    [void]$opts.Add(@{ label = $lab; pts = $pt; seg = $s; ter = $t; dia = $dv })
  }
  $opts = @($opts | Sort-Object { -($_.seg + $_.ter + $_.dia) })
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
    tierTot = $f.tierTot; abcTot = $f.abcTot
    totalRev = $f.totalRev; totalSales = $f.totalSales
    editions = @($f.editions); survDaily = @($f.survDaily)
    daily = @($f.daily); grain = @($f.grain)
    resp = @($f.resp); respOpts = $f.respOpts
  }
}

# ---- Validacao AUTO do leadscore: quem responde x quem compra FDI --------
#  Recalcula toda atualizacao (3h): conversao por tier + perfil do comprador.
#  Escopo = respostas ja maturadas (data <= hoje-4d, deu tempo do webinario/venda).
function Compute-Validation($surveyFiles, $buyers, $matCut) {
  $leads = @{}
  foreach ($f in $surveyFiles) {
    if (-not (Test-Path $f)) { continue }
    foreach ($r in (Read-Rows $f)) {
      if ($r.Count -lt 11) { continue }
      $sd = if ($r.Count -gt 17) { DKey $r[17] } else { '' }
      if ($sd -eq '' -or $sd -gt $matCut) { continue }
      $e = EmKey $r[1]; if ($e -eq '' -or $e.IndexOf('@') -lt 0) { continue }
      $sc = ScoreOf $r[3] $r[4] $r[5] $r[6] $r[7] $r[8] $r[9] $r[10]
      if (-not $leads.ContainsKey($e) -or $sc -gt $leads[$e].sc) {
        $leads[$e] = @{ sc = $sc; idade = $r[3].Trim(); nivel = $r[4].Trim(); valor = $r[5].Trim(); trava = $r[6].Trim(); result = $r[7].Trim(); renda = $r[8].Trim(); cap = $r[9].Trim(); motiv = $r[10].Trim() }
      }
    }
  }
  $bt = @{ q = @{ n = 0; b = 0 }; m = @{ n = 0; b = 0 }; f = @{ n = 0; b = 0 } }
  $abc = @{ a = @{ n = 0; b = 0 }; b = @{ n = 0; b = 0 }; c = @{ n = 0; b = 0 } }   # A/B/C x compra (aderencia)
  $prof = @{}; $aprof = @{}   # perfil do COMPRADOR e perfil do LEAD A
  $conv = @{}                 # dimKey -> resposta -> {n=leads, b=compradores}  (indice de conversao AO VIVO)
  $DK8 = @('idade', 'renda', 'motiv', 'trava', 'valor', 'nivel', 'cap', 'result')
  foreach ($dk in $DK8) { $prof[$dk] = @{}; $aprof[$dk] = @{}; $conv[$dk] = @{} }
  foreach ($e in $leads.Keys) {
    $x = $leads[$e]; $t = TierOf $x.sc; $bought = $buyers.ContainsKey($e)
    $band = ClassABC $x.idade $x.nivel $x.valor $x.trava $x.renda $x.cap
    $bt[$t].n++; if ($bought) { $bt[$t].b++ }
    $abc[$band].n++; if ($bought) { $abc[$band].b++ }
    foreach ($dk in $DK8) {
      $a = $x[$dk]; if ($a -eq '') { $a = '(sem resposta)' }
      if (-not $conv[$dk].ContainsKey($a)) { $conv[$dk][$a] = @{ n = 0; b = 0 } }
      $conv[$dk][$a].n++
      if ($bought) {
        $conv[$dk][$a].b++
        if (-not $prof[$dk].ContainsKey($a)) { $prof[$dk][$a] = 0 }; $prof[$dk][$a]++
      }
      if ($band -eq 'a') { if (-not $aprof[$dk].ContainsKey($a)) { $aprof[$dk][$a] = 0 }; $aprof[$dk][$a]++ }
    }
  }
  # ---- indice de conversao por resposta = (compra/lead da resposta) / conversao media ----
  $totN = $bt.q.n + $bt.m.n + $bt.f.n; $totB = $bt.q.b + $bt.m.b + $bt.f.b
  $avgConv = if ($totN -gt 0) { $totB / $totN } else { 0 }
  $convArr = @{}
  foreach ($dk in $DK8) {
    $mm = @{}
    foreach ($a in $conv[$dk].Keys) {
      $c = $conv[$dk][$a]
      $cv = if ($c.n -gt 0) { $c.b / $c.n } else { 0 }
      $ix = if ($avgConv -gt 0 -and $c.n -ge 25) { [Math]::Round($cv / $avgConv, 2) } else { $null }
      $mm[$a] = @{ n = $c.n; b = $c.b; idx = $ix }
    }
    $convArr[$dk] = $mm
  }
  function TopProf($h, $dims) {
    $arr = New-Object System.Collections.ArrayList
    foreach ($dm in $dims) {
      $dk = $dm.key; $top = ''; $topN = 0; $tot = 0
      foreach ($a in $h[$dk].Keys) { $tot += $h[$dk][$a]; if ($h[$dk][$a] -gt $topN) { $topN = $h[$dk][$a]; $top = $a } }
      [void]$arr.Add(@{ key = $dk; label = $dm.label; top = $top; n = $topN; tot = $tot })
    }
    return @($arr)
  }
  $profArr = TopProf $prof $DIMS
  $aProfArr = TopProf $aprof $DIMS
  # ---- distribuicao COMPLETA do comprador por dimensao (pras pizzas) ----
  $buyerDist = @{}
  foreach ($dm in $DIMS) { $dk = $dm.key; $o = @{}; foreach ($a in $prof[$dk].Keys) { $o[$a] = $prof[$dk][$a] }; $buyerDist[$dk] = $o }
  return @{ matCut = $matCut; leads = $leads.Count; buyers = ($bt.q.b + $bt.m.b + $bt.f.b); tier = $bt; abc = $abc; profile = @($profArr); aProfile = @($aProfArr); conv = $convArr; avgConv = [Math]::Round($avgConv, 5); buyerDist = $buyerDist }
}
$nowBR = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'E. South America Standard Time')
$matCut = $nowBR.AddDays(-4).ToString('yyyy-MM-dd')
$validation = Compute-Validation @((Join-Path $dataDir 'terca_pesq.csv'), (Join-Path $dataDir 'segunda_pesq.csv'), (Join-Path $dataDir 'diario_pesq.csv'), (Join-Path $dataDir 'dias2_pesq.csv')) $script:FDI_BUYERS $matCut
Write-Host ("   validacao: {0} leads maturados, {1} compradores | Quente {2}/{3} Morno {4}/{5} Frio {6}/{7}" -f $validation.leads, $validation.buyers, $validation.tier.q.b, $validation.tier.q.n, $validation.tier.m.b, $validation.tier.m.n, $validation.tier.f.b, $validation.tier.f.n)
$payload = @{
  generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
  generatedAtBR = $nowBR.ToString('dd/MM/yyyy HH:mm')
  taxMultiplier = $TAX
  quenteMin     = $QUENTE_MIN
  mornoMin      = $MORNO_MIN
  surveyStart   = $SURVEY_START
  product       = 'Formula dos Investimentos'
  sales         = $salesInfo
  validation    = $validation
  names         = @{ c = @($CampArr.ToArray()); s = @($SetArr.ToArray()); a = @($AdArr.ToArray()); src = @($SrcArr.ToArray()); med = @($MedArr.ToArray()) }
  segunda       = FunnelPayload $seg
  terca         = FunnelPayload $ter
  diario        = FunnelPayload $dia
  dias2         = FunnelPayload $dois2
  pesquisa      = @{
    surveyStart = $SURVEY_START
    dims        = @($pesqDims)
    profile     = @($pesqProfile)
    seg         = @{ respTot = $seg.respTot; respMatch = $seg.respMatch; tierTot = $seg.tierTot; leadsEra = $seg.leadsEra }
    ter         = @{ respTot = $ter.respTot; respMatch = $ter.respMatch; tierTot = $ter.tierTot; leadsEra = $ter.leadsEra }
    dia         = @{ respTot = $dia.respTot; respMatch = $dia.respMatch; tierTot = $dia.tierTot; leadsEra = $dia.leadsEra }
  }
}

$json = $payload | ConvertTo-Json -Depth 20 -Compress
$js = "window.POMPEU = $json;`nwindow.POMPEU_OK = true;"
$outFile = Join-Path $root 'data.js'
[System.IO.File]::WriteAllText($outFile, $js, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $outFile ($([Math]::Round((Get-Item $outFile).Length/1kb,1)) KB)"
Write-Host "DONE $($payload.generatedAtBR)"
