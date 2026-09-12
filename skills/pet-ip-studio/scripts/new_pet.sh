#!/usr/bin/env bash
#
# 铺出一个可以开始开发的新宠物项目。
#
#   bash scripts/new_pet.sh ~/Projects/柴犬
#   bash scripts/new_pet.sh ./小橘 --name 小橘
#
# 做完之后，目标目录里是一套**能立刻编译、能立刻出对照图**的完整工作区：
#
#   目标目录/
#   ├── main.swift              模板 app（就是那份跑通的完整实现）
#   ├── harness/
#   │   ├── tools/              5 个验证工具 + build.sh + mkhead.py
#   │   ├── build/              编译产物（工具会往里写）
#   │   ├── baseline.txt        渲染基线指纹
#   │   └── ip-spec.json        参数快照（第一次 export_spec 时生成）
#   └── starter/                教学骨架 + 参数对比图
#
# ⚠️ 为什么起点是「模板 app」而不是教学骨架 PetStarter：
#    工具链（mkhead / render_sheet / verify / export_spec）是按 **main.swift 的结构**
#    写的 —— 它需要 `// MARK: - App` 切分标记，也需要那 7 个维度枚举
#    （LOOKS / EyeStyle / EyeColor / BibStyle / EarStyle / TailStyle / MouthStyle / CatState）。
#    PetStarter 用的是另一套结构（Palette / Geometry），**接不上**。
#    所以：**做新宠物 = 拿模板改**，PetStarter 只用来读、理解原理。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET=""
PET_NAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --name) PET_NAME="${2:-}"; shift 2 ;;
        -h|--help)
            sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0 ;;
        *)
            if [ -z "${TARGET}" ]; then TARGET="$1"; else
                echo "多余的参数：$1" >&2; exit 2
            fi
            shift ;;
    esac
done

if [ -z "${TARGET}" ]; then
    echo "用法： bash scripts/new_pet.sh <目标目录> [--name 宠物名]" >&2
    exit 2
fi

# ── 把目标路径解析成绝对路径 ──
#
# ⚠️ 不能写成 `cd "$(dirname "$T")"` 就完事：父目录很可能**还不存在**
#    （用户就是要新建 ~/Projects/柴犬）。cd 失败 → 命令替换返回空串 →
#    路径变成 "/柴犬" → 报 "Read-only file system"，报错信息跟真正的原因
#    毫无关系（踩过）。所以先把父目录建出来，再解析。
expand_path() {
    local p="$1"
    case "${p}" in
        "~"*) p="${HOME}${p#\~}" ;;
    esac
    case "${p}" in
        /*) ;;
        *)  p="${PWD}/${p}" ;;
    esac
    p="${p%/}"
    [ -n "${p}" ] || return 1
    local dir; dir="$(dirname "${p}")"
    mkdir -p "${dir}" || return 1
    ( cd "${dir}" && printf '%s/%s' "$(pwd)" "$(basename "${p}")" )
}

TARGET="$(expand_path "${TARGET}")" || {
    echo "✗ 目标路径没法解析：${TARGET}" >&2; exit 1
}
if [ -z "${TARGET}" ] || [ "${TARGET}" = "/" ]; then
    echo "✗ 目标路径解析成了空/根目录，拒绝继续" >&2; exit 1
fi

if [ -e "${TARGET}" ] && [ -n "$(ls -A "${TARGET}" 2>/dev/null)" ]; then
    echo "✗ ${TARGET} 已存在且不是空的。换个目录，或者先清空它。" >&2
    exit 1
fi

for need in assets/PetApp.swift scripts/build.sh scripts/mkhead.py scripts/baseline.txt; do
    if [ ! -f "${SKILL_ROOT}/${need}" ]; then
        echo "✗ skill 包不完整，缺 ${need}" >&2
        echo "  这个脚本得跟 assets/ 和 scripts/ 放在同一个 skill 目录下。" >&2
        exit 1
    fi
done

echo "喵藏 · 新建宠物项目"
echo "────────────────────────────────────────"
echo "  目标目录  ${TARGET}"
[ -n "${PET_NAME}" ] && echo "  宠物名    ${PET_NAME}"

mkdir -p "${TARGET}/harness/tools" "${TARGET}/harness/build" "${TARGET}/scripts" "${TARGET}/starter"

cp "${SKILL_ROOT}/assets/PetApp.swift" "${TARGET}/main.swift"
printf "  %-16s %s 行（模板 app）\n" "main.swift" "$(wc -l < "${TARGET}/main.swift" | tr -d ' ')"

for f in build.sh mkhead.py common.swift fingerprint.swift render_sheet.swift \
         verify.swift export_spec.swift compare_sheet.swift make_cats.swift; do
    cp "${SKILL_ROOT}/scripts/${f}" "${TARGET}/harness/tools/${f}"
done
cp "${SKILL_ROOT}/scripts/baseline.txt" "${TARGET}/harness/baseline.txt"
printf "  %-16s %s 个文件\n" "harness/tools" "$(ls "${TARGET}/harness/tools" | wc -l | tr -d ' ')"

# 这两个留在项目里，以后直接 `bash scripts/pack_app.sh` 就行，不用回去找 skill 目录
for f in new_pet.sh pack_app.sh; do
    [ -f "${SKILL_ROOT}/scripts/${f}" ] && cp "${SKILL_ROOT}/scripts/${f}" "${TARGET}/scripts/${f}"
done
printf "  %-16s %s\n" "scripts/" "new_pet.sh pack_app.sh"

# 合规材料必须跟着项目走 —— 见 SKILL.md「分发前必读」。
# 最高法《意见》第十三条：免费开源 + **公开说明其功能和安全风险** 才可能免责，
# 少这一份就等于主动放弃这条路径。
if [ -f "${SKILL_ROOT}/DISCLAIMER.md" ]; then
    cp "${SKILL_ROOT}/DISCLAIMER.md" "${TARGET}/DISCLAIMER.md"
    printf "  %-16s %s\n" "DISCLAIMER.md" "功能与风险说明（合规材料）"
fi

cp "${SKILL_ROOT}/assets/PetStarter.swift" "${TARGET}/starter/"
[ -f "${SKILL_ROOT}/assets/parameter-demo.png" ] && \
    cp "${SKILL_ROOT}/assets/parameter-demo.png" "${TARGET}/starter/"
chmod +x "${TARGET}/harness/tools/build.sh" 2>/dev/null || true

echo
echo "  编译验证工具…"
if ! ( cd "${TARGET}" && bash harness/tools/build.sh 2>&1 | sed 's/^/    /' ); then
    echo "✗ 工具链编译失败 —— 先把上面报的错解决，再开始做宠物。" >&2
    exit 1
fi

echo
echo "────────────────────────────────────────"
echo "  好了。接下来："
echo
echo "    cd ${TARGET}"
echo "    ./harness/build/render_sheet --dim look --out harness/out/look.png"
echo
echo "  第一次改动之后，务必跑一次："
echo
echo "    ./harness/build/fingerprint --baseline    # 默认档有没有被动过"
echo "    ./harness/build/verify                    # 19 条断言"
echo
echo "  想马上看看它长什么样："
echo
echo "    swiftc -O -o pet main.swift && ./pet      # 桌上会出现一只猫，右键退出"
echo
