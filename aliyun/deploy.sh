#!/bin/bash

# Mall项目阿里云一键部署脚本
# 使用方法: ./deploy.sh [--env ENV_FILE] [--skip-build] [--skip-db-init]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
ENV_FILE=".env"
SKIP_BUILD=false
SKIP_DB_INIT=false
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
Mall项目阿里云部署脚本

使用方法:
    $0 [选项]

选项:
    --env FILE          指定环境变量文件 (默认: .env)
    --skip-build        跳过镜像构建步骤
    --skip-db-init      跳过数据库初始化
    --help, -h          显示此帮助信息

示例:
    $0                          # 完整部署
    $0 --skip-build             # 跳过构建，直接部署
    $0 --env .env.prod          # 使用生产环境配置

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)
                ENV_FILE="$2"
                shift 2
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-db-init)
                SKIP_DB_INIT=true
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
    log_info "检查部署环境..."
    
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
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f ".env.example" ]; then
            log_warning "环境变量文件不存在，从示例文件复制..."
            cp .env.example "$ENV_FILE"
            log_warning "请编辑 $ENV_FILE 文件配置您的环境变量"
            read -p "是否继续部署？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        else
            log_error "环境变量文件 $ENV_FILE 不存在"
            exit 1
        fi
    fi
    
    # 加载环境变量
    source "$ENV_FILE"
    
    log_success "环境检查完成"
}

# 创建必要的目录
create_directories() {
    log_info "创建数据目录..."
    
    local data_path="${DATA_PATH:-/data/mall}"
    
    sudo mkdir -p "$data_path"/{mysql/{data,conf,logs},redis/data,elasticsearch/{data,plugins},rabbitmq/data,mongodb/{data,logs},nginx/{conf,html,ssl},logs/{mall-admin,mall-portal,mall-search,nginx}}
    
    # 设置权限
    sudo chown -R $USER:$USER "$data_path"
    sudo chmod -R 755 "$data_path"
    
    # 设置Elasticsearch目录权限
    sudo chown -R 1000:1000 "$data_path/elasticsearch"
    
    log_success "目录创建完成"
}

# 构建镜像
build_images() {
    if [ "$SKIP_BUILD" = true ]; then
        log_info "跳过镜像构建步骤"
        return
    fi
    
    log_info "开始构建应用镜像..."
    
    cd "$PROJECT_ROOT"
    
    if [ -f "$DEPLOY_DIR/build-images.sh" ]; then
        chmod +x "$DEPLOY_DIR/build-images.sh"
        "$DEPLOY_DIR/build-images.sh"
    else
        log_error "构建脚本不存在"
        exit 1
    fi
    
    cd "$DEPLOY_DIR"
    
    log_success "镜像构建完成"
}

# 启动基础设施服务
start_infrastructure() {
    log_info "启动基础设施服务..."
    
    # 创建网络
    docker network create mall-network 2>/dev/null || true
    
    # 启动基础设施服务
    docker-compose --env-file="$ENV_FILE" -f docker-compose-infrastructure.yml up -d
    
    # 等待服务启动
    log_info "等待基础设施服务启动..."
    sleep 30
    
    # 检查服务状态
    check_service_health "mall-mysql" "MySQL"
    check_service_health "mall-redis" "Redis"
    check_service_health "mall-elasticsearch" "Elasticsearch"
    check_service_health "mall-rabbitmq" "RabbitMQ"
    check_service_health "mall-mongodb" "MongoDB"
    
    log_success "基础设施服务启动完成"
}

# 初始化数据库
init_database() {
    if [ "$SKIP_DB_INIT" = true ]; then
        log_info "跳过数据库初始化"
        return
    fi
    
    log_info "初始化数据库..."
    
    # 等待MySQL完全启动
    sleep 10
    
    # 检查SQL文件是否存在
    local sql_file="$PROJECT_ROOT/document/sql/mall.sql"
    if [ ! -f "$sql_file" ]; then
        log_error "数据库初始化文件不存在: $sql_file"
        exit 1
    fi
    
    # 执行数据库初始化
    docker exec -i mall-mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" < "$sql_file"
    
    if [ $? -eq 0 ]; then
        log_success "数据库初始化完成"
    else
        log_error "数据库初始化失败"
        exit 1
    fi
}

# 启动应用服务
start_applications() {
    log_info "启动应用服务..."
    
    docker-compose --env-file="$ENV_FILE" -f docker-compose-apps.yml up -d
    
    # 等待应用启动
    log_info "等待应用服务启动..."
    sleep 60
    
    # 检查应用服务状态
    check_service_health "mall-admin" "Mall Admin"
    check_service_health "mall-portal" "Mall Portal"
    check_service_health "mall-search" "Mall Search"
    
    log_success "应用服务启动完成"
}

# 启动Nginx
start_nginx() {
    log_info "启动Nginx反向代理..."
    
    docker-compose --env-file="$ENV_FILE" -f docker-compose-nginx.yml up -d
    
    # 等待Nginx启动
    sleep 10
    
    check_service_health "mall-nginx" "Nginx"
    
    log_success "Nginx启动完成"
}

# 检查服务健康状态
check_service_health() {
    local container_name=$1
    local service_name=$2
    local max_attempts=30
    local attempt=1
    
    log_info "检查 $service_name 服务状态..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker ps | grep -q "$container_name.*Up"; then
            log_success "$service_name 服务运行正常"
            return 0
        fi
        
        log_info "等待 $service_name 启动... ($attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    log_error "$service_name 服务启动失败或超时"
    docker logs "$container_name" --tail 50
    return 1
}

# 显示部署信息
show_deployment_info() {
    log_success "=== 部署完成 ==="
    echo
    log_info "服务访问地址:"
    echo "  前台商城: https://${DOMAIN_NAME:-your-domain.com}"
    echo "  后台管理: https://${ADMIN_DOMAIN:-admin.your-domain.com}"
    echo "  API文档: https://${API_DOMAIN:-api.your-domain.com}/swagger-ui.html"
    echo
    log_info "管理界面:"
    echo "  RabbitMQ: http://$(hostname -I | awk '{print $1}'):15672 (用户名: ${RABBITMQ_DEFAULT_USER}, 密码: ${RABBITMQ_DEFAULT_PASS})"
    echo "  Elasticsearch: http://$(hostname -I | awk '{print $1}'):9200"
    echo
    log_info "常用命令:"
    echo "  查看服务状态: docker-compose ps"
    echo "  查看日志: docker-compose logs -f [service-name]"
    echo "  停止服务: docker-compose down"
    echo "  重启服务: docker-compose restart [service-name]"
    echo
    log_warning "请确保:"
    echo "  1. 域名DNS已正确解析到服务器IP"
    echo "  2. SSL证书已正确配置"
    echo "  3. 防火墙已开放必要端口 (80, 443)"
    echo "  4. 阿里云安全组已配置正确"
}

# 主函数
main() {
    log_info "开始部署Mall项目到阿里云..."
    
    # 解析参数
    parse_args "$@"
    
    # 进入部署目录
    cd "$DEPLOY_DIR"
    
    # 执行部署步骤
    check_environment
    create_directories
    build_images
    start_infrastructure
    init_database
    start_applications
    start_nginx
    
    # 显示部署信息
    show_deployment_info
    
    log_success "Mall项目部署完成！"
}

# 捕获中断信号
trap 'log_error "部署被中断"; exit 1' INT TERM

# 执行主函数
main "$@"