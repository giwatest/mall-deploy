#!/bin/bash

# Mall项目Docker镜像构建脚本
# 使用方法: ./build-images.sh [--push]

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

# 检查Docker是否运行
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker未运行或无权限访问Docker"
        exit 1
    fi
}

# 检查Maven是否安装
check_maven() {
    if ! command -v mvn &> /dev/null; then
        log_error "Maven未安装，请先安装Maven"
        exit 1
    fi
}

# 构建单个模块
build_module() {
    local module=$1
    local dockerfile_path=$2
    
    log_info "开始构建 $module 模块..."
    
    # 进入模块目录
    cd "$module"
    
    # 清理并打包
    log_info "正在编译 $module..."
    mvn clean package -DskipTests -q
    
    if [ $? -ne 0 ]; then
        log_error "$module 编译失败"
        exit 1
    fi
    
    # 复制Dockerfile
    if [ -f "$dockerfile_path" ]; then
        cp "$dockerfile_path" .
    else
        # 创建默认Dockerfile
        create_dockerfile "$module"
    fi
    
    # 构建Docker镜像
    log_info "正在构建 $module Docker镜像..."
    docker build -t "mall/$module:1.0-SNAPSHOT" .
    
    if [ $? -eq 0 ]; then
        log_success "$module 镜像构建成功"
    else
        log_error "$module 镜像构建失败"
        exit 1
    fi
    
    # 清理临时文件
    [ -f "Dockerfile" ] && rm -f Dockerfile
    
    # 返回上级目录
    cd ..
}

# 创建默认Dockerfile
create_dockerfile() {
    local module=$1
    cat > Dockerfile << EOF
# 基于OpenJDK 8
FROM openjdk:8-jre-alpine

# 设置时区
RUN apk add --no-cache tzdata && \\
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \\
    echo "Asia/Shanghai" > /etc/timezone

# 创建应用目录
WORKDIR /app

# 复制jar包
COPY target/$module-1.0-SNAPSHOT.jar app.jar

# 设置JVM参数
ENV JAVA_OPTS="-Xms512m -Xmx1024m -XX:+UseG1GC -XX:+PrintGCDetails -Xloggc:/app/logs/gc.log"

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
}

# 推送镜像到仓库
push_images() {
    local registry=$1
    
    if [ -z "$registry" ]; then
        log_warning "未指定镜像仓库，跳过推送"
        return
    fi
    
    log_info "开始推送镜像到 $registry..."
    
    for module in mall-admin mall-portal mall-search; do
        local local_image="mall/$module:1.0-SNAPSHOT"
        local remote_image="$registry/mall/$module:1.0-SNAPSHOT"
        
        log_info "推送 $module 镜像..."
        docker tag "$local_image" "$remote_image"
        docker push "$remote_image"
        
        if [ $? -eq 0 ]; then
            log_success "$module 镜像推送成功"
        else
            log_error "$module 镜像推送失败"
        fi
    done
}

# 主函数
main() {
    local push_flag=false
    local registry=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --push)
                push_flag=true
                shift
                ;;
            --registry)
                registry="$2"
                shift 2
                ;;
            -h|--help)
                echo "使用方法: $0 [--push] [--registry REGISTRY_URL]"
                echo "  --push              构建完成后推送镜像"
                echo "  --registry URL      指定镜像仓库地址"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    log_info "开始构建Mall项目Docker镜像..."
    
    # 检查环境
    check_docker
    check_maven
    
    # 进入项目根目录
    cd "$(dirname "$0")/../.."
    
    # 构建各个模块
    build_module "mall-admin" "document/sh/Dockerfile"
    build_module "mall-portal" "document/sh/Dockerfile"
    build_module "mall-search" "document/sh/Dockerfile"
    
    log_success "所有镜像构建完成！"
    
    # 显示构建的镜像
    log_info "构建的镜像列表:"
    docker images | grep "mall/"
    
    # 推送镜像（如果需要）
    if [ "$push_flag" = true ]; then
        push_images "$registry"
    fi
    
    log_success "构建脚本执行完成！"
}

# 执行主函数
main "$@"