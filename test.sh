#!/bin/bash
# 版本: 3.5.5 - 新增列出已有项目API密钥的功能
# 更新说明: 添加菜单选项 "4"，允许用户查询并列出指定项目中所有已存在的 API 密钥及其详细信息。
#           修复说明: 将 enable_api_and_create_key 函数内 gcloud services enable 的输出重定向到 stderr，
#                     防止其成功消息污染最终返回的 API Key 字符串。

# 脚本设置：pipefail 依然有用，但移除了 -e，改为手动错误检查
set -uo pipefail

# ===== 颜色定义 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ===== 环境自检与设置 =====
setup_environment() {
    echo -e "${CYAN}--- 环境自检与设置 ---${NC}" >&2
    # 检查 'bc' 并尝试安装
    if ! command -v bc &>/dev/null; then
        echo -e "${YELLOW}[!] 核心依赖 'bc' 未找到，正在尝试自动安装...${NC}" >&2
        echo "    (这可能需要您输入 sudo 密码)" >&2
        if command -v apt-get &>/dev/null; then
            if sudo apt-get update >/dev/null && sudo apt-get install -y bc >/dev/null; then
                echo -e "${GREEN}[✓] 依赖 'bc' 安装成功！${NC}" >&2
            else
                echo -e "${RED}[✗] 自动安装 'bc' 失败。请手动安装 'bc'。${NC}" >&2
                exit 1
            fi
        else
            echo -e "${RED}[✗] 无法找到 apt-get 包管理器。请手动安装 'bc'。${NC}" >&2
            exit 1
        fi
    fi

    # 检查 'jq' 并提示安装
    if ! command -v jq &>/dev/null; then
        echo -e "${YELLOW}[!] 推荐依赖 'jq' 未找到。脚本将使用备用方法解析数据，但这可能不稳定。${NC}" >&2
        echo -e "${YELLOW}    建议安装 'jq' 以提高稳定性 (例如: 'sudo apt-get install jq')${NC}" >&2
    fi
    echo -e "${CYAN}--- 环境检查完毕 ---\n${NC}" >&2
    sleep 1
}


# ===== 全局配置 =====
VERSION="3.5.5" # Updated Version
MAX_PARALLEL_JOBS="${CONCURRENCY:-25}"
MAX_RETRY_ATTEMPTS="${MAX_RETRY:-3}"
RANDOM_DELAY_MAX="1.5"
SESSION_ID=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="gemini_session_${SESSION_ID}"
DETAILED_LOG_FILE="${OUTPUT_DIR}/detailed_run.log"
DELETION_LOG_FILE="${OUTPUT_DIR}/project_deletion.log"
TEMP_DIR=$(mktemp -d -t gcp_gemini_XXXXXX)
SECONDS=0

# ===== 生命周期管理 =====
cleanup_resources() {
    local exit_code=$?
    wait
    log "INFO" "正在执行清理程序..."
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log "INFO" "已清理临时文件目录: $TEMP_DIR"
    fi
    if [ $exit_code -eq 0 ]; then
        log "SUCCESS" "所有操作已成功完成。"
    elif [ $exit_code -eq 130 ]; then
        log "WARN" "用户手动中断操作。"
    else
        log "WARN" "脚本因错误退出 (退出码: $exit_code)。"
    fi
    duration=$SECONDS
    echo -e "\n${PURPLE}本次运行总耗时: ${BOLD}$((duration / 60)) 分 $((duration % 60)) 秒${NC}" >&2
    echo -e "${CYAN}感谢使用！${NC}" >&2
}
trap cleanup_resources EXIT

# ====================================================================================
#  所有屏幕输出都重定向到 stderr (>&2)，确保不污染 stdout。
# ====================================================================================
log() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line
    local clean_log_line
    
    case "$level" in
        "INFO")    log_line="${CYAN}[${timestamp}] [INFO] ${msg}${NC}" ;;
        "SUCCESS") log_line="${GREEN}[${timestamp}] [SUCCESS] ${msg}${NC}" ;;
        "WARN")    log_line="${YELLOW}[${timestamp}] [WARN] ${msg}${NC}" ;;
        "ERROR")   log_line="${RED}[${timestamp}] [ERROR] ${msg}${NC}" ;;
        *)         log_line="[${timestamp}] [${level}] ${msg}" ;;
    esac
    
    clean_log_line="[${timestamp}] [${level}] ${msg}"
    
    echo -e "$log_line" >&2
    if [ -d "$OUTPUT_DIR" ] && [ -f "${TEMP_DIR}/log.lock" ]; then
        (
            flock -x 9
            echo "$clean_log_line" >> "$DETAILED_LOG_FILE"
        ) 9>"${TEMP_DIR}/log.lock"
    fi
}

require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        log "ERROR" "核心依赖缺失: '$1'。请确保它已安装并位于您的 PATH 中。"
        exit 1
    fi
}

smart_retry_gcloud() {
    local n=1
    local output
    local exit_code
    local fatal_patterns=(
        "exceeded your allotted project quota"
        "PERMISSION_DENIED"
        "Billing account not configured"
        "already exists"
        "The project ID you specified is already in use by another project"
        "Caller does not have permission"
    )

    while true; do
        output=$( { "$@" 2>&1; } 2>&1 )
        exit_code=$?

        if [ $exit_code -eq 0 ] && ! echo "$output" | grep -q "ERROR:"; then
            echo "$output"
            return 0
        fi

        for pattern in "${fatal_patterns[@]}"; do
            if [[ "$output" == *"$pattern"* ]]; then
                log "ERROR" "检测到致命且不可重试的错误: '$pattern'"
                log "ERROR" "相关命令: '$*'"
                log "ERROR" "详细输出: $output"
                return 1
            fi
        done
        
        if [ $n -ge "$MAX_RETRY_ATTEMPTS" ]; then
            log "ERROR" "命令在 ${MAX_RETRY_ATTEMPTS} 次尝试后仍然失败。"
            log "ERROR" "相关命令: '$*'"
            log "ERROR" "最后一次错误输出: $output"
            return 1
        fi
        
        local delay=$((n * 2 + RANDOM % 3))
        log "WARN" "命令 '$*' 出现问题 (退出码: $exit_code)。正在重试 (${n}/${MAX_RETRY_ATTEMPTS})，等待 ${delay}s..."
        sleep "$delay"
        ((n++))
    done
}

ask_yes_no() {
    local prompt="$1"
    local resp
    while true; do
        read -r -p "${prompt} [y/n]: " resp
        case "$resp" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "请输入 y 或 n." >&2;;
        esac
    done
}

new_project_id() {
    local prefix="$1"
    local random_part
    random_part=$(openssl rand -hex 4)
    echo "${prefix}-$(date +%s)-${random_part}" | cut -c1-30
}

write_key_atomic() {
    local api_key="$1"
    local pure_key_file="$2"
    local comma_key_file="$3"
    (
        flock -x 200
        echo "$api_key" >> "$pure_key_file"
        if [ -s "$comma_key_file" ]; then
            echo -n "," >> "$comma_key_file"
        fi
        echo -n "$api_key" >> "$comma_key_file"
    ) 200>"${TEMP_DIR}/keys.lock"
}

random_sleep() {
    sleep "$(bc <<< "scale=2; $RANDOM/32767 * $RANDOM_DELAY_MAX")"
}

check_gcp_env() {
    log "INFO" "检查 GCP 环境配置..."
    require_cmd gcloud
    require_cmd openssl
    require_cmd bc
    if ! gcloud config get-value account >/dev/null 2>&1; then
        log "ERROR" "GCP 账户未配置。请先运行 'gcloud auth login' 和 'gcloud config set project [YOUR_PROJECT_ID]'."
        exit 1
    fi
    local account
    account=$(gcloud config get-value account)
    log "SUCCESS" "GCP 环境检查通过。当前活动账户: ${BOLD}${account}${NC}"
}

enable_api_and_create_key() {
    local project_id="$1"
    local log_prefix="$2"
    
    random_sleep
    if ! smart_retry_gcloud gcloud services enable generativelanguage.googleapis.com --project="$project_id" --quiet >&2; then
        log "ERROR" "${log_prefix} 启用 Generative Language API 失败。"
        return 1
    fi
    log "INFO" "${log_prefix} API 启用成功。"

    random_sleep
    local display_name="gemini-key-$(openssl rand -hex 2)"
    local key_json
    key_json=$(smart_retry_gcloud gcloud services api-keys create --project="$project_id" --display-name="$display_name" --format="json" --quiet)
    
    if [ -z "$key_json" ]; then
        log "ERROR" "${log_prefix} 创建 API 密钥失败。"
        return 1
    fi

    local api_key
    if command -v jq &>/dev/null; then
        api_key=$(echo "$key_json" | sed -n '/^{/,$p' | jq -r '.response.keyString')
    else
        api_key=$(echo "$key_json" | sed -n '/^{/,$p' | grep -o '"keyString": "[^"]*' | cut -d'"' -f4 | tail -n 1)
    fi

    if [ -z "$api_key" ] || [ "$api_key" == "null" ]; then
        log "ERROR" "${log_prefix} 无法从API响应中提取密钥。收到的内容: $key_json"
        return 1
    fi
    
    echo "$api_key"
    return 0
}

process_new_project_creation() {
    local project_id="$1"
    local task_num="$2"
    local total_tasks="$3"
    local pure_key_file="$4"
    local comma_key_file="$5"
    local log_prefix="[${task_num}/${total_tasks}] [${project_id}]"

    log "INFO" "${log_prefix} 开始创建..."
    random_sleep

    if ! smart_retry_gcloud gcloud projects create "$project_id" --name="$project_id" --quiet >&2; then
        log "ERROR" "${log_prefix} 项目创建失败。"
        echo "$project_id" >> "${TEMP_DIR}/failed.log"
        return
    fi
    log "INFO" "${log_prefix} 项目创建成功。"

    local api_key
    api_key=$(enable_api_and_create_key "$project_id" "$log_prefix")
    if [ -z "$api_key" ]; then
        log "WARN" "${log_prefix} 获取密钥失败，将尝试删除此空项目以进行清理。"
        smart_retry_gcloud gcloud projects delete "$project_id" --quiet >/dev/null 2>&1 || true
        echo "$project_id" >> "${TEMP_DIR}/failed.log"
        return
    fi
    
    write_key_atomic "$api_key" "$pure_key_file" "$comma_key_file"
    log "SUCCESS" "${log_prefix} 成功获取密钥并已保存！"
    echo "$project_id" >> "${TEMP_DIR}/success.log"
}

process_existing_project_extraction() {
    local project_id="$1"
    local task_num="$2"
    local total_tasks="$3"
    local pure_key_file="$4"
    local comma_key_file="$5"
    local log_prefix="[${task_num}/${total_tasks}] [${project_id}]"

    log "INFO" "${log_prefix} 开始处理现有项目..."
    
    local api_key
    api_key=$(enable_api_and_create_key "$project_id" "$log_prefix")
    if [ -z "$api_key" ]; then
        echo "$project_id" >> "${TEMP_DIR}/failed.log"
        return
    fi
    
    write_key_atomic "$api_key" "$pure_key_file" "$comma_key_file"
    log "SUCCESS" "${log_prefix} 成功获取密钥并已保存！"
    echo "$project_id" >> "${TEMP_DIR}/success.log"
}

# ===== MODIFICATION START: 新增函数用于列出项目密钥 =====
gemini_list_project_keys() {
    log "INFO" "====== 列出指定项目的 API 密钥 ======"
    log "INFO" "正在获取您账户下的所有活跃项目列表..."
    mapfile -t all_projects < <(gcloud projects list --filter='lifecycleState:ACTIVE' --format='value(projectId)' 2>/dev/null)

    if [ ${#all_projects[@]} -eq 0 ]; then
        log "ERROR" "未找到任何活跃项目。"
        return
    fi
    
    log "INFO" "找到 ${#all_projects[@]} 个活跃项目。请选择要查询的项目:"
    for i in "${!all_projects[@]}"; do
        printf "  %3d. %s\n" "$((i+1))" "${all_projects[i]}" >&2
    done

    local selection
    read -r -p "请输入您想查询的单个项目编号: " selection
    
    local project_id
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#all_projects[@]}" ]; then
        project_id="${all_projects[$((selection-1))]}"
    else
        log "ERROR" "无效的编号: $selection。操作已取消。"
        return
    fi

    log "INFO" "正在查询项目 [${project_id}] 的 API 密钥列表..."
    
    # 优先使用 jq 进行格式化输出，否则回退到 gcloud 默认的表格输出
    if command -v jq &>/dev/null; then
        local keys_json
        keys_json=$(smart_retry_gcloud gcloud services api-keys list --project="$project_id" --format="json" --quiet)
        if [ -z "$keys_json" ]; then
            log "ERROR" "无法获取项目 [${project_id}] 的密钥列表。"
            return
        fi

        if [[ $(echo "$keys_json" | jq '.keys | length') -eq 0 ]]; then
            log "WARN" "项目 [${project_id}] 中没有找到任何 API 密钥。"
        else
            log "SUCCESS" "在项目 [${project_id}] 中找到以下 API 密钥:"
            echo -e "${GREEN}" >&2
            # 使用 jq 解析并格式化输出
            echo "$keys_json" | jq -r '.keys[] | "  - 名称 (Display Name): \(.displayName)\n    密钥 (Key String):     \(.keyString)\n    创建时间 (Create Time): \(.createTime)\n"' >&2
            echo -e "${NC}" >&2
        fi
    else
        log "WARN" "未找到 'jq'。将以默认表格格式显示，可能包含额外信息。" >&2
        # Fallback to default gcloud table format
        local key_list_output
        key_list_output=$(smart_retry_gcloud gcloud services api-keys list --project="$project_id" --quiet)
        if [ -z "$key_list_output" ] || [[ "$key_list_output" == *"Listed 0 items."* ]]; then
             log "WARN" "项目 [${project_id}] 中没有找到任何 API 密钥。"
        else
            log "SUCCESS" "在项目 [${project_id}] 中找到以下 API 密钥:"
            echo -e "${GREEN}" >&2
            echo "$key_list_output" >&2
            echo -e "${NC}" >&2
        fi
    fi
}
# ===== MODIFICATION END =====

# ===== 新增功能: 批量删除所有密钥 =====
process_key_deletion_for_project() {
    local project_id="$1"
    local task_num="$2"
    local total_tasks="$3"
    local log_prefix="[${task_num}/${total_tasks}] [${project_id}]"

    log "INFO" "${log_prefix} 开始扫描并删除密钥..."
    random_sleep

    local keys_json
    keys_json=$(smart_retry_gcloud gcloud services api-keys list --project="$project_id" --format="json" --quiet)
    if [ -z "$keys_json" ]; then
        log "WARN" "${log_prefix} 无法获取密钥列表，跳过。"
        return
    fi
    
    local key_ids
    if command -v jq &>/dev/null; then
        mapfile -t key_ids < <(echo "$keys_json" | jq -r '.keys[].name' | sed "s/.*\///")
    else
        mapfile -t key_ids < <(echo "$keys_json" | grep -o '"name": "[^"]*' | cut -d'"' -f4 | sed "s/.*\///")
    fi

    if [ ${#key_ids[@]} -eq 0 ]; then
        log "INFO" "${log_prefix} 未找到任何密钥，无需操作。"
        return
    fi

    log "INFO" "${log_prefix} 找到 ${#key_ids[@]} 个密钥，准备删除..."
    local deleted_count=0
    for key_id in "${key_ids[@]}"; do
        if smart_retry_gcloud gcloud services api-keys delete "$key_id" --project="$project_id" --quiet >/dev/null 2>&1; then
            log "SUCCESS" "${log_prefix} 成功删除密钥 ID: ${key_id}"
            ((deleted_count++))
        else
            log "ERROR" "${log_prefix} 删除密钥 ID: ${key_id} 失败。"
        fi
    done
    log "INFO" "${log_prefix} 完成, 共删除了 ${deleted_count} 个密钥。"
}

gemini_batch_delete_all_keys() {
    log "INFO" "====== 批量删除所有项目的API密钥 ======"
    log "INFO" "正在获取您账户下的所有活跃项目列表..."
    mapfile -t all_projects < <(gcloud projects list --filter='lifecycleState:ACTIVE' --format='value(projectId)' 2>/dev/null)

    if [ ${#all_projects[@]} -eq 0 ]; then
        log "ERROR" "未找到任何活跃项目。"
        return
    fi

    echo -e "\n${RED}${BOLD}!!! 极度危险操作警告 !!!${NC}" >&2
    echo -e "${YELLOW}此操作将永久删除您 GCP 账户下 ${#all_projects[@]} 个活跃项目中的【所有】API 密钥。${NC}" >&2
    echo -e "${YELLOW}这个过程是不可逆的，并且不会区分密钥的用途。${NC}" >&2
    read -r -p "如果您完全理解并希望继续，请输入 'DELETE ALL KEYS' 来确认: " confirmation
    if [ "$confirmation" != "DELETE ALL KEYS" ]; then
        log "INFO" "删除操作已取消。"
        return
    fi

    log "INFO" "确认成功。开始并行删除所有密钥..."
    mkdir -p "$OUTPUT_DIR"
    
    local job_count=0
    local total_tasks=${#all_projects[@]}
    for i in "${!all_projects[@]}"; do
        local project_id="${all_projects[i]}"
        process_key_deletion_for_project "$project_id" "$((i+1))" "$total_tasks" &
        job_count=$((job_count + 1))
        if [ "$job_count" -ge "$MAX_PARALLEL_JOBS" ]; then
            wait -n || true
            job_count=$((job_count - 1))
        fi
    done

    log "INFO" "所有删除任务已派发，正在等待完成..."
    wait
    log "SUCCESS" "所有项目的密钥删除操作已执行完毕。"
}
# ===== 新增功能结束 =====

# ===== 编排函数 =====
run_parallel_processor() {
    local processor_func="$1"
    shift
    local projects_to_process=("$@")
    
    local pure_key_file="${OUTPUT_DIR}/all_keys.txt"
    local comma_key_file="${OUTPUT_DIR}/all_keys_comma_separated.txt"

    > "$pure_key_file"
    > "$comma_key_file"

    rm -f "${TEMP_DIR}/success.log" "${TEMP_DIR}/failed.log"
    touch "${TEMP_DIR}/success.log" "${TEMP_DIR}/failed.log"

    local job_count=0
    local total_tasks=${#projects_to_process[@]}
    for i in "${!projects_to_process[@]}"; do
        local project_id="${projects_to_process[i]}"
        "$processor_func" "$project_id" "$((i+1))" "$total_tasks" "$pure_key_file" "$comma_key_file" &
        job_count=$((job_count + 1))
        if [ "$job_count" -ge "$MAX_PARALLEL_JOBS" ]; then
            wait -n || true
            job_count=$((job_count - 1))
        fi
    done

    log "INFO" "所有任务已派发，正在等待剩余任务完成..."
    wait

    report_and_download_results "$comma_key_file" "$pure_key_file"
}

gemini_batch_create_keys() {
    log "INFO" "====== 高性能批量创建 Gemini API 密钥 ======"
    local num_projects
    read -r -p "请输入要创建的项目数量 (例如: 50): " num_projects
    if ! [[ "$num_projects" =~ ^[1-9][0-9]*$ ]]; then
        log "ERROR" "无效的数字。请输入一个大于0的整数。"
        return
    fi
    local project_prefix
    read -r -p "请输入项目前缀 (默认: gemini-pro): " project_prefix
    project_prefix=${project_prefix:-gemini-pro}
    
    mkdir -p "$OUTPUT_DIR"
    
    echo -e "\n${YELLOW}${BOLD}=== 操作确认 ===${NC}" >&2
    echo -e "  计划创建项目数: ${BOLD}${num_projects}${NC}" >&2
    echo -e "  项目前缀:       ${BOLD}${project_prefix}${NC}" >&2
    echo -e "  并行任务数:     ${BOLD}${MAX_PARALLEL_JOBS}${NC}" >&2
    echo -e "  输出目录:       ${BOLD}${OUTPUT_DIR}${NC}" >&2
    echo -e "${RED}警告: 大规模创建项目可能违反GCP服务条款或超出配额。${NC}" >&2
    if ! ask_yes_no "确认要继续吗?"; then
        log "INFO" "操作已取消。"
        return
    fi

    local projects_to_create=()
    for ((i=1; i<=num_projects; i++)); do
        projects_to_create+=("$(new_project_id "$project_prefix")")
    done
    
    run_parallel_processor "process_new_project_creation" "${projects_to_create[@]}"
}

gemini_extract_from_existing() {
    log "INFO" "====== 从现有项目提取 Gemini API 密钥 ======"
    log "INFO" "正在获取您账户下的所有活跃项目列表..."
    mapfile -t all_projects < <(gcloud projects list --filter='lifecycleState:ACTIVE' --format='value(projectId)' 2>/dev/null)

    if [ ${#all_projects[@]} -eq 0 ]; then
        log "ERROR" "未找到任何活跃项目。"
        return
    fi
    
    log "INFO" "找到 ${#all_projects[@]} 个活跃项目。请选择要处理的项目:"
    for i in "${!all_projects[@]}"; do
        printf "  %3d. %s\n" "$((i+1))" "${all_projects[i]}" >&2
    done

    read -r -p "请输入项目编号 (多个用空格隔开，或输入 'all' 处理全部): " -a selections
    
    local projects_to_process=()
    if [[ " ${selections[*],,} " =~ " all " ]]; then
        projects_to_process=("${all_projects[@]}")
    else
        for num in "${selections[@]}"; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#all_projects[@]}" ]; then
                projects_to_process+=("${all_projects[$((num-1))]}")
            else
                log "WARN" "无效的编号: $num，已忽略。"
            fi
        done
    fi

    if [ ${#projects_to_process[@]} -eq 0 ]; then
        log "ERROR" "未选择任何有效项目。"
        return
    fi

    mkdir -p "$OUTPUT_DIR"

    echo -e "\n${YELLOW}${BOLD}=== 操作确认 ===${NC}" >&2
    echo -e "  将为 ${#projects_to_process[@]} 个现有项目提取新密钥。" >&2
    echo -e "  并行任务数:     ${BOLD}${MAX_PARALLEL_JOBS}${NC}" >&2
    echo -e "  输出目录:       ${BOLD}${OUTPUT_DIR}${NC}" >&2
    if ! ask_yes_no "确认要继续吗?"; then
        log "INFO" "操作已取消。"
        return
    fi
    
    run_parallel_processor "process_existing_project_extraction" "${projects_to_process[@]}"
}

gemini_batch_delete_projects() {
    log "INFO" "====== 批量删除项目 ======"
    mapfile -t projects < <(gcloud projects list --filter='lifecycleState:ACTIVE' --format='value(projectId)' 2>/dev/null)
    if [ ${#projects[@]} -eq 0 ]; then
        log "ERROR" "未找到任何活跃项目。"
        return
    fi
    
    read -r -p "请输入要删除的项目前缀 (留空则匹配所有): " prefix

    local projects_to_delete=()
    for proj in "${projects[@]}"; do
        if [[ "$proj" == "${prefix}"* ]]; then
            projects_to_delete+=("$proj")
        fi
    done

    if [ ${#projects_to_delete[@]} -eq 0 ]; then
        log "WARN" "没有找到任何项目匹配前缀: '${prefix}'"
        return
    fi

    echo -e "\n${YELLOW}将要删除以下 ${#projects_to_delete[@]} 个项目:${NC}" >&2
    printf ' - %s\n' "${projects_to_delete[@]}" | head -n 20 >&2
    if [ ${#projects_to_delete[@]} -gt 20 ]; then
        echo "   ... 等等" >&2
    fi

    echo -e "\n${RED}${BOLD}!!! 警告：此操作不可逆 !!!${NC}" >&2
    read -r -p "请输入 'DELETE' 来确认删除: " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log "INFO" "删除操作已取消。"
        return
    fi

    rm -f "${TEMP_DIR}/delete_success.log" "${TEMP_DIR}/delete_failed.log"
    touch "${TEMP_DIR}/delete_success.log" "${TEMP_DIR}/delete_failed.log"
    log "INFO" "开始批量删除任务..."
    
    local job_count=0
    for project_id in "${projects_to_delete[@]}"; do
        {
            if smart_retry_gcloud gcloud projects delete "$project_id" --quiet; then
                log "SUCCESS" "项目 [${project_id}] 删除成功。"
                echo "$project_id" >> "${TEMP_DIR}/delete_success.log"
            else
                log "ERROR" "项目 [${project_id}] 删除失败。"
                echo "$project_id" >> "${TEMP_DIR}/delete_failed.log"
            fi
        } &
        job_count=$((job_count + 1))
        if [ "$job_count" -ge "$MAX_PARALLEL_JOBS" ]; then
            wait -n || true
            job_count=$((job_count - 1))
        fi
    done
    
    wait
    local success_count=$(wc -l < "${TEMP_DIR}/delete_success.log" | tr -d ' ')
    local failed_count=$(wc -l < "${TEMP_DIR}/delete_failed.log" | tr -d ' ')

    echo -e "\n${GREEN}${BOLD}====== 批量删除完成 ======${NC}" >&2
    log "SUCCESS" "成功删除: ${success_count}"
    log "ERROR" "删除失败: ${failed_count}"
}

report_and_download_results() {
    local comma_key_file="$1"
    local pure_key_file="$2"
    local success_count
    local failed_count
    success_count=$(wc -l < "${TEMP_DIR}/success.log" | tr -d ' ')
    failed_count=$(wc -l < "${TEMP_DIR}/failed.log" | tr -d ' ')

    echo -e "\n${GREEN}${BOLD}====== 操作完成：统计结果 ======${NC}" >&2
    log "SUCCESS" "成功: ${success_count}"
    log "ERROR" "失败: ${failed_count}"
    
    if [ "$success_count" -gt 0 ]; then
        echo -e "\n${PURPLE}======================================================" >&2
        echo -e "      ✨ 最终API密钥 (可直接复制) ✨" >&2
        echo -e "======================================================${NC}" >&2
        echo -e "${GREEN}${BOLD}" >&2
        cat "$comma_key_file" >&2
        echo >&2
        echo -e "${NC}" >&2
        echo -e "${PURPLE}======================================================${NC}\n" >&2

        log "INFO" "以上密钥已完整保存至目录: ${BOLD}${OUTPUT_DIR}${NC}"
        log "INFO" "逗号分隔密钥文件: ${BOLD}${comma_key_file}${NC}"
        log "INFO" "每行一个密钥文件: ${BOLD}${pure_key_file}${NC}"
        
        if [ -n "${DEVSHELL_PROJECT_ID-}" ] && command -v cloudshell &>/dev/null; then
            log "INFO" "检测到 Cloud Shell 环境，将自动触发下载..."
            cloudshell download "$comma_key_file"
            log "SUCCESS" "下载提示已发送。文件: ${comma_key_file##*/}"
        fi
    fi
    if [ "$failed_count" -gt 0 ]; then
        log "WARN" "失败的项目ID列表保存在详细日志中: ${DETAILED_LOG_FILE}"
    fi
}

show_main_menu() {
    clear
    echo -e "${PURPLE}${BOLD}" >&2
    cat >&2 << "EOF"
  ____ ____ ____ ____ ____ ____ _________ ____ ____ ____ 
 ||G |||e |||m |||i |||n |||i |||       |||K |||e |||y ||
 ||__|||__|||__|||__|||__|||__|||_______|||__|||__|||__||
 |/__\|/__\|/__\|/__\|/__\|/__\|/_______\|/__\|/__\|/__\|
EOF
    echo -e "      高性能 Gemini API 密钥批量管理工具 ${BOLD}v${VERSION}${NC}" >&2
    echo -e "-----------------------------------------------------" >&2
    echo -e "${YELLOW}  作者: ddddd (脚本完全免费分享，请勿倒卖)${NC}" >&2
    echo -e "-----------------------------------------------------" >&2
    local account
    account=$(gcloud config get-value account 2>/dev/null || echo "未登录")
    echo -e "  当前账户: ${CYAN}${account}${NC}" >&2
    echo -e "  并行任务: ${CYAN}${MAX_PARALLEL_JOBS}${NC}" >&2
    echo -e "-----------------------------------------------------" >&2
    echo -e "\n${RED}${BOLD}请注意：滥用此脚本可能导致您的GCP账户受限。${NC}\n" >&2
    echo "  1. 批量创建新项目并提取密钥" >&2
    echo "  2. 从现有项目中提取新 API 密钥" >&2
    echo "  3. 批量删除指定前缀的项目" >&2
    # ===== MODIFICATION START: 新增菜单选项 =====
    echo "  4. 【高危】删除所有项目的所有API密钥" >&2
    echo "  5. 列出已有项目的 API 密钥" >&2
    # ===== MODIFICATION END =====
    echo "  0. 退出脚本" >&2
    echo "" >&2
}

main_app() {
    mkdir -p "$OUTPUT_DIR"
    touch "${TEMP_DIR}/log.lock"
    check_gcp_env

    while true;
    do
        show_main_menu
        # ===== MODIFICATION START: 更新输入提示和 case 语句 =====
        read -r -p "请选择操作 [0-5]: " choice
        case "$choice" in
            1) gemini_batch_create_keys ;;
            2) gemini_extract_from_existing ;;
            3) gemini_batch_delete_projects ;;
            4) gemini_batch_delete_all_keys ;;
            5) gemini_list_project_keys ;;
            0) exit 0 ;;
            *) log "ERROR" "无效输入，请输入 0, 1, 2, 3, 4, 或 5。" ;;
        esac
        # ===== MODIFICATION END =====
        echo -e "\n${GREEN}按任意键返回主菜单...${NC}" >&2
        read -n 1 -s -r || true
    done
}

# ===== Main Execution =====
setup_environment
main_app
