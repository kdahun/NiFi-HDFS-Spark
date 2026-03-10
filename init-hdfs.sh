#!/bin/bash
# ================================================================
# HDFS 디렉토리 초기화 스크립트
# VDES 빅데이터 플랫폼 - Lambda Architecture
# 실행: bash init-hdfs.sh
# ================================================================

echo ">> Waiting for NameNode to be ready..."
sleep 20

echo ""
echo ">> [1/4] Creating Data Lake directories (raw message 저장)..."
docker exec namenode hdfs dfs -mkdir -p /data/raw/ais
docker exec namenode hdfs dfs -mkdir -p /data/raw/asm
docker exec namenode hdfs dfs -mkdir -p /data/raw/vde
docker exec namenode hdfs dfs -mkdir -p /data/raw/vsi

echo ">> [2/4] Creating Spark directories..."
docker exec namenode hdfs dfs -mkdir -p /spark-logs
docker exec namenode hdfs dfs -mkdir -p /spark-checkpoints

echo ">> [3/4] Creating Batch/ML directories..."
docker exec namenode hdfs dfs -mkdir -p /data/batch-view
docker exec namenode hdfs dfs -mkdir -p /data/ml-dataset

echo ">> [4/4] Setting permissions..."
docker exec namenode hdfs dfs -chmod -R 777 /data
docker exec namenode hdfs dfs -chmod -R 777 /spark-logs
docker exec namenode hdfs dfs -chmod -R 777 /spark-checkpoints

echo ""
echo ">> HDFS directory structure:"
docker exec namenode hdfs dfs -ls -R /

echo ""
echo "================================================================"
echo " Done! HDFS is ready."
echo " NiFi UI: https://localhost:8443/nifi (admin / adminpassword123!)"
echo " Spark UI: http://localhost:8090"
echo " HDFS UI:  http://localhost:9870"
echo "================================================================"
