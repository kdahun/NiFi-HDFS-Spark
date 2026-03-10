# NiFi - Kafka → HDFS 플로우 설정 가이드

## 접속
- URL: https://localhost:8443/nifi
- ID: admin
- PW: adminpassword123! (최초 접속 후 변경 권장)

## Kafka → HDFS 플로우 구성 순서

### 1. ConsumeKafkaRecord 프로세서 추가
Kafka 토픽에서 메시지를 읽어오는 프로세서입니다.

| 속성 | 값 |
|---|---|
| Kafka Brokers | host.docker.internal:9092 |
| Topic Name | ais (asm / vde / vsi 토픽별 반복) |
| Group ID | nifi-vdes-consumer |
| Record Reader | JsonTreeReader |
| Record Writer | JsonRecordSetWriter |

### 2. PutHDFS 프로세서 추가
읽어온 메시지를 HDFS에 저장합니다.

| 속성 | 값 |
|---|---|
| Hadoop Configuration Resources | /opt/nifi/conf/hdfs/core-site.xml |
| Directory | /data/raw/ais (토픽별로 경로 변경) |
| Conflict Resolution | APPEND |

### 3. 연결 (Connection)
ConsumeKafkaRecord → PutHDFS (success 연결)

## 토픽별 디렉토리 매핑
| Kafka 토픽 | HDFS 경로 |
|---|---|
| ais | /data/raw/ais |
| asm | /data/raw/asm |
| vde | /data/raw/vde |
| vsi | /data/raw/vsi |
