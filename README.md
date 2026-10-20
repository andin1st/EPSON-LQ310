# 🖨️ Driver Optimization Epson LQ-310 (Linux CUPS)

Repositori ini berisi skrip installer otomatis, file PPD teroptimasi, dan filter CUPS khusus untuk printer dot-matrix **Epson LQ-310** pada lingkungan Linux (**Linux Mint**, Ubuntu, Debian, Arch, Fedora, dan distro berbasis CUPS lainnya).

Penggunaan konfigurasi ini berhasil mengatasi kendala pencetakan lambat di Linux, memangkas waktu cetak dokumen Bukti Kas Masuk (BKM) / faktur 2 halaman dari **~150 detik** menjadi **~13.3 detik** (**21.6% lebih cepat** dibandingkan driver resmi Windows yang membutuhkan 16.99 detik).

---

## ⚡ Pemasangan Kilat (One-Liner Install)

Anda dapat memasang driver ini secara langsung di PC client (Linux Mint) cukup dengan satu baris perintah terminal tanpa perlu melakukan `git clone` manual:

```bash
curl -fsSL https://raw.githubusercontent.com/<username>/<repo>/main/install.sh | sudo bash
```

> **Catatan:** Ganti `<username>/<repo>` pada URL dengan nama akun dan repositori GitHub Anda.

### Apa yang Dilakukan oleh One-Liner Script Ini?
1. **Auto-Fetch Dependencies:** Otomatis mendeteksi dan mengunduh berkas `LQ-310.ppd` dan `foomatic-rip-lq310` dari Raw GitHub ke folder sementara (`/tmp`).
2. **Paket Pendukung Otomatis:** Mendeteksi package manager (`apt`, `pacman`, `dnf`, `zypper`) dan menginstal dependensi CUPS (`cups`, `cups-client`, `cups-filters`, `foomatic-db`, `perl`).
3. **Pemasangan Filter CUPS:** Menyalin filter `foomatic-rip-lq310` ke `/usr/lib/cups/filter/` dengan izin eksekusi yang sesuai.
4. **Deteksi Auto USB:** Mendeteksi printer Epson LQ-310 yang terhubung via USB secara otomatis.
5. **Pendaftaran Antrean Printer:** Mendaftarkan printer dengan nama `LQ-310`, mengunci resolusi ke **120x180 dpi**, dan mengaktifkan ukuran form kustom **arc-paper (5.5 x 8.5 inci)**.
6. **Pembersihan Otomatis:** Menghapus berkas temporary di `/tmp` setelah instalasi selesai.

---

## 🛠️ Opsi Penggunaan Skrip (`install.sh`)

Jika Anda telah mengunduh / melakukan `git clone` repositori ini secara lokal, Anda dapat menjalankan skrip `install.sh` dengan beberapa parameter opsi:

### 1. Instalasi Printer USB Lokal (Default)
```bash
./install.sh
```

### 2. Instalasi Lokal + Cetak Halaman Uji (Test Page)
```bash
./install.sh --test
```

### 3. Instalasi Client Jaringan (Shared IPP Printer)
Jika printer terhubung ke PC server lain di jaringan lokal dan dibagikan via CUPS/IPP:
```bash
./install.sh --client ipp://<IP-SERVER>:631/printers/<NAMA-QUEUE> --name LQ-310-IT --default --test
```

---

## 📁 Isi Berkas Repositori

| Berkas | Fungsi / Deskripsi |
| :--- | :--- |
| **`install.sh`** | Skrip installer universal (mendukung mode local USB, network IPP client, dan remote pipe execution via `curl`). |
| **`LQ-310.ppd`** | Profil PPD teroptimasi dengan resolusi default `120x180 dpi` dan definisi form kertas kustom `arc-paper` (5.5 x 8.5 in). |
| **`foomatic-rip-lq-310`** | Filter wrapper CUPS dengan injeksi perintah ESC/P (`ESC C = 5.5 inch`) untuk menjamin penghentian kertas tepat pada garis perforasi continuous form. |
| **`README.md`** | Dokumentasi lengkap repositori dan panduan penggunaan. |

---

## 📊 Hasil Benchmark Kecepatan Cetak (Dokumen BKM 2 Halaman)

| Konfigurasi / Driver | Resolusi 120x180 dpi | Resolusi 180 dpi | Status Performa |
| :--- | :---: | :---: | :--- |
| **Custom PPD Optimized (Printer D)** | **13.31 detik** | **19.25 detik** | **Tercepat (Rekomendasi Utama)** |
| **Generic EPSON ESC/P 2 (Printer B)** | **14.05 detik** | **19.66 detik** | Sangat Baik & Stabil |
| **Driver Resmi Windows** *(Pembanding)* | 16.99 detik | 23.32 detik | Standar Acuan Windows |
| **Epson LQ-24 Foomatic (Printer A)** | 16.26 detik | Error / Fail | Tidak Stabil |
| **PPD Borwita Custom (Printer C)** | 45.00 detik | 47.00 detik | Lambat |

---

## 🔧 Spesifikasi & Fitur Teknis Utama

* **Resolusi Teroptimasi (120x180 dpi):** Mengurangi volume pemrosesan data raster grafik sebesar ~33%, memangkas gerakan head printer sebesar 5–6 detik per dokumen.
* **Penghentian Perforasi Tepat (Arc-Paper 5.5 x 8.5 in):** Mengatur panjang halaman fisik ke 5.5 inci (`ESC C 33`) sehingga printer berhenti pas di garis perforasi kertas tanpa *page eject delay* atau kertas tergulung berlebih.
* **Dukungan Lintas Distro:** Bekerja secara *out-of-the-box* pada Linux Mint, Ubuntu, Debian, Arch Linux, Fedora, openSUSE, dan Alpine Linux.

---

## 🔍 Verifikasi & Perintah Dasar CUPS

Setelah instalasi selesai, Anda dapat memverifikasi antrean printer di terminal:

- **Cek Status Printer:**
  ```bash
  lpstat -p LQ-310
  lpstat -v LQ-310
  ```
- **Cetak Dokumen Manual:**
  ```bash
  lp -d LQ-310 namafile.pdf
  ```
- **Menghapus Printer dari CUPS:**
  ```bash
  sudo lpadmin -x LQ-310
  ```
