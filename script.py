import re
import os
import sys  # sys.exit() kullanmak için bu modül gerekli

# --- BÖLÜM 1: Scan ID'yi Bulan Fonksiyon (Değişiklik yok) ---
def scan_id_bul(dosya_yolu):
    """Başlangıç log dosyasından Scan ID'yi bulur."""
    try:
        with open(dosya_yolu, 'r', encoding='utf-16') as dosya:
            for satir in dosya:
                eslesme = re.search(r"Scan ID\s*:\s*([a-f0-9-]+)", satir, re.IGNORECASE)
                if eslesme:
                    return eslesme.group(1).strip()
        print(f"HATA: '{dosya_yolu}' içinde 'Scan ID' formatına uygun bir satır bulunamadı.")
        return None
    except FileNotFoundError:
        print(f"HATA: Başlangıç log dosyası bulunamadı: {dosya_yolu}")
        return None
    except Exception as e:
        print(f"HATA: Başlangıç log dosyası okunurken bir sorun oluştu: {e}")
        return None

# --- BÖLÜM 2: Hedef Log Dosyasını Bulan Fonksiyon (Değişiklik yok) ---
def hedef_log_dosyasini_bul(scan_id):
    """Verilen Scan ID'yi kullanarak hedef .txt log dosyasının tam yolunu bulur."""
    base_path = r"C:\Users\Administrator\AppData\Local\HP\HP WebInspect\Logs"
    hedef_dizin = os.path.join(base_path, scan_id, "ScanLog")

    print(f"Kontrol edilecek dizin: {hedef_dizin}")
    if not os.path.isdir(hedef_dizin):
        print(f"HATA: Belirtilen dizin bulunamadı. Lütfen yolu ve Scan ID'yi kontrol edin.")
        return None
    for dosya_adi in os.listdir(hedef_dizin):
        if dosya_adi.lower().endswith('.txt'):
            return os.path.join(hedef_dizin, dosya_adi)
    print(f"HATA: '{hedef_dizin}' klasörü içinde .txt uzantılı bir log dosyası bulunamadı.")
    return None

# --- BÖLÜM 3: HATA BULURSA PİPELINE'I KIRAN FONKSİYON (YENİ MANTIK) ---
def hatalari_kontrol_et_ve_durdur(hedef_log_yolu, hatalar_dosyasi):
    """
    Hedef log dosyasında yasaklı bir hata metni bulursa,
    programı hata koduyla sonlandırır.
    """
    # 1. Aranacak hataları 'hatalar.txt' dosyasından oku
    try:
        with open(hatalar_dosyasi, 'r', encoding='utf-8') as f:
            aranacak_hatalar = [line.strip() for line in f if line.strip()]
        if not aranacak_hatalar:
            print(f"UYARI: '{hatalar_dosyasi}' dosyası boş. Kontrol atlanıyor.")
            return # Hata yok, devam et
    except FileNotFoundError:
        print(f"HATA: Hata listesi dosyası bulunamadı: {hatalar_dosyasi}")
        sys.exit(1) # Kritik hata, pipeline'ı kır

    # 2. Hedef log dosyasının içeriğini oku
    try:
        with open(hedef_log_yolu, 'r', encoding='utf-16') as log_dosyasi:
            log_icerigi = log_dosyasi.read()
    except Exception as e:
        print(f"HATA: Hedef log dosyası '{hedef_log_yolu}' okunurken bir sorun oluştu: {e}")
        sys.exit(1) # Kritik hata, pipeline'ı kır

    # 3. Hataları kontrol et. İlk bulunan hatada programı durdur.
    for hata in aranacak_hatalar:
        if re.search(re.escape(hata), log_icerigi, re.IGNORECASE):
            # HATA BULUNDU! Pipeline'ı kır.
            print("\n" + "!"*60)
            print(f"!!! KRİTİK HATA TESPİT EDİLDİ !!!")
            print(f"Log dosyasında yasaklı metin bulundu: '{hata}'")
            print("Pipeline başarısız olarak sonlandırılıyor.")
            print("!"*60)
            sys.exit(1) # Programı "başarısız" durum koduyla sonlandır

# --- ANA PROGRAM AKIŞI ---
if __name__ == "__main__":
    print("--- WebInspect Log Hata Kontrol Script'i Başlatıldı ---")

    # Adım 1: log.txt'den Scan ID'yi al
    scan_id = scan_id_bul("log.txt")
    if not scan_id:
        sys.exit(1) # Fonksiyon zaten hata mesajını yazdı, sadece çıkış yap
    print(f"[OK] Scan ID başarıyla bulundu: {scan_id}")

    # Adım 2: Scan ID'yi kullanarak hedef log dosyasının yolunu bul
    hedef_log_yolu = hedef_log_dosyasini_bul(scan_id)
    if not hedef_log_yolu:
        sys.exit(1) # Fonksiyon zaten hata mesajını yazdı, sadece çıkış yap
    print(f"[OK] Kontrol edilecek hedef log dosyası bulundu:\n     -> {hedef_log_yolu}")

    # Adım 3: Hataları kontrol et. Eğer hata bulursa fonksiyon programı sonlandıracak.
    print("\n[INFO] Kritik hatalar için log dosyası taranıyor...")
    hatalari_kontrol_et_ve_durdur(hedef_log_yolu, "hatalar.txt")

    # Eğer program bu satıra ulaşabildiyse, hiçbir kritik hata bulunamamıştır.
    print("\n" + "="*60)
    print(">>> BAŞARILI: Log dosyasında belirtilen kritik hatalardan hiçbiri bulunmadı.")
    print(">>> Pipeline başarıyla devam edebilir.")
    print("="*60)
    sys.exit(0) # Programı "başarılı" durum koduyla sonlandır

