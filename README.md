# BITBus

北京理工大学班车抢票项目，当前仓库包含两部分：

- 原始 Python/Flask 抢票服务
- 新增的原生 iOS 客户端 `BITBusGrab`

该仓库用于研究北理工班车接口、座位查询与自动抢票流程。iOS 端复刻了核心用户流程，并补充了未签名 IPA 打包脚本与原生图标资源。

## 项目结构

```text
BITBus/
├── api/                          # Python 班车接口封装
├── static/                       # Flask 前端静态资源
├── templates/                    # Flask 页面模板
├── app.py                        # Flask 入口
├── api_client.py                 # Python 业务封装
├── task_manager.py               # Python 抢票任务管理
├── BITBusGrab.xcodeproj/         # iOS 工程
├── ios/
│   ├── Sources/
│   │   ├── App/                  # App 入口与全局状态
│   │   ├── Models/               # 数据模型
│   │   ├── Services/             # API、持久化、通知、任务调度
│   │   ├── Views/                # SwiftUI 页面
│   │   └── Assets.xcassets/      # AppIcon 资源
│   └── Tests/                    # iOS 单元测试
├── project.yml                   # XcodeGen 工程描述
└── scripts/
    ├── build_unsigned_ipa.sh     # 未签名 ipa 打包脚本
    └── generate_app_icon.swift   # App 图标生成脚本
```

## 功能概览

### Python Web 端

- 查询指定日期、线路的班车
- 查看座位占用状态
- 手动选座或自动轮询抢座
- 本地配置保存
- 任务状态跟踪
- 代理捕获凭证

### iOS 客户端

- SwiftUI 原生界面
- 凭证手动配置
- 班车查询
- 座位可视化与优先级设置
- 手动抢票
- 自动抢票任务
- 本地通知提醒

## iOS 端说明

### 当前实现

- 工程名：`BITBusGrab`
- 技术栈：`SwiftUI + Observation + URLSession`
- 打包方式：支持生成未签名 `ipa`
- 图标资源：已补充标准 `AppIcon.appiconset`

### 已知限制

- 原 Flask 版本中的“本机代理抓包”能力无法在 iOS App 内等价实现
- iOS 端当前使用手动录入 `API Host / API Token / API Time / User ID`
- 班车后端接口为 `HTTP` 明文接口，项目已在 iOS 工程里放开 ATS 限制

## 本地运行

### 运行 Python 服务

```bash
pip install -r requirements.txt
python app.py
```

默认访问地址：

```text
http://localhost:23200
```

### 生成 iOS 工程

如果你修改了 `project.yml`，先重新生成工程：

```bash
xcodegen generate
```

### 打开 iOS 工程

```bash
open BITBusGrab.xcodeproj
```

## 测试

### iOS 单元测试

```bash
xcodebuild test \
  -scheme BITBusGrab \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4'
```

当前已覆盖的关键逻辑：

- 请求构造
- 表单编码下单
- 座位信息解析
- 开抢时间计算
- 自动抢票座位优先级排序

## 打包未签名 IPA

直接执行：

```bash
./scripts/build_unsigned_ipa.sh
```

默认输出：

```text
build/BITBusGrab-unsigned.ipa
```

可覆盖参数：

```bash
SCHEME=BITBusGrab \
CONFIGURATION=Release \
OUTPUT_DIR=./dist \
./scripts/build_unsigned_ipa.sh
```

说明：

- 该脚本会关闭代码签名并直接打包 `.app`
- 之后会手动封装为未签名 `.ipa`
- 未签名包不能直接安装到普通设备，可用于后续重签名或归档分发

## 图标资源

App 图标资源位于：

- `ios/Sources/Assets.xcassets/AppIcon.appiconset`

如需重新生成整套图标：

```bash
swift scripts/generate_app_icon.swift ios/Sources/Assets.xcassets/AppIcon.appiconset
```

## 凭证来源

项目调用的班车接口依赖以下信息：

- `API_HOST`
- `API_TOKEN`
- `API_TIME`
- `USER_ID`

请仅在你本人合法可访问的账号环境中使用，并自行承担接口变更、账号限制和使用风险。

## 免责声明

本项目仅用于学习研究、接口分析和个人自动化实践。请遵守学校系统、账号与网络环境的相关规定，不要将本项目用于任何违反管理要求的用途。
