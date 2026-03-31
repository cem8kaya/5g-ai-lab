# 5g-ai-lab

# 5G AI/ML Laboratory

> **A simulated 5G Core Network for generating labeled telecommunications traffic datasets and developing ML-ready data science pipelines.**
>
> **Etiketlenmiş telekomünikasyon trafik veri setleri üretmek ve makine öğrenmesine hazır veri bilimi pipeline'ları geliştirmek için simüle edilmiş 5G Core Network laboratuvarı.**

<br>

<img src="https://raw.githubusercontent.com/cem8kaya/5g-ai-lab/main/5g_lab_architecture.svg" width="800">

<br>

---

## Table of Contents / İçindekiler

- [Overview](#overview--genel-bakış)
- [Architecture](#architecture--mimari)
- [Data Pipeline](#data-pipeline)
- [Traffic Scenarios](#traffic-scenarios--trafik-senaryoları)
- [5G-Specific Experiments](#5g-specific-experiments--5g-spesifik-deneyler)
- [SeismoSense Integration](#seismosense-integration--seismosense-entegrasyonu)
- [3GPP Standards Compliance](#3gpp-standards-compliance--3gpp-standart-uyumu)
- [Key Technical Findings](#key-technical-findings--teknik-bulgular)
- [Dataset Schema](#dataset-schema--veri-seti-şeması)
- [ML Pipeline](#ml-pipeline)
- [Getting Started](#getting-started--başlangıç)
- [Lab Roadmap](#lab-roadmap--yol-haritası)
- [References](#references--referanslar)

---

## Overview / Genel Bakış

This lab builds an end-to-end simulated **5G Standalone (SA) Core Network** on Google Cloud Platform using **Open5GS v2.7.6** and **UERANSIM**, managed entirely through **Google Colab notebooks** via `gcloud` CLI. The primary goal is to generate realistic, labeled network traffic datasets for machine learning research in telecommunications.

Bu laboratuvar, **Open5GS v2.7.6** ve **UERANSIM** kullanarak Google Cloud Platform üzerinde uçtan uca simüle edilmiş bir **5G Standalone (SA) Core Network** kurar ve tüm yönetimi **Google Colab notebook'ları** üzerinden `gcloud` CLI ile gerçekleştirir. Temel hedef, telekomünikasyon alanında makine öğrenmesi araştırmaları için gerçekçi, etiketlenmiş ağ trafiği veri setleri üretmektir.

### Key Capabilities / Temel Özellikler

| Capability | Detail |
|---|---|
| **5G Core** | Full SA deployment: AMF, SMF, UPF, AUSF, UDM, PCF, NRF |
| **RAN Simulation** | UERANSIM gNB + UE, PLMN 999-70 |
| **Traffic Scenarios** | 8 labeled scenarios: baseline, anomaly, handover, session, QoS, slicing |
| **Data Science** | Pandas ETL, feature engineering, anomaly detection |
| **IoT Integration** | SeismoSense iPhone CoreMotion → 5G Core via Flask/STA-LTA |
| **Remote Management** | Full Colab-based operation: monitoring, config, fault management |
| **3GPP Compliance** | TS 23.501, TS 33.501, TS 28.554 alignment |

---

## Architecture / Mimari

<img src="https://raw.githubusercontent.com/cem8kaya/5g-ai-lab/main/5g_system_overview.svg" width="800">

### Infrastructure / Altyapı

```
Platform  : Google Cloud Platform
Project   : g-ai-lab-491619
Zone      : europe-west4-a
VM        : open5gs-ai-lab (Ubuntu 22.04 LTS, Kernel 6.8.0-gcp)
Management: Google Colab → gcloud compute ssh/scp
```

### Network Functions / Ağ Fonksiyonları

```
┌─────────────────────────────────────────────────────────────┐
│                    5G Core Network                          │
│                                                             │
│  AMF ──── SMF ──── UPF ──── ogstun ──── ens4 ──► Internet  │
│   │         │        │                                      │
│  AUSF      PCF    gtp5g kernel module                       │
│   │         │     (GTP-U encap/decap)                       │
│  UDM       NRF                                              │
│                                                             │
│  Prometheus :9090 ─── All NF metrics                       │
│  MongoDB ────────── Subscribers + SeismoSense data         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                       UERANSIM                              │
│                                                             │
│  nr-gnb ──► NGAP ──► AMF                                    │
│  nr-ue  ──► uesimtun0 (10.45.0.x/24)                       │
│  nr-binder ── GTP-U traffic binding                         │
└─────────────────────────────────────────────────────────────┘
```

### Subscriber Configuration / Abone Konfigürasyonu

| Parameter | Value |
|---|---|
| IMSI | `999700000000001` |
| Subscriber Key (K) | `465B5CE8B199B49FAA5F0A2EE238A6BC` |
| OPc | `E8ED289DEBA952E4283B54E88E6183CA` |
| DNN | `internet` |
| UE IP | `10.45.0.x` (dynamic, per PDU session) |
| PLMN | `999-70` (MCC: 999, MNC: 70) |

---

## Data Pipeline

<img src="https://raw.githubusercontent.com/cem8kaya/5g-ai-lab/main/5g_data_pipeline.svg" width="800">

### Critical Finding: gtp5g Kernel Bypass / Kritik Bulgu

First discovery of this lab is that the **gtp5g kernel module processes packets entirely in kernel space**, bypassing all standard user-space capture mechanisms:

Bu laboratuvarın ilk bulgusu, **gtp5g kernel modülünün paketleri tamamen kernel alanında işlemesi** ve tüm standart kullanıcı alanı yakalama mekanizmalarını atlamasıdır:

| Method / Yöntem | Result / Sonuç | Reason / Sebep |
|---|---|---|
| `tcpdump -i uesimtun0` |  0 packets | gtp5g kernel bypass |
| `tcpdump -i ogstun` |  0 packets | gtp5g kernel bypass |
| `tcpdump -i ens4` |  0 packets | NAT hides UE IP |
| `tcpdump -i lo` |  0 packets | loopback bypass |
| `iptables NFLOG` |  0 packets | nfnetlink_log unavailable |
| `eBPF TC SCHED_CLS` |  failed | BPF verifier: zero-size read |
| **CSV logging**  | **Working** | **nr-binder output parsing** |

**Adopted solution:** Parse `nr-binder` (curl/ping) output directly into structured CSV files, capturing RTT, byte counts, and timestamps with real measured values.

**Benimsenen çözüm:** `nr-binder` (curl/ping) çıktısını doğrudan yapılandırılmış CSV dosyalarına ayrıştırarak RTT, byte sayısı ve zaman damgalarını gerçek ölçülen değerlerle yakalamak.

### ETL Flow / ETL Akışı

```
nr-binder (ping/curl) ──► bash script ──► /tmp/*.csv (VM)
                                               │
                                        gcloud compute scp
                                               │
                                    Colab ◄─── *.csv
                                         │
                              pandas.read_csv() → DataFrame
                                         │
                              Feature Engineering → ML
```

---

## Traffic Scenarios / Trafik Senaryoları

<img src="https://raw.githubusercontent.com/cem8kaya/5g-ai-lab/main/5g_scenarios_overview.svg" width="800">

### Scenario A — General Traffic Profile / Genel Trafik Profili

Baseline 5G traffic across four sub-types over real UE tunnel (uesimtun0).

```
A_ICMP  : 20 × ping 8.8.8.8  │ RTT baseline: 0.285–0.499ms
A_HTTP  : 5  × HTTP GET       │ Bytes: 84B – 981KB
A_DNS   : 4  × DNS lookup     │ Latency: 3–8ms
A_BURST : 10 × rapid HTTP     │ Pattern: concurrency stress
```

**CSV Schema:**
```
timestamp_ms, scenario, ue_ip, target, protocol, bytes, rtt_ms, status
```

### Scenario B — Labeled Anomaly Dataset / Etiketli Anomali Veri Seti

Ground-truth labeled dataset for supervised ML anomaly detection.

```
NORMAL          : Web browsing + IoT heartbeat (2–6s intervals)
ANOMALY_SCAN    : 30 parallel rapid requests   → inter_arrival ~3ms
ANOMALY_FLOOD   : 50 parallel ICMP             → pkt_rate = 50
ANOMALY_SLOWLORIS: 5× slow large connections   → rtt_ms > 300ms
ANOMALY_EXFIL   : 1MB+ file transfer           → bytes_per_ms × 18
```

**Discriminating Features / Ayırt Edici Özellikler:**

| Feature | NORMAL | ANOMALY_SCAN | ANOMALY_EXFIL |
|---|---|---|---|
| `inter_arrival_ms` | ~2000ms | ~3ms (**666×** faster) | ~500ms |
| `bytes_per_ms` | 277 | 0 | 5115 (**18×** larger) |
| `rtt_zscore` | -0.35 → 0.30 | -0.35 | **6.93** |

### Scenario C — UPF Throughput Time Series / UPF Verim Zaman Serisi

Real-time interface statistics via `/proc/net/dev` delta calculation.

```
normal  (0–30s) : Regular HTTP + ICMP
burst   (30–45s): 8 parallel HTTP requests
idle    (45–60s): No traffic
burst2  (60–90s): Repeated HTTP + ICMP
```

### Multi-UE Profile Simulation / Çoklu UE Profil Simülasyonu

Three device profiles simulated over single UE tunnel:

```
UE1 / mobile_broadband : Large HTTP, 2s interval  → eMBB behavior
UE2 / iot_sensor        : 16B ICMP, 0.5s interval → mMTC behavior
UE3 / video_stream      : Large HTTP + 1400B ICMP  → Video pattern
```

---

## 5G-Specific Experiments / 5G Spesifik Deneyler

### Handover Simulation / Handover Simülasyonu

UE detach → re-attach cycle measuring NR handover KPIs (3GPP TS 38.300):

```
PRE_HANDOVER  → 10 RTT measurements (baseline: ~0.39ms)
HO_START      → pkill nr-ue (simulates cell loss)
HO_GAP        → tunnel down, session interrupted
HO_COMPLETE   → re-attach (measured: ~514ms)
POST_HANDOVER → 15 RTT measurements (spike observed: ~0.43ms)
STEADY_STATE  → 10 RTT measurements (stabilization: ~0.39ms)
```

**Observed KPIs / Gözlemlenen KPI'lar:**

| KPI | Value |
|---|---|
| Handover duration | ~514ms |
| Pre-HO RTT (avg) | 0.389ms |
| Post-HO RTT (avg, first 5) | 0.427ms (+9.8%) |
| Steady-state RTT (avg) | 0.392ms |

### PDU Session Lifecycle / PDU Session Yaşam Döngüsü

3 × complete session cycles measuring 3GPP TS 23.502 procedures:

```
SESSION_ACTIVE → DATA_TRANSFER → SESSION_TEARDOWN
→ SESSION_RELEASING → SESSION_RELEASED
→ SESSION_ESTABLISHING → SESSION_ESTABLISHED
```

**Measured durations / Ölçülen süreler:**

| Procedure | Duration |
|---|---|
| Teardown (via `nr-cli deregister`) | ~2–3s |
| Teardown (via `pkill` fallback) | ~22s |
| Re-establishment | ~530–3100ms |

> **Note:** `nr-cli deregister` triggers proper NAS Deregistration → PFCP Session Deletion, reducing teardown from 22s to ~2s compared to process kill.

### QoS Differentiation / QoS Farklılaştırma

3GPP TS 23.501 5QI class simulation:

| QoS Class | 5QI | Traffic Type | Target |
|---|---|---|---|
| eMBB | 9 | Large HTTP GET | Throughput > 10KB/s |
| mMTC | 8 | 84B ICMP, 0.5s | Low jitter < 1ms |
| URLLC | 1 | ping 1.1.1.1 | RTT < 5ms SLA |

**Observed URLLC SLA:** 83.3% SLA_MET (RTT < 5ms threshold)

### Network Slicing / Ağ Dilimleme

SST-labeled trafic profiles (3GPP TS 23.501 Sec. 5.15):

| Slice | SST | SD | Traffic | KPI |
|---|---|---|---|---|
| eMBB | 1 | 0x000001 | cloudflare HTTP | 981KB avg/request |
| URLLC | 2 | 0x000002 | 1.1.1.1 ping | 83.3% SLA met |
| mMTC | 3 | 0x000003 | 16B IoT ping | 40 heartbeats |

---

## SeismoSense Integration / SeismoSense Entegrasyonu

<img src="https://raw.githubusercontent.com/cem8kaya/5g-ai-lab/main/seismosense_integration.svg" width="800">

[SeismoSense](https://github.com/cem8kaya/SeismoSense) is an iPhone CoreMotion application that detects earthquake-like motion events. Integrated into the 5G Core lab as a real-time IoT sensor data source.

[SeismoSense](https://github.com/cem8kaya/SeismoSense), deprem benzeri hareket olaylarını tespit eden bir iPhone CoreMotion uygulamasıdır. 5G Core laboratuvarına gerçek zamanlı IoT sensör veri kaynağı olarak entegre edilmiştir.

### Integration Architecture / Entegrasyon Mimarisi

```
iPhone (SeismoSense)
  CoreMotion → AccelX/Y/Z @ 100Hz
  STA/LTA motion detection
        │
        │ HTTP POST JSON
        │ (WiFi / cellular)
        ▼
GCP VM :8080 (Flask Collector)
  STA/LTA seismic algorithm
  Alert threshold = 3.0
        │
        │ insert
        ▼
MongoDB (seismosense db)
  sensor_events collection
        │
        │ query API
        ▼
Google Colab
  Pandas analysis
  Real-time STA/LTA plot
  Anomaly detection
```

### STA/LTA Algorithm / STA/LTA Algoritması

Classic seismic early-warning algorithm applied to accelerometer data:

```
STA = mean(|a|²) over last 0.5s   (Short-Term Average)
LTA = mean(|a|²) over last 10.0s  (Long-Term Average)

ratio = STA / LTA

ratio ≥ 3.0  →  SEISMIC ALERT triggered
ratio < 3.0  →  NORMAL motion
```

### JSON Payload (iPhone → GCP)

```json
{
  "device_id":  "iphone-cem-001",
  "timestamp":  1711234567.123,
  "accel":      { "x": 0.01, "y": -0.02, "z": 0.98 },
  "gyro":       { "x": 0.001, "y": 0.002, "z": -0.001 },
  "magnitude":  0.985
}
```

### 5G Integration Note / 5G Entegrasyon Notu

> Current integration routes iPhone data over the public internet to the GCP VM external IP. True 5G radio integration (NR air interface) requires SDR hardware (e.g., USRP B210) and a physical USIM card. The mMTC slice (SST=3) is the intended bearer for this use case.
>
> Mevcut entegrasyon, iPhone verilerini genel internet üzerinden GCP VM dış IP'sine yönlendirir. Gerçek 5G radyo entegrasyonu (NR hava arayüzü) için SDR donanımı ve fiziksel USIM kartı gerekir. Bu kullanım senaryosu için hedeflenen taşıyıcı mMTC dilimi (SST=3)'dir.

---

## 3GPP Standards Compliance / 3GPP Standart Uyumu

| Standard | Topic | Implementation |
|---|---|---|
| TS 23.501 | 5G System Architecture | AMF/SMF/UPF/PCF/UDM/NRF |
| TS 23.502 | Procedures | PDU Session, Registration, Handover |
| TS 23.503 | Policy Control | PCF PCC rules |
| TS 24.501 | NAS Protocol | T3502/T3512 timers |
| TS 28.530 | Network Slice Management | S-NSSAI SST=1/2/3 |
| TS 28.554 | 5G E2E KPI | Prometheus metrics per NF |
| TS 33.501 | Security | NIA2/NEA2 algorithm order, SUCI/ECIES |
| TS 38.300 | NR Overall | gNB simulation via UERANSIM |

### Security Configuration / Güvenlik Konfigürasyonu

```yaml
# AMF security (TS 33.501 Sec. 6.7.1)
security:
  integrity_order: [NIA2, NIA1, NIA0]   # AES > SNOW-3G > NULL
  ciphering_order: [NEA2, NEA1, NEA0]   # AES > SNOW-3G > NULL
```

```yaml
# UDM SUCI concealment (TS 33.501 Sec. 6.12)
# Profile A: X25519 ECIES key pair
hnet:
  - scheme: 1       # Profile A (Curve25519)
    key: <private_key_hex>
```

---

## Key Technical Findings / Teknik Bulgular

### 1. gtp5g Kernel Bypass

The `gtp5g` kernel module performs GTP-U decapsulation entirely in kernel space, bypassing netfilter FORWARD chain, tcpdump hook points, eBPF TC ingress, and NFLOG. No user-space packet capture is possible on any interface (uesimtun0, ogstun, ens4, loopback). **Adopted workaround:** structured CSV logging from nr-binder output.

### 2. PDU Session IP Accumulation

Each PDU session restart assigns a new IP address (10.45.0.2 → .3 → .4...). The `get_ue_iface()` function dynamically detects the active tunnel interface, preventing silent measurement errors from hardcoded `uesimtun0` references.

### 3. Teardown Latency

Process-kill teardown (`pkill nr-ue`) takes ~22 seconds for UPF to release the PFCP session. Proper NAS Deregistration via `nr-cli deregister disable-5g` reduces this to ~2 seconds by triggering the correct 3GPP N1 → N11 → N4 signaling chain.

### 4. Throughput Measurement

`bc` command returns empty values in this kernel version for float arithmetic. **Fix:** inline Python3 calculations for KB/s delta computation. Additionally, `uesimtun0` RX counter always reads 0 due to gtp5g bypass; `ogstun` and `ens4` counters are the reliable measurement points.

### 5. URLLC SLA Observation

In GCP datacenter-internal routing conditions, 83.3% of URLLC pings to 1.1.1.1 achieve < 5ms RTT. The remaining 16.7% exceed threshold due to GCP egress jitter, not radio-layer issues — demonstrating realistic 5G QoS simulation limitations.

---

## Dataset Schema / Veri Seti Şeması

### Produced Files / Üretilen Dosyalar

| File | Records | Description |
|---|---|---|
| `scenario_a.csv` | ~39 | General traffic profile |
| `scenario_b.csv` | ~121 | Labeled anomaly dataset |
| `scenario_c.csv` | ~30 | UPF throughput time series |
| `scenario_multi_ue.csv` | ~85 | 3 UE device profiles |
| `scenario_handover.csv` | ~42 | HO lifecycle |
| `scenario_session.csv` | ~97 | PDU session lifecycle |
| `scenario_qos.csv` | ~65 | QoS class comparison |
| `scenario_slice.csv` | ~80 | Network slice KPIs |

### Feature Engineering / Özellik Mühendisliği

```python
# Derived features for ML
df['inter_arrival_ms'] = df['timestamp'].diff().dt.total_seconds() * 1000
df['bytes_per_ms']     = df['bytes'] / (df['rtt_ms'] + 1e-9)
df['is_icmp']          = (df['protocol'] == 'ICMP').astype(int)
df['is_http']          = (df['protocol'] == 'HTTP').astype(int)
df['is_dns']           = (df['protocol'] == 'DNS').astype(int)
df['rtt_zscore']       = (df['rtt_ms'] - df['rtt_ms'].mean()) / df['rtt_ms'].std()
df['is_anomaly']       = df['label'].str.startswith('ANOMALY').astype(int)
```

---

## ML Pipeline

### Anomaly Detection (Unsupervised) / Anomali Tespiti

```python
from sklearn.ensemble import IsolationForest

features = ['inter_arrival_ms', 'bytes_per_ms', 'rtt_zscore',
            'is_icmp', 'is_http', 'pkt_rate']

model = IsolationForest(contamination=0.2, random_state=42)
df['anomaly_pred'] = model.fit_predict(df[features])
```

### Traffic Classification (Supervised) / Trafik Sınıflandırma

```python
from sklearn.ensemble import RandomForestClassifier

# Scenario B: 5 classes
# NORMAL, ANOMALY_SCAN, ANOMALY_FLOOD, ANOMALY_SLOWLORIS, ANOMALY_EXFIL
clf = RandomForestClassifier(n_estimators=100, random_state=42)
clf.fit(X_train, y_train)
```

### Observed Class Separability / Gözlemlenen Sınıf Ayrışabilirliği

```
NORMAL vs ANOMALY_SCAN   → inter_arrival_ms gap: 2000ms vs 3ms   (666× ratio)
NORMAL vs ANOMALY_EXFIL  → bytes_per_ms gap:     277 vs 5115     (18× ratio)
NORMAL vs ANOMALY_FLOOD  → pkt_rate label:        1 vs 50        (50× ratio)
All anomalies            → rtt_zscore max: 6.93 (statistical outlier)
```

---

## Getting Started / Başlangıç

### Prerequisites / Ön Koşullar

```bash
# Local / Google Colab
pip install pandas scapy matplotlib seaborn numpy

# gcloud CLI authenticated
gcloud auth login
gcloud config set project g-ai-lab-491619
```

### Notebook Structure / Notebook Yapısı

```
5g_ai_lab_colab_v2.py     ← Main traffic scenarios (Hücre 0–16)
open5gs_operations.py      ← Monitoring, config, fault management
open5gs_3gpp_dev.py        ← 3GPP standards development
```

### Quick Start / Hızlı Başlangıç

```python
# 1. Health check
%%bash
gcloud compute ssh open5gs-ai-lab --project=g-ai-lab-491619 \
  --zone=europe-west4-a --command="
  for svc in amfd smfd upfd ausfd udmd; do
    printf '%-8s: %s\n' $svc $(systemctl is-active open5gs-$svc)
  done"

# 2. Run Scenario A (3 min)
# → Execute Cell 3 in 5g_ai_lab_colab_v2.py

# 3. Download and analyze
# → Execute Cells 11–14 for ETL + visualization
```

### Connectivity Setup / Bağlantı Kurulumu

```bash
# Fix NAT (run once after VM restart)
sudo iptables -t nat -F POSTROUTING
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
sudo sysctl -w net.ipv4.ip_forward=1

# Test UE connectivity
cd /opt/UERANSIM/build
./nr-binder uesimtun0 ping -c 3 8.8.8.8
```

---

## Lab Roadmap / Yol Haritası

<img src="https://raw.githubusercontent.com/cem8kaya/5g-ai-lab/main/5g_lab_roadmap.svg" width="800">

### Phase 1 — Complete / Aşama 1 — Tamamlandı ✅

- [x] Open5GS Core (7 NFs) deployment
- [x] UERANSIM gNB + UE + nr-binder integration
- [x] gtp5g bypass discovery and CSV workaround
- [x] 8 traffic scenarios with labeled datasets
- [x] Full Colab remote management (monitoring, ops, fault)
- [x] SeismoSense iPhone integration (Flask + STA/LTA)

### Phase 2 — In Progress / Aşama 2 — Devam Ediyor 🔄

- [ ] 3GPP security hardening (NIA2/NEA2 + SUCI/ECIES)
- [ ] Full network slicing (SST=1/2/3 separate subnets)
- [ ] Linux TC QoS enforcement per slice
- [ ] ML anomaly detection pipeline (Isolation Forest + XGBoost)
- [ ] Prometheus KPI activation on all NFs (TS 28.554)
- [ ] Multi-subscriber registration (UE2, UE3)

### Phase 3 — Vision / Aşama 3 — Vizyon 🔭

- [ ] SDR hardware integration (USRP B210 / LimeSDR)
- [ ] Multi-VM distributed lab (Core + gNB + UE separate VMs)
- [ ] Real-time streaming pipeline (Pub/Sub → Dataflow → BigQuery)
- [ ] ML model serving (Vertex AI + Edge deployment)
- [ ] Real X2/Xn handover (dual gNB)
- [ ] GTP-U capture solution (gtp5g kernel patch or BTF eBPF)

---

## References / Referanslar

### 3GPP Standards
- **TS 23.501** — System Architecture for 5G System
- **TS 23.502** — Procedures for 5G System
- **TS 23.503** — Policy and Charging Control Framework
- **TS 24.501** — Non-Access-Stratum (NAS) Protocol for 5G
- **TS 28.530** — Management and Orchestration of Networks and Services
- **TS 28.554** — 5G End-to-end Key Performance Indicators
- **TS 33.501** — Security Architecture and Procedures for 5G System
- **TS 38.300** — NR; NR and NG-RAN Overall Description

### Tools and Frameworks / Araçlar ve Çerçeveler

| Tool | Version | Purpose |
|---|---|---|
| [Open5GS](https://open5gs.org) | v2.7.6 | 5G Core Network |
| [UERANSIM](https://github.com/aligungr/UERANSIM) | latest | gNB + UE simulation |
| [gtp5g](https://github.com/free5gc/gtp5g) | kernel module | GTP-U data plane |
| [SeismoSense](https://github.com/cem8kaya/SeismoSense) | — | iPhone IoT sensor app |
| Google Cloud Platform | — | VM hosting, networking |
| Google Colab | — | Remote notebook management |

### Related Projects / İlgili Projeler
- [SeismoSense](https://github.com/cem8kaya/SeismoSense) — iPhone CoreMotion earthquake detection app / iPhone CoreMotion deprem tespit uygulaması

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

*Built with Open5GS, UERANSIM, and Google Cloud Platform.*
*Open5GS, UERANSIM ve Google Cloud Platform ile geliştirilmiştir.*
