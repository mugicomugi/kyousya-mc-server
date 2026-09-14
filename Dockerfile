# syntax=docker/dockerfile:1.7

#############################################
# Stage 1: Fabric installer
#   Fabric公式インストーラーでバニラサーバーの
#   ダウンロードとFabric Loaderの適用を行う
#############################################
FROM eclipse-temurin:25-jdk-alpine AS installer

ARG MC_VERSION=26.2
ARG LOADER_VERSION=0.19.5
ARG INSTALLER_VERSION=1.1.2

RUN apk add --no-cache curl

WORKDIR /install

RUN mkdir -p /opt/minecraft \
    && curl -fsSL -o fabric-installer.jar \
      "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${INSTALLER_VERSION}/fabric-installer-${INSTALLER_VERSION}.jar" \
    && java -jar fabric-installer.jar server \
         -mcversion "${MC_VERSION}" \
         -loader "${LOADER_VERSION}" \
         -downloadMinecraft \
         -dir /opt/minecraft \
    && rm fabric-installer.jar

#############################################
# Stage 2: 実行用ランタイムイメージ
#############################################
FROM eclipse-temurin:25-jre-alpine AS runtime

ARG MC_VERSION=26.2
ARG LOADER_VERSION=0.19.5

LABEL org.opencontainers.image.title="kyousya-mc-server" \
      org.opencontainers.image.description="Fabric Minecraft server (MC ${MC_VERSION}, Fabric Loader ${LOADER_VERSION})" \
      minecraft.version="${MC_VERSION}" \
      fabric.loader.version="${LOADER_VERSION}"

ENV MC_VERSION=${MC_VERSION} \
    FABRIC_LOADER_VERSION=${LOADER_VERSION} \
    SERVER_DIR=/opt/minecraft \
    DATA_DIR=/data

RUN apk add --no-cache bash \
    && addgroup -g 1000 minecraft \
    && adduser -D -u 1000 -G minecraft -h /data -s /bin/bash minecraft

COPY --from=installer --chown=minecraft:minecraft /opt/minecraft /opt/minecraft
COPY --chown=minecraft:minecraft docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/data"]
WORKDIR /opt/minecraft
EXPOSE 25565/tcp 25575/tcp

USER minecraft

HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=5 \
  CMD bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/25565' || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
