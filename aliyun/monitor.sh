#!/bin/bash

# Mall项目监控脚本
# 使用方法: ./monitor.sh [--interval SECONDS] [--alert] [--log-file FILE]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
MONITOR_INTERVAL=60
ENABLE_ALERT=false
LOG_FILE="/var/log/mall-monitor.log"
ENV_FILE=".env"
ALERT_EMAIL=""
ALERT_WEBHOOK=""

# 阈值配置
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85
LOAD_THRESHOLD=5.0

# 日志函数
log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[INFO]${NC} $message"
    echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
}

log_success() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    echo "[$timestamp] [SUCCESS] $message" >> "$LOG_FILE"
}

log_warning() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[WARNING]${NC} $message"
    echo "[$timestamp] [WARNING] $message" >> "$LOG_FILE"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR]${NC} $message"
    echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
}

# 显示帮助信息
show_help() {
    cat << EOF
Mall项目监控脚本

使用方法:
    $0 [选项]

选项:
    --interval SECONDS  监控间隔时间，单位秒 (默认: 60)
    --alert            启用告警功能
    --log-file FILE    指定日志文件路径 (默认: /var/log/mall-monitor.log)
    --help, -h         显示此帮助信息

监控项目:
    - 容器状态监控
    - 系统资源监控 (CPU、内存、磁盘)
    - 服务健康检查
    - 网络连接监控
    - 日志错误监控

示例:
    $0                          # 默认监控
    $0 --interval 30 --alert    # 30秒间隔，启用告警
    $0 --log-file /tmp/monitor.log  # 自定义日志文件

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --interval)
                MONITOR_INTERVAL="$2"
                shift 2
                ;;
            --alert)
                ENABLE_ALERT=true
                shift
                ;;
            --log-file)
                LOG_FILE="$2"
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

# 初始化监控环境
init_monitor() {
    log_info "初始化监控环境..."
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # 加载环境变量
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
    
    log_success "监控环境初始化完成"
}

# 检查容器状态
check_containers() {
    local containers=("mall-mysql" "mall-redis" "mall-elasticsearch" "mall-rabbitmq" "mall-mongodb" "mall-admin" "mall-portal" "mall-search" "mall-nginx")
    local failed_containers=()
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container.*Up"; then
            # 检查健康状态
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
            
            if [ "$health" = "unhealthy" ]; then
                log_warning "容器 $container 健康检查失败"
                failed_containers+=("$container")
            fi
        else
            log_error "容器 $container 未运行"
            failed_containers+=("$container")
        fi
    done
    
    if [ ${#failed_containers[@]} -eq 0 ]; then
        log_success "所有容器运行正常"
        return 0
    else
        log_error "以下容器存在问题: ${failed_containers[*]}"
        
        if [ "$ENABLE_ALERT" = true ]; then
            send_alert "容器状态异常" "以下容器存在问题: ${failed_containers[*]}"
        fi
        
        return 1
    fi
}

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源使用情况..."
    
    # CPU使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    cpu_usage=${cpu_usage%.*}  # 去掉小数部分
    
    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
        log_warning "CPU使用率过高: ${cpu_usage}%"
        if [ "$ENABLE_ALERT" = true ]; then
            send_alert "CPU使用率告警" "当前CPU使用率: ${cpu_usage}%，超过阈值: ${CPU_THRESHOLD}%"
        fi
    else
        log_info "CPU使用率正常: ${cpu_usage}%"
    fi
    
    # 内存使用率
    local memory_info=$(free | grep Mem)
    local total_mem=$(echo $memory_info | awk '{print $2}')
    local used_mem=$(echo $memory_info | awk '{print $3}')
    local memory_usage=$((used_mem * 100 / total_mem))
    
    if [ "$memory_usage" -gt "$MEMORY_THRESHOLD" ]; then
        log_warning "内存使用率过高: ${memory_usage}%"
        if [ "$ENABLE_ALERT" = true ]; then
            send_alert "内存使用率告警" "当前内存使用率: ${memory_usage}%，超过阈值: ${MEMORY_THRESHOLD}%"
        fi
    else
        log_info "内存使用率正常: ${memory_usage}%"
    fi
    
    # 磁盘使用率
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
        log_warning "磁盘使用率过高: ${disk_usage}%"
        if [ "$ENABLE_ALERT" = true ]; then
            send_alert "磁盘使用率告警" "当前磁盘使用率: ${disk_usage}%，超过阈值: ${DISK_THRESHOLD}%"
        fi
    else
        log_info "磁盘使用率正常: ${disk_usage}%"
    fi
    
    # 系统负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    if (( $(echo "$load_avg > $LOAD_THRESHOLD" | bc -l) )); then
        log_warning "系统负载过高: $load_avg"
        if [ "$ENABLE_ALERT" = true ]; then
            send_alert "系统负载告警" "当前系统负载: $load_avg，超过阈值: $LOAD_THRESHOLD"
        fi
    else
        log_info "系统负载正常: $load_avg"
    fi
}

# 检查服务健康
check_service_health() {
    log_info "检查服务健康状态..."
    
    local services=(
        "mall-admin:8080:/actuator/health"
        "mall-portal:8085:/actuator/health"
        "mall-search:8081:/actuator/health"
    )
    
    local failed_services=()
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service port path <<< "$service_info"
        
        # 检查端口是否可访问
        if docker exec "$service" wget --spider --timeout=10 "http://localhost:$port$path" >/dev/null 2>&1; then
            log_success "$service 服务健康检查通过"
        else
            log_error "$service 服务健康检查失败"
            failed_services+=("$service")
        fi
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        if [ "$ENABLE_ALERT" = true ]; then
            send_alert "服务健康检查失败" "以下服务健康检查失败: ${failed_services[*]}"
        fi
        return 1
    fi
    
    return 0
}

# 检查网络连接
check_network_connectivity() {
    log_info "检查网络连接..."
    
    # 检查数据库连接
    if docker exec mall-mysql mysqladmin ping -h localhost >/dev/null 2>&1; then
        log_success "MySQL连接正常"
    else
        log_error "MySQL连接失败"
        if [ "$ENABLE_ALERT" = true ]; then
            send_alert "数据库连接异常" "MySQL数据库连接失败"
        fi
    fi
    
    # 检查Redis连接
    if docker exec mall-redis redis-cli ping >/dev/null 2>&1; then
        log_success "Redis连接正常"
    else
        log_error "Redis连接失败"
        if [ "$ENABLE_ALERT" = true ]; then
            send_alert "缓存连接异常" "Redis缓存连接失败"
        fi
    fi
    
    # 检查Elasticsearch连接
    if docker exec mall-elasticsearch curl -f http://localhost:9200/_cluster/health >/dev/null 2>&1; then
        log_success "Elasticsearch连接正常"
    else
        log_error "Elasticsearch连接失败"
        if [ "$ENABLE_ALERT" = true ]; then
            send_alert "搜索引擎连接异常" "Elasticsearch搜索引擎连接失败"
        fi
    fi
}

# 检查日志错误
check_log_errors() {
    log_info "检查应用日志错误..."
    
    local log_path="${DATA_PATH:-/data/mall}/logs"
    local error_count=0
    
    # 检查最近5分钟的错误日志
    if [ -d "$log_path" ]; then
        error_count=$(find "$log_path" -name "*.log" -mmin -5 -exec grep -l "ERROR\|FATAL" {} \; 2>/dev/null | wc -l)
        
        if [ "$error_count" -gt 0 ]; then
            log_warning "发现 $error_count 个日志文件包含错误信息"
            
            # 获取最新的错误信息
            local recent_errors=$(find "$log_path" -name "*.log" -mmin -5 -exec grep "ERROR\|FATAL" {} \; 2>/dev/null | tail -5)
            
            if [ "$ENABLE_ALERT" = true ] && [ -n "$recent_errors" ]; then
                send_alert "应用日志错误" "发现应用错误日志:\n$recent_errors"
            fi
        else
            log_success "未发现错误日志"
        fi
    else
        log_warning "日志目录不存在: $log_path"
    fi
}

# 发送告警
send_alert() {
    local title="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_warning "发送告警: $title"
    
    # 邮件告警
    if [ -n "$ALERT_EMAIL" ] && command -v mail >/dev/null 2>&1; then
        echo -e "时间: $timestamp\n\n$message" | mail -s "[Mall监控告警] $title" "$ALERT_EMAIL"
    fi
    
    # Webhook告警（钉钉、企业微信等）
    if [ -n "$ALERT_WEBHOOK" ] && command -v curl >/dev/null 2>&1; then
        local payload=$(cat <<EOF
{
    "msgtype": "text",
    "text": {
        "content": "[Mall监控告警]\n标题: $title\n时间: $timestamp\n详情: $message"
    }
}
EOF
        )
        
        curl -X POST "$ALERT_WEBHOOK" \
             -H 'Content-Type: application/json' \
             -d "$payload" >/dev/null 2>&1
    fi
    
    # 系统日志
    logger "Mall监控告警: $title - $message"
}

# 生成监控报告
generate_report() {
    local report_file="/tmp/mall-monitor-report-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Mall项目监控报告
================

报告时间: $(date)

=== 容器状态 ===
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")

=== 系统资源 ===
CPU使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
内存使用情况:
$(free -h)

磁盘使用情况:
$(df -h)

系统负载: $(uptime)

=== 网络状态 ===
$(netstat -tlnp | grep -E ':(3306|6379|9200|5672|8080|8081|8085|80|443)\s')

=== 最近错误日志 ===
EOF
    
    # 添加最近的错误日志
    local log_path="${DATA_PATH:-/data/mall}/logs"
    if [ -d "$log_path" ]; then
        find "$log_path" -name "*.log" -mmin -60 -exec grep "ERROR\|FATAL" {} \; 2>/dev/null | tail -20 >> "$report_file" || echo "无错误日志" >> "$report_file"
    fi
    
    log_info "监控报告已生成: $report_file"
}

# 主监控循环
monitor_loop() {
    log_info "开始监控Mall项目，间隔: ${MONITOR_INTERVAL}秒"
    
    while true; do
        log_info "=== 开始监控检查 ==="
        
        # 执行各项检查
        check_containers
        check_system_resources
        check_service_health
        check_network_connectivity
        check_log_errors
        
        log_info "=== 监控检查完成 ==="
        
        # 等待下次检查
        sleep "$MONITOR_INTERVAL"
    done
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"
    
    # 初始化监控
    init_monitor
    
    # 检查是否为一次性运行
    if [ "$1" = "--once" ]; then
        log_info "执行一次性监控检查..."
        check_containers
        check_system_resources
        check_service_health
        check_network_connectivity
        check_log_errors
        generate_report
        exit 0
    fi
    
    # 启动监控循环
    monitor_loop
}

# 捕获中断信号
trap 'log_info "监控被停止"; exit 0' INT TERM

# 执行主函数
main "$@"