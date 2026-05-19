# 考虑RGV运输的柔性作业车间调度优化

## 项目简介

本项目针对**考虑RGV（有轨制导小车）运输与夹具约束的柔性作业车间调度问题（FJSP-RGV）**，以最小化最大完工时间（Makespan）为优化目标，设计并实现了多种智能优化算法进行求解与对比。

## 问题描述

在柔性作业车间中，每个工件包含多道工序，每道工序可在多台可选机器上加工。此外：

- **RGV运输**：工件在机器间的转移由RGV完成，需考虑运输时间
- **夹具约束**：加工需使用特定类型夹具，夹具数量有限，需调度分配
- **线边布局**：机器分布在两条线边，RGV在通道中双向移动

## 算法实现

本项目实现了以下五种算法：

| 算法 | 文件 | 说明 |
|------|------|------|
| **GA-VNS** | `ga_vns_main.m` | 混合遗传-变邻域搜索算法（本文核心算法），结合自适应参数调节与5种邻域结构 |
| **GA** | `ga_standard.m` | 标准遗传算法（基准对比） |
| **SA** | `sa_solver.m` | 模拟退火算法 |
| **PSO** | `pso_solver.m` | 离散粒子群优化算法 |
| **TS** | `ts_solver.m` | 禁忌搜索算法 |

### VNS邻域结构（5种）

1. 交换同一工件内两道工序的顺序
2. 交换不同工件的两道工序
3. 将一道工序插入到另一位置
4. 随机改变一道工序的加工机器
5. 改变一道工序的夹具选择

## 项目结构

```
.
├── main.m                          # 主程序入口（单算例多算法对比+可视化）
├── ga_vns_main.m                   # GA-VNS混合算法主循环
├── ga_standard.m                   # 标准遗传算法
├── sa_solver.m                     # 模拟退火求解器
├── pso_solver.m                    # 离散粒子群求解器
├── ts_solver.m                     # 禁忌搜索求解器
├── variable_neighborhood_search.m  # VNS变邻域搜索
├── init_population.m               # 种群初始化（编码与解码）
├── crossover.m                     # 交叉操作
├── mutation.m                      # 变异操作
├── decode_makespan.m               # 解码（不考虑RGV）
├── decode_makespan2.m              # 解码（考虑RGV运输）
├── read_production_data.m          # 读取算例数据
├── create_layout_info.m            # 车间布局信息
├── get_distance_wrapper.m          # 机器间距离计算
├── get_operation_info.m            # 工序信息提取
├── get_job_op.m                    # 工件-工序索引
├── get_job_operation_info.m        # 工件工序信息
├── plot_gantt_with_rgv.m           # 甘特图绘制（含RGV运输）
├── analyze_rgv.m                   # RGV运输统计分析
├── get_rgv_speed_factor.m          # RGV速度因子
├── run_algorithm_comparison.m      # 多算法对比实验（统计重复）
├── run_batch_benchmark.m           # 批量算例对比实验
├── run_neighborhood_ablation.m     # 邻域结构消融实验
├── mk01-A.txt ~ mk10-C.txt         # MK系列基准算例（30个）
├── mfjs01-A.txt ~ mfjs10-C.txt     # MFJS系列扩展算例（30个）
└── benchmark_results/              # 实验结果输出目录
    ├── summary_*.csv               # 结果汇总表
    ├── wide_*.csv                  # 宽表格式结果
    └── convergence_*.png           # 收敛曲线图
```

## 快速开始

### 环境要求

- MATLAB R2020a 或更高版本
- 无需额外工具箱

### 运行单算例对比

1. 打开 `main.m`
2. 修改 `filename` 变量指定算例文件（如 `'mk01-A.txt'`）
3. 运行脚本，将依次执行GA-VNS、GA、SA、PSO、TS五种算法，并绘制：
   - 多算法迭代收敛曲线对比图
   - 最终Makespan柱状图
   - GA-VNS最优解的甘特图（含RGV运输轨迹）

### 运行批量实验

```matlab
% 默认配置（所有算例，每种算法5次独立重复）
res = run_batch_benchmark();

% 指定算例
res = run_batch_benchmark('instances', {'mk01-A', 'mk01-B'});

% 自定义参数
res = run_batch_benchmark('num_runs', 10, 'max_gen', 150, 'pop_size', 100);
```

### 运行消融实验

```matlab
% 验证各邻域结构的贡献
res = run_neighborhood_ablation('filename', 'mk01-A.txt', 'num_runs', 10);
```

## 算例说明

- **MK系列**（`mkXX-Y.txt`）：Brandimarte标准FJSP基准算例，共10组(A/B/C)，每组3个变体，含10个工件、6台机器
- **MFJS系列**（`mfjsXX-Y.txt`）：扩展算例，10组(A/B/C)，每组3个变体

算例文件格式：
- 第1行：工件数 机器数 夹具类型数
- `#machine`行：各工件的可选机器及加工时间
- `#fixture`行：各工件的夹具需求及装卸时间

## 实验结果

在MK系列算例上，GA-VNS算法相比GA、SA、PSO、TS四种传统算法在Makespan指标上均有显著提升，验证了混合策略与VNS邻域搜索的有效性。详细结果见 `benchmark_results/` 目录。
