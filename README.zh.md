# AI Data Assistant

[English](README.md)

一款原生 macOS 应用，通过 AI 驱动的自然语言查询数据库。无需编写 SQL，用日常语言即可查询数据。

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## ✨ 功能特性

- 🗣️ **自然语言查询** - 用日常语言提问，获取 SQL 结果
- 🤖 **AI 驱动** - 集成 AWS Bedrock (Claude 3.5/4.5) 智能生成 SQL
- 💾 **多数据库支持** - 支持 SQLite、MySQL、PostgreSQL、DuckDB
- 📊 **智能结果展示** - 清晰的表格呈现查询结果
- 💡 **查询解释** - AI 自动解释生成的 SQL 查询
- 🔍 **Schema 浏览器** - 可视化数据库结构
- ⚡ **直接 SQL 模式** - 可切换自然语言和原生 SQL 输入

## 📸 截图

### 数据库配置
![数据库配置](Screenshot/db_config_01.png)
![数据库配置详情](Screenshot/db_config_02.png)

### AWS Bedrock 配置
![Bedrock 配置](Screenshot/bedrock_config.png)

### 查询界面
![SQL 查询](Screenshot/sql_query.png)
![AI 增强查询](Screenshot/ai_enhanced.png)

### 连接设置
![配置](Screenshot/config.png)

## 🛠 技术栈

| 组件 | 技术 |
|------|------|
| 语言 | Swift 5.9+ |
| UI 框架 | SwiftUI |
| 平台 | macOS 14.0+ (Sonoma) |
| 数据库 | SQLite, MySQL, DuckDB |
| AI 服务 | AWS Bedrock (Claude 3.5) |
| 架构 | MVVM + 面向协议编程 |

## 🚀 快速开始

### 前置要求

- macOS 14.0 或更高版本
- Xcode 15.0 或更高版本
- 具有 Bedrock 访问权限的 AWS 账户
- 一个待查询的数据库（SQLite、MySQL 或 DuckDB）

### 安装

1. **克隆仓库**
   ```bash
   git clone https://github.com/yourusername/AIDataAssistant.git
   cd AIDataAssistant
   ```

2. **在 Xcode 中打开**
   ```bash
   open AIDataAssistant.xcodeproj
   ```

3. **构建并运行**
   - 选择 `AIDataAssistant` scheme
   - 按 `⌘R` 运行

### 配置

1. 启动应用，点击 **"添加连接"**
2. 配置数据库：
   - **SQLite**：浏览选择 `.db` 文件
   - **MySQL**：输入主机、端口、用户名、密码和数据库名
   - **DuckDB**：选择内存或文件模式，可附加 Parquet/CSV/JSON 文件
3. 配置 AWS Bedrock：
   - 输入 AWS 区域（如 `us-east-1`）
   - 输入 AWS Access Key ID 和 Secret Access Key
   - 选择 AI 模型（推荐：Claude 3.5 Sonnet）
4. 点击 **"连接"**

## 💬 使用示例

连接成功后，尝试这些自然语言查询：

```
"显示所有用户"
"上周有多少订单？"
"销售额最高的 10 个产品"
"列出 30 天内未下单的客户"
"每个类别的平均订单金额"
```

## 🏗 项目结构

```
AIDataAssistant/
├── Sources/Core/           # 核心库
│   ├── Models/             # 数据模型
│   ├── Database/           # 数据库适配器
│   ├── AI/                 # AI 服务集成
│   └── QueryEngine/        # 查询处理引擎
├── AIDataAssistantApp/     # macOS 应用
│   ├── Views/              # SwiftUI 视图
│   └── Assets.xcassets/    # 应用资源
└── Tests/                  # 单元测试
```

## 🔧 开发

### 构建
```bash
swift build
```

### 测试
```bash
swift test
```

## 📋 路线图

- [x] SQLite 支持
- [x] MySQL 支持
- [x] DuckDB 支持
- [ ] PostgreSQL 支持
- [ ] OpenAI 集成
- [ ] Google Gemini 集成
- [ ] 数据可视化
- [ ] 导出结果到 CSV/Excel

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 🤝 贡献

欢迎贡献！请随时提交 Pull Request。

## 📧 联系方式

如有问题，请在 GitHub 上 [提交 Issue](https://github.com/yourusername/AIDataAssistant/issues)。

