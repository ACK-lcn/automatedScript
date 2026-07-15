#!/usr/bin/env bash

set -euo pipefail

# 全局变量与日志
readonly SCRIPT_NAME="$(basename "$0")"
readonly DOCKER_DATA_ROOT="/data/docker"        # 生产环境建议独立数据盘，可按需修改
readonly DAEMON_JSON="/etc/docker/daemon.json"
readonly LOG_MAX_SIZE="100m"
readonly LOG_MAX_FILE="3"

log()  { printf '\033[0;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[0;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }


# 1 前期检查与准备
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "请使用 root 用户或 sudo 运行本脚本。"v
    fi
}

detect_os() {
    [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release，不支持的系统。"
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-}"
    OS_VERSION="${VERSION_ID:-}"
    OS_LIKE="${ID_LIKE:-}"

    case "${OS_ID}" in
        ubuntu|debian)
            PKG_FAMILY="debian"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            PKG_FAMILY="rhel"
            ;;
        *)
            if [[ "${OS_LIKE}" == *"debian"* ]]; then
                PKG_FAMILY="debian"
            elif [[ "${OS_LIKE}" == *"rhel"* || "${OS_LIKE}" == *"fedora"* ]]; then
                PKG_FAMILY="rhel"
            else
                die "不支持的操作系统：${OS_ID} ${OS_VERSION}"
            fi
            ;;
    esac
    log "检测到系统：${PRETTY_NAME:-${OS_ID} ${OS_VERSION}}（软件包族：${PKG_FAMILY}）"
}

check_arch() {
    local arch
    arch="$(uname -m)"
    case "${arch}" in
        x86_64|aarch64) log "CPU 架构：${arch}" ;;
        *) die "不支持的 CPU 架构：${arch}" ;;
    esac
}

check_network() {
    log "检查网络连通性..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 10 -o /dev/null https://download.docker.com/ \
            && log "网络连通正常。" \
            || warn "无法访问 download.docker.com，若在国内建议切换为镜像源后重试。"
    else
        warn "未安装 curl，跳过网络检查。"
    fi
}

check_existing_docker() {
    if command -v docker >/dev/null 2>&1; then
        local ver
        ver="$(docker --version 2>/dev/null || echo unknown)"
        warn "检测到已安装 Docker：${ver}"
        warn "脚本将继续，但不会覆盖已运行的容器数据；daemon.json 会在覆盖前自动备份。"
    fi
}

# 2 安装 Docker 与 docker compose
install_debian() {
    log "使用 apt 安装 Docker CE..."
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y
    apt-get install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    local codename
    codename="${VERSION_CODENAME:-$(. /etc/os-release && echo "${VERSION_CODENAME}")}"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} ${codename} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
}

install_rhel() {
    log "使用 yum/dnf 安装 Docker CE..."
    local pm="yum"
    command -v dnf >/dev/null 2>&1 && pm="dnf"

    ${pm} install -y yum-utils

    # RHEL 系用 centos 仓库通常兼容；fedora 单独处理
    local repo_os="centos"
    [[ "${OS_ID}" == "fedora" ]] && repo_os="fedora"

    yum-config-manager --add-repo \
        "https://download.docker.com/linux/${repo_os}/docker-ce.repo"

    ${pm} install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
}

install_docker() {
    case "${PKG_FAMILY}" in
        debian) install_debian ;;
        rhel)   install_rhel ;;
    esac
}

# 兼容旧写法 docker-compose（带横杠）：创建 wrapper 指向 Compose v2 插件
setup_compose_shim() {
    local shim="/usr/local/bin/docker-compose"
    # 若系统已存在真实的 docker-compose 二进制（非本脚本创建），不覆盖
    if command -v docker-compose >/dev/null 2>&1 && [[ ! -e "${shim}" ]]; then
        warn "检测到已存在的 docker-compose，跳过兼容命令创建。"
        return
    fi
    log "创建 docker-compose 兼容命令 -> docker compose ..."
    cat > "${shim}" <<'EOF'
#!/bin/sh
# 兼容旧版 docker-compose 命令，实际调用 Docker Compose v2 插件
exec docker compose "$@"
EOF
    chmod +x "${shim}"
}

# 3 生成生产专用 daemon.json
write_daemon_json() {
    log "生成生产环境 ${DAEMON_JSON} ..."
    mkdir -p /etc/docker

    if [[ -f "${DAEMON_JSON}" ]]; then
        local backup="${DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "${DAEMON_JSON}" "${backup}"
        warn "已存在 daemon.json，已备份到 ${backup}"
    fi

    cat > "${DAEMON_JSON}" <<EOF
{
  "data-root": "${DOCKER_DATA_ROOT}",
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "${LOG_MAX_SIZE}",
    "max-file": "${LOG_MAX_FILE}"
  },
  "live-restore": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  },
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": []
}
EOF

    log "daemon.json 写入完成。数据目录：${DOCKER_DATA_ROOT}"
    mkdir -p "${DOCKER_DATA_ROOT}"
}

# 4 启动与校验
enable_and_start() {
    log "启用并启动 Docker 服务..."
    # containerd 显式设为开机自启，避免个别系统重启后未被拉起
    systemctl enable containerd >/dev/null 2>&1 || true
    systemctl enable docker >/dev/null 2>&1 || true
    # 已运行则 reload 配置，否则启动
    if systemctl is-active --quiet docker; then
        systemctl restart docker
    else
        systemctl start docker
    fi
}

verify() {
    log "校验安装结果..."
    docker version --format '  Client: {{.Client.Version}} / Server: {{.Server.Version}}' \
        || die "Docker 服务未正常运行，请检查 journalctl -u docker。"

    if docker compose version >/dev/null 2>&1; then
        log "docker compose (v2 插件): $(docker compose version --short)"
    else
        warn "docker compose 插件不可用，请检查安装。"
    fi

    # 校验带横杠的兼容命令
    if docker-compose version >/dev/null 2>&1; then
        log "docker-compose (兼容命令): 可用"
    else
        warn "docker-compose 兼容命令不可用，请检查 /usr/local/bin/docker-compose。"
    fi

    log "运行 hello-world 测试（可选）..."
    docker run --rm hello-world >/dev/null 2>&1 \
        && log "hello-world 测试通过。" \
        || warn "hello-world 测试失败，可能是网络原因，不影响本地使用。"
}

post_hint() {
    cat <<'EOF'

============================================================
Docker 部署完成。

后续可选操作（脚本未自动执行，避免改动云主机配置）：
  1. 将普通用户加入 docker 组（免 sudo）：
       usermod -aG docker <用户名> && 重新登录生效
  2. 如需配置镜像加速，编辑 /etc/docker/daemon.json 的
     "registry-mirrors" 字段后执行：
       systemctl restart docker
  3. 数据目录默认为 /data/docker，如需修改请编辑脚本
     DOCKER_DATA_ROOT 变量或 daemon.json 后重启服务。
============================================================
EOF
}

# 主流程
main() {
    log "===== ${SCRIPT_NAME} 开始 ====="
    # 1) 检查准备
    check_root
    detect_os
    check_arch
    check_network
    check_existing_docker
    # 2) 安装
    install_docker
    setup_compose_shim
    # 3) 生产配置
    write_daemon_json
    # 启动校验
    enable_and_start
    verify
    post_hint
    log "===== 全部完成 ====="
}

main "$@"
