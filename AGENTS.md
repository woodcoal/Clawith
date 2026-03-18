# Clawith 智能体编码指南

本文件为在此代码库中工作的智能体提供指导。

## 项目概述

**Clawith** 是一个开源的多智能体协作平台，基于以下技术栈构建：
- **后端**: Python 3.12+ / FastAPI / SQLAlchemy (async) / PostgreSQL / Redis
- **前端**: React 19 / TypeScript / Vite / Zustand / TanStack Query

## 构建命令

### 后端 (Python)

```bash
cd backend

# 安装依赖（dev 模式包含 pytest、ruff）
pip install -e ".[dev]"

# 使用 ruff 检查代码
ruff check .
ruff check --fix .        # 自动修复

# 使用 ruff 格式化代码
ruff format .

# 运行测试
pytest                    # 运行所有测试
pytest tests/             # 运行指定目录
pytest -xvs tests/test_file.py  # 单文件详细输出
pytest -xvs tests/test_file.py::test_function_name  # 单个测试
pytest -k "test_name"   # 运行匹配模式的测试

# 带覆盖率运行
pytest --cov=app --cov-report=term-missing

# 类型检查（如已安装 mypy）
mypy app/
```

### 前端 (TypeScript/React)

```bash
cd frontend

# 安装依赖
npm install

# 开发服务器（端口 3008）
npm run dev

# 生产构建
npm run build

# 预览生产构建
npm run preview

# 类型检查（通过 Vite）
# TypeScript 在构建时检查 (tsc && vite build)
```

## 代码风格指南

### Python (后端)

**命名规范：**
- 模块/函数/变量：`snake_case`
- 类名：`PascalCase`
- 常量：`UPPER_SNAKE_CASE`
- 私有成员：前缀 `_`（如 `_internal_function`）
- 异步函数：内部使用 `_` 前缀，或使用标准命名

**导入顺序：**
- 标准库导入放最前
- 第三方库导入其次
- 本地/相对导入放最后
- 使用显式相对导入（如 `from app.models.user import User`）
- 各组之间用空行分隔

**错误处理：**
```python
# 尽量少用 try/except，让 FastAPI 处理验证错误
try:
    result = await db.execute(query)
except Exception as e:
    # 记录并重新抛出，带上下文信息
    raise HTTPException(status_code=500, detail="操作失败")
```

**异步模式：**
```python
# 使用 asyncpg 配合 SQLAlchemy 异步
async def get_items(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Item))
    return result.scalars().all()

# 会话始终使用 `async with`
async with _session() as db:
    ...
```

**FastAPI 模式：**
```python
# 使用 Pydantic 进行请求/响应验证
from pydantic import BaseModel

class ItemCreate(BaseModel):
    name: str
    description: str | None = None

@router.post("/", response_model=ItemOut, status_code=201)
async def create_item(data: ItemCreate, db: AsyncSession = Depends(get_db)):
    ...

# 使用 Depends 进行依赖注入（认证、数据库等）
async def get_current_user(user: User = Depends(get_current_user)):
    return user
```

**数据库模式：**
```python
# 使用 select() 而非 query()
from sqlalchemy import select

result = await db.execute(select(User).where(User.id == user_id))
user = result.scalar_one_or_none()

# 显式 flush/commit
await db.flush()  # 在事务内可见
await db.commit() # 持久化到数据库
```

**代码行宽：** 120 字符（ruff 配置）

---

### TypeScript/React (前端)

**命名规范：**
- 变量/函数：`camelCase`
- 组件/接口/类型：`PascalCase`
- 常量：`UPPER_SNAKE_CASE`
- 文件命名：组件用 `PascalCase.tsx`，工具类用 `camelCase.ts`

**导入顺序：**
- React 导入放最前
- 第三方库其次
- 内部导入放最后
- 通过 `@/` 别名使用绝对路径（已在 tsconfig 中配置）

**组件模式：**
```typescript
// 函数组件，显式类型
interface Props {
    title: string;
    onSubmit: (data: FormData) => void;
}

export default function MyComponent({ title, onSubmit }: Props) {
    // Hook 放在顶部
    const [state, setState] = useState<string>('');
    
    // 处理函数
    const handleClick = () => { ... };
    
    return <div>{title}</div>;
}
```

**状态管理 (Zustand)：**
```typescript
// stores/index.ts
import { create } from 'zustand';

interface AuthState {
    token: string | null;
    user: User | null;
    login: (user: User, token: string) => void;
    logout: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
    token: localStorage.getItem('token'),
    user: null,
    login: (user, token) => {
        localStorage.setItem('token', token);
        set({ token, user });
    },
    logout: () => {
        localStorage.remove('token');
        localStorage.remove('user');
        set({ token: null, user: null });
    },
}));
```

**API 层 (api.ts)：**
```typescript
// 集中式 API 服务，带类型
const API_BASE = '/api';

async function request<T>(url: string, options: RequestInit = {}): Promise<T> {
    const res = await fetch(`${API_BASE}${url}`, { ...options, headers });
    if (!res.ok) throw new Error('请求失败');
    return res.json();
}

export const agentApi = {
    list: () => request<Agent[]>('/agents/'),
    get: (id: string) => request<Agent>(`/agents/${id}`),
};
```

**TypeScript 最佳实践：**
- 启用严格模式（已配置）
- 为 props 和返回值使用显式类型
- 避免使用 `any`——使用 proper types 或 `unknown` 配合类型守卫
- 适当使用 TypeScript 工具类型（`Partial<T>`, `Omit<T>`）

---

## 项目结构

```
backend/
├── app/
│   ├── api/          # FastAPI 路由处理（每个资源一个文件）
│   ├── core/         # 认证、安全、事件、中间件
│   ├── models/       # SQLAlchemy ORM 模型
│   ├── schemas/      # Pydantic 请求/响应模式
│   ├── services/     # 业务逻辑、外部集成
│   ├── main.py       # FastAPI 应用入口
│   └── config.py     # 环境配置
frontend/
├── src/
│   ├── pages/        # 路由级页面组件
│   ├── components/   # 可复用 UI 组件
│   ├── stores/       # Zustand 状态管理
│   ├── services/     # API 层
│   ├── types/        # 共享 TypeScript 类型/接口
│   ├── i18n/         # 翻译文件 (en.json, zh.json)
│   └── App.tsx       # 带路由的主应用
```

## 数据库迁移

```bash
# 生成新迁移
alembic revision --autogenerate -m "description"

# 应用迁移
alembic upgrade head

# 回滚
alembic downgrade -1
```

## 环境配置

参见 `.env.example` 获取所需环境变量。关键配置：
- `DATABASE_URL`: PostgreSQL 连接字符串
- `REDIS_URL`: Redis 连接字符串
- `SECRET_KEY`: 应用加密密钥
- `JWT_SECRET_KEY`: JWT 签名密钥

## 测试指南

- **后端**: pytest，`asyncio_mode = "auto"`（已在 pyproject.toml 配置）
- 测试文件放在 `backend/tests/` 目录
- 使用描述性测试名：`test_user_can_login_successfully`
- Mock 外部服务（LLM API、webhooks）
- 使用 fixtures 进行通用设置

## 常见模式

### 添加新 API 端点

1. **后端**：
   - 在 `app/api/*.py` 中添加路由
   - 在 `app/schemas/schemas.py` 创建 Pydantic 模式
   - 需要时在 `app/models/` 添加数据库模型
   - 使用依赖注入进行认证：`current_user: User = Depends(get_current_user)`

2. **前端**：
   - 在 `src/services/api.ts` 添加 API 函数
   - 在 `src/types/index.ts` 添加 TypeScript 接口
   - 在对应目录创建/更新组件

### 认证流程

1. 用户提交凭证 → `/api/auth/login`
2. 后端验证，返回 JWT token 到 `TokenResponse`
3. 前端将 token 存储在 localStorage
4. 后续所有请求包含 `Authorization: Bearer <token>`
5. 后端 `get_current_user` 依赖提取并验证 JWT

## 注意事项

- 所有代码注释应使用**英文**（根据 CONTRIBUTING.md）
- 为所有公共函数和类添加 docstring
- 保持函数小而专注（单一职责）
- 避免过早优化，优先考虑可读性和可维护性
