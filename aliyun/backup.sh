#!/bin/bash

# Mall项目数据备份脚本
# 使用方法: ./backup.sh [--type TYPE] [--retention DAYS]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
BACKUP_TYPE="all"
RETENTION_DAYS=7
BACKUP_DIR="/data/mall/backups"
DATE=$(date +"%Y%m%d_%H%M%S")
ENV_FILE=".env"

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
Mall项目数据备份脚本

使用方法:
    $0 [选项]

选项:
    --type TYPE         备份类型: all, mysql, redis, mongodb, files (默认: all)
    --retention DAYS    备份保留天数 (默认: 7)
    --help, -h          显示此帮助信息

备份类型说明:
    all                 备份所有数据
    mysql               仅备份MySQL数据库
    redis               仅备份Redis数据
    mongodb             仅备份MongoDB数据
    files               仅备份配置文件和日志

示例:
    $0                          # 完整备份
    $0 --type mysql             # 仅备份MySQL
    $0 --retention 30           # 保留30天的备份

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                BACKUP_TYPE="$2"
                shift 2
                ;;
            --retention)
                RETENTION_DAYS="$2"
                shift 2
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
    log_info "检查备份环境..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装"
        exit 1
    fi
    
    # 检查环境变量文件
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    else
        log_warning "环境变量文件不存在，使用默认配置"
    fi
    
    # 创建备份目录
    mkdir -p "$BACKUP_DIR"
    
    log_success "环境检查完成"
}

# 备份MySQL数据库
backup_mysql() {
    log_info "开始备份MySQL数据库..."
    
    local backup_file="$BACKUP_DIR/mysql_${DATE}.sql.gz"
    local mysql_password="${MYSQL_ROOT_PASSWORD:-root}"
    
    # 检查MySQL容器是否运行
    if ! docker ps | grep -q "mall-mysql.*Up"; then
        log_error "MySQL容器未运行"
        return 1
    fi
    
    # 执行备份
    docker exec mall-mysql mysqldump -uroot -p"$mysql_password" \
        --single-transaction \
        --routines \
        --triggers \
        --all-databases | gzip > "$backup_file"
    
    if [ $? -eq 0 ]; then
        log_success "MySQL备份完成: $backup_file"
        log_info "备份文件大小: $(du -h "$backup_file" | cut -f1)"
    else
        log_error "MySQL备份失败"
        return 1
    fi
}

# 备份Redis数据
backup_redis() {
    log_info "开始备份Redis数据..."
    
    local backup_file="$BACKUP_DIR/redis_${DATE}.rdb"
    
    # 检查Redis容器是否运行
    if ! docker ps | grep -q "mall-redis.*Up"; then
        log_error "Redis容器未运行"
        return 1
    fi
    
    # 执行BGSAVE命令
    docker exec mall-redis redis-cli BGSAVE
    
    # 等待备份完成
    while [ "$(docker exec mall-redis redis-cli LASTSAVE)" = "$(docker exec mall-redis redis-cli LASTSAVE)" ]; do
        sleep 1
    done
    
    # 复制备份文件
    docker cp mall-redis:/data/dump.rdb "$backup_file"
    
    if [ $? -eq 0 ]; then
        log_success "Redis备份完成: $backup_file"
        log_info "备份文件大小: $(du -h "$backup_file" | cut -f1)"
    else
        log_error "Redis备份失败"
        return 1
    fi
}

# 备份MongoDB数据
backup_mongodb() {
    log_info "开始备份MongoDB数据..."
    
    local backup_dir="$BACKUP_DIR/mongodb_${DATE}"
    local backup_file="$BACKUP_DIR/mongodb_${DATE}.tar.gz"
    local mongo_user="${MONGO_INITDB_ROOT_USERNAME:-mall}"
    local mongo_password="${MONGO_INITDB_ROOT_PASSWORD:-Mall@2024}"
    
    # 检查MongoDB容器是否运行
    if ! docker ps | grep -q "mall-mongodb.*Up"; then
        log_error "MongoDB容器未运行"
        return 1
    fi
    
    # 创建临时备份目录
    mkdir -p "$backup_dir"
    
    # 执行备份
    docker exec mall-mongodb mongodump \
        --username "$mongo_user" \
        --password "$mongo_password" \
        --authenticationDatabase admin \
        --out /tmp/backup
    
    # 复制备份文件
    docker cp mall-mongodb:/tmp/backup "$backup_dir"
    
    # 压缩备份
    tar -czf "$backup_file" -C "$BACKUP_DIR" "mongodb_${DATE}"
    
    # 清理临时目录
    rm -rf "$backup_dir"
    docker exec mall-mongodb rm -rf /tmp/backup
    
    if [ $? -eq 0 ]; then
        log_success "MongoDB备份完成: $backup_file"
        log_info "备份文件大小: $(du -h "$backup_file" | cut -f1)"
    else
        log_error "MongoDB备份失败"
        return 1
    fi
}

# 备份配置文件和日志
backup_files() {
    log_info "开始备份配置文件和日志..."
    
    local backup_file="$BACKUP_DIR/files_${DATE}.tar.gz"
    local data_path="${DATA_PATH:-/data/mall}"
    
    # 创建文件列表
    local files_to_backup=(
        "$data_path/nginx/conf"
        "$data_path/mysql/conf"
        "$(pwd)/.env"
        "$(pwd)/docker-compose-*.yml"
        "$(pwd)/nginx"
    )
    
    # 备份日志文件（最近7天）
    local log_files=$(find "$data_path/logs" -name "*.log" -mtime -7 2>/dev/null || true)
    
    # 创建备份
    tar -czf "$backup_file" \
        --exclude='*.tmp' \
        --exclude='*.lock' \
        "${files_to_backup[@]}" \
        $log_files 2>/dev/null || true
    
    if [ -f "$backup_file" ]; then
        log_success "文件备份完成: $backup_file"
        log_info "备份文件大小: $(du -h "$backup_file" | cut -f1)"
    else
        log_error "文件备份失败"
        return 1
    fi
}

# 清理旧备份
cleanup_old_backups() {
    log_info "清理 $RETENTION_DAYS 天前的备份文件..."
    
    local deleted_count=0
    
    # 查找并删除旧备份
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((deleted_count++))
        log_info "删除旧备份: $(basename "$file")"
    done < <(find "$BACKUP_DIR" -name "*.sql.gz" -o -name "*.rdb" -o -name "*.tar.gz" -type f -mtime +$RETENTION_DAYS -print0 2>/dev/null)
    
    if [ $deleted_count -gt 0 ]; then
        log_success "清理了 $deleted_count 个旧备份文件"
    else
        log_info "没有需要清理的旧备份文件"
    fi
}

# 生成备份报告
generate_report() {
    local report_file="$BACKUP_DIR/backup_report_${DATE}.txt"
    
    cat > "$report_file" << EOF
Mall项目备份报告
================

备份时间: $(date)
备份类型: $BACKUP_TYPE
备份目录: $BACKUP_DIR
保留天数: $RETENTION_DAYS

备份文件列表:
EOF
    
    # 列出当前备份文件
    find "$BACKUP_DIR" -name "*_${DATE}.*" -type f -exec ls -lh {} \; >> "$report_file"
    
    echo "" >> "$report_file"
    echo "磁盘使用情况:" >> "$report_file"
    df -h "$BACKUP_DIR" >> "$report_file"
    
    log_info "备份报告已生成: $report_file"
}

# 发送通知（可选）
send_notification() {
    local status=$1
    local message=$2
    
    # 这里可以集成邮件、钉钉、企业微信等通知方式
    # 示例：发送到系统日志
    logger "Mall备份通知: $status - $message"
    
    # 如果配置了邮件，可以发送邮件通知
    # if [ -n "$EMAIL_TO" ]; then
    #     echo "$message" | mail -s "Mall备份通知: $status" "$EMAIL_TO"
    # fi
}

# 主函数
main() {
    local start_time=$(date +%s)
    local backup_success=true
    
    log_info "开始执行Mall项目数据备份..."
    
    # 解析参数
    parse_args "$@"
    
    # 检查环境
    check_environment
    
    # 根据备份类型执行相应的备份
    case $BACKUP_TYPE in
        "all")
            backup_mysql || backup_success=false
            backup_redis || backup_success=false
            backup_mongodb || backup_success=false
            backup_files || backup_success=false
            ;;
        "mysql")
            backup_mysql || backup_success=false
            ;;
        "redis")
            backup_redis || backup_success=false
            ;;
        "mongodb")
            backup_mongodb || backup_success=false
            ;;
        "files")
            backup_files || backup_success=false
            ;;
        *)
            log_error "不支持的备份类型: $BACKUP_TYPE"
            exit 1
            ;;
    esac
    
    # 清理旧备份
    cleanup_old_backups
    
    # 生成报告
    generate_report
    
    # 计算耗时
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$backup_success" = true ]; then
        log_success "备份完成！耗时: ${duration}秒"
        send_notification "成功" "Mall项目备份成功完成，耗时${duration}秒"
    else
        log_error "备份过程中出现错误！"
        send_notification "失败" "Mall项目备份过程中出现错误"
        exit 1
    fi
}

# 捕获中断信号
trap 'log_error "备份被中断"; exit 1' INT TERM

# 执行主函数
main "$@"