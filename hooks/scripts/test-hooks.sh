#!/bin/bash

# GitHub Integration Hooks 테스트 스크립트
# 모든 Hook 기능을 테스트하여 정상 동작 확인

set -euo pipefail

# 색상 출력용
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 설정 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# 환경 변수 로드
if [[ -f "$ROOT_DIR/.env" ]]; then
    source "$ROOT_DIR/.env"
fi

LOG_FILE="${LOG_FILE:-$ROOT_DIR/logs/test-hooks.log}"

# 로깅 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [TEST] $1" | tee -a "$LOG_FILE"
}

# 결과 출력 함수
print_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"
    
    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}✓ $test_name: PASS${NC} $message"
    elif [[ "$result" == "FAIL" ]]; then
        echo -e "${RED}✗ $test_name: FAIL${NC} $message"
    else
        echo -e "${YELLOW}⚠ $test_name: SKIP${NC} $message"
    fi
}

# 환경 변수 확인
test_environment() {
    log "환경 변수 테스트 시작"
    
    local missing_vars=()
    
    [[ -z "${GITHUB_TOKEN:-}" ]] && missing_vars+=("GITHUB_TOKEN")
    [[ -z "${GITHUB_OWNER:-}" ]] && missing_vars+=("GITHUB_OWNER")
    [[ -z "${GITHUB_REPO:-}" ]] && missing_vars+=("GITHUB_REPO")
    
    if [[ ${#missing_vars[@]} -eq 0 ]]; then
        print_result "환경 변수 확인" "PASS"
        return 0
    else
        print_result "환경 변수 확인" "FAIL" "Missing: ${missing_vars[*]}"
        return 1
    fi
}

# 필수 파일 확인
test_files() {
    log "필수 파일 확인 테스트 시작"
    
    local files=(
        "$ROOT_DIR/hooks/scripts/plan-to-issue.sh"
        "$ROOT_DIR/hooks/scripts/todo-to-project.sh"
        "$ROOT_DIR/hooks/utils/github-api.sh"
    )
    
    local missing_files=()
    
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        elif [[ ! -x "$file" ]]; then
            missing_files+=("$file (not executable)")
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        print_result "필수 파일 확인" "PASS"
        return 0
    else
        print_result "필수 파일 확인" "FAIL" "Missing: ${missing_files[*]}"
        return 1
    fi
}

# GitHub API 연결 테스트
test_github_api() {
    log "GitHub API 연결 테스트 시작"
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        print_result "GitHub API 연결" "SKIP" "GITHUB_TOKEN not set"
        return 0
    fi
    
    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO" 2>/dev/null || echo "")
    
    if echo "$response" | grep -q '"full_name"'; then
        print_result "GitHub API 연결" "PASS"
        return 0
    else
        print_result "GitHub API 연결" "FAIL" "API 응답 오류"
        return 1
    fi
}

# Plan to Issue Hook 테스트
test_plan_to_issue_hook() {
    log "Plan to Issue Hook 테스트 시작"
    
    local test_data='{"prompt": "새로운 기능을 구현하는 테스트 계획을 세워보자"}'
    
    local result
    result=$(echo "$test_data" | "$ROOT_DIR/hooks/scripts/plan-to-issue.sh" 2>&1 || echo "ERROR")
    
    if echo "$result" | grep -q '"success": true'; then
        print_result "Plan to Issue Hook" "PASS"
        return 0
    else
        print_result "Plan to Issue Hook" "FAIL" "$result"
        log "Plan to Issue Hook 오류: $result"
        return 1
    fi
}

# Todo to Project Hook 테스트
test_todo_to_project_hook() {
    log "Todo to Project Hook 테스트 시작"
    
    local test_data='{
        "tool_name": "TodoWrite",
        "tool_input": {
            "todos": [
                {
                    "id": "test-1",
                    "content": "테스트 할일 1",
                    "status": "pending",
                    "priority": "high"
                },
                {
                    "id": "test-2", 
                    "content": "테스트 할일 2",
                    "status": "completed",
                    "priority": "medium"
                }
            ]
        }
    }'
    
    local result
    result=$(echo "$test_data" | "$ROOT_DIR/hooks/scripts/todo-to-project.sh" 2>&1 || echo "ERROR")
    
    if echo "$result" | grep -q '"success": true'; then
        print_result "Todo to Project Hook" "PASS"
        return 0
    else
        print_result "Todo to Project Hook" "FAIL" "$result"
        log "Todo to Project Hook 오류: $result"
        return 1
    fi
}

# GitHub API 유틸리티 테스트
test_github_api_utils() {
    log "GitHub API 유틸리티 테스트 시작"
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        print_result "GitHub API 유틸리티" "SKIP" "GITHUB_TOKEN not set"
        return 0
    fi
    
    local result
    result=$("$ROOT_DIR/hooks/utils/github-api.sh" search-issues "is:open" 1 2>&1 || echo "ERROR")
    
    if echo "$result" | grep -q '"total_count"'; then
        print_result "GitHub API 유틸리티" "PASS"
        return 0
    else
        print_result "GitHub API 유틸리티" "FAIL" "$result"
        return 1
    fi
}

# 권한 테스트
test_permissions() {
    log "파일 권한 테스트 시작"
    
    local scripts=(
        "$ROOT_DIR/hooks/scripts/plan-to-issue.sh"
        "$ROOT_DIR/hooks/scripts/todo-to-project.sh" 
        "$ROOT_DIR/hooks/utils/github-api.sh"
    )
    
    local permission_errors=()
    
    for script in "${scripts[@]}"; do
        if [[ ! -x "$script" ]]; then
            permission_errors+=("$script")
        fi
    done
    
    if [[ ${#permission_errors[@]} -eq 0 ]]; then
        print_result "파일 권한" "PASS"
        return 0
    else
        print_result "파일 권한" "FAIL" "Not executable: ${permission_errors[*]}"
        return 1
    fi
}

# 로그 디렉토리 테스트
test_log_directory() {
    log "로그 디렉토리 테스트 시작"
    
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            print_result "로그 디렉토리" "FAIL" "Cannot create $log_dir"
            return 1
        }
    fi
    
    if [[ -w "$log_dir" ]]; then
        print_result "로그 디렉토리" "PASS"
        return 0
    else
        print_result "로그 디렉토리" "FAIL" "Not writable: $log_dir"
        return 1
    fi
}

# 모든 테스트 실행
run_all_tests() {
    echo "GitHub Integration Hooks 테스트 시작"
    echo "======================================"
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0
    
    # 테스트 목록
    local tests=(
        "test_environment"
        "test_files"
        "test_permissions"
        "test_log_directory"
        "test_github_api"
        "test_github_api_utils"
        "test_plan_to_issue_hook"
        "test_todo_to_project_hook"
    )
    
    for test in "${tests[@]}"; do
        ((total_tests++))
        
        if $test; then
            ((passed_tests++))
        else
            case $? in
                0) ((passed_tests++)) ;;
                2) ((skipped_tests++)) ;;
                *) ((failed_tests++)) ;;
            esac
        fi
    done
    
    echo ""
    echo "테스트 결과 요약"
    echo "================"
    echo "총 테스트: $total_tests"
    echo -e "${GREEN}통과: $passed_tests${NC}"
    echo -e "${RED}실패: $failed_tests${NC}"
    echo -e "${YELLOW}건너뜀: $skipped_tests${NC}"
    
    if [[ $failed_tests -eq 0 ]]; then
        echo -e "\n${GREEN}모든 테스트가 성공했습니다!${NC}"
        return 0
    else
        echo -e "\n${RED}일부 테스트가 실패했습니다. 로그를 확인하세요: $LOG_FILE${NC}"
        return 1
    fi
}

# 도움말 표시
show_help() {
    cat << EOF
GitHub Integration Hooks 테스트 스크립트

사용법:
  $0 [command]

명령어:
  all          - 모든 테스트 실행 (기본값)
  env          - 환경 변수 테스트
  files        - 필수 파일 확인
  permissions  - 파일 권한 테스트
  api          - GitHub API 연결 테스트
  utils        - GitHub API 유틸리티 테스트
  plan-hook    - Plan to Issue Hook 테스트
  todo-hook    - Todo to Project Hook 테스트
  help         - 이 도움말 표시

예제:
  $0                    # 모든 테스트 실행
  $0 all               # 모든 테스트 실행
  $0 api               # GitHub API 연결만 테스트
  $0 plan-hook         # Plan to Issue Hook만 테스트
EOF
}

# 메인 로직
main() {
    local command="${1:-all}"
    
    case "$command" in
        "all")
            run_all_tests
            ;;
        "env")
            test_environment
            ;;
        "files")
            test_files
            ;;
        "permissions")
            test_permissions
            ;;
        "api")
            test_github_api
            ;;
        "utils")
            test_github_api_utils
            ;;
        "plan-hook")
            test_plan_to_issue_hook
            ;;
        "todo-hook")
            test_todo_to_project_hook
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo "Unknown command: $command" >&2
            show_help
            exit 1
            ;;
    esac
}

# 실행
main "$@"