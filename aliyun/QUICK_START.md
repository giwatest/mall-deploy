# Mall项目阿里云部署快速开始指南

## 🚀 一键部署

### 1. 环境准备

确保您的阿里云ECS服务器满足以下要求：
- **操作系统**: CentOS 7+ 或 Ubuntu 18.04+
- **配置**: 最低2核4GB，推荐4核8GB
- **磁盘**: 至少50GB可用空间
- **网络**: 已配置安全组，开放80、443端口

### 2. 安装Docker环境

```bash
# 安装Docker
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
sudo systemctl start docker
sudo systemctl enable docker

# 安装Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 配置Docker镜像加速（替换为您的阿里云镜像加速地址）
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://your-mirror.mirror.aliyuncs.com"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 3. 克隆项目并配置

```bash
# 克隆项目（替换为您的项目地址）
git clone <your-mall-project-url>
cd mall/deploy/aliyun

# 复制并编辑环境配置
cp .env.example .env
vi .env  # 修改数据库密码、域名等配置
```

### 4. 一键部署

```bash
# 完整部署（包含构建镜像、启动服务、初始化数据库）
./deploy.sh

# 如果已有镜像，可跳过构建步骤
./deploy.sh --skip-build

# 如果数据库已初始化，可跳过数据库初始化
./deploy.sh --skip-db-init
```

## 📋 常用操作

### 服务管理

```bash
# 查看服务状态
docker-compose ps

# 查看服务日志
docker-compose logs -f mall-admin
docker-compose logs -f mall-portal
docker-compose logs -f mall-search

# 重启服务
docker-compose restart mall-admin

# 停止所有服务
docker-compose down

# 启动所有服务
docker-compose up -d
```

### 应用更新

```bash
# 更新所有应用
./update.sh

# 更新指定应用
./update.sh --service mall-admin

# 更新前自动备份
./update.sh --backup
```

### 数据备份

```bash
# 完整备份
./backup.sh

# 仅备份数据库
./backup.sh --type mysql

# 设置备份保留天数
./backup.sh --retention 30
```

### 系统监控

```bash
# 启动持续监控
./monitor.sh

# 一次性检查
./monitor.sh --once

# 启用告警功能
./monitor.sh --alert
```

## 🔧 配置说明

### 环境变量配置 (.env)

```bash
# 必须修改的配置
MYSQL_ROOT_PASSWORD=your-strong-password
REDIS_PASSWORD=your-redis-password
DOMAIN_NAME=your-domain.com
ADMIN_DOMAIN=admin.your-domain.com

# 可选配置
ALIYUN_OSS_ACCESS_KEY_ID=your-access-key
ALIYUN_OSS_ACCESS_KEY_SECRET=your-secret-key
```

### SSL证书配置

1. 申请阿里云免费SSL证书
2. 下载证书文件
3. 将证书文件放置到 `nginx/ssl/` 目录
4. 修改nginx配置中的证书路径

### 域名解析

在阿里云DNS控制台添加以下解析记录：
- `your-domain.com` → 服务器IP
- `admin.your-domain.com` → 服务器IP
- `api.your-domain.com` → 服务器IP

## 🌐 访问地址

部署完成后，您可以通过以下地址访问：

- **前台商城**: https://your-domain.com
- **后台管理**: https://admin.your-domain.com
- **API文档**: https://api.your-domain.com/swagger-ui.html
- **RabbitMQ管理**: http://服务器IP:15672
- **Elasticsearch**: http://服务器IP:9200

## 🔍 故障排除

### 常见问题

1. **容器启动失败**
   ```bash
   # 查看容器日志
   docker logs container-name
   
   # 检查端口占用
   netstat -tlnp | grep :8080
   ```

2. **内存不足**
   ```bash
   # 查看内存使用
   free -h
   
   # 调整JVM参数
   vi .env  # 修改JAVA_OPTS
   ```

3. **网络连接问题**
   ```bash
   # 检查防火墙
   sudo ufw status
   
   # 检查安全组配置
   # 在阿里云控制台检查ECS安全组规则
   ```

4. **数据库连接失败**
   ```bash
   # 检查MySQL状态
   docker exec mall-mysql mysqladmin ping
   
   # 重置数据库密码
   docker exec -it mall-mysql mysql -uroot -p
   ```

### 日志查看

```bash
# 应用日志
tail -f /data/mall/logs/mall-admin/app.log
tail -f /data/mall/logs/mall-portal/app.log

# 系统日志
journalctl -u docker -f

# Nginx日志
tail -f /data/mall/logs/nginx/access.log
tail -f /data/mall/logs/nginx/error.log
```

## 📞 技术支持

如果在部署过程中遇到问题，请：

1. 查看相关日志文件
2. 检查系统资源使用情况
3. 确认网络和防火墙配置
4. 联系技术支持团队

## 📚 相关文档

- [完整部署文档](README.md)
- [Docker官方文档](https://docs.docker.com/)
- [阿里云ECS文档](https://help.aliyun.com/product/25365.html)
- [Mall项目文档](../../README.md)

---

**注意**: 请确保在生产环境中使用强密码，并定期更新系统和应用程序。