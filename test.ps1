# Hatalarla karsilasildiginda script'in hemen durmasini saglar.
$ErrorActionPreference = "Stop"

# ==============================================================================
# BOLUM 1: SCRIPT PARAMETRELERI
# Bu script, pipeline'dan gelen -InitialLogPath ve -ErrorsFilePath argumanlarini alir.
# ==============================================================================
param (
    [Parameter(Mandatory=$true)]
    [string]$InitialLogPath,

    [Parameter(Mandatory=$true)]
    [string]$ErrorsFilePath
)

# Script'in basladigini ve hangi dosyalari kontrol edecegini belirten baslik.
Write-Host "--- WebInspect Log Hata Kontrol Script'i Baslatildi ---" -ForegroundColor Cyan
Write-Host "Kontrol edilecek log dosyasi: '$InitialLogPath'" -ForegroundColor Yellow
Write-Host "Kullanilacak hata listesi: '$ErrorsFilePath'" -ForegroundColor Yellow

# ==============================================================================
# BOLUM 2: LOG DOSYASINI KONTROL EDEN FONKSIYON
# ==============================================================================
function Check-LogForErrorsAndFail {
    param (
        [Parameter(Mandatory=$true)]
        [string]$TargetLogPath,
        [Parameter(Mandatory=$true)]
        [string]$ErrorsListPath
    )

    # 1. Kontrol edilecek log dosyasinin varligini dogrula
    if (-not (Test-Path -Path $TargetLogPath -PathType Leaf)) {
        Write-Host "HATA: Pipeline tarafindan saglanan log dosyasi bulunamadi: $TargetLogPath" -ForegroundColor Red
        exit 1
    }

    # 2. Aranacak hatalari 'hatalar.txt' dosyasindan oku
    if (-not (Test-Path -Path $ErrorsListPath -PathType Leaf)) {
        Write-Host "HATA: Hata listesi dosyasi bulunamadi: $ErrorsListPath" -ForegroundColor Red
        exit 1
    }

    # Bos satirlari atlayarak hata listesini al
    $aranacakHatalar = Get-Content -Path $ErrorsListPath -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }

    if ($aranacakHatalar.Count -eq 0) {
        Write-Host "UYARI: '$ErrorsListPath' dosyasi bos. Kontrol atlaniyor." -ForegroundColor Yellow
        return
    }

    # 3. Log dosyasinin icerigini tek bir string olarak oku
    # Not: Log dosyasi cok buyukse Get-Content satir satir daha verimli olabilir,
    # ancak -Raw ile arama genellikle daha hizlidir.
    $logIcerigi = Get-Content -Path $TargetLogPath -Raw -Encoding Default # WI loglari genellikle sistem varsayilan kodlamasindadir.

    # 4. Hatalari kontrol et. Ilk bulunan hatada programi durdur.
    foreach ($hata in $aranacakHatalar) {
        $escapedHata = [regex]::Escape($hata)

        if (Select-String -InputObject $logIcerigi -Pattern $escapedHata -Quiet -CaseSensitive:$false) {
            # HATA BULUNDU! Pipeline'i kir.
            Write-Host ("`n" + "!"*60) -ForegroundColor Red
            Write-Host "!!! KRITIK HATA TESPIT EDILDI !!!" -ForegroundColor Red
            Write-Host "Log dosyasinda yasakli metin bulundu: '$hata'" -ForegroundColor Yellow
            Write-Host "Pipeline basarisiz olarak sonlandiriliyor." -ForegroundColor Red
            Write-Host ("!"*60) -ForegroundColor Red
            exit 1 # Programi "basarisiz" durum koduyla sonlandir
        }
    }
}


# ==============================================================================
# --- ANA PROGRAM AKISI ---
# ==============================================================================
try {
    # Hatalari kontrol et.
    Write-Host "`n[INFO] Kritik hatalar icin log dosyasi taraniyor..."
    Check-LogForErrorsAndFail -TargetLogPath $InitialLogPath -ErrorsListPath $ErrorsFilePath

    # Bu noktaya gelindiyse hicbir hata bulunmamistir.
    Write-Host ("`n" + "="*60) -ForegroundColor Green
    Write-Host ">>> BASARILI: Log dosyasinda belirtilen kritik hatalardan hicbiri bulunmadi." -ForegroundColor Green
    Write-Host ">>> Pipeline basariyla devam edebilir." -ForegroundColor Green
    Write-Host ("="*60) -ForegroundColor Green
    exit 0 # Basarili durum koduyla cik

}
catch {
    # Beklenmedik bir hata olursa yakala ve pipeline'i kir.
    Write-Host "`n!!! BEKLENMEDIK BIR HATA OLUSTU !!!" -ForegroundColor Red
    Write-Host "Hata Mesaji: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script basarisiz olarak sonlandiriliyor." -ForegroundColor Red
    exit 1
}
