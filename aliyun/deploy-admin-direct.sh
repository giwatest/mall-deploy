#!/bin/bash

# Mall Admin 阿里云直接部署脚本
# 不使用Docker，直接在服务器上运行Java应用
# 使用.env.aliyun配置文件中的环境变量

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
Mall Admin 阿里云直接部署脚本

使用方法:
    $0 [选项]

选项:
    -h, --help              显示此帮助信息
    -s, --skip-build        跳过编译构建
    -d, --skip-db-init      跳过数据库初始化
    -c, --clean             清理旧的部署文件
    -v, --verbose           详细输出
    --dry-run              仅显示将要执行的命令，不实际执行
    --stop                 停止服务
    --restart              重启服务
    --status               查看服务状态

示例:
    $0                      # 完整部署
    $0 -s                   # 跳过构建，直接部署
    $0 --stop               # 停止服务
    $0 --restart            # 重启服务
    $0 --status             # 查看状态

EOF
}

# 解析命令行参数
SKIP_BUILD=false
SKIP_DB_INIT=false
CLEAN_DEPLOY=false
VERBOSE=false
DRY_RUN=false
ACTION="deploy"

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
        --stop)
            ACTION="stop"
            shift
            ;;
        --restart)
            ACTION="restart"
            shift
            ;;
        --status)
            ACTION="status"
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

# 配置文件路径
ENV_FILE=".env.aliyun"
APP_NAME="mall-admin"
APP_DIR="/opt/mall"
LOG_DIR="/var/log/mall"
PID_FILE="/var/run/mall-admin.pid"
JAR_FILE="$APP_DIR/mall-admin.jar"

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
    
    # 检查Java
    if ! command -v java &> /dev/null; then
        log_error "Java未安装，请先安装Java 8+"
        exit 1
    fi
    
    # 检查Maven（如果需要构建）
    if [ "$SKIP_BUILD" = false ] && ! command -v mvn &> /dev/null; then
        log_error "Maven未安装，请先安装Maven或使用 -s 选项跳过构建"
        exit 1
    fi
    
    # 检查环境变量文件
    if [ ! -f "$ENV_FILE" ]; then
        log_error "环境变量文件 $ENV_FILE 不存在，请先配置"
        exit 1
    fi
    
    log_success "环境检查通过"
}

# 加载环境变量
load_env() {
    log_info "加载环境变量..."
    set -a
    source "$ENV_FILE"
    set +a
    log_success "环境变量加载完成"
}

# 创建必要的目录
create_directories() {
    log_info "创建应用目录..."
    
    execute_command "sudo mkdir -p $APP_DIR" "创建应用目录: $APP_DIR"
    execute_command "sudo mkdir -p $LOG_DIR" "创建日志目录: $LOG_DIR"
    execute_command "sudo mkdir -p /etc/mall" "创建配置目录: /etc/mall"
    
    # 设置目录权限
    execute_command "sudo chown -R $USER:$USER $APP_DIR" "设置应用目录权限"
    execute_command "sudo chown -R $USER:$USER $LOG_DIR" "设置日志目录权限"
    
    log_success "目录创建完成"
}

# 构建应用
build_application() {
    if [ "$SKIP_BUILD" = true ]; then
        log_info "跳过应用构建"
        return 0
    fi
    
    log_info "开始构建Mall Admin应用..."
    
    # 回到项目根目录
    cd "../../"
    
    # 构建mall-admin模块
    execute_command "mvn clean package -pl mall-admin -am -DskipTests" "编译mall-admin模块"
    
    # 复制JAR文件到部署目录
    execute_command "cp mall-admin/target/mall-admin-*.jar $JAR_FILE" "复制JAR文件到部署目录"
    
    log_success "应用构建完成"
}

# 生成应用配置文件
generate_config() {
    log_info "生成应用配置文件..."
    
    cat > "/etc/mall/application-prod.yml" << EOF
server:
  port: 8080
  servlet:
    context-path: /

spring:
  profiles:
    active: prod
  datasource:
    url: jdbc:mysql://${ALIYUN_RDS_HOST}:${ALIYUN_RDS_PORT}/${MYSQL_DATABASE}?useUnicode=true&characterEncoding=utf-8&serverTimezone=Asia/Shanghai&useSSL=false&allowPublicKeyRetrieval=true
    username: ${MYSQL_USER}
    password: ${MYSQL_PASSWORD}
    driver-class-name: com.mysql.cj.jdbc.Driver
    type: com.alibaba.druid.pool.DruidDataSource
    druid:
      initial-size: 5
      min-idle: 5
      max-active: 20
      max-wait: 60000
      time-between-eviction-runs-millis: 60000
      min-evictable-idle-time-millis: 300000
      validation-query: SELECT 1 FROM DUAL
      test-while-idle: true
      test-on-borrow: false
      test-on-return: false
      pool-prepared-statements: true
      max-pool-prepared-statement-per-connection-size: 20
      filters: stat,wall,slf4j
      connection-properties: druid.stat.mergeSql=true;druid.stat.slowSqlMillis=5000
      stat-view-servlet:
        enabled: true
        url-pattern: /druid/*
        login-username: admin
        login-password: ${DRUID_PASSWORD:-admin123}
      web-stat-filter:
        enabled: true
        url-pattern: /*
        exclusions: "*.js,*.gif,*.jpg,*.png,*.css,*.ico,/druid/*"
  redis:
    host: ${ALIYUN_REDIS_HOST}
    port: ${ALIYUN_REDIS_PORT}
    password: ${REDIS_PASSWORD}
    database: 0
    timeout: 3000ms
    lettuce:
      pool:
        max-active: 8
        max-wait: -1ms
        max-idle: 8
        min-idle: 0

# 阿里云OSS配置
aliyun:
  oss:
    endpoint: ${ALIYUN_OSS_ENDPOINT}
    accessKeyId: ${ALIYUN_OSS_ACCESS_KEY_ID}
    accessKeySecret: ${ALIYUN_OSS_ACCESS_KEY_SECRET}
    bucketName: ${ALIYUN_OSS_BUCKET_NAME}
    policy:
      expire: 300
    maxSize: 10
    callback: ${ALIYUN_OSS_CALLBACK}
    dir:
      prefix: mall/images/

# JWT配置
jwt:
  tokenHeader: Authorization
  secret: ${JWT_SECRET}
  expiration: 604800
  tokenHead: Bearer

# MyBatis配置
mybatis:
  mapper-locations: classpath:mapper/*.xml,classpath*:com/**/mapper/*.xml
  type-aliases-package: com.macro.mall.model
  configuration:
    map-underscore-to-camel-case: true

# 日志配置
logging:
  level:
    com.macro.mall: ${LOG_LEVEL}
    org.springframework.security: ${LOG_LEVEL}
  file:
    name: ${LOG_DIR}/mall-admin.log
  logback:
    rollingpolicy:
      max-file-size: 100MB
      max-history: 30
      total-size-cap: 1GB

# 管理端点配置
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: when-authorized
EOF
    
    log_success "配置文件生成完成"
}

# 生成systemd服务文件
generate_service() {
    log_info "生成systemd服务文件..."
    
    sudo tee "/etc/systemd/system/mall-admin.service" > /dev/null << EOF
[Unit]
Description=Mall Admin Service
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/java $JAVA_OPTS_ADMIN -jar $JAR_FILE --spring.config.location=/etc/mall/application-prod.yml
ExecStop=/bin/kill -TERM \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mall-admin
KillMode=mixed
KillSignal=TERM
TimeoutStopSec=30

# 环境变量
Environment=JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
Environment=SPRING_PROFILES_ACTIVE=prod
Environment=TZ=Asia/Shanghai

# 资源限制
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF
    
    execute_command "sudo systemctl daemon-reload" "重新加载systemd配置"
    execute_command "sudo systemctl enable mall-admin" "启用mall-admin服务"
    
    log_success "systemd服务配置完成"
}

# 初始化数据库
init_database() {
    if [ "$SKIP_DB_INIT" = true ]; then
        log_info "跳过数据库初始化"
        return 0
    fi
    
    log_info "初始化数据库..."
    
    # 检查MySQL连接
    if ! mysql -h"$ALIYUN_RDS_HOST" -P"$ALIYUN_RDS_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then
        log_error "无法连接到MySQL数据库，请检查配置"
        exit 1
    fi
    
    # 导入数据库脚本
    if [ -f "../../document/sql/mall.sql" ]; then
        execute_command "mysql -h\"$ALIYUN_RDS_HOST\" -P\"$ALIYUN_RDS_PORT\" -u\"$MYSQL_USER\" -p\"$MYSQL_PASSWORD\" \"$MYSQL_DATABASE\" < ../../document/sql/mall.sql" "导入数据库脚本"
        log_success "数据库初始化完成"
    else
        log_warning "数据库脚本文件不存在，跳过数据库初始化"
    fi
}

# 启动服务
start_service() {
    log_info "启动Mall Admin服务..."
    
    execute_command "sudo systemctl start mall-admin" "启动服务"
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if sudo systemctl is-active --quiet mall-admin; then
        log_success "Mall Admin服务启动成功"
        log_info "服务状态: $(sudo systemctl is-active mall-admin)"
        log_info "访问地址: http://$(hostname -I | awk '{print $1}'):8080"
        log_info "管理后台: http://$(hostname -I | awk '{print $1}'):8080/index.html"
        log_info "API文档: http://$(hostname -I | awk '{print $1}'):8080/swagger-ui.html"
        log_info "数据库监控: http://$(hostname -I | awk '{print $1}'):8080/druid"
    else
        log_error "Mall Admin服务启动失败"
        log_info "查看日志: sudo journalctl -u mall-admin -f"
        exit 1
    fi
}

# 停止服务
stop_service() {
    log_info "停止Mall Admin服务..."
    
    if sudo systemctl is-active --quiet mall-admin; then
        execute_command "sudo systemctl stop mall-admin" "停止服务"
        log_success "Mall Admin服务已停止"
    else
        log_info "Mall Admin服务未运行"
    fi
}

# 重启服务
restart_service() {
    log_info "重启Mall Admin服务..."
    
    execute_command "sudo systemctl restart mall-admin" "重启服务"
    
    # 等待服务启动
    sleep 5
    
    if sudo systemctl is-active --quiet mall-admin; then
        log_success "Mall Admin服务重启成功"
    else
        log_error "Mall Admin服务重启失败"
        exit 1
    fi
}

# 查看服务状态
show_status() {
    log_info "Mall Admin服务状态:"
    
    echo "=== 服务状态 ==="
    sudo systemctl status mall-admin --no-pager
    
    echo "\n=== 最近日志 ==="
    sudo journalctl -u mall-admin --no-pager -n 20
    
    echo "\n=== 端口监听 ==="
    netstat -tlnp | grep :8080 || echo "端口8080未监听"
    
    echo "\n=== 进程信息 ==="
    ps aux | grep mall-admin | grep -v grep || echo "未找到mall-admin进程"
}

# 清理旧部署
clean_deployment() {
    if [ "$CLEAN_DEPLOY" = true ]; then
        log_info "清理旧的部署..."
        
        # 停止服务
        if sudo systemctl is-active --quiet mall-admin; then
            execute_command "sudo systemctl stop mall-admin" "停止服务"
        fi
        
        # 清理文件
        execute_command "rm -f $JAR_FILE" "删除旧的JAR文件"
        execute_command "rm -f /etc/mall/application-prod.yml" "删除旧的配置文件"
        
        log_success "清理完成"
    fi
}

# 主函数
main() {
    log_info "开始Mall Admin阿里云直接部署..."
    
    case $ACTION in
        "deploy")
            check_requirements
            load_env
            clean_deployment
            create_directories
            build_application
            generate_config
            generate_service
            init_database
            start_service
            ;;
        "stop")
            stop_service
            ;;
        "restart")
            load_env
            restart_service
            ;;
        "status")
            show_status
            ;;
        *)
            log_error "未知操作: $ACTION"
            show_help
            exit 1
            ;;
    esac
    
    log_success "操作完成！"
}

# 执行主函数
main "$@"