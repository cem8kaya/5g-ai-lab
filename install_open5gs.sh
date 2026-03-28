#!/bin/bash

# Loglama: Tüm kurulum çıktılarını bir log dosyasına yazdırarak hata takibini kolaylaştırıyoruz.
exec > >(tee -i /var/log/open5gs_install.log)
exec 2>&1

echo "============================================="
echo "   5G Core (Open5GS) & gtp5g Otomatik Kurulum"
echo "============================================="

# 1. Sistem Güncellemesi ve Temel Bağımlılıklar
echo "[1/5] Sistem güncelleniyor ve derleme araçları kuruluyor..."

# Tüm interaktif pencereleri tamamen kapatıyoruz
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get upgrade -y

# iptables-persistent kurulumunda çıkan mavi ekranları otomatik "Yes" olarak geçmek için cevapları önceden tanımlıyoruz:
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

sudo apt-get install -y software-properties-common curl git build-essential cmake ninja-build \
    python3-pip python3-setuptools python3-wheel meson net-tools iptables iptables-persistent

# 2. MongoDB Kurulumu (Open5GS Subscriber veritabanı için zorunlu)
echo "[2/5] MongoDB kuruluyor..."
curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | sudo gpg --dearmor -o /etc/apt/keyrings/mongodb-server-6.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/etc/apt/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org
sudo systemctl start mongod
sudo systemctl enable mongod

# 3. gtp5g Kernel Modülünün Derlenmesi (UPF için hayati önem taşır)
echo "[3/5] gtp5g kernel modülü derleniyor ve yükleniyor..."
cd ~
git clone https://github.com/free5gc/gtp5g.git
cd gtp5g
make
sudo make install

# 4. Open5GS Kurulumu
echo "[4/5] Open5GS paketleri indiriliyor ve kuruluyor..."
sudo add-apt-repository ppa:open5gs/latest -y
sudo apt-get update
sudo apt-get install -y open5gs

# 5. Network Ayarları (IP Forwarding ve NAT)
# Bu adım simüle edilen UE'lerin Data Network'e (İnternete) çıkabilmesini sağlar.
echo "[5/5] IPv4 Forwarding ve NAT ayarları yapılandırılıyor..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sh -c "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"

# Open5GS varsayılan olarak 10.45.0.0/16 bloğunu kullanır. ogstun interface'inden çıkan trafiği maskeliyoruz.
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
sudo netfilter-persistent save

echo "============================================="
echo " Kurulum Tamamlandı! Open5GS servisleri aktif."
echo "============================================="

# Servis durumunu kontrol etmek için (opsiyonel):
# systemctl status open5gs-amfd --no-pager
