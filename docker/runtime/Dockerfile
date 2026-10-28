# The RSKj runtime image: a JRE, jattach, the JMX exporter and the entrypoint RSKj's own
# Docker image uses, without an RSKj build. The lab mounts the jar under test at
# /usr/local/lib/rsk/rsk.jar (bin/live-arm.sh, bin/replay-docker.sh, bin/seed.sh).
#   docker build -f docker/runtime/Dockerfile -t clientslab-runtime:1 docker/runtime
FROM alpine:3.20 AS tools
ARG TARGETARCH
RUN wget -qO- "https://github.com/jattach/jattach/releases/download/v2.2/jattach-linux-$( [ "$TARGETARCH" = amd64 ] && echo x64 || echo arm64 ).tgz" | tar -xz -C / && chmod +x /jattach

FROM eclipse-temurin:17-jre@sha256:38e0afc86a10bf4cadbf1586fb617b3a9a4d09c9a0be882e29ada4ed0895fc84
LABEL org.opencontainers.image.authors="ops@rootstocklabs.com"

# Copy jattach from build stage
COPY --from=tools /jattach /usr/local/bin/jattach

RUN useradd -ms /sbin/nologin -d /var/lib/rsk rsk

# Use a separate directory for JMX to avoid volume mount overrides
RUN mkdir -p /usr/local/lib/rsk && chown rsk:rsk /usr/local/lib/rsk

USER rsk
WORKDIR /var/lib/rsk
# Keep rsk.jar OUTSIDE the /var/lib/rsk volume mount so a rebuilt image always
# ships a fresh jar. If it lived under /var/lib/rsk, the named data volume would
# shadow it with a stale copy and code changes would silently not take effect.

WORKDIR /usr/local/lib/rsk
COPY --chown=rsk:rsk jmx_prometheus_javaagent.jar ./
COPY --chown=rsk:rsk jmx_exporter_config.yaml ./

WORKDIR /var/lib/rsk

ENV ENABLE_JMX="false"
ENV JMX_PORT="9010"
ENV JMX_HOSTNAME="127.0.0.1"

ENV MINER_ID="1"
ENV IS_MINER="true"
ENV WIRE_DELAY="100"
ENV DEFAULT_JVM_OPTS="-Xms3G"
ENV RSKJ_SYS_PROPS="-Drpc.providers.web.cors=* -Drpc.providers.web.http.port=4444 -Drpc.providers.web.http.enabled=true -Drpc.providers.web.ws.enabled=true -Drpc.providers.web.ws.port=4445 -Ddatabase.dir=./test/local-regtest/database -Dtransaction.accountTxRateLimit.enabled=true -Dlogging.dir=test/local-regtest/ -Dsync.peer.count=20 -Drpc.providers.web.http.bind_address=0.0.0.0"
ENV RSKJ_LOG_PROPS="-Dlogging.stdout=INFO -Dlogging.file=INFO -Dlogging=INFO" 
ENV RSKJ_CLASS=co.rsk.Start
ENV RSKJ_OPTS="--regtest"
ENV BLOCK_GAS_LIMIT="7000000"
ENV GENESIS_FILE=""
# SHARED_BLOCK_CACHE_SIZE is intentionally NOT defaulted: when unset, the
# -Ddatabase.rocksdb.sharedBlockCacheSize flag is omitted entirely so the value
# from rsk.conf (or RSKj's own default) is used. Set it per-node in docker-compose.


ENTRYPOINT ["/bin/sh", "-c", "\
  JMX_OPTS=''; \
  if [ \"${ENABLE_JMX}\" = \"true\" ]; then \
  JMX_OPTS=\"-Dcom.sun.management.jmxremote \
  -Dcom.sun.management.jmxremote.port=${JMX_PORT} \
  -Dcom.sun.management.jmxremote.rmi.port=${JMX_PORT} \
  -Dcom.sun.management.jmxremote.local.only=false \
  -Dcom.sun.management.jmxremote.authenticate=false \
  -Dcom.sun.management.jmxremote.ssl=false \
  -Djava.rmi.server.hostname=${JMX_HOSTNAME}\"; \
  fi; \
  MINER_OPTS=''; \
  if [ \"${IS_MINER}\" = \"true\" ]; then \
  MINER_OPTS=\"-Dminer.server.enabled=true \
  -Dminer.client.timedMine=true \
  -Dminer.coinbase.secret=miner${MINER_ID} \
  -Dpeer.privateKey=AFF6A83FEFFF6FF0C9F6FFFE41F6FF10D9FFFF3F41FFCFBF41F6FF90DFFFFF9${MINER_ID} \
  -Dpeer.port=5050${MINER_ID} \
  -Dminer.client.medianBlockTime=10s\"; \
  else \
  MINER_OPTS=\"-Dminer.server.enabled=false \
  -Dpeer.privateKey=AFF6A83FEFFF6FF0C9F6FFFE41F6FF10D9FFFF3F41FFCFBF41F6FF90DFFFFF8${MINER_ID} \
  -Dpeer.port=5060${MINER_ID} \
  -Dminer.client.timedMine=false\"; \
  fi; \
  GENESIS_OPT=''; \
  if [ -n \"${GENESIS_FILE}\" ]; then \
  GENESIS_OPT=\"-Dgenesis=${GENESIS_FILE}\"; \
  fi; \
  CACHE_OPT=''; \
  if [ -n \"${SHARED_BLOCK_CACHE_SIZE}\" ]; then \
  CACHE_OPT=\"-Ddatabase.rocksdb.sharedBlockCacheSize=${SHARED_BLOCK_CACHE_SIZE}\"; \
  fi; \
  exec java $DEFAULT_JVM_OPTS \
  -javaagent:/usr/local/lib/rsk/jmx_prometheus_javaagent.jar=8080:/usr/local/lib/rsk/jmx_exporter_config.yaml \
  $RSKJ_SYS_PROPS \
  $MINER_OPTS \
  -Dminer.server.skipPowValidation=true \
  -Dwire.simulatedDelay=${WIRE_DELAY} \
  -DtxLoad.blockTargetGas=${BLOCK_GAS_LIMIT} \
  -DtxLoad.primaryTxGas=${BLOCK_GAS_LIMIT} \
  -Drpc.gasEstimationCap=${BLOCK_GAS_LIMIT} \
  -Dtargetgaslimit=${BLOCK_GAS_LIMIT} \
  $CACHE_OPT \
  -Dsystem.profiling.enabled=true \
  -Dblockchain.flushNumberOfBlocks=${FLUSH_BLOCKS} \
  $GENESIS_OPT \
  $JMX_OPTS \
  $RSKJ_LOG_PROPS \
  -cp /usr/local/lib/rsk/rsk.jar $RSKJ_CLASS $RSKJ_OPTS \"${@}\" \
  ", "--"]

