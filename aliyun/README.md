# Mall项目阿里云容器化部署指南

本指南将帮助您将mall项目完整部署到阿里云上，使用Docker容器化技术。

## 部署架构

### 服务组件
- **mall-admin**: 后台管理系统 (端口: 8080)
- **mall-portal**: 前台商城系统 (端口: 8085)
- **mall-search**: 商品搜索服务 (端口: 8081)
- **MySQL**: 数据库服务 (端口: 3306)
- **Redis**: 缓存服务 (端口: 6379)
- **Elasticsearch**: 搜索引擎 (端口: 9200)
- **RabbitMQ**: 消息队列 (端口: 5672, 15672)
- **MongoDB**: NoSQL数据库 (端口: 27017)
- **Nginx**: 反向代理和负载均衡 (端口: 80, 443)

## 部署前准备

### 1. 阿里云ECS服务器要求
- **推荐配置**: 4核8GB内存，100GB SSD硬盘
- **最低配置**: 2核4GB内存，50GB SSD硬盘
- **操作系统**: CentOS 7.x 或 Ubuntu 18.04+

### 2. 安装Docker和Docker Compose
```bash
# 安装Docker
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
sudo systemctl start docker
sudo systemctl enable docker

# 安装Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### 3. 配置Docker镜像加速
```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://your-aliyun-mirror.mirror.aliyuncs.com"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## 部署步骤

### 1. 克隆项目并进入部署目录
```bash
git clone <your-mall-project-url>
cd mall/deploy/aliyun
```

### 2. 配置环境变量
```bash
cp .env.example .env
# 编辑.env文件，配置数据库密码、域名等信息
vi .env
```

### 3. 创建数据目录
```bash
sudo mkdir -p /data/mall/{mysql,redis,elasticsearch,rabbitmq,mongodb,nginx,logs}
sudo chmod -R 755 /data/mall
```

### 4. 构建应用镜像
```bash
# 在项目根目录执行
./build-images.sh
```

### 5. 启动基础服务
```bash
docker-compose -f docker-compose-infrastructure.yml up -d
```

### 6. 初始化数据库
```bash
# 等待MySQL启动完成后执行
sleep 30
docker exec -i mall-mysql mysql -uroot -p123456 < ../../document/sql/mall.sql
```

### 7. 启动应用服务
```bash
docker-compose -f docker-compose-apps.yml up -d
```

### 8. 配置Nginx反向代理
```bash
docker-compose -f docker-compose-nginx.yml up -d
```

## 监控和维护

### 查看服务状态
```bash
docker-compose ps
docker-compose logs -f [service-name]
```

### 备份数据
```bash
./backup.sh
```

### 更新应用
```bash
./update.sh
```

## 安全配置

### 1. 防火墙设置
```bash
# 只开放必要端口
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw enable
```

### 2. SSL证书配置
- 申请阿里云免费SSL证书
- 将证书文件放置到nginx/ssl目录
- 修改nginx配置启用HTTPS

## 故障排除

### 常见问题
1. **内存不足**: 调整JVM参数或升级服务器配置
2. **端口冲突**: 检查端口占用情况
3. **网络问题**: 检查安全组和防火墙设置
4. **数据库连接失败**: 检查数据库服务状态和连接配置

### 日志查看
```bash
# 查看应用日志
docker logs mall-admin
docker logs mall-portal
docker logs mall-search

# 查看基础服务日志
docker logs mall-mysql
docker logs mall-redis
docker logs mall-elasticsearch
```

## 性能优化

### 1. JVM参数调优
- 根据服务器内存调整堆内存大小
- 启用G1垃圾收集器

### 2. 数据库优化
- 配置MySQL参数
- 创建适当的索引
- 定期清理日志

### 3. 缓存策略
- 合理配置Redis缓存
- 启用应用层缓存

## 扩展部署

### 集群部署
- 使用Docker Swarm或Kubernetes
- 配置负载均衡
- 实现服务发现

### 数据库集群
- MySQL主从复制
- Redis集群
- Elasticsearch集群

联系方式：如有问题请联系运维团队