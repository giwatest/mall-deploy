# Mall Admin 阿里云直接部署指南

本指南将帮助您在阿里云ECS服务器上直接部署Mall Admin服务，无需使用Docker容器。

## 🚀 快速开始

### 1. 服务器环境要求

- **操作系统**: CentOS 7+ 或 Ubuntu 18.04+
- **配置**: 最低2核4GB，推荐4核8GB
- **Java**: OpenJDK 8 或 Oracle JDK 8+
- **Maven**: 3.6+（如果需要构建）
- **MySQL客户端**: 用于数据库初始化

### 2. 阿里云资源准备

确保您已经创建并配置了以下阿里云资源：

- ✅ **ECS服务器**: 已安装Java 8+
- ✅ **RDS MySQL实例**: 已创建数据库和用户
- ✅ **Redis实例**: 已配置访问密码
- ✅ **OSS存储桶**: 已配置访问密钥
- ✅ **安全组**: 已开放8080端口

### 3. 部署步骤

#### 步骤1: 登录服务器并安装依赖

```bash
# 登录ECS服务器
ssh root@your-server-ip

# 安装Java 8 (CentOS)
sudo yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel

# 安装Java 8 (Ubuntu)
sudo apt update
sudo apt install -y openjdk-8-jdk

# 安装Maven (如果需要构建)
sudo yum install -y maven  # CentOS
sudo apt install -y maven  # Ubuntu

# 安装MySQL客户端
sudo yum install -y mysql  # CentOS
sudo apt install -y mysql-client  # Ubuntu

# 验证安装
java -version
mvn -version
mysql --version
```

#### 步骤2: 克隆项目代码

```bash
# 克隆项目
git clone https://github.com/giwatest/mall.git
cd mall/deploy/aliyun

# 检查部署脚本
ls -la deploy-admin-direct.sh
```

#### 步骤3: 配置环境变量

编辑 `.env.aliyun` 文件，确保以下配置正确：

```bash
vi .env.aliyun
```

**必须配置的关键参数**：

```bash
# RDS MySQL配置
ALIYUN_RDS_HOST=rm-xxxxxxxxx.mysql.rds.aliyuncs.com
MYSQL_USER=your_mysql_user
MYSQL_PASSWORD="your_mysql_password"
MYSQL_DATABASE=mall

# Redis配置
ALIYUN_REDIS_HOST=r-xxxxxxxxx.redis.rds.aliyuncs.com
REDIS_PASSWORD=your_redis_password

# OSS配置
ALIYUN_OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com
ALIYUN_OSS_ACCESS_KEY_ID=your_access_key_id
ALIYUN_OSS_ACCESS_KEY_SECRET=your_access_key_secret
ALIYUN_OSS_BUCKET_NAME=your_bucket_name

# 安全配置
JWT_SECRET=your_jwt_secret_key_here_32_chars_min
DRUID_PASSWORD=your_druid_admin_password
```

#### 步骤4: 执行一键部署

```bash
# 完整部署（包含构建、数据库初始化、服务启动）
./deploy-admin-direct.sh

# 如果已有JAR文件，跳过构建
./deploy-admin-direct.sh --skip-build

# 如果数据库已初始化，跳过数据库初始化
./deploy-admin-direct.sh --skip-db-init

# 查看详细输出
./deploy-admin-direct.sh --verbose
```

#### 步骤5: 验证部署

```bash
# 查看服务状态
./deploy-admin-direct.sh --status

# 查看服务日志
sudo journalctl -u mall-admin -f

# 检查端口监听
netstat -tlnp | grep :8080

# 测试API接口
curl http://localhost:8080/actuator/health
```

## 📱 访问应用

部署成功后，您可以通过以下地址访问：

- **管理后台**: http://your-server-ip:8080/index.html
- **API文档**: http://your-server-ip:8080/swagger-ui.html
- **数据库监控**: http://your-server-ip:8080/druid
- **健康检查**: http://your-server-ip:8080/actuator/health

### 默认登录信息

- **用户名**: admin
- **密码**: macro123

## 🔧 服务管理

### 启动/停止/重启服务

```bash
# 停止服务
./deploy-admin-direct.sh --stop

# 启动服务
sudo systemctl start mall-admin

# 重启服务
./deploy-admin-direct.sh --restart

# 查看状态
./deploy-admin-direct.sh --status
```

### 查看日志

```bash
# 查看实时日志
sudo journalctl -u mall-admin -f

# 查看应用日志
tail -f /var/log/mall/mall-admin.log

# 查看最近的错误日志
sudo journalctl -u mall-admin --since "1 hour ago" | grep ERROR
```

### 更新应用

```bash
# 拉取最新代码
git pull origin master

# 重新构建和部署
./deploy-admin-direct.sh --clean
```

## 🔍 故障排除

### 常见问题

#### 1. 服务启动失败

```bash
# 查看详细错误信息
sudo journalctl -u mall-admin --no-pager

# 检查配置文件
cat /etc/mall/application-prod.yml

# 检查JAR文件
ls -la /opt/mall/mall-admin.jar
```

#### 2. 数据库连接失败

```bash
# 测试数据库连接
mysql -h"$ALIYUN_RDS_HOST" -P"$ALIYUN_RDS_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1"

# 检查网络连通性
telnet $ALIYUN_RDS_HOST $ALIYUN_RDS_PORT

# 检查安全组规则
# 确保ECS可以访问RDS的3306端口
```

#### 3. Redis连接失败

```bash
# 测试Redis连接
redis-cli -h $ALIYUN_REDIS_HOST -p $ALIYUN_REDIS_PORT -a $REDIS_PASSWORD ping

# 检查Redis配置
echo "CONFIG GET requirepass" | redis-cli -h $ALIYUN_REDIS_HOST -p $ALIYUN_REDIS_PORT -a $REDIS_PASSWORD
```

#### 4. 内存不足

```bash
# 查看内存使用
free -h

# 调整JVM参数
vi .env.aliyun
# 修改 JAVA_OPTS_ADMIN="-Xms512m -Xmx1g ..."

# 重启服务
./deploy-admin-direct.sh --restart
```

#### 5. 端口被占用

```bash
# 查看端口占用
netstat -tlnp | grep :8080

# 杀死占用进程
sudo kill -9 <PID>

# 或修改应用端口
vi /etc/mall/application-prod.yml
# 修改 server.port: 8081
```

## 🔒 安全配置

### 防火墙设置

```bash
# CentOS 7 (firewalld)
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

# Ubuntu (ufw)
sudo ufw allow 8080/tcp
sudo ufw reload

# 或者使用iptables
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
sudo iptables-save
```

### SSL/HTTPS配置

如需配置HTTPS，建议使用Nginx作为反向代理：

```bash
# 安装Nginx
sudo yum install -y nginx  # CentOS
sudo apt install -y nginx  # Ubuntu

# 配置反向代理
sudo vi /etc/nginx/conf.d/mall-admin.conf
```

## 📊 监控和维护

### 系统监控

```bash
# 查看系统资源
top
htop
iotop

# 查看磁盘使用
df -h
du -sh /opt/mall
du -sh /var/log/mall

# 查看网络连接
netstat -an | grep :8080
ss -tlnp | grep :8080
```

### 日志轮转

```bash
# 配置logrotate
sudo vi /etc/logrotate.d/mall-admin

# 内容示例：
/var/log/mall/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 $USER $USER
    postrotate
        sudo systemctl reload mall-admin
    endscript
}
```

### 定期备份

```bash
# 创建备份脚本
sudo vi /usr/local/bin/backup-mall.sh

# 添加到crontab
crontab -e
# 每天凌晨2点备份
0 2 * * * /usr/local/bin/backup-mall.sh
```

## 📞 技术支持

如果遇到问题，请：

1. 查看本文档的故障排除部分
2. 检查应用日志和系统日志
3. 确认阿里云资源配置正确
4. 联系技术支持团队

---

**部署脚本位置**: `deploy/aliyun/deploy-admin-direct.sh`  
**配置文件位置**: `deploy/aliyun/.env.aliyun`  
**文档更新时间**: 2024年1月