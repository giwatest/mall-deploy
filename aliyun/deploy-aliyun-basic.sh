#!/bin/bash

# Mall项目阿里云基础部署脚本
# 第一阶段：ECS + RDS + Redis + OSS 基础部署
# 使用说明：./deploy-aliyun-basic.sh [选项]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
Mall项目阿里云基础部署脚本

使用方法:
    $0 [选项]

选项:
    -h, --help              显示此帮助信息
    -s, --skip-build        跳过镜像构建
    -d, --skip-db-init      跳过数据库初始化
    -c, --clean             清理旧容器和镜像
    -v, --verbose           详细输出
    --dry-run              仅显示将要执行的命令，不实际执行

示例:
    $0                      # 完整部署
    $0 -s                   # 跳过构建，直接部署
    $0 -c                   # 清理后重新部署
    $0 --dry-run            # 预览部署命令

EOF
}

# 解析命令行参数
SKIP_BUILD=false
SKIP_DB_INIT=false
CLEAN_DEPLOY=false
VERBOSE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--skip-build)
            SKIP_BUILD=true
            shift
            ;;
        -d|--skip-db-init)
            SKIP_DB_INIT=true
            shift
            ;;
        -c|--clean)
            CLEAN_DEPLOY=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 设置详细输出
if [ "$VERBOSE" = true ]; then
    set -x
fi

# 执行命令函数
execute_command() {
    local cmd="$1"
    local desc="$2"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] $desc"
        echo "  命令: $cmd"
        return 0
    fi
    
    log_info "$desc"
    if [ "$VERBOSE" = true ]; then
        eval "$cmd"
    else
        eval "$cmd" > /dev/null 2>&1
    fi
}

# 检查必要的工具
check_requirements() {
    log_info "检查部署环境..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装，请先安装Docker"
        exit 1
    fi
    
    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose未安装，请先安装Docker Compose"
        exit 1
    fi
    
    # 检查Maven
    if [ "$SKIP_BUILD" = false ] && ! command -v mvn &> /dev/null; then
        log_error "Maven未安装，请先安装Maven或使用 -s 选项跳过构建"
        exit 1
    fi
    
    # 检查环境变量文件
    if [ ! -f ".env.aliyun" ]; then
        log_error "环境变量文件 .env.aliyun 不存在，请先配置"
        log_info "可以复制 .env.aliyun 模板并修改配置"
        exit 1
    fi
    
    log_success "环境检查通过"
}

# 加载环境变量
load_env() {
    log_info "加载环境变量..."
    set -a
    source .env.aliyun
    set +a
    log_success "环境变量加载完成"
}

# 创建必要的目录
create_directories() {
    log_info "创建数据目录..."
    
    local dirs=(
        "$DATA_PATH/logs/mall-admin"
        "$DATA_PATH/logs/mall-portal"
        "$DATA_PATH/logs/mall-search"
        "$DATA_PATH/logs/nginx"
        "$DATA_PATH/mongodb/data"
        "$DATA_PATH/mongodb/logs"
        "$DATA_PATH/rabbitmq/data"
        "$DATA_PATH/rabbitmq/logs"
        "$DATA_PATH/elasticsearch/data"
        "$DATA_PATH/elasticsearch/logs"
        "$DATA_PATH/ssl"
        "$DATA_PATH/backup"
    )
    
    for dir in "${dirs[@]}"; do
        execute_command "mkdir -p $dir" "创建目录: $dir"
        execute_command "chmod -R 755 $dir" "设置目录权限: $dir"
    done
    
    log_success "目录创建完成"
}

# 清理旧容器和镜像
clean_old_deployment() {
    if [ "$CLEAN_DEPLOY" = true ]; then
        log_info "清理旧的部署..."
        
        execute_command "docker-compose -f docker-compose-aliyun-basic.yml down -v" "停止并删除容器"
        execute_command "docker system prune -f" "清理无用的Docker资源"
        
        log_success "清理完成"
    fi
}

# 构建应用镜像
build_images() {
    if [ "$SKIP_BUILD" = false ]; then
        log_info "构建应用镜像..."
        
        # 回到项目根目录
        cd ../..
        
        # 构建各个模块
        local modules=("mall-admin" "mall-portal" "mall-search")
        
        for module in "${modules[@]}"; do
            log_info "构建 $module 镜像..."
            
            # 检查模块目录是否存在
            if [ ! -d "$module" ]; then
                log_error "模块目录 $module 不存在"
                exit 1
            fi
            
            # 使用Maven构建镜像
            execute_command "mvn clean package docker:build -pl $module -am -DskipTests" "Maven构建 $module"
            
            log_success "$module 镜像构建完成"
        done
        
        # 回到部署目录
        cd deploy/aliyun
        
        log_success "所有镜像构建完成"
    else
        log_info "跳过镜像构建"
    fi
}

# 检查阿里云服务连接
check_aliyun_services() {
    log_info "检查阿里云服务连接..."
    
    # 检查RDS连接
    log_info "检查RDS MySQL连接..."
    if command -v mysql &> /dev/null; then
        if ! mysql -h"$ALIYUN_RDS_HOST" -P"$ALIYUN_RDS_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1" &> /dev/null; then
            log_warning "无法连接到RDS MySQL，请检查配置"
        else
            log_success "RDS MySQL连接正常"
        fi
    else
        log_warning "MySQL客户端未安装，跳过RDS连接检查"
    fi
    
    # 检查Redis连接
    log_info "检查Redis连接..."
    if command -v redis-cli &> /dev/null; then
        if ! redis-cli -h "$ALIYUN_REDIS_HOST" -p "$ALIYUN_REDIS_PORT" -a "$REDIS_PASSWORD" ping &> /dev/null; then
            log_warning "无法连接到Redis，请检查配置"
        else
            log_success "Redis连接正常"
        fi
    else
        log_warning "Redis客户端未安装，跳过Redis连接检查"
    fi
    
    log_success "阿里云服务检查完成"
}

# 启动基础服务
start_infrastructure() {
    log_info "启动基础设施服务..."
    
    # 启动MongoDB、RabbitMQ、Elasticsearch
    execute_command "docker-compose -f docker-compose-aliyun-basic.yml up -d mall-mongodb mall-rabbitmq mall-elasticsearch" "启动基础服务"
    
    # 等待服务启动
    log_info "等待基础服务启动..."
    sleep 30
    
    # 检查服务状态
    execute_command "docker-compose -f docker-compose-aliyun-basic.yml ps" "检查服务状态"
    
    log_success "基础设施服务启动完成"
}

# 初始化数据库
init_database() {
    if [ "$SKIP_DB_INIT" = false ]; then
        log_info "初始化数据库..."
        
        # 检查SQL文件是否存在
        local sql_file="../../document/sql/mall.sql"
        if [ -f "$sql_file" ]; then
            log_info "导入数据库结构和数据..."
            if command -v mysql &> /dev/null; then
                execute_command "mysql -h$ALIYUN_RDS_HOST -P$ALIYUN_RDS_PORT -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE < $sql_file" "导入SQL文件"
                log_success "数据库初始化完成"
            else
                log_warning "MySQL客户端未安装，请手动导入SQL文件: $sql_file"
            fi
        else
            log_warning "SQL文件不存在: $sql_file"
        fi
    else
        log_info "跳过数据库初始化"
    fi
}

# 启动应用服务
start_applications() {
    log_info "启动应用服务..."
    
    # 启动应用服务
    execute_command "docker-compose -f docker-compose-aliyun-basic.yml up -d mall-admin mall-portal mall-search" "启动应用服务"
    
    # 等待应用启动
    log_info "等待应用服务启动..."
    sleep 60
    
    # 检查应用状态
    execute_command "docker-compose -f docker-compose-aliyun-basic.yml ps" "检查应用状态"
    
    log_success "应用服务启动完成"
}

# 启动Nginx
start_nginx() {
    log_info "启动Nginx反向代理..."
    
    execute_command "docker-compose -f docker-compose-aliyun-basic.yml up -d mall-nginx" "启动Nginx"
    
    log_success "Nginx启动完成"
}

# 显示部署结果
show_deployment_result() {
    log_success "=== Mall项目阿里云基础部署完成 ==="
    
    echo
    log_info "服务访问地址:"
    echo "  管理后台: http://$ADMIN_DOMAIN 或 http://$(hostname -I | awk '{print $1}'):80"
    echo "  前台门户: http://$PORTAL_DOMAIN 或 http://$(hostname -I | awk '{print $1}'):80"
    echo "  搜索服务: http://$(hostname -I | awk '{print $1}'):8081"
    echo "  RabbitMQ管理: http://$(hostname -I | awk '{print $1}'):15672"
    echo "  Elasticsearch: http://$(hostname -I | awk '{print $1}'):9200"
    
    echo
    log_info "常用命令:"
    echo "  查看服务状态: docker-compose -f docker-compose-aliyun-basic.yml ps"
    echo "  查看日志: docker-compose -f docker-compose-aliyun-basic.yml logs -f [服务名]"
    echo "  停止服务: docker-compose -f docker-compose-aliyun-basic.yml down"
    echo "  重启服务: docker-compose -f docker-compose-aliyun-basic.yml restart [服务名]"
    
    echo
    log_info "下一步操作:"
    echo "  1. 配置域名解析指向ECS公网IP"
    echo "  2. 配置SSL证书（可选）"
    echo "  3. 配置阿里云安全组开放相应端口"
    echo "  4. 设置定期备份任务"
    echo "  5. 配置监控告警"
    
    echo
    log_warning "注意事项:"
    echo "  - 请确保阿里云安全组已开放80、443、8080、8081、8085端口"
    echo "  - 建议配置SSL证书启用HTTPS"
    echo "  - 定期备份数据库和重要数据"
    echo "  - 监控服务运行状态和资源使用情况"
}

# 主函数
main() {
    log_info "开始Mall项目阿里云基础部署..."
    
    # 检查当前目录
    if [ ! -f "docker-compose-aliyun-basic.yml" ]; then
        log_error "请在部署目录中运行此脚本"
        exit 1
    fi
    
    # 执行部署步骤
    check_requirements
    load_env
    create_directories
    clean_old_deployment
    build_images
    check_aliyun_services
    start_infrastructure
    init_database
    start_applications
    start_nginx
    show_deployment_result
    
    log_success "部署完成！"
}

# 错误处理
trap 'log_error "部署过程中发生错误，请检查日志"; exit 1' ERR

# 执行主函数
main "$@"