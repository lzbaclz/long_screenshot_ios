# 长截图核心算法合成基准报告

**证据类型：确定性合成灰度测试，不是 G1 实机验收、用户测试或兼容性通过记录。**

- 生成时间：2026-09-13T22:49:42Z
- 夹具版本：1
- 运行系统：Version 15.7.8 (Build 24G824)
- 通过：120 / 120；失败：0
- 常规：90；压力：30；处理帧数：3730
- 总耗时：5224.793 ms；其中匹配：4877.873 ms

常规用例为 6 类画布 × 5 / 10 / 20 屏深度 × 5 种滚动、裁剪或回退方式。压力用例覆盖周期歧义、断层后恢复、新场景、尺寸变化、重叠不足和低对比度歧义。预期拒绝属于通过条件。

输出逐像素与独立生成的原始画布前缀比较；FNV-1a 64 位指纹便于复核，不用于安全校验。每帧预期/实际位置、条带行、置信度、拒绝原因和时间在同目录 report.json。

分类说明：complete 表示序列没有拒绝；rejected 表示至少一次非歧义拒绝（可能随后恢复）；ambiguous 表示至少一次歧义拒绝。分类不是质量分数，应结合通过列与逐像素一致性。

本机时间不代表 iPhone 性能；未测 ReplayKit、内存、耗电、真实页面加载、透明导航栏或视觉接缝。120 项是受控参数组合，不是独立现实样本，通过比例不能估计真实成功率。总耗时涵盖夹具生成和验证，不含编译和报告落盘。

| 用例 | 组 / 图案 / 方式 | 深度 | 帧 | 预期 / 实际分类 | 预期 / 实际保留行 | 像素一致 | 通过 | 最慢帧 ms |
| --- | --- | ---: | ---: | --- | ---: | --- | --- | ---: |
| core-001 | core / texture / steady | 5 | 11 | complete / complete | 900 / 900 | 是 | 通过 | 1.353 |
| core-002 | core / texture / odd_steps | 5 | 13 | complete / complete | 900 / 900 | 是 | 通过 | 1.422 |
| core-003 | core / texture / fixed_bars | 5 | 10 | complete / complete | 900 / 900 | 是 | 通过 | 2.107 |
| core-004 | core / texture / short_reversals | 5 | 17 | complete / complete | 900 / 900 | 是 | 通过 | 1.475 |
| core-005 | core / texture / pause_reverse_bars | 5 | 21 | complete / complete | 900 / 900 | 是 | 通过 | 1.424 |
| core-006 | core / texture / steady | 10 | 24 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.342 |
| core-007 | core / texture / odd_steps | 10 | 28 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.334 |
| core-008 | core / texture / fixed_bars | 10 | 20 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.331 |
| core-009 | core / texture / short_reversals | 10 | 37 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.577 |
| core-010 | core / texture / pause_reverse_bars | 10 | 51 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.449 |
| core-011 | core / texture / steady | 20 | 48 | complete / complete | 3600 / 3600 | 是 | 通过 | 1.443 |
| core-012 | core / texture / odd_steps | 20 | 58 | complete / complete | 3600 / 3600 | 是 | 通过 | 1.347 |
| core-013 | core / texture / fixed_bars | 20 | 41 | complete / complete | 3600 / 3600 | 是 | 通过 | 3.285 |
| core-014 | core / texture / short_reversals | 20 | 78 | complete / complete | 3600 / 3600 | 是 | 通过 | 1.391 |
| core-015 | core / texture / pause_reverse_bars | 20 | 103 | complete / complete | 3600 / 3600 | 是 | 通过 | 1.455 |
| core-016 | core / text / steady | 5 | 12 | complete / complete | 965 / 965 | 是 | 通过 | 1.479 |
| core-017 | core / text / odd_steps | 5 | 14 | complete / complete | 965 / 965 | 是 | 通过 | 1.519 |
| core-018 | core / text / fixed_bars | 5 | 10 | complete / complete | 965 / 965 | 是 | 通过 | 1.396 |
| core-019 | core / text / short_reversals | 5 | 17 | complete / complete | 965 / 965 | 是 | 通过 | 1.483 |
| core-020 | core / text / pause_reverse_bars | 5 | 26 | complete / complete | 965 / 965 | 是 | 通过 | 1.403 |
| core-021 | core / text / steady | 10 | 25 | complete / complete | 1930 / 1930 | 是 | 通过 | 1.393 |
| core-022 | core / text / odd_steps | 10 | 30 | complete / complete | 1930 / 1930 | 是 | 通过 | 1.409 |
| core-023 | core / text / fixed_bars | 10 | 21 | complete / complete | 1930 / 1930 | 是 | 通过 | 1.518 |
| core-024 | core / text / short_reversals | 10 | 38 | complete / complete | 1930 / 1930 | 是 | 通过 | 1.575 |
| core-025 | core / text / pause_reverse_bars | 10 | 53 | complete / complete | 1930 / 1930 | 是 | 通过 | 1.609 |
| core-026 | core / text / steady | 20 | 52 | complete / complete | 3860 / 3860 | 是 | 通过 | 1.557 |
| core-027 | core / text / odd_steps | 20 | 62 | complete / complete | 3860 / 3860 | 是 | 通过 | 1.710 |
| core-028 | core / text / fixed_bars | 20 | 44 | complete / complete | 3860 / 3860 | 是 | 通过 | 1.484 |
| core-029 | core / text / short_reversals | 20 | 81 | complete / complete | 3860 / 3860 | 是 | 通过 | 1.707 |
| core-030 | core / text / pause_reverse_bars | 20 | 112 | complete / complete | 3860 / 3860 | 是 | 通过 | 1.601 |
| core-031 | core / chat / steady | 5 | 13 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.695 |
| core-032 | core / chat / odd_steps | 5 | 16 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.653 |
| core-033 | core / chat / fixed_bars | 5 | 11 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.725 |
| core-034 | core / chat / short_reversals | 5 | 18 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.701 |
| core-035 | core / chat / pause_reverse_bars | 5 | 27 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.650 |
| core-036 | core / chat / steady | 10 | 28 | complete / complete | 2160 / 2160 | 是 | 通过 | 1.574 |
| core-037 | core / chat / odd_steps | 10 | 33 | complete / complete | 2160 / 2160 | 是 | 通过 | 4.193 |
| core-038 | core / chat / fixed_bars | 10 | 24 | complete / complete | 2160 / 2160 | 是 | 通过 | 1.578 |
| core-039 | core / chat / short_reversals | 10 | 44 | complete / complete | 2160 / 2160 | 是 | 通过 | 1.611 |
| core-040 | core / chat / pause_reverse_bars | 10 | 60 | complete / complete | 2160 / 2160 | 是 | 通过 | 1.589 |
| core-041 | core / chat / steady | 20 | 58 | complete / complete | 4320 / 4320 | 是 | 通过 | 1.738 |
| core-042 | core / chat / odd_steps | 20 | 69 | complete / complete | 4320 / 4320 | 是 | 通过 | 1.531 |
| core-043 | core / chat / fixed_bars | 20 | 49 | complete / complete | 4320 / 4320 | 是 | 通过 | 1.639 |
| core-044 | core / chat / short_reversals | 20 | 92 | complete / complete | 4320 / 4320 | 是 | 通过 | 1.675 |
| core-045 | core / chat / pause_reverse_bars | 20 | 126 | complete / complete | 4320 / 4320 | 是 | 通过 | 1.735 |
| core-046 | core / table / steady | 5 | 11 | complete / complete | 900 / 900 | 是 | 通过 | 1.394 |
| core-047 | core / table / odd_steps | 5 | 13 | complete / complete | 900 / 900 | 是 | 通过 | 1.345 |
| core-048 | core / table / fixed_bars | 5 | 10 | complete / complete | 900 / 900 | 是 | 通过 | 1.454 |
| core-049 | core / table / short_reversals | 5 | 17 | complete / complete | 900 / 900 | 是 | 通过 | 1.407 |
| core-050 | core / table / pause_reverse_bars | 5 | 21 | complete / complete | 900 / 900 | 是 | 通过 | 1.357 |
| core-051 | core / table / steady | 10 | 24 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.425 |
| core-052 | core / table / odd_steps | 10 | 28 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.416 |
| core-053 | core / table / fixed_bars | 10 | 20 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.472 |
| core-054 | core / table / short_reversals | 10 | 37 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.457 |
| core-055 | core / table / pause_reverse_bars | 10 | 51 | complete / complete | 1800 / 1800 | 是 | 通过 | 1.375 |
| core-056 | core / table / steady | 20 | 48 | complete / complete | 3600 / 3600 | 是 | 通过 | 3.093 |
| core-057 | core / table / odd_steps | 20 | 58 | complete / complete | 3600 / 3600 | 是 | 通过 | 1.939 |
| core-058 | core / table / fixed_bars | 20 | 41 | complete / complete | 3600 / 3600 | 是 | 通过 | 1.444 |
| core-059 | core / table / short_reversals | 20 | 78 | complete / complete | 3600 / 3600 | 是 | 通过 | 1.964 |
| core-060 | core / table / pause_reverse_bars | 20 | 103 | complete / complete | 3600 / 3600 | 是 | 通过 | 1.829 |
| core-061 | core / sections / steady | 5 | 12 | complete / complete | 965 / 965 | 是 | 通过 | 1.918 |
| core-062 | core / sections / odd_steps | 5 | 14 | complete / complete | 965 / 965 | 是 | 通过 | 1.886 |
| core-063 | core / sections / fixed_bars | 5 | 10 | complete / complete | 965 / 965 | 是 | 通过 | 1.867 |
| core-064 | core / sections / short_reversals | 5 | 17 | complete / complete | 965 / 965 | 是 | 通过 | 1.770 |
| core-065 | core / sections / pause_reverse_bars | 5 | 26 | complete / complete | 965 / 965 | 是 | 通过 | 2.564 |
| core-066 | core / sections / steady | 10 | 25 | complete / complete | 1930 / 1930 | 是 | 通过 | 12.552 |
| core-067 | core / sections / odd_steps | 10 | 30 | complete / complete | 1930 / 1930 | 是 | 通过 | 1.752 |
| core-068 | core / sections / fixed_bars | 10 | 21 | complete / complete | 1930 / 1930 | 是 | 通过 | 1.949 |
| core-069 | core / sections / short_reversals | 10 | 38 | complete / complete | 1930 / 1930 | 是 | 通过 | 1.568 |
| core-070 | core / sections / pause_reverse_bars | 10 | 53 | complete / complete | 1930 / 1930 | 是 | 通过 | 1.891 |
| core-071 | core / sections / steady | 20 | 52 | complete / complete | 3860 / 3860 | 是 | 通过 | 3.659 |
| core-072 | core / sections / odd_steps | 20 | 62 | complete / complete | 3860 / 3860 | 是 | 通过 | 1.642 |
| core-073 | core / sections / fixed_bars | 20 | 44 | complete / complete | 3860 / 3860 | 是 | 通过 | 1.653 |
| core-074 | core / sections / short_reversals | 20 | 81 | complete / complete | 3860 / 3860 | 是 | 通过 | 4.664 |
| core-075 | core / sections / pause_reverse_bars | 20 | 112 | complete / complete | 3860 / 3860 | 是 | 通过 | 1.575 |
| core-076 | core / cards / steady | 5 | 13 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.655 |
| core-077 | core / cards / odd_steps | 5 | 16 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.643 |
| core-078 | core / cards / fixed_bars | 5 | 11 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.631 |
| core-079 | core / cards / short_reversals | 5 | 18 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.668 |
| core-080 | core / cards / pause_reverse_bars | 5 | 27 | complete / complete | 1080 / 1080 | 是 | 通过 | 1.616 |
| core-081 | core / cards / steady | 10 | 28 | complete / complete | 2160 / 2160 | 是 | 通过 | 1.648 |
| core-082 | core / cards / odd_steps | 10 | 33 | complete / complete | 2160 / 2160 | 是 | 通过 | 1.665 |
| core-083 | core / cards / fixed_bars | 10 | 24 | complete / complete | 2160 / 2160 | 是 | 通过 | 1.611 |
| core-084 | core / cards / short_reversals | 10 | 44 | complete / complete | 2160 / 2160 | 是 | 通过 | 1.699 |
| core-085 | core / cards / pause_reverse_bars | 10 | 60 | complete / complete | 2160 / 2160 | 是 | 通过 | 2.367 |
| core-086 | core / cards / steady | 20 | 58 | complete / complete | 4320 / 4320 | 是 | 通过 | 1.637 |
| core-087 | core / cards / odd_steps | 20 | 69 | complete / complete | 4320 / 4320 | 是 | 通过 | 1.656 |
| core-088 | core / cards / fixed_bars | 20 | 49 | complete / complete | 4320 / 4320 | 是 | 通过 | 1.628 |
| core-089 | core / cards / short_reversals | 20 | 92 | complete / complete | 4320 / 4320 | 是 | 通过 | 1.628 |
| core-090 | core / cards / pause_reverse_bars | 20 | 126 | complete / complete | 4320 / 4320 | 是 | 通过 | 2.530 |
| stress-001 | stress / periodic / periodic_ambiguity | 5 | 2 | ambiguous / ambiguous | 160 / 160 | 是 | 通过 | 0.389 |
| stress-002 | stress / periodic / periodic_ambiguity | 5 | 2 | ambiguous / ambiguous | 164 / 164 | 是 | 通过 | 0.453 |
| stress-003 | stress / periodic / periodic_ambiguity | 5 | 2 | ambiguous / ambiguous | 168 / 168 | 是 | 通过 | 0.558 |
| stress-004 | stress / periodic / periodic_ambiguity | 5 | 2 | ambiguous / ambiguous | 172 / 172 | 是 | 通过 | 0.476 |
| stress-005 | stress / periodic / periodic_ambiguity | 5 | 2 | ambiguous / ambiguous | 176 / 176 | 是 | 通过 | 0.433 |
| stress-006 | stress / texture / gap_then_recovery | 5 | 4 | rejected / rejected | 225 / 225 | 是 | 通过 | 0.867 |
| stress-007 | stress / texture / gap_then_recovery | 5 | 4 | rejected / rejected | 229 / 229 | 是 | 通过 | 0.874 |
| stress-008 | stress / texture / gap_then_recovery | 5 | 4 | rejected / rejected | 233 / 233 | 是 | 通过 | 1.104 |
| stress-009 | stress / texture / gap_then_recovery | 5 | 4 | rejected / rejected | 237 / 237 | 是 | 通过 | 0.870 |
| stress-010 | stress / texture / gap_then_recovery | 5 | 4 | rejected / rejected | 241 / 241 | 是 | 通过 | 1.202 |
| stress-011 | stress / texture / scene_change | 5 | 3 | rejected / rejected | 191 / 191 | 是 | 通过 | 0.811 |
| stress-012 | stress / texture / scene_change | 5 | 3 | rejected / rejected | 195 / 195 | 是 | 通过 | 0.829 |
| stress-013 | stress / texture / scene_change | 5 | 3 | rejected / rejected | 199 / 199 | 是 | 通过 | 0.962 |
| stress-014 | stress / texture / scene_change | 5 | 3 | rejected / rejected | 203 / 203 | 是 | 通过 | 0.890 |
| stress-015 | stress / texture / scene_change | 5 | 3 | rejected / rejected | 207 / 207 | 是 | 通过 | 1.164 |
| stress-016 | stress / texture / geometry_change | 5 | 3 | rejected / rejected | 191 / 191 | 是 | 通过 | 1.022 |
| stress-017 | stress / texture / geometry_change | 5 | 3 | rejected / rejected | 195 / 195 | 是 | 通过 | 0.445 |
| stress-018 | stress / texture / geometry_change | 5 | 3 | rejected / rejected | 199 / 199 | 是 | 通过 | 0.430 |
| stress-019 | stress / texture / geometry_change | 5 | 3 | rejected / rejected | 203 / 203 | 是 | 通过 | 0.433 |
| stress-020 | stress / texture / geometry_change | 5 | 3 | rejected / rejected | 207 / 207 | 是 | 通过 | 0.444 |
| stress-021 | stress / texture / below_minimum_overlap | 5 | 2 | rejected / rejected | 160 / 160 | 是 | 通过 | 0.416 |
| stress-022 | stress / texture / below_minimum_overlap | 5 | 2 | rejected / rejected | 164 / 164 | 是 | 通过 | 0.418 |
| stress-023 | stress / texture / below_minimum_overlap | 5 | 2 | rejected / rejected | 168 / 168 | 是 | 通过 | 0.445 |
| stress-024 | stress / texture / below_minimum_overlap | 5 | 2 | rejected / rejected | 172 / 172 | 是 | 通过 | 0.465 |
| stress-025 | stress / texture / below_minimum_overlap | 5 | 2 | rejected / rejected | 176 / 176 | 是 | 通过 | 0.435 |
| stress-026 | stress / gradient / low_contrast_ambiguity | 5 | 2 | ambiguous / ambiguous | 160 / 160 | 是 | 通过 | 0.323 |
| stress-027 | stress / gradient / low_contrast_ambiguity | 5 | 2 | ambiguous / ambiguous | 164 / 164 | 是 | 通过 | 0.327 |
| stress-028 | stress / gradient / low_contrast_ambiguity | 5 | 2 | ambiguous / ambiguous | 168 / 168 | 是 | 通过 | 0.335 |
| stress-029 | stress / gradient / low_contrast_ambiguity | 5 | 2 | ambiguous / ambiguous | 172 / 172 | 是 | 通过 | 0.338 |
| stress-030 | stress / gradient / low_contrast_ambiguity | 5 | 2 | ambiguous / ambiguous | 176 / 176 | 是 | 通过 | 0.342 |
