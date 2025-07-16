# ==============================================================================
# 1. PARAMETRELERİ AL (BU HEP EN BAŞTA OLMALI)
# ==============================================================================
param (
    [Parameter(Mandatory=$true)]
    [string]$InitialLogPath,

    [Parameter(Mandatory=$true)]
    [string]$ErrorsFilePath
)

# Hata olursa script'i hemen durdur.
$ErrorActionPreference = "Stop"

# Script'in basladigini ve hangi parametreleri aldigini ekrana yazdir.
Write-Host "--- WebInspect Log Hata Kontrol Script'i Baslatildi ---" -ForegroundColor Cyan
Write-Host "Scan ID icin kullanilacak ilk log dosyasi: '$InitialLogPath'" -ForegroundColor Yellow
Write-Host "Kullanilacak hata listesi: '$ErrorsFilePath'" -ForegroundColor Yellow


# ==============================================================================
# BOLUM 2: Scan ID'yi Bulan Fonksiyon (DEĞİŞİKLİK YOK)
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
# BOLUM 3: Hedef Log Dosyalarini Bulan Fonksiyon (GÜNCELLENDİ)
# Bu fonksiyon, Scan ID'yi kullanarak AppData altindaki TÜM .log dosyalarini bulur.
# ==============================================================================
function Get-TargetLogFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ScanId
    )
    $basePath = "C:\Users\Administrator\AppData\Local\HP\HP WebInspect\Logs"
    $targetDirectory = Join-Path -Path $basePath -ChildPath (Join-Path -Path $ScanId -ChildPath "ScanLog")
    Write-Host "Asil log dosyalari icin kontrol edilecek dizin: $targetDirectory"
    if (-not (Test-Path -Path $targetDirectory -PathType Container)) {
        Write-Host "HATA: Belirtilen dizin bulunamadi. Lutfen yolu ve Scan ID'yi kontrol edin." -ForegroundColor Red
        return $null
    }

    # <<< DEĞİŞİKLİK 1: Artik ilk dosyayi degil, TÜM .log dosyalarini bulur.
    $logFiles = Get-ChildItem -Path $targetDirectory -Filter "*.log"
    
    if ($logFiles) {
        # Bulunan dosyalarin tam yolunu bir liste olarak dondur.
        return $logFiles.FullName
    } else {
        Write-Host "HATA: '$targetDirectory' klasoru icinde .log uzantili bir log dosyasi bulunamadi." -ForegroundColor Red
        return $null
    }
}

# ==============================================================================
# BOLUM 4: HATA BULURSA PIPELINE'I KIRAN FONKSIYON (DEĞİŞİKLİK YOK)
# Bu fonksiyonun mantigi ayni kaldi, cunku tek bir dosyayi kontrol etmesi yeterli.
# Ana program, bu fonksiyonu her dosya icin ayri ayri cagiracak.
# ==============================================================================
function Check-LogForErrorsAndFail {
    param (
        [Parameter(Mandatory=$true)]
        [string]$TargetLogPath,
        [Parameter(Mandatory=$true)]
        [string]$ErrorsFilePath 
    )
    if (-not (Test-Path -Path $ErrorsFilePath -PathType Leaf)) {
        Write-Host "HATA: Hata listesi dosyasi bulunamadi: $ErrorsFilePath" -ForegroundColor Red
        exit 1
    }
    $aranacakHatalar = Get-Content -Path $ErrorsFilePath -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }
    if ($aranacakHatalar.Count -eq 0) {
        Write-Host "UYARI: '$ErrorsFilePath' dosyasi bos. Kontrol atlaniyor." -ForegroundColor Yellow
        return
    }
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
# --- ANA PROGRAM AKISI (GÜNCELLENDİ) ---
# ==============================================================================
try {
    # Adim 1: Ilk log dosyasindan Scan ID'yi al
    $scanId = Get-ScanIdFromFile -FilePath $InitialLogPath
    if (-not $scanId) { exit 1 }
    Write-Host "[OK] Scan ID basariyla bulundu: $scanId" -ForegroundColor Green

    # Adim 2: AppData'daki TÜM hedef log dosyalarinin listesini al
    $hedefLogDosyalari = Get-TargetLogFile -ScanId $scanId
    if (-not $hedefLogDosyalari) { exit 1 }
    Write-Host "[OK] Kontrol edilecek $(($hedefLogDosyalari).Count) adet hedef log dosyasi bulundu:" -ForegroundColor Green
    $hedefLogDosyalari | ForEach-Object { Write-Host "     -> $_" } # Bulunan dosyalari listele
    
    # <<< DEĞİŞİKLİK 2: Artık tüm log dosyalarını kontrol etmek için bir DÖNGÜ var.
    # Adim 3: Her bir asil log dosyasinda hatalari kontrol et.
    Write-Host "`n[INFO] Hedef log dosyalari kritik hatalar icin sirayla taraniyor..."
    foreach ($tekLogDosyasi in $hedefLogDosyalari) {
        Write-Host "--- Taranan Dosya: $tekLogDosyasi ---"
        Check-LogForErrorsAndFail -TargetLogPath $tekLogDosyasi -ErrorsFilePath $ErrorsFilePath
    }

    # Bu noktaya gelindiyse HİÇBİR dosyada hata bulunmamıştır.
    Write-Host ("`n" + "="*60) -ForegroundColor Green
    Write-Host ">>> BASARILI: Taranan tum log dosyalarinda belirtilen kritik hatalardan hicbiri bulunmadi." -ForegroundColor Green
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
