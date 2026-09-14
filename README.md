# kyousya-mc-server

Fabric Minecraft サーバーを Docker で構築するプロジェクトです。OCI (Oracle Cloud
Infrastructure) の Compute インスタンス上での稼働を想定しています。

- Minecraft: `26.2`
- Fabric Loader: `0.19.5` (Fabric Installer `1.1.2`)
- Java: 25 (`eclipse-temurin:25-jre-alpine`)
- 対応アーキテクチャ: amd64 / arm64 (本ホストは aarch64)

`docker/` にあるインストーラーステージで Fabric 公式インストーラーを実行し、
サーバー本体・ライブラリをイメージに焼き込みます。ワールドデータや mods、
サーバー設定は `./data` (Docker volume ではなくホストのディレクトリ) に永続化され、
コンテナ内では `docker/entrypoint.sh` がシンボリックリンクで結び付けます。

## ディレクトリ構成

```
.
├── Dockerfile              # マルチステージビルド (installer -> runtime)
├── docker/entrypoint.sh    # 起動時セットアップ + java起動
├── docker-compose.yml
├── .env.example             # コピーして .env として使用
├── .gitignore
└── data/                    # 実行時に作成される永続化ディレクトリ (git管理外)
    ├── world/
    ├── mods/
    ├── config/
    ├── logs/
    ├── server.properties
    ├── eula.txt
    ├── ops.json / whitelist.json / banned-*.json / usercache.json
```

## 前提条件

- Docker Engine + Docker Compose plugin (`docker compose` コマンド)
- OCI インスタンスの **Security List または Network Security Group (NSG)** で
  `25565/TCP` を Ingress 許可していること (OCIコンソール/CLI側の作業。本リポジトリの
  設定だけでは外部到達不可)
- ホストOS側ファイアウォール (iptables/nftables/ufw) で `25565/TCP` を許可していること

## セットアップ手順

```bash
# 1. .env を作成し、必要な値を編集する
cp .env.example .env
vi .env   # EULA=TRUE にする(Mojang EULA https://www.minecraft.net/eula に同意する場合のみ)、
          # RCON_PASSWORD、MOTD、MAX_PLAYERS などを必要に応じて変更

# 2. データ用ディレクトリを作成し、コンテナ内ユーザー(uid/gid=1000)に所有権を合わせる
mkdir -p data
sudo chown -R 1000:1000 data

# 3. イメージをビルド
docker compose build

# 4. 起動
docker compose up -d

# 5. ログ確認 ("Done" が出れば起動完了)
docker compose logs -f
```

## 運用

### コンソールへの接続

```bash
docker attach kyousya-mc-fabric
# デタッチは Ctrl+P, Ctrl+Q (Ctrl+C はサーバーを止めてしまうので使わない)
```

### 停止・再起動

```bash
docker compose stop      # save-all + 正常停止 (stop_grace_period=90s)
docker compose restart
```

### アップデート (Minecraft / Fabric Loaderのバージョン変更)

`.env` の `MC_VERSION` / `LOADER_VERSION` / `INSTALLER_VERSION` を変更してから:

```bash
docker compose build --no-cache
docker compose up -d
```

### Mod の追加

`data/mods/` に Fabric 対応 mod の `.jar` を配置して再起動するだけです。
多くの mod が依存する [Fabric API](https://modrinth.com/mod/fabric-api) は、
サーバーに合わせたバージョン (Minecraft 26.2 用) をダウンロードして同じく
`data/mods/` に置いてください。

### バックアップ

`data/world/` をコピーするだけでバックアップになります(サーバー稼働中にバックアップ
する場合は、コンソールで `save-off` → `save-all` → コピー → `save-on` の順に実行してください)。

```bash
docker compose exec fabric-server true  # コンテナが起動していることを確認
tar czf "backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C data world
```

## 設定変数 (`.env`)

| 変数 | 既定値 | 説明 |
|---|---|---|
| `MC_VERSION` | `26.2` | Minecraft バージョン (ビルド時のみ反映) |
| `LOADER_VERSION` | `0.19.5` | Fabric Loader バージョン |
| `INSTALLER_VERSION` | `1.1.2` | Fabric Installer バージョン |
| `EULA` | `FALSE` | `TRUE` にしない限りサーバーは起動しない |
| `SERVER_PORT` | `25565` | ホスト側の公開ポート |
| `MOTD` / `DIFFICULTY` / `GAMEMODE` / `MAX_PLAYERS` / `ONLINE_MODE` / `PVP` / `VIEW_DISTANCE` / `SIMULATION_DISTANCE` / `WHITELIST` / `LEVEL_SEED` | - | `server.properties` の初期値。**`data/server.properties` が既に存在する場合は上書きされません** |
| `ENABLE_RCON` / `RCON_PASSWORD` / `RCON_PORT` | `false` / - / `25575` | RCON管理。有効化する場合は強力なパスワードを設定し、`docker-compose.yml` のRCONポート公開はデフォルトで`127.0.0.1`バインドかつコメントアウトのままにする(外部公開しない)ことを推奨 |
| `MEMORY_MIN` / `MEMORY_MAX` | `2G` / `6G` | JVMヒープ。本ホスト(RAM 11GiB)ではOS/Dockerオーバーヘッド分を差し引いた値 |
| `JAVA_OPTS` | (空) | 追加のJVMオプション |

## OCI 側で必要な設定 (本リポジトリの範囲外)

以下は OCI コンソール / CLI 側での作業が必要です(このセットアップだけでは完結しません):

1. インスタンスが所属する **VCN の Security List** または **NSG** に、
   Ingress ルール `TCP 25565` (ソース: `0.0.0.0/0` または許可したいIP範囲) を追加する。
2. RCONを使う場合でも `25575` は外部に公開しないことを推奨(公開する場合のみ同様に許可)。

## トラブルシューティング

- `EULA has not been accepted` と出て起動しない → `.env` の `EULA=TRUE` を確認し
  `docker compose up -d` し直す。
- コンテナは起動しているが外部から繋がらない → OCI Security List/NSG とホストの
  iptables/nftables の両方で `25565/tcp` が許可されているか確認する
  (`sudo iptables -L INPUT -n --line-numbers` で `REJECT` より前に `ACCEPT` があるか確認)。
- `data is not writable` エラー → `sudo chown -R 1000:1000 data` を実行する。
