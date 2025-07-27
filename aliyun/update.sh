#!/bin/bash

# Mall项目应用更新脚本
# 使用方法: ./update.sh [--service SERVICE] [--version VERSION] [--backup]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
SERVICE="all"
VERSION="1.0-SNAPSHOT"
BACKUP_BEFORE_UPDATE=false
ENV_FILE=".env"
DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$DEPLOY_DIR/../.." && pwd)"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
Mall项目应用更新脚本

使用方法:
    $0 [选项]

选项:
    --service SERVICE   指定要更新的服务: all, mall-admin, mall-portal, mall-search (默认: all)
    --version VERSION   指定镜像版本 (默认: 1.0-SNAPSHOT)
    --backup           更新前自动备份数据
    --help, -h         显示此帮助信息

示例:
    $0                                    # 更新所有服务
    $0 --service mall-admin               # 仅更新后台管理系统
    $0 --version 1.1-SNAPSHOT --backup   # 更新到指定版本并备份

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --service)
                SERVICE="$2"
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --backup)
                BACKUP_BEFORE_UPDATE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查环境
check_environment() {
    log_info "检查更新环境..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装"
        exit 1
    fi
    
    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose未安装"
        exit 1
    fi
    
    # 检查环境变量文件
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    else
        log_warning "环境变量文件不存在，使用默认配置"
    fi
    
    log_success "环境检查完成"
}

# 执行备份
perform_backup() {
    if [ "$BACKUP_BEFORE_UPDATE" = true ]; then
        log_info "执行更新前备份..."
        
        if [ -f "./backup.sh" ]; then
            chmod +x ./backup.sh
            ./backup.sh --type all
        else
            log_warning "备份脚本不存在，跳过备份"
        fi
    fi
}

# 检查服务健康状态
check_service_health() {
    local service_name=$1
    local max_attempts=30
    local attempt=1
    
    log_info "检查 $service_name 服务健康状态..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps | grep -q "$service_name.*Up"; then
            # 检查健康检查状态
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$service_name" 2>/dev/null || echo "unknown")
            
            if [ "$health_status" = "healthy" ] || [ "$health_status" = "unknown" ]; then
                log_success "$service_name 服务健康检查通过"
                return 0
            fi
        fi
        
        log_info "等待 $service_name 服务健康... ($attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    log_error "$service_name 服务健康检查失败"
    return 1
}

# 构建新镜像
build_new_image() {
    local service=$1
    
    log_info "构建 $service 新镜像..."
    
    cd "$PROJECT_ROOT"
    
    # 进入服务目录
    cd "$service"
    
    # 编译项目
    log_info "编译 $service 项目..."
    mvn clean package -DskipTests -q
    
    if [ $? -ne 0 ]; then
        log_error "$service 编译失败"
        return 1
    fi
    
    # 构建Docker镜像
    log_info "构建 $service Docker镜像..."
    
    # 创建临时Dockerfile
    cat > Dockerfile << EOF
FROM openjdk:8-jre-alpine

# 设置时区
RUN apk add --no-cache tzdata && \\
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \\
    echo "Asia/Shanghai" > /etc/timezone

# 创建应用目录
WORKDIR /app

# 复制jar包
COPY target/$service-$VERSION.jar app.jar

# 设置JVM参数
ENV JAVA_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC"

# 创建日志目录
RUN mkdir -p /app/logs

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \\
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# 启动应用
ENTRYPOINT ["sh", "-c", "java \$JAVA_OPTS -Djava.security.egd=file:/dev/./urandom -jar app.jar"]
EOF
    
    # 构建镜像
    docker build -t "mall/$service:$VERSION" .
    
    if [ $? -eq 0 ]; then
        log_success "$service 镜像构建成功"
        # 清理临时文件
        rm -f Dockerfile
        cd "$DEPLOY_DIR"
        return 0
    else
        log_error "$service 镜像构建失败"
        rm -f Dockerfile
        cd "$DEPLOY_DIR"
        return 1
    fi
}

# 滚动更新服务
rolling_update_service() {
    local service=$1
    
    log_info "开始滚动更新 $service 服务..."
    
    # 构建新镜像
    if ! build_new_image "$service"; then
        log_error "$service 镜像构建失败，取消更新"
        return 1
    fi
    
    # 获取当前容器ID
    local old_container=$(docker ps -q --filter "name=$service")
    
    if [ -z "$old_container" ]; then
        log_warning "$service 服务未运行，直接启动新版本"
        docker-compose --env-file="$ENV_FILE" -f docker-compose-apps.yml up -d "$service"
        return $?
    fi
    
    # 启动新容器
    log_info "启动 $service 新版本容器..."
    docker-compose --env-file="$ENV_FILE" -f docker-compose-apps.yml up -d "$service"
    
    # 等待新容器启动
    sleep 30
    
    # 检查新容器健康状态
    if check_service_health "$service"; then
        log_success "$service 服务更新成功"
        
        # 清理旧镜像（保留最近3个版本）
        cleanup_old_images "$service"
        
        return 0
    else
        log_error "$service 新版本启动失败，准备回滚..."
        
        # 回滚到旧版本
        rollback_service "$service" "$old_container"
        return 1
    fi
}

# 回滚服务
rollback_service() {
    local service=$1
    local old_container=$2
    
    log_warning "回滚 $service 服务到之前版本..."
    
    # 停止新容器
    docker stop "$service" 2>/dev/null || true
    docker rm "$service" 2>/dev/null || true
    
    # 启动旧容器
    if [ -n "$old_container" ]; then
        docker start "$old_container"
        
        if check_service_health "$service"; then
            log_success "$service 服务回滚成功"
        else
            log_error "$service 服务回滚失败"
        fi
    else
        log_error "无法回滚 $service 服务，旧容器不存在"
    fi
}

# 清理旧镜像
cleanup_old_images() {
    local service=$1
    
    log_info "清理 $service 旧镜像..."
    
    # 获取所有该服务的镜像，按创建时间排序，保留最新的3个
    local images_to_delete=$(docker images "mall/$service" --format "table {{.Repository}}:{{.Tag}}\t{{.CreatedAt}}" | 
                           tail -n +2 | 
                           sort -k2 -r | 
                           tail -n +4 | 
                           awk '{print $1}')
    
    if [ -n "$images_to_delete" ]; then
        echo "$images_to_delete" | while read -r image; do
            log_info "删除旧镜像: $image"
            docker rmi "$image" 2>/dev/null || true
        done
    else
        log_info "没有需要清理的旧镜像"
    fi
}

# 更新所有服务
update_all_services() {
    local services=("mall-admin" "mall-portal" "mall-search")
    local failed_services=()
    
    for service in "${services[@]}"; do
        log_info "更新服务: $service"
        
        if ! rolling_update_service "$service"; then
            failed_services+=("$service")
            log_error "$service 更新失败"
        else
            log_success "$service 更新成功"
        fi
        
        # 服务间更新间隔
        sleep 10
    done
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        log_success "所有服务更新完成"
        return 0
    else
        log_error "以下服务更新失败: ${failed_services[*]}"
        return 1
    fi
}

# 显示更新后的状态
show_update_status() {
    log_info "=== 更新后服务状态 ==="
    
    echo
    log_info "容器状态:"
    docker-compose --env-file="$ENV_FILE" -f docker-compose-apps.yml ps
    
    echo
    log_info "镜像信息:"
    docker images | grep "mall/"
    
    echo
    log_info "服务健康检查:"
    for service in mall-admin mall-portal mall-search; do
        if docker ps | grep -q "$service.*Up"; then
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "unknown")
            echo "  $service: $health"
        else
            echo "  $service: stopped"
        fi
    done
}

# 主函数
main() {
    local start_time=$(date +%s)
    
    log_info "开始执行Mall项目应用更新..."
    
    # 解析参数
    parse_args "$@"
    
    # 进入部署目录
    cd "$DEPLOY_DIR"
    
    # 检查环境
    check_environment
    
    # 执行备份
    perform_backup
    
    # 根据指定服务执行更新
    local update_success=true
    
    case $SERVICE in
        "all")
            update_all_services || update_success=false
            ;;
        "mall-admin"|"mall-portal"|"mall-search")
            rolling_update_service "$SERVICE" || update_success=false
            ;;
        *)
            log_error "不支持的服务: $SERVICE"
            log_info "支持的服务: all, mall-admin, mall-portal, mall-search"
            exit 1
            ;;
    esac
    
    # 显示更新状态
    show_update_status
    
    # 计算耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$update_success" = true ]; then
        log_success "更新完成！耗时: ${duration}秒"
    else
        log_error "更新过程中出现错误！"
        exit 1
    fi
}

# 捕获中断信号
trap 'log_error "更新被中断"; exit 1' INT TERM

# 执行主函数
main "$@"