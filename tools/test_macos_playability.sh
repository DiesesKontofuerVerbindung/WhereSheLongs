#!/usr/bin/env bash
#
# macOS 可玩性验证：只用 macOS 自带工具（PlistBuddy / lipo / codesign / shasum），
# 不依赖 Homebrew、coreutils 或 GUI 会话。
#
# 覆盖三层：
#   1. 包结构     —— Info.plist、bundle identifier、版本、摄像头用途说明、PCK、主程序；
#   2. 二进制     —— universal（arm64 + x86_64）、codesign --verify --deep --strict；
#   3. 实际运行   —— 打包 App 启动拿 OPENING_PASS；源码跑五段章节验证；
#                    再跑无摄像头隔离测试（必须不带 --verify）。
#
# 全部通过才输出 MAC_PLAYABILITY_PASS，退出码 0。任何一项失败都会列出来并退出 1。
#
# 用法：
#   tools/test_macos_playability.sh \
#     --app "dist/Where She Longs.app" \
#     --godot "/path/to/Godot.app/Contents/MacOS/Godot" \
#     --project "Qimiaoye_DarkForest_TextOnly_V0.1" \
#     [--log-dir tmp/codex_logs]

set -uo pipefail

APP=""
GODOT=""
PROJECT=""
LOG_DIR="tmp/codex_logs"

while [ $# -gt 0 ]; do
	case "$1" in
		--app) APP="$2"; shift 2 ;;
		--godot) GODOT="$2"; shift 2 ;;
		--project) PROJECT="$2"; shift 2 ;;
		--log-dir) LOG_DIR="$2"; shift 2 ;;
		*) echo "未知参数：$1" >&2; exit 2 ;;
	esac
done

if [ -z "$APP" ] || [ -z "$GODOT" ] || [ -z "$PROJECT" ]; then
	echo "用法：$0 --app <.app> --godot <Godot 可执行文件> --project <工程目录> [--log-dir <目录>]" >&2
	exit 2
fi

mkdir -p "$LOG_DIR"

# 用计数器而不是数组：macOS 自带的是 bash 3.2，`set -u` 下展开空数组会直接报错。
FAILURE_COUNT=0

fail() {
	FAILURE_COUNT=$((FAILURE_COUNT + 1))
	echo "MAC_PLAYABILITY_FAIL $1"
}

# macOS 默认没有 coreutils 的 timeout，自己实现一个：超时一律算失败，
# 免得摄像头/网络相关的死等把 CI 挂住。
run_with_timeout() {
	local seconds="$1"; shift
	local log="$1"; shift
	"$@" >"$log" 2>&1 &
	local pid=$!
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if [ "$waited" -ge "$seconds" ]; then
			kill -9 "$pid" 2>/dev/null
			wait "$pid" 2>/dev/null
			echo "[timeout ${seconds}s]" >>"$log"
			return 124
		fi
		sleep 1
		waited=$((waited + 1))
	done
	wait "$pid"
	return $?
}

plist_get() {
	/usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null
}

# ---------------------------------------------------------------- 1. 包结构

echo "== 1/3 包结构 =="

if [ ! -d "$APP" ]; then
	fail "找不到 App 包：$APP"
	echo "MAC_PLAYABILITY_FAIL_TOTAL=$FAILURE_COUNT"
	exit 1
fi

if [ ! -f "$APP/Contents/Info.plist" ]; then
	fail "缺少 Contents/Info.plist"
fi

BUNDLE_ID="$(plist_get CFBundleIdentifier)"
SHORT_VERSION="$(plist_get CFBundleShortVersionString)"
EXE_NAME="$(plist_get CFBundleExecutable)"
CAMERA_USAGE="$(plist_get NSCameraUsageDescription)"

[ "$BUNDLE_ID" = "com.qimiaoye.wheresshelongs" ] || fail "bundle identifier 不符：'$BUNDLE_ID'"
[ "$SHORT_VERSION" = "1.3.17" ] || fail "CFBundleShortVersionString 不是 1.3.17：'$SHORT_VERSION'"
[ -n "$EXE_NAME" ] || fail "Info.plist 缺 CFBundleExecutable"
# 没有摄像头用途说明，macOS 会在请求摄像头时直接杀进程。
[ -n "$CAMERA_USAGE" ] || fail "Info.plist 缺 NSCameraUsageDescription，摄像头玩法会让 App 被系统终止"

EXE="$APP/Contents/MacOS/$EXE_NAME"
[ -x "$EXE" ] || fail "主程序不可执行：$EXE"

PCK_COUNT=$(ls -1 "$APP/Contents/Resources/"*.pck 2>/dev/null | wc -l | tr -d ' ')
[ "$PCK_COUNT" -ge 1 ] || fail "Contents/Resources 下没有 .pck 数据包"

# ------------------------------------------------------------ 2. 二进制与签名

echo "== 2/3 架构与签名 =="

ARCHS=""
if [ -x "$EXE" ]; then
	ARCHS="$(lipo -archs "$EXE" 2>/dev/null)"
	echo "$ARCHS" | grep -q "arm64" || fail "主程序缺少 arm64 切片（Apple Silicon 跑不了）：'$ARCHS'"
	echo "$ARCHS" | grep -q "x86_64" || fail "主程序缺少 x86_64 切片（Intel 跑不了）：'$ARCHS'"
fi

if ! codesign --verify --deep --strict --verbose=2 "$APP" >"$LOG_DIR/macos_codesign_verify.log" 2>&1; then
	fail "codesign --verify --deep --strict 未通过（见 $LOG_DIR/macos_codesign_verify.log）"
fi

# ---------------------------------------------------------------- 3. 实际运行

echo "== 3/3 运行验证 =="

# 3.1 打包 App 自己启动一次。主场景是 opening，verify 模式下打印 OPENING_PASS。
if [ -x "$EXE" ]; then
	run_with_timeout 300 "$LOG_DIR/macos_app_opening_verify.log" "$EXE" --headless -- --verify
	APP_CODE=$?
	if [ "$APP_CODE" -ne 0 ]; then
		fail "打包 App 启动失败（exit=${APP_CODE}，见 ${LOG_DIR}/macos_app_opening_verify.log）"
	fi
	grep -q "OPENING_PASS" "$LOG_DIR/macos_app_opening_verify.log" \
		|| fail "打包 App 没有输出 OPENING_PASS（见 $LOG_DIR/macos_app_opening_verify.log）"
fi

# 3.2 源码五段章节验证。
run_scene_verify() {
	local tag="$1" scene="$2" marker="$3" seconds="$4"
	local log="$LOG_DIR/macos_verify_$tag.log"
	run_with_timeout "$seconds" "$log" \
		"$GODOT" --headless --path "$PROJECT" --resolution 1280x720 "$scene" -- --verify
	local code=$?
	if [ "$code" -ne 0 ]; then
		fail "${tag} 验证退出码 ${code}（见 ${log}）"
		return
	fi
	grep -q "$marker" "$log" || fail "${tag} 验证没有输出 ${marker}（见 ${log}）"
}

run_scene_verify opening  "res://scenes/opening/opening.tscn"          OPENING_PASS          300
run_scene_verify wedding  "res://scenes/wedding/wedding_prologue.tscn" WEDDING_PROLOGUE_PASS 600
run_scene_verify mystic   "res://scenes/mystic_night/mystic_night.tscn" MYSTIC_NIGHT_PASS    600
run_scene_verify full     "res://main.tscn"                            FULL_FLOW_PASS        900
run_scene_verify chapter3 "res://scenes/chapter3/chapter3.tscn"        CHAPTER3_PASS         600

# 3.3 无摄像头隔离测试。这一条**不能**带 --verify：verify 模式下各模块会走直通
#     分支，覆盖不到 macOS 上真正没有摄像头/没有检测服务的路径。
ISO_LOG="$LOG_DIR/macos_camera_unavailable_isolation.log"
run_with_timeout 300 "$ISO_LOG" \
	"$GODOT" --headless --path "$PROJECT" res://tests/camera_unavailable_isolation_test.tscn
ISO_CODE=$?
if [ "$ISO_CODE" -ne 0 ]; then
	fail "无摄像头隔离测试退出码 ${ISO_CODE}（见 ${ISO_LOG}）"
fi
ISO_PASS_COUNT=$(grep -c "CAMERA_UNAVAILABLE_ISOLATION_PASS" "$ISO_LOG" | tr -d ' ')
if [ "$ISO_PASS_COUNT" != "1" ]; then
	fail "无摄像头隔离测试没有输出唯一的 CAMERA_UNAVAILABLE_ISOLATION_PASS（命中 ${ISO_PASS_COUNT} 次，见 ${ISO_LOG}）"
fi

# -------------------------------------------------------------------- 汇总

if [ "$FAILURE_COUNT" -ne 0 ]; then
	echo "MAC_PLAYABILITY_FAIL_TOTAL=$FAILURE_COUNT"
	exit 1
fi

echo "MAC_PLAYABILITY_PASS bundle_id=$BUNDLE_ID version=$SHORT_VERSION archs=$(echo "$ARCHS" | tr '\n' '+' | sed 's/+$//') codesign=verified pck=$PCK_COUNT app_launch=OPENING_PASS chapters=opening+wedding+mystic+full+chapter3 camera_isolation=CAMERA_UNAVAILABLE_ISOLATION_PASS"
exit 0
