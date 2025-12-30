# Gravity Genesis 初始化功能

本文档说明了如何使用新的Genesis初始化功能，包括JSON配置文件和Genesis合约的initialize函数调用。

## 功能概述

新的实现包括：
1. **JSON配置文件** - 用于配置Genesis初始化参数
2. **Genesis合约部署** - 部署Genesis合约到预定义地址
3. **Genesis初始化调用** - 调用Genesis合约的initialize函数
4. **参数传递** - 通过main.rs读取配置文件并传递给execute.rs

## 配置文件格式

配置文件 `generate/genesis_config.json` 包含以下参数：

```json
{
  "validatorAddresses": [
    "0x6e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f"
  ],
  "consensusPublicKeys": [
    "851d41932d866f5fabed6673898e15473e6a0adcf5033d2c93816c6b115c85ad3451e0bac61d570d5ed9f23e1e7f77c4"
  ],
  "votingPowers": [
    "1"
  ],
  "validatorNetworkAddresses": [
    "/ip4/127.0.0.1/tcp/2024/noise-ik/2d86b40a1d692c0749a0a0426e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f/handshake/0"
  ],
  "fullnodeNetworkAddresses": [
    "/ip4/127.0.0.1/tcp/2024/noise-ik/2d86b40a1d692c0749a0a0426e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f/handshake/0"
  ],
  "aptosAddresses": [
    "2d86b40a1d692c0749a0a0426e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f"
  ]
}
```

### 参数说明

- **validatorAddresses**: 验证人地址列表(evm address)
- **consensusPublicKeys**: 共识public key
- **votingPowers**: 投票权重列表（字符串格式的U256）
- **validatorNetworkAddresses**: 投票地址列表（十六进制字符串）
- **fullnodeNetworkAddresses**: 投票地址列表（十六进制字符串）
- **aptosAddresses**: Aptos address(32)

## 使用方法

### 1. 准备配置文件

创建或修改 `generate/genesis_config.json` 文件，设置正确的参数值。

### 2. 运行程序

```bash
# 使用默认配置文件
cargo run -- --byte-code-dir ./out

# 指定自定义配置文件
cargo run -- --byte-code-dir ./out --config-file ./my_config.json

# 启用调试日志
cargo run -- --byte-code-dir ./out --debug
```

### 3. 程序执行流程

1. **读取配置** - 从JSON文件读取Genesis配置参数
2. **部署合约** - 按顺序部署所有22个合约
3. **部署Genesis** - 部署Genesis合约
4. **调用初始化** - 调用Genesis合约的initialize函数
5. **生成输出** - 生成genesis_accounts.json和genesis_contracts.json

## 代码结构

### execute.rs 新增功能

1. **GenesisConfig结构体** - 定义配置参数结构
2. **call_genesis_initialize函数** - 构造Genesis初始化调用
3. **修改genesis_generate函数** - 接受配置参数并调用初始化

### main.rs 新增功能

1. **新增命令行参数** - `--config-file` 用于指定配置文件
2. **配置文件读取** - 使用serde_json解析JSON配置
3. **参数传递** - 将配置传递给execute::genesis_generate

## Genesis合约初始化

Genesis合约的initialize函数会：

1. **初始化质押模块** - 调用StakeConfig、ValidatorManager、ValidatorPerformanceTracker的初始化
2. **初始化周期模块** - 调用EpochManager的初始化
3. **初始化治理模块** - 调用GovToken、Timelock、GravityGovernor的初始化
4. **初始化JWK模块** - 调用JWKManager、KeylessAccount的初始化
5. **初始化Block合约** - 调用Block合约的初始化
6. **触发第一个周期** - 调用EpochManager的triggerEpochTransition

## 输出文件

程序会生成两个输出文件：

1. **genesis_accounts.json** - 包含所有账户状态
2. **genesis_contracts.json** - 包含所有合约字节码

## 错误处理

- 配置文件格式错误会显示详细的错误信息
- 合约部署失败会显示具体的交易结果
- Genesis初始化失败会显示详细的错误信息

## 注意事项

1. **地址格式** - 确保所有地址都是有效的以太坊地址格式
2. **数组长度** - 确保所有数组的长度一致
3. **投票权重** - 使用字符串格式的U256数值
4. **投票地址** - 使用十六进制字符串格式

## 示例配置

```json
{
  "validatorAddresses": [
    "0x6e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f"
  ],
  "consensusPublicKeys": [
    "851d41932d866f5fabed6673898e15473e6a0adcf5033d2c93816c6b115c85ad3451e0bac61d570d5ed9f23e1e7f77c4"
  ],
  "votingPowers": [
    "1"
  ],
  "validatorNetworkAddresses": [
    "/ip4/127.0.0.1/tcp/2024/noise-ik/2d86b40a1d692c0749a0a0426e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f/handshake/0"
  ],
  "fullnodeNetworkAddresses": [
    "/ip4/127.0.0.1/tcp/2024/noise-ik/2d86b40a1d692c0749a0a0426e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f/handshake/0"
  ],
  "aptosAddresses": [
    "2d86b40a1d692c0749a0a0426e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f"
  ]
}
``` 