# Hatalarla karşılaşıldığında script'in hemen durmasını sağlar.
$ErrorActionPreference = "Stop"

# Script'in başladığını belirten başlık.
Write-Host "--- WebInspect Log Hata Kontrol Script'i Başlatıldı ---" -ForegroundColor Cyan

# ==============================================================================
# BÖLÜM 1: Scan ID'yi Bulan Fonksiyon
# ==============================================================================
function Get-ScanIdFromFile {
    <#
    .SYNOPSIS
        Başlangıç log dosyasından Scan ID'yi bulur.
    .PARAMETER FilePath
        Scan ID'yi içeren başlangıç log dosyasının yolu.
    .EXAMPLE
        Get-ScanIdFromFile -FilePath "C:\path\to\log.txt"
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Host "HATA: Başlangıç log dosyası bulunamadı: $FilePath" -ForegroundColor Red
        return $null
    }

    try {
        # Python script'indeki 'utf-16' kodlamasının PowerShell'deki karşılığı 'Unicode'dur.
        # -match operatörü büyük/küçük harfe duyarsızdır, bu da re.IGNORECASE'e denktir.
        $match = Select-String -Path $FilePath -Pattern "Scan ID\s*:\s*([a-f0-9-]+)" -Encoding Unicode

        if ($match) {
            # Eşleşmenin ilk yakalanan grubunu (parantez içindeki kısım) döndürür.
            return $match.Matches[0].Groups[1].Value.Trim()
        } else {
            Write-Host "HATA: '$FilePath' içinde 'Scan ID' formatına uygun bir satır bulunamadı." -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "HATA: Başlangıç log dosyası okunurken bir sorun oluştu: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ==============================================================================
# BÖLÜM 2: Hedef Log Dosyasını Bulan Fonksiyon
# ==============================================================================
function Get-TargetLogFile {
    <#
    .SYNOPSIS
        Verilen Scan ID'yi kullanarak hedef .log dosyasının tam yolunu bulur.
    .PARAMETER ScanId
        WebInspect taramasının benzersiz kimliği.
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
        Write-Host "HATA: Belirtilen dizin bulunamadı. Lütfen yolu ve Scan ID'yi kontrol edin." -ForegroundColor Red
        return $null
    }

    # Belirtilen dizindeki .log uzantılı ilk dosyayı bulur.
    $logFile = Get-ChildItem -Path $targetDirectory -Filter "*.log" | Select-Object -First 1

    if ($logFile) {
        return $logFile.FullName
    } else {
        Write-Host "HATA: '$targetDirectory' klasörü içinde .log uzantılı bir log dosyası bulunamadı." -ForegroundColor Red
        return $null
    }
}


# ==============================================================================
# BÖLÜM 3: HATA BULURSA PİPELINE'I KIRAN FONKSİYON
# ==============================================================================
function Check-LogForErrorsAndFail {
    <#
    .SYNOPSIS
        Hedef log dosyasında yasaklı bir hata metni bulursa,
        script'i hata koduyla sonlandırır.
    .PARAMETER TargetLogPath
        Taranacak olan hedef log dosyasının tam yolu.
    .PARAMETER ErrorsFilePath
        Aranacak hata metinlerini içeren dosyanın yolu (her satırda bir hata).
    .EXAMPLE
        Check-LogForErrorsAndFail -TargetLogPath "C:\path\to\scan.log" -ErrorsFilePath "hatalar.txt"
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$TargetLogPath,
        [Parameter(Mandatory=$true)]
        [string]$ErrorsFilePath
    )

    # 1. Aranacak hataları 'hatalar.txt' dosyasından oku
    if (-not (Test-Path -Path $ErrorsFilePath -PathType Leaf)) {
        Write-Host "HATA: Hata listesi dosyası bulunamadı: $ErrorsFilePath" -ForegroundColor Red
        exit 1 # Kritik hata, pipeline'ı kır
    }

    # Boş satırları atlayarak hata listesini al
    $aranacakHatalar = Get-Content -Path $ErrorsFilePath -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }

    if ($aranacakHatalar.Count -eq 0) {
        Write-Host "UYARI: '$ErrorsFilePath' dosyası boş. Kontrol atlanıyor." -ForegroundColor Yellow
        return # Hata yok, devam et
    }

    # 2. Hedef log dosyasının içeriğini tek bir string olarak oku (-Raw parametresi sayesinde)
    # Bu, büyük dosyalarda arama yapmayı çok daha hızlı hale getirir.
    $logIcerigi = Get-Content -Path $TargetLogPath -Raw -Encoding UTF8

    # 3. Hataları kontrol et. İlk bulunan hatada programı durdur.
    foreach ($hata in $aranacakHatalar) {
        # Hata metnindeki regex özel karakterlerini etkisizleştirir (re.escape gibi)
        $escapedHata = [regex]::Escape($hata)

        # Select-String -Quiet, ilk eşleşmeyi bulduğu anda true döner ve aramayı durdurur. Bu çok verimlidir.
        if (Select-String -InputObject $logIcerigi -Pattern $escapedHata -Quiet -CaseSensitive:$false) {
            # HATA BULUNDU! Pipeline'ı kır.
            Write-Host ("`n" + "!"*60) -ForegroundColor Red
            Write-Host "!!! KRİTİK HATA TESPİT EDİLDİ !!!" -ForegroundColor Red
            Write-Host "Log dosyasında yasaklı metin bulundu: '$hata'" -ForegroundColor Yellow
            Write-Host "Pipeline başarısız olarak sonlandırılıyor." -ForegroundColor Red
            Write-Host ("!"*60) -ForegroundColor Red
            exit 1 # Programı "başarısız" durum koduyla sonlandır
        }
    }
}


# ==============================================================================
# --- ANA PROGRAM AKIŞI ---
# ==============================================================================
try {
    # Adım 1: log.txt'den Scan ID'yi al
    $baslangicLogYolu = "C:\Users\Administrator\Desktop\log.txt"
    $scanId = Get-ScanIdFromFile -FilePath $baslangicLogYolu
    if (-not $scanId) {
        # Fonksiyon zaten hata mesajını yazdırdı, sadece çıkış yap.
        exit 1
    }
    Write-Host "[OK] Scan ID başarıyla bulundu: $scanId" -ForegroundColor Green

    # Adım 2: Scan ID'yi kullanarak hedef log dosyasının yolunu bul
    $hedefLogYolu = Get-TargetLogFile -ScanId $scanId
    if (-not $hedefLogYolu) {
        exit 1
    }
    Write-Host "[OK] Kontrol edilecek hedef log dosyası bulundu:" -ForegroundColor Green
    Write-Host "     -> $hedefLogYolu" -ForegroundColor DarkGreen

    # Adım 3: Hataları kontrol et.
    Write-Host "`n[INFO] Kritik hatalar için log dosyası taranıyor..."
    # Pipeline'da workingDirectory ayarlandığı için sadece dosya adını vermek yeterlidir.
    $hatalarDosyasiYolu = "hatalar.txt"
    Check-LogForErrorsAndFail -TargetLogPath $hedefLogYolu -ErrorsFilePath $hatalarDosyasiYolu

    # Bu noktaya gelindiyse hiçbir hata bulunmamıştır.
    Write-Host ("`n" + "="*60) -ForegroundColor Green
    Write-Host ">>> BAŞARILI: Log dosyasında belirtilen kritik hatalardan hiçbiri bulunmadı." -ForegroundColor Green
    Write-Host ">>> Pipeline başarıyla devam edebilir." -ForegroundColor Green
    Write-Host ("="*60) -ForegroundColor Green
    exit 0 # Başarılı durum koduyla çık

}
catch {
    # Beklenmedik bir hata olursa yakala ve pipeline'ı kır.
    Write-Host "`n!!! BEKLENMEDİK BİR HATA OLUŞTU !!!" -ForegroundColor Red
    Write-Host "Hata Mesajı: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script başarısız olarak sonlandırılıyor." -ForegroundColor Red
    exit 1
}
