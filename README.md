# VDES 빅데이터 플랫폼 - 완전 가이드

## 목차
1. [이 플랫폼이 뭐하는 건가요?](#1-이-플랫폼이-뭐하는-건가요)
2. [전체 파일 구조 설명](#2-전체-파일-구조-설명)
3. [Docker 기초 개념](#3-docker-기초-개념)
4. [컨테이너별 상세 설명](#4-컨테이너별-상세-설명)
5. [설정 파일 상세 설명](#5-설정-파일-상세-설명)
6. [사전 준비](#6-사전-준비)
7. [실행 방법](#7-실행-방법)
8. [서비스 접속 주소](#8-서비스-접속-주소)
9. [Spark 잡 실행 방법](#9-spark-잡-실행-방법)
10. [자주 쓰는 명령어](#10-자주-쓰는-명령어)
11. [문제 해결](#11-문제-해결)

---

## 1. 이 플랫폼이 뭐하는 건가요?

VDES/AIS 선박 메시지의 무결성을 분석하는 빅데이터 플랫폼입니다.
Lambda Architecture 패턴으로 구성되어 있으며, 크게 세 가지 역할을 합니다.

```
[Kafka] ──── 선박 메시지 수신 (AIS, ASM, VDE, VSI 토픽)
    │
    ├── [NiFi] ──────────── 메시지를 HDFS에 저장 (Batch Layer 수집)
    │
    └── [Spark Streaming] ─ 메시지를 실시간 분석 (Speed Layer)
              │
         [Spark Batch] ──── HDFS 데이터를 주기적으로 분석 (Batch Layer)
```

- **Batch Layer**: 쌓인 데이터를 일정 주기로 분석 (정확도 높음)
- **Speed Layer**: 들어오는 데이터를 실시간 분석 (빠른 응답)
- **Serving Layer**: 두 결과를 합쳐 최종 결과 제공 (Cassandra - 별도 구성)

---

## 2. 전체 파일 구조 설명

```
vdes-platform/
├── docker-compose.yml          ← 핵심 파일. 어떤 컨테이너를 어떻게 실행할지 정의
├── .env                        ← 환경변수. Kafka 서버 주소 등 변경 가능한 값 관리
├── init-hdfs.sh                ← HDFS 최초 실행 시 필요한 폴더를 만드는 스크립트
│
├── hadoop/
│   └── config/
│       ├── core-site.xml       ← Hadoop 기본 설정 (HDFS 주소 등)
│       └── hdfs-site.xml       ← HDFS 세부 설정 (복제본 수, 블록 크기 등)
│
├── spark/
│   └── spark-defaults.conf    ← Spark 기본 설정 (HDFS 연동, 리소스 등)
│
├── nifi/
│   └── README.md              ← NiFi UI에서 플로우 구성하는 방법 가이드
│
└── data/                      ← docker compose up 시 자동 생성. 건드리지 마세요.
    ├── namenode/               ← HDFS NameNode가 관리하는 메타데이터 저장
    ├── datanode/               ← HDFS DataNode가 저장하는 실제 데이터
    └── nifi/
        ├── data/               ← NiFi 플로우 상태 데이터
        ├── logs/               ← NiFi 실행 로그
        └── conf/               ← NiFi 설정 파일
```

> **data/ 폴더는 직접 만들거나 수정하지 마세요.**
> docker compose up 시 자동으로 생성되며, 삭제하면 저장된 데이터가 모두 사라집니다.

---

## 3. Docker 기초 개념

Docker를 처음 쓰신다면 이 개념만 알면 됩니다.

### 이미지 (Image)
프로그램 설치 파일과 같습니다. 예를 들어 `apache/hadoop:3.3.6` 은 Hadoop 3.3.6 버전이
미리 설치된 리눅스 환경의 설치 파일입니다. 처음 실행 시 자동으로 다운로드됩니다.

### 컨테이너 (Container)
이미지를 실행한 결과물입니다. 이미지가 설치파일이라면 컨테이너는 실행 중인 프로그램입니다.
각 컨테이너는 독립된 환경으로 실행되며, 서로 격리되어 있습니다.

### docker-compose.yml
여러 컨테이너를 한 번에 정의하고 실행하는 설정 파일입니다.
`docker compose up -d` 한 줄로 모든 컨테이너를 한 번에 시작합니다.

### 포트 (Port)
컨테이너 내부 프로그램에 외부에서 접근하기 위한 통로입니다.
`"9870:9870"` 은 내 PC의 9870 포트로 접속하면 컨테이너 내부 9870 포트로 연결된다는 뜻입니다.

### 볼륨 (Volume)
컨테이너는 기본적으로 삭제하면 데이터가 사라집니다. 볼륨은 데이터를 내 PC에 저장해서
컨테이너를 재시작해도 데이터가 유지되도록 합니다.
`./data/namenode:/tmp/hadoop-root/dfs/name` 은 컨테이너 내부의
`/tmp/hadoop-root/dfs/name` 폴더를 내 PC의 `./data/namenode` 폴더와 연결한다는 뜻입니다.

---

## 4. 컨테이너별 상세 설명

### 4.1 namenode (HDFS NameNode)

**한 줄 설명**: HDFS 파일 시스템의 관리자. 어떤 파일이 어디에 저장되어 있는지 목록을 관리합니다.

**HDFS가 뭔가요?**
Hadoop Distributed File System의 약자로, 대용량 파일을 여러 서버에 나눠서 저장하는
분산 파일 시스템입니다. 일반 파일 시스템(C드라이브 등)과 달리 수 TB 이상의 데이터를
안정적으로 저장할 수 있습니다. 이 플랫폼에서는 AIS/VDE 원시 메시지를 장기 보관하는
Data Lake로 사용합니다.

**NameNode의 역할**
도서관의 목록 시스템과 같습니다. 실제 책(데이터)은 DataNode에 있고, NameNode는
"이 파일은 DataNode의 몇 번 블록에 있다"는 위치 정보만 관리합니다.

```yaml
ports:
  - "9870:9870"   # 웹 브라우저로 HDFS 상태 확인 가능
  - "9000:9000"   # 다른 프로그램(NiFi, Spark)이 HDFS에 접근하는 통로
```

**접속**: http://localhost:9870 에서 HDFS에 저장된 파일 목록, 용량 등을 확인할 수 있습니다.

---

### 4.2 datanode (HDFS DataNode)

**한 줄 설명**: HDFS 파일 시스템의 실제 저장소. 데이터를 블록 단위로 저장합니다.

**DataNode의 역할**
도서관의 실제 책장과 같습니다. NameNode의 지시에 따라 데이터를 저장하고 읽어줍니다.
NiFi가 Kafka 메시지를 HDFS에 저장할 때, Spark가 HDFS에서 데이터를 읽을 때
실제로 데이터를 처리하는 곳이 DataNode입니다.

**왜 1개인가요?**
원래 프로덕션 환경에서는 데이터 안전을 위해 3개 이상을 쓰지만, 개발/테스트 환경에서는
1개로도 충분합니다. hdfs-site.xml에서 replication을 1로 설정해서 DataNode가 1개여도
정상 동작하도록 맞춰져 있습니다.

---

### 4.3 nifi (Apache NiFi)

**한 줄 설명**: Kafka에서 메시지를 읽어 HDFS에 저장하는 데이터 파이프라인 도구입니다.

**NiFi가 뭔가요?**
데이터를 A에서 B로 옮기는 작업을 시각적으로 구성할 수 있는 도구입니다.
코드 없이 웹 UI에서 블록을 연결하는 방식으로 데이터 파이프라인을 만들 수 있습니다.

**이 플랫폼에서의 역할**
```
Kafka (ais/asm/vde/vsi 토픽)
        ↓  [ConsumeKafkaRecord]  메시지 읽기
       NiFi
        ↓  [PutHDFS]             HDFS에 저장
HDFS (/data/raw/ais 등)
```

**왜 Kafka에서 HDFS로 직접 연결하지 않나요?**
NiFi는 실패 시 자동 재시도, 처리 현황 모니터링, 오류 메시지 격리 등의 기능을 제공합니다.
직접 연결하면 이런 안정성 기능을 직접 구현해야 합니다.

```yaml
ports:
  - "8443:8443"   # HTTPS 웹 UI
```

**접속**: https://localhost:8443/nifi (ID: admin / PW: adminpassword123!)
> 플로우 구성 방법은 nifi/README.md 참고

---

### 4.4 spark-master (Spark Master)

**한 줄 설명**: Spark 잡(작업)을 어느 Worker에서 실행할지 결정하는 관리자입니다.

**Spark가 뭔가요?**
대용량 데이터를 빠르게 처리하는 분산 처리 엔진입니다.
HDFS에 쌓인 수억 건의 AIS 메시지를 분석하거나, Kafka에서 실시간으로 들어오는
메시지를 처리하는 데 사용합니다.

**Standalone 모드란?**
Spark가 자체적으로 리소스를 관리하는 방식입니다. Master가 Worker들을 직접 관리하며,
별도의 YARN 같은 리소스 관리자 없이 동작합니다. 설정이 단순해서 개발환경에 적합합니다.

```yaml
ports:
  - "8090:8090"   # Spark Web UI - 실행 중인 잡, Worker 상태 확인
  - "7077:7077"   # spark-submit 할 때 연결하는 주소
```

**접속**: http://localhost:8090 에서 Worker 상태, 실행 중인 잡을 확인할 수 있습니다.

---

### 4.5 spark-worker-1 (Batch Layer Worker)

**한 줄 설명**: HDFS에 쌓인 데이터를 주기적으로 처리하는 Batch 전용 실행 환경입니다.

**Batch 처리란?**
데이터를 실시간으로 처리하지 않고, 일정 주기(예: 매 시간, 매일)마다 쌓인 데이터를
한 번에 처리하는 방식입니다. 실시간보다 느리지만 더 정확한 분석이 가능합니다.

이 Worker에서 실행될 작업 예시:
- HDFS에 저장된 AIS 메시지 전체에 Rule-based 무결성 검사 적용
- XGBoost ML 모델로 위험도 일괄 예측
- 통계 집계 및 Batch View 생성

```yaml
SPARK_WORKER_MEMORY=2G    # 대량 데이터 처리를 위해 메모리 넉넉히
SPARK_WORKER_CORES=2      # 병렬 처리를 위한 코어 수
```

**실행 시 이 Worker만 쓰도록 제한하는 방법:**
```bash
spark-submit --total-executor-cores 2 batch_job.py
```

---

### 4.6 spark-worker-2 (Speed Layer Worker - Streaming 전담)

**한 줄 설명**: Kafka에서 실시간으로 메시지를 읽어 즉시 처리하는 Streaming 전용 실행 환경입니다.

**Structured Streaming이란?**
Spark에서 실시간 데이터 처리를 위한 기능입니다. Kafka 토픽을 마치 무한히 추가되는
테이블처럼 취급하여, 새 메시지가 오면 즉시 처리합니다.

이 Worker에서 실행될 작업 예시:
- Kafka에서 실시간으로 AIS 메시지 수신
- 기본 Rule-based 무결성 검사 즉시 적용
- 이상 징후 실시간 탐지 및 알림

```yaml
SPARK_WORKER_MEMORY=1G    # Streaming은 소량씩 지속 처리 → 1G로 충분
SPARK_WORKER_CORES=2
restart: always           # 중요! Streaming은 항상 살아있어야 해서 자동 재시작
```

**Worker 1과의 실질적 분리 방법:**
```bash
# Batch 잡 (Worker 1의 코어 2개 사용)
spark-submit --total-executor-cores 2 --executor-memory 1G batch_job.py

# Streaming 잡 (Worker 2의 코어 2개 사용)
spark-submit --total-executor-cores 2 --executor-memory 512m streaming_job.py

# 총 코어 4개(워커당 2개씩)를 각각 2개씩 나눠 쓰므로 간섭 없음
```

---

### 4.7 spark-history (Spark History Server)

**한 줄 설명**: 완료된 Spark 잡의 실행 기록을 저장하고 조회하는 서버입니다.

**왜 필요한가요?**
Spark 잡이 완료되면 기본적으로 Web UI에서 사라집니다. History Server는 완료된 잡의
실행 시간, 처리한 데이터량, 오류 내용 등을 HDFS에 저장해두고 나중에 조회할 수 있게 합니다.

```yaml
ports:
  - "18080:18080"   # History Server Web UI
```

**접속**: http://localhost:18080 에서 과거 잡 실행 이력을 확인할 수 있습니다.

---

## 5. 설정 파일 상세 설명

### 5.1 .env

Kafka 서버 주소를 관리합니다. Kafka가 어디에 있느냐에 따라 수정하세요.

```env
# Kafka가 현재 PC(호스트 머신)에 설치된 경우 → 수정 불필요
KAFKA_HOST=host.docker.internal
KAFKA_PORT=9092

# Kafka가 별도 서버에 있는 경우
KAFKA_HOST=192.168.1.100   ← 서버 IP로 변경
KAFKA_PORT=9092
```

---

### 5.2 hadoop/config/core-site.xml

Hadoop 전체에 적용되는 기본 설정입니다.

| 설정 키 | 값 | 설명 |
|---|---|---|
| fs.defaultFS | hdfs://namenode:9000 | HDFS 기본 주소. NiFi, Spark가 이 주소로 접근 |
| io.file.buffer.size | 131072 | 파일 읽기/쓰기 버퍼 크기 (128KB). AIS 대량 처리 최적화 |

---

### 5.3 hadoop/config/hdfs-site.xml

HDFS 세부 설정입니다.

| 설정 키 | 값 | 설명 |
|---|---|---|
| dfs.replication | 1 | 복제본 수. 개발환경이므로 1개 (프로덕션은 3) |
| dfs.blocksize | 134217728 | 블록 크기 128MB. 대용량 로그 파일 처리에 최적화 |
| dfs.permissions.enabled | false | 권한 체크 비활성화. 개발환경 편의를 위한 설정 |
| dfs.webhdfs.enabled | true | WebHDFS 활성화. NiFi가 HTTP로 HDFS에 접근하기 위해 필요 |

---

### 5.4 spark/spark-defaults.conf

모든 Spark 잡에 기본 적용되는 설정입니다. spark-submit 실행 시 옵션으로 재정의 가능합니다.

| 설정 키 | 값 | 설명 |
|---|---|---|
| spark.master | spark://spark-master:7077 | Standalone Master 주소 |
| spark.hadoop.fs.defaultFS | hdfs://namenode:9000 | HDFS 주소. 잡에서 hdfs:// 경로 사용 가능 |
| spark.eventLog.enabled | true | 잡 실행 기록 저장 여부 |
| spark.eventLog.dir | hdfs://...spark-logs | 잡 기록 저장 위치 (History Server가 읽음) |
| spark.sql.streaming.checkpointLocation | hdfs://...spark-checkpoints | Streaming 잡 체크포인트 위치. 재시작 시 이어서 처리 |
| spark.sql.shuffle.partitions | 10 | 셔플 파티션 수. 개발환경에서는 작게 설정 |

---

## 6. 사전 준비

### 필수 확인 사항

```bash
# Docker 설치 확인
docker --version

# Docker Compose 설치 확인
docker compose version
```

### Kafka 주소 확인

.env 파일에서 Kafka 서버 주소를 확인하고 필요 시 수정하세요.

---

## 7. 실행 방법

### Step 1. 프로젝트 폴더로 이동

```bash
cd vdes-platform
```

### Step 2. 전체 서비스 시작

```bash
docker compose up -d
```

`-d` 옵션은 백그라운드로 실행한다는 의미입니다.
처음 실행 시 이미지 다운로드로 5~15분 소요될 수 있습니다.

### Step 3. 컨테이너 상태 확인

```bash
docker compose ps
```

모든 서비스가 아래처럼 표시될 때까지 기다리세요. (1~2분 소요)

```
NAME             STATUS
namenode         running (healthy)
datanode         running
nifi             running (healthy)
spark-master     running (healthy)
spark-worker-1   running
spark-worker-2   running
spark-history    running
```

> NiFi는 초기 기동에 1~2분이 걸립니다. healthy가 될 때까지 기다리세요.

### Step 4. HDFS 디렉토리 초기화 (최초 1회만)

```bash
bash init-hdfs.sh
```

이 스크립트는 HDFS 안에 아래 폴더 구조를 만듭니다.
```
/data/raw/ais          ← AIS 원시 메시지 저장
/data/raw/asm          ← ASM 원시 메시지 저장
/data/raw/vde          ← VDE 원시 메시지 저장
/data/raw/vsi          ← VSI 원시 메시지 저장
/data/batch-view       ← Batch 처리 결과 저장
/data/ml-dataset       ← ML 학습 데이터셋 저장
/spark-logs            ← Spark 잡 실행 기록
/spark-checkpoints     ← Streaming 체크포인트
```

### Step 5. NiFi 플로우 설정

https://localhost:8443/nifi 에 접속하여 Kafka → HDFS 플로우를 구성합니다.
자세한 방법은 `nifi/README.md` 를 참고하세요.

---

## 8. 서비스 접속 주소

| 서비스 | 주소 | 설명 |
|---|---|---|
| HDFS NameNode UI | http://localhost:9870 | HDFS 파일 목록, 용량, DataNode 상태 |
| Spark Master UI | http://localhost:8090 | Worker 상태, 실행 중인 잡 목록 |
| Spark Worker 1 UI | http://localhost:8091 | Batch Worker 상세 상태 |
| Spark Worker 2 UI | http://localhost:8092 | Streaming Worker 상세 상태 |
| Spark History UI | http://localhost:18080 | 완료된 잡 실행 이력 |
| NiFi UI | https://localhost:8443/nifi | Kafka→HDFS 파이프라인 관리 |

> NiFi 로그인: ID `admin` / PW `adminpassword123!` (최초 접속 후 변경 권장)

---

## 9. Spark 잡 실행 방법

### Batch 잡 실행

```bash
docker exec spark-master /opt/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  --total-executor-cores 2 \
  --executor-memory 1G \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  /path/to/batch_job.py
```

### Streaming 잡 실행

```bash
docker exec spark-master /opt/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  --total-executor-cores 2 \
  --executor-memory 512m \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  /path/to/streaming_job.py
```

> `--total-executor-cores 2` 로 각 잡이 코어 2개씩만 사용하게 제한하면
> Batch와 Streaming이 동시에 실행되어도 서로 간섭하지 않습니다.
> (Worker 1: 코어 2개, Worker 2: 코어 2개 → 총 4코어를 2+2로 분리)

### 잡 코드에서 Kafka 연결하는 방법

```python
# Streaming 잡 예시
df = spark.readStream.format("kafka") \
    .option("kafka.bootstrap.servers", "host.docker.internal:9092") \
    .option("subscribe", "ais,asm,vde,vsi") \
    .load()

# Batch 잡 예시
df = spark.read.format("kafka") \
    .option("kafka.bootstrap.servers", "host.docker.internal:9092") \
    .option("subscribe", "ais") \
    .option("startingOffsets", "earliest") \
    .load()
```

---

## 10. 자주 쓰는 명령어

### 서비스 관리

```bash
# 전체 시작
docker compose up -d

# 전체 중지 (데이터 유지)
docker compose stop

# 중지 후 재시작
docker compose start

# 전체 삭제 (컨테이너만 삭제, data/ 폴더는 유지)
docker compose down

# 특정 컨테이너만 재시작
docker compose restart spark-worker-2
```

### 로그 확인

```bash
# 특정 컨테이너 로그 보기
docker logs namenode
docker logs nifi
docker logs spark-master

# 실시간 로그 따라가기 (Ctrl+C로 종료)
docker logs -f spark-worker-2
```

### HDFS 파일 관리

```bash
# HDFS 전체 파일 목록
docker exec namenode hdfs dfs -ls -R /

# 특정 경로 파일 목록
docker exec namenode hdfs dfs -ls /data/raw/ais

# HDFS 용량 확인
docker exec namenode hdfs dfs -du -h /data
```

---

## 11. 문제 해결

### NameNode가 healthy가 되지 않을 때

```bash
docker logs namenode
```

포맷이 필요한 경우:
```bash
docker exec namenode hdfs namenode -format -force
docker compose restart namenode
```

### NiFi 접속이 안 될 때

NiFi는 초기 기동에 1~2분이 걸립니다. 로그로 확인하세요.
```bash
docker logs nifi --tail 50
```

### Spark 잡이 실행되지 않을 때

HDFS에 spark-logs 폴더가 없으면 History Server가 오류를 냅니다.
init-hdfs.sh를 실행했는지 확인하세요.
```bash
bash init-hdfs.sh
```

### data/ 폴더 권한 오류 (Linux/Mac 환경)

```bash
chmod -R 777 ./data
```

### 전체 초기화 (데이터 포함 완전 삭제)

```bash
docker compose down
rm -rf ./data
docker compose up -d
bash init-hdfs.sh
```
