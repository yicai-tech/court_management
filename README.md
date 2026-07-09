# 球场管理与推荐系统

这是一个球场管理与推荐网站/应用的初始工程骨架，基于 Vue 3 + Vite 前端，Node.js + Express 后端。

## 目录结构

- `frontend/`：Vue 3 前端应用
- `backend/`：Express REST API

## 功能目标

- 球场浏览与搜索
- 推荐场地
- 用户登录 / 注册
- 场地预约与支付模拟
- 场地评价与评论系统
- MySQL / MongoDB 真实数据库支持
- 用户个人中心与预约历史
- Capacitor 跨平台移动应用集成

## 数据库配置

1. 复制 `.env.example` 到 `backend/.env`
2. 设置 `DB_TYPE=mongodb` 或 `DB_TYPE=mysql`
3. 如果使用 MongoDB，设置 `MONGO_URI`
4. 如果使用 MySQL，设置 `MYSQL_HOST`、`MYSQL_DATABASE`、`MYSQL_USER`、`MYSQL_PASSWORD`

## 后台管理员

系统会自动生成一个管理员账户：
- 用户名：`admin`
- 密码：`admin123`

登录后可访问 `后台管理` 页面，实现：
- 新增 / 删除球场
- 管理用户角色（user / admin）
- 查看所有预约订单

## 快速启动

1. 安装后端依赖
   ```bash
   cd court-management/backend
   npm install
   ```
2. 启动后端
   ```bash
   npm run dev
   ```
3. 安装前端依赖
   ```bash
   cd ../frontend
   npm install
   ```
4. 启动前端
   ```bash
   npm run dev
   ```

## CentOS 一键部署

仓库根目录提供最终版脚本 `deploy.sh`，包含：

- 清理旧依赖（可关闭）
- MySQL 建库与导入教练相关建表 SQL
- 后端依赖安装 + `db:sync`
- 前端依赖安装 + 构建
- 可选自动启动后端并健康检查

示例：

```bash
cd court-management
chmod +x deploy.sh
DB_PASSWORD='your_db_password' MYSQL_ROOT_PASSWORD='your_mysql_root_password' START_BACKEND=1 bash deploy.sh
```

常用参数：

- `DEPLOY_MODE=all|backend|frontend`
- `CLEAN_INSTALL=1|0`（默认 1）
- `START_BACKEND=1|0`（默认 0）
- `CHECK_HEALTH=1|0`（默认 1）
- `BACKEND_PORT=4000`

## 跨平台移动应用

1. 安装 Capacitor 依赖后端
   ```bash
   cd court-management/frontend
   npm install
   ```
2. 构建前端并同步到 Capacitor
   ```bash
   npm run build
   npm run cap:sync
   ```
3. 添加 Android 或 iOS 平台
   ```bash
   npm run cap:add:android
   npm run cap:add:ios
   ```
4. 打开原生工作区
   ```bash
   npm run cap:open:android
   npm run cap:open:ios
   ```
