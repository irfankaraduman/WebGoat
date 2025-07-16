# Hatalarla karsilasildiginda script'in hemen durmasini saglar.
$ErrorActionPreference = "Stop"

# Script'in basladigini belirten baslik.
Write-Host "--- WebInspect Log Hata Kontrol Script'i Baslatildi ---" -ForegroundColor Cyan

# ==============================================================================
# BOLUM 1: Scan ID'yi Bulan Fonksiyon
# ==============================================================================
function Get-ScanIdFromFile {
    <#
    .SYNOPSIS
        Baslangic log dosyasindan Scan ID'yi bulur.
    .PARAMETER FilePath
        Scan ID'yi iceren baslangic log dosyasinin yolu.
    .EXAMPLE
        Get-ScanIdFromFile -FilePath "C:\path\to\log.txt"
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Host "HATA: Baslangic log dosyasi bulunamadi: $FilePath" -ForegroundColor Red
        return $null
    }

    try {
        # Python script'indeki 'utf-16' kodlamasinin PowerShell'deki karsiligi 'Unicode'dur.
        # -match operatoru buyuk/kucuk harfe duyarsizdir, bu da re.IGNORECASE'e denktir.
        $match = Select-String -Path $FilePath -Pattern "Scan ID\s*:\s*([a-f0-9-]+)" -Encoding Unicode

        if ($match) {
            # Eslesmenin ilk yakalanan grubunu (parantez icindeki kisim) dondurur.
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
# BOLUM 2: Hedef Log Dosyasini Bulan Fonksiyon
# ==============================================================================
function Get-TargetLogFile {
    <#
    .SYNOPSIS
        Verilen Scan ID'yi kullanarak hedef .log dosyasinin tam yolunu bulur.
    .PARAMETER ScanId
        WebInspect taramasinin benzersiz kimligi.
    .EXAMPLE
        Get-TargetLogFile -ScanId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$ScanId
    )

    $basePath = "C:\Users\Administrator\AppData\Local\HP\HP WebInspect\Logs"
    $targetDirectory = Join-Path -Path $basePath -ChildPath (Join-Path -Path $ScanId -ChildPath "ScanLog")

    Write-Host "Kontrol edilecek dizin: $targetDirectory"

    if (-not (Test-Path -Path $targetDirectory -PathType Container)) {
        Write-Host "HATA: Belirtilen dizin bulunamadi. Lutfen yolu ve Scan ID'yi kontrol edin." -ForegroundColor Red
        return $null
    }

    # Belirtilen dizindeki .log uzantili ilk dosyayi bulur.
    $logFile = Get-ChildItem -Path $targetDirectory -Filter "*.log" | Select-Object -First 1

    if ($logFile) {
        return $logFile.FullName
    } else {
        Write-Host "HATA: '$targetDirectory' klasoru icinde .log uzantili bir log dosyasi bulunamadi." -ForegroundColor Red
        return $null
    }
}


# ==============================================================================
# BOLUM 3: HATA BULURSA PIPELINE'I KIRAN FONKSIYON
# ==============================================================================
function Check-LogForErrorsAndFail {
    <#
    .SYNOPSIS
        Hedef log dosyasinda yasakli bir hata metni bulursa,
        script'i hata koduyla sonlandirir.
    .PARAMETER TargetLogPath
        Taranacak olan hedef log dosyasinin tam yolu.
    .PARAMETER ErrorsFilePath
        Aranacak hata metinlerini iceren dosyanin yolu (her satirda bir hata).
    .EXAMPLE
        Check-LogForErrorsAndFail -TargetLogPath "C:\path\to\scan.log" -ErrorsFilePath "hatalar.txt"
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$TargetLogPath,
        [Parameter(Mandatory=$true)]
        [string]$ErrorsFilePath
    )

    # 1. Aranacak hatalari 'hatalar.txt' dosyasindan oku
    if (-not (Test-Path -Path $ErrorsFilePath -PathType Leaf)) {
        Write-Host "HATA: Hata listesi dosyasi bulunamadi: $ErrorsFilePath" -ForegroundColor Red
        exit 1 # Kritik hata, pipeline'i kir
    }

    # Bos satirlari atlayarak hata listesini al
    $aranacakHatalar = Get-Content -Path $ErrorsFilePath -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }

    if ($aranacakHatalar.Count -eq 0) {
        Write-Host "UYARI: '$ErrorsFilePath' dosyasi bos. Kontrol atlaniyor." -ForegroundColor Yellow
        return # Hata yok, devam et
    }

    # 2. Hedef log dosyasinin icerigini tek bir string olarak oku (-Raw parametresi sayesinde)
    # Bu, buyuk dosyalarda arama yapmayi cok daha hizli hale getirir.
    $logIcerigi = Get-Content -Path $TargetLogPath -Raw -Encoding UTF8

    # 3. Hatalari kontrol et. Ilk bulunan hatada programi durdur.
    foreach ($hata in $aranacakHatalar) {
        # Hata metnindeki regex ozel karakterlerini etkisizlestirir (re.escape gibi)
        $escapedHata = [regex]::Escape($hata)

        # Select-String -Quiet, ilk eslesmeyi buldugu anda true doner ve aramayi durdurur. Bu cok verimlidir.
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
    # Adim 1: log.txt'den Scan ID'yi al
    $baslangicLogYolu = "C:\Users\Administrator\Desktop\log.txt"
    $scanId = Get-ScanIdFromFile -FilePath $baslangicLogYolu
    if (-not $scanId) {
        # Fonksiyon zaten hata mesajini yazdirdi, sadece cikis yap.
        exit 1
    }
    Write-Host "[OK] Scan ID basariyla bulundu: $scanId" -ForegroundColor Green

    # Adim 2: Scan ID'yi kullanarak hedef log dosyasinin yolunu bul
    $hedefLogYolu = Get-TargetLogFile -ScanId $scanId
    if (-not $hedefLogYolu) {
        exit 1
    }
    Write-Host "[OK] Kontrol edilecek hedef log dosyasi bulundu:" -ForegroundColor Green
    Write-Host "     -> $hedefLogYolu" -ForegroundColor DarkGreen

    # Adim 3: Hatalari kontrol et.
    Write-Host "`n[INFO] Kritik hatalar icin log dosyasi taraniyor..."
    # Pipeline'da workingDirectory ayarlandigi icin sadece dosya adini vermek yeterlidir.
    $hatalarDosyasiYolu = "hatalar.txt"
    Check-LogForErrorsAndFail -TargetLogPath $hedefLogYolu -ErrorsFilePath $hatalarDosyasiYolu

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
