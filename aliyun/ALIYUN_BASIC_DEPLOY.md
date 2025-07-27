# Mall项目阿里云基础部署指南

## 📋 部署概述

本指南将帮助您完成Mall项目在阿里云的第一阶段基础部署，使用以下架构：

- **计算资源**：阿里云ECS（容器化部署）
- **数据库**：阿里云RDS MySQL
- **缓存**：阿里云Redis
- **存储**：阿里云OSS
- **网络**：阿里云VPC
- **权限**：阿里云RAM
- **容器服务**：MongoDB、RabbitMQ、Elasticsearch（自建容器）

## 🛠️ 前置条件

### 已购买的阿里云服务
- ✅ 云服务器ECS（推荐2核4GB以上）
- ✅ 云数据库RDS MySQL版
- ✅ 云数据库Redis版
- ✅ 对象存储OSS
- ✅ 专有网络VPC
- ✅ 访问控制RAM

### ECS环境要求
- 操作系统：CentOS 7+ / Ubuntu 18.04+
- Docker 20.10+
- Docker Compose 1.29+
- Maven 3.6+（如需构建镜像）
- 可用磁盘空间：20GB+
- 内存：4GB+

## 🚀 快速部署

### 1. 环境准备

#### 1.1 安装Docker和Docker Compose

**CentOS/RHEL:**
```bash
# 安装Docker
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io
sudo systemctl start docker
sudo systemctl enable docker

# 安装Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

**Ubuntu/Debian:**
```bash
# 安装Docker
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# 安装Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

#### 1.2 配置Docker镜像加速

```bash
# 配置阿里云镜像加速器
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://your-accelerator.mirror.aliyuncs.com"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 2. 项目部署

#### 2.1 克隆项目

```bash
# 克隆项目到ECS
git clone https://github.com/your-username/mall.git
cd mall/deploy/aliyun
```

#### 2.2 配置环境变量

```bash
# 复制环境变量模板
cp .env.aliyun .env.aliyun.local

# 编辑配置文件
vim .env.aliyun.local
```

**重要配置项：**
```bash
# 阿里云RDS MySQL配置
ALIYUN_RDS_HOST=rm-xxxxxxxxx.mysql.rds.aliyuncs.com
MYSQL_USER=your_mysql_user
MYSQL_PASSWORD=your_mysql_password

# 阿里云Redis配置
ALIYUN_REDIS_HOST=r-xxxxxxxxx.redis.rds.aliyuncs.com
REDIS_PASSWORD=your_redis_password

# 阿里云OSS配置
ALIYUN_OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com
ALIYUN_OSS_ACCESS_KEY_ID=your_access_key_id
ALIYUN_OSS_ACCESS_KEY_SECRET=your_access_key_secret
ALIYUN_OSS_BUCKET_NAME=your_bucket_name

# 域名配置
DOMAIN_NAME=yourdomain.com
ADMIN_DOMAIN=admin.yourdomain.com
PORTAL_DOMAIN=portal.yourdomain.com
```

#### 2.3 配置安全组

在阿里云控制台配置ECS安全组，开放以下端口：

| 端口 | 协议 | 用途 |
|------|------|------|
| 22 | TCP | SSH访问 |
| 80 | TCP | HTTP访问 |
| 443 | TCP | HTTPS访问 |
| 8080 | TCP | 管理后台 |
| 8081 | TCP | 搜索服务 |
| 8085 | TCP | 前台门户 |
| 9200 | TCP | Elasticsearch |
| 15672 | TCP | RabbitMQ管理 |

#### 2.4 一键部署

```bash
# 完整部署（包含构建）
./deploy-aliyun-basic.sh

# 或者跳过构建（如果已有镜像）
./deploy-aliyun-basic.sh --skip-build

# 查看部署选项
./deploy-aliyun-basic.sh --help
```

### 3. 验证部署

#### 3.1 检查服务状态

```bash
# 查看所有服务状态
docker-compose -f docker-compose-aliyun-basic.yml ps

# 查看服务日志
docker-compose -f docker-compose-aliyun-basic.yml logs -f mall-admin
docker-compose -f docker-compose-aliyun-basic.yml logs -f mall-portal
docker-compose -f docker-compose-aliyun-basic.yml logs -f mall-search
```

#### 3.2 访问应用

- **管理后台**: http://your-ecs-ip:8080
- **前台门户**: http://your-ecs-ip:8085
- **搜索服务**: http://your-ecs-ip:8081
- **RabbitMQ管理**: http://your-ecs-ip:15672
- **Elasticsearch**: http://your-ecs-ip:9200

#### 3.3 健康检查

```bash
# 检查应用健康状态
curl http://localhost:8080/actuator/health
curl http://localhost:8085/actuator/health
curl http://localhost:8081/actuator/health

# 检查Elasticsearch
curl http://localhost:9200/_cluster/health

# 检查RabbitMQ
curl http://localhost:15672/api/overview
```

## 🔧 常用操作

### 服务管理

```bash
# 启动所有服务
docker-compose -f docker-compose-aliyun-basic.yml up -d

# 停止所有服务
docker-compose -f docker-compose-aliyun-basic.yml down

# 重启特定服务
docker-compose -f docker-compose-aliyun-basic.yml restart mall-admin

# 查看服务日志
docker-compose -f docker-compose-aliyun-basic.yml logs -f mall-portal

# 进入容器
docker-compose -f docker-compose-aliyun-basic.yml exec mall-admin bash
```

### 数据备份

```bash
# 备份MongoDB
docker exec mall-mongodb mongodump --out /data/db/backup/$(date +%Y%m%d)

# 备份RDS MySQL（需要在ECS上安装MySQL客户端）
mysqldump -h$ALIYUN_RDS_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE > backup_$(date +%Y%m%d).sql
```

### 应用更新

```bash
# 更新应用代码
git pull origin main

# 重新构建镜像
./deploy-aliyun-basic.sh --clean

# 或者仅重启应用服务
docker-compose -f docker-compose-aliyun-basic.yml restart mall-admin mall-portal mall-search
```

## 🛡️ 安全配置

### 1. 防火墙配置

```bash
# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload

# Ubuntu/Debian
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### 2. SSL证书配置

```bash
# 申请Let's Encrypt证书
sudo yum install -y certbot
sudo certbot certonly --standalone -d yourdomain.com -d admin.yourdomain.com

# 复制证书到数据目录
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem /data/mall/ssl/cert.pem
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem /data/mall/ssl/key.pem
sudo chown $USER:$USER /data/mall/ssl/*
```

### 3. 定期备份

```bash
# 创建备份脚本
crontab -e

# 添加定时任务（每天凌晨2点备份）
0 2 * * * /path/to/backup-script.sh
```

## 📊 监控配置

### 1. 系统监控

```bash
# 安装监控工具
sudo yum install -y htop iotop nethogs

# 查看系统资源
htop
docker stats
df -h
```

### 2. 日志监控

```bash
# 查看应用日志
tail -f /data/mall/logs/mall-admin/application.log
tail -f /data/mall/logs/mall-portal/application.log

# 查看Nginx日志
tail -f /data/mall/logs/nginx/access.log
tail -f /data/mall/logs/nginx/error.log
```

## 🔍 故障排除

### 常见问题

1. **容器启动失败**
   ```bash
   # 查看容器日志
   docker logs mall-admin
   
   # 检查端口占用
   netstat -tlnp | grep :8080
   ```

2. **数据库连接失败**
   ```bash
   # 测试RDS连接
   mysql -h$ALIYUN_RDS_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD
   
   # 检查安全组配置
   # 确保ECS可以访问RDS的3306端口
   ```

3. **Redis连接失败**
   ```bash
   # 测试Redis连接
   redis-cli -h $ALIYUN_REDIS_HOST -p 6379 -a $REDIS_PASSWORD ping
   ```

4. **OSS访问失败**
   ```bash
   # 检查OSS配置
   # 确保AccessKey有OSS访问权限
   # 检查Bucket策略设置
   ```

### 性能优化

1. **JVM调优**
   ```bash
   # 修改.env.aliyun中的JVM参数
   JAVA_OPTS_ADMIN=-Xms1g -Xmx2g -XX:+UseG1GC
   ```

2. **数据库优化**
   - 配置RDS参数组
   - 启用慢查询日志
   - 配置读写分离

3. **缓存优化**
   - 配置Redis持久化
   - 设置合适的过期策略
   - 监控缓存命中率

## 📞 技术支持

如果在部署过程中遇到问题，请：

1. 查看详细的错误日志
2. 检查网络连接和安全组配置
3. 确认阿里云服务配置正确
4. 参考故障排除章节

## 🔄 下一步

完成基础部署后，建议进行以下优化：

1. **配置域名和SSL证书**
2. **设置负载均衡ALB**
3. **配置CDN加速**
4. **集成监控告警**
5. **设置自动备份**
6. **性能调优**

---

**恭喜！您已成功完成Mall项目的阿里云基础部署！** 🎉