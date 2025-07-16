param (
    [Parameter(Mandatory=$true)]
    [string]$InitialLogPath, # Bu, 'C:\temp\scan-adi_log.txt' gibi bir yol olacak

    [Parameter(Mandatory=$true)]
    [string]$ErrorsFilePath  # Bu, '.../hatalar.txt' yolu olacak
)

# Hatalarla karsilasildiginda script'in hemen durmasini saglar.
$ErrorActionPreference = "Stop"

# ==============================================================================
# BOLUM 1: SCRIPT PARAMETRELERI
# Pipeline'dan gelen -InitialLogPath ve -ErrorsFilePath argumanlarini alir.
# ==============================================================================

Write-Host "--- WebInspect Log Hata Kontrol Script'i Baslatildi ---" -ForegroundColor Cyan
Write-Host "Scan ID icin kullanilacak ilk log dosyasi: '$InitialLogPath'" -ForegroundColor Yellow

# ==============================================================================
# BOLUM 2: Scan ID'yi Bulan Fonksiyon (DEGISIKLIK YOK)
# Bu fonksiyon, kendisine verilen dosyadan Scan ID'yi cikarir.
# ==============================================================================
function Get-ScanIdFromFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Host "HATA: Baslangic log dosyasi bulunamadi: $FilePath" -ForegroundColor Red
        return $null
    }
    try {
        # WI.exe | Tee-Object ciktisi genellikle UTF-16 LE (Unicode) olur.
        $match = Select-String -Path $FilePath -Pattern "Scan ID\s*:\s*([a-f0-9-]+)" -Encoding Unicode
        if ($match) {
            return $match.Matches[0].Groups[1].Value.Trim()
        } else {
            Write-Host "HATA: '$FilePath' icinde 'Scan ID' formatina uygun bir satir bulunamadi." -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "HATA: Baslangic log dosyasi okunurken bir sorun olustu: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ==============================================================================
# BOLUM 3: Hedef Log Dosyasini Bulan Fonksiyon (DEGISIKLIK YOK)
# Bu fonksiyon, Scan ID'yi kullanarak AppData altindaki asil log dosyasini bulur.
# ==============================================================================
function Get-TargetLogFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ScanId
    )
    $basePath = "C:\Users\Administrator\AppData\Local\HP\HP WebInspect\Logs"
    $targetDirectory = Join-Path -Path $basePath -ChildPath (Join-Path -Path $ScanId -ChildPath "ScanLog")
    Write-Host "Asil log dosyasi icin kontrol edilecek dizin: $targetDirectory"
    if (-not (Test-Path -Path $targetDirectory -PathType Container)) {
        Write-Host "HATA: Belirtilen dizin bulunamadi. Lutfen yolu ve Scan ID'yi kontrol edin." -ForegroundColor Red
        return $null
    }
    $logFile = Get-ChildItem -Path $targetDirectory -Filter "*.log" | Select-Object -First 1
    if ($logFile) {
        return $logFile.FullName
    } else {
        Write-Host "HATA: '$targetDirectory' klasoru icinde .log uzantili bir log dosyasi bulunamadi." -ForegroundColor Red
        return $null
    }
}

# ==============================================================================
# BOLUM 4: HATA BULURSA PIPELINE'I KIRAN FONKSIYON (DEGISIKLIK YOK)
# Bu fonksiyon, asil log dosyasinda hata arar.
# ==============================================================================
function Check-LogForErrorsAndFail {
    param (
        [Parameter(Mandatory=$true)]
        [string]$TargetLogPath,
        [Parameter(Mandatory=$true)]
        [string]$ErrorsListPath
    )
    if (-not (Test-Path -Path $ErrorsListPath -PathType Leaf)) {
        Write-Host "HATA: Hata listesi dosyasi bulunamadi: $ErrorsListPath" -ForegroundColor Red
        exit 1
    }
    $aranacakHatalar = Get-Content -Path $ErrorsListPath -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }
    if ($aranacakHatalar.Count -eq 0) {
        Write-Host "UYARI: '$ErrorsListPath' dosyasi bos. Kontrol atlaniyor." -ForegroundColor Yellow
        return
    }
    # WebInspect'in dahili loglari genellikle UTF8'dir.
    $logIcerigi = Get-Content -Path $TargetLogPath -Raw -Encoding UTF8
    foreach ($hata in $aranacakHatalar) {
        $escapedHata = [regex]::Escape($hata)
        if (Select-String -InputObject $logIcerigi -Pattern $escapedHata -Quiet -CaseSensitive:$false) {
            Write-Host ("`n" + "!"*60) -ForegroundColor Red
            Write-Host "!!! KRITIK HATA TESPIT EDILDI !!!" -ForegroundColor Red
            Write-Host "ASIL LOG DOSYASINDA ($TargetLogPath) yasakli metin bulundu: '$hata'" -ForegroundColor Yellow
            Write-Host "Pipeline basarisiz olarak sonlandiriliyor." -ForegroundColor Red
            Write-Host ("!"*60) -ForegroundColor Red
            exit 1
        }
    }
}

# ==============================================================================
# --- ANA PROGRAM AKISI (GUNCELLENDI) ---
# Bu bolum, pipeline'dan alinan parametreleri kullanarak fonksiyonlari sirayla cagirir.
# ==============================================================================
try {
    # Adim 1: Pipeline'dan gelen ilk log dosyasindan Scan ID'yi al
    $scanId = Get-ScanIdFromFile -FilePath $InitialLogPath
    if (-not $scanId) {
        exit 1
    }
    Write-Host "[OK] Scan ID basariyla bulundu: $scanId" -ForegroundColor Green

    # Adim 2: Scan ID'yi kullanarak AppData'daki hedef log dosyasinin yolunu bul
    $hedefLogYolu = Get-TargetLogFile -ScanId $scanId
    if (-not $hedefLogYolu) {
        exit 1
    }
    Write-Host "[OK] Kontrol edilecek asil hedef log dosyasi bulundu:" -ForegroundColor Green
    Write-Host "     -> $hedefLogYolu"

    # Adim 3: Asil log dosyasinda hatalari kontrol et.
    Write-Host "`n[INFO] Asil log dosyasi ($hedefLogYolu) kritik hatalar icin taraniyor..."
    Check-LogForErrorsAndFail -TargetLogPath $hedefLogYolu -ErrorsListPath $ErrorsFilePath

    # Bu noktaya gelindiyse hicbir hata bulunmamistir.
    Write-Host ("`n" + "="*60) -ForegroundColor Green
    Write-Host ">>> BASARILI: Asil log dosyasinda belirtilen kritik hatalardan hicbiri bulunmadi." -ForegroundColor Green
    Write-Host ">>> Pipeline basariyla devam edebilir." -ForegroundColor Green
    Write-Host ("="*60) -ForegroundColor Green
    exit 0

}
catch {
    Write-Host "`n!!! BEKLENMEDIK BIR HATA OLUSTU !!!" -ForegroundColor Red
    Write-Host "Hata Mesaji: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script basarisiz olarak sonlandiriliyor." -ForegroundColor Red
    exit 1
}
