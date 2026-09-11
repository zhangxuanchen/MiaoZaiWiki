# 分类是怎么算的

## 算法：就是这二十来行

```
text = 标题 + " " + 标题 + " " + 正文        # 标题权重 ×2
对每个分类：分数 = Σ（每个关键词在 text 里出现的次数）    # str.count，子串计数
取分数最高的那个；全 0 分 → 兜底类（默认「收件箱」）
```

没有模型、没有分词器、没有 TF-IDF —— 就是子串计数。
好处是**确定**：同一篇东西算一百遍都是同一个类，离线、毫秒级、零成本。

## 三个必须知道的点

### 1. 平票时按「类名的字符编码」决胜

```python
scores.sort(reverse=True)     # 比的是 (分数, 类名) 这个元组
```

分数相同时比类名 —— 所以**改分类的名字会改变平票结果**。
用默认四类实测的优先级是：

```
编程技术  >  生活与其他  >  产品与商业  >  AI与Agent
```

这不一定是"你想要的"规则，但它是**当前实际在跑**的规则。想要行为可预测，
就尽量避免平票：把词表写得更互斥（见下）。

### 2. 子串计数会重复命中

`AgentScope` 同时命中 `agent` 和 `agents` 两个词，标题算两遍 → 白送 4 分。

这在"想让它更准"时是好事（真相关的会堆分），但**短词会误伤**：
`go` 这种两个字的关键词会命中 `google` / `logo` / `算法`。
写词表时留意：

- 英文词**小写**（匹配前会 `.lower()`，但词表里也统一小写比较好读）
- 太短的词要带空格或写成短语 —— 默认词表里的 `"go "` 特意拖了个空格，
  就是为了不命中 `google` / `logo` / `django`
- 中文没有分词，所以**选词比选数量重要**

### 3. 改词表**只对新喂的生效**

`--rescan` 不会重新分类 —— 它只认 md 里的 front-matter，其次文件夹名。
老条目想换类：改 front-matter 的 `category` 再 `--rescan`，或者把文件挪到目标文件夹再 `--rescan`。

## 词表怎么调

放 `<书库>/.miao-zang.json`（**跟书库走** —— 换机器、拷书库，规则一起过去）：

```json
{
  "fallback": "收件箱",
  "categories": [
    { "name": "AI与Agent", "keywords": ["agent", "llm", "大模型", "上下文", "mcp"] },
    { "name": "读书笔记",  "keywords": ["读完", "书摘", "作者", "章节", "读后感"] }
  ]
}
```

几条经验：

- **每类 15~40 个词**比较合适。太少 → 长尾全掉进兜底；太多 → 互相抢分制造平票。
- 词要挑**这一类独有的**。`技术` `分享` `平台` `工具` 这种到处都有的词只会让分数平均。
- 类别名不必刻意排序，但知道平票规则后，你会明白为什么有时落点"看起来随机"。
- **兜底类的名字不要同时出现在任何关键词表里**，否则它会去抢分。

## 自测一下（改完词表强烈建议跑）

```bash
python3 - <<'EOF'
import importlib.util, json, pathlib
spec = importlib.util.spec_from_file_location("f", "scripts/fetcher.py")
f = importlib.util.module_from_spec(spec); spec.loader.exec_module(f)
cfg = json.loads(pathlib.Path("<书库>/.miao-zang.json").read_text(encoding="utf-8"))
for t in ["Agent 记忆设计", "读《人月神话》有感", "Swift 并发模型"]:
    print(t, "→", f.classify(t, "", cfg["categories"], cfg.get("fallback")))
EOF
```

拿真实标题跑一遍，看落点是不是你要的 —— 比读文档快得多。
